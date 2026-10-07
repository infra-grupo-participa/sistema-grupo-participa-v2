-- Ensaio de 20261007v_acesso_log_devolucao_admin.sql: 2 passadas num só begin … rollback. Gerado a partir dos .sql
-- como estão. Rodar com aplica_sql.py ensaio (o fim vira raise com a saída). Nada persiste.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;


insert into pg_temp._z_out (passo, linha) select '1 antes', (select jsonb_build_object('log_total', (select count(*) from acesso.log), 'log_motivo', (select jsonb_agg(jsonb_build_object('p', left(perfil_id::text,4), 'autor_jp', autor = '843d43db-73b3-44a9-b449-1731e362dbc3', 'quando', quando, 'antes', antes ->> 'cargo', 'depois', depois ->> 'cargo')) from acesso.log where depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10'), 'admin_dev', (select count(*) from public.perfis where cargo in ('admin','dev'))))::text;

-- ===== PASSADA 1: 20261007v_acesso_log_devolucao_admin.sql =====
-- 20261007v: níveis de acesso, registro em acesso.log da devolução manual de admin/dev feita às 18:39:06 UTC.
--
-- STATUS: NÃO APLICADA. Relatório: 20261007v.explain.md.
--
-- POR QUE
--   Às 2026-10-07 18:39:06.040019 UTC, um update como postgres (pg_stat_statements, achado do pentester) devolveu, a
--   partir da foto acesso.perfis_antes_20261007, o cargo admin a Cristiane (#1b15), Fernanda Tavares (#00b1) e Isabela
--   Teixeira (#e1d2), e dev a Elaine Montenegro (#6ed2), Marcio Carvalho de Sá (#ec6d) e Aldri Santana (#0f6d), com
--   status, áreas, funções e CPF da foto. A mudança não passou por acesso.log. Decisão do Victor Hugo (07/10/2026, noite):
--   foi o João Pedro Alves, de propósito, para quem precisava; fica assim. Esta migration só REGISTRA o que aconteceu
--   (uma linha por pessoa), com autor João Pedro Alves e o motivo. Não muda perfis nem acesso.
--
-- AS 5 PERGUNTAS
--   escala: 6 linhas em acesso.log. índice: PK. frequência: uma vez. repetição: nenhuma.
--   reversão: nenhuma (o log só aceita acréscimo, de propósito); se precisar corrigir, acrescentar linha de correção.
--
-- IDEMPOTENTE: só insere se ainda não houver linha com este motivo para a pessoa.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select count(*) from public.perfis p
       where p.id in ('1b153c6d-6287-43ae-9e02-6caf6e6f9c33', '00b177e0-3c8b-4e55-8f64-f57560bbbd74',
                      'e1d2863d-c975-46bd-b35f-45b1039328e3', '6ed2bfc4-1d69-458d-9954-77a03902c56a',
                      'ec6d1905-200e-4efd-a172-8546f293a4bd', '0f6dd53c-6d1a-4f6b-af00-dc05e6284f68')
         and p.atualizado_em = timestamptz '2026-10-07 18:39:06.040019+00') <> 6
     and not exists (select 1 from acesso.log where tabela = 'perfis'
                       and depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10') then
    raise exception '20261007v: os 6 perfis não estão mais no estado das 18:39:06. Reler antes de registrar.';
  end if;
  if (select nome from public.perfis where id = '843d43db-73b3-44a9-b449-1731e362dbc3') is distinct from 'João Pedro Alves' then
    raise exception '20261007v: autor esperado (João Pedro Alves) não confere';
  end if;
end
$g$;

insert into acesso.log (quando, autor, tabela, acao, perfil_id, antes, depois)
select timestamptz '2026-10-07 18:39:06.040019+00', '843d43db-73b3-44a9-b449-1731e362dbc3', 'perfis', 'update', p.id,
       jsonb_build_object('cargo', 'visualizador', 'status', f.status, 'areas', f.areas, 'funcoes', f.funcoes,
                          'cpf', case when p.id = '00b177e0-3c8b-4e55-8f64-f57560bbbd74' then false else f.pode_ver_cpf_completo end,
                          'nota', 'estado depois da fase 2 (20261007182928)'),
       jsonb_build_object('cargo', p.cargo, 'status', p.status, 'areas', p.areas, 'funcoes', p.funcoes,
                          'cpf', p.pode_ver_cpf_completo,
                          'motivo', 'devolução manual de admin/dev, decisão do Victor 07/10',
                          'via', 'postgres, update a partir de acesso.perfis_antes_20261007 (sem gatilho de log na hora)',
                          'registrado_em', now(), 'registrado_por', 'migration 20261007v')
  from public.perfis p join acesso.perfis_antes_20261007 f on f.id = p.id
 where p.id in ('1b153c6d-6287-43ae-9e02-6caf6e6f9c33', '00b177e0-3c8b-4e55-8f64-f57560bbbd74',
                'e1d2863d-c975-46bd-b35f-45b1039328e3', '6ed2bfc4-1d69-458d-9954-77a03902c56a',
                'ec6d1905-200e-4efd-a172-8546f293a4bd', '0f6dd53c-6d1a-4f6b-af00-dc05e6284f68')
   and not exists (select 1 from acesso.log l where l.tabela = 'perfis' and l.perfil_id = p.id
                     and l.depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10');

do $c$
begin
  if (select count(*) from acesso.log where tabela = 'perfis'
       and depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10') <> 6 then
    raise exception '20261007v: esperava 6 linhas de registro';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '2 depois1', (select jsonb_build_object('log_total', (select count(*) from acesso.log), 'log_motivo', (select jsonb_agg(jsonb_build_object('p', left(perfil_id::text,4), 'autor_jp', autor = '843d43db-73b3-44a9-b449-1731e362dbc3', 'quando', quando, 'antes', antes ->> 'cargo', 'depois', depois ->> 'cargo')) from acesso.log where depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10'), 'admin_dev', (select count(*) from public.perfis where cargo in ('admin','dev'))))::text;

-- ===== PASSADA 2: 20261007v_acesso_log_devolucao_admin.sql =====
-- 20261007v: níveis de acesso, registro em acesso.log da devolução manual de admin/dev feita às 18:39:06 UTC.
--
-- STATUS: NÃO APLICADA. Relatório: 20261007v.explain.md.
--
-- POR QUE
--   Às 2026-10-07 18:39:06.040019 UTC, um update como postgres (pg_stat_statements, achado do pentester) devolveu, a
--   partir da foto acesso.perfis_antes_20261007, o cargo admin a Cristiane (#1b15), Fernanda Tavares (#00b1) e Isabela
--   Teixeira (#e1d2), e dev a Elaine Montenegro (#6ed2), Marcio Carvalho de Sá (#ec6d) e Aldri Santana (#0f6d), com
--   status, áreas, funções e CPF da foto. A mudança não passou por acesso.log. Decisão do Victor Hugo (07/10/2026, noite):
--   foi o João Pedro Alves, de propósito, para quem precisava; fica assim. Esta migration só REGISTRA o que aconteceu
--   (uma linha por pessoa), com autor João Pedro Alves e o motivo. Não muda perfis nem acesso.
--
-- AS 5 PERGUNTAS
--   escala: 6 linhas em acesso.log. índice: PK. frequência: uma vez. repetição: nenhuma.
--   reversão: nenhuma (o log só aceita acréscimo, de propósito); se precisar corrigir, acrescentar linha de correção.
--
-- IDEMPOTENTE: só insere se ainda não houver linha com este motivo para a pessoa.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if (select count(*) from public.perfis p
       where p.id in ('1b153c6d-6287-43ae-9e02-6caf6e6f9c33', '00b177e0-3c8b-4e55-8f64-f57560bbbd74',
                      'e1d2863d-c975-46bd-b35f-45b1039328e3', '6ed2bfc4-1d69-458d-9954-77a03902c56a',
                      'ec6d1905-200e-4efd-a172-8546f293a4bd', '0f6dd53c-6d1a-4f6b-af00-dc05e6284f68')
         and p.atualizado_em = timestamptz '2026-10-07 18:39:06.040019+00') <> 6
     and not exists (select 1 from acesso.log where tabela = 'perfis'
                       and depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10') then
    raise exception '20261007v: os 6 perfis não estão mais no estado das 18:39:06. Reler antes de registrar.';
  end if;
  if (select nome from public.perfis where id = '843d43db-73b3-44a9-b449-1731e362dbc3') is distinct from 'João Pedro Alves' then
    raise exception '20261007v: autor esperado (João Pedro Alves) não confere';
  end if;
end
$g$;

insert into acesso.log (quando, autor, tabela, acao, perfil_id, antes, depois)
select timestamptz '2026-10-07 18:39:06.040019+00', '843d43db-73b3-44a9-b449-1731e362dbc3', 'perfis', 'update', p.id,
       jsonb_build_object('cargo', 'visualizador', 'status', f.status, 'areas', f.areas, 'funcoes', f.funcoes,
                          'cpf', case when p.id = '00b177e0-3c8b-4e55-8f64-f57560bbbd74' then false else f.pode_ver_cpf_completo end,
                          'nota', 'estado depois da fase 2 (20261007182928)'),
       jsonb_build_object('cargo', p.cargo, 'status', p.status, 'areas', p.areas, 'funcoes', p.funcoes,
                          'cpf', p.pode_ver_cpf_completo,
                          'motivo', 'devolução manual de admin/dev, decisão do Victor 07/10',
                          'via', 'postgres, update a partir de acesso.perfis_antes_20261007 (sem gatilho de log na hora)',
                          'registrado_em', now(), 'registrado_por', 'migration 20261007v')
  from public.perfis p join acesso.perfis_antes_20261007 f on f.id = p.id
 where p.id in ('1b153c6d-6287-43ae-9e02-6caf6e6f9c33', '00b177e0-3c8b-4e55-8f64-f57560bbbd74',
                'e1d2863d-c975-46bd-b35f-45b1039328e3', '6ed2bfc4-1d69-458d-9954-77a03902c56a',
                'ec6d1905-200e-4efd-a172-8546f293a4bd', '0f6dd53c-6d1a-4f6b-af00-dc05e6284f68')
   and not exists (select 1 from acesso.log l where l.tabela = 'perfis' and l.perfil_id = p.id
                     and l.depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10');

do $c$
begin
  if (select count(*) from acesso.log where tabela = 'perfis'
       and depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10') <> 6 then
    raise exception '20261007v: esperava 6 linhas de registro';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '3 depois2', (select jsonb_build_object('log_total', (select count(*) from acesso.log), 'log_motivo', (select jsonb_agg(jsonb_build_object('p', left(perfil_id::text,4), 'autor_jp', autor = '843d43db-73b3-44a9-b449-1731e362dbc3', 'quando', quando, 'antes', antes ->> 'cargo', 'depois', depois ->> 'cargo')) from acesso.log where depois ->> 'motivo' = 'devolução manual de admin/dev, decisão do Victor 07/10'), 'admin_dev', (select count(*) from public.perfis where cargo in ('admin','dev'))))::text;


set local statement_timeout = '60s';
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
