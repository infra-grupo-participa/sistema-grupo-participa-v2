-- =====================================================================
-- 20260916_remocao_acessos_slack_imediato
-- Slack na hora (pedido do Victor, 16/09/2026): antes a mensagem só saía no
-- disparo de 5 em 5 minutos do n8n, e uma triagem desfeita dentro desse
-- intervalo não gerava aviso nenhum.
--
-- • Toda mudança de caso (novo, triagem, desfazer, concluir) chama o webhook
--   do n8n na hora, via pg_net (a chamada só sai depois do commit).
-- • O disparo de 5 em 5 minutos continua como garantia.
-- • Para os dois caminhos nunca postarem a mesma mensagem, o n8n RESERVA o que
--   vai enviar (ra_slack_reservar); a reserva vale 2 minutos e some na
--   confirmação. Se o Slack falhar, a mensagem volta à fila depois disso.
-- =====================================================================

create table if not exists public.ra_slack_reservas (
  caso_id uuid not null references public.ra_casos(id) on delete cascade,
  aviso text not null,
  reservado_em timestamptz not null default now(),
  primary key (caso_id, aviso)
);
alter table public.ra_slack_reservas enable row level security;
revoke all on public.ra_slack_reservas from anon, authenticated;

insert into public.ra_config (chave, valor) values
  ('n8n_webhook_url', 'https://infra-csm-n8n.nfpbgs.easypanel.host/webhook/remocao-acessos-slack')
on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();

create or replace function public.ra_slack_reservar(p_segredo text)
returns json language plpgsql volatile security definer set search_path to 'public' as $$
declare
  v_base json;
  v_out jsonb := '[]'::jsonb;
  m json;
begin
  v_base := public.ra_slack_pendentes(p_segredo);
  if coalesce((v_base->>'ok')::boolean, false) is not true then return v_base; end if;
  delete from public.ra_slack_reservas where reservado_em < now() - interval '2 minutes';
  for m in select * from json_array_elements(v_base->'mensagens') loop
    insert into public.ra_slack_reservas (caso_id, aviso)
    values ((m->>'caso_id')::uuid, m->>'aviso')
    on conflict do nothing;
    if found then v_out := v_out || jsonb_build_array(m::jsonb); end if;
  end loop;
  return json_build_object('ok', true, 'mensagens', v_out);
end $$;

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
  delete from public.ra_slack_reservas where caso_id = p_caso and aviso = p_aviso;
  return json_build_object('ok', found);
end $$;

-- Chama o n8n quando o caso muda de um jeito que gera mensagem.
-- Nunca derruba a operação: se o pg_net falhar, o disparo de 5 min cobre.
create or replace function public.ra_fn_avisar_n8n()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_url text;
begin
  if tg_op = 'UPDATE'
     and new.status is not distinct from old.status
     and new.decisao is not distinct from old.decisao
     and not (new.slack_avisos ? 'desfazer_pendente' and not (old.slack_avisos ? 'desfazer_pendente'))
     and not (new.slack_ts is not null and old.slack_ts is null) then
    return new;
  end if;
  select valor into v_url from public.ra_config where chave = 'n8n_webhook_url';
  if v_url is null then return new; end if;
  begin
    perform net.http_post(url := v_url,
                          body := jsonb_build_object('caso', new.id, 'status', new.status),
                          headers := '{"Content-Type": "application/json"}'::jsonb,
                          timeout_milliseconds := 10000);
  exception when others then
    raise warning 'ra_fn_avisar_n8n: %', sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists trg_ra_avisar_n8n on public.ra_casos;
create trigger trg_ra_avisar_n8n
  after insert or update on public.ra_casos
  for each row execute function public.ra_fn_avisar_n8n();

revoke all on function public.ra_fn_avisar_n8n() from public, anon, authenticated;
revoke all on function public.ra_slack_reservar(text) from public;
grant execute on function public.ra_slack_reservar(text) to anon, authenticated;
