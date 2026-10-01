import json,glob,os,re,urllib.request,unicodedata
from fam import familia
WS={160:'Holding Masters',161:'Diamante',162:'Aurum',3380:'Acelera Holding',574:'Holding Total'}
env={};[env.__setitem__(*l.strip().split('=',1)) for l in open(os.environ['RESPONDI_SUPABASE_ENV'],encoding='utf-8') if '=' in l and not l.startswith('#')]
URL=[v for k,v in env.items() if k.endswith('SUPABASE_URL')][0].strip('"');KEY=env['SUPABASE_SERVICE_ROLE_KEY'].strip('"')
assert 'mbvybujpkwuorhtdzcde' in URL
def rpc(fn,body):
    r=urllib.request.Request(f'{URL}/rest/v1/rpc/{fn}',data=json.dumps(body).encode(),method='POST',headers={'apikey':KEY,'Authorization':'Bearer '+KEY,'Content-Type':'application/json'})
    with urllib.request.urlopen(r,timeout=120) as f: return json.loads(f.read().decode())
def sem_acento(s): return ''.join(c for c in unicodedata.normalize('NFD',s) if unicodedata.category(c)!='Mn').lower()
def chave(tipo,q,fam):
    q=sem_acento(re.sub(r'<[^>]+>|\s+',' ',q or '')).strip()
    soc=('socio' in q) and not re.search(r'aluno|titular|voce vai trazer|quantos socios|comprove|documento',q)
    if re.search(r'voce vai trazer um socio',q): return 'traz_socio'
    if re.search(r'quantos socios',q): return 'qtd_socios'
    p='socio_' if soc else ''
    if tipo=='email' or re.search(r'\be-?mail\b',q): return p+'email'
    if tipo=='cpf' or re.search(r'\bcpf\b',q): return p+'cpf'
    if tipo=='cnpj' or 'cnpj' in q: return 'cnpj'
    if tipo=='phone' or re.search(r'telefone|whats',q): return p+'telefone'
    if re.search(r'cracha',q): return 'cracha'
    if tipo=='name' or re.search(r'nome completo|seu nome|qual o nome',q): return p+'nome'
    if re.search(r'espaco de instrucao',q): return 'espaco'
    if re.search(r'em qual nivel|seu nivel|nivel voce',q): return 'nivel'
    if re.search(r'\bturma\b',q): return 'turma'
    if re.search(r'profiss',q): return 'profissao'
    if re.search(r'qual a area',q): return 'area'
    if re.search(r'sua idade',q): return 'idade'
    if re.search(r'seu sexo',q): return 'sexo'
    if re.search(r'anos voce se formou',q): return 'anos_formado'
    if re.search(r'forma autonoma',q): return 'atuacao'
    if re.search(r'possui equipe',q): return 'equipe'
    if re.search(r'redes sociais como ferramenta',q): return 'redes_sociais'
    if re.search(r'por que voce ingressou',q): return 'objetivo'
    if re.search(r'conhecimento juridico',q): return 'conhecimento_juridico'
    if re.search(r'conhecimento de holding',q): return 'conhecimento_hf'
    if re.search(r'instagram',q) and not re.search(r'seguidores|palestra',q): return 'instagram'
    if 'facebook' in q: return 'facebook'
    if re.search(r'canal no youtube',q): return 'youtube'
    if 'camisa' in q: return 'camisa'
    if re.search(r'razao social',q): return 'razao_social'
    if 'seccional' in q: return 'seccional'
    if re.search(r'familias atendidas',q): return 'familias_12m'
    if re.search(r'patrimonio somado',q): return 'patrimonio_familias'
    if re.search(r'honorarios faturados',q): return 'honorarios_12m'
    if re.search(r'\bcep\b',q): return p+'cep'
    if re.search(r'\bcidade\b',q): return p+'cidade'
    if re.search(r'\bbairro\b',q): return p+'bairro'
    if re.search(r'\bpais\b',q): return p+'pais'
    if re.search(r'complemento',q): return p+'complemento'
    if re.search(r'^(informe o )?numero$',q): return p+'numero'
    if re.search(r'logradouro|endereco completo|endereco',q): return p+'endereco'
    if re.search(r'estado \(uf\)|seu estado|^estado$|informe o estado',q): return p+'uf'
    return None
def val(v):
    if v is None: return ''
    if isinstance(v,list): return ', '.join(val(x) for x in v)
    if isinstance(v,dict): return v.get('url') or v.get('name') or json.dumps(v,ensure_ascii=False)
    s=str(v).strip()
    if s.startswith('[') and s.endswith(']'):
        try:
            l=json.loads(s)
            if isinstance(l,list): return ', '.join(val(x) for x in l)
        except Exception: pass
    return s
UFS={'acre':'AC','alagoas':'AL','amapa':'AP','amazonas':'AM','bahia':'BA','ceara':'CE','distrito federal':'DF','espirito santo':'ES','goias':'GO','maranhao':'MA','mato grosso':'MT','mato grosso do sul':'MS','minas gerais':'MG','para':'PA','paraiba':'PB','parana':'PR','pernambuco':'PE','piaui':'PI','rio de janeiro':'RJ','rio grande do norte':'RN','rio grande do sul':'RS','rondonia':'RO','roraima':'RR','santa catarina':'SC','sao paulo':'SP','sergipe':'SE','tocantins':'TO'}
def uf(s):
    t=sem_acento(s or '').strip()
    if t.upper() in UFS.values(): return t.upper()
    return UFS.get(t)
def nivel(s):
    t=re.sub(r'\s+',' ',sem_acento(s or '').split(' - ')[0]).strip()
    for k,c in [('diamante vermelho','diamante_vermelho'),('diamante','diamante'),('platina','platina'),('ouro','ouro'),('profissional','profissional'),('em formacao','em_formacao'),('pessoal','pessoal'),('iniciante','iniciante')]:
        if 'nivel '+k in t or t.startswith(k): return c
def espaco(s):
    t=sem_acento(s or '')
    for k,c in [('nao faco parte',None),('implementa','holding_masters_implementacao'),('holding masters','holding_masters'),('aurum','aurum'),('platina','platina'),('mastermind','mastermind_diamante'),('vermelho','diamante_vermelho')]:
        if k in t: return c
def cpf_ok(c):
    if len(c)!=11 or c==c[0]*11: return False
    for n in (9,10):
        s=sum(int(c[i])*(n+1-i) for i in range(n));d=(s*10)%11%10
        if d!=int(c[n]): return False
    return True
def dig(s): return re.sub(r'\D','',s or '')
forms=[];resps=[]
for fn in glob.glob('raw/*.json'):
    d=json.load(open(fn,encoding='utf-8'));f=d['form'];fam=familia(f['name'])
    if not fam: continue
    m=re.search(r'\[(T\d{2})(?:\.\d)?\]|\b(A\d{1,2})\b',f['name']);tc=(m.group(1) or m.group(2)) if m else None
    flds={x['slug']:x for x in d['fields']}
    forms.append({'slug':f['slug'],'form_id':f['id'],'workspace':WS[f['team']],'nome':f['name'],'familia':fam,'turma_codigo':tc,'criado_em':f['created'] or None,'n_respostas':len(d['respondents']),
                  'campos':[{'slug':x['slug'],'tipo':x['type'],'pergunta':re.sub(r'<[^>]+>','',x['q'])} for x in d['fields'] if x['type'] not in('welcome','message','thankyou','statement','end')]})
    for r in d['respondents']:
        dados={};arr=[]
        for a in r['answers']:
            fl=flds.get(a['field_slug'],{});t=a.get('field_type') or fl.get('type');q=a.get('field_title') or fl.get('q','')
            v=val(a.get('value'))
            if not v or t in('welcome','message','thankyou','statement'): continue
            arr.append({'p':re.sub(r'<[^>]+>','',q)[:300],'v':v[:4000]})
            k=chave(t,q,fam)
            if k and fam=='socios' and k in ('cep','cidade','bairro','pais','complemento','numero','endereco','uf'): k='socio_'+k
            if k and k not in dados: dados[k]=v[:1000]
        if not arr: continue
        if 'uf' in dados and uf(dados['uf']): dados['uf_sigla']=uf(dados['uf'])
        if 'socio_uf' in dados and uf(dados['socio_uf']): dados['socio_uf_sigla']=uf(dados['socio_uf'])
        if 'nivel' in dados and nivel(dados['nivel']): dados['nivel_codigo']=nivel(dados['nivel'])
        if 'espaco' in dados and espaco(dados['espaco']): dados['espaco_codigo']=espaco(dados['espaco'])
        tm=re.fullmatch(r'\s*(T\d{1,2}(?:\.2)?|A\d{1,2})\s*',dados.get('turma') or '')
        if tm: dados['turma_codigo']=tm.group(1)
        elif tc and fam in('questionario_inicial','socios'): dados['turma_codigo']=tc
        for k in ('cpf','socio_cpf'):
            if k in dados: dados[k+'_valido']=cpf_ok(dig(dados[k]))
        em=(dados.get('email') or '').strip().lower()
        if fam=='socios' and dados.get('socio_email') and not em: em=''
        cpf=dig(dados.get('cpf'));tel=dig(dados.get('telefone'))
        resps.append({'uuid':r['uuid'],'form_slug':f['slug'],'respondido_em':r.get('updated_at') or r.get('created_at'),'email':em,'cpf':cpf if cpf_ok(cpf) else '','telefone':tel if len(tel)>=10 else '','dados':dados,'respostas':arr})
print('forms',len(forms),'resps',len(resps))
import sys
if '--enviar' in sys.argv:
    print(rpc('fn_respondi_carga',{'p_formularios':forms,'p_respostas':[]}))
    tot=0
    for i in range(0,len(resps),300):
        tot+=rpc('fn_respondi_carga',{'p_formularios':[],'p_respostas':resps[i:i+300]})['respostas']
    print('respostas enviadas',tot)
else:
    import collections;c=collections.Counter(k for r in resps for k in r['dados']);print(c.most_common(60))
