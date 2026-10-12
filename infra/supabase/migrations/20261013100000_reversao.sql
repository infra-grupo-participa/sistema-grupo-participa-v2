-- Reversão de 20261013100000. Numa transação. ANTES: reverter a 20261013110000 (B), que usa dados.black_cadastro e grava
-- marcações de teste com a chave da Black (FK em dados.dashboards; o delete abaixo falha se ainda houver linha filha).
-- O dashboard da Black volta a não ter cadastro (a tela cai em "dashboard não cadastrado").
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists public.dados_black_trafego(text, date, date);
drop function if exists dados.black_cadastro(text);
delete from dados.dashboards where chave = 'black-friday-2026-10';
-- falha de propósito se outra linha tiver passado a usar o modelo jornada-captacao
alter table dados.dashboards drop constraint dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check
  check (modelo = any (array['presencial-base'::text, 'seminario-atm'::text]));
