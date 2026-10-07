-- ENSAIO 20261007h (calendario_eventos) — roda tudo e termina em ROLLBACK. Nada persiste.
--
-- ESPERADOS (coluna ok = true em todas as linhas):
--   1. membro da equipe (perfil ativo @advmais.com, inclusive cargo visualizador) lê; PB26 vem com fase evento 09–11/11
--      e links de captura; não há coluna de orçamento/verba/receita/obs no retorno
--   2. usuário do auth.users SEM perfil (outro sistema) recebe 42501
--   3. perfil fora do domínio @advmais.com recebe 42501
--   4. perfil @advmais.com inativo recebe 42501
--   5. anon não tem EXECUTE (42501 de permissão)
--   6. janela > 400 dias recusa (22023)
--   7. proacl sem PUBLIC/anon
--   8. depois do ROLLBACK a função não existe (conferir com: select to_regprocedure('public.calendario_eventos(date,date)'))

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';


do $guarda$
begin
  if to_regprocedure('public.calendario_eventos(date, date)') is not null then
    raise exception '20261007h: public.calendario_eventos já existe';
  end if;
  if to_regclass('mkt.projetos') is null or to_regclass('mkt.especialistas') is null or to_regclass('mkt.unidades') is null
     or to_regclass('mkt.tipos_lancamento') is null or to_regclass('mkt.paginas') is null then
    raise exception '20261007h: falta mkt.projetos/especialistas/unidades/tipos_lancamento/paginas (20261005m, 20261006j)';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'mkt' and table_name = 'projetos'
        and column_name in ('captacao_inicio', 'captacao_fim', 'evento_inicio', 'evento_fim', 'etiqueta_clickup',
                            'tipo', 'unidade', 'tipo_lancamento', 'especialista_id', 'ativo', 'inicio', 'fim')) <> 12 then
    raise exception '20261007h: colunas esperadas de mkt.projetos não batem';
  end if;
  if to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception '20261007h: falta public.gp_eh_equipe()';
  end if;
end
$guarda$;

create function public.calendario_eventos(p_de date, p_ate date)
returns table (
  id                   bigint,
  chave                text,
  sigla                text,
  nome                 text,
  tipo                 text,
  unidade              text,
  unidade_nome         text,
  tipo_lancamento      text,
  tipo_lancamento_nome text,
  especialista         text,
  inicio               date,
  fim                  date,
  fases                jsonb,
  links                jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'calendario_eventos: acesso só da equipe' using errcode = '42501';
  end if;
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 400 then
    raise exception 'calendario_eventos: janela inválida (de <= até, no máximo 400 dias)' using errcode = '22023';
  end if;

  return query
  with base as (
    select p.id, p.etiqueta_clickup, p.sigla, p.nome, p.tipo, p.unidade, u.nome as unidade_nome,
           p.tipo_lancamento, tl.nome as tipo_lancamento_nome, e.nome as especialista,
           p.captacao_inicio, coalesce(p.captacao_fim, p.captacao_inicio) as captacao_fim,
           p.evento_inicio, coalesce(p.evento_fim, p.evento_inicio) as evento_fim,
           p.inicio as p_inicio, coalesce(p.fim, p.inicio) as p_fim
      from mkt.projetos p
      left join mkt.unidades u on u.codigo = p.unidade
      left join mkt.tipos_lancamento tl on tl.codigo = p.tipo_lancamento
      left join mkt.especialistas e on e.id = p.especialista_id
     where p.ativo
  ), periodo as (
    select b.*,
           least(b.captacao_inicio, b.evento_inicio, case when b.captacao_inicio is null and b.evento_inicio is null then b.p_inicio end) as ini,
           greatest(b.captacao_fim, b.evento_fim, case when b.captacao_inicio is null and b.evento_inicio is null then b.p_fim end) as fi
      from base b
  )
  select pr.id, pr.etiqueta_clickup, pr.sigla, pr.nome, pr.tipo, pr.unidade, pr.unidade_nome,
         pr.tipo_lancamento, pr.tipo_lancamento_nome, pr.especialista,
         pr.ini, pr.fi,
         coalesce((
           select jsonb_agg(f.obj order by f.ordem)
             from (values
               (1, case when pr.captacao_inicio is not null then jsonb_build_object(
                     'fase', 'captacao', 'inicio', pr.captacao_inicio, 'fim', pr.captacao_fim, 'interno', false) end),
               (2, case when pr.evento_inicio is not null then jsonb_build_object(
                     'fase', 'evento', 'inicio', pr.evento_inicio, 'fim', pr.evento_fim, 'interno', false) end),
               -- Projeto antigo sem captação nem evento, só com o período geral: vira "evento" (mesmo critério do
               -- gatilho da 20261006j, que deriva inicio/fim desses dois períodos).
               (3, case when pr.captacao_inicio is null and pr.evento_inicio is null and pr.p_inicio is not null
                     then jsonb_build_object('fase', 'evento', 'inicio', pr.p_inicio, 'fim', pr.p_fim, 'interno', false) end)
             ) as f(ordem, obj)
            where f.obj is not null
         ), '[]'::jsonb),
         coalesce((
           select jsonb_agg(jsonb_build_object('nome', pg.nome, 'url', 'https://' || pg.dominio || coalesce(pg.caminho, '/'))
                            order by pg.caminho)
             from mkt.paginas pg
            where pg.projeto_id = pr.id and pg.ativa and pg.funcao = 'captura' and pg.dominio is not null
         ), '[]'::jsonb)
    from periodo pr
   where pr.ini is null                                    -- sem data: a tela lista à parte
      or (pr.ini <= p_ate and coalesce(pr.fi, pr.ini) >= p_de)
   order by pr.ini nulls last, pr.nome;
end
$$;

revoke all on function public.calendario_eventos(date, date) from public, anon;
grant execute on function public.calendario_eventos(date, date) to authenticated;

comment on function public.calendario_eventos(date, date) is
  'Calendário da empresa (home /): projetos ativos de mkt.projetos com fases e páginas de captura, só campos não '
  'sensíveis. Guarda gp_eh_equipe(). Janela máx. 400 dias. 20261007h.';

-- REVERSÃO
--   drop function public.calendario_eventos(date, date);


create temp table _r (n int, caso text, ok boolean, detalhe text) on commit drop;
grant all on _r to public;

-- uuids escolhidos pelo critério, sem e-mail no arquivo
create temp table _u on commit drop as
select (select id from public.perfis where status = 'ativo' and email ilike '%@advmais.com' and cargo = 'visualizador' limit 1) as equipe_vis,
       (select id from public.perfis where status = 'ativo' and email ilike '%@advmais.com' and cargo in ('admin','dev') limit 1) as equipe_adm,
       (select u.id from auth.users u where not exists (select 1 from public.perfis p where p.id = u.id)
          and u.email not ilike '%@advmais.com' limit 1) as externo,
       (select id from public.perfis where email not ilike '%@advmais.com' limit 1) as fora_dominio,
       (select id from public.perfis where status <> 'ativo' and email ilike '%@advmais.com' limit 1) as inativo;
grant select on _u to public;

-- 1a. equipe (visualizador)
select set_config('request.jwt.claims', json_build_object('sub', (select equipe_vis from _u), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into _r select 1, 'equipe visualizador lê', count(*) > 0,
       string_agg(sigla || ' ' || coalesce(inicio::text,'sem data') || ' fases=' || fases::text || ' links=' || jsonb_array_length(links), ' | ')
  from public.calendario_eventos('2026-09-01', '2026-12-31');
insert into _r select 1, 'PB26 com fase evento 09–11/11 e links',
       bool_or(sigla = 'PB26' and fases @> '[{"fase":"evento","inicio":"2026-11-09","fim":"2026-11-11"}]' and jsonb_array_length(links) > 0), null
  from public.calendario_eventos('2026-11-01', '2026-11-30');
reset role;

-- 1b. equipe (admin)
select set_config('request.jwt.claims', json_build_object('sub', (select equipe_adm from _u), 'role', 'authenticated')::text, true);
set local role authenticated;
insert into _r select 1, 'equipe admin lê', count(*) > 0, null from public.calendario_eventos('2026-09-01', '2026-12-31');
reset role;

-- 1c. contrato: nenhuma coluna sensível
insert into _r select 1, 'retorno sem campo sensível',
       not exists (select 1 from unnest(p.proargnames) a where a ~* '(orcamento|verba|receita|valor|obs|criado_por|email)'),
       array_to_string(p.proargnames, ',')
  from pg_proc p where p.oid = 'public.calendario_eventos(date,date)'::regprocedure;

-- 2–4. fora da equipe
do $t$
declare r record; v_state text;
begin
  for r in select 2 as n, 'externo sem perfil' as caso, externo as uid from _u
           union all select 3, 'perfil fora do domínio', fora_dominio from _u
           union all select 4, 'perfil @advmais inativo', inativo from _u loop
    perform set_config('request.jwt.claims', json_build_object('sub', r.uid, 'role', 'authenticated')::text, true);
    execute 'set local role authenticated';
    begin
      perform * from public.calendario_eventos('2026-09-01', '2026-12-31');
      v_state := 'LEU';
    exception when others then v_state := sqlstate;
    end;
    execute 'reset role';
    insert into _r values (r.n, r.caso, r.uid is not null and v_state = '42501', coalesce(r.uid::text, 'SEM UID') || ' -> ' || v_state);
  end loop;
end
$t$;

-- 5. anon
select set_config('request.jwt.claims', '{"role":"anon"}', true);
do $t$
declare v_state text;
begin
  execute 'set local role anon';
  begin
    perform * from public.calendario_eventos('2026-09-01', '2026-12-31');
    v_state := 'EXECUTOU';
  exception when others then v_state := sqlstate || ' ' || sqlerrm;
  end;
  execute 'reset role';
  insert into _r values (5, 'anon não executa', v_state like '42501%permission denied%', v_state);
end
$t$;

-- 6. janela grande
select set_config('request.jwt.claims', json_build_object('sub', (select equipe_adm from _u), 'role', 'authenticated')::text, true);
do $t$
declare v_state text;
begin
  execute 'set local role authenticated';
  begin
    perform * from public.calendario_eventos('2026-01-01', '2027-12-31');
    v_state := 'ACEITOU';
  exception when others then v_state := sqlstate;
  end;
  execute 'reset role';
  insert into _r values (6, 'janela > 400 dias recusa', v_state = '22023', v_state);
end
$t$;

-- 7. proacl
insert into _r select 7, 'proacl sem PUBLIC/anon',
       not has_function_privilege('anon', 'public.calendario_eventos(date,date)', 'execute')
       and has_function_privilege('authenticated', 'public.calendario_eventos(date,date)', 'execute')
       and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0),
       p.proacl::text
  from pg_proc p where p.oid = 'public.calendario_eventos(date,date)'::regprocedure;

select * from _r order by n, caso;

rollback;
