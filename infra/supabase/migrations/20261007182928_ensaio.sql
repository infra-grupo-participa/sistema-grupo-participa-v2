-- Ensaio das fases 2 (20261007t) e 3 (20261007u) de níveis de acesso, sobre o banco com as fases 0 e 1 aplicadas.
-- Uma transação desfeita: foto atual, fase 2 duas vezes, provas, fase 3 duas vezes, provas. Nada persiste.
-- Rodar com aplica_sql.py ensaio. Saída: nomes de perfil e booleanos; nenhum e-mail, CPF ou telefone.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;

create function pg_temp.sonda(p_id uuid) returns jsonb language plpgsql as $s$
declare j jsonb; k text; a record;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  j := jsonb_build_object(
    'equipe', public.gp_eh_equipe(), 'admin', public.gp_is_admin(),
    'fin_ver', public.gp_pode_ver_financeiro(), 'fin_operar', public.gp_pode_operar_financeiro(), 'cpf', public.gp_pode_ver_cpf(),
    'crm_gestor', crm.eh_gestor(), 'crm_comercial', crm.eh_comercial(), 'crm_catalogar', crm.pode_catalogar(),
    'remocao', public.ra_pode_ver(), 'pedidos', public.pa_pode_pedir(), 'placas', public.gp_pode_editar('placas'),
    'base_pessoas', pessoas.pode_ver(),
    'mkt_ver', mkt.pode_ver('mkt_trafego'), 'ed_trafego', mkt.pode_editar('mkt_trafego'), 'ed_web', mkt.pode_editar('mkt_web'),
    'ed_mensageria', mkt.pode_editar('mkt_mensageria'),
    'gps', public.gp_is_admin() or coalesce(public.gp_acesso_pode_editar('educacional', null), false),
    'ver_financeiro', public.gp_acesso_pode_ver('financeiro', null));
  for a in select d.key as dep, null::text as ar from acesso.departamento d union all select ar2.departamento, ar2.key from acesso.area ar2 loop
    j := j || jsonb_build_object('ed:' || a.dep || coalesce('/' || a.ar, ''), public.gp_acesso_pode_editar(a.dep, a.ar));
  end loop;
  return j;
end $s$;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 100);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.sonda(uuid), pg_temp.tenta(uuid, text) to authenticated;

insert into pg_temp._z_out (passo, linha) select '0 atual (fases 0 e 1)', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), jsonb_build_object('cargo', p.cargo, 'status', p.status, 's', pg_temp.sonda(p.id))) from public.perfis p where p.status = 'ativo' or exists (select 1 from acesso.vinculo v where v.perfil_id = p.id and v.vigente_ate is null);

-- ===== FASE 2, passada 1 =====
-- 20261007t: níveis de acesso, fase 2 (rebaixar). Quem não é master deixa de ser admin/dev e passa a valer só pelos
-- vínculos e capacidades de acesso.*, com os ajustes que o Victor Hugo decidiu sobre o relatório (07/10/2026).
--
-- STATUS: NÃO APLICADA. Fase 2 aprovada pelo Victor Hugo (07/10/2026, ajustes abaixo, versão 3) e pelo pentester;
--   só aplicar quando o Maestro mandar. Relatório: .maestri/entregas/niveis-de-acesso/ensaio-fase2.md (cérebro);
--   resumo em 20261007t.explain.md. Ensaio: 20261007t_ensaio.sql (rollback).
--
-- POR QUE
--   É a fase que de fato impede o líder de Web de criar projeto no Tráfego: com a fase 1 a guarda é "velho OU novo", e o
--   "velho" (cargo admin) ainda abre tudo para quem não é master.
--
-- O QUE FAZ
--   1. Fotos antes de mexer: acesso.perfis_antes_20261007 (id, nome, status, cargo, areas, funcoes,
--      pode_ver_cpf_completo) de TODOS os perfis, e acesso.capacidade_antes_20261007. Nada é apagado.
--   2. Perfis ativos com admin ou dev que não são master → cargo visualizador (areas e funcoes ficam).
--   3. Decisões do Victor Hugo (07/10/2026) sobre o relatório:
--      - Thomas Henrique e Ana Camila: membro do Educacional;
--      - Jusy: membro do Comercial;
--      - Fernanda Tavares: RESPONSÁVEL do Financeiro no perfil #8c37 (a conta do Financeiro, confirmada pelo Maestro no
--        Auth em 07/10/2026). O responsável ganha financeiro.ver e financeiro.operar. O outro perfil (#00b1) vira leitor:
--        perde as capacidades financeiras e o pode_ver_cpf_completo (na foto, reversível). Nenhum perfil é apagado;
--      - Marco e Cristiane (Escritório, só precisam ver informação de venda; decisão do Victor sobre a v2): continuam
--        ativos, visualizador, só leitura, sem vínculo de edição, sem capacidade financeira e sem CPF;
--      - Eduardo Vinicius Silva e Gabriel Sales: acesso ao sistema DESATIVADO (status negado, o único valor fora de
--        ativo/pendente que o CHECK de perfis aceita). Não apaga perfil, usuário do Auth nem histórico;
--      - guilherme e matheusvasconcellos: entram (ativo), SÓ LEITURA: o vínculo de edição em marketing/audiovisual é
--        encerrado (vigente_ate), porque a área ainda não existe.
--   4. Ativa os pendentes que entram: renan, emmanuel, jessica (com vínculo), guilherme e matheusvasconcellos (leitores).
--
-- AS 5 PERGUNTAS
--   escala: ~23 updates em perfis, 4 vínculos novos, 2 encerrados, 4 linhas de capacidade. índice: PK.
--   frequência: uma vez. repetição: nenhuma. reversão: bloco REVERSÃO no fim (pelas fotos e pela vigência).
--
-- IDEMPOTENTE: fotos só uma vez (on conflict do nothing); vínculos e capacidades com where not exists / on conflict;
--   rodar de novo não muda nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.master') is null or to_regclass('acesso.corpo_antes') is null then
    raise exception '20261007t: faltam as fases 0 e 1 (20261007180503, 20261007181138)';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.provolatile = 'v' and p.prosrc ~ 'mkt\.pode_ver\(') then
    raise exception '20261007t: a fase 1 não está completa (escrita do Marketing ainda em mkt.pode_ver)';
  end if;
  if to_regclass('acesso.perfis_antes_20261007') is null
     and (select count(*) from acesso.master m join public.perfis p on p.id = m.perfil_id
           where p.status = 'ativo' and p.cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007t: os 3 masters não estão ativos com cargo admin/dev. Conferir antes de rebaixar.';
  end if;
end
$g$;

-- 0b. Os perfis das decisões, por id completo, com o nome esperado (id errado aborta)
drop table if exists pg_temp._t_pessoas;
create temp table _t_pessoas (id uuid primary key, nome text not null, papel text not null) on commit drop;
insert into _t_pessoas (id, nome, papel)
select p.id, p.nome, x.papel
  from (values ('Thomas Henrique', 'educacional'), ('Ana Camila', 'educacional'), ('Jusy', 'comercial'),
               ('Cristiane', 'leitor_escritorio'), ('Eduardo Vinicius Silva', 'desativar'), ('Gabriel Sales', 'desativar'),
               ('Marco', 'leitor_escritorio'), ('guilherme', 'leitor'), ('matheusvasconcellos', 'leitor')) x(nome, papel)
  join public.perfis p on p.nome = x.nome;
insert into _t_pessoas (id, nome, papel) values
  ('8c37c683-a430-4bdd-9295-57bc92fb98db', 'Fernanda Tavares', 'financeiro_responsavel'),
  ('00b177e0-3c8b-4e55-8f64-f57560bbbd74', 'Fernanda Tavares', 'financeiro_leitor');
do $p$
begin
  if (select count(*) from _t_pessoas) <> 11 then
    raise exception '20261007t: esperava 11 perfis das decisões, achei % (nome duplicado ou sumido)', (select count(*) from _t_pessoas);
  end if;
  if exists (select 1 from _t_pessoas t join public.perfis p on p.id = t.id where p.nome <> t.nome) then
    raise exception '20261007t: perfil da Fernanda Tavares com outro nome';
  end if;
  if exists (select 1 from _t_pessoas t where left(t.id::text, 4) not in
               ('998e', 'e303', '412d', '1b15', 'a9df', '3e10', '8501', '46b3', '7bd5', '8c37', '00b1')) then
    raise exception '20261007t: id fora dos conferidos no relatório (#998e #e303 #412d #1b15 #a9df #3e10 #8501 #46b3 #7bd5 #8c37 #00b1)';
  end if;
end
$p$;

-- 1. Fotos
create table if not exists acesso.perfis_antes_20261007 (
  id uuid primary key, nome text, status text, cargo text, areas text[], funcoes text[],
  pode_ver_cpf_completo boolean, foto_em timestamptz not null default now()
);
alter table acesso.perfis_antes_20261007 enable row level security;
revoke all on acesso.perfis_antes_20261007 from public, anon, authenticated;
insert into acesso.perfis_antes_20261007 (id, nome, status, cargo, areas, funcoes, pode_ver_cpf_completo)
select p.id, p.nome, p.status, p.cargo, p.areas, p.funcoes, p.pode_ver_cpf_completo from public.perfis p
on conflict (id) do nothing;
create table if not exists acesso.capacidade_antes_20261007 (
  perfil_id uuid not null, chave text not null, foto_em timestamptz not null default now(), primary key (perfil_id, chave)
);
alter table acesso.capacidade_antes_20261007 enable row level security;
revoke all on acesso.capacidade_antes_20261007 from public, anon, authenticated;
insert into acesso.capacidade_antes_20261007 (perfil_id, chave)
select c.perfil_id, c.chave from acesso.capacidade c
 where not exists (select 1 from acesso.capacidade_antes_20261007)  -- foto só na primeira vez
on conflict do nothing;

-- 2. Rebaixar quem não é master
update public.perfis p set cargo = 'visualizador', atualizado_em = now()
 where p.status = 'ativo' and p.cargo in ('admin', 'dev')
   and not exists (select 1 from acesso.master m where m.perfil_id = p.id);

-- 3. Decisões do Victor
insert into acesso.vinculo (perfil_id, departamento, area, papel)
select t.id, d.dep, null, d.papel
  from _t_pessoas t
  join (values ('educacional', 'educacional', 'membro'), ('comercial', 'comercial', 'membro'),
               ('financeiro_responsavel', 'financeiro', 'responsavel')) d(chave, dep, papel) on d.chave = t.papel
 where not exists (select 1 from acesso.vinculo v where v.perfil_id = t.id and v.departamento = d.dep
                     and v.area is null and v.vigente_ate is null);

insert into acesso.capacidade (perfil_id, chave)
select t.id, c.chave from _t_pessoas t cross join (values ('financeiro.ver'), ('financeiro.operar')) c(chave)
 where t.papel = 'financeiro_responsavel'
on conflict do nothing;

delete from acesso.capacidade c using _t_pessoas t
 where t.id = c.perfil_id and t.papel = 'financeiro_leitor' and c.chave in ('financeiro.ver', 'financeiro.operar');
update public.perfis p set pode_ver_cpf_completo = false, atualizado_em = now()
  from _t_pessoas t where t.id = p.id and t.papel = 'financeiro_leitor' and p.pode_ver_cpf_completo;

update acesso.vinculo v set vigente_ate = now()
  from _t_pessoas t where t.id = v.perfil_id and t.papel = 'leitor' and v.vigente_ate is null;

update public.perfis p set status = 'negado', atualizado_em = now()
  from _t_pessoas t where t.id = p.id and t.papel = 'desativar' and p.status = 'ativo';

-- 4. Ativar quem entra
update public.perfis p set status = 'ativo', atualizado_em = now()
 where p.status = 'pendente'
   and (exists (select 1 from acesso.vinculo v where v.perfil_id = p.id and v.vigente_ate is null)
        or p.id in (select t.id from _t_pessoas t where t.papel = 'leitor'));

-- 5. Pós-condição
do $c$
begin
  if (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007t: esperava só os 3 masters com admin/dev';
  end if;
  if exists (select 1 from acesso.vinculo v join public.perfis p on p.id = v.perfil_id
              where v.vigente_ate is null and p.status <> 'ativo') then
    raise exception '20261007t: sobrou perfil com vínculo sem estar ativo';
  end if;
  if exists (select 1 from _t_pessoas t join public.perfis p on p.id = t.id
              where (t.papel = 'desativar' and p.status <> 'negado') or (t.papel <> 'desativar' and p.status <> 'ativo')) then
    raise exception '20261007t: status das pessoas das decisões diferente do esperado';
  end if;
  if exists (select 1 from _t_pessoas t join public.perfis p on p.id = t.id
              where t.papel = 'leitor_escritorio'
                and (p.cargo <> 'visualizador' or p.pode_ver_cpf_completo
                     or exists (select 1 from acesso.vinculo v where v.perfil_id = t.id and v.vigente_ate is null)
                     or exists (select 1 from acesso.capacidade c where c.perfil_id = t.id))) then
    raise exception '20261007t: Marco ou Cristiane com edição, financeiro ou CPF (devem ser só leitores)';
  end if;
  if exists (select 1 from acesso.vinculo v join _t_pessoas t on t.id = v.perfil_id
              where t.papel = 'leitor' and v.vigente_ate is null) then
    raise exception '20261007t: guilherme ou matheusvasconcellos ficou com vínculo de edição';
  end if;
  if (select count(*) from acesso.capacidade c join _t_pessoas t on t.id = c.perfil_id
       where t.papel = 'financeiro_responsavel' and c.chave in ('financeiro.ver', 'financeiro.operar')) <> 2
     or exists (select 1 from acesso.capacidade c join _t_pessoas t on t.id = c.perfil_id where t.papel = 'financeiro_leitor') then
    raise exception '20261007t: capacidades financeiras dos perfis da Fernanda Tavares erradas';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- 1. perfis (cargo, status, CPF) pela foto:
-- update public.perfis p set cargo = f.cargo, status = f.status, pode_ver_cpf_completo = f.pode_ver_cpf_completo,
--        atualizado_em = now()
--   from acesso.perfis_antes_20261007 f
--  where f.id = p.id and (p.cargo, p.status, p.pode_ver_cpf_completo) is distinct from (f.cargo, f.status, f.pode_ver_cpf_completo);
-- 2. capacidades pela foto:
-- delete from acesso.capacidade c where not exists (select 1 from acesso.capacidade_antes_20261007 f
--   where f.perfil_id = c.perfil_id and f.chave = c.chave);
-- insert into acesso.capacidade (perfil_id, chave) select perfil_id, chave from acesso.capacidade_antes_20261007
-- on conflict do nothing;
-- 3. vínculos: encerrar os criados e reabrir os encerrados por esta migration (o acesso.log tem a hora exata):
-- update acesso.vinculo set vigente_ate = now() where vigente_ate is null and vigente_de >= '<hora da aplicação>'
--   and departamento in ('educacional', 'comercial', 'financeiro') and area is null;
-- insert into acesso.vinculo (perfil_id, departamento, area, papel)
-- select perfil_id, departamento, area, papel from acesso.vinculo where area = 'audiovisual' and vigente_ate >= '<hora da aplicação>';
-- Só a desativação dos 2 (Eduardo Vinicius Silva, Gabriel Sales):
-- update public.perfis p set status = 'ativo', atualizado_em = now() from acesso.perfis_antes_20261007 f
--  where f.id = p.id and f.status = 'ativo' and p.status = 'negado' and p.nome in ('Eduardo Vinicius Silva', 'Gabriel Sales');

-- ===== FASE 2, passada 2 =====
-- 20261007t: níveis de acesso, fase 2 (rebaixar). Quem não é master deixa de ser admin/dev e passa a valer só pelos
-- vínculos e capacidades de acesso.*, com os ajustes que o Victor Hugo decidiu sobre o relatório (07/10/2026).
--
-- STATUS: NÃO APLICADA. Fase 2 aprovada pelo Victor Hugo (07/10/2026, ajustes abaixo, versão 3) e pelo pentester;
--   só aplicar quando o Maestro mandar. Relatório: .maestri/entregas/niveis-de-acesso/ensaio-fase2.md (cérebro);
--   resumo em 20261007t.explain.md. Ensaio: 20261007t_ensaio.sql (rollback).
--
-- POR QUE
--   É a fase que de fato impede o líder de Web de criar projeto no Tráfego: com a fase 1 a guarda é "velho OU novo", e o
--   "velho" (cargo admin) ainda abre tudo para quem não é master.
--
-- O QUE FAZ
--   1. Fotos antes de mexer: acesso.perfis_antes_20261007 (id, nome, status, cargo, areas, funcoes,
--      pode_ver_cpf_completo) de TODOS os perfis, e acesso.capacidade_antes_20261007. Nada é apagado.
--   2. Perfis ativos com admin ou dev que não são master → cargo visualizador (areas e funcoes ficam).
--   3. Decisões do Victor Hugo (07/10/2026) sobre o relatório:
--      - Thomas Henrique e Ana Camila: membro do Educacional;
--      - Jusy: membro do Comercial;
--      - Fernanda Tavares: RESPONSÁVEL do Financeiro no perfil #8c37 (a conta do Financeiro, confirmada pelo Maestro no
--        Auth em 07/10/2026). O responsável ganha financeiro.ver e financeiro.operar. O outro perfil (#00b1) vira leitor:
--        perde as capacidades financeiras e o pode_ver_cpf_completo (na foto, reversível). Nenhum perfil é apagado;
--      - Marco e Cristiane (Escritório, só precisam ver informação de venda; decisão do Victor sobre a v2): continuam
--        ativos, visualizador, só leitura, sem vínculo de edição, sem capacidade financeira e sem CPF;
--      - Eduardo Vinicius Silva e Gabriel Sales: acesso ao sistema DESATIVADO (status negado, o único valor fora de
--        ativo/pendente que o CHECK de perfis aceita). Não apaga perfil, usuário do Auth nem histórico;
--      - guilherme e matheusvasconcellos: entram (ativo), SÓ LEITURA: o vínculo de edição em marketing/audiovisual é
--        encerrado (vigente_ate), porque a área ainda não existe.
--   4. Ativa os pendentes que entram: renan, emmanuel, jessica (com vínculo), guilherme e matheusvasconcellos (leitores).
--
-- AS 5 PERGUNTAS
--   escala: ~23 updates em perfis, 4 vínculos novos, 2 encerrados, 4 linhas de capacidade. índice: PK.
--   frequência: uma vez. repetição: nenhuma. reversão: bloco REVERSÃO no fim (pelas fotos e pela vigência).
--
-- IDEMPOTENTE: fotos só uma vez (on conflict do nothing); vínculos e capacidades com where not exists / on conflict;
--   rodar de novo não muda nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.master') is null or to_regclass('acesso.corpo_antes') is null then
    raise exception '20261007t: faltam as fases 0 e 1 (20261007180503, 20261007181138)';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.provolatile = 'v' and p.prosrc ~ 'mkt\.pode_ver\(') then
    raise exception '20261007t: a fase 1 não está completa (escrita do Marketing ainda em mkt.pode_ver)';
  end if;
  if to_regclass('acesso.perfis_antes_20261007') is null
     and (select count(*) from acesso.master m join public.perfis p on p.id = m.perfil_id
           where p.status = 'ativo' and p.cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007t: os 3 masters não estão ativos com cargo admin/dev. Conferir antes de rebaixar.';
  end if;
end
$g$;

-- 0b. Os perfis das decisões, por id completo, com o nome esperado (id errado aborta)
drop table if exists pg_temp._t_pessoas;
create temp table _t_pessoas (id uuid primary key, nome text not null, papel text not null) on commit drop;
insert into _t_pessoas (id, nome, papel)
select p.id, p.nome, x.papel
  from (values ('Thomas Henrique', 'educacional'), ('Ana Camila', 'educacional'), ('Jusy', 'comercial'),
               ('Cristiane', 'leitor_escritorio'), ('Eduardo Vinicius Silva', 'desativar'), ('Gabriel Sales', 'desativar'),
               ('Marco', 'leitor_escritorio'), ('guilherme', 'leitor'), ('matheusvasconcellos', 'leitor')) x(nome, papel)
  join public.perfis p on p.nome = x.nome;
insert into _t_pessoas (id, nome, papel) values
  ('8c37c683-a430-4bdd-9295-57bc92fb98db', 'Fernanda Tavares', 'financeiro_responsavel'),
  ('00b177e0-3c8b-4e55-8f64-f57560bbbd74', 'Fernanda Tavares', 'financeiro_leitor');
do $p$
begin
  if (select count(*) from _t_pessoas) <> 11 then
    raise exception '20261007t: esperava 11 perfis das decisões, achei % (nome duplicado ou sumido)', (select count(*) from _t_pessoas);
  end if;
  if exists (select 1 from _t_pessoas t join public.perfis p on p.id = t.id where p.nome <> t.nome) then
    raise exception '20261007t: perfil da Fernanda Tavares com outro nome';
  end if;
  if exists (select 1 from _t_pessoas t where left(t.id::text, 4) not in
               ('998e', 'e303', '412d', '1b15', 'a9df', '3e10', '8501', '46b3', '7bd5', '8c37', '00b1')) then
    raise exception '20261007t: id fora dos conferidos no relatório (#998e #e303 #412d #1b15 #a9df #3e10 #8501 #46b3 #7bd5 #8c37 #00b1)';
  end if;
end
$p$;

-- 1. Fotos
create table if not exists acesso.perfis_antes_20261007 (
  id uuid primary key, nome text, status text, cargo text, areas text[], funcoes text[],
  pode_ver_cpf_completo boolean, foto_em timestamptz not null default now()
);
alter table acesso.perfis_antes_20261007 enable row level security;
revoke all on acesso.perfis_antes_20261007 from public, anon, authenticated;
insert into acesso.perfis_antes_20261007 (id, nome, status, cargo, areas, funcoes, pode_ver_cpf_completo)
select p.id, p.nome, p.status, p.cargo, p.areas, p.funcoes, p.pode_ver_cpf_completo from public.perfis p
on conflict (id) do nothing;
create table if not exists acesso.capacidade_antes_20261007 (
  perfil_id uuid not null, chave text not null, foto_em timestamptz not null default now(), primary key (perfil_id, chave)
);
alter table acesso.capacidade_antes_20261007 enable row level security;
revoke all on acesso.capacidade_antes_20261007 from public, anon, authenticated;
insert into acesso.capacidade_antes_20261007 (perfil_id, chave)
select c.perfil_id, c.chave from acesso.capacidade c
 where not exists (select 1 from acesso.capacidade_antes_20261007)  -- foto só na primeira vez
on conflict do nothing;

-- 2. Rebaixar quem não é master
update public.perfis p set cargo = 'visualizador', atualizado_em = now()
 where p.status = 'ativo' and p.cargo in ('admin', 'dev')
   and not exists (select 1 from acesso.master m where m.perfil_id = p.id);

-- 3. Decisões do Victor
insert into acesso.vinculo (perfil_id, departamento, area, papel)
select t.id, d.dep, null, d.papel
  from _t_pessoas t
  join (values ('educacional', 'educacional', 'membro'), ('comercial', 'comercial', 'membro'),
               ('financeiro_responsavel', 'financeiro', 'responsavel')) d(chave, dep, papel) on d.chave = t.papel
 where not exists (select 1 from acesso.vinculo v where v.perfil_id = t.id and v.departamento = d.dep
                     and v.area is null and v.vigente_ate is null);

insert into acesso.capacidade (perfil_id, chave)
select t.id, c.chave from _t_pessoas t cross join (values ('financeiro.ver'), ('financeiro.operar')) c(chave)
 where t.papel = 'financeiro_responsavel'
on conflict do nothing;

delete from acesso.capacidade c using _t_pessoas t
 where t.id = c.perfil_id and t.papel = 'financeiro_leitor' and c.chave in ('financeiro.ver', 'financeiro.operar');
update public.perfis p set pode_ver_cpf_completo = false, atualizado_em = now()
  from _t_pessoas t where t.id = p.id and t.papel = 'financeiro_leitor' and p.pode_ver_cpf_completo;

update acesso.vinculo v set vigente_ate = now()
  from _t_pessoas t where t.id = v.perfil_id and t.papel = 'leitor' and v.vigente_ate is null;

update public.perfis p set status = 'negado', atualizado_em = now()
  from _t_pessoas t where t.id = p.id and t.papel = 'desativar' and p.status = 'ativo';

-- 4. Ativar quem entra
update public.perfis p set status = 'ativo', atualizado_em = now()
 where p.status = 'pendente'
   and (exists (select 1 from acesso.vinculo v where v.perfil_id = p.id and v.vigente_ate is null)
        or p.id in (select t.id from _t_pessoas t where t.papel = 'leitor'));

-- 5. Pós-condição
do $c$
begin
  if (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007t: esperava só os 3 masters com admin/dev';
  end if;
  if exists (select 1 from acesso.vinculo v join public.perfis p on p.id = v.perfil_id
              where v.vigente_ate is null and p.status <> 'ativo') then
    raise exception '20261007t: sobrou perfil com vínculo sem estar ativo';
  end if;
  if exists (select 1 from _t_pessoas t join public.perfis p on p.id = t.id
              where (t.papel = 'desativar' and p.status <> 'negado') or (t.papel <> 'desativar' and p.status <> 'ativo')) then
    raise exception '20261007t: status das pessoas das decisões diferente do esperado';
  end if;
  if exists (select 1 from _t_pessoas t join public.perfis p on p.id = t.id
              where t.papel = 'leitor_escritorio'
                and (p.cargo <> 'visualizador' or p.pode_ver_cpf_completo
                     or exists (select 1 from acesso.vinculo v where v.perfil_id = t.id and v.vigente_ate is null)
                     or exists (select 1 from acesso.capacidade c where c.perfil_id = t.id))) then
    raise exception '20261007t: Marco ou Cristiane com edição, financeiro ou CPF (devem ser só leitores)';
  end if;
  if exists (select 1 from acesso.vinculo v join _t_pessoas t on t.id = v.perfil_id
              where t.papel = 'leitor' and v.vigente_ate is null) then
    raise exception '20261007t: guilherme ou matheusvasconcellos ficou com vínculo de edição';
  end if;
  if (select count(*) from acesso.capacidade c join _t_pessoas t on t.id = c.perfil_id
       where t.papel = 'financeiro_responsavel' and c.chave in ('financeiro.ver', 'financeiro.operar')) <> 2
     or exists (select 1 from acesso.capacidade c join _t_pessoas t on t.id = c.perfil_id where t.papel = 'financeiro_leitor') then
    raise exception '20261007t: capacidades financeiras dos perfis da Fernanda Tavares erradas';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- 1. perfis (cargo, status, CPF) pela foto:
-- update public.perfis p set cargo = f.cargo, status = f.status, pode_ver_cpf_completo = f.pode_ver_cpf_completo,
--        atualizado_em = now()
--   from acesso.perfis_antes_20261007 f
--  where f.id = p.id and (p.cargo, p.status, p.pode_ver_cpf_completo) is distinct from (f.cargo, f.status, f.pode_ver_cpf_completo);
-- 2. capacidades pela foto:
-- delete from acesso.capacidade c where not exists (select 1 from acesso.capacidade_antes_20261007 f
--   where f.perfil_id = c.perfil_id and f.chave = c.chave);
-- insert into acesso.capacidade (perfil_id, chave) select perfil_id, chave from acesso.capacidade_antes_20261007
-- on conflict do nothing;
-- 3. vínculos: encerrar os criados e reabrir os encerrados por esta migration (o acesso.log tem a hora exata):
-- update acesso.vinculo set vigente_ate = now() where vigente_ate is null and vigente_de >= '<hora da aplicação>'
--   and departamento in ('educacional', 'comercial', 'financeiro') and area is null;
-- insert into acesso.vinculo (perfil_id, departamento, area, papel)
-- select perfil_id, departamento, area, papel from acesso.vinculo where area = 'audiovisual' and vigente_ate >= '<hora da aplicação>';
-- Só a desativação dos 2 (Eduardo Vinicius Silva, Gabriel Sales):
-- update public.perfis p set status = 'ativo', atualizado_em = now() from acesso.perfis_antes_20261007 f
--  where f.id = p.id and f.status = 'ativo' and p.status = 'negado' and p.nome in ('Eduardo Vinicius Silva', 'Gabriel Sales');

insert into pg_temp._z_out (passo, linha) select '2 depois da fase 2', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), jsonb_build_object('cargo', p.cargo, 'status', p.status, 's', pg_temp.sonda(p.id))) from public.perfis p where p.status = 'ativo' or exists (select 1 from acesso.vinculo v where v.perfil_id = p.id and v.vigente_ate is null);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'prova fase2 trafego_projeto_salvar ' || x.n, pg_temp.tenta(x.id, $q$select public.trafego_projeto_salvar('{"sigla":"ENSAIOAC99","nome":"Ensaio de acesso"}'::jsonb)::text$q$)
  from (values ('Iromar Júnior (Web, responsável)', 'b65dc9c1-8edb-4e7a-ae07-681555523093'::uuid),
  ('Luis Fernando (Web, membro)', '9d5fb8e7-f61e-459d-be04-d103ec783c08'::uuid),
  ('Caio Fábio (Tráfego)', 'caf36b74-0441-4f0b-b2a6-b3af88705f02'::uuid),
  ('renan / Renan Schwarz (Tráfego)', '1023e685-2b13-4365-a2d9-7e012afd4516'::uuid),
  ('emmanuel / Emmanuel Fernandes (Tráfego)', '9a3ea481-f46b-43a6-a418-e66b3d97b1ae'::uuid),
  ('Victor Hugo (master)', '81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid),
  ('Arthur Galvão (master)', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid),
  ('João Pedro Alves (master)', '843d43db-73b3-44a9-b449-1731e362dbc3'::uuid)) x(n, id);
insert into pg_temp._z_out (passo, linha) select 'prova fase2 fn_fin_board ' || x.n, pg_temp.tenta(x.id, $q$select count(*)::text from public.fn_fin_board(null, null)$q$)
  from (values ('Luis Fernando (sem financeiro.ver)', '9d5fb8e7-f61e-459d-be04-d103ec783c08'::uuid),
  ('Isabela Teixeira (sem financeiro.ver)', 'e1d2863d-c975-46bd-b35f-45b1039328e3'::uuid),
  ('Iromar Júnior (sem financeiro.ver)', 'b65dc9c1-8edb-4e7a-ae07-681555523093'::uuid),
  ('Caio Fábio (sem financeiro.ver)', 'caf36b74-0441-4f0b-b2a6-b3af88705f02'::uuid),
  ('Marcio Carvalho de Sá (diretoria, financeiro.ver)', 'ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid),
  ('Fernanda Tavares #00b1 (vira leitora: tem de dar erro)', '00b177e0-3c8b-4e55-8f64-f57560bbbd74'::uuid),
  ('Victor Hugo (master)', '81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid),
  ('Arthur Galvão (master)', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid),
  ('João Pedro Alves (master)', '843d43db-73b3-44a9-b449-1731e362dbc3'::uuid)) x(n, id);
reset role;

-- ===== FASE 3, passada 1 =====
-- 20261007u: níveis de acesso, fase 3 (limpar). Tira o "velho" das guardas: gp_is_admin() passa a ser só o master
-- (acesso.master) e as guardas de financeiro, CPF, Marketing e Comercial deixam de aceitar o cargo admin/dev.
--
-- STATUS: NÃO APLICADA. SÓ DEPOIS DA FASE 2 (20261007t) APLICADA E VALIDADA PELO VICTOR HUGO. Ensaio junto com a fase
--   2 em 20261007t_ensaio.sql (rollback). Relatório: 20261007u.explain.md.
--
-- POR QUE
--   Depois da fase 2 só os 3 masters têm cargo admin/dev, então o "velho" já não abre nada a mais; esta fase tira o
--   atalho para que um cargo admin dado por engano (tela de Usuários, cadastro) não volte a abrir o sistema inteiro.
--
-- O QUE FAZ (corpo anterior de cada função guardado em acesso.corpo_antes, migration 20261007u)
--   - gp_is_admin()               = acesso.eh_master()
--   - gp_pode_ver_financeiro()    = acesso.tem('financeiro.ver')
--   - gp_pode_operar_financeiro() = acesso.tem('financeiro.operar')
--   - gp_pode_ver_cpf()           = acesso.tem('cpf.ver') ou perfis.pode_ver_cpf_completo
--   - gp_pode_editar(setor)       = gestor/operador com setor (e função, no operador), como antes, sem o ramo admin/dev,
--                                   OR a regra de acesso.* da fase 1
--   - crm.eh_gestor()             = master ou responsável do comercial, ou gestor com a área comercial (sem admin/dev)
--   - ra_pode_ver(), pa_pode_pedir(): sem o ramo admin/dev
--   - mkt.pode_ver/pode_editar    = só acesso.pode_ver/pode_editar
--   Ficam como estão (já valem só para master depois da fase 2, porque leem cargo admin/dev): crm.pode_catalogar,
--   pessoas.pode_*, e todas as funções/policies que a fase 1 deixou com "(gp_is_admin() OR editar <depto>)".
--
-- AS 5 PERGUNTAS
--   escala: 10 funções. índice: o de acesso.* (fase 0). frequência: toda RPC. repetição: nenhuma.
--   reversão: recriar os corpos de acesso.corpo_antes (migration 20261007u).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.perfis_antes_20261007') is null then
    raise exception '20261007u: a fase 2 (20261007t) não foi aplicada';
  end if;
  if (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007u: tem perfil admin/dev além dos 3 masters. Conferir antes de limpar.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007u'
  from pg_proc p
 where p.oid in ('public.gp_is_admin()'::regprocedure, 'public.gp_pode_ver_financeiro()'::regprocedure,
                 'public.gp_pode_operar_financeiro()'::regprocedure, 'public.gp_pode_ver_cpf()'::regprocedure,
                 'public.gp_pode_editar(text)'::regprocedure, 'crm.eh_gestor()'::regprocedure,
                 'public.ra_pode_ver()'::regprocedure, 'public.pa_pode_pedir()'::regprocedure,
                 'mkt.pode_ver(text)'::regprocedure, 'mkt.pode_editar(text)'::regprocedure)
on conflict do nothing;

create or replace function public.gp_is_admin()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.eh_master(), false);  -- 20261007u: admin do sistema = master
$function$;

create or replace function public.gp_pode_ver_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('financeiro.ver'), false);  -- 20261007u
$function$;

create or replace function public.gp_pode_operar_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('financeiro.operar'), false);  -- 20261007u
$function$;

create or replace function public.gp_pode_ver_cpf()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('cpf.ver'), false)
      or exists (select 1 from public.perfis p where p.id = (select auth.uid()) and p.status = 'ativo'
                   and p.email ilike '%@advmais.com' and p.pode_ver_cpf_completo is true);  -- 20261007u
$function$;

create or replace function public.gp_pode_editar(p_setor text)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfis p
    WHERE p.id = auth.uid()
      AND p.status = 'ativo'
      AND (
        (p.cargo = 'gestor' AND p_setor = ANY(coalesce(p.areas,'{}')))
        OR (p.cargo = 'operador' AND p_setor = ANY(coalesce(p.areas,'{}'))
            AND EXISTS (SELECT 1 FROM unnest(coalesce(p.funcoes,'{}')) f WHERE f LIKE p_setor || '.%'))
      )
  ) OR coalesce(acesso.eh_master(), false) OR coalesce(case  -- 20261007u
         when p_setor in ('ativacao', 'placas', 'depoimentos', 'centro_controle', 'remocao_acessos', 'pedidos_alteracao')
           then acesso.pode_editar('educacional')
         when p_setor = 'social_media' then acesso.pode_editar('marketing', 'social-media')
         when p_setor = 'comercial' then acesso.pode_editar('comercial')
         when p_setor = 'financeiro' then acesso.tem('financeiro.operar')
       end, false);
$function$;

create or replace function crm.eh_gestor()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.eh_master(), false)  -- 20261007u
      or exists (select 1 from acesso.vinculo v where v.perfil_id = acesso.eu() and v.vigente_ate is null
                   and v.departamento = 'comercial' and v.area is null and v.papel = 'responsavel')
      or coalesce((select p.status = 'ativo' and p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))
                     from public.perfis p where p.id = (select auth.uid())), false);
$function$;

create or replace function public.ra_pode_ver()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and p.cargo in ('gestor', 'operador') and 'remocao_acessos' = any(coalesce(p.areas, '{}'))
  ) or coalesce(acesso.pode_editar('educacional'), false);  -- 20261007u
$function$;

create or replace function public.pa_pode_pedir()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_eh_equipe(), false) and (exists (
    select 1 from public.perfis p
     where p.id = (select auth.uid()) and p.status = 'ativo'
       and p.cargo in ('gestor', 'operador') and 'pedidos_alteracao' = any(coalesce(p.areas, '{}')))
    or coalesce(acesso.pode_editar('educacional'), false));  -- 20261007u
$function$;

create or replace function mkt.pode_ver(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_ver('marketing', acesso.area_mkt(p_area)), false);  -- 20261007u
$function$;

create or replace function mkt.pode_editar(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_editar('marketing', acesso.area_mkt(p_area)), false);  -- 20261007u
$function$;

do $c$
begin
  if (select prosrc from pg_proc where oid = 'public.gp_is_admin()'::regprocedure) !~ 'acesso\.eh_master' then
    raise exception '20261007u: gp_is_admin não virou master';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007u' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;

-- ===== FASE 3, passada 2 =====
-- 20261007u: níveis de acesso, fase 3 (limpar). Tira o "velho" das guardas: gp_is_admin() passa a ser só o master
-- (acesso.master) e as guardas de financeiro, CPF, Marketing e Comercial deixam de aceitar o cargo admin/dev.
--
-- STATUS: NÃO APLICADA. SÓ DEPOIS DA FASE 2 (20261007t) APLICADA E VALIDADA PELO VICTOR HUGO. Ensaio junto com a fase
--   2 em 20261007t_ensaio.sql (rollback). Relatório: 20261007u.explain.md.
--
-- POR QUE
--   Depois da fase 2 só os 3 masters têm cargo admin/dev, então o "velho" já não abre nada a mais; esta fase tira o
--   atalho para que um cargo admin dado por engano (tela de Usuários, cadastro) não volte a abrir o sistema inteiro.
--
-- O QUE FAZ (corpo anterior de cada função guardado em acesso.corpo_antes, migration 20261007u)
--   - gp_is_admin()               = acesso.eh_master()
--   - gp_pode_ver_financeiro()    = acesso.tem('financeiro.ver')
--   - gp_pode_operar_financeiro() = acesso.tem('financeiro.operar')
--   - gp_pode_ver_cpf()           = acesso.tem('cpf.ver') ou perfis.pode_ver_cpf_completo
--   - gp_pode_editar(setor)       = gestor/operador com setor (e função, no operador), como antes, sem o ramo admin/dev,
--                                   OR a regra de acesso.* da fase 1
--   - crm.eh_gestor()             = master ou responsável do comercial, ou gestor com a área comercial (sem admin/dev)
--   - ra_pode_ver(), pa_pode_pedir(): sem o ramo admin/dev
--   - mkt.pode_ver/pode_editar    = só acesso.pode_ver/pode_editar
--   Ficam como estão (já valem só para master depois da fase 2, porque leem cargo admin/dev): crm.pode_catalogar,
--   pessoas.pode_*, e todas as funções/policies que a fase 1 deixou com "(gp_is_admin() OR editar <depto>)".
--
-- AS 5 PERGUNTAS
--   escala: 10 funções. índice: o de acesso.* (fase 0). frequência: toda RPC. repetição: nenhuma.
--   reversão: recriar os corpos de acesso.corpo_antes (migration 20261007u).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.perfis_antes_20261007') is null then
    raise exception '20261007u: a fase 2 (20261007t) não foi aplicada';
  end if;
  if (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007u: tem perfil admin/dev além dos 3 masters. Conferir antes de limpar.';
  end if;
end
$g$;

insert into acesso.corpo_antes (tipo, alvo, md5, definicao, migration)
select 'funcao', p.oid::regprocedure::text, md5(p.prosrc), pg_get_functiondef(p.oid), '20261007u'
  from pg_proc p
 where p.oid in ('public.gp_is_admin()'::regprocedure, 'public.gp_pode_ver_financeiro()'::regprocedure,
                 'public.gp_pode_operar_financeiro()'::regprocedure, 'public.gp_pode_ver_cpf()'::regprocedure,
                 'public.gp_pode_editar(text)'::regprocedure, 'crm.eh_gestor()'::regprocedure,
                 'public.ra_pode_ver()'::regprocedure, 'public.pa_pode_pedir()'::regprocedure,
                 'mkt.pode_ver(text)'::regprocedure, 'mkt.pode_editar(text)'::regprocedure)
on conflict do nothing;

create or replace function public.gp_is_admin()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.eh_master(), false);  -- 20261007u: admin do sistema = master
$function$;

create or replace function public.gp_pode_ver_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('financeiro.ver'), false);  -- 20261007u
$function$;

create or replace function public.gp_pode_operar_financeiro()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('financeiro.operar'), false);  -- 20261007u
$function$;

create or replace function public.gp_pode_ver_cpf()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('cpf.ver'), false)
      or exists (select 1 from public.perfis p where p.id = (select auth.uid()) and p.status = 'ativo'
                   and p.email ilike '%@advmais.com' and p.pode_ver_cpf_completo is true);  -- 20261007u
$function$;

create or replace function public.gp_pode_editar(p_setor text)
 returns boolean language sql stable security definer set search_path to 'public', 'pg_temp'
as $function$
  SELECT EXISTS (
    SELECT 1 FROM public.perfis p
    WHERE p.id = auth.uid()
      AND p.status = 'ativo'
      AND (
        (p.cargo = 'gestor' AND p_setor = ANY(coalesce(p.areas,'{}')))
        OR (p.cargo = 'operador' AND p_setor = ANY(coalesce(p.areas,'{}'))
            AND EXISTS (SELECT 1 FROM unnest(coalesce(p.funcoes,'{}')) f WHERE f LIKE p_setor || '.%'))
      )
  ) OR coalesce(acesso.eh_master(), false) OR coalesce(case  -- 20261007u
         when p_setor in ('ativacao', 'placas', 'depoimentos', 'centro_controle', 'remocao_acessos', 'pedidos_alteracao')
           then acesso.pode_editar('educacional')
         when p_setor = 'social_media' then acesso.pode_editar('marketing', 'social-media')
         when p_setor = 'comercial' then acesso.pode_editar('comercial')
         when p_setor = 'financeiro' then acesso.tem('financeiro.operar')
       end, false);
$function$;

create or replace function crm.eh_gestor()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.eh_master(), false)  -- 20261007u
      or exists (select 1 from acesso.vinculo v where v.perfil_id = acesso.eu() and v.vigente_ate is null
                   and v.departamento = 'comercial' and v.area is null and v.papel = 'responsavel')
      or coalesce((select p.status = 'ativo' and p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))
                     from public.perfis p where p.id = (select auth.uid())), false);
$function$;

create or replace function public.ra_pode_ver()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and p.cargo in ('gestor', 'operador') and 'remocao_acessos' = any(coalesce(p.areas, '{}'))
  ) or coalesce(acesso.pode_editar('educacional'), false);  -- 20261007u
$function$;

create or replace function public.pa_pode_pedir()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_eh_equipe(), false) and (exists (
    select 1 from public.perfis p
     where p.id = (select auth.uid()) and p.status = 'ativo'
       and p.cargo in ('gestor', 'operador') and 'pedidos_alteracao' = any(coalesce(p.areas, '{}')))
    or coalesce(acesso.pode_editar('educacional'), false));  -- 20261007u
$function$;

create or replace function mkt.pode_ver(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_ver('marketing', acesso.area_mkt(p_area)), false);  -- 20261007u
$function$;

create or replace function mkt.pode_editar(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_editar('marketing', acesso.area_mkt(p_area)), false);  -- 20261007u
$function$;

do $c$
begin
  if (select prosrc from pg_proc where oid = 'public.gp_is_admin()'::regprocedure) !~ 'acesso\.eh_master' then
    raise exception '20261007u: gp_is_admin não virou master';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007u' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;

insert into pg_temp._z_out (passo, linha) select '3 depois da fase 3', jsonb_object_agg(p.nome || ' #' || left(p.id::text, 4), jsonb_build_object('cargo', p.cargo, 'status', p.status, 's', pg_temp.sonda(p.id))) from public.perfis p where p.status = 'ativo' or exists (select 1 from acesso.vinculo v where v.perfil_id = p.id and v.vigente_ate is null);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'prova fase3 trafego_projeto_salvar ' || x.n, pg_temp.tenta(x.id, $q$select public.trafego_projeto_salvar('{"sigla":"ENSAIOAC99","nome":"Ensaio de acesso"}'::jsonb)::text$q$)
  from (values ('Iromar Júnior (Web, responsável)', 'b65dc9c1-8edb-4e7a-ae07-681555523093'::uuid),
  ('Luis Fernando (Web, membro)', '9d5fb8e7-f61e-459d-be04-d103ec783c08'::uuid),
  ('Caio Fábio (Tráfego)', 'caf36b74-0441-4f0b-b2a6-b3af88705f02'::uuid),
  ('renan / Renan Schwarz (Tráfego)', '1023e685-2b13-4365-a2d9-7e012afd4516'::uuid),
  ('emmanuel / Emmanuel Fernandes (Tráfego)', '9a3ea481-f46b-43a6-a418-e66b3d97b1ae'::uuid),
  ('Victor Hugo (master)', '81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid),
  ('Arthur Galvão (master)', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid),
  ('João Pedro Alves (master)', '843d43db-73b3-44a9-b449-1731e362dbc3'::uuid)) x(n, id);
insert into pg_temp._z_out (passo, linha) select 'prova fase3 fn_fin_board ' || x.n, pg_temp.tenta(x.id, $q$select count(*)::text from public.fn_fin_board(null, null)$q$)
  from (values ('Luis Fernando (sem financeiro.ver)', '9d5fb8e7-f61e-459d-be04-d103ec783c08'::uuid),
  ('Isabela Teixeira (sem financeiro.ver)', 'e1d2863d-c975-46bd-b35f-45b1039328e3'::uuid),
  ('Iromar Júnior (sem financeiro.ver)', 'b65dc9c1-8edb-4e7a-ae07-681555523093'::uuid),
  ('Caio Fábio (sem financeiro.ver)', 'caf36b74-0441-4f0b-b2a6-b3af88705f02'::uuid),
  ('Marcio Carvalho de Sá (diretoria, financeiro.ver)', 'ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid),
  ('Fernanda Tavares #00b1 (vira leitora: tem de dar erro)', '00b177e0-3c8b-4e55-8f64-f57560bbbd74'::uuid),
  ('Victor Hugo (master)', '81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid),
  ('Arthur Galvão (master)', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid),
  ('João Pedro Alves (master)', '843d43db-73b3-44a9-b449-1731e362dbc3'::uuid)) x(n, id);
reset role;


-- ===== Provas das decisões do Victor (07/10/2026), depois da fase 3 =====
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select 'decisao ' || x.n, pg_temp.tenta(x.id, x.q)
  from (values
    ('Thomas Henrique edita Placas', '998e', 'select public.gp_pode_editar(''placas'')::text'),
    ('Thomas Henrique edita Educacional', '998e', 'select public.gp_acesso_pode_editar(''educacional'', null)::text'),
    ('Ana Camila edita Educacional', 'e303', 'select public.gp_acesso_pode_editar(''educacional'', null)::text'),
    ('Ana Camila Remoção de acessos', 'e303', 'select public.ra_pode_ver()::text'),
    ('Jusy usa o CRM', '412d', 'select crm.eh_comercial()::text'),
    ('Fernanda #8c37 vê financeiro', '8c37', 'select public.gp_pode_ver_financeiro()::text'),
    ('Fernanda #8c37 opera financeiro', '8c37', 'select public.gp_pode_operar_financeiro()::text'),
    ('Fernanda #8c37 fn_fin_board', '8c37', 'select count(*)::text from public.fn_fin_board(null, null)'),
    ('Fernanda #00b1 fn_fin_board', '00b1', 'select count(*)::text from public.fn_fin_board(null, null)'),
    ('Fernanda #00b1 vê CPF', '00b1', 'select public.gp_pode_ver_cpf()::text'),
    ('Cristiane entra', '1b15', 'select public.gp_eh_equipe()::text'),
    ('Cristiane edita algo', '1b15', 'select (public.gp_meu_acesso() -> ''editar'')::text'),
    ('Cristiane vê financeiro', '1b15', 'select public.gp_pode_ver_financeiro()::text'),
    ('Cristiane vê CPF', '1b15', 'select public.gp_pode_ver_cpf()::text'),
    ('Marco entra', '8501', 'select public.gp_eh_equipe()::text'),
    ('Marco edita algo', '8501', 'select (public.gp_meu_acesso() -> ''editar'')::text'),
    ('Marco vê financeiro', '8501', 'select public.gp_pode_ver_financeiro()::text'),
    ('Marco vê CPF', '8501', 'select public.gp_pode_ver_cpf()::text'),
    ('Marco fn_fin_board', '8501', 'select count(*)::text from public.fn_fin_board(null, null)'),
    ('Eduardo Vinicius Silva entra', 'a9df', 'select public.gp_eh_equipe()::text'),
    ('Gabriel Sales entra', '3e10', 'select public.gp_eh_equipe()::text'),
    ('guilherme entra', '46b3', 'select public.gp_eh_equipe()::text'),
    ('guilherme edita algo', '46b3', 'select (public.gp_meu_acesso() -> ''editar'')::text'),
    ('matheusvasconcellos edita algo', '7bd5', 'select (public.gp_meu_acesso() -> ''editar'')::text'),
    ('guilherme trafego_projeto_salvar', '46b3', $q$select public.trafego_projeto_salvar('{"sigla":"ENSAIOAC99","nome":"Ensaio de acesso"}'::jsonb)::text$q$)
  ) x0(n, pref, q)
  cross join lateral (select p.id from public.perfis p where left(p.id::text, 4) = x0.pref) pid
  cross join lateral (select x0.n as n, pid.id as id, x0.q as q) x;
reset role;
insert into pg_temp._z_out (passo, linha) select 'contagem admin/dev ativos depois', count(*)::text from public.perfis where status = 'ativo' and cargo in ('admin','dev');
do $x$ declare l text; i int; begin
  perform set_config('request.jwt.claims', '{"sub":"caf36b74-0441-4f0b-b2a6-b3af88705f02","role":"authenticated"}', true);
  for i in 1..2 loop
    for l in execute 'explain (analyze, buffers) select public.gp_is_admin(), mkt.pode_editar(''mkt_trafego''), crm.eh_gestor(), public.gp_pode_ver_financeiro()' loop
      if l like '%Execution Time%' then insert into pg_temp._z_out (passo, linha) values ('x guardas fase3 ' || i, l); end if; end loop;
  end loop;
end $x$;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
