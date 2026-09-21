-- =====================================================================
-- 20260916_remocao_acessos_lembrete
-- Lembrete diário com TUDO o que está pendente (pedido do Victor, 16/09/2026):
-- cada caso aberto, a situação do prazo e, por responsável, os itens que faltam
-- (com o nome da pessoa quando o caso tem sócios).
-- =====================================================================

create or replace function public.ra_slack_lembrete(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_blocos text;
  v_n int;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  if not public.ra_dia_util(v_hoje) then return json_build_object('ok', true, 'texto', null); end if;

  select count(*), string_agg(bloco, E'\n\n' order by ordem, prazo_em nulls last)
    into v_n, v_blocos
  from (
    select case when c.prazo_em < now() then 0
                when (c.prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje then 1 else 2 end as ordem,
           c.prazo_em,
           case when c.prazo_em < now() then ':red_circle: *Atrasado*'
                when (c.prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje then ':large_yellow_circle: *Vence hoje*'
                else ':white_circle: *No prazo*' end
           || case when c.teste then ' · TESTE' else '' end
           || ' · *' || coalesce(c.nome, 'sem nome') || '* · ' || case c.tipo when 'chargeback' then 'chargeback' else 'reembolso' end
           || ' · prazo ' || coalesce(to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), 'sem prazo')
           || ' · <' || v_url || '/relatorios/remocoes?caso=' || c.id || '|abrir>' || E'\n'
           || case
                when c.status = 'aguardando_triagem' then
                  '    • triagem pendente: ' || public.ra_slack_marca(v_triador)
                else coalesce((
                  select string_agg('    • ' || public.ra_slack_marca(z.responsavel_id) || ': ' || z.itens, E'\n' order by z.ordem)
                    from (
                      -- Um responsável por linha; com sócio, os itens vêm agrupados por pessoa.
                      select y.responsavel_id, min(y.ordem) as ordem,
                             string_agg(case when y.varias then y.pessoa || ' (' || y.itens || ')' else y.itens end,
                                        ' · ' order by y.pordem) as itens
                        from (
                          select i.responsavel_id, p.ordem as pordem, min(k.ordem) as ordem,
                                 coalesce(p.nome, 'sem nome') as pessoa,
                                 (select count(*) from public.ra_pessoas pp where pp.caso_id = c.id) > 1 as varias,
                                 string_agg(k.rotulo, ', ' order by k.ordem) as itens
                            from public.ra_itens i
                            join public.ra_itens_catalogo k on k.item = i.item
                            join public.ra_pessoas p on p.id = i.pessoa_id
                           where i.caso_id = c.id and i.situacao = 'pendente'
                           group by i.responsavel_id, p.id, p.ordem, p.nome
                        ) y
                       group by y.responsavel_id
                    ) z), '    • nada pendente')
              end as bloco
      from public.ra_casos c
     where c.status in ('aguardando_triagem', 'em_remocao')
  ) b;

  return json_build_object('ok', true, 'texto',
    case when coalesce(v_n, 0) = 0 then null
         else ':alarm_clock: *Remoção de acessos: ' || v_n || ' caso(s) em aberto*' || E'\n\n' || v_blocos end);
end $$;

revoke all on function public.ra_slack_lembrete(text) from public;
grant execute on function public.ra_slack_lembrete(text) to anon, authenticated;
