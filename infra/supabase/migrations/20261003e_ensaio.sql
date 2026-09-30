-- 20261003e — ENSAIO (begin … rollback; nada fica gravado). Rodar como postgres, arquivo inteiro numa chamada,
-- DEPOIS de 20261003a–d aplicadas (os números são medidos com a base já corrigida pela c).
-- Esperados:
--   0.antes_cadeias               = linhas de cadeia/autorreferência HOJE (passo 0: 8 cadeias antes da c; cai depois)
--   1.resumo                      = contagem por grupo/tipo/severidade (itens, alunos, conferidos=0)
--   1.teto                        = itens × teto da auditoria; ACIMA = explicar ou parar
--   1.pares                       = 12 linhas / 6 itens (os pares sem S1 decisivo) · 1.cadeia_por_caso = medido
--   1.fora_base                   = comprou_fora_da_base 0 (esperado real) · comprou_em_ativacao = medido
--   1.pii                         = 0 · 0 · 0 · 0 (detalhe com @/11+ dígitos; ref_externa fora de uuid/hex64; ref = doc/e-mail)
--   1.item_unico_por_linha        = 0 (nenhum item com tipo diferente)
--   2.decisao_*                   = some da lista; volta com conferido=t e decisao_id = id gravado; 2ª vigente = 23505
--   2.p_aluno                     = total = do_aluno
--   3.explain_*                   = Execution Time ≤ 1.500 ms (conciliação); > 3.000 ms = PARAR
--   4.anon_* / 4.nao_equipe_* / 4.equipe_direto_* = 42501 · 4.equipe_ok = contagem
--
-- RESULTADO (30/09/2026, produção, rodada final depois de corrigir a definição do teto — sinal/reserva não faz aluno;
-- tratamento_manual não é revogação):
--   1.teto: comprou_em_ativacao 7 · comprou_fora_da_base 2 · gps_divergente 35 · revogado_com_vigencia 98 — todos ok
--   1.acesso_por_motivo: revogado_com_vigencia = acessos_revogados 7 + sem_acesso 91 · situacao_desatualizada 130
--   1.fora_base: comprou_em_ativacao 7 (08/06–30/09) · comprou_fora_da_base 2 (27/08–04/09) · placa_sem_aluno 4 ·
--                sip_sem_aluno 21 · 1.total (1495, 1475, 806)
--   3.explain_conciliacao 1.713 ms (acima dos 1.500 alvo, abaixo dos 3.000 de parar: tela carrega UMA vez e pagina
--   no cliente) · 3.explain_fora_base 589 ms
--   Aplicada e conferida: 3 funções + tabela existem; anon não executa; authenticated executa a conciliação;
--   fn_aluno_compras_fora_base fechada para authenticated.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to authenticated, anon;
create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record;
begin
  for r in execute p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, r::text);
  end loop;
end $f$;
create function pg_temp.z_err(p_passo text, p_sql text) returns void language plpgsql as $f$
begin
  execute p_sql;
  insert into pg_temp._z_out (passo, linha) values (p_passo, 'SEM ERRO');
exception when others then
  insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate || ' ' || sqlerrm);
end $f$;
create function pg_temp.z_explain(p_passo text, p_sql text) returns void language plpgsql as $f$
declare l text;
begin
  for l in execute 'explain (analyze, buffers) ' || p_sql loop
    insert into pg_temp._z_out (passo, linha) values (p_passo, l);
  end loop;
end $f$;
grant execute on function pg_temp.z_q(text, text), pg_temp.z_err(text, text), pg_temp.z_explain(text, text) to authenticated, anon;
-- papéis: equipe (dev/admin @advmais) e não-equipe (perfil ativo que não passa em gp_eh_equipe)
select set_config('z.eq', (select p.id::text from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
                             and p.cargo in ('dev', 'admin') order by p.id limit 1), true);

-- ─── 0. ANTES ───────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('0.ja_existe', $q$select count(*) filter (where proname in ('fn_aluno_conciliacao','fn_aluno_conciliacao_resumo','fn_aluno_compras_fora_base')),
  (select to_regclass('public.thb_aluno_conciliacao_decisao')::text) from pg_proc where pronamespace = 'public'::regnamespace$q$);
select pg_temp.z_q('0.antes_cadeias', $q$select case when x.socio_de_aluno_id = x.id then 'autorreferencia' else 'cadeia' end, count(*)
  from public.thb_alunos x left join public.thb_alunos y on y.id = x.socio_de_aluno_id
 where x.cancelado_em is null and y.cancelado_em is null
   and (x.socio_de_aluno_id = x.id or (y.socio_de_aluno_id is not null and y.socio_de_aluno_id <> x.id and y.id <> x.id))
 group by 1$q$);
select pg_temp.z_q('0.antes_pares', $q$select count(*) from public.thb_alunos x join public.thb_alunos y on y.id = x.socio_de_aluno_id and y.socio_de_aluno_id = x.id
 where x.cancelado_em is null and y.cancelado_em is null and x.id < y.id$q$);

-- ─── Migration (cópia literal do corpo da 20261003e) ────────────────────────────────────────────────────────────────
-- ─── 0. Guardas (falham ANTES de gravar) ───────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
begin
  -- 0.1 dependências: a (pagamentos), b (trava), c (correção aplicada), d (situação calculada) + funções de fora
  select string_agg(x.f, ', ') into v_falta
    from unnest(array['public.fn_aluno_pagamentos_programa()', 'public.fn_aluno_programas_safe()',
                      'public.fn_aluno_situacao_calculada()', 'public.fn_thb_alunos_trava_vinculo_socio()',
                      'public.gp_eh_equipe()', 'fin.chave_opaca(text)', 'controle.fone_key(text)']) x(f)
   where to_regprocedure(x.f) is null;
  if v_falta is not null then
    raise exception '20261003e: função ausente (aplicar a→d antes): %', v_falta;
  end if;
  if not exists (select 1 from public.thb_alunos_audit_log where origem = 'conciliacao_20261003') then
    raise exception '20261003e: aplicar a 20261003c antes (sem audit_log com origem conciliacao_20261003)';
  end if;
  if to_regclass('public.thb_aluno_conciliacao_decisao') is not null
     and not exists (select 1 from pg_class c where c.oid = to_regclass('public.thb_aluno_conciliacao_decisao')
                       and obj_description(c.oid, 'pg_class') like '20261003e%') then
    raise exception '20261003e: public.thb_aluno_conciliacao_decisao já existe e não é desta migration';
  end if;
  -- 0.2 colunas lidas
  select string_agg(format('%s.%s.%s', x.s, x.t, x.c), ', ') into v_falta
    from (values ('public','thb_alunos','socio_de_nome'), ('public','thb_alunos','telefone_e164'), ('public','thb_alunos','telefone'),
                 ('public','thb_alunos','documento'), ('public','thb_alunos','comprador_id'), ('public','thb_alunos','turma_id'),
                 ('public','thb_alunos','turma_aurum_id'), ('public','thb_alunos','data_compra'), ('public','thb_alunos','data_expiracao'),
                 ('public','compradores','id'), ('public','compradores','email'), ('public','compradores','documento'),
                 ('fin','identidade','no'), ('fin','identidade','pessoa_chave'), ('fin','identidade_bloqueio','valor'),
                 ('fin','vw_email_pessoa','email'), ('fin','vw_email_pessoa','pessoa_chave'),
                 ('cs','contatos_hm','id'), ('cs','contatos_hm','aluno_id'), ('cs','contatos_hm','comprador_id'),
                 ('cs','contatos_hm','produto'), ('cs','contatos_hm','cancelamento_efetivado_em'),
                 ('gps','membros','id'), ('gps','membros','aluno_id'), ('gps','membros','pessoa_aluno_id'), ('gps','membros','papel'),
                 ('sip','users','id'), ('sip','users','email'), ('sip','users','role'),
                 ('public','thb_placas_solicitacoes','id'), ('public','thb_placas_solicitacoes','aluno_id'),
                 ('public','thb_placas_solicitacoes','status')) x(s, t, c)
    left join information_schema.columns c on c.table_schema = x.s and c.table_name = x.t and c.column_name = x.c
   where c.column_name is null;
  if v_falta is not null then
    raise exception '20261003e: coluna ausente: %', v_falta;
  end if;
end $guarda$;

-- ─── 1. Decisões da fila (escrita só pelas funções da 20261003f) ────────────────────────────────────────────────────
create table if not exists public.thb_aluno_conciliacao_decisao (
  id            bigserial primary key,
  item          text        not null,
  tipo          text        not null,
  aluno_id      uuid,                              -- sem FK: item pode não ter aluno; aluno arquivado não apaga a trilha
  decisao       text        not null check (decisao in ('conferido', 'pessoas_diferentes', 'manter_sem_acesso')),
  observacao    text,
  decidido_por  uuid        default auth.uid(),
  decidido_em   timestamptz not null default now(),
  revertido_em  timestamptz,
  revertido_por uuid,
  check (revertido_em is null or revertido_em >= decidido_em)
);
comment on table public.thb_aluno_conciliacao_decisao is
  '20261003e: decisão humana por item da conciliação de alunos (fn_aluno_conciliacao). Nunca DELETE: desfazer = revertido_em. '
  'Sem grant para public/anon/authenticated; escrita só por fn_aluno_conciliacao_marcar/desmarcar (20261003f).';
-- uma decisão vigente por item (a leitura casa por item; duas vigentes seriam ambíguas)
create unique index if not exists thb_aluno_conciliacao_decisao_vigente_uidx
  on public.thb_aluno_conciliacao_decisao (item) where revertido_em is null;

alter table public.thb_aluno_conciliacao_decisao enable row level security;
revoke all on table public.thb_aluno_conciliacao_decisao from public, anon, authenticated;
revoke all on sequence public.thb_aluno_conciliacao_decisao_id_seq from public, anon, authenticated;
revoke delete, truncate on table public.thb_aluno_conciliacao_decisao from service_role;

-- ─── 2. Compradores de programa fora da base (interna) ─────────────────────────────────────────────────────────────
-- SQL invoker, sem SET (inlinável), sem EXECUTE para public/anon/authenticated: só as funções definer do owner leem.
-- Documento: só dígitos; 9–11 → lpad 11, 12–14 → lpad 14; repetido (000…, 111…) e fin.identidade_bloqueio fora.
create or replace function public.fn_aluno_compras_fora_base()
returns table (pessoa_chave text, ultima_paga_em timestamptz, em_ativacao boolean)
language sql
stable
as $fn$
  with
  pp as (   -- regra única do "pagou programa" (20261003a), última compra paga nos últimos 12 meses
    select p.email, p.ultima_paga_em
      from public.fn_aluno_pagamentos_programa() p
     where p.ultima_paga_em >= now() - interval '12 months'
       and (p.pg_hm or p.pg_impl or p.pg_aurum or p.pg_mmd)
  ),
  pes as (  -- e-mail → pessoa (sem identidade: a pessoa é o próprio e-mail)
    select coalesce(ep.pessoa_chave, '#email:' || pp.email) as chave, max(pp.ultima_paga_em) as ult
      from pp
      left join fin.vw_email_pessoa ep on ep.email = pp.email
     group by 1
  ),
  nos as (  -- todos os nós da pessoa (e-mails e documentos), menos os bloqueados
    select p.chave, i.no
      from pes p
      join fin.identidade i on i.pessoa_chave = p.chave
     where i.no like 'e:%' or i.no like 'd:%'
    union
    select p.chave, 'e:' || substr(p.chave, 8) from pes p where p.chave like '#email:%'
  ),
  nos_ok as (
    select n.chave, n.no from nos n
     where not exists (select 1 from fin.identidade_bloqueio b where b.valor = n.no)
  ),
  cp as (   -- compradores, chaves normalizadas
    select c.id, 'e:' || nullif(lower(trim(both from c.email)), '') as no_e,
           'd:' || (case when length(d.x) between 9 and 11 then lpad(d.x, 11, '0')
                         when length(d.x) between 12 and 14 then lpad(d.x, 14, '0') end) as no_d
      from public.compradores c
     cross join lateral (select regexp_replace(coalesce(c.documento, ''), '\D', '', 'g') as x) d
  ),
  comp as ( -- compradores da pessoa: por e-mail OU por documento (dois joins de igualdade, sem OR no join)
    select n.chave, cp.id from nos_ok n join cp on cp.no_e = n.no
    union
    select n.chave, cp.id from nos_ok n join cp on cp.no_d = n.no where cp.no_d !~ '^d:(\d)\1+$'
  ),
  al as (   -- alunos ativos, chaves normalizadas (e-mail = expressão do índice thb_alunos_email_uidx)
    select a.id, a.comprador_id,
           'e:' || nullif(lower(trim(both from a.email)), '') as no_e,
           'd:' || (case when length(d.x) between 9 and 11 then lpad(d.x, 11, '0')
                         when length(d.x) between 12 and 14 then lpad(d.x, 14, '0') end) as no_d
      from public.thb_alunos a
     cross join lateral (select regexp_replace(coalesce(a.documento, ''), '\D', '', 'g') as x) d
     where a.cancelado_em is null
  ),
  al_nos as (
    select al.no_e as no from al where al.no_e is not null
    union
    select al.no_d from al where al.no_d is not null and al.no_d !~ '^d:(\d)\1+$'
  ),
  casa as (  -- a pessoa já é aluno ativo: mesmo nó, mesma pessoa em fin.identidade, ou comprador ligado ao aluno
    select n.chave from nos_ok n join al_nos x on x.no = n.no
    union
    select i.pessoa_chave from al_nos x join fin.identidade i on i.no = x.no
    union
    select c.chave from comp c join al on al.comprador_id = c.id
  ),
  card as (  -- card na Ativação (aberto ou cancelado): pelo comprador, ou por aluno (inclusive cancelado) com o mesmo e-mail
    select c.chave from comp c join cs.contatos_hm h on h.comprador_id = c.id
    union
    select n.chave
      from nos_ok n
      join public.thb_alunos a2 on 'e:' || lower(trim(both from a2.email)) = n.no
      join cs.contatos_hm h on h.aluno_id = a2.id
  )
  select p.chave, p.ult, exists (select 1 from card k where k.chave = p.chave)
    from pes p
   where not exists (select 1 from casa c where c.chave = p.chave)
$fn$;

comment on function public.fn_aluno_compras_fora_base() is
  '20261003e: pessoas com compra paga de programa nos últimos 12 meses sem aluno ativo (pessoa, e-mail, documento ou '
  'comprador). em_ativacao = tem card em cs.contatos_hm. Devolve a pessoa_chave CRUA: interna, sem EXECUTE para '
  'public/anon/authenticated. Leitores: fn_aluno_conciliacao e fn_aluno_conciliacao_ref (via fin.chave_opaca).';

revoke all on function public.fn_aluno_compras_fora_base() from public, anon, authenticated;

-- ─── 3. Conciliação (leitura) ───────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_conciliacao(p_aluno uuid default null, p_incluir_conferidos boolean default false)
returns table (item text, aluno_id uuid, ref_aluno_id uuid, ref_externa text, grupo text, tipo text,
               severidade text, acao text, detalhe jsonb, conferido boolean, decisao_id bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_conciliacao: acesso restrito à equipe' using errcode = '42501';
  end if;

  return query
  with
  al as (   -- 1 passada em thb_alunos (ativos) com as chaves normalizadas
    select a.id, a.eh_socio, a.socio_de_aluno_id as fk, (nullif(btrim(a.socio_de_nome), '') is not null) as tem_nome_titular,
           a.plano, a.espaco_instrucao as espaco, a.turma_id, a.turma_aurum_id, a.data_compra, a.data_expiracao,
           nullif(lower(trim(both from a.email)), '') as email_n,
           case when length(d.x) between 9 and 11 then lpad(d.x, 11, '0')
                when length(d.x) between 12 and 14 then lpad(d.x, 14, '0') end as doc_n,
           controle.fone_key(coalesce(a.telefone_e164, a.telefone)) as fone_k   -- = expressão de ix_thb_alunos_fone_key_ativo
      from public.thb_alunos a
     cross join lateral (select regexp_replace(coalesce(a.documento, ''), '\D', '', 'g') as x) d
     where a.cancelado_em is null
  ),
  bloq as (select b.valor from fin.identidade_bloqueio b),
  ide as (  -- pessoa pelo e-mail e pelo documento (identidade_pkey)
    select al.id, ie.pessoa_chave as p_email, idd.pessoa_chave as p_doc
      from al
      left join fin.identidade ie  on ie.no  = 'e:' || al.email_n
      left join fin.identidade idd on idd.no = 'd:' || al.doc_n
                                  and not exists (select 1 from bloq where bloq.valor = 'd:' || al.doc_n)
  ),
  gps_ids as (
    select m.aluno_id as id, (m.papel = 'titular') as titular from gps.membros m
    union
    select m.pessoa_aluno_id, (m.papel = 'titular') from gps.membros m where m.pessoa_aluno_id is not null
  ),
  -- ── vínculo ──
  pag as (  -- S2: compra paga de programa PRÓPRIA, por pessoa (mesma regra da 20261003c)
    select coalesce(ep.pessoa_chave, '#email:' || pp.email) as chave
      from public.fn_aluno_pagamentos_programa() pp
      left join fin.vw_email_pessoa ep on ep.email = pp.email
     where pp.pg_hm or pp.pg_catalogo or pp.pg_aurum or pp.pg_mmd
     group by 1
  ),
  par as (
    select x.id, y.id as outro,
           (x.eh_socio is false) as s1_e, (y.eh_socio is false) as s1_o
      from al x
      join al y on y.id = x.fk and y.fk = x.id
     where x.id <> y.id
  ),
  par_sinal as (
    select p.*,
           exists (select 1 from pag g join ide i on g.chave in (i.p_email, '#email:' || ax.email_n)
                    where i.id = p.id)                                                      as s2_e,
           exists (select 1 from pag g join ide i on g.chave in (i.p_email, '#email:' || ay.email_n)
                    where i.id = p.outro)                                                   as s2_o,
           exists (select 1 from gps_ids gi where gi.id = p.id and gi.titular)              as gps_e,
           exists (select 1 from gps_ids gi where gi.id = p.outro and gi.titular)           as gps_o
      from par p
      join al ax on ax.id = p.id
      join al ay on ay.id = p.outro
  ),
  vinc as (
    select md5('socio_par_mutuo|' || least(s.id, s.outro)::text || '|' || greatest(s.id, s.outro)::text) as item,
           s.id as aluno_id, s.outro as ref_aluno_id, null::text as ref_externa,
           'vinculo'::text as grupo, 'socio_par_mutuo'::text as tipo, 'alta'::text as severidade, 'definir_titular'::text as acao,
           jsonb_build_object('cadastro_titular', s.s1_e, 'pagou_programa', s.s2_e, 'gps_titular', s.gps_e,
                              'outro_cadastro_titular', s.s1_o, 'outro_pagou_programa', s.s2_o, 'outro_gps_titular', s.gps_o,
                              'sugestao_titular',
                              case when s.s1_e <> s.s1_o then case when s.s1_e then 'este' else 'outro' end
                                   when s.s2_e <> s.s2_o then case when s.s2_e then 'este' else 'outro' end
                                   when s.gps_e <> s.gps_o then case when s.gps_e then 'este' else 'outro' end
                              end) as detalhe
      from par_sinal s
    union all
    -- autorreferência residual e cadeia (a → b, b → c, c ≠ a)
    select md5('socio_cadeia|' || x.id::text || '|' || x.fk::text || '|' || coalesce(y.fk::text, '-')),
           x.id, case when x.fk = x.id then null else x.fk end, null,
           'vinculo', 'socio_cadeia', 'alta', 'definir_titular',
           jsonb_build_object('caso', case when x.fk = x.id then 'autorreferencia' else 'cadeia' end,
                              'eh_socio', x.eh_socio)
      from al x
      left join al y on y.id = x.fk
     where x.fk = x.id
        or (y.fk is not null and y.fk <> x.id and y.id <> x.id)
    union all
    select md5('socio_sem_vinculo|' || x.id::text), x.id, null, null,
           'vinculo', 'socio_sem_vinculo', 'media', 'definir_titular',
           jsonb_build_object('tem_nome_titular', x.tem_nome_titular)
      from al x
     where x.eh_socio and x.fk is null
    union all
    select md5('vinculo_sem_marcacao|' || x.id::text || '|' || x.fk::text), x.id, x.fk, null,
           'vinculo', 'vinculo_sem_marcacao', 'media', 'confirmar_papel', '{}'::jsonb
      from al x
      join al y on y.id = x.fk
     where x.eh_socio is false and x.fk <> x.id and y.fk is null
    union all
    select md5('socio_diverge_titular|' || x.id::text || '|' || x.fk::text || '|' || array_to_string(v.campos, ',')
               || '|' || coalesce(x.plano, '') || '|' || coalesce(y.plano, '') || '|' || coalesce(x.espaco, '') || '|'
               || coalesce(y.espaco, '') || '|' || coalesce(x.turma_id::text, '') || '|' || coalesce(y.turma_id::text, '')),
           x.id, x.fk, null, 'vinculo', 'socio_diverge_titular', 'baixa', 'alinhar_ao_titular',
           jsonb_build_object('campos', to_jsonb(v.campos),
                              'plano', x.plano, 'plano_titular', y.plano,
                              'espaco', x.espaco, 'espaco_titular', y.espaco,
                              'turma_id', x.turma_id, 'turma_id_titular', y.turma_id)
      from al x
      join al y on y.id = x.fk
     cross join lateral (select array_remove(array[
                           case when x.plano   is distinct from y.plano    then 'plano'  end,
                           case when x.espaco  is distinct from y.espaco   then 'espaco' end,
                           case when x.turma_id is distinct from y.turma_id then 'turma' end], null) as campos) v
     where x.fk <> x.id and y.fk is null and cardinality(v.campos) > 0
  ),
  -- ── identidade ──
  chaves as (
    select al.id, 'documento'::text as motivo, al.doc_n as k
      from al where al.doc_n is not null and al.doc_n !~ '^(\d)\1+$'
                and not exists (select 1 from bloq where bloq.valor = 'd:' || al.doc_n)
    union
    select al.id, 'telefone', al.fone_k from al where al.fone_k is not null and al.fone_k <> ''
    union
    select i.id, 'pessoa', i.p_email from ide i where i.p_email is not null
    union
    select i.id, 'pessoa', i.p_doc from ide i where i.p_doc is not null
  ),
  dup_par as (
    select x.id as a, y.id as b, array_agg(distinct x.motivo order by x.motivo) as motivos
      from chaves x
      join chaves y on y.motivo = x.motivo and y.k = x.k and y.id > x.id
     group by x.id, y.id
  ),
  dup as (
    select d.a, d.b, d.motivos
      from dup_par d
      join al xa on xa.id = d.a
      join al xb on xb.id = d.b
     where not (d.motivos = array['telefone']                                        -- só o telefone bate e os dois
                and (xa.fk = d.b or xb.fk = d.a or (xa.fk is not null and xa.fk = xb.fk)))  -- são ligados por vínculo
  ),
  ident as (
    select md5('possivel_duplicado|' || d.a::text || '|' || d.b::text || '|' || array_to_string(d.motivos, ',')) as item,
           l.aluno_id, l.ref_aluno_id, null::text as ref_externa, 'identidade'::text as grupo, 'possivel_duplicado'::text as tipo,
           (case when d.motivos && array['documento', 'pessoa'] then 'alta' else 'media' end)::text as severidade,
           'conferir_duplicado'::text as acao, jsonb_build_object('motivos', to_jsonb(d.motivos)) as detalhe
      from dup d
     cross join lateral (values (d.a, d.b), (d.b, d.a)) l(aluno_id, ref_aluno_id)
    union all
    select md5('conflito_identidade|' || i.id::text), i.id, null, null, 'identidade', 'conflito_identidade', 'alta',
           'revisar_identidade', '{}'::jsonb
      from ide i
     where i.p_email is not null and i.p_doc is not null and i.p_email <> i.p_doc
    union all
    select md5('email_vazio|' || al.id::text), al.id, null, null, 'identidade', 'email_vazio', 'media',
           'preencher_email', jsonb_build_object('eh_socio', al.eh_socio)
      from al where al.email_n is null
  ),
  -- ── programa ──
  ps as (select s.aluno_id, s.programas, s.revisar_motivos from public.fn_aluno_programas_safe() s),
  prog as (
    select md5('programa_a_revisar|' || ps.aluno_id::text || '|' || m.motivo) as item, ps.aluno_id, null::uuid as ref_aluno_id,
           null::text as ref_externa, 'programa'::text as grupo, 'programa_a_revisar'::text as tipo, 'media'::text as severidade,
           'ver_evidencias'::text as acao, jsonb_build_object('motivo', m.motivo) as detalhe
      from ps cross join lateral unnest(ps.revisar_motivos) m(motivo)
    union all
    select md5('sem_programa|' || al.id::text), al.id, null, null, 'programa', 'sem_programa', 'media',
           'confirmar_se_aluno', jsonb_build_object('plano', al.plano, 'espaco', al.espaco)
      from al join ps on ps.aluno_id = al.id
     where al.eh_socio is false and al.fk is null and cardinality(ps.programas) = 0
    union all
    select md5('gps_divergente|espaco|' || al.id::text || '|' || coalesce(al.espaco, '')), al.id, null, null,
           'programa', 'gps_divergente', 'media', 'alinhar_ao_gps',
           jsonb_build_object('caso', 'espaco_diferente', 'espaco', al.espaco)
      from al
     where al.espaco is distinct from 'holding_masters_implementacao'
       and exists (select 1 from gps_ids g where g.id = al.id)
    union all
    select md5('gps_divergente|cancelado|' || m.id::text || '|' || v.campo), a.id, null, m.id::text,
           'programa', 'gps_divergente', 'media', 'alinhar_ao_gps',
           jsonb_build_object('caso', 'aluno_cancelado', 'campo', v.campo, 'papel', m.papel)
      from gps.membros m
     cross join lateral (values ('aluno_id', m.aluno_id), ('pessoa_aluno_id', m.pessoa_aluno_id)) v(campo, id)
      join public.thb_alunos a on a.id = v.id and a.cancelado_em is not null
    union all
    select md5('card_hm_aluno_cancelado|' || h.id::text), a.id, null, h.id::text,
           'programa', 'card_hm_aluno_cancelado', 'info', 'avisar_ativacao', jsonb_build_object('produto', h.produto)
      from cs.contatos_hm h
      join public.thb_alunos a on a.id = h.aluno_id and a.cancelado_em is not null
     where h.cancelamento_efetivado_em is null
  ),
  -- ── cadastro ──
  cad as (
    select md5('cadastro_incoerente|' || al.id::text || '|' || array_to_string(v.campos, ',')) as item, al.id as aluno_id,
           null::uuid as ref_aluno_id, null::text as ref_externa, 'cadastro'::text as grupo, 'cadastro_incoerente'::text as tipo,
           'baixa'::text as severidade, 'corrigir_cadastro'::text as acao, jsonb_build_object('campos', to_jsonb(v.campos)) as detalhe
      from al
     cross join lateral (select array_remove(array[
                           case when al.plano = 'aurum' and al.turma_aurum_id is null then 'aurum_sem_turma' end,
                           case when al.turma_aurum_id is not null and al.plano <> 'aurum'
                                     and al.espaco is distinct from 'aurum' then 'turma_aurum_sem_aurum' end,
                           case when al.espaco = 'aurum' and al.plano = 'aluno' then 'espaco_aurum_plano_aluno' end,
                           case when al.espaco is null then 'sem_espaco' end,
                           case when al.turma_id is null then 'sem_turma' end], null) as campos) v
     where cardinality(v.campos) > 0
    union all
    select md5('datas_incoerentes|' || al.id::text || '|' || array_to_string(v.campos, ',')), al.id, null, null,
           'cadastro', 'datas_incoerentes', 'baixa', 'corrigir_datas', jsonb_build_object('campos', to_jsonb(v.campos))
      from al
     cross join lateral (select array_remove(array[
                           case when al.data_compra > now() then 'data_compra_futura' end,
                           case when al.data_expiracao < al.data_compra::date then 'expiracao_antes_da_compra' end,
                           case when al.eh_socio is false and al.fk is null and al.data_expiracao is null
                                then 'titular_sem_expiracao' end], null) as campos) v
     where cardinality(v.campos) > 0
  ),
  -- ── acesso (mesma regra da rotina: fn_aluno_situacao_calculada, 20261003d) ──
  calc as (  -- 1 passada: calculada × gravado
    select c.aluno_id, c.situacao, c.status, c.preservado, c.motivo_preserva,
           t.situacao_acesso as g_situacao, t.status_acesso as g_status
      from public.fn_aluno_situacao_calculada() c
      join public.thb_alunos t on t.id = c.aluno_id
  ),
  ac as (
    select md5('revogado_com_vigencia|' || c.aluno_id::text || '|' || c.motivo_preserva || '|' || c.situacao) as item,
           c.aluno_id, null::uuid as ref_aluno_id, null::text as ref_externa, 'acesso'::text as grupo,
           'revogado_com_vigencia'::text as tipo, 'alta'::text as severidade, 'decidir_acesso'::text as acao,
           jsonb_build_object('motivo', c.motivo_preserva, 'calculado', c.situacao, 'gravado', c.g_situacao) as detalhe
      from calc c
     where c.preservado and c.motivo_preserva in ('sem_acesso', 'acessos_revogados') and c.situacao in ('em_dia', 'a_vencer')
    union all
    select md5('situacao_desatualizada|' || c.aluno_id::text || '|' || coalesce(c.g_situacao, '-') || '|'
               || coalesce(c.g_status, '-') || '|' || coalesce(c.situacao, '-') || '|' || coalesce(c.status, '-')),
           c.aluno_id, null, null, 'acesso', 'situacao_desatualizada', 'info', 'aguarda_rotina',
           jsonb_build_object('gravado', jsonb_build_object('situacao', c.g_situacao, 'status', c.g_status),
                              'calculado', jsonb_build_object('situacao', c.situacao, 'status', c.status))
      from calc c
     where not c.preservado
       and (c.g_situacao is distinct from c.situacao or c.g_status is distinct from c.status)
  ),
  -- ── fora da base ──
  fb as (   -- chave_opaca (HMAC com segredo do Vault) só nas linhas finais: 1 leitura do Vault por pessoa fora da base
    select fin.chave_opaca(f.pessoa_chave) as ref, f.ultima_paga_em, f.em_ativacao
      from public.fn_aluno_compras_fora_base() f
  ),
  fora as (
    select md5(case when fb.em_ativacao then 'comprou_em_ativacao|' else 'comprou_fora_da_base|' end || fb.ref) as item,
           null::uuid as aluno_id, null::uuid as ref_aluno_id, fb.ref as ref_externa, 'fora_base'::text as grupo,
           (case when fb.em_ativacao then 'comprou_em_ativacao' else 'comprou_fora_da_base' end)::text as tipo,
           (case when fb.em_ativacao then 'info' else 'alta' end)::text as severidade,
           (case when fb.em_ativacao then 'avisar_ativacao' else 'cadastrar_aluno' end)::text as acao,
           jsonb_build_object('ultima_paga_em', fb.ultima_paga_em::date) as detalhe
      from fb
    union all
    select md5('sip_sem_aluno|' || u.id::text), null, null, u.id::text, 'fora_base', 'sip_sem_aluno', 'media',
           'corrigir_email_sip', '{}'::jsonb
      from sip.users u
     where u.role = 'student'
       and not exists (select 1 from al where al.email_n = lower(trim(both from u.email)))
    union all
    select md5('placa_sem_aluno|' || s.id::text || '|' || coalesce(s.aluno_id::text, '-')), null, null, s.id::text,
           'fora_base', 'placa_sem_aluno', 'media', 'vincular_placa',
           jsonb_build_object('caso', case when s.aluno_id is null then 'sem_aluno' else 'aluno_inexistente' end,
                              'status', s.status)
      from public.thb_placas_solicitacoes s
     where s.aluno_id is null
        or not exists (select 1 from public.thb_alunos a where a.id = s.aluno_id)
  ),
  tudo as (
    select * from vinc union all select * from ident union all select * from prog
    union all select * from cad union all select * from ac union all select * from fora
  ),
  dcs as (  -- decisão vigente (uma por item: índice único parcial)
    select d.item, d.id from public.thb_aluno_conciliacao_decisao d where d.revertido_em is null
  )
  select t.item, t.aluno_id, t.ref_aluno_id, t.ref_externa, t.grupo, t.tipo, t.severidade, t.acao, t.detalhe,
         (d.id is not null), d.id
    from tudo t
    left join dcs d on d.item = t.item
   where (p_incluir_conferidos or d.id is null)
     and (p_aluno is null or t.aluno_id = p_aluno or t.ref_aluno_id = p_aluno)
   order by array_position(array['alta', 'media', 'baixa', 'info']::text[], t.severidade), t.grupo, t.tipo, t.item, t.aluno_id;
end;
$fn$;

comment on function public.fn_aluno_conciliacao(uuid, boolean) is
  '20261003e: fila de conciliação da base de alunos (só equipe). Sem nome/e-mail/documento/telefone na saída. '
  'item = md5(tipo|ids|estado); conferido/decisao_id vêm de thb_aluno_conciliacao_decisao (vigente = não revertida).';

revoke all on function public.fn_aluno_conciliacao(uuid, boolean) from public, anon;
grant execute on function public.fn_aluno_conciliacao(uuid, boolean) to authenticated;

-- ─── 4. Resumo (vigia/ops/ensaio) ───────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_conciliacao_resumo()
returns table (grupo text, tipo text, severidade text, itens bigint, alunos bigint, conferidos bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_conciliacao_resumo: acesso restrito à equipe' using errcode = '42501';
  end if;
  return query
  select c.grupo, c.tipo, c.severidade, count(distinct c.item), count(distinct c.aluno_id),
         count(distinct c.item) filter (where c.conferido)
    from public.fn_aluno_conciliacao(null, true) c
   group by c.grupo, c.tipo, c.severidade
   order by array_position(array['alta', 'media', 'baixa', 'info']::text[], c.severidade), c.grupo, c.tipo;
end;
$fn$;

comment on function public.fn_aluno_conciliacao_resumo() is
  '20261003e: contagem da conciliação por grupo/tipo/severidade (inclui conferidos). Só equipe.';

revoke all on function public.fn_aluno_conciliacao_resumo() from public, anon;
grant execute on function public.fn_aluno_conciliacao_resumo() to authenticated;

-- ─── 5. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
begin
  -- interna: ninguém de fora executa (nem por PUBLIC)
  if has_function_privilege('anon', 'public.fn_aluno_compras_fora_base()', 'execute')
     or has_function_privilege('authenticated', 'public.fn_aluno_compras_fora_base()', 'execute') then
    raise exception '20261003e: fn_aluno_compras_fora_base executável por anon/authenticated';
  end if;
  if exists (select 1 from pg_proc p where p.oid = 'public.fn_aluno_compras_fora_base()'::regprocedure
                and (p.prosecdef or p.proconfig is not null or p.provolatile <> 's')) then
    raise exception '20261003e: fn_aluno_compras_fora_base deixou de ser SQL invoker inlinável';
  end if;
  -- telas: definer + search_path; anon e PUBLIC fora; authenticated passa pela guarda do corpo
  if exists (select 1 from unnest(array['public.fn_aluno_conciliacao(uuid,boolean)', 'public.fn_aluno_conciliacao_resumo()']) f
              where has_function_privilege('anon', f, 'execute')
                 or not has_function_privilege('authenticated', f, 'execute')
                 or not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                                   and p.proconfig @> array['search_path=public, pg_temp'])
                 or exists (select 1 from pg_proc p, aclexplode(p.proacl) g
                             where p.oid = f::regprocedure and g.grantee = 0 and g.privilege_type = 'EXECUTE')) then
    raise exception '20261003e: grants/definer das funções de tela fora do esperado';
  end if;
  if pg_get_function_result('public.fn_aluno_conciliacao(uuid,boolean)'::regprocedure) not like '%conferido boolean, decisao_id bigint)' then
    raise exception '20261003e: decisao_id não é a última coluna de fn_aluno_conciliacao';
  end if;
  -- tabela de decisões: nada para anon/authenticated, RLS ligada, service_role sem delete/truncate
  if has_table_privilege('anon', 'public.thb_aluno_conciliacao_decisao', 'select')
     or has_table_privilege('authenticated', 'public.thb_aluno_conciliacao_decisao', 'select')
     or has_table_privilege('authenticated', 'public.thb_aluno_conciliacao_decisao', 'insert')
     or has_table_privilege('authenticated', 'public.thb_aluno_conciliacao_decisao', 'update')
     or has_table_privilege('service_role', 'public.thb_aluno_conciliacao_decisao', 'delete')
     or has_table_privilege('service_role', 'public.thb_aluno_conciliacao_decisao', 'truncate')
     or not (select c.relrowsecurity from pg_class c where c.oid = to_regclass('public.thb_aluno_conciliacao_decisao')) then
    raise exception '20261003e: permissões/RLS de thb_aluno_conciliacao_decisao fora do esperado';
  end if;
end $confere$;

-- ─── 1. Números (como postgres, com o JWT de um usuário de equipe: a guarda lê auth.uid()) ──────────────────────────
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
create temp table _z_c on commit drop as select * from public.fn_aluno_conciliacao(null, true);
select pg_temp.z_q('1.resumo', $q$select grupo, tipo, severidade, itens, alunos, conferidos from public.fn_aluno_conciliacao_resumo()$q$);
select pg_temp.z_q('1.teto', $q$select t.tipo, coalesce(c.itens, 0) itens, coalesce(c.linhas, 0) linhas, coalesce(c.alunos, 0) alunos, t.teto,
  case when (case when t.tipo = 'programa_a_revisar' then coalesce(c.alunos, 0) else coalesce(c.itens, 0) end) > t.teto then 'ACIMA' else 'ok' end
  from (values ('socio_par_mutuo', 122), ('socio_cadeia', 8), ('socio_sem_vinculo', 113), ('vinculo_sem_marcacao', 162),
               ('socio_diverge_titular', 125), ('possivel_duplicado', 32), ('conflito_identidade', 11), ('email_vazio', 21),
               ('programa_a_revisar', 423), ('sem_programa', 62), ('gps_divergente', 35), ('card_hm_aluno_cancelado', 2),
               ('cadastro_incoerente', 393), ('datas_incoerentes', 62), ('revogado_com_vigencia', 98),
               ('situacao_desatualizada', 262), ('comprou_fora_da_base', 8), ('comprou_em_ativacao', 8),
               ('sip_sem_aluno', 21), ('placa_sem_aluno', 4)) t(tipo, teto)
  left join (select tipo, count(distinct item) itens, count(*) linhas, count(distinct aluno_id) alunos from _z_c group by 1) c on c.tipo = t.tipo
 order by 1$q$);
select pg_temp.z_q('1.tipo_fora_do_catalogo', $q$select tipo, count(*) from _z_c where tipo not in ('socio_par_mutuo','socio_cadeia',
  'socio_sem_vinculo','vinculo_sem_marcacao','socio_diverge_titular','possivel_duplicado','conflito_identidade','email_vazio',
  'programa_a_revisar','sem_programa','gps_divergente','card_hm_aluno_cancelado','cadastro_incoerente','datas_incoerentes',
  'revogado_com_vigencia','situacao_desatualizada','comprou_fora_da_base','comprou_em_ativacao','sip_sem_aluno','placa_sem_aluno')
  group by 1$q$);
select pg_temp.z_q('1.pares', $q$select count(*) linhas, count(distinct item) itens,
  count(*) filter (where detalhe->>'sugestao_titular' is not null) com_sugestao from _z_c where tipo = 'socio_par_mutuo'$q$);
select pg_temp.z_q('1.cadeia_por_caso', $q$select detalhe->>'caso', count(*) from _z_c where tipo = 'socio_cadeia' group by 1$q$);
select pg_temp.z_q('1.duplicado_por_motivo', $q$select severidade, detalhe->'motivos', count(distinct item) from _z_c
  where tipo = 'possivel_duplicado' group by 1, 2 order by 1, 2$q$);
select pg_temp.z_q('1.gps_por_caso', $q$select detalhe->>'caso', count(*) from _z_c where tipo = 'gps_divergente' group by 1$q$);
select pg_temp.z_q('1.acesso_por_motivo', $q$select tipo, detalhe->>'motivo', count(*) from _z_c where grupo = 'acesso' group by 1, 2 order by 1, 2$q$);
select pg_temp.z_q('1.fora_base', $q$select tipo, severidade, count(*), min((detalhe->>'ultima_paga_em')::date), max((detalhe->>'ultima_paga_em')::date)
  from _z_c where tipo in ('comprou_fora_da_base', 'comprou_em_ativacao') group by 1, 2$q$);
-- varredura de PII: nenhum e-mail, nenhuma sequência de 11+ dígitos, ref_externa só uuid ou HMAC hex64, nenhum valor igual a doc/e-mail/fone real
select pg_temp.z_q('1.pii', $q$select
  count(*) filter (where detalhe::text like '%@%' or detalhe::text ~ '\d{11,}') detalhe_suspeito,
  count(*) filter (where ref_externa is not null and ref_externa !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
                                            and ref_externa !~ '^[0-9a-f]{64}$') ref_fora_do_formato,
  count(*) filter (where ref_externa like '%@%') ref_com_arroba,
  count(*) filter (where ref_externa is not null
                     and exists (select 1 from public.thb_alunos a
                                  where ref_externa in (a.email, a.documento, regexp_replace(coalesce(a.documento, ''), '\D', '', 'g'),
                                                        a.telefone, a.telefone_e164))) ref_igual_pii
  from _z_c$q$);
select pg_temp.z_q('1.item_unico_por_linha', $q$select count(*) from (select item from _z_c group by item having count(distinct tipo) > 1) x$q$);
select pg_temp.z_q('1.total', $q$select count(*) linhas, count(distinct item) itens, count(distinct aluno_id) alunos,
  count(*) filter (where conferido) conferidos, count(*) filter (where decisao_id is not null) com_decisao from _z_c$q$);

-- ─── 2. Decisão: o item some da lista aberta e volta com conferido/decisao_id (a escrita real é da 20261003f) ──────
select set_config('z.item', coalesce((select item from _z_c where tipo = 'socio_par_mutuo' order by item limit 1),
                                     (select item from _z_c order by item limit 1)), true);
insert into public.thb_aluno_conciliacao_decisao (item, tipo, aluno_id, decisao, observacao, decidido_por)
select c.item, c.tipo, c.aluno_id, 'conferido', 'ENSAIO 20261003e', current_setting('z.eq')::uuid
  from _z_c c where c.item = current_setting('z.item') order by c.aluno_id limit 1;
select set_config('z.dec', (select max(id)::text from public.thb_aluno_conciliacao_decisao where observacao = 'ENSAIO 20261003e'), true);
select pg_temp.z_q('2.decisao_aberta', $q$select count(*) from public.fn_aluno_conciliacao(null, false) where item = current_setting('z.item')$q$);
select pg_temp.z_q('2.decisao_com_conferidos', $q$select conferido, decisao_id, decisao_id = current_setting('z.dec')::bigint bate, count(*)
  from public.fn_aluno_conciliacao(null, true) where item = current_setting('z.item') group by 1, 2, 3$q$);
select pg_temp.z_q('2.decisao_resumo', $q$select tipo, itens, conferidos from public.fn_aluno_conciliacao_resumo() where conferidos > 0$q$);
select pg_temp.z_err('2.decisao_segunda_vigente', $q$insert into public.thb_aluno_conciliacao_decisao (item, tipo, decisao) values (current_setting('z.item'), 'x', 'conferido')$q$);
update public.thb_aluno_conciliacao_decisao set revertido_em = now(), revertido_por = current_setting('z.eq')::uuid
 where id = current_setting('z.dec')::bigint;
select pg_temp.z_q('2.decisao_revertida', $q$select conferido, decisao_id, count(*) from public.fn_aluno_conciliacao(null, false)
  where item = current_setting('z.item') group by 1, 2$q$);
select set_config('z.aluno', coalesce((select aluno_id::text from _z_c where aluno_id is not null order by tipo = 'socio_par_mutuo' desc, item, aluno_id limit 1), ''), true);
select pg_temp.z_q('2.p_aluno', $q$select count(*) total,
  count(*) filter (where aluno_id = nullif(current_setting('z.aluno'), '')::uuid or ref_aluno_id = nullif(current_setting('z.aluno'), '')::uuid) do_aluno
  from public.fn_aluno_conciliacao(nullif(current_setting('z.aluno'), '')::uuid, true)$q$);

-- ─── 3. Custo ───────────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_explain('3.explain_conciliacao', 'select count(*) from public.fn_aluno_conciliacao(null, false)');
select pg_temp.z_explain('3.explain_fora_base', 'select count(*) from public.fn_aluno_compras_fora_base()');
select pg_temp.z_explain('3.explain_resumo', 'select count(*) from public.fn_aluno_conciliacao_resumo()');

-- ─── 4. Permissões ──────────────────────────────────────────────────────────────────────────────────────────────────
select pg_temp.z_q('4.grants', $q$select f, r, has_function_privilege(r, f, 'execute') from unnest(array['public.fn_aluno_conciliacao(uuid,boolean)',
  'public.fn_aluno_conciliacao_resumo()','public.fn_aluno_compras_fora_base()']) f, unnest(array['anon','authenticated','service_role']) r order by 1, 2$q$);
select pg_temp.z_q('4.tabela', $q$select r, has_table_privilege(r, 'public.thb_aluno_conciliacao_decisao', 'select') sel,
  has_table_privilege(r, 'public.thb_aluno_conciliacao_decisao', 'insert') ins, has_table_privilege(r, 'public.thb_aluno_conciliacao_decisao', 'delete') del
  from unnest(array['anon','authenticated','service_role']) r$q$);
-- anon
set local role anon;
select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select pg_temp.z_err('4.anon_conciliacao', 'select count(*) from public.fn_aluno_conciliacao()');
select pg_temp.z_err('4.anon_resumo', 'select count(*) from public.fn_aluno_conciliacao_resumo()');
select pg_temp.z_err('4.anon_tabela', 'select count(*) from public.thb_aluno_conciliacao_decisao');
reset role;
-- authenticated fora da equipe (perfil ativo que não passa em gp_eh_equipe; sem ele, uuid inexistente)
select set_config('z.neq', coalesce((select p.id::text from public.perfis p where p.status = 'ativo'
                                       and not (p.email ilike '%@advmais.com') order by p.id limit 1), gen_random_uuid()::text), true);
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.neq'), 'role', 'authenticated')::text, true);
select pg_temp.z_err('4.nao_equipe_conciliacao', 'select count(*) from public.fn_aluno_conciliacao()');
select pg_temp.z_err('4.nao_equipe_resumo', 'select count(*) from public.fn_aluno_conciliacao_resumo()');
-- authenticated da equipe: a tela passa; o direto (tabela, função interna) não
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role', 'authenticated')::text, true);
select pg_temp.z_q('4.equipe_ok', 'select count(*) from public.fn_aluno_conciliacao()');
select pg_temp.z_err('4.equipe_direto_tabela', 'select count(*) from public.thb_aluno_conciliacao_decisao');
select pg_temp.z_err('4.equipe_direto_insert', $q$insert into public.thb_aluno_conciliacao_decisao (item, tipo, decisao) values ('x', 'x', 'conferido')$q$);
select pg_temp.z_err('4.equipe_direto_fora_base', 'select count(*) from public.fn_aluno_compras_fora_base()');
reset role;

-- ─── Resultado: UM select (o MCP mostra só o último resultado) e rollback ──────────────────────────────────────────
reset role;
select json_build_object('ensaio', '20261003e',
                         'linhas', (select json_agg(json_build_object('p', passo, 'l', linha) order by em) from _z_out)) as resultado;
rollback;
-- Se o cliente devolver só o resultado do rollback (vazio): troque as 2 linhas acima por
--   do $z$ begin raise exception 'ZOUT %', (select string_agg(passo || ' | ' || linha, E'\n' order by em) from pg_temp._z_out); end $z$;
-- (o erro desfaz tudo e traz a saída no texto do erro — padrão das 20261002d/e).
