-- 20261007r: níveis de acesso, fase 0 (fundação). Schema acesso, quem é master, vínculo por departamento/área,
-- capacidades sensíveis, log só de acréscimo, funções de checagem, RPCs de gestão e o seed confirmado.
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007180503 (nome acesso_fundacao, era 20261007r), pelo aplica_sql.py aplicar
-- + insert em supabase_migrations.schema_migrations na mesma transação. md5 gravado = ddfd7ab31ec2b6e673f562e61108dd68 = este arquivo
-- antes desta troca de STATUS. Ensaio: 20261007180503_ensaio.sql. Relatório: 20261007180503.explain.md.
--
-- POR QUE
--   Pedido do Victor Hugo (07/10/2026): "garanta que as pessoas lideres das suas areas n podem mexer nas áreas dos
--   outros, só ver (e tem area q n vai poder ver, tipo financeiro). tipo o cara de web n pode iniciar projeto no
--   trafego". Hoje 22 dos 24 perfis ativos da equipe são admin ou dev, e mkt.pode_ver (leitura e escrita do Marketing)
--   é só gp_is_admin(). Plano: .maestri/entregas/niveis-de-acesso/plano.md (cérebro do Victor), decisões do Maestro em
--   decisoes-maestro.md (mesma pasta). Esta fase NÃO muda guarda nenhuma: só cria o modelo. Ninguém perde nem ganha.
--
-- O QUE FAZ
--   1. schema acesso (sem USAGE para anon/authenticated) e tabelas: departamento, area, master, vinculo (com vigência,
--      nunca apaga), capacidade (financeiro.ver, financeiro.operar, cpf.ver, contato.ver), log (só acréscimo).
--   2. Funções internas: acesso.eu(), eh_master(), pode_ver(depto, area), pode_editar(depto, area), tem(chave),
--      area_mkt(p_area). Regras:
--      - todo perfil ativo da equipe (@advmais.com) VÊ tudo, menos o departamento financeiro (só com financeiro.ver);
--      - EDITA: master; responsável do departamento (vínculo sem área, papel responsavel); vínculo na área pedida;
--        sem área pedida: em departamento SEM áreas (educacional, comercial, financeiro), qualquer vínculo no
--        departamento; em departamento COM áreas (marketing, infra), só o responsável do departamento ou o master;
--      - capacidade = master ou linha em acesso.capacidade. Nunca vem de "vê o resto".
--   3. Wrappers no public para o app e para as policies: gp_meu_acesso(), gp_acesso_pode_ver, gp_acesso_pode_editar,
--      gp_acesso_tem (nome novo: não sobrecarrega gp_pode_editar(p_setor)).
--   4. Gestão (só master, decisão 6 do Maestro): acesso_listar, acesso_vincular, acesso_desvincular,
--      acesso_capacidade_definir. Ninguém cria master por RPC (só por migration).
--   5. Seed: só o que está na fonte (Painel de KPIs, crm.vendedor, perfis) e nas decisões do Maestro (tabela no explain).
--
-- AS 5 PERGUNTAS
--   escala: ~50 perfis, ~20 vínculos, ~10 capacidades. índice: PKs, único parcial do vínculo vigente e
--   vinculo(perfil_id) where vigente_ate is null. frequência: as guardas rodam em toda RPC (CRM a cada 3 s por usuário):
--   cada checagem é busca por índice. repetição: o front chama gp_meu_acesso() uma vez por request.
--   reversão: drop schema acesso cascade + drop das funções public.gp_acesso_*, gp_meu_acesso e acesso_* (bloco no fim).
--
-- IDEMPOTENTE: create … if not exists / create or replace / on conflict do nothing. A guarda confere que cada perfil do
--   seed ainda tem o nome esperado (id errado aborta).

set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- 0. Guarda de premissa
do $g$
declare r record;
begin
  if to_regprocedure('public.gp_eh_equipe()') is null or to_regprocedure('public.gp_is_admin()') is null then
    raise exception '20261007r: gp_eh_equipe/gp_is_admin ausentes';
  end if;
  for r in select * from (values
      ('81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid, 'Victor Hugo'),
      ('3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid, 'Arthur Galvão'),
      ('843d43db-73b3-44a9-b449-1731e362dbc3'::uuid, 'João Pedro Alves'),
      ('e1d2863d-c975-46bd-b35f-45b1039328e3'::uuid, 'Isabela Teixeira'),
      ('bd5361bc-3c3f-4f85-8b5a-f21433d040e3'::uuid, 'Jonathan Mendes'),
      ('9d347183-5395-434e-9e96-2a65dde1a3cd'::uuid, 'Marcos Paulo'),
      ('b65dc9c1-8edb-4e7a-ae07-681555523093'::uuid, 'Iromar Júnior'),
      ('9d5fb8e7-f61e-459d-be04-d103ec783c08'::uuid, 'Luis Fernando Pinto Ferreira da Costa'),
      ('caf36b74-0441-4f0b-b2a6-b3af88705f02'::uuid, 'Caio Fábio'),
      ('1023e685-2b13-4365-a2d9-7e012afd4516'::uuid, 'renan'),
      ('9a3ea481-f46b-43a6-a418-e66b3d97b1ae'::uuid, 'emmanuel'),
      ('012bbcd3-cade-4889-a6ff-4804ed15c36d'::uuid, 'jessica'),
      ('0788cdcd-9a6e-4850-897d-89f3724f57b4'::uuid, 'Manuela'),
      ('46b36c51-06a6-4062-9e8f-41d2579b50c8'::uuid, 'guilherme'),
      ('7bd54635-0802-4a11-9e20-81ff137b6506'::uuid, 'matheusvasconcellos'),
      ('0f6dd53c-6d1a-4f6b-af00-dc05e6284f68'::uuid, 'Aldri Santana'),
      ('6ed2bfc4-1d69-458d-9954-77a03902c56a'::uuid, 'Elaine Montenegro'),
      ('ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid, 'Marcio Carvalho de Sá'),
      ('00b177e0-3c8b-4e55-8f64-f57560bbbd74'::uuid, 'Fernanda Tavares'),
      ('6f0c31a2-26cf-4ef0-a608-b482b1e92db8'::uuid, 'Robô de teste E2E (Financeiro)')) v(id, nome)
  loop
    if (select p.nome from public.perfis p where p.id = r.id) is distinct from r.nome then
      raise exception '20261007r: perfil % não é mais "%". Conferir o seed.', r.id, r.nome;
    end if;
  end loop;
end
$g$;

-- 1. Schema e tabelas
create schema if not exists acesso;
revoke all on schema acesso from public, anon, authenticated;
comment on schema acesso is 'Níveis de acesso por pessoa, departamento e área (20261007r). Só funções leem e escrevem.';

create table if not exists acesso.departamento (
  key   text primary key check (key ~ '^[a-z]+$'),
  label text not null
);
create table if not exists acesso.area (
  departamento text not null references acesso.departamento(key),
  key          text not null check (key ~ '^[a-z]+(-[a-z]+)*$'),
  label        text not null,
  primary key (departamento, key)
);
create table if not exists acesso.master (
  perfil_id  uuid primary key references public.perfis(id) on delete cascade,
  criado_por uuid,
  criado_em  timestamptz not null default now()
);
create table if not exists acesso.vinculo (
  id           bigint generated always as identity primary key,
  perfil_id    uuid not null references public.perfis(id) on delete cascade,
  departamento text not null references acesso.departamento(key),
  area         text,
  papel        text not null check (papel in ('responsavel', 'membro')),
  vigente_de   timestamptz not null default now(),
  vigente_ate  timestamptz,
  criado_por   uuid,
  criado_em    timestamptz not null default now(),
  constraint vinculo_area_fk foreign key (departamento, area) references acesso.area(departamento, key),
  constraint vinculo_vigencia_ck check (vigente_ate is null or vigente_ate >= vigente_de)
);
create unique index if not exists vinculo_vigente_uq on acesso.vinculo (perfil_id, departamento, coalesce(area, ''))
  where vigente_ate is null;
create index if not exists vinculo_perfil_vigente_idx on acesso.vinculo (perfil_id) where vigente_ate is null;
create table if not exists acesso.capacidade (
  perfil_id  uuid not null references public.perfis(id) on delete cascade,
  chave      text not null check (chave in ('financeiro.ver', 'financeiro.operar', 'cpf.ver', 'contato.ver')),
  criado_por uuid,
  criado_em  timestamptz not null default now(),
  primary key (perfil_id, chave)
);
create table if not exists acesso.log (
  id        bigint generated always as identity primary key,
  quando    timestamptz not null default now(),
  autor     uuid,
  tabela    text not null,
  acao      text not null,
  perfil_id uuid,
  antes     jsonb,
  depois    jsonb
);
alter table acesso.departamento enable row level security;
alter table acesso.area enable row level security;
alter table acesso.master enable row level security;
alter table acesso.vinculo enable row level security;
alter table acesso.capacidade enable row level security;
alter table acesso.log enable row level security;
revoke all on all tables in schema acesso from public, anon, authenticated;

-- log: grava toda mudança em master, vinculo e capacidade; o próprio log só aceita insert
create or replace function acesso.tg_log() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values ((select auth.uid()), tg_table_name, lower(tg_op),
          coalesce((case when tg_op = 'DELETE' then old else new end).perfil_id, null),
          case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end);
  return null;
end
$f$;
create or replace function acesso.tg_log_imutavel() returns trigger
language plpgsql set search_path = '' as $f$
begin
  raise exception 'acesso.log só aceita acréscimo' using errcode = '42501';
end
$f$;
revoke all on function acesso.tg_log(), acesso.tg_log_imutavel() from public, anon, authenticated;
drop trigger if exists log_master on acesso.master;
drop trigger if exists log_vinculo on acesso.vinculo;
drop trigger if exists log_capacidade on acesso.capacidade;
drop trigger if exists log_imutavel on acesso.log;
create trigger log_master after insert or update or delete on acesso.master for each row execute function acesso.tg_log();
create trigger log_vinculo after insert or update or delete on acesso.vinculo for each row execute function acesso.tg_log();
create trigger log_capacidade after insert or update or delete on acesso.capacidade for each row execute function acesso.tg_log();
create trigger log_imutavel before update or delete on acesso.log for each row execute function acesso.tg_log_imutavel();

-- 2. Departamentos e áreas (as chaves de web/shared/domain/departamentos.ts; telas do Comercial não viram área)
insert into acesso.departamento (key, label) values
  ('educacional', 'Educacional'), ('marketing', 'Marketing'), ('comercial', 'Comercial'),
  ('financeiro', 'Financeiro'), ('infra', 'Infra')
on conflict (key) do nothing;
insert into acesso.area (departamento, key, label) values
  ('marketing', 'web', 'Web'), ('marketing', 'mensageria', 'Mensageria'), ('marketing', 'trafego', 'Tráfego'),
  ('marketing', 'audiovisual', 'Audiovisual'), ('marketing', 'social-media', 'Social Media'), ('infra', 'dados', 'Dados')
on conflict (departamento, key) do nothing;

-- 3. Funções internas (rodam como dono; sem execute para a API)
create or replace function acesso.eu() returns uuid
language sql stable security definer set search_path = '' as $f$
  select p.id from public.perfis p
   where p.id = (select auth.uid()) and p.status = 'ativo' and p.email ilike '%@advmais.com'
$f$;

create or replace function acesso.eh_master() returns boolean
language sql stable security definer set search_path = '' as $f$
  select exists (select 1 from acesso.master m where m.perfil_id = acesso.eu())
$f$;

create or replace function acesso.tem(p_chave text) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce(acesso.eu() is not null
                  and (acesso.eh_master()
                       or exists (select 1 from acesso.capacidade c where c.perfil_id = acesso.eu() and c.chave = p_chave)),
                  false)
$f$;

create or replace function acesso.pode_ver(p_depto text, p_area text default null) returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce(acesso.eu() is not null and (p_depto is distinct from 'financeiro' or acesso.tem('financeiro.ver')), false)
$f$;

create or replace function acesso.pode_editar(p_depto text, p_area text default null) returns boolean
language sql stable security definer set search_path = '' as $f$
  with eu as (select acesso.eu() as id)
  select coalesce((select eu.id is not null from eu), false)
     and (acesso.eh_master()
          or exists (
            select 1 from acesso.vinculo v, eu
             where v.perfil_id = eu.id and v.vigente_ate is null and v.departamento = p_depto
               and (   (v.area is null and v.papel = 'responsavel')
                    or (p_area is not null and v.area = p_area)
                    or (p_area is null and not exists (select 1 from acesso.area a where a.departamento = p_depto)))))
$f$;

-- área do Marketing a partir do argumento antigo de mkt.pode_ver
create or replace function acesso.area_mkt(p_area text) returns text
language sql immutable set search_path = '' as $f$
  select case p_area when 'mkt_trafego' then 'trafego' when 'mkt_web' then 'web' when 'mkt_mensageria' then 'mensageria'
                     when 'trafego' then 'trafego' when 'web' then 'web' when 'mensageria' then 'mensageria'
                     when 'audiovisual' then 'audiovisual' when 'social-media' then 'social-media' end
$f$;

revoke all on function acesso.eu(), acesso.eh_master(), acesso.tem(text), acesso.pode_ver(text, text),
  acesso.pode_editar(text, text), acesso.area_mkt(text) from public, anon, authenticated;

-- 4. Wrappers para o app e para policies
create or replace function public.gp_acesso_pode_ver(p_depto text, p_area text default null) returns boolean
language sql stable security definer set search_path = '' as $f$ select acesso.pode_ver(p_depto, p_area) $f$;
create or replace function public.gp_acesso_pode_editar(p_depto text, p_area text default null) returns boolean
language sql stable security definer set search_path = '' as $f$ select acesso.pode_editar(p_depto, p_area) $f$;
create or replace function public.gp_acesso_tem(p_chave text) returns boolean
language sql stable security definer set search_path = '' as $f$ select acesso.tem(p_chave) $f$;

-- Uma chamada por request: tudo que o front precisa para mostrar ou esconder botão (o banco continua sendo a fronteira)
create or replace function public.gp_meu_acesso() returns jsonb
language sql stable security definer set search_path = '' as $f$
  with eu as (select acesso.eu() as id)
  select case when (select id from eu) is null then
           jsonb_build_object('equipe', false, 'master', false, 'vinculos', '[]'::jsonb, 'capacidades', '[]'::jsonb,
                              'ver', '[]'::jsonb, 'editar', '[]'::jsonb)
         else jsonb_build_object(
           'equipe', true,
           'master', acesso.eh_master(),
           'vinculos', coalesce((select jsonb_agg(jsonb_build_object('departamento', v.departamento, 'area', v.area,
                                                                      'papel', v.papel) order by v.departamento, v.area)
                                   from acesso.vinculo v, eu where v.perfil_id = eu.id and v.vigente_ate is null), '[]'::jsonb),
           'capacidades', coalesce((select jsonb_agg(c.chave order by c.chave) from (
                                      select k.chave from (values ('financeiro.ver'), ('financeiro.operar'), ('cpf.ver'),
                                                                  ('contato.ver')) k(chave)
                                       where acesso.tem(k.chave)) c), '[]'::jsonb),
           'ver', coalesce((select jsonb_agg(d.key order by d.key) from acesso.departamento d
                             where acesso.pode_ver(d.key)), '[]'::jsonb),
           'editar', coalesce((select jsonb_agg(x.k order by x.k) from (
                                  select d.key as k from acesso.departamento d where acesso.pode_editar(d.key)
                                  union all
                                  select a.departamento || '/' || a.key from acesso.area a
                                   where acesso.pode_editar(a.departamento, a.key)) x), '[]'::jsonb))
         end
$f$;

revoke all on function public.gp_acesso_pode_ver(text, text), public.gp_acesso_pode_editar(text, text),
  public.gp_acesso_tem(text), public.gp_meu_acesso() from public, anon;
grant execute on function public.gp_acesso_pode_ver(text, text), public.gp_acesso_pode_editar(text, text),
  public.gp_acesso_tem(text), public.gp_meu_acesso() to authenticated;

-- 5. Gestão (só master)
create or replace function public.acesso_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
begin
  if not acesso.eh_master() then raise exception 'sem acesso' using errcode = '42501'; end if;
  return jsonb_build_object(
    'masters', coalesce((select jsonb_agg(jsonb_build_object('perfil_id', m.perfil_id, 'nome', p.nome) order by p.nome)
                           from acesso.master m join public.perfis p on p.id = m.perfil_id), '[]'::jsonb),
    'vinculos', coalesce((select jsonb_agg(jsonb_build_object('id', v.id, 'perfil_id', v.perfil_id, 'nome', p.nome,
                             'status', p.status, 'departamento', v.departamento, 'area', v.area, 'papel', v.papel,
                             'vigente_de', v.vigente_de) order by v.departamento, v.area, p.nome)
                            from acesso.vinculo v join public.perfis p on p.id = v.perfil_id
                           where v.vigente_ate is null), '[]'::jsonb),
    'capacidades', coalesce((select jsonb_agg(jsonb_build_object('perfil_id', c.perfil_id, 'nome', p.nome, 'chave', c.chave)
                                order by c.chave, p.nome)
                               from acesso.capacidade c join public.perfis p on p.id = c.perfil_id), '[]'::jsonb),
    'departamentos', (select jsonb_agg(jsonb_build_object('key', d.key, 'label', d.label,
                         'areas', coalesce((select jsonb_agg(jsonb_build_object('key', a.key, 'label', a.label) order by a.key)
                                              from acesso.area a where a.departamento = d.key), '[]'::jsonb)) order by d.key)
                        from acesso.departamento d));
end
$f$;

create or replace function public.acesso_vincular(p_perfil uuid, p_departamento text, p_area text, p_papel text)
returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_area text := nullif(btrim(coalesce(p_area, '')), ''); v_id bigint;
begin
  if not acesso.eh_master() then raise exception 'sem acesso' using errcode = '42501'; end if;
  if not exists (select 1 from public.perfis p where p.id = p_perfil) then
    return jsonb_build_object('ok', false, 'msg', 'Perfil não encontrado.');
  end if;
  if not exists (select 1 from acesso.departamento d where d.key = p_departamento) then
    return jsonb_build_object('ok', false, 'msg', 'Departamento inválido.');
  end if;
  if v_area is not null and not exists (select 1 from acesso.area a where a.departamento = p_departamento and a.key = v_area) then
    return jsonb_build_object('ok', false, 'msg', 'Área inválida para o departamento.');
  end if;
  if p_papel not in ('responsavel', 'membro') then
    return jsonb_build_object('ok', false, 'msg', 'Papel inválido (responsavel ou membro).');
  end if;
  update acesso.vinculo set vigente_ate = now()
   where perfil_id = p_perfil and departamento = p_departamento and coalesce(area, '') = coalesce(v_area, '')
     and vigente_ate is null and papel <> p_papel;
  insert into acesso.vinculo (perfil_id, departamento, area, papel, criado_por)
  select p_perfil, p_departamento, v_area, p_papel, (select auth.uid())
   where not exists (select 1 from acesso.vinculo v where v.perfil_id = p_perfil and v.departamento = p_departamento
                       and coalesce(v.area, '') = coalesce(v_area, '') and v.vigente_ate is null)
  returning id into v_id;
  return jsonb_build_object('ok', true, 'id', v_id);
end
$f$;

create or replace function public.acesso_desvincular(p_vinculo bigint) returns jsonb
language plpgsql security definer set search_path = '' as $f$
begin
  if not acesso.eh_master() then raise exception 'sem acesso' using errcode = '42501'; end if;
  update acesso.vinculo set vigente_ate = now() where id = p_vinculo and vigente_ate is null;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Vínculo vigente não encontrado.'); end if;
  return jsonb_build_object('ok', true);
end
$f$;

create or replace function public.acesso_capacidade_definir(p_perfil uuid, p_chave text, p_ligar boolean) returns jsonb
language plpgsql security definer set search_path = '' as $f$
begin
  if not acesso.eh_master() then raise exception 'sem acesso' using errcode = '42501'; end if;
  if p_chave not in ('financeiro.ver', 'financeiro.operar', 'cpf.ver', 'contato.ver') then
    return jsonb_build_object('ok', false, 'msg', 'Capacidade inválida.');
  end if;
  if not exists (select 1 from public.perfis p where p.id = p_perfil) then
    return jsonb_build_object('ok', false, 'msg', 'Perfil não encontrado.');
  end if;
  if p_ligar then
    insert into acesso.capacidade (perfil_id, chave, criado_por) values (p_perfil, p_chave, (select auth.uid()))
    on conflict do nothing;
  else
    delete from acesso.capacidade where perfil_id = p_perfil and chave = p_chave;
  end if;
  return jsonb_build_object('ok', true);
end
$f$;

revoke all on function public.acesso_listar(), public.acesso_vincular(uuid, text, text, text),
  public.acesso_desvincular(bigint), public.acesso_capacidade_definir(uuid, text, boolean) from public, anon;
grant execute on function public.acesso_listar(), public.acesso_vincular(uuid, text, text, text),
  public.acesso_desvincular(bigint), public.acesso_capacidade_definir(uuid, text, boolean) to authenticated;

-- 6. Seed (fonte: Painel de KPIs kpi.pessoa_area cruzado por e-mail, crm.vendedor, perfis; decisões do Maestro)
insert into acesso.master (perfil_id) values
  ('81d2eaee-cce1-4058-8714-439b0fc6f970'),  -- Victor Hugo
  ('3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'),  -- Arthur Galvão (o perfil ativo)
  ('843d43db-73b3-44a9-b449-1731e362dbc3')   -- João Pedro Alves (o perfil ativo)
on conflict do nothing;

insert into acesso.vinculo (perfil_id, departamento, area, papel)
select v.perfil_id, v.departamento, v.area, v.papel
  from (values
    ('81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid, 'infra',       null::text,     'responsavel'),  -- Victor Hugo
    ('843d43db-73b3-44a9-b449-1731e362dbc3'::uuid, 'infra',       null,           'responsavel'),  -- João Pedro Alves
    ('e1d2863d-c975-46bd-b35f-45b1039328e3'::uuid, 'educacional', null,           'responsavel'),  -- Isabela Teixeira
    ('bd5361bc-3c3f-4f85-8b5a-f21433d040e3'::uuid, 'comercial',   null,           'responsavel'),  -- Jonathan Mendes
    ('9d347183-5395-434e-9e96-2a65dde1a3cd'::uuid, 'comercial',   null,           'membro'),       -- Marcos Paulo
    ('9d347183-5395-434e-9e96-2a65dde1a3cd'::uuid, 'marketing',   'mensageria',   'membro'),       -- Marcos Paulo
    ('b65dc9c1-8edb-4e7a-ae07-681555523093'::uuid, 'marketing',   'web',          'responsavel'),  -- Iromar Júnior
    ('9d5fb8e7-f61e-459d-be04-d103ec783c08'::uuid, 'marketing',   'web',          'membro'),       -- Luis Fernando
    ('caf36b74-0441-4f0b-b2a6-b3af88705f02'::uuid, 'marketing',   'trafego',      'responsavel'),  -- Caio Fábio
    ('1023e685-2b13-4365-a2d9-7e012afd4516'::uuid, 'marketing',   'trafego',      'membro'),       -- renan (Renan Schwarz)
    ('9a3ea481-f46b-43a6-a418-e66b3d97b1ae'::uuid, 'marketing',   'trafego',      'membro'),       -- emmanuel (Emmanuel Fernandes)
    ('012bbcd3-cade-4889-a6ff-4804ed15c36d'::uuid, 'marketing',   'mensageria',   'responsavel'),  -- jessica (Jéssica Ferreira)
    ('0788cdcd-9a6e-4850-897d-89f3724f57b4'::uuid, 'marketing',   'social-media', 'membro'),       -- Manuela (Manuela Rios)
    ('46b36c51-06a6-4062-9e8f-41d2579b50c8'::uuid, 'marketing',   'audiovisual',  'membro'),       -- guilherme (Guilherme Silva)
    ('7bd54635-0802-4a11-9e20-81ff137b6506'::uuid, 'marketing',   'audiovisual',  'membro')        -- matheusvasconcellos
  ) v(perfil_id, departamento, area, papel)
 where not exists (select 1 from acesso.vinculo x where x.perfil_id = v.perfil_id and x.departamento = v.departamento
                     and coalesce(x.area, '') = coalesce(v.area, '') and x.vigente_ate is null);

insert into acesso.capacidade (perfil_id, chave) values
  ('0f6dd53c-6d1a-4f6b-af00-dc05e6284f68', 'financeiro.ver'),     -- Aldri Santana (diretoria, decisão 5)
  ('6ed2bfc4-1d69-458d-9954-77a03902c56a', 'financeiro.ver'),     -- Elaine Montenegro (diretoria)
  ('ec6d1905-200e-4efd-a172-8546f293a4bd', 'financeiro.ver'),     -- Marcio Carvalho de Sá (diretoria)
  ('00b177e0-3c8b-4e55-8f64-f57560bbbd74', 'financeiro.ver'),     -- Fernanda Tavares (perfil com a área financeiro hoje)
  ('00b177e0-3c8b-4e55-8f64-f57560bbbd74', 'financeiro.operar'),  -- idem, com a função financeiro.operar hoje
  ('6f0c31a2-26cf-4ef0-a608-b482b1e92db8', 'financeiro.ver'),     -- Robô de teste E2E (Financeiro), área financeiro hoje
  ('e1d2863d-c975-46bd-b35f-45b1039328e3', 'cpf.ver')             -- Isabela Teixeira (decisão 7)
on conflict do nothing;

-- 7. Pós-condição
do $c$
begin
  if (select count(*) from acesso.master) <> 3 then raise exception '20261007r: esperava 3 masters'; end if;
  if (select count(*) from acesso.vinculo where vigente_ate is null) <> 15 then
    raise exception '20261007r: esperava 15 vínculos vigentes, achei %', (select count(*) from acesso.vinculo where vigente_ate is null);
  end if;
  if (select count(*) from acesso.capacidade) <> 7 then raise exception '20261007r: esperava 7 capacidades'; end if;
  if has_schema_privilege('authenticated', 'acesso', 'usage') or has_schema_privilege('anon', 'acesso', 'usage') then
    raise exception '20261007r: schema acesso exposto';
  end if;
  if has_function_privilege('anon', 'public.gp_meu_acesso()', 'execute')
     or not has_function_privilege('authenticated', 'public.gp_meu_acesso()', 'execute') then
    raise exception '20261007r: permissão errada em gp_meu_acesso';
  end if;
end
$c$;

-- REVERSÃO (numa transação; só antes da fase 1, que passa a chamar estas funções):
-- drop function if exists public.gp_meu_acesso(), public.gp_acesso_pode_ver(text, text), public.gp_acesso_pode_editar(text, text),
--   public.gp_acesso_tem(text), public.acesso_listar(), public.acesso_vincular(uuid, text, text, text),
--   public.acesso_desvincular(bigint), public.acesso_capacidade_definir(uuid, text, boolean);
-- drop schema acesso cascade;
