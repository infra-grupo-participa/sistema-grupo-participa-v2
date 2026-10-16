-- Ensaio de 20261016234500_dados_atm_grupo_leads_apto.sql (transação desfeita, sobre produção). Só agregados na saída:
-- nenhum nome, e-mail ou telefone. Personas no papel authenticated com JWT: Victor (master, contato.ver), jessica
-- (contato.ver, não master), QA Tráfego e Deborah (sem contato.ver); anon.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', case when p_id is null then '{"role":"anon"}' else jsonb_build_object('sub', p_id, 'role', 'authenticated')::text end, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 600);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.tenta(uuid, text) to authenticated, anon;

set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '0 antes (versão 15/10) por origem',
  pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_object_agg(o, n)::text from (select origem o, count(*) n from public.dados_atm_grupo_leads('black-thb-2026-10') group by 1) z$q$);
reset role;
select set_config('request.jwt.claims', '', true);

do $g$
begin
  if to_regprocedure('public.dados_atm_grupo_leads(text, date, date)') is null then
    raise exception '20261016234500: public.dados_atm_grupo_leads(text, date, date) não existe';
  end if;
  if to_regprocedure('dados.atm_leads(text)') is null or to_regprocedure('dados.perfil(text)') is null
     or to_regprocedure('dados.atm_cadastro(text)') is null or to_regclass('dados.v_grupo_pessoas_todos') is null then
    raise exception '20261016234500: dependência ausente';
  end if;
end
$g$;

drop function public.dados_atm_grupo_leads(text, date, date);

create function public.dados_atm_grupo_leads(p_chave text, p_de date default null, p_ate date default null)
returns table (
  fone_grupo text, origem text, na_lista boolean, na_base boolean,
  nome text, email text, telefone text, turma text, instrucao text,
  entrou_em timestamptz, saiu_em timestamptz, no_grupo boolean, entrada_aproximada boolean,
  na_central boolean, apto boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards;
  v_ini timestamptz; v_fim timestamptz;
begin
  -- contato.ver primeiro (pentester 15/10): sem ele, nem a existência da chave vaza pela diferença P0002 x 42501
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  d := dados.atm_cadastro(p_chave);   -- 42501 sem acesso ao dashboard, P0002 chave fora do cadastro ou outro modelo
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with g as (
    select p.fone8, coalesce(p.fone_key, p.fone8) as fone, p.pessoa_id, p.entrou_em, p.saiu_em, p.no_grupo, p.entrada_aproximada
      from dados.v_grupo_pessoas_todos p
     where p.chave = d.chave and p.entrou_em >= v_ini and p.entrou_em < v_fim and not p.teste
  ),
  lst as materialized (
    select distinct on (right(controle.fone_key(a.telefone), 8))
           right(controle.fone_key(a.telefone), 8) as fk8, a.nome, m.email_norm as email, a.telefone
      from dados.lista_membros m
      join public.thb_alunos a on pessoas.norm_email(a.email) = m.email_norm
     where m.chave = d.chave and a.telefone is not null
     order by right(controle.fone_key(a.telefone), 8), a.eh_socio, a.id
  ),
  ld as materialized (
    select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id, x.nome, x.email, x.telefone, x.primeiro_em
      from dados.atm_leads(d.chave) x
     where not coalesce(x.teste, false)
  ),
  ce as materialized (
    -- Central de Alunos pelos 3 telefones; quando o mesmo número aparece em mais de um aluno, quem está na lista primeiro
    select distinct on (t.fk8) t.fk8, t.nome, t.email
      from (select right(controle.fone_key(f.tel), 8) as fk8, a.nome, pessoas.norm_email(a.email) as email, a.eh_socio, a.id
              from public.thb_alunos a
             cross join lateral (values (a.telefone), (a.telefone_e164), (a.telefone_profissional)) f(tel)
             where nullif(btrim(f.tel), '') is not null) t
     where length(t.fk8) = 8 and t.fk8 in (select g.fone8 from g)
     order by t.fk8, exists (select 1 from dados.lista_membros m where m.chave = d.chave and m.email_norm = t.email) desc, t.eh_socio, t.id
  ),
  c as (
    select g.*, l.nome as l_nome, l.email as l_email, l.telefone as l_tel,
           b.nome as b_nome, b.email as b_email, b.telefone as b_tel,
           k.nome as k_nome, k.email as k_email,
           (l.fk8 is not null) as em_lista, coalesce(b.achou, false) as em_base, (k.fk8 is not null) as em_central
      from g
      left join lst l on l.fk8 = g.fone8
      left join lateral (select true as achou, ld.nome, ld.email, ld.telefone from ld
                          where ld.fk8 = g.fone8 or (g.pessoa_id is not null and ld.pessoa_id = g.pessoa_id)
                          order by (ld.fk8 = g.fone8) desc, ld.primeiro_em limit 1) b on true
      left join ce k on k.fk8 = g.fone8
  )
  select c.fone,
         case when c.em_lista then 'lista_disparo' when c.em_base then 'base_leads'
              when c.em_central then 'central_alunos' else 'nao_encontrado' end,
         c.em_lista, c.em_base,
         coalesce(c.l_nome, c.b_nome, c.k_nome), coalesce(c.l_email, c.b_email, c.k_email), coalesce(c.l_tel, c.b_tel, c.fone),
         pf.turma, pf.instrucao,
         c.entrou_em, c.saiu_em, c.no_grupo, c.entrada_aproximada,
         c.em_central,
         -- lista_membros_email_idx (chave, email_norm): no ATM a lista da chave passa de 100 mil linhas
         (c.em_lista or exists (select 1 from dados.lista_membros m
                                 where m.chave = d.chave and m.email_norm is not null
                                   and m.email_norm = any (array[pessoas.norm_email(c.b_email), pessoas.norm_email(c.k_email)])))
    from c
    left join lateral (select x.turma, x.instrucao from dados.perfil(coalesce(c.l_email, c.b_email, c.k_email)) x
                        where coalesce(c.l_email, c.b_email, c.k_email) is not null limit 1) pf on true
   order by c.entrou_em desc, c.fone;
end
$function$;

comment on function public.dados_atm_grupo_leads(text, date, date) is
  '20261016234500: aba Leads e Resumo do modal Ingresso no grupo (acao-black e seminario-atm). Um número do grupo uma vez, cruzado com a lista do disparo, a base de leads e a Central de Alunos; apto = está na lista do disparo. Exige contato.ver.';

revoke all on function public.dados_atm_grupo_leads(text, date, date) from public, anon;
grant execute on function public.dados_atm_grupo_leads(text, date, date) to authenticated;

insert into pg_temp._z_out (passo, linha) select '0 acl', (select proacl::text from pg_proc where proname = 'dados_atm_grupo_leads');
insert into pg_temp._z_out (passo, linha) select '0 lista da chave', count(distinct email_norm)::text from dados.lista_membros where chave = 'black-thb-2026-10';
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '1 Victor agregados',
  pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object(
    'linhas', count(*), 'fones_distintos', count(distinct fone_grupo),
    'por_origem', (select jsonb_object_agg(o, n) from (select origem o, count(*) n from public.dados_atm_grupo_leads('black-thb-2026-10') group by 1) z),
    'apto', count(*) filter (where apto), 'nao_apto', count(*) filter (where not apto), 'apto_nulo', count(*) filter (where apto is null),
    'apto_sem_na_lista', count(*) filter (where apto and not na_lista),
    'apto_por_origem', (select jsonb_object_agg(o, n) from (select origem o, count(*) n from public.dados_atm_grupo_leads('black-thb-2026-10') where apto group by 1) z),
    'na_central', count(*) filter (where na_central), 'na_lista', count(*) filter (where na_lista), 'na_base', count(*) filter (where na_base),
    'com_nome', count(nome), 'com_email', count(email), 'com_turma', count(turma), 'com_instrucao', count(instrucao),
    'instrucoes', (select jsonb_object_agg(coalesce(i,'(vazio)'), n) from (select instrucao i, count(*) n from public.dados_atm_grupo_leads('black-thb-2026-10') group by 1) z),
    'nao_encontrado_com_campo', count(*) filter (where origem = 'nao_encontrado' and (nome is not null or email is not null or turma is not null or apto)),
    'central_sem_email', count(*) filter (where origem = 'central_alunos' and email is null))::text from public.dados_atm_grupo_leads('black-thb-2026-10')$q$);
insert into pg_temp._z_out (passo, linha) select '1 Victor ATM (outro modelo serve)',
  pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object('linhas', count(*), 'fones', count(distinct fone_grupo), 'por_origem', (select jsonb_object_agg(o, n) from (select origem o, count(*) n from public.dados_atm_grupo_leads('atm-elaine-1-2026-10') group by 1) z), 'apto', count(*) filter (where apto))::text from public.dados_atm_grupo_leads('atm-elaine-1-2026-10')$q$);
insert into pg_temp._z_out (passo, linha) select '1 Victor chave de outro modelo (black-friday)',
  pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select count(*)::text from public.dados_atm_grupo_leads('black-friday-2026-10')$q$);
insert into pg_temp._z_out (passo, linha) select '2 jessica (contato.ver, não master)',
  pg_temp.tenta('012bbcd3-cade-4889-a6ff-4804ed15c36d', $q$select count(*)::text from public.dados_atm_grupo_leads('black-thb-2026-10')$q$);
insert into pg_temp._z_out (passo, linha) select '3 QA Tráfego (sem contato.ver)',
  pg_temp.tenta('6e8d878d-086c-4b12-bef7-c424d89d85b6', $q$select count(*)::text from public.dados_atm_grupo_leads('black-thb-2026-10')$q$);
insert into pg_temp._z_out (passo, linha) select '3 Deborah (sem contato.ver)',
  pg_temp.tenta('5231a48f-a2d9-4c5f-8ee4-cde459aa7a9e', $q$select count(*)::text from public.dados_atm_grupo_leads('black-thb-2026-10')$q$);
reset role;
set local role anon;
insert into pg_temp._z_out (passo, linha) select '4 anon', pg_temp.tenta(null, $q$select count(*)::text from public.dados_atm_grupo_leads('black-thb-2026-10')$q$);
reset role;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select * from public.dados_atm_grupo_leads(''black-thb-2026-10'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Buffers: shared|Function Scan)' and r."QUERY PLAN" !~ '^\s{6,}' then
        insert into pg_temp._z_out (passo, linha) values ('5 explain black-thb ' || n, r."QUERY PLAN");
      end if;
    end loop;
    for r in execute 'explain (analyze, buffers) select * from public.dados_atm_grupo_leads(''atm-elaine-1-2026-10'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Buffers: shared|Function Scan)' and r."QUERY PLAN" !~ '^\s{6,}' then
        insert into pg_temp._z_out (passo, linha) values ('5 explain atm ' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

-- reversão ensaiada
drop function if exists public.dados_atm_grupo_leads(text, date, date);
create function public.dados_atm_grupo_leads(p_chave text, p_de date default null, p_ate date default null)
returns table (
  fone_grupo text, origem text, na_lista boolean, na_base boolean,
  nome text, email text, telefone text, turma text, instrucao text,
  entrou_em timestamptz, saiu_em timestamptz, no_grupo boolean, entrada_aproximada boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards;
  v_ini timestamptz; v_fim timestamptz;
begin
  -- contato.ver primeiro (pentester 15/10): sem ele, nem a existência da chave vaza pela diferença P0002 x 42501
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  d := dados.atm_cadastro(p_chave);   -- 42501 sem acesso ao dashboard, P0002 chave fora do cadastro ou outro modelo
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with g as (
    select p.fone8, coalesce(p.fone_key, p.fone8) as fone, p.pessoa_id, p.entrou_em, p.saiu_em, p.no_grupo, p.entrada_aproximada
      from dados.v_grupo_pessoas_todos p
     where p.chave = d.chave and p.entrou_em >= v_ini and p.entrou_em < v_fim and not p.teste
  ),
  lst as materialized (
    select distinct on (right(controle.fone_key(a.telefone), 8))
           right(controle.fone_key(a.telefone), 8) as fk8, a.nome, m.email_norm as email, a.telefone
      from dados.lista_membros m
      join public.thb_alunos a on pessoas.norm_email(a.email) = m.email_norm
     where m.chave = d.chave and a.telefone is not null
     order by right(controle.fone_key(a.telefone), 8), a.eh_socio, a.id
  ),
  ld as materialized (
    select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id, x.nome, x.email, x.telefone, x.primeiro_em
      from dados.atm_leads(d.chave) x
     where not coalesce(x.teste, false)
  ),
  c as (
    select g.*, l.nome as l_nome, l.email as l_email, l.telefone as l_tel,
           b.nome as b_nome, b.email as b_email, b.telefone as b_tel, (l.fk8 is not null) as em_lista, coalesce(b.achou, false) as em_base
      from g
      left join lst l on l.fk8 = g.fone8
      left join lateral (select true as achou, ld.nome, ld.email, ld.telefone from ld
                          where ld.fk8 = g.fone8 or (g.pessoa_id is not null and ld.pessoa_id = g.pessoa_id)
                          order by (ld.fk8 = g.fone8) desc, ld.primeiro_em limit 1) b on true
  )
  select c.fone,
         case when c.em_lista then 'lista_disparo' when c.em_base then 'base_leads' else 'nao_encontrado' end,
         c.em_lista, c.em_base,
         coalesce(c.l_nome, c.b_nome), coalesce(c.l_email, c.b_email), coalesce(c.l_tel, c.b_tel, c.fone),
         pf.turma, pf.instrucao,
         c.entrou_em, c.saiu_em, c.no_grupo, c.entrada_aproximada
    from c
    left join lateral (select x.turma, x.instrucao from dados.perfil(coalesce(c.l_email, c.b_email)) x
                        where coalesce(c.l_email, c.b_email) is not null limit 1) pf on true
   order by c.entrou_em desc, c.fone;
end
$function$;

comment on function public.dados_atm_grupo_leads(text, date, date) is
  '20261015210000: aba Leads do modal Ingresso no grupo (acao-black e seminario-atm). Um número do grupo uma vez, cruzado com a lista do disparo e a base de leads. Exige contato.ver.';

revoke all on function public.dados_atm_grupo_leads(text, date, date) from public, anon;
grant execute on function public.dados_atm_grupo_leads(text, date, date) to authenticated;
insert into pg_temp._z_out (passo, linha) select '6 depois da reversão', (select pg_get_function_result(p.oid) from pg_proc p where p.proname = 'dados_atm_grupo_leads');

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
