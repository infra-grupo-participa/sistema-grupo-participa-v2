import json,os,time
from concurrent.futures import ThreadPoolExecutor
from rq import req
from fam import familia
inv=json.load(open('inventario.json',encoding='utf-8'))
def get(f):
    fn=f"raw/{f['slug']}.json"
    if os.path.exists(fn): return
    allr=[];p=1
    while True:
        d=None
        for k in range(5):
            try: d=req('GET',f"answers/form/{f['slug']}?page={p}&completed=1")['data'];break
            except Exception as e: time.sleep(2*(k+1))
        if d is None: print('FALHA',f['slug'],p,flush=True);return
        rs=d.get('respondents') or []
        if not rs: break
        allr+=rs;p+=1
    json.dump({'form':{k:f[k] for k in('team','id','slug','name','created','n')},'familia':familia(f['name']),'fields':f['fields'],'respondents':allr},open(fn,'w',encoding='utf-8'),ensure_ascii=False)
    print(f['team'],f['n'],len(allr),flush=True)
for tid in [160,161,162,3380,574]:
    req('PUT',f'team/switch/{tid}')
    fs=[x for x in inv if x['team']==tid and (x['n'] or 0)>0 and not x['draft_of'] and familia(x['name'])]
    with ThreadPoolExecutor(4) as ex: list(ex.map(get,fs))
req('PUT','team/switch/160');print('FIM')
