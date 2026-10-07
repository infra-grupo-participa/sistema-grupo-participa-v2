-- 20261007t: níveis de acesso, fase 2 (rebaixar). Quem não é master deixa de ser admin/dev e passa a valer só pelos
-- vínculos e capacidades de acesso.*, com os ajustes que o Victor Hugo decidiu sobre o relatório (07/10/2026).
--
-- STATUS: NÃO APLICADA. Fase 2 aprovada pelo Victor Hugo em 07/10/2026 com os ajustes abaixo; só aplicar depois que o
--   pentester aprovar e o Maestro mandar. Relatório: .maestri/entregas/niveis-de-acesso/ensaio-fase2.md (cérebro);
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
--      - Fernanda Tavares: RESPONSÁVEL do Financeiro, no perfil em uso (#8c37, último login no Auth 21/07/2026, contra
--        15/07/2026 do #00b1). O responsável ganha financeiro.ver e financeiro.operar. O outro perfil (#00b1) vira leitor:
--        perde as capacidades financeiras e o pode_ver_cpf_completo (na foto, reversível). Nenhum perfil é apagado;
--      - Cristiane, Eduardo Vinicius Silva, Gabriel Sales e Marco: acesso ao sistema DESATIVADO (status negado, o único
--        valor fora de ativo/pendente que o CHECK de perfis aceita). Não apaga perfil, usuário do Auth nem histórico;
--      - guilherme e matheusvasconcellos: entram (ativo), SÓ LEITURA: o vínculo de edição em marketing/audiovisual é
--        encerrado (vigente_ate), porque a área ainda não existe.
--   4. Ativa os pendentes que entram: renan, emmanuel, jessica (com vínculo), guilherme e matheusvasconcellos (leitores).
--
-- AS 5 PERGUNTAS
--   escala: ~25 updates em perfis, 4 vínculos novos, 2 encerrados, 4 linhas de capacidade. índice: PK.
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
               ('Cristiane', 'desativar'), ('Eduardo Vinicius Silva', 'desativar'), ('Gabriel Sales', 'desativar'),
               ('Marco', 'desativar'), ('guilherme', 'leitor'), ('matheusvasconcellos', 'leitor')) x(nome, papel)
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
-- Só a desativação dos 4 (Cristiane, Eduardo Vinicius Silva, Gabriel Sales, Marco):
-- update public.perfis p set status = 'ativo', atualizado_em = now() from acesso.perfis_antes_20261007 f
--  where f.id = p.id and f.status = 'ativo' and p.status = 'negado' and p.nome in ('Cristiane', 'Eduardo Vinicius Silva', 'Gabriel Sales', 'Marco');
