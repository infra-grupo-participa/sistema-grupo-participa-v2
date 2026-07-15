#!/usr/bin/env python3
"""
Backfill de valor_liquido / taxa_processamento em public.compras a partir do
"Relatório de Vendas" (Sales History) exportado da Hotmart.

Contexto: o webhook `hotmart-events-webhook` só passou a gravar líquido/taxa em
2026-07-15 (deriva de data.commissions[]). Tudo que entrou antes tem
valor_liquido NULL, e `fn_fin_faturamento_diario`/`vw_fin_contas_receber` fazem
coalesce(valor_liquido, preco) → exibiam líquido=bruto (taxa 0). Este script
reconstrói o histórico a partir do CSV oficial da Hotmart.

O relatório é POR PRODUTO: um export cobre um product_id (ex.: 5064314 = Holding
Masters). Para cobrir renovação HM (3507214), Holding Total, ETHB etc., exporte
um relatório por produto e rode este script para cada um.

Mapeamento de colunas (delimitador ';', encoding latin-1):
  0  Código da transação            -> compras.hotmart_transaction (HP...)
  16 Faturamento bruto (sem impostos)
  19 Faturamento líquido do Produtor -> compras.valor_liquido
  23 Taxa de processamento           -> compras.taxa_processamento  (= bruto - líquido)

O UPDATE é idempotente: só grava onde valor_liquido IS NULL (não sobrescreve
dado já enriquecido). taxa = bruto - líquido bate 100% no CSV auditado.

Uso:
    python hotmart_backfill_liquido.py <caminho.csv> [tamanho_lote]

Saída: arquivos backfill_NN.sql no diretório atual. Aplique cada um no Supabase
(SQL editor ou MCP execute_sql). Não conecta ao banco — gera SQL revisável.
"""
import csv
import sys
import os

COL_TX, COL_BRUTO, COL_LIQ, COL_TAXA = 0, 16, 19, 23


def parse(csv_path):
    rows = list(csv.reader(open(csv_path, encoding="latin-1"), delimiter=";"))
    data, descartadas, mismatch = {}, 0, 0
    for r in rows[1:]:
        tx = r[COL_TX].strip()
        if not tx.startswith("HP"):
            descartadas += 1
            continue
        try:
            liq = round(float(r[COL_LIQ]), 2)
            tax = round(float(r[COL_TAXA]), 2)
            bruto = round(float(r[COL_BRUTO]), 2)
        except (ValueError, IndexError):
            descartadas += 1
            continue
        if liq <= 0:
            continue
        if abs((bruto - liq) - tax) > 0.05:
            mismatch += 1  # taxa não bate bruto-líquido: revisar coluna
        data[tx] = (liq, tax)  # dedup: 1 por transação
    return data, len(rows) - 1, descartadas, mismatch


def emit(data, batch=500, out_dir="."):
    items = list(data.items())
    n = 0
    for i in range(0, len(items), batch):
        chunk = items[i : i + batch]
        vals = ",".join(f"('{tx}',{liq},{tax})" for tx, (liq, tax) in chunk)
        sql = (
            "UPDATE public.compras c SET valor_liquido=v.liq, taxa_processamento=v.tax "
            f"FROM (VALUES {vals}) AS v(tx,liq,tax) "
            "WHERE c.hotmart_transaction=v.tx AND c.valor_liquido IS NULL;"
        )
        n += 1
        path = os.path.join(out_dir, f"backfill_{n:02}.sql")
        open(path, "w", encoding="utf-8").write(sql)
        print(f"  gerado {path} ({len(chunk)} transações)")
    return n


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    csv_path = sys.argv[1]
    batch = int(sys.argv[2]) if len(sys.argv) > 2 else 500
    data, total, descartadas, mismatch = parse(csv_path)
    print(f"CSV: {total} linhas | {len(data)} transações válidas | {descartadas} descartadas")
    if mismatch:
        print(f"  AVISO: {mismatch} linhas onde |bruto-líquido - taxa| > 0.05 — confira as colunas do export")
    emit(data, batch)


if __name__ == "__main__":
    main()
