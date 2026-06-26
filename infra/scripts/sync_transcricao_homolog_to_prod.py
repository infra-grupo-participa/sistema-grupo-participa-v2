"""
Transfere a coluna `transcript` de gp_depoimentos de homologacao para producao.
Match feito por `id` (UUID identico nos dois bancos, pois foram clonados).

Uso:
  python infra/scripts/sync_transcricao_homolog_to_prod.py

Requer as variaveis de ambiente (ou editar as constantes abaixo):
  HOMOLOG_URL / HOMOLOG_SERVICE_KEY
  PROD_URL    / PROD_SERVICE_KEY
"""

import os
import sys
import requests

# ---------------------------------------------------------------------------
# Configuracao — preencha aqui ou exporte as variaveis de ambiente
# ---------------------------------------------------------------------------
HOMOLOG_URL         = os.getenv("HOMOLOG_URL",         "https://msjppzivlxmqclhxqutd.supabase.co")
HOMOLOG_SERVICE_KEY = os.getenv("HOMOLOG_SERVICE_KEY", "")   # service_role key de homolog

PROD_URL            = os.getenv("PROD_URL",            "https://mbvybujpkwuorhtdzcde.supabase.co")
PROD_SERVICE_KEY    = os.getenv("PROD_SERVICE_KEY",    "")   # service_role key de prod
# ---------------------------------------------------------------------------

def headers(service_key: str) -> dict:
    return {
        "apikey": service_key,
        "Authorization": f"Bearer {service_key}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }


def fetch_transcripts_homolog() -> list[dict]:
    """Busca todos os registros com transcript preenchido em homolog."""
    url = f"{HOMOLOG_URL}/rest/v1/gp_depoimentos"
    params = {
        "select": "id,aluno_id,transcript",
        "transcript": "not.is.null",
    }
    r = requests.get(url, headers=headers(HOMOLOG_SERVICE_KEY), params=params)
    r.raise_for_status()
    data = r.json()
    # filtrar vazios por garantia
    return [row for row in data if row.get("transcript")]


def update_transcript_prod(record_id: str, transcript: str) -> bool:
    """Faz PATCH em producao no registro pelo id."""
    url = f"{PROD_URL}/rest/v1/gp_depoimentos"
    params = {"id": f"eq.{record_id}"}
    payload = {"transcript": transcript}
    r = requests.patch(url, headers=headers(PROD_SERVICE_KEY), params=params, json=payload)
    return r.status_code in (200, 204)


def main():
    if not HOMOLOG_SERVICE_KEY or not PROD_SERVICE_KEY:
        print("ERRO: defina HOMOLOG_SERVICE_KEY e PROD_SERVICE_KEY antes de rodar.")
        print("  export HOMOLOG_SERVICE_KEY='eyJ...'")
        print("  export PROD_SERVICE_KEY='eyJ...'")
        sys.exit(1)

    print("Buscando transcripts em homologacao...")
    records = fetch_transcripts_homolog()
    print(f"  {len(records)} registros com transcript encontrados.\n")

    ok = 0
    fail = 0
    for rec in records:
        rid = rec["id"]
        aluno_id = rec.get("aluno_id", "?")
        t_len = len(rec["transcript"])
        success = update_transcript_prod(rid, rec["transcript"])
        status = "OK" if success else "FALHA"
        if success:
            ok += 1
        else:
            fail += 1
        print(f"  [{status}] id={rid[:8]}... aluno={aluno_id[:8]}... ({t_len} chars)")

    print(f"\nConcluido: {ok} atualizados, {fail} falhas.")
    if fail > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
