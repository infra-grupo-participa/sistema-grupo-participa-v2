-- =====================================================================
-- 20260916_remocao_acessos_desfazer
-- "Desfazer triagem" (pedido do Victor, 16/09/2026): clicou em "Remover acessos"
-- ou "Mantém acesso antigo" por engano → o caso volta para aguardando triagem.
--
-- Trava: se algum item já foi marcado (feito ou não se aplica), não desfaz.
-- Marcação é registro de acesso removido de verdade; o triador desmarca antes,
-- e isso fica no histórico. Os itens pendentes são apagados; o histórico fica.
-- Se o Slack já tinha avisado a triagem, sai uma resposta na thread dizendo que
-- ela foi desfeita, e a próxima triagem avisa de novo.
-- =====================================================================

create or replace function public.ra_desfazer_triagem(p_caso uuid)
returns json language plpgsql security definer set search_path to 'public' as $$
declare
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
  v_marcados int;
  v_avisou boolean;
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem pode desfazer.');
  end if;
  select * into v_caso from public.ra_casos where id = p_caso for update;
  if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
  if v_caso.status not in ('em_remocao', 'mantem_acesso', 'concluido') then
    return json_build_object('ok', false, 'msg', 'Este caso não tem triagem para desfazer.');
  end if;

  select count(*) into v_marcados from public.ra_itens where caso_id = p_caso and situacao <> 'pendente';
  if v_marcados > 0 then
    return json_build_object('ok', false, 'msg',
      format('%s item(ns) já marcado(s). Desmarque antes de desfazer a triagem.', v_marcados));
  end if;

  delete from public.ra_itens where caso_id = p_caso;

  v_avisou := v_caso.slack_ts is not null
              and (v_caso.slack_avisos ? 'liberado' or v_caso.slack_avisos ? 'fechado');
  update public.ra_casos
     set status = 'aguardando_triagem', triado_por = null, triado_em = null,
         decisao_obs = null, concluido_em = null,
         slack_avisos = (slack_avisos - 'liberado' - 'fechado' - 'concluido')
                        || case when v_avisou then '{"desfazer_pendente": true}'::jsonb else '{}'::jsonb end
   where id = p_caso;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (p_caso, 'triagem_desfeita', v_uid, jsonb_build_object('status_anterior', v_caso.status));
  return json_build_object('ok', true, 'msg', 'Triagem desfeita. O caso voltou para aguardando triagem.');
end $$;

revoke all on function public.ra_desfazer_triagem(uuid) from public, anon;
grant execute on function public.ra_desfazer_triagem(uuid) to authenticated;

-- Slack: resposta na thread quando a triagem é desfeita.
create or replace function public.ra_slack_pendentes(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare v_base json;
begin
  v_base := public.ra_slack_pendentes_base(p_segredo);
  if coalesce((v_base->>'ok')::boolean, false) is not true then return v_base; end if;
  return json_build_object('ok', true, 'mensagens', coalesce((
    select json_agg(x order by ord) from (
      -- Desfeita vem antes: numa triagem refeita no mesmo tick, a ordem na thread fica certa.
      select json_build_object('caso_id', c.id, 'aviso', 'desfeito', 'thread_ts', c.slack_ts,
               'texto', ':leftwards_arrow_with_hook: *Triagem desfeita.* O caso voltou para aguardando triagem; desconsiderem o aviso anterior.') x, 0 as ord
        from public.ra_casos c
       where c.slack_avisos ? 'desfazer_pendente' and c.slack_ts is not null
      union all
      select json_build_object(
               'caso_id', m->>'caso_id', 'aviso', m->>'aviso', 'thread_ts', m->>'thread_ts',
               'texto', case when c.teste and m->>'thread_ts' is null
                             then ':test_tube: *TESTE (webhook da remoção de acessos)*' || E'\n' || (m->>'texto')
                             else m->>'texto' end), 1
        from json_array_elements(v_base->'mensagens') m
        join public.ra_casos c on c.id = (m->>'caso_id')::uuid
    ) t), '[]'::json));
end $$;

revoke all on function public.ra_slack_pendentes(text) from public;
grant execute on function public.ra_slack_pendentes(text) to anon, authenticated;

create or replace function public.ra_slack_confirmar(p_segredo text, p_caso uuid, p_aviso text, p_ts text default null)
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  update public.ra_casos
     set slack_avisos = case when p_aviso = 'desfeito'
                             then slack_avisos - 'desfazer_pendente'
                             else slack_avisos || jsonb_build_object(p_aviso, now()) end,
         slack_ts = case when p_aviso in ('novo', 'alerta') and slack_ts is null then p_ts else slack_ts end
   where id = p_caso;
  return json_build_object('ok', found);
end $$;
