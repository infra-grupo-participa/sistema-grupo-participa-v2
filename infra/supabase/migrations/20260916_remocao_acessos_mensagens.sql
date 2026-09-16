-- =====================================================================
-- 20260916_remocao_acessos_mensagens
-- Mensagens do Slack mais enxutas (pedido do Victor, 16/09/2026):
-- • pessoas (titular e sócios, nome e e-mail) aparecem UMA vez;
-- • cada responsável é marcado UMA vez, com os itens dele, sem repetir nomes;
-- • tudo de um caso fica na conversa do primeiro aviso, inclusive o lembrete
--   diário (que deixa de ser uma mensagem solta no canal);
-- • Thomas, Ana Camila e João passam a ser marcados de verdade.
-- =====================================================================

insert into public.ra_slack (perfil_id, slack_id) values
  ('998e69ce-0c71-409f-b267-b8409889b640', 'U0AQXNQGJEL'),   -- Thomas Henrique
  ('e303b8d1-e31a-4539-a450-259a8cb1d71a', 'U0AV376RATC'),   -- Ana Camila
  ('843d43db-73b3-44a9-b449-1731e362dbc3', 'U0AR4NAKX9N')    -- João Pedro Alves (joao@advmais.com)
on conflict (perfil_id) do update set slack_id = excluded.slack_id;

-- Pessoas do caso, uma por linha: "• Nome · e-mail (titular)".
create or replace function public.ra_slack_pessoas(p_caso uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select string_agg('• ' || coalesce(p.nome, 'sem nome') || ' · ' || coalesce(nullif(p.email, ''), 'sem e-mail')
                    || case when p.papel = 'titular' then ' (titular)' else ' (sócio)' end,
                    E'\n' order by p.ordem)
    from public.ra_pessoas p where p.caso_id = p_caso;
$$;

-- Responsáveis, uma linha cada: "• @Thomas: Searchie e Obvio".
-- p_pendentes = true mostra só o que falta; quando falta só para parte das
-- pessoas do caso, diz para quem.
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
  select string_agg('• ' || public.ra_slack_marca(pr.responsavel_id) || ': ' || regexp_replace(pr.itens, ', ([^,]*)$', ' e \1')
                    || case when p_pendentes and pr.pessoas < (select n from total) then ' (falta: ' || pr.nomes || ')' else '' end,
                    E'\n' order by pr.ordem)
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
           ':warning: *Disputa aberta no HM* ' || public.ra_slack_marca(v_triador) || E'\n'
           || public.ra_slack_pessoas(b.id) || E'\n'
           || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n'
           || 'Ainda não é reembolso nem chargeback. ' || b.link as texto
      from base b where b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
    union all
    -- Caso novo: marca só o triador.
    select b.id, 'novo', null, 1,
           ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente* ' || public.ra_slack_marca(v_triador) || E'\n'
           || public.ra_slack_pessoas(b.id) || E'\n'
           || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
           || case when b.eh_programa then ' · Programa de Implementação' else '' end || E'\n'
           || 'Sugestão: *' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || '* · ' || coalesce(b.sugestao->>'motivo', '') || E'\n'
           || 'Prazo: ' || coalesce(b.prazo, 'sem prazo') || ' · ' || b.link
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
           ':scissors: *Remover acessos* · prazo ' || coalesce(b.prazo, 'sem prazo') || E'\n'
           || public.ra_slack_pessoas(b.id) || E'\n\n'
           || coalesce(public.ra_slack_responsaveis(b.id, false), '• nenhum item') || E'\n'
           || 'Marquem no sistema quando removerem. ' || b.link
      from base b where b.status in ('em_remocao', 'concluido') and b.slack_ts is not null
                    and not (b.slack_avisos ? 'liberado')
    union all
    -- Concluído.
    select b.id, 'concluido', b.slack_ts, 3,
           ':white_check_mark: *Acessos removidos.* '
           || (select string_agg(linha, ' · ') from (
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

-- Lembrete diário: uma resposta DENTRO da conversa de cada caso aberto.
-- Caso sem conversa (o aviso ainda não saiu) fica de fora: o aviso novo sai antes.
create or replace function public.ra_slack_lembrete(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  if not public.ra_dia_util(v_hoje) then return json_build_object('ok', true, 'mensagens', '[]'::json); end if;

  return json_build_object('ok', true, 'mensagens', coalesce((
    select json_agg(json_build_object('caso_id', c.id, 'thread_ts', c.slack_ts, 'texto',
             ':alarm_clock: *Lembrete* · '
             || case when c.prazo_em < now() then ':red_circle: atrasado desde '
                     when (c.prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje then ':large_yellow_circle: vence hoje às '
                     else 'prazo ' end
             || coalesce(to_char(c.prazo_em at time zone 'America/Sao_Paulo',
                                 case when (c.prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje and c.prazo_em >= now()
                                      then 'HH24:MI' else 'DD/MM HH24:MI' end), 'sem prazo') || E'\n'
             || case when c.status = 'aguardando_triagem'
                     then '• ' || public.ra_slack_marca(v_triador) || ': triagem'
                     else coalesce(public.ra_slack_responsaveis(c.id, true), '• nada pendente') end)
           order by c.prazo_em nulls last)
      from public.ra_casos c
     where c.status in ('aguardando_triagem', 'em_remocao') and c.slack_ts is not null), '[]'::json));
end $$;

revoke all on function public.ra_slack_pessoas(uuid) from public, anon, authenticated;
revoke all on function public.ra_slack_responsaveis(uuid, boolean) from public, anon, authenticated;
revoke all on function public.ra_slack_pendentes_base(text) from public, anon, authenticated;
revoke all on function public.ra_slack_lembrete(text) from public;
grant execute on function public.ra_slack_lembrete(text) to anon, authenticated;
