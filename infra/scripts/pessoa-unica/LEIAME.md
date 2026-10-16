# Cargas da pessoa única

`carga_ac.py`: ActiveCampaign completo → `pessoas` (migration `20261014170000`). Leia o
`infra/supabase/migrations/20261014170000.explain.md` antes de rodar. Em resumo:

- `python3 carga_ac.py --status`: execuções e contagens.
- `python3 carga_ac.py --ensaio 300`: amostra real (até 500) passada como parâmetro a `pessoas.carga_ensaio($1)`, que
  roda tudo e desfaz (rollback interno, sem erro). Exige a 170000 aplicada.
- `caffeinate -i python3 carga_ac.py --rodar tudo --lote 500`: a carga (catálogo, estágio, pessoas). Retoma de onde parou.
- Parar: `update pessoas.carga_chave set ligada = false where fonte = 'activecampaign';`

Credencial: `SUPABASE_ACCESS_TOKEN` (Management API) e `SUPABASE_SERVICE_ROLE_KEY` (só para ler a RAM nas métricas), ou
`--env-file`. A chave do AC vem do Vault.

## Dado pessoal (regras do script, revisadas pelo pentester em 14/10/2026)

- O lote vai como **parâmetro ligado** da Management API, nunca no texto do SQL. O Postgres do projeto registra o texto da
  instrução que falha (`log_min_error_statement = error`) e toda instrução com DDL (`log_statement = ddl`), mas não o valor
  do parâmetro (`log_parameter_max_length_on_error = 0`). Conferido em 14/10/2026.
- Erro do banco sai só com o SQLSTATE e a 1ª linha (até 200 caracteres). DETAIL e CONTEXT, que podem trazer a linha com
  e-mail, telefone ou nome, nunca são impressos. Erro numa fase fecha a execução como `erro`.
- Ensaio com dado real termina em rollback, nunca em erro.

## Prazo de limpeza do estágio `pessoas.ac_contato` (PROPOSTA, decide o Victor)

O estágio guarda, por contato, e-mail, telefone e nome (cópia do que já vai para `pessoas.identificadores` e
`pessoas.pessoas`) e os campos da pesquisa da SV e o WhatsApp crus. Não pode ficar para sempre (LGPD: guardar só o necessário).

| Quando | O que | Por quê |
|---|---|---|
| D+2 depois da carga terminar (fase `pessoas` com status `ok`) e da conferência das contagens | `update pessoas.ac_contato set email = null, telefone = null, nome = null` em lotes de 2.000 (`where email is not null`, com IS DISTINCT FROM implícito no filtro) | já estão em `identificadores`/`pessoas`; o estágio continua servindo para listas, tags e descadastro pelo `contact_id` e `pessoa_id` |
| Até 30 dias depois da carga, ou quando os atributos (ETAPA 5) lerem os campos, o que vier primeiro | `campos = '{}'` | a pesquisa da SV e o WhatsApp passam para o atributo da pessoa (com regra no dicionário) e saem do estágio |
| Recarga incremental (se houver) | o script volta a gravar e-mail/telefone/nome só durante a carga, e a limpeza de D+2 roda de novo | |

Nunca `truncate` nem `drop` de linha: a tabela guarda o vínculo `contact_id` → `pessoa_id`, que é o que permite recarregar
sem duplicar. A limpeza vira migration própria com ensaio, e entra no DIARIO-DO-BANCO.
