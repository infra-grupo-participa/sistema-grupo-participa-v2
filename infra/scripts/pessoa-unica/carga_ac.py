#!/usr/bin/env python3
"""Carga do ActiveCampaign completo para a pessoa única (migration 20261014170000).

Fases (cada uma retoma de onde parou, pelo cursor gravado em pessoas.carga_execucao):
  catalogo  listas, tags e campos do AC -> pessoas.ac_catalogo
  estagio   contatos (com listas, tags e campos) -> pessoas.ac_contato, em lotes de --lote contatos (padrão 1.000)
  pessoas   pessoas.ac_contato pendente -> pessoas.pessoas / identificadores / eventos, em lotes de --lote

Uso:
  caffeinate -i python3 carga_ac.py --rodar tudo            # catalogo + estagio + pessoas (noite)
  python3 carga_ac.py --rodar estagio --max-lotes 5          # só 5 lotes, para conferir
  python3 carga_ac.py --ensaio 300                           # amostra real de 300 contatos, numa transação DESFEITA
                                                              # junto com as migrations (exige --migrations DIR)
  python3 carga_ac.py --status                               # execuções e contagens

Segurança e regras (Manual de banco; censo-capacidade-ac.md):
  - Uma conexão por vez (Management API do Supabase, uma chamada SQL por lote). Nunca em paralelo.
  - Pausa entre páginas do AC (0,5 s) e entre lotes no banco (2 s).
  - Antes de cada lote: chave pessoas.carga_chave ligada? conexões abertas <= 50? alerta do vigia (ops.banco_alerta) nos
    últimos 10 min? Último lote demorou mais que --lento s? Se algo falhar: espera 60 s e tenta de novo (3 vezes); depois
    fecha a execução como 'parada' e sai. Rodar de novo retoma do cursor.
  - Chave do AC: lida do Vault (activecampaign_api_key) a cada execução; nunca impressa nem gravada.
  - Saída e log só com contagens. Nenhum e-mail, nome ou telefone é impresso nem gravado em arquivo.
Credencial do Supabase (Management API): variável SUPABASE_ACCESS_TOKEN, ou --env-file com SUPABASE_ACESS_TOKEN=... (padrão
do repo: controle-de-eventos/.env).
"""
import argparse, json, os, re, secrets, sys, time, urllib.error, urllib.request
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


class Banco:
    def __init__(self, tok):
        self.tok = tok

    def sql(self, q, timeout=120):
        r = urllib.request.Request(f'https://api.supabase.com/v1/projects/{PROJETO}/database/query',
                                   data=json.dumps({'query': q}).encode(),
                                   headers={'Authorization': 'Bearer ' + self.tok, 'Content-Type': 'application/json', 'User-Agent': UA},
                                   method='POST')
        try:
            with urllib.request.urlopen(r, timeout=timeout) as x:
                return json.loads(x.read().decode())
        except urllib.error.HTTPError as e:
            corpo = e.read().decode()
            try:
                corpo = json.loads(corpo).get('message', corpo)
            except Exception:
                pass
            raise RuntimeError(f'SQL HTTP {e.code}: {corpo[:8000]}')

    def um(self, q):
        r = self.sql(q)
        return list(r[0].values())[0] if r else None


def lit(obj):
    """JSON como literal SQL seguro (dollar quoting com marca aleatória)."""
    s = json.dumps(obj, ensure_ascii=False, separators=(',', ':'))
    tag = 'j' + secrets.token_hex(6)
    while f'${tag}$' in s:
        tag = 'j' + secrets.token_hex(6)
    return f'${tag}${s}${tag}$::jsonb'


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
def saude(banco, ultimo_ms, lento_s):
    r = banco.sql("""select (select count(*) from pg_stat_activity) conexoes,
                            (select count(*) from ops.banco_alerta where criado_em > now() - interval '10 minutes') alertas,
                            pessoas.carga_ligada('activecampaign') ligada""")[0]
    motivos = []
    if not r['ligada']:
        return 'desligada'
    if int(r['conexoes']) > 50:
        motivos.append(f"conexões {r['conexoes']}")
    if int(r['alertas']) > 0:
        motivos.append(f"{r['alertas']} alerta(s) do vigia")
    if ultimo_ms and ultimo_ms > lento_s * 1000:
        motivos.append(f'último lote {ultimo_ms} ms')
    return '; '.join(motivos) or None


def esperar_saude(banco, ultimo_ms, lento_s):
    for t in range(4):
        m = saude(banco, ultimo_ms if t == 0 else None, lento_s)
        if m is None:
            return True
        if m == 'desligada':
            log('chave pessoas.carga_chave desligada: parando')
            return False
        if t == 3:
            log(f'banco segue lento ({m}): parando para retomar depois')
            return False
        log(f'banco lento ({m}): esperando 60 s')
        time.sleep(60)
    return False


# ---------------------------------------------------------------- fases
def fase_catalogo(banco, ac, por):
    ex = banco.um(f"select pessoas.carga_abrir('{FONTE}', 'catalogo', '{por}')")
    eid = ex['execucao']
    itens = [{'tipo': 'lista', 'id': int(x['id']), 'nome': x['name']} for x in ac.todos('lists', 'lists')]
    itens += [{'tipo': 'tag', 'id': int(x['id']), 'nome': x['tag']} for x in ac.todos('tags', 'tags')]
    itens += [{'tipo': 'campo', 'id': int(x['id']), 'nome': x['title'], 'extra': {'perstag': x.get('perstag'), 'tipo': x.get('type')}}
              for x in ac.todos('fields', 'fields')]
    n = banco.um(f'select pessoas.carga_ac_catalogo({lit(itens)})')
    banco.sql(f"select pessoas.carga_fechar({eid}, 'ok')")
    log(f'catálogo: {len(itens)} itens lidos, {n} gravados/atualizados')


def fase_estagio(banco, ac, por, lote_n, max_lotes, lento_s):
    ex = banco.um(f"select pessoas.carga_abrir('{FONTE}', 'estagio', '{por}')")
    eid, cursor = ex['execucao'], int(ex['cursor'] or 0)
    log(f"estágio: execução {eid} {'retomada do contato ' + str(cursor) if ex['retomada'] else 'nova'}")
    campos = {str(r['field_id']): r['perstag'] for r in banco.sql('select field_id, perstag from pessoas.ac_campo_carga')}
    lotes, ultimo_ms, t0 = 0, None, time.time()
    while True:
        if max_lotes and lotes >= max_lotes:
            banco.sql(f"select pessoas.carga_fechar({eid}, 'parada', 'max-lotes atingido')")
            log('max-lotes atingido: execução parada (retoma do cursor)')
            return
        if not esperar_saude(banco, ultimo_ms, lento_s):
            banco.sql(f"select pessoas.carga_fechar({eid}, 'parada', 'banco lento ou chave desligada')")
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
            r = banco.um(f"select pessoas.carga_ac_estagio({eid}, {lit(lote)}, '{cursor}')")
            ultimo_ms = r['ms']
            lotes += 1
            log(f"estágio lote {lotes}: {r['lidas']} lidos, {r['inseridas']} novos, {r['atualizadas']} atualizados, "
                f"{r['iguais']} iguais, {r['ms']} ms (cursor {cursor}, {ac.chamadas} chamadas AC, {time.time() - t0:.0f} s)")
            time.sleep(2)
        if fim:
            banco.sql(f"select pessoas.carga_fechar({eid}, 'ok')")
            log('estágio: fim da lista de contatos do AC')
            return


def fase_pessoas(banco, por, lote_n, max_lotes, lento_s):
    ex = banco.um(f"select pessoas.carga_abrir('{FONTE}', 'pessoas', '{por}')")
    eid = ex['execucao']
    log(f"pessoas: execução {eid} {'retomada' if ex['retomada'] else 'nova'}")
    lotes, ultimo_ms = 0, None
    while True:
        if max_lotes and lotes >= max_lotes:
            banco.sql(f"select pessoas.carga_fechar({eid}, 'parada', 'max-lotes atingido')")
            log('max-lotes atingido: execução parada')
            return
        if not esperar_saude(banco, ultimo_ms, lento_s):
            banco.sql(f"select pessoas.carga_fechar({eid}, 'parada', 'banco lento ou chave desligada')")
            return
        r = banco.um(f'select pessoas.carga_ac_pessoas({eid}, {lote_n})')
        ultimo_ms = r['ms']
        lotes += 1
        log(f"pessoas lote {lotes}: {r['lidas']} lidos, {r['pessoas_novas']} pessoas novas, {r['casadas']} casadas, "
            f"{r['sem_email']} sem e-mail, {r['revisao']} revisão, {r['eventos']} eventos, {r['ms']} ms, restam {r['restam']}")
        if r['lidas'] == 0 or r['restam'] == 0:
            banco.sql(f"select pessoas.carga_fechar({eid}, 'ok')")
            log('pessoas: estágio todo processado')
            return
        time.sleep(2)


# ---------------------------------------------------------------- ensaio (amostra real, transação desfeita)
def ensaio(banco, ac, n, dir_mig):
    """Aplica as migrations (sem os índices concurrently) + carga de n contatos reais + 2ª passada (idempotência), tudo numa
    transação que termina em erro proposital: nada fica gravado. Imprime só contagens."""
    d = Path(dir_mig)
    corpo = lambda f: re.sub(r"set local statement_timeout = '30s';\n", '', (d / f).read_text(encoding='utf-8'))
    migs = ['20261014160000_fin_criar_chave_eventos.sql', '20261014160100_vincular_catalogo_eventos.sql',
            '20261014160200_pessoas_vincular_eventos_e_relacoes.sql']
    idx = """create unique index eventos_fonte_unico on pessoas.eventos (fonte_tabela, fonte_id, tipo) where fonte_id is not null;
create index eventos_evento_idx on pessoas.eventos (evento_id, tipo, quando) where evento_id is not null;
create index eventos_turma_idx on pessoas.eventos (turma_id, tipo) where turma_id is not null;\n"""
    # a tabela pessoas.ac_campo_carga ainda não existe: os campos saem do insert da própria migration
    campos = {m.group(1): m.group(2) for m in re.finditer(r"\((\d+), '([A-Z0-9_]+)'", corpo('20261014170000_pessoas_criar_carga_ac.sql').split('insert into pessoas.ac_campo_carga')[1].split(';')[0])}
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
    # inclui contatos que caem em listas de SV, para provar o evento pre_checkout (busca por lista 412)
    pg = ac.get('contacts?limit=20&listid=412&include=contactLists,contactTags,fieldValues')
    lote += [c for c in montar_lote(pg, campos) if c['id'] not in {x['id'] for x in lote}]
    s = "begin;\nset local lock_timeout = '5s';\nset local statement_timeout = '110s';\n"
    s += 'create temp table _z_out (em serial, passo text, linha text);\n'
    s += "insert into pg_temp._z_out(passo, linha) select '00 antes', (select jsonb_build_object('pessoas', (select count(*) from pessoas.pessoas), 'identificadores', (select count(*) from pessoas.identificadores), 'eventos', (select count(*) from pessoas.eventos), 'revisao', (select count(*) from pessoas.revisao))::text);\n"
    for f in migs:
        s += corpo(f) + '\n'
    s += idx + corpo('20261014170000_pessoas_criar_carga_ac.sql') + '\n'
    s += f"""
create temp table _z_e as select (pessoas.carga_abrir('activecampaign', 'estagio', 'ensaio')->>'execucao')::bigint id;
insert into pg_temp._z_out(passo, linha) select '10 estágio 1ª passada', pessoas.carga_ac_estagio((select id from pg_temp._z_e), {lit(lote)}, '{cursor}')::text;
insert into pg_temp._z_out(passo, linha) select '11 estágio 2ª passada (idempotente: tudo igual)', pessoas.carga_ac_estagio((select id from pg_temp._z_e), {lit(lote)}, '{cursor}')::text;
insert into pg_temp._z_out(passo, linha) select '12 estágio: total / com e-mail / descadastrou / desativado_empresa / com campos / com lista SV',
  count(*) || ' / ' || count(email) || ' / ' || count(*) filter (where descadastrou) || ' / ' || count(*) filter (where desativado_empresa) || ' / ' ||
  count(*) filter (where campos <> '{{}}') || ' / ' || count(*) filter (where exists (select 1 from jsonb_array_elements(listas) l join pessoas.ac_lista_papel p on p.lista_id = (l->>0)::int)) from pessoas.ac_contato;
select pessoas.carga_fechar((select id from pg_temp._z_e), 'ok');
create temp table _z_p as select (pessoas.carga_abrir('activecampaign', 'pessoas', 'ensaio')->>'execucao')::bigint id;
insert into pg_temp._z_out(passo, linha) select '20 pessoas 1º lote', pessoas.carga_ac_pessoas((select id from pg_temp._z_p), 1000)::text;
insert into pg_temp._z_out(passo, linha) select '21 pessoas 2º lote (nada pendente)', pessoas.carga_ac_pessoas((select id from pg_temp._z_p), 1000)::text;
update pessoas.ac_contato set pendente = true;
insert into pg_temp._z_out(passo, linha) select '22 reprocessar tudo (idempotente: 0 pessoas novas, 0 eventos)', pessoas.carga_ac_pessoas((select id from pg_temp._z_p), 1000)::text;
insert into pg_temp._z_out(passo, linha) select '23 eventos da carga por tipo', string_agg(tipo || ' ' || n, ', ') from (select tipo, count(*) n from pessoas.eventos where fonte_tabela = 'pessoas.ac_contato' group by 1) x;
insert into pg_temp._z_out(passo, linha) select '24 contatos com pessoa / pessoa nova / casada com quem já existia', count(pessoa_id) || ' / ' || count(*) filter (where pessoa_nova) || ' / ' || count(*) filter (where pessoa_nova = false) from pessoas.ac_contato;
insert into pg_temp._z_out(passo, linha) select '25 lotes registrados / execuções', (select count(*) from pessoas.carga_lote) || ' / ' || (select string_agg(fase || ':' || status, ',') from pessoas.carga_execucao);
update pessoas.carga_chave set ligada = false;
do $t$ begin
  begin perform pessoas.carga_ac_pessoas((select id from pg_temp._z_p), 10);
    insert into pg_temp._z_out(passo, linha) values ('26 chave desligada', 'RODOU (ERRO)');
  exception when raise_exception then insert into pg_temp._z_out(passo, linha) values ('26 chave desligada', 'recusou (ok)'); end;
end $t$;
insert into pg_temp._z_out(passo, linha) select '27 funções executáveis por anon/authenticated', count(*)::text from pg_proc p where p.pronamespace = 'pessoas'::regnamespace and p.proname like any (array['carga%', 'casar_email']) and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'));
insert into pg_temp._z_out(passo, linha) select '30 depois', (select jsonb_build_object('pessoas', (select count(*) from pessoas.pessoas), 'identificadores', (select count(*) from pessoas.identificadores), 'eventos', (select count(*) from pessoas.eventos), 'revisao', (select count(*) from pessoas.revisao))::text);
do $saida$ begin raise exception 'ENSAIO_SAIDA%', (select string_agg(passo || ' = ' || linha, E'\\n' order by em) from pg_temp._z_out); end $saida$;
"""
    t0 = time.time()
    try:
        banco.sql(s, timeout=200)
        log('ERRO: o ensaio não abortou (deveria terminar em erro proposital)')
    except RuntimeError as e:
        m = str(e)
        if 'ENSAIO_SAIDA' in m:
            print(m.split('ENSAIO_SAIDA', 1)[1].split('CONTEXT')[0].replace('\\n', '\n'))
            log(f'ensaio: {len(lote)} contatos, {time.time() - t0:.1f} s, transação desfeita')
        else:
            log('ensaio falhou: ' + m[:600])


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
    a.add_argument('--migrations', default=str(Path(__file__).resolve().parents[2] / 'supabase/migrations'))
    a.add_argument('--env-file', default=next((str(p / 'controle-de-eventos/.env') for p in Path(__file__).resolve().parents
                                               if (p / 'controle-de-eventos/.env').exists()), None))
    a.add_argument('--por', default='carga_ac.py')
    x = a.parse_args()
    if not 1 <= x.lote <= 2000:
        sys.exit('--lote entre 1 e 2000')
    if not re.fullmatch(r'[A-Za-z0-9_.\-]{1,60}', x.por):
        sys.exit('--por inválido')
    banco = Banco(token(x.env_file))
    if x.status:
        return status(banco)
    ac = AC(banco)
    if x.ensaio:
        return ensaio(banco, ac, x.ensaio, x.migrations)
    if x.rodar in ('catalogo', 'tudo'):
        fase_catalogo(banco, ac, x.por)
    if x.rodar in ('estagio', 'tudo'):
        fase_estagio(banco, ac, x.por, x.lote, x.max_lotes, x.lento)
    if x.rodar in ('pessoas', 'tudo'):
        fase_pessoas(banco, x.por, x.lote, x.max_lotes, x.lento)
    if x.rodar:
        status(banco)


if __name__ == '__main__':
    main()
