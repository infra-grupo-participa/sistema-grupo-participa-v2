#!/usr/bin/env python3
"""Gera carga-studio.sql: o minuto a minuto do YouTube Studio (liveViewership_*.csv) das lives já realizadas.

Uso: python3 -I gerar_carga_studio.py <pasta com os .zip do Studio> > carga-studio.sql
Lê só o liveViewership_*.csv de dentro de cada .zip, em memória (nada é extraído em disco; o nome interno tem "/").
Só números saem no SQL (posição em segundos, espectadores, mensagens de chat, reações). Nenhum dado pessoal.
O SQL é uma transação: confere que a live existe e que o título bate com o do .zip, substitui as linhas origem 'studio'
daquele vídeo e confere contagem, pico e soma de chat/reações. Rodar de novo muda 0 linhas.
"""
import csv, io, sys, zipfile
from pathlib import Path

# arquivo do Studio (prefixo "Transmissões ao vivo " e ".zip" retirados; "/" no título vira "_" no nome) -> id do vídeo
LIVES = {
    "Consultoria ao Vivo com Vitor Negrão e Márcia Cristina - 06_10": "fpgmDwBKVcQ",
    "Método Perfeito - Primeiro Pilar - 0 que você precisa dominar antes do primeiro cliente": "Hdsg23VbfHI",
    "Consultoria ao vivo com Joyce Nunes e Naírio Augusto - 13_10": "t0PLYUORt1E",
}
PREFIXO = "Transmissões ao vivo "
CAB = ["Posição na transmissão ao vivo (segundos)", "Espectadores simultâneos na transmissão", "Mensagens do chat ao vivo",
       "Média de espectadores simultâneos", "Envolvimentos ao vivo", "Reações"]


def inteiro(v):
    v = v.strip()
    return None if v == "" else int(v)


def ler(zip_path):
    with zipfile.ZipFile(zip_path) as zf:
        nomes = [n for n in zf.namelist() if n.startswith("liveViewership_") and n.endswith(".csv")]
        if len(nomes) != 1:
            sys.exit(f"{zip_path.name}: esperava 1 liveViewership_*.csv, achei {len(nomes)}")
        linhas = list(csv.reader(io.StringIO(zf.read(nomes[0]).decode("utf-8-sig"))))
    if linhas[0] != CAB:
        sys.exit(f"{zip_path.name}: cabeçalho diferente do esperado: {linhas[0]}")
    saida = []
    for r in linhas[1:]:
        if not r or all(c == "" for c in r):
            continue
        seg, esp, chat, _media, _env, rea = (inteiro(c) for c in r)
        if seg is None or seg < 0 or seg % 60 != 0:
            sys.exit(f"{zip_path.name}: posição inválida {r[0]!r}")
        saida.append((seg, esp, chat, rea))
    return saida


def main(pasta):
    pasta = Path(pasta)
    print("-- Carga do minuto a minuto do Studio (origem 'studio') das lives realizadas. Gerado por gerar_carga_studio.py.")
    print("-- Só números. Idempotente: apaga e regrava as linhas studio do vídeo, na mesma transação.")
    print("begin;")
    print("set local lock_timeout = '5s'; set local statement_timeout = '60s';")
    for stem, vid in LIVES.items():
        arq = pasta / f"{PREFIXO}{stem}.zip"
        if not arq.exists():
            sys.exit(f"não achei {arq.name}")
        dados = ler(arq)
        picos = max((e for _, e, _, _ in dados if e is not None), default=None)
        seg_pico = next(s for s, e, _, _ in dados if e == picos)
        chat = sum(c or 0 for _, _, c, _ in dados)
        rea = sum(r or 0 for _, _, _, r in dados)
        print(f"\n-- {vid}: {len(dados)} linhas, pico {picos} em {seg_pico}s, chat {chat}, reações {rea}")
        print(f"""do $g$ begin
  if not exists (select 1 from dados.black_lives where video_id = '{vid}' and replace(titulo, '/', '_') = {sql_txt(stem)}) then
    raise exception 'live {vid} não cadastrada ou com título diferente do .zip do Studio';
  end if;
end $g$;""")
        print(f"delete from dados.black_live_minuto where video_id = '{vid}' and origem = 'studio';")
        print("insert into dados.black_live_minuto (video_id, origem, seg, espectadores, chat, reacoes) values")
        print(",\n".join(f"  ('{vid}', 'studio', {s}, {nulo(e)}, {nulo(c)}, {nulo(r)})" for s, e, c, r in dados) + ";")
        print(f"""do $c$ begin
  if (select count(*) from dados.black_live_minuto where video_id = '{vid}' and origem = 'studio') <> {len(dados)}
     or (select max(espectadores) from dados.black_live_minuto where video_id = '{vid}' and origem = 'studio') is distinct from {nulo(picos)}
     or (select coalesce(sum(chat), 0) from dados.black_live_minuto where video_id = '{vid}' and origem = 'studio') <> {chat}
     or (select coalesce(sum(reacoes), 0) from dados.black_live_minuto where video_id = '{vid}' and origem = 'studio') <> {rea} then
    raise exception 'conferência da carga de {vid} falhou';
  end if;
end $c$;""")
    print("commit;")


def nulo(v):
    return "null" if v is None else str(v)


def sql_txt(s):
    return "'" + s.replace("'", "''") + "'"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
