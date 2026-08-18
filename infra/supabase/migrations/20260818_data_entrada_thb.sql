-- Data de entrada no Time Holding Brasil na base de alunos.
--
-- Por que existe: thb_alunos.data_compra guarda a compra que dá o acesso VIGENTE, não a
-- primeira. Quem entrou na T14 em 2022 e recomprou em 2026 tem data_compra de 2026, e a
-- ficha 360 não conseguia responder "desde quando essa pessoa é aluna".
--
-- A Central de Acessos 2026 já tem esse dado em 1.617 pessoas, calculado a partir da venda
-- mais antiga na Hotmart e, para sócio, herdado do titular. Esta coluna é o destino dele.
--
-- Só adiciona coluna: não altera nada existente e não afeta o funil de ativação.
alter table public.thb_alunos
  add column if not exists data_entrada_thb date;

comment on column public.thb_alunos.data_entrada_thb is
  'Data em que a pessoa entrou no THB (1a compra que a tornou aluna). Origem: Central de Acessos 2026. Para socio, herdada do titular. Diferente de data_compra, que e a compra do acesso vigente.';
