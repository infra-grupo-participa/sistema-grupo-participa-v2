-- 20261001e — Vigia das rotinas (5/5): texto das mensagens.
--
-- Português claro, sem jargão de banco. Horários em America/Sao_Paulo.
--   ciclo    só o que mudou: PAROU (abriu incidente) · VOLTOU (K ok seguidos) · ENCERRADO (rotina desligada)
--   inicial  primeira mensagem do vigia: foto de tudo (quantas ativas, quais com problema, quais sem rastreio)
--   resumo   11 UTC (8 h de Brasília): mesma foto + o que mudou no ciclo
-- O que vai ao Slack: nome da rotina, motivo (N falhas / sem sucesso em X), status HTTP + classe
--   (ops.rotina_estado.ultima_falha) e horários. NUNCA corpo de resposta, return_message, header nem
--   ultimo_erro (esse fica só no banco, redigido, visível pela RPC de admin).
-- Todo o texto passa por ops.slack_esc (& < >): o Slack interpreta <...> como link/menção.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

create function ops.fmt_hora(p timestamptz) returns text
language sql stable set search_path = '' as $f$
  select to_char(p at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI')
$f$;

create function ops.slack_esc(p text) returns text
language sql immutable set search_path = '' as $f$
  select replace(replace(replace(p, '&', '&amp;'), '<', '&lt;'), '>', '&gt;')
$f$;

create function ops.montar_mensagem(p_tipo text, p_mud jsonb default '[]'::jsonb) returns text
language plpgsql stable set search_path = '' as $f$
declare
  v_mud     text;
  v_prob    text;
  v_semr    text;
  v_ativas  int;
  v_nprob   int;
  v_deslig  int;
begin
  select string_agg(case m->>'acao'
           when 'abriu' then format('PAROU: %s — %s. Último erro: %s. Último sucesso: %s.',
                                    m->>'jobname', m->>'motivo', coalesce(m->>'falha', 'sem detalhe'),
                                    coalesce(ops.fmt_hora((m->>'ultimo_ok')::timestamptz), 'nenhum desde que o vigia começou a olhar'))
           when 'voltou' then format('VOLTOU: %s — %s execução(ões) certa(s) seguida(s)%s.',
                                    m->>'jobname', m->>'oks',
                                    coalesce(', estava com problema desde ' || ops.fmt_hora((m->>'desde')::timestamptz), ''))
           else format('ENCERRADO: %s — a rotina foi desligada ou removida; o alerta foi fechado.', m->>'jobname')
         end, E'\n' order by (m->>'acao') <> 'abriu', m->>'jobname')
    into v_mud
    from jsonb_array_elements(coalesce(p_mud, '[]'::jsonb)) m;

  if p_tipo = 'ciclo' then
    return ops.slack_esc('Vigia das rotinas' || E'\n' || coalesce(v_mud, '(nada mudou)'));
  end if;

  select count(*) filter (where e.ativo and e.rastreio <> 'removido'),
         count(*) filter (where e.incidente_aberto_em is not null),
         count(*) filter (where e.ativo is not true)
    into v_ativas, v_nprob, v_deslig
    from ops.rotina_estado e;

  select string_agg(format('- %s: %s. Último erro: %s. Último sucesso: %s.',
                           e.jobname, e.incidente_motivo, coalesce(e.ultima_falha, 'sem detalhe'),
                           coalesce(ops.fmt_hora(e.ultimo_ok_em), 'nenhum visto')), E'\n' order by e.jobname)
    into v_prob
    from ops.rotina_estado e where e.incidente_aberto_em is not null;

  select string_agg(e.jobname, ', ' order by e.jobname) into v_semr
    from ops.rotina_estado e where e.ativo and e.rastreio = 'sem_rastreio';

  return ops.slack_esc(concat_ws(E'\n',
    case p_tipo when 'inicial' then 'Vigia das rotinas ligado. Situação agora (' || ops.fmt_hora(now()) || '):'
                else 'Resumo diário das rotinas — ' || to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM') end,
    format('%s rotinas ativas · %s com problema · %s desligadas.', v_ativas, v_nprob, v_deslig),
    case when v_nprob = 0 then 'Todas as rotinas ativas estão funcionando.' else 'Com problema:' || E'\n' || v_prob end,
    case when v_semr is not null then 'Sem rastreio da resposta HTTP (o vigia só vê se o pedido saiu): ' || v_semr || '.' end,
    case when p_tipo = 'resumo' and v_mud is not null then E'\nMudou agora:\n' || v_mud end));
end
$f$;

revoke execute on all functions in schema ops from public, anon, authenticated;
