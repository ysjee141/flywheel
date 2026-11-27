"""설계 알고리즘 검증: 예산, 임대, 승인 소비, 볼트 교체 중 강제 종료. 제품 코드가 아니다."""
import sqlite3,multiprocessing as mp,tempfile,os,pathlib,time,signal,random,sys
DDL=(pathlib.Path(__file__).resolve().parent.parent/'schemas/memory.sql').read_text()
def con(p):
    c=sqlite3.connect(p,timeout=30,isolation_level=None);c.execute('pragma foreign_keys=on');return c
def setup():
    p=os.path.join(tempfile.mkdtemp(),'s.db');c=con(p);c.execute('pragma journal_mode=wal');c.executescript(DDL)
    c.execute("insert into project values('p','p','u',1)")
    for i in range(50):c.execute("insert into task(id,project_id,state,risk,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values(?,'p','draft','R1','g','[]',1000,1,1)",(f't{i}',))
    return p
RESERVE="""insert into budget_entry(id,task_id,call_id,kind,amount_micro_usd,at)
select :c,:t,:c,'reserve',:a,0 where
 (select coalesce(sum(case
    when r.kind='settle' then r.amount_micro_usd
    when r.kind='reserve' and not exists(select 1 from budget_entry x where x.call_id=r.call_id and x.kind in('settle','release')) then r.amount_micro_usd
    else 0 end),0) from budget_entry r where r.task_id=:t) + :a
 <= (select budget_micro_usd from task where id=:t)"""
def res(a):
    p,i=a;c=con(p);c.execute('begin immediate');n=c.execute(RESERVE,dict(c=f'c{i}',t='t0',a=100)).rowcount;c.execute('commit');return n
ACQ1="insert into fence_counter values(:r,1) on conflict(resource) do update set value=value+1 where not exists(select 1 from lease where resource=:r and expires_at>:n)"
ACQ2="insert into lease(resource,task_id,fence,expires_at) select :r,:t,value,:n+60000 from fence_counter where resource=:r on conflict(resource) do update set task_id=excluded.task_id,fence=excluded.fence,expires_at=excluded.expires_at where lease.expires_at<=:n"
def acquire(c,r,t,n):
    c.execute('begin immediate');k=c.execute(ACQ1,dict(r=r,n=n)).rowcount
    if k: c.execute(ACQ2,dict(r=r,t=t,n=n))
    f=c.execute('select fence from lease where resource=?',(r,)).fetchone()[0] if k else None
    c.execute('commit');return f
def acq(a):
    p,i=a;return acquire(con(p),'merge:p',f't{i}',1000)
def consume(a):
    p,i=a;c=con(p);return c.execute("update approval set status='consumed',consumed_at=5 where id='a' and status='approved' and expires_at>5").rowcount
def swap(root,p,i,parent):
    vs=f'v{i}';d=root/'versions'/vs;d.mkdir(parents=True);(d/'_index.md').write_text('x');fd=os.open(d,os.O_RDONLY);os.fsync(fd)
    time.sleep(random.random()*.002);l=root/f'.tmp{i}';os.symlink(f'versions/{vs}',l);time.sleep(random.random()*.002);c=con(p)
    c.execute('begin immediate');cur=c.execute("select id from vault_version where status='current'").fetchone()
    if (cur and cur[0])!=parent: c.execute('rollback');return
    c.execute("update vault_version set status='archived' where status='current'")
    c.execute("insert into vault_version values(?,?,'current','h',null,1)",(vs,parent));time.sleep(random.random()*.002)
    c.execute('commit');time.sleep(random.random()*.002);os.replace(l,root/'current')
def recover(root,p):
    r=con(p).execute("select id from vault_version where status='current'").fetchone()
    if not r: return None
    t=root/'.rec'; t.unlink(missing_ok=True);os.symlink(f'versions/{r[0]}',t);os.replace(t,root/'current')
    assert (root/'current'/'_index.md').read_text()=='x';return r[0]
if __name__=='__main__':
    p=setup()
    with mp.Pool(16) as pool:
        print('O-05 reserve granted (expect 10):',sum(pool.map(res,[(p,i) for i in range(100)],chunksize=1)))
        print('lease winners (expect 1):',sum(x is not None for x in pool.map(acq,[(p,i) for i in range(50)],chunksize=1)))
        c=con(p);f1=c.execute('select fence from lease').fetchone()[0];f2=acquire(c,'merge:p','t9',10**9);print('O-04 fence increases:',f2>f1)
        c.execute("insert into approval(id,task_id,action,payload_hash,nonce,status,requested_at,expires_at) values('a','t1','x',?,'n','pending',1,9)",('a'*64,));c.execute("update approval set status='approved',decided_at=2,signature=x'01'")
        print('P-04 consume winners (expect 1):',sum(pool.map(consume,[(p,i) for i in range(100)],chunksize=1)))
    root=pathlib.Path(tempfile.mkdtemp());par=None;com=0
    for i in range(100):
        q=mp.Process(target=swap,args=(root,p,i,par));q.start();time.sleep(random.random()*.02)
        if q.is_alive():os.kill(q.pid,signal.SIGKILL)
        q.join();new=recover(root,p);com+=new!=par;par=new
    print('M-04 100 kills, committed',com,'integrity',con(p).execute('pragma integrity_check').fetchone()[0])
