-- =====================================================================
-- 20260916_remocao_acessos_formatacao
-- Mensagens com mais respiro (pedido do Victor, 16/09/2026): um bloco por
-- assunto (pessoas, compra, sugestão, prazo) e um bloco por pessoa marcada,
-- com linha em branco entre eles.
-- =====================================================================

-- Responsáveis em blocos separados por linha em branco:
--   @Thomas
--   Searchie e Obvio
create or replace function public.ra_slack_responsaveis(p_caso uuid, p_pendentes boolean)
returns text language sql stable security definer set search_path to 'public' as $$
  with base as (
    select i.responsavel_id, k.rotulo, k.ordem, i.pessoa_id
      from public.ra_itens i join public.ra_itens_catalogo k on k.item = i.item
     where i.caso_id = p_caso and (not p_pendentes or i.situacao = 'pendente')
  ), total as (
    select count(*) n from public.ra_pessoas where caso_id = p_caso
  ), por_resp as (
    select b.responsavel_id, min(b.ordem) ordem,
           (select string_agg(r.rotulo, ', ' order by r.ordem)
              from (select distinct b2.rotulo, b2.ordem from base b2 where b2.responsavel_id = b.responsavel_id) r) itens,
           count(distinct b.pessoa_id) pessoas,
           (select string_agg(split_part(coalesce(p.nome, 'sem nome'), ' ', 1), ', ' order by p.ordem)
              from public.ra_pessoas p
             where p.id in (select b3.pessoa_id from base b3 where b3.responsavel_id = b.responsavel_id)) nomes
      from base b group by b.responsavel_id
  )
  select string_agg(public.ra_slack_marca(pr.responsavel_id) || E'\n' || regexp_replace(pr.itens, ', ([^,]*)$', ' e \1')
                    || case when p_pendentes and pr.pessoas < (select n from total) then ' (falta: ' || pr.nomes || ')' else '' end,
                    E'\n\n' order by pr.ordem)
    from por_resp pr;
$$;

create or replace function public.ra_slack_pendentes_base(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_out json;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;

  with base as (
    select c.*, to_char(c.ocorrido_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando,
           to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as prazo,
           '<' || v_url || '/relatorios/remocoes?caso=' || c.id || '|Abrir no sistema>' as link
      from public.ra_casos c
  ),
  msgs as (
    -- Disputa: só alerta, marca o triador.
    select b.id as caso_id, 'alerta' as aviso, null::text as thread_ts, 1 as ordem,
           ':warning: *Disputa aberta no HM*' || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || 'Ainda não é reembolso nem chargeback.' || E'\n' || b.link as texto
      from base b where b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
    union all
    -- Caso novo: marca só o triador.
    select b.id, 'novo', null, 1,
           ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente*' || E'\n'
           || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
           || case when b.eh_programa then E'\n' || 'Programa de Implementação' else '' end || E'\n\n'
           || '*Sugestão:* ' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || E'\n' || coalesce(b.sugestao->>'motivo', '') || E'\n\n'
           || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n' || b.link
      from base b where b.tipo <> 'disputa' and not (b.slack_avisos ? 'novo')
    union all
    -- Triagem: manter acesso.
    select b.id, 'fechado', b.slack_ts, 2,
           ':white_check_mark: *Mantém o acesso antigo.* Nada a remover.'
           || coalesce(E'\n' || b.decisao_obs, '')
      from base b where b.status = 'mantem_acesso' and b.slack_ts is not null and not (b.slack_avisos ? 'fechado')
    union all
    -- Triagem: remoção liberada. Pessoas uma vez, responsáveis uma vez.
    select b.id, 'liberado', b.slack_ts, 2,
           ':scissors: *Remover acessos*' || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
           || 'Marquem no sistema quando removerem.' || E'\n' || b.link
      from base b where b.status in ('em_remocao', 'concluido') and b.slack_ts is not null
                    and not (b.slack_avisos ? 'liberado')
    union all
    -- Concluído.
    select b.id, 'concluido', b.slack_ts, 3,
           ':white_check_mark: *Acessos removidos*' || E'\n\n'
           || (select string_agg('• ' || linha, E'\n') from (
                 select coalesce(mp.nome, 'sem nome') || ' ' || to_char(max(i.marcado_em) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as linha
                   from public.ra_itens i left join public.perfis mp on mp.id = i.marcado_por
                  where i.caso_id = b.id
                  group by mp.nome) z)
      from base b where b.status = 'concluido' and b.slack_ts is not null
                    and (b.slack_avisos ? 'liberado') and not (b.slack_avisos ? 'concluido')
  )
  select json_build_object('ok', true, 'mensagens',
           coalesce(json_agg(json_build_object('caso_id', m.caso_id, 'aviso', m.aviso,
                                               'thread_ts', m.thread_ts, 'texto', m.texto) order by m.ordem), '[]'::json))
    into v_out from msgs m;
  return v_out;
end $$;

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
           '• <' || v_url || '/relatorios/remocoes?caso=' || caso_id || '|' || pessoa || '>: '
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
  -- Linha em branco dupla entre responsáveis, para cada bloco ficar separado.
  select string_agg(bloco, E'\n\n\n' order by kordem) into v_corpo from por_resp;

  return json_build_object('ok', true, 'texto',
    ':alarm_clock: *Remoção de acessos: ' || v_casos || ' caso(s) em aberto'
    || case when v_atrasados > 0 then ', ' || v_atrasados || ' atrasado(s)' else '' end || '*'
    || E'\n\n' || coalesce(v_corpo, 'Nada pendente.'));
end $$;

revoke all on function public.ra_slack_responsaveis(uuid, boolean) from public, anon, authenticated;
revoke all on function public.ra_slack_pendentes_base(text) from public, anon, authenticated;
revoke all on function public.ra_slack_lembrete(text) from public;
grant execute on function public.ra_slack_lembrete(text) to anon, authenticated;
