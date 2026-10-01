from rq import req;import json
TEAMS=[160,161,162,472,574,2548,2587,3380];out=[]
for tid in TEAMS:
    req('PUT',f'team/switch/{tid}');p=1
    while True:
        d=req('GET',f'form?page={p}')
        for f in d['data']:
            out.append({'team':tid,'id':f['id'],'slug':f['slug'],'name':f['name'],'created':(f.get('created_at') or '')[:10],'n':f.get('respondents_count'),'draft_of':f.get('draft_of'),
              'fields':[{'slug':x.get('slug'),'type':x.get('type'),'q':(x.get('value') or '')[:200]} for x in f.get('fields',[])]})
        if not d.get('next_page_url'): break
        p+=1
req('PUT','team/switch/160')
json.dump(out,open('inventario.json','w',encoding='utf-8'),ensure_ascii=False)
tn={160:'HM',161:'DIA',162:'AUR',472:'CUR',574:'HT',2548:'LPSG-HT',2587:'LPSG-HSI',3380:'ACE'}
tot=0
for o in sorted(out,key=lambda o:(o['team'],-(o['n'] or 0))):
    if (o['n'] or 0)>=5 and not o['draft_of']:
        tot+=o['n'];print(tn[o['team']],o['n'],o['created'][:7],o['name'][:70],sep='|')
print('total respostas',tot,'forms',len(out))
