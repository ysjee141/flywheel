import re,pathlib,sys
d=pathlib.Path(__file__).resolve().parent.parent
defs={};refs=[]
for f in sorted(x for x in d.rglob('*.md') if x.parent.name!='evidence'):
    s=f.read_text()
    for t in re.findall(r'\]\(([^)#]+)\)',s):
        if not t.startswith('http') and not (f.parent/t).exists(): print('LINK',f.name,t)
    code=False
    for i,l in enumerate(s.splitlines(),1):
        if l.startswith('```'): code=not code
        if code: continue
        m=re.match(r'^(?:- |\| )([A-Z]{1,3}\d?-\d+)(?::| \|)',l)
        if m:
            if m[1] in defs: print('DUP',m[1],f.name,i,defs[m[1]])
            defs[m[1]]=f'{f.name}:{i}'
        for r in re.findall(r'\b(?:NFR|[BCFLMOPSTHQV]|HC|BH|SB|AP|GH|W[0-3])-\d+\b',l): refs.append((r,f.name,i))
        for sent in re.split(r'(?<=다\.)\s',re.sub(r'^[\s\-|#\d.]+','',l)):
            if '|' not in sent and len(sent.split())>25: print('LONG',f.name,i,len(sent.split()))
        # section refs
        for fn,sec in re.findall(r'\[(0\d|10)\]\([^)]*\) §(\d+)',l):
            t=next(d.glob(fn+'-*.md')).read_text()
            if not re.search(rf'^## {sec}\.',t,re.M): print('SEC',f.name,i,fn,sec)
for r,f,i in refs:
    if r not in defs: print('UNDEF',r,f,i)
print('ids',len(defs))
