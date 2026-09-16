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
   "Mantém acesso antigo" encerra; "Remover acessos" cria o checklist.
3. **Checklist** para o titular e cada sócio (`socio_de_aluno_id`, ou nome do titular quando o sócio não tem vínculo).
   Cada item tem um responsável (`ra_itens_catalogo`) e **só ele marca**. O triador pode corrigir
   (`corrigido = true`, fica no histórico). O item do sistema do Programa de Implementação só entra
   se a pessoa é do programa (espaço `holding_masters_implementacao`, ajustável na triagem).
4. Último item marcado → caso **concluído**. Desmarcar reabre.

**Prazo:** 1 dia útil a partir do evento (`ra_calcular_prazo`). Horário útil 9h às 18h de segunda a sexta,
sem os feriados de `ra_feriados` (nacionais, Carnaval e Corpus Christi, 2026 e 2027). Fora do horário, conta da próxima abertura.

## Acesso

`ra_pode_ver()` = dev, admin, ou gestor/operador com a área `remocao_acessos` (catálogo 3.5).
Visualizador geral **não** entra (dado pessoal). Tabelas `ra_*` fechadas; tudo por função SECURITY DEFINER.

## Slack (n8n)

O n8n chama, com a chave anon, `ra_slack_pendentes(segredo)`, posta cada mensagem e confirma com
`ra_slack_confirmar(segredo, caso, aviso, ts)`. O aviso `novo`/`alerta` abre a thread; `liberado`,
`fechado` e `concluido` respondem nela. `ra_slack_lembrete(segredo)` monta o lembrete do dia útil.
O segredo está em `ra_config.slack_segredo` (não é lido pelo PostgREST). Quem é marcado vem de `ra_slack`.

Migration: `infra/supabase/migrations/20260916_remocao_acessos.sql`.
