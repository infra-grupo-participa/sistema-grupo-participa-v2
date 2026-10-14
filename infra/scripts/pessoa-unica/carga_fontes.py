#!/usr/bin/env python3
"""Cargas das fontes que já moram no banco para a pessoa única (migration 20261014170100).

Fontes, na ordem: hotmart_academy, hotmart_escritorio, thb_alunos, aluno_historico, contatos_hm, hm_socios, respondi,
leads_cnhf, leads_workbook, leads_black, crm_negocio. Cada uma retoma de onde parou (cursor em pessoas.carga_execucao).

Uso:
  caffeinate -i python3 carga_fontes.py --rodar todas
  python3 carga_fontes.py --rodar thb_alunos --max-lotes 1
  python3 carga_fontes.py --status

Mesmas regras do carga_ac.py (importa as funções dele): uma chamada por vez, pausa de 2 s entre lotes, saúde conferida
antes de cada lote (chave de desligar, disco até 6 GB, RAM livre, conexões, vigia, lote lento), erro só com código e
1ª linha e execução fechada como 'erro'. Nenhum valor de pessoa vai no texto do SQL (só id de execução, conta e limite).
"""
import argparse, sys, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import carga_ac as c   # noqa: E402

# fonte -> (sql, parâmetros extras, lote padrão). O lote menor na Hotmart é porque a regra de evento do financeiro
# (fin.trajetoria_nucleo) custa ~30 a 80 ms por transação (ensaio de 14/10/2026).
FONTES = {
    'hotmart_academy':    ('select pessoas.carga_fin_hotmart($1::bigint, $2::text, $3::int)', ['academy'], 300),
    'hotmart_escritorio': ('select pessoas.carga_fin_hotmart($1::bigint, $2::text, $3::int)', ['escritorio'], 150),
    'thb_alunos':         ('select pessoas.carga_thb_alunos($1::bigint, $2::int)', [], 1000),
    'aluno_historico':    ('select pessoas.carga_aluno_historico($1::bigint, $2::int)', [], 1000),
    'contatos_hm':        ('select pessoas.carga_contatos_hm($1::bigint, $2::int)', [], 1000),
    'hm_socios':          ('select pessoas.carga_hm_socios($1::bigint, $2::int)', [], 1000),
    'respondi':           ('select pessoas.carga_respondi($1::bigint, $2::int)', [], 500),
    'leads_cnhf':         ('select pessoas.carga_leads($1::bigint, $2::text, $3::int)', ['leads_cnhf'], 1000),
    'leads_workbook':     ('select pessoas.carga_leads($1::bigint, $2::text, $3::int)', ['leads_workbook'], 1000),
    'leads_black':        ('select pessoas.carga_leads($1::bigint, $2::text, $3::int)', ['leads_black'], 1000),
    'crm_negocio':        ('select pessoas.carga_crm_negocio($1::bigint, $2::int)', [], 1000),
}


def fase_fonte(banco, fonte, por, max_lotes, lento_s, ram_min_mb, lote=None):
    sql, extra, padrao = FONTES[fonte]
    n = lote or padrao
    ex = banco.um('select pessoas.carga_abrir($1::text, $2::text, $3::text)', [fonte, 'pessoas', por])
    eid = ex['execucao']
    c.ABERTA['id'] = eid
    c.log(f"{fonte}: execução {eid} {'retomada' if ex['retomada'] else 'nova'}, lote {n}")
    lotes, ultimo_ms = 0, None
    while True:
        if max_lotes and lotes >= max_lotes:
            c.fechar(banco, eid, 'parada', 'max-lotes atingido')
            c.log(f'{fonte}: max-lotes atingido, execução parada')
            return
        if not c.esperar_saude(banco, ultimo_ms, lento_s, ram_min_mb):
            c.fechar(banco, eid, 'parada', 'banco sem folga ou chave desligada')
            raise SystemExit(f'{fonte}: parada por saúde do banco')
        r = banco.um(sql, [eid] + extra + [n])
        ultimo_ms, lotes = r['ms'], lotes + 1
        c.log(f"{fonte} lote {lotes}: {r['lidas']} lidas, {r['pessoas_novas']} pessoas novas, {r['casadas']} casadas, "
              f"{r['puladas']} puladas, {r['eventos']} eventos, {r['relacoes']} relações, {r['ms']} ms; "
              f"disco {c.ULTIMA.get('disco_gb')} GB, RAM livre {c.ULTIMA.get('ram_livre_mb')} MB")
        if r['lidas'] == 0:
            c.fechar(banco, eid, 'ok')
            c.log(f'{fonte}: fim')
            return
        time.sleep(2)


def status(banco):
    for r in banco.sql("""select fonte, fase, status, lotes, lidas, inseridas, atualizadas, iguais, iniciada_em, atualizada_em
                          from pessoas.carga_execucao where fonte <> 'activecampaign' order by id"""):
        print(r)
    print(banco.um('select pessoas.carga_contagem()'))


def main():
    a = argparse.ArgumentParser()
    a.add_argument('--rodar', choices=['todas'] + list(FONTES))
    a.add_argument('--status', action='store_true')
    a.add_argument('--lote', type=int, default=0)
    a.add_argument('--max-lotes', type=int, default=0)
    a.add_argument('--lento', type=float, default=45.0)
    a.add_argument('--ram-min', type=float, default=150.0)
    a.add_argument('--env-file', default=next((str(p / 'controle-de-eventos/.env') for p in Path(__file__).resolve().parents
                                               if (p / 'controle-de-eventos/.env').exists()), None))
    a.add_argument('--por', default='carga_fontes.py')
    x = a.parse_args()
    if x.lote and not 1 <= x.lote <= 2000:
        sys.exit('--lote entre 1 e 2000')
    banco = c.Banco(c.token(x.env_file), None if x.status else c.chave_metricas(x.env_file))
    if x.status or not x.rodar:
        return status(banco)
    fontes = list(FONTES) if x.rodar == 'todas' else [x.rodar]
    for f in fontes:
        if not c.rodar_fase(f, lambda b, f=f: fase_fonte(b, f, x.por, x.max_lotes, x.lento, x.ram_min, x.lote or None), banco):
            status(banco)
            sys.exit(1)
    status(banco)


if __name__ == '__main__':
    main()
