"""기업 기능 모듈 예제와 company.db DDL의 계약 시험."""
import json,pathlib,sqlite3
d=pathlib.Path(__file__).resolve().parent.parent/'schemas'
M=json.loads((d/'examples/business-modules.json').read_text());n=0
def ok(c,t):
    global n
    assert c,t
    n+=1
ok(len(M)==12 and len({m['id'] for m in M})==12,'12 modules')
for m in M:
    ok(not set(m['makers'])&set(m['reviewers']),m['id']+' self review')
    ok(all(p['source'] in m['records'] for p in m['panels']),m['id']+' panel source')
appr=json.loads((d/'approval.schema.json').read_text())['properties']['action']['enum']
ok(all(set(m['approvals'])<=set(appr) for m in M),'approval actions exist')
db=sqlite3.connect(':memory:');db.executescript((d/'company.sql').read_text())
def rec(id,ver=1,sup=None,scope='company',svc=None,verb='INSERT',mod='brand'):
    db.execute(f"{verb} INTO company_record VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",(id,mod,'brand_kit',scope,svc,ver,sup,'confidential','actual','{}',None,'founder',1))
def bad(f,t):
    try:f()
    except sqlite3.Error:ok(True,t);return
    ok(False,t)
rec('r1');rec('r2',2,'r1');ok(True,'chain')
bad(lambda:rec('r3',2,'r1'),'fork');bad(lambda:rec('r3',4,'r2'),'gap');bad(lambda:rec('r3',3,'r2',mod='legal'),'cross module')
bad(lambda:rec('r3',3,'r2','service','svc_a'),'cross scope');bad(lambda:rec('r1',verb='INSERT OR REPLACE'),'replace id')
bad(lambda:rec('r9',2,'r1',verb='INSERT OR REPLACE'),'replace chain');bad(lambda:rec('x',scope='service'),'service needs id')
for q in("UPDATE company_record SET actor='a'","UPDATE OR REPLACE company_record SET id='r1' WHERE id='r2'","DELETE FROM company_record"):bad(lambda:db.execute(q),q)
ins=lambda id='d1',actor='founder',opt='["a","b"]',verb='INSERT':db.execute(f"{verb} INTO decision VALUES(?,?,?,?,?,?,?,?,?,?,?)",(id,'portfolio',None,'q',opt,'a','why','{"m":1}',None,actor,1))
ins();bad(lambda:ins('d2','A01'),'agent decision');bad(lambda:ins('d2',opt='["a"]'),'one option');bad(lambda:ins(verb='INSERT OR REPLACE'),'replace decision')
bad(lambda:db.execute("UPDATE decision SET snapshot_json='{}'"),'snapshot fixed');bad(lambda:db.execute("DELETE FROM decision"),'delete decision')
t=lambda id,w,c,a:db.execute("INSERT INTO founder_time VALUES(?,?,?,?,?,?,?,?)",(id,None,'business',w,30,20,c,a))
t('t1','2026-11-30',45,1);t('t2','2026-11-30',None,None)
ok(db.execute("SELECT minutes FROM founder_week").fetchall()==[(45,)],'only confirmed time counts')
bad(lambda:t('t3','2026-12-01',1,1),'not monday');bad(lambda:t('t3','2026-11-30',1,None),'confirm time')
print('business ok',n)
