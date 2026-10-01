# Carga do Respondi → `respondi.*`

O Respondi não tem API pública: estes scripts usam a API interna do painel (`api.respondi.app/api/`).
Token de sessão em `.tok` (nunca commitado). Os workspaces são 160 (HM), 161 (Diamante), 162 (Aurum), 3380 (Acelera) e 574 (HT).

1. `inv.py` gera o inventário de formulários em `inventario.json`.
2. `dl.py` baixa as respostas para `raw/<slug>.json`, só das famílias relevantes (`fam.py`).
3. `carga.py` normaliza `dados` e `respostas = [{p,v}]` e envia por RPC (`fn_respondi_carga`, migration `20261004b`) com a service role.
   O `.env` vem de `RESPONDI_SUPABASE_ENV`, que precisa ter `SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY`.
4. No banco, `select public.fn_respondi_casar();` e depois `select public.fn_respondi_aplicar(true);`, que é o ensaio.
   Se estiver tudo certo, rode com `false`. Cada alteração fica em `respondi.aplicacoes` e pode ser revertida.

Contrato de `dados`: `email`, `cpf`, `cpf_valido`, `telefone`, `nivel_codigo`, `turma_codigo`, `profissao`,
`facebook`, `instagram`, `youtube`, `cep`, `endereco`, `numero`, `complemento`, `bairro`, `cidade`, `uf_sigla`
e os mesmos com prefixo `socio_` em "Inclusão sócios".
