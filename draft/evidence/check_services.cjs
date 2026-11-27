// ajv 8이 설치된 폴더에서: node check_services.cjs <schemas 경로>. 팩 필수 능력 검사는 코어 스키마와 분리한다.
const A=require('ajv/dist/2020').default,fs=require('fs'),d=process.argv[2],J=f=>JSON.parse(fs.readFileSync(d+'/'+f));
const v=new A({strict:false,allErrors:true}).compile(J('service.schema.json'));const common=['config','telemetry','health','backup'];
const check=(m,packs)=>{if(!v(m))return'schema';const p=packs[m.pack.id];if(!p)return'pack';if(p.required.some(c=>!m.capabilities.includes(c)))return'required';
 if(m.capabilities.some(c=>![...common,...p.required,...p.optional].includes(c)))return'unknown';
 if(Object.values(m.environments).some(e=>!e.deployer_ref.startsWith('executor:'+m.id+'/')))return'deployer';return'ok'};
const packs=J('examples/packs.json');let bad=0;const t=(n,g,w)=>{if(g!==w){bad++;console.log('FAIL',n,g,w)}};let n=0;
for(const k of'abcd'){const m=J(`examples/service.type-${k}.json`);t('ok '+k,check(m,packs),'ok');n++;
 for(const c of packs['type-'+k].required){const x=structuredClone(m);x.capabilities=x.capabilities.filter(y=>y!==c);const r=check(x,packs);t(`missing ${k}/${c}`,r==='ok',false);n++}
 for(const c of common){const x=structuredClone(m);x.capabilities=x.capabilities.filter(y=>y!==c);t(`common ${k}/${c}`,check(x,packs),'schema');n++}
 const x=structuredClone(m);x.environments.preview.deployer_ref='executor:svc_other/preview';t('cross deploy '+k,check(x,packs),'deployer');n++}
const e=J('examples/service.type-b.json');e.pack.id='type-e';t('no pack e',check(e,packs),'pack');t('fifth pack',check(e,{...packs,'type-e':{required:['abuse-control'],optional:[]}}),'ok');
const pii=J('examples/service.type-b.json');pii.data.classification='personal';t('pii needs privacy',check(pii,packs),'schema');n+=3;
console.log('service cases',n,'bad',bad);process.exit(bad?1:0);
