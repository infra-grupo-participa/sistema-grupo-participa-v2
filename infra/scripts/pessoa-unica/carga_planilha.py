#!/usr/bin/env python3
"""Carga da planilha "Alunos T1-T42 Ativação" para a pessoa única (migration 20261014210200).

Lê as abas de turma (nome começa com T<n>) e de sócios (nome começa com "Sócios") pela conta Google do Victor
(~/.mcp-google-sheets, a mesma do MCP local), reconhece as colunas pelo cabeçalho e manda SÓ e-mail, telefone, nome,
turma, data e papel ao banco, como parâmetro ligado (nunca no texto do SQL). Documento e CPF não são lidos.

Uso:
  python3 carga_planilha.py --previa            # NÃO toca no banco: por aba, o papel, a turma, as colunas reconhecidas e
                                                # quantas linhas com e-mail (só contagens)
  caffeinate -i python3 carga_planilha.py --rodar   # estágio + pessoas, com as mesmas checagens de saúde do carga_ac.py
"""
import argparse, json, os, re, sys, time, urllib.parse, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import carga_ac as c   # noqa: E402

PLANILHA = '1bxr71O3UKo0fdPfNXPEYNs9ZWrHNooXALxmvCXa6Ak8'
FONTE = 'ativacao_planilha'
E = re.compile(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')


def google_token():
    p = Path(os.path.expanduser('~/.mcp-google-sheets/'))
    t = json.loads((p / 'gdrive-token.json').read_text())
    cr = json.loads((p / 'gdrive-credentials.json').read_text())
    cr = cr.get('installed', cr.get('web', cr))
    d = urllib.parse.urlencode({'client_id': cr['client_id'], 'client_secret': cr['client_secret'],
                                'refresh_token': t['refresh_token'], 'grant_type': 'refresh_token'}).encode()
    return json.loads(urllib.request.urlopen('https://oauth2.googleapis.com/token', d).read())['access_token']


def ler_abas(tok):
    g = lambda u: json.loads(urllib.request.urlopen(urllib.request.Request(u, headers={'Authorization': 'Bearer ' + tok}), timeout=120).read())
    meta = g(f'https://sheets.googleapis.com/v4/spreadsheets/{PLANILHA}?fields=sheets.properties(title,sheetId)')
    titulos = [s['properties']['title'] for s in meta['sheets']]
    out = {}
    for i in range(0, len(titulos), 25):       # lote de 25 abas por chamada (cota de leitura do Google)
        q = '&'.join('ranges=' + urllib.parse.quote(f"'{t}'", safe='') for t in titulos[i:i + 25])
        for t, vr in zip(titulos[i:i + 25], g(f'https://sheets.googleapis.com/v4/spreadsheets/{PLANILHA}/values:batchGet?{q}')['valueRanges']):
            out[t] = vr.get('values', [])
        time.sleep(3)
    return titulos, out


def turma_da_aba(aba):
    if re.search(r'\bT\d+\s+e\s+T\d+', aba):          # "Sócios T9 e T10": duas turmas, não escolho uma
        return None
    m = re.match(r'^(?:S[óo]cios\s+)?(T\d{1,3}(?:\.\d{1,2}|\.?R)?)\b', aba.strip(), re.I)
    return m.group(1).upper().replace('.R', 'R') if m else None


def papel_da_aba(aba):
    if re.match(r'^\s*S[óo]cios', aba, re.I):
        return 'socio'
    if re.match(r'^\s*T\d', aba):
        return 'aluno'
    return None


PROIBIDA = re.compile(r'documento|cpf|cnpj|rg\b|identidade|passaporte|nascimento|endere|cep|bairro|n[úu]mero$|complemento', re.I)


def colunas(v, papel):
    """(linha do cabeçalho, índices). Cabeçalho = 1ª das 3 primeiras linhas com uma célula 'e-mail'. Sem cabeçalho: a
    coluna de e-mail sai do conteúdo e o resto fica sem coluna. Coluna de documento/CPF/endereço nunca é usada."""
    hdr = next((i for i, r in enumerate(v[:3]) if any(re.search(r'e-?mail', (c or '').lower()) for c in r)), None)
    if hdr is None:
        n = max((len(r) for r in v), default=0)
        cont = [sum(1 for r in v if j < len(r) and E.match(r[j].strip())) for j in range(n)]
        j = max(range(n), key=lambda k: cont[k]) if n and max(cont) > 0 else None
        return 0, {'email': j, 'titular_email': None, 'nome': None, 'titular_nome': None, 'telefone': None, 'ddd': None, 'data': None}
    cab = [(c or '').strip().lower() for c in v[hdr]]
    ok = lambda i: not PROIBIDA.search(cab[i])
    def acha1(*pads, evita=None, fora=()):
        for i, h in enumerate(cab):
            if i in fora or not h or not ok(i) and not re.search(r'n[úu]mero de (telefone|contato)', h):
                continue
            if any(re.search(p, h) for p in pads) and not (evita and re.search(evita, h)):
                return i
        return None
    col = {}
    if papel == 'socio':
        col['titular_email'] = acha1(r'e-?mail.*(aluno|titular)', r'(aluno|titular).*e-?mail')
        col['email'] = acha1(r'e-?mail.*s[óo]cio', fora=(col['titular_email'],)) or acha1(r'e-?mail', fora=(col['titular_email'],))
        col['titular_nome'] = acha1(r'principal', r'titular', r'^nome do aluno$', r'nome completo do aluno', r'^s[óo]cio de',
                                    r'se [ée] s[óo]cio', r's[óo]cio do aluno', r'^de$', evita=r'e-?mail')
        col['nome'] = acha1(r'nome.*s[óo]cio', r'^nome$', r'^nome do s[óo]cio', evita=r'principal|titular|e-?mail',
                            fora=(col['titular_nome'],))
        if col['nome'] is None and cab and cab[0] == '' and col['email'] == 1:
            col['nome'] = 0                                   # aba com a 1ª coluna (nome) sem título
    else:
        col['titular_email'], col['titular_nome'] = None, None
        col['email'] = acha1(r'^e-?mail$', r'^e-?mail\b', r'e-?mail')
        col['nome'] = acha1(r'^nome$', r'^nome completo', r'^nome\b', evita=r's[óo]cio|titular|produt|afiliad')
    col['telefone'] = acha1(r'^telefone', r'telefone', r'^whats', r'n[úu]mero de (telefone|contato)', r'^n[úu]mero$',
                            evita=r'profissional|link')
    col['ddd'] = acha1(r'^ddd$')
    col['data'] = acha1(r'^data da compra', r'^data de confirma', r'^data de venda', r'^data$')
    return hdr + 1, col


def data_iso(v):
    m = re.match(r'^\s*(\d{1,2})/(\d{1,2})/(\d{4})', v or '')
    return f'{m.group(3)}-{int(m.group(2)):02d}-{int(m.group(1)):02d}' if m else None


def linhas(titulos, dados):
    resumo, todas = [], []
    for aba in titulos:
        papel = papel_da_aba(aba)
        if not papel:
            resumo.append((aba, 'fora', None, {}, 0)); continue
        v = dados.get(aba, [])
        if not v:
            resumo.append((aba, papel, turma_da_aba(aba), {}, 0)); continue
        ini, col = colunas(v, papel)
        if col['email'] is None:
            resumo.append((aba, papel, turma_da_aba(aba), col, -1)); continue
        cel = lambda r, k: (r[col[k]].strip() if col.get(k) is not None and col[k] < len(r) else '')
        n = 0
        for r in v[ini:]:
            em = cel(r, 'email')
            if not E.match(em):
                continue
            tel = cel(r, 'telefone')
            if col.get('ddd') is not None and cel(r, 'ddd') and len(re.sub(r'\D', '', tel)) <= 9:
                tel = cel(r, 'ddd') + tel
            tit = cel(r, 'titular_email')
            todas.append({'aba': aba, 'papel': papel, 'turma': turma_da_aba(aba), 'email': em, 'telefone': tel or None,
                          'nome': cel(r, 'nome') or None, 'titular_email': tit if E.match(tit) else None,
                          'titular_nome': cel(r, 'titular_nome') or None, 'data': data_iso(cel(r, 'data'))})
            n += 1
        titulos_cab = [(c or '').strip() for c in v[ini - 1]] if ini > 0 else []
        resumo.append((aba, papel, turma_da_aba(aba),
                       {k: (repr(titulos_cab[i]) if i is not None and i < len(titulos_cab) else (('coluna ' + str(i) + ' (sem cabeçalho)') if i is not None else None))
                        for k, i in col.items()}, n))
    return resumo, todas


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--previa', action='store_true')
    a.add_argument('--rodar', action='store_true')
    a.add_argument('--lote', type=int, default=500)
    a.add_argument('--lento', type=float, default=30.0)
    a.add_argument('--ram-min', type=float, default=150.0)
    a.add_argument('--env-file', default=next((str(p / 'controle-de-eventos/.env') for p in Path(__file__).resolve().parents
                                               if (p / 'controle-de-eventos/.env').exists()), None))
    x = a.parse_args()
    titulos, dados = ler_abas(google_token())
    resumo, todas = linhas(titulos, dados)
    if x.previa or not x.rodar:
        for aba, papel, turma, col, n in resumo:
            if papel == 'fora':
                print(f'FORA  | {aba}')
            elif n == -1:
                print(f'SEM COLUNA DE E-MAIL RECONHECIDA | {aba} | {papel} | colunas: {col}')
            else:
                print(f'{papel:5} | {turma or "-":6} | {n:5} linhas com e-mail | {aba} | ' +
                      ', '.join(f'{k}={v}' for k, v in col.items() if v))
        so = [t for t in todas if t['papel'] == 'socio']
        print(f'TOTAL: {len(todas)} linhas ({len(todas) - len(so)} alunos, {len(so)} sócios, dos quais '
              f'{sum(1 for t in so if t["titular_email"])} com e-mail do titular e {sum(1 for t in so if not t["titular_email"])} só com o nome do titular)')
        return
    banco = c.Banco(c.token(x.env_file), c.chave_metricas(x.env_file))

    def estagio(b):
        ex = b.um('select pessoas.carga_abrir($1::text, $2::text, $3::text)', [FONTE, 'estagio', 'carga_planilha.py'])
        c.ABERTA['id'] = ex['execucao']
        for i in range(0, len(todas), x.lote):
            if not c.esperar_saude(b, None, x.lento, x.ram_min):
                c.fechar(b, ex['execucao'], 'parada', 'banco sem folga'); raise SystemExit('parada por saúde')
            r = b.um('select pessoas.carga_planilha_estagio($1::bigint, $2::text, $3::jsonb)',
                     [ex['execucao'], PLANILHA, json.dumps(todas[i:i + x.lote], ensure_ascii=False)])
            c.log(f"estágio {i // x.lote + 1}: {r['lidas']} lidas, {r['inseridas']} novas, {r['atualizadas']} atualizadas, {r['ms']} ms")
            time.sleep(2)
        c.fechar(b, ex['execucao'], 'ok')

    def pessoas(b):
        ex = b.um('select pessoas.carga_abrir($1::text, $2::text, $3::text)', [FONTE, 'pessoas', 'carga_planilha.py'])
        c.ABERTA['id'] = ex['execucao']
        while True:
            if not c.esperar_saude(b, None, x.lento, x.ram_min):
                c.fechar(b, ex['execucao'], 'parada', 'banco sem folga'); raise SystemExit('parada por saúde')
            r = b.um('select pessoas.carga_planilha_pessoas($1::bigint, $2::int)', [ex['execucao'], x.lote])
            c.log(f"pessoas: {r['lidas']} lidas, {r['pessoas_novas']} novas, {r['casadas']} casadas, {r['eventos']} eventos, "
                  f"{r['relacoes']} relações, restam {r['restam']}, {r['ms']} ms")
            if r['lidas'] == 0 or r['restam'] == 0:
                break
            time.sleep(2)
        c.fechar(b, ex['execucao'], 'ok')

    if c.rodar_fase('planilha: estágio', estagio, banco) and c.rodar_fase('planilha: pessoas', pessoas, banco):
        c.log('planilha: fim')
    else:
        sys.exit(1)


if __name__ == '__main__':
    main()
