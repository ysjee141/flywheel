const A=require('ajv/dist/2020').default,fs=require('fs'),d=process.argv[2];
for(const n of ['task','memory-record','approval','review']){const v=new A({strict:false,allErrors:true}).compile(JSON.parse(fs.readFileSync(`${d}/${n}.schema.json`)));
for(const k of ['valid','invalid']){const r=v(JSON.parse(fs.readFileSync(`${d}/examples/${n}.${k}.json`)));console.log(n,k,r===(k==='valid')?'OK':'FAIL',r?'':v.errors.map(e=>e.instancePath+' '+e.message).slice(0,3))}}
