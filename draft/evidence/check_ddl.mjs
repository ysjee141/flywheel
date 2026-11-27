import {DatabaseSync as D} from 'node:sqlite'; import fs from 'fs';
const db=new D(':memory:'); console.log(db.prepare('select sqlite_version() v').get());
db.exec(fs.readFileSync(process.argv[2],'utf8')); console.log('ddl ok');
const ok=(n,s)=>{try{db.exec(s);console.log('OK   ',n)}catch(e){console.log('FAIL ',n,e.message)}};
const no=(n,s)=>{try{db.exec(s);console.log('FAIL(accepted)',n)}catch(e){console.log('REJ  ',n,'|',e.message)}};
ok('project',"insert into project values('p','p','u',1)");
const T=(id,t)=>`insert into task(id,project_id,state,risk,tainted,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values('${id}','p','draft','R1',${t},'g','[]',1,1,1)`;
ok('t1',T('t1',0));ok('t2',T('t2',0));ok('tx',T('tx',1));
const M=(id,sc,tr,st,h,p="'p'")=>`insert into memory(id,project_id,scope,kind,status,trust,sensitivity,title,body,content_hash,source_json,created_at,updated_at) values('${id}',${p},'${sc}','lesson','${st}','${tr}','internal','결제 웹훅 멱등성','중복결제를 막는다','${h}','{}',1,1)`;
ok('mem',M('m1','project','agent','candidate','h1'));
no('M-01 external active',M('m2','project','external','active','h2'));
no('global agent active',M('m3','global','agent','active','h3','null'));
no('dedupe',M('m4','project','agent','candidate','h1'));
const E=(id,t,c,w,v)=>`insert into memory_evidence values('${id}','m1','${t}','p','${c}','success',${w},'${v}','ci:1',1)`;
ok('ev',E('e1','t1','c1',1.0,'ci'));no('M-02 same commit',E('e2','t2','c1',1.0,'ci'));
no('M-03 taint',E('e3','tx','c2',1.0,'ci'));no('weight mismatch',E('e4','t2','c3',1.0,'local_test'));
console.log('fts',db.prepare("select count(*) n from memory_fts where memory_fts match '멱등성'").get());
ok('appr',`insert into approval(id,task_id,action,payload_hash,nonce,status,requested_at,expires_at) values('a','t1','x','${'a'.repeat(64)}','n','pending',1,2)`);
no('consume pending',"update approval set status='consumed',consumed_at=1 where id='a'");
no('tamper hash',"update approval set payload_hash='b' where id='a'");
no('approve without sig',"update approval set status='approved',decided_at=1 where id='a'");
ok('approve',"update approval set status='approved',decided_at=1,signature=x'01' where id='a'");
ok('consume',"update approval set status='consumed',consumed_at=2 where id='a'");
no('replay',"update approval set status='consumed' where id='a'");
no('event upd',"insert into event(type,actor,idempotency_key,payload_json,prev_hash,hash,at) values('t','a','k','{}','','h',1);update event set type='z'");
no('blocked without resume',"update task set state='blocked' where id='t1'");
// CHECK-null pitfalls
no("taint clear","update task set tainted=0 where id='tx'");no("external candidate",M("m9","project","external","candidate","h9"));db.exec("vacuum");console.log("fts after vacuum",db.prepare("select m.title from memory m join memory_fts f on f.rowid=m.rid where memory_fts match '멱등성'").get());
const sc=(s,f)=>((s+.5)/(s+f+1)).toFixed(3);console.log([sc(2,0),sc(3,0),sc(3,1),sc(8,1),sc(3,0)]);
const S=['draft','ready','running','verifying','reviewing','awaiting_approval','merging','done','blocked','failed','cancelled'];
const allow=new Set(db.prepare('select from_state||\'>\'||to_state k from task_transition').all().map(r=>r.k));let bad=0,acc=0;
const ins=db.prepare("insert into task(id,project_id,state,resume_state,risk,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values('q','p',?,?,'R1','g','[]',1,1,1)");
for(const a of S)for(const b of S){if(a===b)continue;
 db.exec('drop trigger if exists task_starts_draft');
 const rs=a==='blocked'?(['ready','verifying','reviewing','awaiting_approval'].includes(b)?b:'ready'):null;ins.run(a,rs);let r=true;
 try{db.prepare("update task set state=?,resume_state=? where id='q'").run(b,b==='blocked'?'ready':null)}catch{r=false}
 if(r)acc++; if(r!==allow.has(a+'>'+b)){bad++;console.log('MISMATCH',a,b,r)} db.exec("delete from task where id='q'")}
console.log('O-01 pairs',S.length*(S.length-1),'accepted',acc,'mismatch',bad);
no('risk down',"update task set risk='R0' where id='t1'");
db.exec("update task set tainted=1 where id='t1'");console.log('eligible after taint',db.prepare('select count(*) n from eligible_evidence').get().n,'raw',db.prepare('select count(*) n from memory_evidence').get().n);
ins.run('blocked','reviewing');no('resume elsewhere',"update task set state='ready',resume_state=null where id='q'");

{const t=(id,par,x)=>db.prepare("insert into task(id,project_id,parent_id,state,risk,tainted,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values(?,'p',?,'draft','R1',?,'g','[]',1,1,1)").run(id,par,x);
 no('child clean of tainted',"insert into task(id,project_id,parent_id,state,risk,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values('zz','p','tx','draft','R1','g','[]',1,1,1)");
 t('g0',null,0);t('g1','g0',0);t('g2','g1',0);db.exec("update task set tainted=1 where id='g0'");
 console.log('grandchild tainted',db.prepare("select tainted from task where id='g2'").get().tainted===1?'OK':'FAIL');
 no('reparent',"update task set parent_id=null where id='g2'");}
{// REPLACE 우회
 const tryReplace=(n,s)=>{try{db.exec(s);console.log('FAIL(accepted)',n)}catch(e){console.log('REJ  ',n,'|',e.message)}};
 try{db.exec("insert into event(type,actor,idempotency_key,payload_json,prev_hash,hash,at) values('t','a','k9','{}','','h9',1)")}catch{}
 tryReplace('REPLACE event',"insert or replace into event(seq,type,actor,idempotency_key,payload_json,prev_hash,hash,at) select seq,'FORGED','a',idempotency_key,'{}','',hash,1 from event limit 1");
 tryReplace('REPLACE consumed approval',`insert or replace into approval(id,task_id,action,payload_hash,nonce,status,requested_at,expires_at) values('a','t2','y','${'c'.repeat(64)}','n','pending',1,2)`);
 tryReplace('DELETE approval',"delete from approval where id='a'");
 tryReplace('insert pre-approved',`insert into approval(id,task_id,action,payload_hash,nonce,status,requested_at,expires_at,decided_at,signature) values('b','t2','y','${'c'.repeat(64)}','n2','approved',1,2,1,x'01')`);
 tryReplace('taint via REPLACE',"insert or replace into task(id,project_id,state,risk,tainted,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values('g2','p','draft','R0',0,'g','[]',1,1,1)");}
{const b=(i,c,k)=>`insert into budget_entry values('${i}','t2','${c}','${k}',1,null,1)`;
 no('settle without reserve',b('b1','k','settle'));ok('reserve',b('b2','k','reserve'));ok('settle',b('b3','k','settle'));no('release after settle',b('b4','k','release'));no('budget update',"update budget_entry set amount_micro_usd=0");
 ok('cand',M('mp','project','agent','candidate','hp'));no('insert active agent',M('mq','project','agent','active','hq'));no('promote no evidence',"update memory set status='active' where id='mp'");
 for(const[i,v,w,d]of[[1,'ci',1,0],[2,'ci',1,0],[3,'local_test',.5,86400000]]){db.exec(`insert into task(id,project_id,state,risk,goal,acceptance_json,budget_micro_usd,created_at,updated_at) values('pe${i}','p','draft','R1','g','[]',1,1,1)`);db.exec(`insert into memory_evidence values('pe${i}','mp','pe${i}','p','pc${i}','success',${w},'${v}','ci:1',${d})`)}
 no('raise trust',"update memory set trust='founder' where id='mp'");ok('promote with evidence',"update memory set status='active' where id='mp'");
 ok('demote',"update memory set status='retired' where id='mp'");no('revive retired',"update memory set status='active' where id='mp'");}

{const SS=['discover','define','build','release','operate','retire','archived'];const al=new Set(db.prepare("select from_state||'>'||to_state k from service_transition").all().map(r=>r.k));let bad=0,n=0;
 db.exec('drop trigger service_starts_discover; drop trigger service_no_delete; drop trigger service_gate_no_delete');
 for(const a of SS)for(const b of SS){if(a===b)continue;n++;
  db.prepare("insert into service(id,name,project_id,state,pack_id,pack_version,manifest_hash,created_at,updated_at) values('sv','sv','p',?,'type-e','1.0.0','h',1,1)").run(a);
  let r=true;try{db.prepare("insert into service_gate values('sv',1,?,?,'[\"e\"]','founder',1)").run(a,b);db.prepare("update service set state=?,version=2 where id='sv'").run(b)}catch{r=false}
  if(r!==al.has(a+'>'+b)){bad++;console.log('MISMATCH svc',a,b,r)} db.exec("delete from service_gate; delete from service where id='sv'")}
 console.log('L-03 pairs',n,'mismatch',bad);
 db.exec("insert into service(id,name,state,created_at,updated_at) values('sv','sv','discover',1,1)");
 no('advance without gate',"update service set state='define',version=2 where id='sv'");
 no('gate without evidence',"insert into service_gate values('sv',1,'discover','define','[]','f',1)");
 ok('gate',"insert into service_gate values('sv',1,'discover','define','[\"prd\"]','f',1)");ok('advance',"update service set state='define',version=2 where id='sv'");
 no('reuse gate',"update service set state='archived',version=3 where id='sv'");
 ok('gate2',"insert into service_gate values('sv',2,'define','build','[\"m\"]','f',1)");no('build without manifest',"update service set state='build',version=3 where id='sv'");
 no('version skip',"update service set version=9 where id='sv'");}
