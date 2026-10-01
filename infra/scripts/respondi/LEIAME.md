# Carga do Respondi → `respondi.*`

## Caminho canônico: Edge Function `respondi-sync` (diária)

Desde a `20261004f`, o cron `respondi-sync` (09:10 UTC) chama a Edge `infra/supabase/functions/respondi-sync`, que
loga no Respondi, percorre os workspaces, baixa só o formulário cujo `respondents_count` mudou, grava por
`fn_respondi_carga`, roda `fn_respondi_casar()` e `fn_respondi_aplicar(false)`. Se `casadas` cair mais de 2%, não
aplica e responde 500. Credenciais no Vault: `respondi_email`, `respondi_senha` (cadastrada à mão, nunca em arquivo)
e `respondi_sync_chave`. Desligar: `select cron.unschedule('respondi-sync');`.

A normalização da Edge (`normaliza.ts`) é porte fiel do `carga.py` (prova: `normaliza.test.ts` compara com a saída
do Python). **Mudou a regra aqui? Mude lá também e regere o fixture.**

## Python: carga manual e acervo completo

Use só para recarregar o acervo inteiro ou investigar. Diferença: o `carga.py` grava `n_respostas` = respostas
concluídas baixadas; a Edge grava `respondents_count` da API. Depois de uma carga pelo Python, a Edge rebaixa uma
vez os formulários em que os dois diferem.

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
