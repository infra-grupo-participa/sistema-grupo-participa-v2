# Remoção de Acessos

Módulo em `/educacional/remocoes` (pedido do Victor, 16/09/2026; o endereço antigo `/relatorios/remocoes` redireciona). Organiza a retirada de acesso de
quem pede reembolso ou dá chargeback no **Holding Masters** (produtos 5064314 e 3507214) e, desde a migration
`20261006134133`, no **Acelera Holding** (produto 8381847, ver a seção própria abaixo).

## Ciclo

1. O webhook da Hotmart grava o status em `public.compras`. O gatilho `trg_zzzz_ra_caso` abre o caso:
   - `REFUNDED` → reembolso, `CHARGEBACK` → chargeback: caso **aguardando triagem**;
   - `PROTESTED` → disputa: só **alerta**, sem checklist.
   O gatilho nunca derruba a gravação da compra (erro vira `warning` no log).
2. **Triagem** (só o triador, `ra_config.triador_id`, hoje o Victor): verifica se a pessoa tinha acesso
   antes (regra da Central: reembolso volta ao acesso antigo quando ele ainda vale).
   - "Remover acessos" cria o checklist de remoção.
   - "Não remover" exige a **expiração antiga** (pré-preenchida pelo histórico da base quando dá) e, se mudou,
     a instrução antiga. O caso fica em **Ajustar acesso**, com dois itens do triador por pessoa (Central e
     Base de Alunos), e só conclui quando os dois são marcados. Sócios acompanham a data do titular.
     O ajuste da Base é manual por decisão do Victor; `ra_casos` guarda as datas para automatizar depois.
3. **Checklist** para o titular e cada sócio (`socio_de_aluno_id`, ou nome do titular quando o sócio não tem vínculo).
   Cada item tem um responsável (`ra_itens_catalogo`) e **só ele marca**. O triador pode corrigir
   (e, desde 05/10/2026, quem está em `ra_marcadores` também: hoje a Isabela Teixeira, a pedido do Victor;
   ela marca qualquer item mas não faz triagem)
   (`corrigido = true`, fica no histórico). O item do sistema do Programa de Implementação só entra
   se a pessoa é do programa (espaço `holding_masters_implementacao`, ajustável na triagem).
4. Último item marcado → caso **concluído**. Desmarcar reabre.
5. **Desfazer triagem** (só o triador, `ra_desfazer_triagem`): volta o caso para aguardando triagem e apaga os
   itens pendentes. Bloqueia se algum item já foi marcado (desmarcar antes). Se o Slack já tinha avisado,
   responde na thread que a triagem foi desfeita.

**Prazo:** 1 dia útil a partir do evento (`ra_calcular_prazo`). Horário útil 9h às 18h de segunda a sexta,
sem os feriados de `ra_feriados` (nacionais, Carnaval e Corpus Christi, 2026 e 2027). Fora do horário, conta da próxima abertura.

## Acesso

`ra_pode_ver()` = dev, admin, ou gestor/operador com a área `remocao_acessos` (catálogo 3.5).
Visualizador geral **não** entra (dado pessoal). Tabelas `ra_*` fechadas; tudo por função SECURITY DEFINER.

## Slack (n8n)

Toda mudança de caso chama na hora o webhook do n8n (`trg_ra_avisar_n8n` + pg_net, URL em
`ra_config.n8n_webhook_url`); o disparo de 5 em 5 min é a garantia. O n8n, com a chave anon, reserva o que
vai postar com `ra_slack_reservar(segredo)` (reserva de 2 min, para os dois caminhos não duplicarem), posta
e confirma com `ra_slack_confirmar(segredo, caso, aviso, ts)`. A mensagem sai em 2 a 5 segundos. O aviso `novo`/`alerta` abre a thread; `liberado`,
`fechado` e `concluido` respondem nela. `ra_slack_lembrete(segredo)` monta o lembrete do dia útil.
O segredo está em `ra_config.slack_segredo` (não é lido pelo PostgREST). Quem é marcado vem de `ra_slack`.

Migration: `infra/supabase/migrations/20260916_remocao_acessos.sql`.

## Webhook próprio (`remocao-acessos-webhook`)

URL para a Hotmart: `https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/remocao-acessos-webhook`
(eventos: reembolso, chargeback e protesto; produto Holding Masters). Confere o `HOTMART_HOTTOK` e passa
o payload para `ra_receber_hotmart`. Não grava compra, não mexe no financeiro, não avisa o canal do time.
Todo evento recebido fica em `ra_webhook_eventos` com o resultado (caso criado, ignorado e por quê).

O caso nasce do payload; se a transação existe em `compras`, fica ligada. O gatilho em `compras` segue
como rede de segurança, e os dois caminhos viram um caso só.

**Modo de teste** (`ra_config.webhook_modo = 'teste'`): transação que não existe em `compras` vira caso
**de teste** (aceita qualquer produto, selo "Teste" na tela, prefixo TESTE no Slack, botão para apagar;
reenviar a mesma transação recria o caso). Em `producao`, só Holding Masters e Acelera Holding, e nada é teste.
Deploy: `verify_jwt = false`. Migration: `20260916_remocao_acessos_webhook.sql`.

## Acelera Holding (produto Hotmart 8381847)

> **Situação (06/10/2026): NÃO APLICADO.** Migrations `20261006134133_ra_acelera_holding.sql` (estrutura, funções,
> reprocessamento) e `20261006134134_ra_acelera_carga.sql` (carga das 41), nessa ordem, ensaiadas em `begin … rollback`
> sem sobra. Detalhe, ensaio, `explain` e reversão nos `.explain.md` de cada uma.

**Linha de produto.** `ra_casos.linha` e `ra_itens_catalogo.linha` valem `hm` (o que já existia, default) ou
`acelera`. O Holding Masters não muda: `ra_triar` só usa itens `linha = 'hm'`.

**Itens** (todos do Thomas Henrique, fluxo `remocao`): `acelera_grupo_informes` "Grupo de informes",
`acelera_area_membros` "Área de membros (Hotmart)", `acelera_obvio` "Obvio". São outros grupo e Obvio, não os do HM.
Marcam o Thomas e quem está em `ra_marcadores` (Isabela); o triador corrige como no HM.

**Sem triagem.** Reembolso ou chargeback abre o caso direto em **Em remoção** (`decisao = remover`), 1 pessoa (o
comprador, sem sócios), os 3 itens e prazo de 1 dia útil. `ra_triar` e `ra_desfazer_triagem` recusam caso do Acelera.
Disputa (protesto) vira só **alerta**, como no HM.

**Regra de recompra.** Se a pessoa tem **outra** compra do 8381847 `APPROVED`/`COMPLETE`/`COMPLETED`
(`fin.hotmart_transacoes` da conta `academy` ou `public.compras`), casando por e-mail, documento ou telefone (com ou
sem 55), o reembolso não abre checklist: vira **alerta**, com `sugestao.motivo` explicando e
`sugestao.compras_anteriores` com as compras (mesmo formato do HM: transacao, produto, oferta, valor, status, data). A regra é uma função só para
o webhook e a carga: `ra_acelera_compras_validas`.

**Transação de outro produto.** Se a transação já existe no financeiro (qualquer conta) ou em `public.compras` com outro
produto, o caso do Acelera nasce **alerta**, sem itens, com a chave `<transação> (conflito de produto)`, para não ocupar
o lugar do caso do HM.

**Slack.** O aviso `novo` sai com o título "Reembolso/Chargeback no Acelera Holding: remover do Grupo de informes, da
Área de membros (Hotmart) e do Obvio", marcando o Thomas; não há aviso `liberado`; `concluido` responde na thread.
Caso com `avisar_slack = false` fica fora do Slack, do lembrete e da chamada ao n8n. O n8n não muda.
Nome, e-mail e produto passam por `ra_slack_esc` (`&`, `<`, `>` viram `&amp;`, `&lt;`, `&gt;`) em todas as mensagens,
HM incluído: texto vindo da Hotmart não vira `<!channel>` nem link.

**Webhook.** O mesmo do HM: `https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/remocao-acessos-webhook`, cadastrado
no produto 8381847 com os eventos `PURCHASE_REFUNDED`, `PURCHASE_CHARGEBACK` e `PURCHASE_PROTEST`. A função confere um
hottok só (`HOTMART_HOTTOK`); que o da conta do Acelera é o mesmo **não foi conferido**: conferir no primeiro evento do
8381847 em `ra_webhook_eventos` (recusado por hottok = é outro).
A venda do Acelera **não** entra em `public.compras`; o webhook é o único caminho automático. Eventos do 8381847 que
chegaram antes da migration (`ignorado: produto não é Holding Masters`) são reprocessados por ela, com Slack normal.

**Carga silenciosa (`20261006134134`).** As 41 pessoas com reembolso sem recompra (aba "Reembolsos sem recompra" da
planilha `1Y40pTGVAPgdH8lJDvbUgQZSdcwPYYsmrU-bBUnejlb4`) entram como casos com `origem = 'carga'`,
`avisar_slack = false` e `prazo_em` nulo, 1 por pessoa. A carga aborta, listando só IDs de transação, se a regra e a
planilha divergirem. Quem já tem caso do Acelera não ganha outro; rodar de novo não duplica.

**Contrato com a tela.** `ra_fila`, `ra_caso` (caso e itens) e `ra_responsaveis` (por item) devolvem `linha`;
`ra_meu_papel.meus_itens` é `[{item, rotulo, linha}]`; `prazo_em` pode vir nulo; `origem` pode ser `carga`.

**Data nos casos importados.** Em `origem = 'carga'` o `ocorrido_em` é a data da compra (o financeiro não guarda a do reembolso): a ficha mostra "Compra em" (`rotuloDataCaso` em `domain/caso.ts`), a fila acrescenta "data da compra" sob a data e a descrição da aba Acelera avisa.

**Conferência depois de aplicar:**

```sql
select linha, origem, status, avisar_slack, count(*)
from public.ra_casos group by 1, 2, 3, 4 order by 1, 2, 3;
-- esperado logo após as duas: hm = os casos de antes; acelera/carga/em_remocao/false = 41
-- (+ os reprocessados, se algum evento do 8381847 tiver chegado antes)
select resultado, count(*) from public.ra_webhook_eventos where produto_id = '8381847' group by 1;
```
