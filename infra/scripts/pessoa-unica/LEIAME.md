# Cargas da pessoa única

`carga_ac.py`: ActiveCampaign completo → `pessoas` (migration `20261014170000`). Leia o
`infra/supabase/migrations/20261014170000.explain.md` antes de rodar. Em resumo:

- `python3 carga_ac.py --status`: execuções e contagens.
- `python3 carga_ac.py --ensaio 100`: amostra real numa transação desfeita (só antes de aplicar as migrations).
- `caffeinate -i python3 carga_ac.py --rodar tudo`: a carga (catálogo, estágio, pessoas). Retoma de onde parou.
- Parar: `update pessoas.carga_chave set ligada = false where fonte = 'activecampaign';`

Credencial: `SUPABASE_ACCESS_TOKEN` (Management API) ou `--env-file`. A chave do AC vem do Vault. Saída só com contagens.
