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
Opções: --rps 2 (requisições/s), --historico todos|abertos|nenhum, --sem-atividades, --lote-itens 500.

Idempotente: reextrair o mesmo dado = 0 novos (md5 do payload). O lote só fecha como 'completo' se cada recurso
paginado trouxe exatamente o totalCount que a API anunciou; senão 'incompleto' (e a carga real recusa o lote).
"""
import argparse
import datetime as dt
import json
import os
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
            except (urllib.error.URLError, TimeoutError) as e:
                print(f"  aviso: rede ({e}) em {caminho}; nova tentativa em {espera:.0f}s", file=sys.stderr)
                time.sleep(espera)
                espera = min(espera * 2, 120)
        raise SystemExit(f"Clint: desisti de {caminho} depois de {tentativas} tentativas")

    def paginas(self, caminho, params=None, limite=500, v2=False):
        """Percorre página a página. Devolve (itens, total_anunciado)."""
        params = dict(params or {})
        pagina, itens, total, max_pag = 1, [], None, None
        while True:
            params.update({"page": pagina, "limit": limite})
            r = self.get(caminho, params)
            if r is None:
                break
            dados = r.get("data") or []
            itens.extend(dados)
            if total is None:
                total = r.get("total_count" if v2 else "totalCount")
                tp = r.get("total_pages" if v2 else "totalPages")
                max_pag = (tp or 0) + 2           # trava contra laço infinito se a API errar o hasNext
            tem_mais = r.get("has_next" if v2 else "hasNext")
            if not tem_mais or not dados or pagina >= (max_pag or 10**6):
                break
            pagina += 1
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
    a = ap.parse_args()

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
        url, chave = env.get("SUPABASE_URL"), env.get("SUPABASE_SERVICE_ROLE_KEY")
        if not url or not chave:
            raise SystemExit("Defina SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY (ou CLINT_SUPABASE_ENV) para gravar.")
        banco = Banco(url, chave)

    lote = "clint-" + dt.datetime.now().strftime("%Y%m%dT%H%M%S")
    contagens, completo = {}, True
    tam = max(1, min(a.lote_itens, 1000))

    def gravar(tipo, itens, total_api=None):
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
        print(f"  {tipo}: {len(itens)} baixados" + (f" (API anunciou {total_api})" if total_api is not None else ""))

    if banco:
        banco.rpc("crm_clint_staging_lote", {"p_lote": lote, "p_acao": "abrir", "p_contagens": {}})
    print(f"lote {lote}{' (seco: nada é gravado)' if a.seco else ''}")

    try:
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
    print(json.dumps({"lote": lote, "situacao": "completo" if completo else "incompleto", "contagens": contagens,
                      "requisicoes_clint": cl.requisicoes}, ensure_ascii=False, indent=2))
    print("Próximo passo (no banco, como postgres): select crm.clint_preparar_mapas(); revisar arquivo.clint_mapa_*;"
          f" select crm.clint_carregar('{lote}');  -- ensaio")


if __name__ == "__main__":
    main()
