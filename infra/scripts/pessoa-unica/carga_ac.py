#!/usr/bin/env python3
"""Carga do ActiveCampaign completo para a pessoa única (migration 20261014170000).

Fases (cada uma retoma de onde parou, pelo cursor gravado em pessoas.carga_execucao):
  catalogo  listas, tags e campos do AC -> pessoas.ac_catalogo
  estagio   contatos (com listas, tags e campos) -> pessoas.ac_contato, em lotes de --lote contatos (padrão 1.000)
  pessoas   pessoas.ac_contato pendente -> pessoas.pessoas / identificadores / eventos, em lotes de --lote

Uso:
  caffeinate -i python3 carga_ac.py --rodar tudo            # catalogo + estagio + pessoas (noite)
  python3 carga_ac.py --rodar estagio --max-lotes 5          # só 5 lotes, para conferir
  python3 carga_ac.py --ensaio 300                           # amostra real (até 500) por pessoas.carga_ensaio($1): roda
                                                              # estágio e pessoas e DESFAZ tudo (exige a 170000 aplicada)
  python3 carga_ac.py --status                               # execuções e contagens

Segurança e regras (Manual de banco; censo-capacidade-ac.md):
  - Uma conexão por vez (Management API do Supabase, uma chamada SQL por lote). Nunca em paralelo.
  - Pausa entre páginas do AC (0,5 s) e entre lotes no banco (2 s).
  - Antes de cada lote: chave pessoas.carga_chave ligada? disco usado <= 6 GB (Management API; passou = para na hora)?
    RAM livre na máquina do banco >= --ram-min MB (métrica node_memory_MemAvailable_bytes, com a service role)? conexões
    abertas <= 50? alerta do vigia (ops.banco_alerta) nos últimos 10 min? último lote abaixo de --lento s? Sem leitura de
    disco/RAM conta como falha. Se algo falhar: espera 60 s e tenta de novo (3 vezes); depois fecha a execução como
    'parada' e sai. Rodar de novo retoma do cursor.
  - Chave do AC: lida do Vault (activecampaign_api_key) a cada execução; nunca impressa nem gravada.
  - Saída e log só com contagens. Nenhum e-mail, nome ou telefone é impresso nem gravado em arquivo.
  - O lote de contatos vai como PARÂMETRO ligado ($2 da Management API), nunca dentro do texto do SQL: com
    log_min_error_statement = error, uma instrução com erro grava o texto no log do projeto; o valor do parâmetro não vai
    (log_parameter_max_length_on_error = 0, conferido em 14/10/2026). Achado do pentester de 14/10.
  - Erro do banco: só o SQLSTATE e a 1ª linha da mensagem, até 200 caracteres (sem DETAIL nem CONTEXT, que podem trazer
    a linha com dado pessoal). Qualquer erro numa fase fecha a execução como 'erro' com esse texto curto e sai.
Credencial do Supabase (Management API): variável SUPABASE_ACCESS_TOKEN, ou --env-file com SUPABASE_ACESS_TOKEN=... (padrão
do repo: controle-de-eventos/.env).
"""
import argparse, json, os, re, sys, time, urllib.error, urllib.request
from datetime import datetime
from pathlib import Path

PROJETO = 'mbvybujpkwuorhtdzcde'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/124 Safari/537.36'
FONTE = 'activecampaign'


def log(msg):
    print(f"{datetime.now():%H:%M:%S} {msg}", flush=True)


# ---------------------------------------------------------------- Supabase (Management API, uma chamada por vez)
def token(env_file):
    t = os.environ.get('SUPABASE_ACCESS_TOKEN')
    if t:
        return t.strip()
    if env_file and Path(env_file).exists():
        m = re.search(r'^SUPABASE_ACE?SS_TOKEN=(.*)$', Path(env_file).read_text(encoding='utf-8'), re.M)
        if m:
            return m.group(1).strip().strip('"')
    sys.exit('sem credencial do Supabase: defina SUPABASE_ACCESS_TOKEN ou --env-file')


def chave_metricas(env_file):
    k = os.environ.get('SUPABASE_SERVICE_ROLE_KEY')
    if not k and env_file and Path(env_file).exists():
        m = re.search(r'^SUPABASE_SERVICE_ROLE_KEY=(.*)$', Path(env_file).read_text(encoding='utf-8'), re.M)
        k = m.group(1).strip().strip('"') if m else None
    if not k:
        sys.exit('sem SUPABASE_SERVICE_ROLE_KEY: sem ela não dá para medir a RAM entre lotes (regra da carga)')
    return k


class Banco:
    def __init__(self, tok, chave_met=None):
        self.tok = tok
        self.chave_met = chave_met

    def disco_usado_gb(self):
        r = urllib.request.Request(f'https://api.supabase.com/v1/projects/{PROJETO}/config/disk/util',
                                   headers={'Authorization': 'Bearer ' + self.tok, 'User-Agent': UA})
        with urllib.request.urlopen(r, timeout=30) as x:
            return int(json.loads(x.read())['metrics']['fs_used_bytes']) / 1e9

    def ram_livre_mb(self):
        import base64
        r = urllib.request.Request(f'https://{PROJETO}.supabase.co/customer/v1/privileged/metrics',
                                   headers={'Authorization': 'Basic ' + base64.b64encode(f'service_role:{self.chave_met}'.encode()).decode(),
                                            'User-Agent': UA})
        with urllib.request.urlopen(r, timeout=30) as x:
            for l in x.read().decode().splitlines():
                if l.startswith('node_memory_MemAvailable_bytes{'):
                    return float(l.rsplit(' ', 1)[1]) / 1e6
        raise RuntimeError('métrica node_memory_MemAvailable_bytes não encontrada')

    def sql(self, q, params=None, timeout=120):
        corpo = {'query': q}
        if params is not None:
            corpo['parameters'] = params          # parâmetro ligado: o valor não entra no texto do SQL nem no log
        r = urllib.request.Request(f'https://api.supabase.com/v1/projects/{PROJETO}/database/query',
                                   data=json.dumps(corpo).encode(),
                                   headers={'Authorization': 'Bearer ' + self.tok, 'Content-Type': 'application/json', 'User-Agent': UA},
                                   method='POST')
        try:
            with urllib.request.urlopen(r, timeout=timeout) as x:
                return json.loads(x.read().decode())
        except urllib.error.HTTPError as e:
            raise ErroBanco(e.code, e.read().decode())

    def um(self, q, params=None):
        r = self.sql(q, params)
        return list(r[0].values())[0] if r else None


class ErroBanco(RuntimeError):
    """Só o SQLSTATE e a 1ª linha da mensagem, até 200 caracteres. DETAIL e CONTEXT (que podem trazer a linha com e-mail,
    telefone ou nome) nunca saem daqui."""
    def __init__(self, http, corpo):
        try:
            corpo = json.loads(corpo).get('message', corpo)
        except Exception:
            pass
        corpo = str(corpo).replace('Failed to run sql query: ', '')
        m = re.search(r'ERROR:\s+([0-9A-Z]{5}):\s*([^\n]*)', corpo)
        if m:
            self.codigo, linha = m.group(1), m.group(2)
        else:
            self.codigo, linha = f'HTTP{http}', corpo.split('\n', 1)[0]
        linha = re.sub(r'[^\s"\'<>@]+@[^\s"\'<>@]+', '***@***', linha)          # rede de segurança: e-mail
        linha = re.sub(r'\d[\d.\-\s()]{8,}\d', '***', linha)                   # rede de segurança: telefone/documento
        self.texto = f'{self.codigo} {linha.strip()}'[:200]
        super().__init__(self.texto)


# ---------------------------------------------------------------- ActiveCampaign
class AC:
    def __init__(self, banco):
        d = banco.um("select description from vault.secrets where name = 'activecampaign_api_key'") or ''
        m = re.search(r'https://[a-z0-9]+\.api-us1\.com', d)
        if not m:
            sys.exit('URL base do AC não encontrada na descrição do segredo activecampaign_api_key')
        self.base = m.group(0)
        self._k = banco.um("select decrypted_secret from vault.decrypted_secrets where name = 'activecampaign_api_key'")
        if not self._k:
            sys.exit('segredo activecampaign_api_key vazio')
        self.chamadas = 0

    def get(self, caminho):
        for t in range(5):
            r = urllib.request.Request(self.base + '/api/3/' + caminho, headers={'Api-Token': self._k, 'Accept': 'application/json'})
            try:
                with urllib.request.urlopen(r, timeout=90) as x:
                    self.chamadas += 1
                    return json.loads(x.read())
            except urllib.error.HTTPError as e:
                if e.code in (429, 500, 502, 503, 504):
                    time.sleep(5 * (t + 1))
                    continue
                raise RuntimeError(f'AC HTTP {e.code} em {caminho.split("?")[0]}')
            except urllib.error.URLError:
                time.sleep(5 * (t + 1))
        raise RuntimeError(f'AC sem resposta em {caminho.split("?")[0]}')

    def todos(self, recurso, chave):
        out, off = [], 0
        while True:
            j = self.get(f'{recurso}?limit=100&offset={off}')
            out += j.get(chave, [])
            off += 100
            time.sleep(0.5)
            if off >= int(j.get('meta', {}).get('total', 0)):
                return out


def saiu_pela_pessoa(cl):
    """Regra do descadastro (censo-capacidade-ac.md): saiu pelo link de um e-mail (campaign/message) ou deixou motivo."""
    z = lambda v: v in (None, '', '0')
    return cl.get('status') == '2' and (not z(cl.get('campaign')) or not z(cl.get('message')) or bool((cl.get('unsubreason') or '').strip()))


def montar_lote(pagina, campos):
    """Página da API (contacts + contactLists + contactTags + fieldValues) -> lote para pessoas.carga_ac_estagio."""
    listas, tags, valores = {}, {}, {}
    for cl in pagina.get('contactLists', []):
        sdate = (cl.get('sdate') or '')[:10] or None
        listas.setdefault(cl['contact'], []).append([int(cl['list']), int(cl['status']), sdate, saiu_pela_pessoa(cl)])
    for ct in pagina.get('contactTags', []):
        tags.setdefault(ct['contact'], []).append(int(ct['tag']))
    for fv in pagina.get('fieldValues', []):
        pt = campos.get(str(fv.get('field')))
        if pt and (fv.get('value') or '').strip():
            valores.setdefault(fv['contact'], {})[pt] = fv['value'].strip()[:500]
    lote = []
    for c in pagina.get('contacts', []):
        nome = ' '.join(x for x in [(c.get('firstName') or '').strip(), (c.get('lastName') or '').strip()] if x)
        lote.append({'id': int(c['id']), 'email': c.get('email') or None, 'telefone': c.get('phone') or None, 'nome': nome or None,
                     'cdate': c.get('cdate') or None, 'udate': c.get('udate') or None,
                     'bounced_hard': int(c['bounced_hard']) if str(c.get('bounced_hard') or '').isdigit() else None,
                     'listas': sorted(listas.get(c['id'], [])), 'tags': sorted(set(tags.get(c['id'], []))),
                     'campos': valores.get(c['id'], {})})
    return lote


# ---------------------------------------------------------------- saúde do banco
DISCO_MAX_GB = 6.0      # regra do Maestro (14/10/2026): parar se o disco passar de 6 GB
ULTIMA = {}


def saude(banco, ultimo_ms, lento_s, ram_min_mb):
    """None = pode seguir; 'desligada' / 'disco' = parar já; outro texto = esperar e tentar de novo."""
    r = banco.sql("""select (select count(*) from pg_stat_activity) conexoes,
                            (select count(*) from ops.banco_alerta where criado_em > now() - interval '10 minutes') alertas,
                            pessoas.carga_ligada('activecampaign') ligada""")[0]
    if not r['ligada']:
        return 'desligada'
    try:
        disco = banco.disco_usado_gb()
        ram = banco.ram_livre_mb()
    except Exception as e:
        return f'sem leitura de disco/RAM ({str(e)[:80]})'   # falha fechada: espera e tenta de novo; 4 falhas = para
    ULTIMA.update(disco_gb=round(disco, 2), ram_livre_mb=round(ram), conexoes=int(r['conexoes']))
    if disco > DISCO_MAX_GB:
        return 'disco'
    motivos = []
    if ram < ram_min_mb:
        motivos.append(f'RAM livre {ram:.0f} MB')
    if int(r['conexoes']) > 50:
        motivos.append(f"conexões {r['conexoes']}")
    if int(r['alertas']) > 0:
        motivos.append(f"{r['alertas']} alerta(s) do vigia")
    if ultimo_ms and ultimo_ms > lento_s * 1000:
        motivos.append(f'último lote {ultimo_ms} ms')
    return '; '.join(motivos) or None


def esperar_saude(banco, ultimo_ms, lento_s, ram_min_mb):
    for tentativa in range(4):
        m = saude(banco, ultimo_ms if tentativa == 0 else None, lento_s, ram_min_mb)
        if m is None:
            return True
        if m == 'desligada':
            log('chave pessoas.carga_chave desligada: parando')
            return False
        if m == 'disco':
            log(f"disco usado {ULTIMA.get('disco_gb')} GB passou de {DISCO_MAX_GB} GB: parando")
            return False
        if tentativa == 3:
            log(f'banco segue sem folga ({m}): parando para retomar depois')
            return False
        log(f'banco sem folga ({m}): esperando 60 s')
        time.sleep(60)
    return False


# ---------------------------------------------------------------- fases
ABERTA = {}


def fechar(banco, eid, status_, erro=None):
    banco.um('select pessoas.carga_fechar($1::bigint, $2::text, $3::text)', [eid, status_, erro])
    ABERTA.pop('id', None)


def rodar_fase(nome, fn, banco, *args):
    """Qualquer erro: imprime só o texto curto (ErroBanco/AC) e fecha a execução aberta como 'erro'. Ctrl+C: 'parada'."""
    try:
        fn(banco, *args)
        return True
    except KeyboardInterrupt:
        if ABERTA.get('id'):
            fechar(banco, ABERTA['id'], 'parada', 'interrompida à mão')
        log(f'{nome}: interrompida; rodar de novo retoma do cursor')
        return False
    except Exception as e:
        curto = e.texto if isinstance(e, ErroBanco) else f'{type(e).__name__}: {str(e)[:150]}'
        if isinstance(e, ErroBanco) is False and ('@' in curto or re.search(r'\d{8,}', curto)):
            curto = type(e).__name__          # nunca imprimir algo que pareça dado pessoal
        log(f'{nome}: ERRO {curto}')
        if ABERTA.get('id'):
            try:
                fechar(banco, ABERTA['id'], 'erro', curto)
            except Exception:
                log('não consegui fechar a execução como erro; ela segue aberta e retoma na próxima rodada')
        return False


def fase_catalogo(banco, ac, por):
    ex = banco.um('select pessoas.carga_abrir($1::text, $2::text, $3::text)', [FONTE, 'catalogo', por])
    eid = ex['execucao']
    ABERTA['id'] = eid
    itens = [{'tipo': 'lista', 'id': int(x['id']), 'nome': x['name']} for x in ac.todos('lists', 'lists')]
    itens += [{'tipo': 'tag', 'id': int(x['id']), 'nome': x['tag']} for x in ac.todos('tags', 'tags')]
    itens += [{'tipo': 'campo', 'id': int(x['id']), 'nome': x['title'], 'extra': {'perstag': x.get('perstag'), 'tipo': x.get('type')}}
              for x in ac.todos('fields', 'fields')]
    n = banco.um('select pessoas.carga_ac_catalogo($1::jsonb)', [json.dumps(itens, ensure_ascii=False)])
    fechar(banco, eid, 'ok')
    log(f'catálogo: {len(itens)} itens lidos, {n} gravados/atualizados')


def fase_estagio(banco, ac, por, lote_n, max_lotes, lento_s, ram_min_mb):
    ex = banco.um('select pessoas.carga_abrir($1::text, $2::text, $3::text)', [FONTE, 'estagio', por])
    eid, cursor = ex['execucao'], int(ex['cursor'] or 0)
    ABERTA['id'] = eid
    log(f"estágio: execução {eid} {'retomada do contato ' + str(cursor) if ex['retomada'] else 'nova'}")
    campos = {str(r['field_id']): r['perstag'] for r in banco.sql('select field_id, perstag from pessoas.ac_campo_carga')}
    lotes, ultimo_ms, t0 = 0, None, time.time()
    while True:
        if max_lotes and lotes >= max_lotes:
            fechar(banco, eid, 'parada', 'max-lotes atingido')
            log('max-lotes atingido: execução parada (retoma do cursor)')
            return
        if not esperar_saude(banco, ultimo_ms, lento_s, ram_min_mb):
            fechar(banco, eid, 'parada', 'banco lento ou chave desligada')
            return
        lote, fim = [], False
        while len(lote) < lote_n:
            pg = ac.get(f'contacts?limit=100&orders[id]=ASC&id_greater={cursor}&include=contactLists,contactTags,fieldValues')
            time.sleep(0.5)
            novos = montar_lote(pg, campos)
            if not novos:
                fim = True
                break
            lote += novos
            cursor = max(c['id'] for c in novos)
        if lote:
            r = banco.um('select pessoas.carga_ac_estagio($1::bigint, $2::jsonb, $3::text)',
                         [eid, json.dumps(lote, ensure_ascii=False, separators=(',', ':')), str(cursor)])
            ultimo_ms = r['ms']
            lotes += 1
            log(f"estágio lote {lotes}: {r['lidas']} lidos, {r['inseridas']} novos, {r['atualizadas']} atualizados, "
                f"{r['iguais']} iguais, {r['ms']} ms (cursor {cursor}, {ac.chamadas} chamadas AC, {time.time() - t0:.0f} s; "
                f"disco {ULTIMA.get('disco_gb')} GB, RAM livre {ULTIMA.get('ram_livre_mb')} MB, conexões {ULTIMA.get('conexoes')})")
            time.sleep(2)
        if fim:
            fechar(banco, eid, 'ok')
            log('estágio: fim da lista de contatos do AC')
            return


def fase_pessoas(banco, por, lote_n, max_lotes, lento_s, ram_min_mb):
    ex = banco.um('select pessoas.carga_abrir($1::text, $2::text, $3::text)', [FONTE, 'pessoas', por])
    eid = ex['execucao']
    ABERTA['id'] = eid
    log(f"pessoas: execução {eid} {'retomada' if ex['retomada'] else 'nova'}")
    lotes, ultimo_ms = 0, None
    while True:
        if max_lotes and lotes >= max_lotes:
            fechar(banco, eid, 'parada', 'max-lotes atingido')
            log('max-lotes atingido: execução parada')
            return
        if not esperar_saude(banco, ultimo_ms, lento_s, ram_min_mb):
            fechar(banco, eid, 'parada', 'banco lento ou chave desligada')
            return
        r = banco.um('select pessoas.carga_ac_pessoas($1::bigint, $2::int)', [eid, lote_n])
        ultimo_ms = r['ms']
        lotes += 1
        log(f"pessoas lote {lotes}: {r['lidas']} lidos, {r['pessoas_novas']} pessoas novas, {r['casadas']} casadas, "
            f"{r['sem_email']} sem e-mail, {r['revisao']} revisão, {r['eventos']} eventos, {r['ms']} ms, restam {r['restam']}; "
            f"disco {ULTIMA.get('disco_gb')} GB, RAM livre {ULTIMA.get('ram_livre_mb')} MB, conexões {ULTIMA.get('conexoes')}")
        if r['lidas'] == 0 or r['restam'] == 0:
            fechar(banco, eid, 'ok')
            log('pessoas: estágio todo processado')
            return
        time.sleep(2)


# ---------------------------------------------------------------- ensaio (amostra real, transação desfeita)
def ensaio(banco, ac, n):
    """Amostra REAL (até 500 contatos) passada como parâmetro a pessoas.carga_ensaio($1), que roda estágio (2×) e pessoas
    num bloco interno que sempre volta atrás e devolve só contagens. Termina em rollback, nunca em erro; nada vai para o
    log. Exige a migration 20261014170000 aplicada (antes disso, o ensaio é o 20261014170000_ensaio.sql do repo, com
    contatos fictícios)."""
    if not banco.um("select to_regprocedure('pessoas.carga_ensaio(jsonb)') is not null"):
        sys.exit('pessoas.carga_ensaio não existe: aplicar a 20261014170000 antes (ou usar o ensaio do repo, com dado fictício)')
    campos = {str(r['field_id']): r['perstag'] for r in banco.sql('select field_id, perstag from pessoas.ac_campo_carga')}
    n = min(n, 480)
    lote, cursor = [], 0
    while len(lote) < n:
        pg = ac.get(f'contacts?limit=100&orders[id]=ASC&id_greater={cursor}&include=contactLists,contactTags,fieldValues')
        novos = montar_lote(pg, campos)
        if not novos:
            break
        lote += novos
        cursor = max(c['id'] for c in novos)
        time.sleep(0.5)
    lote = lote[:n]
    pg = ac.get('contacts?limit=20&listid=412&include=contactLists,contactTags,fieldValues')   # garante lista de SV
    ids = {x['id'] for x in lote}
    lote += [c for c in montar_lote(pg, campos) if c['id'] not in ids]
    t0 = time.time()
    r = banco.um('select pessoas.carga_ensaio($1::jsonb)', [json.dumps(lote, ensure_ascii=False, separators=(',', ':'))])
    for k, v in r.items():
        print(f'{k} = {json.dumps(v, ensure_ascii=False)}')
    log(f'ensaio: {len(lote)} contatos, {time.time() - t0:.1f} s, desfeito (rollback interno, sem erro)')


def status(banco):
    for r in banco.sql("""select id, fase, status, cursor, lotes, lidas, inseridas, atualizadas, iguais, iniciada_em, atualizada_em
                          from pessoas.carga_execucao where fonte = 'activecampaign' order by id"""):
        print(r)
    print(banco.um('select pessoas.carga_contagem()'))


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--rodar', choices=['catalogo', 'estagio', 'pessoas', 'tudo'])
    a.add_argument('--ensaio', type=int)
    a.add_argument('--status', action='store_true')
    a.add_argument('--lote', type=int, default=1000)
    a.add_argument('--max-lotes', type=int, default=0)
    a.add_argument('--lento', type=float, default=15.0, help='segundos: lote mais lento que isto conta como banco lento')
    a.add_argument('--ram-min', type=float, default=150.0, help='MB de RAM livre na máquina do banco abaixo dos quais o lote espera')
    a.add_argument('--env-file', default=next((str(p / 'controle-de-eventos/.env') for p in Path(__file__).resolve().parents
                                               if (p / 'controle-de-eventos/.env').exists()), None))
    a.add_argument('--por', default='carga_ac.py')
    x = a.parse_args()
    if not 1 <= x.lote <= 2000:
        sys.exit('--lote entre 1 e 2000')
    if not re.fullmatch(r'[A-Za-z0-9_.\-]{1,60}', x.por):
        sys.exit('--por inválido')
    banco = Banco(token(x.env_file), None if (x.status or x.ensaio) else chave_metricas(x.env_file))
    if x.status:
        return status(banco)
    ac = AC(banco)
    if x.ensaio:
        return ensaio(banco, ac, x.ensaio)
    ok = True
    if x.rodar in ('catalogo', 'tudo'):
        ok = rodar_fase('catálogo', lambda b: fase_catalogo(b, ac, x.por), banco)
    if ok and x.rodar in ('estagio', 'tudo'):
        ok = rodar_fase('estágio', lambda b: fase_estagio(b, ac, x.por, x.lote, x.max_lotes, x.lento, x.ram_min), banco)
    if ok and x.rodar in ('pessoas', 'tudo'):
        ok = rodar_fase('pessoas', lambda b: fase_pessoas(b, x.por, x.lote, x.max_lotes, x.lento, x.ram_min), banco)
    if x.rodar:
        status(banco)
    if not ok:
        sys.exit(1)


if __name__ == '__main__':
    main()
