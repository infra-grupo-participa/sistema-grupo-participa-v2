-- 20261005d — Placas: guarda o id da reunião Zoom e a hora agendada da cutucada.
--
-- public.thb_placas_solicitacoes tem 191 linhas (medido 01/10/2026).
-- Duas colunas novas, ambas anuláveis e sem default: o ADD COLUMN é só
-- metadado (não reescreve a tabela) e nenhuma linha existente muda.
-- Sem índice: com 191 linhas o planner faz Seq Scan de qualquer jeito
-- (prova por explain (analyze) fica com quem aplica).

alter table public.thb_placas_solicitacoes
  add column if not exists zoom_meeting_id text,
  add column if not exists cutucada_agendar_at timestamptz;

comment on column public.thb_placas_solicitacoes.zoom_meeting_id is
  'Id da reunião Zoom criada para a entrevista da placa. Permite atualizar/cancelar a reunião pela API do Zoom sem depender de entrevista_link. Null = reunião não criada pelo sistema.';

comment on column public.thb_placas_solicitacoes.cutucada_agendar_at is
  'Momento em que a cutucada (lembrete ao aluno com solicitação parada) deve ser disparada. Null = nenhuma cutucada agendada.';

-- REVERSÃO (apaga os dados gravados nas duas colunas — exportar antes se já houver uso):
--   alter table public.thb_placas_solicitacoes
--     drop column if exists cutucada_agendar_at,
--     drop column if exists zoom_meeting_id;
