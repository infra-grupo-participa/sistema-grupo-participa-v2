#!/usr/bin/env python3
"""
Extração da Clint → staging arquivo.clint_* (F6 do CRM Comercial, migration 20261006d).

Só faz GET na Clint (https://api.clint.digital, header `api-token`, plano Elite). Nunca escreve na Clint.
Grava no banco SOMENTE pelas 2 RPCs service_role da 20261006d:
  public.crm_clint_staging_lote(p_lote, p_acao, p_contagens)   abrir / completo / incompleto
  public.crm_clint_staging_gravar(p_lote, p_tipo, p_itens)      upsert idempotente por (tipo, clint_id), até 1000 itens
Nada de dado pessoal sai em arquivo ou na tela: o script imprime só contagens.

Pré-requisito: migration 20261006d APLICADA (sem ela as RPCs não existem e o script para no 1º passo).
A carga staging → pessoas/crm NÃO é feita aqui: é crm.clint_carregar(...) no banco (ensaio por padrão).

Variáveis de ambiente (nunca em arquivo do repo):
  CLINT_TOKEN                 token da API (Conta → API na Clint). Obrigatório.
  SUPABASE_URL                https://mbvybujpkwuorhtdzcde.supabase.co
  SUPABASE_SERVICE_ROLE_KEY   chave service_role
  (ou CLINT_SUPABASE_ENV=<caminho de um .env fora do repo com as duas acima>, como o respondi/carga.py)

Uso:
  python3 clint_extrair.py --contar                 # só mede volume (1 GET por recurso, limit=1); não grava nada
  python3 clint_extrair.py --seco                   # baixa tudo e conta, sem gravar no banco
  python3 clint_extrair.py                          # extração completa para o staging (lote novo)
  python3 clint_extrair.py --desde 2026-10-01       # incremental: só negócios com updated_at >= data (+ cadastros)
  python3 clint_extrair.py --escopo recentes --dias 90 [--seco] [--com-historico]
      abertos com updated_at nos últimos N dias + TODOS os ganhos/perdidos; só os contatos (varredura de /v1/contacts
      filtrada; --contatos individual = 1 GET por contato), origens/grupos e atividades desses negócios; usuários,
      motivos, tags e campos inteiros. Histórico desligado por padrão (1 GET por negócio). Grava página a página.
Opções: --rps 2 (requisições/s), --historico todos|abertos|nenhum, --sem-atividades, --lote-itens 500.

Idempotente: reextrair o mesmo dado = 0 novos (md5 do payload). O lote só fecha como 'completo' se cada recurso
paginado trouxe exatamente o totalCount que a API anunciou; senão 'incompleto' (e a carga real recusa o lote).
"""
import argparse
import datetime as dt
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

CLINT = "https://api.clint.digital"
PROJETO = "mbvybujpkwuorhtdzcde"
USER_AGENT = "grupo-participa-crm-f6/1.0"


# ─── configuração ────────────────────────────────────────────────────────────────────────────────────────────────────
def ler_env():
    env = dict(os.environ)
    arq = env.get("CLINT_SUPABASE_ENV")
    if arq:
        with open(arq, encoding="utf-8") as f:
            for linha in f:
                linha = linha.strip()
                if linha and not linha.startswith("#") and "=" in linha:
                    k, v = linha.split("=", 1)
                    env.setdefault(k.strip(), v.strip().strip('"'))
    return env


# ─── HTTP com limite de taxa e repetição ─────────────────────────────────────────────────────────────────────────────
class Limitador:
    def __init__(self, rps):
        self.intervalo = 1.0 / max(rps, 0.1)
        self.ultimo = 0.0

    def esperar(self):
        falta = self.ultimo + self.intervalo - time.monotonic()
        if falta > 0:
            time.sleep(falta)
        self.ultimo = time.monotonic()


class Clint:
    def __init__(self, token, rps):
        self.token = token
        self.lim = Limitador(rps)
        self.requisicoes = 0

    def get(self, caminho, params=None, tentativas=6):
        url = CLINT + caminho + ("?" + urllib.parse.urlencode(params) if params else "")
        espera = 2.0
        for n in range(tentativas):
            self.lim.esperar()
            self.requisicoes += 1
            req = urllib.request.Request(url, method="GET", headers={
                "api-token": self.token, "Accept": "application/json", "User-Agent": USER_AGENT})
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    return json.loads(r.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                if e.code in (401, 403):
                    raise SystemExit(f"Clint recusou {caminho} (HTTP {e.code}): token inválido, sem plano Elite ou sem escopo.")
                if e.code == 404:
                    return None
                if e.code == 429 or e.code >= 500:
                    ra = e.headers.get("Retry-After")
                    pausa = float(ra) if ra and ra.replace(".", "", 1).isdigit() else espera
                    print(f"  aviso: HTTP {e.code} em {caminho}; nova tentativa em {pausa:.0f}s", file=sys.stderr)
                    time.sleep(pausa)
                    espera = min(espera * 2, 120)
                    continue
                raise SystemExit(f"Clint: HTTP {e.code} em {caminho}")
            except (urllib.error.URLError, TimeoutError, socket.timeout, ConnectionError, json.JSONDecodeError) as e:
                print(f"  aviso: rede ({e}) em {caminho}; nova tentativa em {espera:.0f}s", file=sys.stderr)
                time.sleep(espera)
                espera = min(espera * 2, 120)
        raise SystemExit(f"Clint: desisti de {caminho} depois de {tentativas} tentativas")

    def iterar(self, caminho, params=None, limite=500, v2=False):
        """Percorre página a página sem acumular tudo em memória. Gera (itens_da_pagina, total_anunciado).
        Página vazia com has_next verdadeiro (já visto em /v1/contacts) é repetida até 2 vezes antes de parar."""
        params = dict(params or {})
        pagina, max_pag, vazias = 1, None, 0
        while True:
            params.update({"page": pagina, "limit": limite})
            r = self.get(caminho, params)
            if r is None:
                return
            dados = r.get("data") or []
            total = r.get("total_count" if v2 else "totalCount")
            if max_pag is None:
                tp = r.get("total_pages" if v2 else "totalPages")
                max_pag = (tp or 0) + 2           # trava contra laço infinito se a API errar o hasNext
            tem_mais = r.get("has_next" if v2 else "hasNext")
            if not dados and tem_mais and vazias < 2:
                vazias += 1
                print(f"  aviso: página {pagina} de {caminho} veio vazia com has_next; repetindo", file=sys.stderr)
                time.sleep(2)
                continue
            vazias = 0
            yield dados, total
            if not tem_mais or not dados or pagina >= (max_pag or 10**6):
                return
            pagina += 1

    def paginas(self, caminho, params=None, limite=500, v2=False):
        """Devolve (itens, total_anunciado) — para recursos pequenos."""
        itens, total = [], None
        for dados, t in self.iterar(caminho, params, limite, v2):
            itens.extend(dados)
            total = t if total is None else total
        return itens, total

    def total(self, caminho, params=None, v2=False):
        p = dict(params or {})
        p.update({"page": 1, "limit": 1})
        r = self.get(caminho, p) or {}
        return r.get("total_count" if v2 else "totalCount")


# ─── banco (só as 2 RPCs service_role) ───────────────────────────────────────────────────────────────────────────────
class Banco:
    def __init__(self, url, chave):
        if PROJETO not in url:
            raise SystemExit("SUPABASE_URL não é o projeto mbvybujpkwuorhtdzcde")
        self.url, self.chave = url.rstrip("/"), chave

    def rpc(self, fn, corpo):
        req = urllib.request.Request(f"{self.url}/rest/v1/rpc/{fn}", data=json.dumps(corpo).encode("utf-8"), method="POST",
                                     headers={"apikey": self.chave, "Authorization": "Bearer " + self.chave,
                                              "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=120) as r:
            res = json.loads(r.read().decode("utf-8"))
        if not isinstance(res, dict) or not res.get("ok"):
            raise SystemExit(f"{fn} recusou: {res.get('msg') if isinstance(res, dict) else res}")
        return res


# ─── normalização dos itens para o staging ───────────────────────────────────────────────────────────────────────────
def itens_campos(resp):
    """GET /v1/account/fields → 1 item por (entidade, chave). O formato publicado é {data:[{groups, fields:{DEAL:{...}}}]}."""
    saida = []
    blocos = (resp or {}).get("data") or []
    if isinstance(blocos, dict):
        blocos = [blocos]
    for b in blocos:
        campos = (b or {}).get("fields") or {}
        for ent in ("CONTACT", "DEAL", "ORGANIZATION"):
            defs = campos.get(ent) or {}
            if isinstance(defs, dict) and any(isinstance(v, dict) for v in defs.values()):
                pares = defs.items()                       # {chave: {type, group, label}}
            elif isinstance(defs, list):
                pares = [(d.get("key") or d.get("name") or d.get("label"), d) for d in defs if isinstance(d, dict)]
            else:
                pares = [(defs.get("key") or defs.get("label"), defs)] if defs.get("label") else []
            for chave, meta in pares:
                if not chave:
                    continue
                saida.append({"clint_id": f"{ent}:{chave}"[:200], "payload": {
                    "entidade": ent, "chave": chave, "label": (meta or {}).get("label"),
                    "type": (meta or {}).get("type"), "group": (meta or {}).get("group")}})
    return saida


def com_id(lista, tipo):
    return [{"clint_id": str(x["id"]), "payload": x} for x in lista if isinstance(x, dict) and x.get("id")]


# ─── escopo "recentes" ───────────────────────────────────────────────────────────────────────────────────────────────
def extrair_recentes(a, cl, gravar, contagens, tam):
    """Abertos com updated_at nos últimos a.dias + TODOS os ganhos e perdidos; só os contatos, origens (e grupos
    delas) e atividades desses negócios; usuários, motivos, tags e campos inteiros. Histórico só com --com-historico.
    Vai gravando página a página (não acumula os negócios em memória). Devolve False se algo veio incompleto."""
    ok = True
    inicio_janela = (dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=a.dias)).strftime("%Y-%m-%dT00:00:00+00:00")
    tempos = {}

    def etapa(nome, t0, r0):
        tempos[nome] = {"s": round(time.monotonic() - t0, 1), "req": cl.requisicoes - r0}
        print(f"  [{nome}] {tempos[nome]['s']}s, {tempos[nome]['req']} requisições")

    # 1) cadastros pequenos, inteiros
    t0, r0 = time.monotonic(), cl.requisicoes
    for tipo, caminho in (("usuario", "/v1/users"), ("motivo", "/v1/lost-status"), ("tag", "/v1/tags")):
        lista, total = cl.paginas(caminho, limite=1000)
        gravar(tipo, com_id(lista, tipo), total)
    gravar("campo", itens_campos(cl.get("/v1/account/fields")))
    etapa("cadastros", t0, r0)

    # 2) negócios: OPEN na janela + WON + LOST (sem filtro de data). Guarda só ids (negócio, contato, origem).
    t0, r0 = time.monotonic(), cl.requisicoes
    negocios, contatos_ref, origens_ref = [], set(), set()
    vistos = set()
    c = contagens.setdefault("negocio", {"api": 0, "baixados": 0, "novos": 0, "alterados": 0})
    for st, params in (("OPEN", {"status": "OPEN", "updated_at_start": inicio_janela}),
                       ("WON", {"status": "WON"}), ("LOST", {"status": "LOST"})):
        anunciado, vieram, pag = None, 0, 0
        for dados, total in cl.iterar("/v1/deals", params, limite=1000):
            anunciado = total if anunciado is None else anunciado
            pag += 1
            novos = []
            for x in dados:
                if not isinstance(x, dict) or not x.get("id") or str(x["id"]) in vistos:
                    continue                                   # repetido entre páginas (paginação andou) não conta 2×
                vistos.add(str(x["id"]))
                negocios.append(str(x["id"]))
                cid = (x.get("contact") or {}).get("id")
                if cid:
                    contatos_ref.add(str(cid))
                if x.get("origin_id"):
                    origens_ref.add(str(x["origin_id"]))
                novos.append(x)
            vieram += len(novos)
            gravar("negocio", com_id(novos, "negocio"), silencioso=True)
            if pag % 20 == 0:
                print(f"  negócios {st}: {vieram}/{anunciado}")
        c["api"] += int(anunciado or 0)
        print(f"  negócios {st}: {vieram} baixados (API anunciou {anunciado})")
    etapa("negocios", t0, r0)

    # 3) origens usadas por esses negócios (+ os grupos delas)
    t0, r0 = time.monotonic(), cl.requisicoes
    origens, total_origens = cl.paginas("/v1/origins", limite=1000)
    usadas = [o for o in origens if isinstance(o, dict) and str(o.get("id")) in origens_ref]
    gravar("origem", com_id(usadas, "origem"))
    faltam = len(origens_ref - {str(o.get("id")) for o in usadas})
    contagens["origem"].update({"referenciadas": len(origens_ref), "na_conta": total_origens, "sem_cadastro": faltam})
    if faltam:
        print(f"  aviso: {faltam} origem(ns) usada(s) por negócio não existe(m) mais em /v1/origins", file=sys.stderr)
    grupos_ref = set()
    for o in usadas:
        g = o.get("group")
        gid = g.get("id") if isinstance(g, dict) else (g if isinstance(g, str) else o.get("group_id"))
        if gid:
            grupos_ref.add(str(gid))
    grupos, _ = cl.paginas("/v1/groups", limite=1000)
    grupos = [g for g in grupos if isinstance(g, dict) and (not grupos_ref or str(g.get("id")) in grupos_ref)]
    gravar("grupo", com_id(grupos, "grupo"))
    etapa("origens", t0, r0)

    # 4) contatos referenciados. Varredura (1000/página) sai muito mais barata que 1 GET por contato; quem não aparecer
    #    na varredura é buscado individualmente. Sem cadastro (404) a carga usa o contato embutido no negócio.
    t0, r0 = time.monotonic(), cl.requisicoes
    achados = set()
    if a.contatos == "varredura":
        pag = 0
        for dados, _ in cl.iterar("/v1/contacts", limite=1000):
            pag += 1
            sel = [x for x in dados if isinstance(x, dict) and str(x.get("id")) in contatos_ref
                   and str(x.get("id")) not in achados]
            achados.update(str(x["id"]) for x in sel)
            gravar("contato", com_id(sel, "contato"), silencioso=True)
            if pag % 25 == 0:
                print(f"  contatos: página {pag}, {len(achados)}/{len(contatos_ref)} referenciados achados")
    faltando = sorted(contatos_ref - achados)
    if faltando and a.contatos == "varredura":
        print(f"  contatos: {len(faltando)} referenciados fora da varredura → GET individual")
    sem_cadastro, buf = 0, []
    for k, cid in enumerate(faltando, 1):
        r = cl.get(f"/v1/contacts/{cid}")
        x = (r.get("data") if isinstance(r, dict) and isinstance(r.get("data"), dict) else r) if r else None
        if isinstance(x, dict) and x.get("id"):
            achados.add(str(x["id"]))
            buf.append(x)
        else:
            sem_cadastro += 1
        if len(buf) >= tam:
            gravar("contato", com_id(buf, "contato"), silencioso=True)
            buf = []
        if k % 500 == 0:
            print(f"  contatos individuais: {k}/{len(faltando)}")
    if buf:
        gravar("contato", com_id(buf, "contato"), silencioso=True)
    cc = contagens.setdefault("contato", {"api": 0, "baixados": 0, "novos": 0, "alterados": 0})
    cc.update({"referenciados": len(contatos_ref), "get_individual": len(faltando), "sem_cadastro": sem_cadastro})
    print(f"  contatos: {cc['baixados']} de {len(contatos_ref)} referenciados ({len(faltando)} por GET individual,"
          f" {sem_cadastro} sem cadastro)")
    etapa("contatos", t0, r0)

    # 5) atividades: a lista não filtra por vários negócios → varre /v2/activities (200/página) e guarda as do escopo
    if not a.sem_atividades:
        t0, r0 = time.monotonic(), cl.requisicoes
        try:
            # a lista vem de índice de busca (eventualmente consistente): a paginação repete itens → dedupe por id
            unicas, anunciado, sel_total, vistas = set(), None, 0, 0
            for dados, total in cl.iterar("/v2/activities", limite=200, v2=True):
                anunciado = total if anunciado is None else anunciado
                vistas += len(dados)
                sel = []
                for x in dados:
                    if not isinstance(x, dict) or not x.get("id") or str(x["id"]) in unicas:
                        continue
                    unicas.add(str(x["id"]))
                    if str((x.get("deal") or {}).get("id")) in vistos:
                        sel.append({"clint_id": str(x["id"]), "pai_id": str(x["deal"]["id"]), "payload": x})
                sel_total += len(sel)
                gravar("atividade", sel, silencioso=True)
            contagens["atividade"].update({"varridas": vistas, "unicas": len(unicas), "anunciadas": anunciado})
            print(f"  atividades: {sel_total} do escopo, de {len(unicas)} únicas ({vistas} com repetição;"
                  f" API anunciou {anunciado})")
            if anunciado is not None and len(unicas) < anunciado:
                ok = False
                print(f"  ATENÇÃO atividades: API anunciou {anunciado} e a varredura achou {len(unicas)} únicas"
                      " (paginação perdeu itens; rodar de novo — é idempotente)", file=sys.stderr)
        except SystemExit as e:
            print(f"  atividades: puladas ({e})", file=sys.stderr)
            contagens["atividade"] = {"api": None, "baixados": 0, "erro": "indisponivel"}
        etapa("atividades", t0, r0)

    # 6) histórico (opcional): 1 GET (ou mais) por negócio
    # estimativa do histórico com amostra real (5 negócios; só leitura, nada gravado)
    amostra = negocios[:: max(1, len(negocios) // 5)][:5]
    t_am = time.monotonic()
    for nid in amostra:
        cl.get(f"/v2/deals/{nid}/history", {"page": 1, "limit": 200})
    seg_hist = max((time.monotonic() - t_am) / max(1, len(amostra)), 1.0 / max(a.rps, 0.1))
    if a.com_historico:
        t0, r0 = time.monotonic(), cl.requisicoes
        itens = []
        for k, nid in enumerate(negocios, 1):
            for dados, _ in cl.iterar(f"/v2/deals/{nid}/history", limite=200, v2=True):
                for h in dados:
                    if isinstance(h, dict) and h.get("id"):
                        itens.append({"clint_id": f"{nid}:{h['id']}"[:200], "pai_id": nid, "payload": h})
            if len(itens) >= tam:
                gravar("historico", itens, silencioso=True)
                itens = []
            if k % 500 == 0:
                feito = time.monotonic() - t0
                print(f"  histórico: {k}/{len(negocios)} negócios, faltam ~{feito / k * (len(negocios) - k) / 3600:.1f} h")
        if itens:
            gravar("historico", itens, silencioso=True)
        etapa("historico", t0, r0)
    else:
        print(f"  histórico: pulado (--com-historico). Custaria ≥ {len(negocios)} GET ≈"
              f" {len(negocios) * seg_hist / 3600:.1f} h a {seg_hist:.2f} s/negócio (amostra de {len(amostra)})")

    print("  tempos por etapa: " + json.dumps(tempos, ensure_ascii=False))
    return ok


# ─── principal ───────────────────────────────────────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Extrai a Clint para arquivo.clint_* (só GET; só contagens na saída).")
    ap.add_argument("--contar", action="store_true", help="só mede volume (totalCount de cada recurso); não grava")
    ap.add_argument("--seco", action="store_true", help="baixa tudo e conta; não grava no banco")
    ap.add_argument("--rps", type=float, default=2.0, help="requisições por segundo na Clint (padrão 2)")
    ap.add_argument("--historico", choices=["todos", "abertos", "nenhum"], default="todos",
                    help="GET /v2/deals/{id}/history: 1 requisição (ou mais) por negócio")
    ap.add_argument("--sem-atividades", action="store_true", help="não chama /v2/activities (exige escopo activities:read)")
    ap.add_argument("--desde", help="incremental: negócios com updated_at >= AAAA-MM-DD")
    ap.add_argument("--lote-itens", type=int, default=500, help="itens por chamada da RPC (máx. 1000)")
    ap.add_argument("--escopo", choices=["completo", "recentes"], default="completo",
                    help="completo = tudo (padrão antigo); recentes = abertos mexidos nos últimos --dias + todos os"
                         " ganhos/perdidos + só os contatos, origens e atividades desses negócios")
    ap.add_argument("--dias", type=int, default=90, help="recentes: janela de updated_at dos negócios abertos (padrão 90)")
    ap.add_argument("--com-historico", action="store_true",
                    help="recentes: baixa /v2/deals/{id}/history de cada negócio (1 GET por negócio; desligado por padrão)")
    ap.add_argument("--contatos", choices=["varredura", "individual"], default="varredura",
                    help="recentes: varredura = percorre /v1/contacts (1000/página) e guarda só os referenciados;"
                         " individual = 1 GET /v1/contacts/{id} por contato referenciado")
    a = ap.parse_args()
    if a.escopo == "recentes" and a.desde:
        raise SystemExit("--desde é do escopo completo; no recentes use --dias.")

    env = ler_env()
    token = env.get("CLINT_TOKEN")
    if not token:
        raise SystemExit("Defina CLINT_TOKEN no ambiente (nunca em arquivo do repositório).")
    cl = Clint(token, a.rps)

    if a.contar:
        totais = {
            "grupos": cl.total("/v1/groups"), "origens": cl.total("/v1/origins"), "usuarios": cl.total("/v1/users"),
            "motivos_perda": cl.total("/v1/lost-status"), "tags": cl.total("/v1/tags"),
            "contatos": cl.total("/v1/contacts"),
            "negocios_abertos": cl.total("/v1/deals", {"status": "OPEN"}),
            "negocios_ganhos": cl.total("/v1/deals", {"status": "WON"}),
            "negocios_perdidos": cl.total("/v1/deals", {"status": "LOST"}),
        }
        agora = dt.datetime.now(dt.timezone.utc)
        for d in (30, 90, 180):
            ini = (agora - dt.timedelta(days=d)).strftime("%Y-%m-%dT00:00:00+00:00")
            totais[f"abertos_mexidos_{d}d"] = cl.total("/v1/deals", {"status": "OPEN", "updated_at_start": ini})
        if not a.sem_atividades:
            try:
                totais["atividades"] = cl.total("/v2/activities", v2=True)
            except SystemExit as e:
                totais["atividades"] = f"indisponível ({e})"
        print(json.dumps({"medido_em": dt.datetime.now().isoformat(timespec="seconds"), "totais": totais,
                          "requisicoes": cl.requisicoes}, ensure_ascii=False, indent=2))
        return

    banco = None
    if not a.seco:
        url = env.get("SUPABASE_URL") or env.get("NEXT_PUBLIC_SUPABASE_URL")
        chave = env.get("SUPABASE_SERVICE_ROLE_KEY")   # JWT antigo ou sb_secret_ (aceita em apikey e Bearer; testado)
        if not url or not chave:
            raise SystemExit("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY (ou CLINT_SUPABASE_ENV) para gravar.")
        banco = Banco(url, chave)

    lote = "clint-" + dt.datetime.now().strftime("%Y%m%dT%H%M%S")
    contagens, completo = {}, True
    tam = max(1, min(a.lote_itens, 1000))

    def gravar(tipo, itens, total_api=None, silencioso=False):
        nonlocal completo
        c = contagens.setdefault(tipo, {"api": 0, "baixados": 0, "novos": 0, "alterados": 0})
        if total_api is not None:
            c["api"] += int(total_api)
        c["baixados"] += len(itens)
        if banco:
            for i in range(0, len(itens), tam):
                r = banco.rpc("crm_clint_staging_gravar", {"p_lote": lote, "p_tipo": tipo, "p_itens": itens[i:i + tam]})
                c["novos"] += r.get("novos", 0)
                c["alterados"] += r.get("alterados", 0)
        if not silencioso:
            print(f"  {tipo}: {len(itens)} baixados" + (f" (API anunciou {total_api})" if total_api is not None else ""))

    if banco:
        banco.rpc("crm_clint_staging_lote", {"p_lote": lote, "p_acao": "abrir", "p_contagens": {}})
    inicio = time.monotonic()
    print(f"lote {lote}{' (seco: nada é gravado)' if a.seco else ''} — escopo {a.escopo}"
          + (f", abertos mexidos nos últimos {a.dias} dias" if a.escopo == "recentes" else ""))

    try:
        if a.escopo == "recentes":
            completo = extrair_recentes(a, cl, gravar, contagens, tam) and completo
        else:
            # cadastros
            for tipo, caminho in (("grupo", "/v1/groups"), ("origem", "/v1/origins"), ("usuario", "/v1/users"),
                                  ("motivo", "/v1/lost-status"), ("tag", "/v1/tags")):
                lista, total = cl.paginas(caminho)
                gravar(tipo, com_id(lista, tipo), total)
            gravar("campo", itens_campos(cl.get("/v1/account/fields")))

            # contatos (a API não filtra por atualização: varre tudo)
            lista, total = cl.paginas("/v1/contacts")
            gravar("contato", com_id(lista, "contato"), total)

            # negócios: a API devolve só OPEN por padrão → uma varredura por status
            negocios = []
            for st in ("OPEN", "WON", "LOST"):
                p = {"status": st}
                if a.desde:
                    p["updated_at_start"] = a.desde + "T00:00:00+00:00"
                lista, total = cl.paginas("/v1/deals", p)
                gravar("negocio", com_id(lista, "negocio"), total)
                negocios.extend(lista)

            # histórico (notas, mudanças de etapa/status/dono, atividades concluídas): GET por negócio
            if a.historico != "nenhum":
                alvo = [d for d in negocios if a.historico == "todos" or (d.get("status") or "OPEN") == "OPEN"]
                itens = []
                for k, d in enumerate(alvo, 1):
                    hist, _ = cl.paginas(f"/v2/deals/{d['id']}/history", limite=200, v2=True)
                    for h in hist:
                        if isinstance(h, dict) and h.get("id"):
                            itens.append({"clint_id": f"{d['id']}:{h['id']}"[:200], "pai_id": str(d["id"]), "payload": h})
                    if len(itens) >= tam:
                        gravar("historico", itens)
                        itens = []
                    if k % 200 == 0:
                        print(f"  histórico: {k}/{len(alvo)} negócios")
                if itens:
                    gravar("historico", itens)

            # atividades (exige feature ACTIVITIES_API + escopo activities:read; 403 = segue sem)
            if not a.sem_atividades:
                try:
                    lista, total = cl.paginas("/v2/activities", limite=200, v2=True)
                    itens = [{"clint_id": str(x["id"]), "pai_id": str((x.get("deal") or {}).get("id") or "") or None, "payload": x}
                             for x in lista if isinstance(x, dict) and x.get("id")]
                    gravar("atividade", itens, total)
                except SystemExit as e:
                    print(f"  atividades: puladas ({e})", file=sys.stderr)
                    contagens["atividade"] = {"api": None, "baixados": 0, "erro": "indisponivel"}
    except BaseException:
        completo = False
        if banco:
            banco.rpc("crm_clint_staging_lote", {"p_lote": lote, "p_acao": "incompleto", "p_contagens": contagens})
        raise

    for tipo, c in contagens.items():
        if c.get("api") not in (None, 0) and c["api"] != c["baixados"] and not a.desde:
            completo = False
            print(f"  ATENÇÃO {tipo}: API anunciou {c['api']} e vieram {c['baixados']}", file=sys.stderr)
    if banco:
        banco.rpc("crm_clint_staging_lote", {"p_lote": lote, "p_acao": "completo" if completo else "incompleto",
                                             "p_contagens": contagens})
    print(json.dumps({"lote": lote, "escopo": a.escopo, "situacao": "completo" if completo else "incompleto",
                      "contagens": contagens, "requisicoes_clint": cl.requisicoes,
                      "duracao_s": round(time.monotonic() - inicio, 1)}, ensure_ascii=False, indent=2))
    print("Próximo passo (no banco, como postgres): select crm.clint_preparar_mapas(); revisar arquivo.clint_mapa_*;"
          f" select crm.clint_carregar('{lote}');  -- ensaio")


if __name__ == "__main__":
    main()
