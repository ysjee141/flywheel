import {JSDOM} from 'jsdom';const w=new JSDOM('').window;globalThis.window=w;globalThis.document=w.document;
const m=(await import('mermaid')).default;import fs from 'fs';
const d=process.argv[2];for(const f of fs.readdirSync(d).filter(x=>x.endsWith('.md')))for(const b of fs.readFileSync(d+'/'+f,'utf8').matchAll(/```mermaid\n([\s\S]*?)```/g)){try{await m.parse(b[1]);console.log('ok',f)}catch(e){console.log('BAD',f,e.message.slice(0,200))}}
