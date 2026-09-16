-- =====================================================================
-- 20260916_remocao_acessos_lembrete_geral
-- Lembrete das 10h volta a ser UMA mensagem no canal (pedido do Victor,
-- 16/09/2026), agrupada por RESPONSÁVEL: cada um marcado uma vez, com os
-- alunos (titular e sócios) e o que falta de cada um. A triagem pendente
-- entra na lista do triador.
-- =====================================================================

create or replace function public.ra_slack_lembrete(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_casos int;
  v_atrasados int;
  v_corpo text;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  if not public.ra_dia_util(v_hoje) then return json_build_object('ok', true, 'texto', null); end if;

  select count(*), count(*) filter (where prazo_em < now())
    into v_casos, v_atrasados
    from public.ra_casos where status in ('aguardando_triagem', 'em_remocao');
  if v_casos = 0 then return json_build_object('ok', true, 'texto', null); end if;

  with pend as (
    -- Uma linha por (responsável, caso, pessoa) com os itens que faltam.
    select i.responsavel_id, c.id caso_id, c.prazo_em, c.teste, p.ordem pordem,
           coalesce(p.nome, 'sem nome') || case when p.papel = 'socio' then ' (sócio)' else '' end as pessoa,
           string_agg(k.rotulo, ', ' order by k.ordem) itens, min(k.ordem) kordem
      from public.ra_itens i
      join public.ra_casos c on c.id = i.caso_id and c.status = 'em_remocao'
      join public.ra_pessoas p on p.id = i.pessoa_id
      join public.ra_itens_catalogo k on k.item = i.item
     where i.situacao = 'pendente'
     group by i.responsavel_id, c.id, c.prazo_em, c.teste, p.id, p.ordem, p.nome, p.papel
    union all
    -- Triagem pendente: conta para o triador, uma linha por caso (titular).
    select v_triador, c.id, c.prazo_em, c.teste, 0,
           coalesce(c.nome, 'sem nome'), 'triagem', 0
      from public.ra_casos c where c.status = 'aguardando_triagem'
  ), linhas as (
    select responsavel_id, prazo_em, caso_id, pordem, kordem,
           '    • <' || v_url || '/relatorios/remocoes?caso=' || caso_id || '|' || pessoa || '>: '
           || regexp_replace(itens, ', ([^,]*)$', ' e \1')
           || case when prazo_em < now() then ' · :red_circle: atrasado'
                   when (prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje
                     then ' · :large_yellow_circle: vence hoje ' || to_char(prazo_em at time zone 'America/Sao_Paulo', 'HH24:MI')
                   else ' · prazo ' || coalesce(to_char(prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), 'sem prazo') end
           || case when teste then ' · teste' else '' end as linha
      from pend
  ), por_resp as (
    select responsavel_id, min(kordem) kordem,
           public.ra_slack_marca(responsavel_id) || E'\n'
           || string_agg(linha, E'\n' order by prazo_em nulls last, caso_id, pordem) as bloco
      from linhas group by responsavel_id
  )
  select string_agg(bloco, E'\n\n' order by kordem) into v_corpo from por_resp;

  return json_build_object('ok', true, 'texto',
    ':alarm_clock: *Remoção de acessos: ' || v_casos || ' caso(s) em aberto'
    || case when v_atrasados > 0 then ', ' || v_atrasados || ' atrasado(s)' else '' end || '*'
    || E'\n\n' || coalesce(v_corpo, 'Nada pendente.'));
end $$;

revoke all on function public.ra_slack_lembrete(text) from public;
grant execute on function public.ra_slack_lembrete(text) to anon, authenticated;
