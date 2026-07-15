-- Controle financeiro avançado: cobrança com régua, metas por turma e log de cobranças.
-- Aplicada em produção em 2026-07-14.
--
-- Baseado em práticas de accounts-receivable / dunning: régua de cobrança com
-- cadência configurável, metas/targets por turma, e histórico de cobranças que
-- alimenta a "fila do dia" (próxima ação) e o aging.

-- Tabelas (schema cs, não exposto ao PostgREST — acesso só por RPC SECURITY DEFINER).
create table if not exists cs.fin_metas (
  turma               text primary key,
  meta_arrecadacao    numeric,
  meta_cobertura_pct  numeric,
  prazo_quitacao_dias int,
  data_fechamento     date,
  obs                 text,
  atualizado_em       timestamptz not null default now(),
  atualizado_por      text
);

create table if not exists cs.fin_regua_passos (
  id          smallint generated always as identity primary key,
  ordem       int  not null,
  offset_dias int  not null,   -- relativo ao vencimento; negativo = antes
  titulo      text not null,
  canal       text,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now()
);

create table if not exists cs.fin_cobrancas (
  id            uuid primary key default gen_random_uuid(),
  contato_hm_id uuid not null,
  quando        timestamptz not null default now(),
  canal         text,
  resultado     text,
  obs           text,
  autor         text,
  autor_id      uuid,
  criado_em     timestamptz not null default now()
);
create index if not exists idx_fin_cobrancas_contato on cs.fin_cobrancas (contato_hm_id, quando desc);

alter table cs.fin_metas        enable row level security;
alter table cs.fin_regua_passos enable row level security;
alter table cs.fin_cobrancas    enable row level security;

-- Régua padrão (cadência validada: pré-vencimento + follow-ups em +1/+7/+14/+30).
insert into cs.fin_regua_passos (ordem, offset_dias, titulo, canal) values
  (1, -3, 'Lembrete pré-vencimento', 'whatsapp'),
  (2,  1, '1º aviso de atraso',      'whatsapp'),
  (3,  7, '2ª cobrança',             'ligacao'),
  (4, 14, 'Cobrança firme',          'ligacao'),
  (5, 30, 'Renegociar / última chance', 'ligacao')
on conflict do nothing;

-- ── RPCs: metas ──────────────────────────────────────────────────────────────
create or replace function public.fn_fin_metas()
returns table (turma text, meta_arrecadacao numeric, meta_cobertura_pct numeric,
               prazo_quitacao_dias int, data_fechamento date, obs text,
               atualizado_em timestamptz, atualizado_por text)
language sql stable security definer set search_path to 'public','cs'
as $$
  select m.turma, m.meta_arrecadacao, m.meta_cobertura_pct, m.prazo_quitacao_dias,
         m.data_fechamento, m.obs, m.atualizado_em, m.atualizado_por
  from cs.fin_metas m where public.gp_pode_ver_financeiro() order by m.turma;
$$;

create or replace function public.fn_fin_meta_salvar(
  p_turma text, p_meta_arrecadacao numeric default null,
  p_meta_cobertura_pct numeric default null, p_prazo_quitacao_dias int default null,
  p_data_fechamento date default null, p_obs text default null)
returns jsonb language plpgsql security definer set search_path to 'public','cs'
as $$
declare v_autor text;
begin
  if not public.gp_pode_operar_financeiro() then return jsonb_build_object('ok', false, 'erro', 'sem_permissao'); end if;
  select coalesce(nome, email, 'financeiro') into v_autor from public.perfis where id = (select auth.uid());
  insert into cs.fin_metas (turma, meta_arrecadacao, meta_cobertura_pct, prazo_quitacao_dias, data_fechamento, obs, atualizado_em, atualizado_por)
  values (p_turma, p_meta_arrecadacao, p_meta_cobertura_pct, p_prazo_quitacao_dias, p_data_fechamento, p_obs, now(), v_autor)
  on conflict (turma) do update set
    meta_arrecadacao = excluded.meta_arrecadacao, meta_cobertura_pct = excluded.meta_cobertura_pct,
    prazo_quitacao_dias = excluded.prazo_quitacao_dias, data_fechamento = excluded.data_fechamento,
    obs = excluded.obs, atualizado_em = now(), atualizado_por = v_autor;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── RPCs: régua ──────────────────────────────────────────────────────────────
create or replace function public.fn_fin_regua()
returns table (id smallint, ordem int, offset_dias int, titulo text, canal text, ativo boolean)
language sql stable security definer set search_path to 'public','cs'
as $$
  select r.id, r.ordem, r.offset_dias, r.titulo, r.canal, r.ativo
  from cs.fin_regua_passos r where public.gp_pode_ver_financeiro() order by r.ordem, r.offset_dias;
$$;

create or replace function public.fn_fin_regua_salvar(p_passos jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','cs'
as $$
begin
  if not public.gp_pode_operar_financeiro() then return jsonb_build_object('ok', false, 'erro', 'sem_permissao'); end if;
  delete from cs.fin_regua_passos;
  insert into cs.fin_regua_passos (ordem, offset_dias, titulo, canal, ativo)
  select (p->>'ordem')::int, (p->>'offset_dias')::int, p->>'titulo', nullif(p->>'canal',''), coalesce((p->>'ativo')::boolean, true)
  from jsonb_array_elements(p_passos) p;
  return jsonb_build_object('ok', true);
end;
$$;

-- ── RPCs: cobranças ──────────────────────────────────────────────────────────
create or replace function public.fn_fin_cobranca_registrar(
  p_contato_hm_id uuid, p_canal text, p_resultado text, p_obs text default null)
returns jsonb language plpgsql security definer set search_path to 'public','cs'
as $$
declare v_autor text; v_aluno uuid; v_comprador uuid;
begin
  if not public.gp_pode_operar_financeiro() then return jsonb_build_object('ok', false, 'erro', 'sem_permissao'); end if;
  select coalesce(nome, email, 'financeiro') into v_autor from public.perfis where id = (select auth.uid());
  select aluno_id, comprador_id into v_aluno, v_comprador from cs.contatos_hm where id = p_contato_hm_id;
  insert into cs.fin_cobrancas (contato_hm_id, canal, resultado, obs, autor, autor_id)
  values (p_contato_hm_id, nullif(p_canal,''), nullif(p_resultado,''), nullif(p_obs,''), v_autor, (select auth.uid()));
  insert into public.thb_system_events (tipo, fonte, titulo, detalhe, aluno_id)
  values ('info', 'financeiro', 'Cobrança registrada',
    jsonb_build_object('contato_hm_id', p_contato_hm_id, 'comprador_id', v_comprador,
      'canal', p_canal, 'resultado', p_resultado, 'autor', coalesce(v_autor,'?')), v_aluno);
  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.fn_fin_cobrancas(p_contato_hm_id uuid)
returns table (id uuid, quando timestamptz, canal text, resultado text, obs text, autor text)
language sql stable security definer set search_path to 'public','cs'
as $$
  select c.id, c.quando, c.canal, c.resultado, c.obs, c.autor
  from cs.fin_cobrancas c
  where public.gp_pode_ver_financeiro() and c.contato_hm_id = p_contato_hm_id
  order by c.quando desc;
$$;

-- ── Contas a receber: + última cobrança, total e remarcações (promessa quebrada)
drop function if exists public.fn_fin_contas_receber(text);
create function public.fn_fin_contas_receber(p_turma text default null)
returns table (
  contato_hm_id uuid, comprador_id uuid, aluno_id uuid,
  nome varchar, email varchar, telefone varchar, documento varchar,
  turma text, turma_origem text, canal text, publico text, tags text[],
  estagio_nome text, estagio_aba text,
  sinal_bruto numeric, sinal_liquido numeric, sinal_taxas numeric,
  sinal_pago_em timestamptz, sinal_metodo text, sinal_transacao text,
  saldo_pago_bruto numeric, saldo_pago_liquido numeric, saldo_taxas numeric,
  saldo_pago_em timestamptz, saldo_metodo text, saldo_lancamentos int,
  total_pago_bruto numeric, total_pago_liquido numeric,
  pacote numeric, credito numeric, saldo_a_pagar numeric, pago_pct numeric,
  vencimento date, acordo text, pagamento_meio text, pagamento_forma text,
  pagamento_parcelas int, parcelas_pagas int, parcelas_contratadas int,
  valor_parcela numeric, dias_atraso int,
  oferta_codigo text, oferta_valor numeric, oferta_link text,
  oferta_recorrente boolean, oferta_enviada_em timestamptz,
  cancelamento_em timestamptz, cancelamento_motivo text,
  cancelamento_efetivado_em timestamptz, quitado_em timestamptz,
  reembolso_em timestamptz, reembolso_status text, reembolso_valor numeric,
  ultimo_pagamento_em timestamptz, situacao_ativacao text, status_financeiro text,
  pacote_regra numeric, divergencia_regra numeric,
  ultima_cobranca_em timestamptz, cobrancas_total int, remarcacoes int
)
language sql stable security definer set search_path to 'public','cs'
as $$
  select v.contato_hm_id, v.comprador_id, v.aluno_id, v.nome, v.email, v.telefone, v.documento,
         v.turma, v.turma_origem, v.canal, v.publico, v.tags, v.estagio_nome, v.estagio_aba,
         v.sinal_bruto, v.sinal_liquido, v.sinal_taxas, v.sinal_pago_em, v.sinal_metodo, v.sinal_transacao,
         v.saldo_pago_bruto, v.saldo_pago_liquido, v.saldo_taxas, v.saldo_pago_em, v.saldo_metodo, v.saldo_lancamentos,
         v.total_pago_bruto, v.total_pago_liquido, v.pacote, v.credito, v.saldo_a_pagar, v.pago_pct,
         v.vencimento, v.acordo, v.pagamento_meio, v.pagamento_forma, v.pagamento_parcelas,
         v.parcelas_pagas, v.parcelas_contratadas, v.valor_parcela, v.dias_atraso,
         v.oferta_codigo, v.oferta_valor, v.oferta_link, v.oferta_recorrente, v.oferta_enviada_em,
         v.cancelamento_em, v.cancelamento_motivo, v.cancelamento_efetivado_em, v.quitado_em,
         v.reembolso_em, v.reembolso_status, v.reembolso_valor,
         v.ultimo_pagamento_em, v.situacao_ativacao, v.status_financeiro,
         v.pacote_regra, v.divergencia_regra,
         (select max(fc.quando) from cs.fin_cobrancas fc where fc.contato_hm_id = v.contato_hm_id),
         (select count(*) from cs.fin_cobrancas fc where fc.contato_hm_id = v.contato_hm_id)::int,
         (select count(*) from public.thb_system_events ev
            where ev.fonte = 'financeiro' and ev.titulo = 'Acordo de pagamento registrado'
              and ev.detalhe->>'contato_hm_id' = v.contato_hm_id::text
              and nullif(ev.detalhe->'antes'->>'vencimento','') is not null
              and coalesce(ev.detalhe->'antes'->>'vencimento','') <> coalesce(ev.detalhe->'depois'->>'vencimento',''))::int
  from cs.vw_fin_contas_receber v
  where public.gp_pode_ver_financeiro() and (p_turma is null or v.turma = p_turma)
  order by v.saldo_a_pagar desc nulls last, v.nome;
$$;

-- Permissões: só authenticated (guard interno), revoga de public.
revoke execute on function public.fn_fin_metas()                                       from public;
revoke execute on function public.fn_fin_meta_salvar(text,numeric,numeric,int,date,text) from public;
revoke execute on function public.fn_fin_regua()                                       from public;
revoke execute on function public.fn_fin_regua_salvar(jsonb)                           from public;
revoke execute on function public.fn_fin_cobranca_registrar(uuid,text,text,text)       from public;
revoke execute on function public.fn_fin_cobrancas(uuid)                               from public;
revoke execute on function public.fn_fin_contas_receber(text)                          from public;
grant execute on function public.fn_fin_metas()                                       to authenticated;
grant execute on function public.fn_fin_meta_salvar(text,numeric,numeric,int,date,text) to authenticated;
grant execute on function public.fn_fin_regua()                                       to authenticated;
grant execute on function public.fn_fin_regua_salvar(jsonb)                           to authenticated;
grant execute on function public.fn_fin_cobranca_registrar(uuid,text,text,text)       to authenticated;
grant execute on function public.fn_fin_cobrancas(uuid)                               to authenticated;
grant execute on function public.fn_fin_contas_receber(text)                          to authenticated;
