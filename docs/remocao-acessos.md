# Remoção de Acessos

Módulo em `/relatorios/remocoes` (pedido do Victor, 16/09/2026). Organiza a retirada de acesso de
quem pede reembolso ou dá chargeback no **Holding Masters** (produtos 5064314 e 3507214).

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
reenviar a mesma transação recria o caso). Em `producao`, só Holding Masters e nada é teste.
Deploy: `verify_jwt = false`. Migration: `20260916_remocao_acessos_webhook.sql`.
