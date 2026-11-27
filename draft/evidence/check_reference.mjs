import {spawn} from 'node:child_process';import fs from 'fs';import os from 'os';import path from 'path';import net from 'net';import crypto from 'crypto';
import {canon,challenge,payloadHash,verify} from './reference/approval.mjs';
const here=import.meta.dirname,T=fs.mkdtempSync(os.tmpdir()+'/axh-'),W=T+'/w';fs.mkdirSync(W+'/.git',{recursive:true});
fs.symlinkSync('/etc',W+'/esc');fs.symlinkSync('/nope/x',W+'/dang');fs.symlinkSync(W+'/.git',W+'/g');fs.writeFileSync(W+'/a.ts','');
const ack=net.createServer(s=>s.on('data',()=>s.write('ack'))).listen(T+'/ok.sock'),nack=net.createServer(s=>s.on('data',()=>s.write('no'))).listen(T+'/no.sock'),hang=net.createServer(s=>{s.on('error',()=>{})}).listen(T+'/hang.sock');
let bad=0;const chk=(n,g,w)=>{if(g!==w){bad++;console.log('FAIL',n,g,w)}};let cnt=0;
const run=(inp,sock='ok',env={})=>new Promise(r=>{const c=spawn(process.execPath,[here+'/reference/hook-entry.mjs'],{env:{AX_WORK:W,AX_SOCK:`${T}/${sock}.sock`,...env}});c.stdin.on('error',()=>{});c.stdout.resume();c.stderr.resume();c.on('close',x=>r(x));c.stdin.end(inp)});
const J=(t,i)=>JSON.stringify({hook_event_name:'PreToolUse',tool_name:t,tool_use_id:'u',cwd:W,tool_input:i});const w=p=>J('Write',{file_path:p});
for(const [n,i,x,s,e] of [['ok',w(W+'/a.ts'),0],['new nested',w('x/y/z.ts'),0],['outside',w('/etc/passwd'),2],['dotdot',w('../q'),2],['symlink',w('esc/p'),2],['dangling',w('dang'),2],['link to .git',w('g/config'),2],['.git',w('.git/config'),2],['case .GIT',w('.GIT/config'),2],['settings',w('.claude/settings.json'),2],['wf',w('.github/workflows/a.yml'),2],['env read',J('Read',{file_path:'.env.local'}),2],['..foo ok-ish',w('..foo'),2],
['bad json','{bad',2],['empty','',2],['array','[]',2],['null','null',2],['no path',J('Write',{}),2],['unknown tool',J('WebFetch',{}),2],['big','x'.repeat(1200000),2],['nack',w('a.ts'),2,'no'],['hang',w('a.ts'),2,'hang'],['no sock',w('a.ts'),2,'zz'],['no env',w('a.ts'),2,'ok',{AX_WORK:''}],['nul',w('a\0b'),2]]){cnt++;chk(n,await run(i,s,e),x)}
console.log('hook cases',cnt,'bad',bad);
const k=crypto.generateKeyPairSync('ec',{namedCurve:'P-256'}),cred={publicKey:k.publicKey},cfg={origin:'http://localhost:7777',rpId:'localhost'};
const P={schema:1,action:'ads.spend',target:'t',params:{b:1,a:'가'},nonce:'n'.repeat(22),expires_at:1000,max_spend_micro_usd:5};
const sign=(p,o={})=>{const cd=Buffer.from(JSON.stringify({type:o.type??'webauthn.get',challenge:challenge(p).toString('base64url'),origin:o.origin??cfg.origin}));const d=Buffer.concat([crypto.createHash('sha256').update(o.rp??cfg.rpId).digest(),Buffer.from([o.f??5,0,0,0,0])]);return{clientDataJSON:cd,authenticatorData:d,signature:crypto.sign('sha256',Buffer.concat([d,crypto.createHash('sha256').update(cd).digest()]),k.privateKey)}};
const a=sign(P);let b0=bad,m=0;const v=(n,g,x)=>{m++;chk(n,g,x)};
v('ok',verify(P,a,cred,cfg,999),'ok');v('AP-01',payloadHash({...P,params:{a:'가',b:1}}).equals(payloadHash(P)),true);
for(const q of [{target:'u'},{max_spend_micro_usd:6},{nonce:'m'.repeat(22)},{params:{a:'가',b:2}},{expires_at:9999}])v('AP-02',verify({...P,...q},a,cred,cfg,999),'challenge');
v('AP-03 o',verify(P,sign(P,{origin:'http://evil'}),cred,cfg,1),'origin');v('AP-03 rp',verify(P,sign(P,{rp:'evil'}),cred,cfg,1),'rpid');v('AP-04',verify(P,sign(P,{f:1}),cred,cfg,1),'user-verification');v('AP-05',verify(P,a,cred,cfg,1000),'expired');v('revoked',verify(P,a,{...cred,revoked:1},cfg,1),'revoked');
v('type',verify(P,sign(P,{type:'webauthn.create'}),cred,cfg,1),'type');v('key',verify(P,a,{publicKey:crypto.generateKeyPairSync('ec',{namedCurve:'P-256'}).publicKey},cfg,1),'signature');
const t={...a,authenticatorData:Buffer.from(a.authenticatorData)};t.authenticatorData[36]=1;v('tamper',verify(P,t,cred,cfg,1),'signature');
for(const x of [1.5,2**60,undefined,'\ud800']){m++;try{canon({x});chk('canon',1,0)}catch{}}
console.log('approval cases',m,'bad',bad-b0);process.exit(bad?1:0);
