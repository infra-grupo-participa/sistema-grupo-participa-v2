-- Reversão de 20261008161000 (modelo seminario-atm) e de 20261008161100 (cadastro do ATM 1 da Dra. Elaine).
--
-- STATUS: NÃO RODADA. As migrations 20261008161000, 161001 e 161100 foram aplicadas em 08/10/2026; esta reversão desfaz. Rodada dentro do ensaio
-- 20261008161000_ensaio.sql: volta dados.dashboards às colunas e checks de antes e as funções do presencial seguem iguais.
--
-- Ordem: primeiro o cadastro da edição (se existir), depois o modelo. Aborta se houver outro dashboard 'seminario-atm'
-- cadastrado (cadastro de outra edição tem de sair antes, com o mesmo bloco trocando a chave).
-- O gatilho public.tg_carimbar_atualizado_em() NÃO é apagado se outra tabela fora destas o usar.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 1. Cadastro da edição atm-elaine-1-2026-10
do $c$
declare v_chave text := 'atm-elaine-1-2026-10'; v_proj bigint;
begin
  if to_regclass('dados.sessoes') is null then
    return;
  end if;
  select projeto_id into v_proj from dados.dashboards where chave = v_chave;
  delete from dados.sessao_presencas where sessao_id in (select id from dados.sessoes where chave = v_chave);
  delete from dados.sessoes where chave = v_chave;
  delete from dados.dashboard_grupos where chave = v_chave;
  delete from dados.lista_membros where chave = v_chave;
  delete from dados.dashboards where chave = v_chave;
  if v_proj is not null
     and not exists (select 1 from mkt_mensageria.disparos where projeto_id = v_proj)
     and not exists (select 1 from pessoas.eventos where projeto_id = v_proj)
     and not exists (select 1 from pessoas.origens where projeto_id = v_proj)
     and not exists (select 1 from dados.dashboards where projeto_id = v_proj) then
    delete from mkt.projetos where id = v_proj and etiqueta_clickup = v_chave;
  elsif v_proj is not null then
    raise notice 'reversão: projeto % mantido em mkt.projetos (há disparo, evento ou origem apontando para ele)', v_proj;
  end if;
end
$c$;

-- 2. Modelo seminario-atm
do $g$
begin
  if exists (select 1 from dados.dashboards where modelo = 'seminario-atm') then
    raise exception 'reversão: ainda há dashboard seminario-atm cadastrado. Tirar o cadastro antes.';
  end if;
  if exists (select 1 from dados.dashboards where oferta_codigo is null) then
    raise exception 'reversão: há dashboard sem oferta; o NOT NULL de oferta_codigo não volta.';
  end if;
end
$g$;

drop function if exists public.dados_atm_resumo(text), public.dados_atm_leads(text), public.dados_atm_serie_diaria(text),
                        public.dados_atm_disparos_canais(text), public.dados_atm_comparecimento(text),
                        public.dados_atm_pos_live(text);
drop function if exists dados.atm_leads(text), dados.atm_vendas(text), dados.atm_cadastro(text),
                        dados.leads_todos(text, bigint, text);
drop view if exists dados.v_grupo_pessoas;
drop view if exists dados.v_grupo_eventos;
drop table if exists dados.sessao_presencas;
drop table if exists dados.sessoes;
drop table if exists dados.lista_membros;
drop table if exists dados.dashboard_grupos;
drop table if exists dados.ddd_uf;

alter table dados.dashboards drop column if exists ciclo_fecha_em;
alter table dados.dashboards drop column if exists vendas_desde;
alter table dados.dashboards drop column if exists lista_ac_leads;
alter table dados.dashboards alter column oferta_codigo set not null;
comment on column dados.dashboards.oferta_codigo is null;
alter table dados.dashboards drop constraint if exists dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check check (modelo = 'presencial-base');

do $t$
begin
  if to_regprocedure('public.tg_carimbar_atualizado_em()') is not null
     and not exists (select 1 from pg_trigger where tgfoid = to_regprocedure('public.tg_carimbar_atualizado_em()')) then
    drop function public.tg_carimbar_atualizado_em();
  end if;
end
$t$;
