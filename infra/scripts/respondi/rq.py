import json,urllib.request,sys
B='https://api.respondi.app/api/';T=open('.tok').read().strip()
def req(m,p,body=None):
    r=urllib.request.Request(B+p,method=m,data=json.dumps(body).encode() if body is not None else None,headers={'Authorization':'Bearer '+T,'Accept':'application/json','Content-Type':'application/json','User-Agent':'Mozilla/5.0'})
    with urllib.request.urlopen(r,timeout=60) as f: return json.loads(f.read().decode('utf-8'))
