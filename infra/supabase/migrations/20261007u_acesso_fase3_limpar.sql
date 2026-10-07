-- 20261007u: níveis de acesso, fase 3 (limpar). Tira o "velho" das guardas: gp_is_admin() passa a ser só o master
-- (acesso.master) e as guardas de financeiro, CPF, Marketing e Comercial deixam de aceitar o cargo admin/dev.
--
-- STATUS: NÃO APLICADA. Versão 3: correções do pentester das rodadas 1 e 2 (.maestri/entregas/niveis-de-acesso/
--   pentester.md no cérebro) e a EXCEÇÃO NOMINAL decidida pelo Victor Hugo em 07/10/2026 (noite) para os 6 não masters
--   a quem o João Pedro Alves devolveu admin/dev às 18:39:06 UTC (registro: migration 20261007184603). Só aplicar depois
--   de o pentester aprovar (rodada 3) e o Maestro mandar. Ensaio: 20261007u_ensaio.sql (rollback). Relatório: 20261007u.explain.md.
--
-- POR QUE
--   Depois da fase 2 (20261007182928, aplicada) só os 3 masters têm cargo admin/dev. Esta fase fecha o caminho de volta:
--   (a) gp_is_admin() e as guardas centrais deixam de aceitar o cargo; (b) o cargo admin/dev só pode existir em quem está
--   em acesso.master OU na exceção nominal acesso.excecao_admin (lista fechada de 6 ids, com o cargo de cada um, só
--   muda por migration): um gatilho em public.perfis recusa dar admin/dev a quem não está em nenhuma, venha da tela de Usuários
--   (/api/admin/usuarios, service_role), do cadastro (handle_new_user/garantir_perfil) ou de SQL. Assim as 20 funções
--   que ainda leem cargo admin/dev inline (lista no explain, correção do pentester) passam a valer só para master, sem
--   reescrever uma a uma: a dívida fica registrada e neutralizada na origem; (c) CPF completo vira só a capacidade
--   cpf.ver (com log); a coluna perfis.pode_ver_cpf_completo deixa de abrir CPF e não pode mais ser ligada.
--
-- EXCEÇÃO NOMINAL (decisão do Victor Hugo, 07/10/2026): Cristiane (#1b15) admin, Fernanda Tavares (#00b1) admin, Isabela
--   Teixeira (#e1d2) admin, Elaine Montenegro (#6ed2) dev, Marcio Carvalho de Sá (#ec6d) dev, Aldri Santana (#0f6d) dev.
--   Ninguém vira master. A exceção vale enquanto o cargo do perfil for o da lista, e cobre o "admin do sistema"
--   (gp_is_admin e as guardas de edição). NÃO cobre financeiro nem CPF: esses continuam só por capacidade
--   (decisões 1 e 7 do Victor). O CPF da Fernanda #00b1 (coluna ligada pelo João) vira a capacidade cpf.ver, com log.
--
-- O QUE FAZ (corpo anterior de cada função guardado em acesso.corpo_antes, migration 20261007u)
--   1. Guardas sem o atalho do cargo: gp_is_admin() = acesso.eh_admin() (master ou exceção nominal); gp_pode_ver_financeiro() =
--      tem('financeiro.ver'); gp_pode_operar_financeiro() = tem('financeiro.operar'); gp_pode_ver_cpf() = tem('cpf.ver');
--      gp_pode_editar(setor), crm.eh_gestor(), ra_pode_ver(), pa_pode_pedir() sem o ramo admin/dev (os ramos de
--      gestor/operador com função fina ficam: o usuário não consegue mudar o próprio cargo, áreas nem funções, só nome,
--      avatar e atualizado_em); mkt.pode_ver/pode_editar só pela regra nova.
--   2. CPF: quem tem pode_ver_cpf_completo = true e está ativo ganha a capacidade cpf.ver (hoje: Fernanda Tavares #8c37);
--      a coluna inteira vira false (foto em acesso.cpf_coluna_antes_20261007).
--   3. Gatilho acesso_guarda em public.perfis (BEFORE INSERT OR UPDATE):
--      - cargo admin/dev em quem não está em acesso.master → 42501;
--      - ligar pode_ver_cpf_completo → 42501 (CPF é acesso_capacidade_definir, só master, com log);
--      - o próprio usuário (não master) trocar o próprio nome → 42501 (correção BAIXA do pentester);
--      - toda mudança de cargo, status, áreas, funções ou CPF vai para acesso.log (sem e-mail).
--   Ficam lendo cargo (já valem só para master depois da fase 2, e o gatilho impede que volte): crm.pode_catalogar,
--   pessoas.pode_*, as 20 funções da lista do pentester e as funções/policies "(gp_is_admin() OR editar <depto>)".
--
-- AS 5 PERGUNTAS
--   escala: 10 funções, 1 gatilho, ~1 capacidade nova. índice: o de acesso.* e PK de acesso.master. frequência: o
--   gatilho roda em cada insert/update de perfis (raro). repetição: nenhuma.
--   reversão: bloco REVERSÃO no fim (drop do gatilho, corpos de acesso.corpo_antes, coluna pela foto).
--
-- IDEMPOTENTE: foto e capacidade com on conflict; create or replace; drop trigger if exists antes de criar.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.perfis_antes_20261007') is null then
    raise exception '20261007u: a fase 2 (20261007t) não foi aplicada';
  end if;
  if (select count(*) from acesso.master) <> 3 then
    raise exception '20261007u: esperava os 3 masters (Victor Hugo, Arthur Galvão, João Pedro Alves)';
  end if;
end
$g$;

-- Exceção nominal: lista FECHADA (só muda por migration; não há RPC para ela)
create table if not exists acesso.excecao_admin (
  perfil_id     uuid primary key references public.perfis(id) on delete cascade,
  cargo         text not null check (cargo in ('admin', 'dev')),
  motivo        text not null,
  autorizado_por text not null,
  registrado_em timestamptz not null default now()
);
alter table acesso.excecao_admin enable row level security;
revoke all on acesso.excecao_admin from public, anon, authenticated;
insert into acesso.excecao_admin (perfil_id, cargo, motivo, autorizado_por) values
  ('1b153c6d-6287-43ae-9e02-6caf6e6f9c33', 'admin', 'devolução manual de admin/dev, decisão do Victor 07/10', 'Victor Hugo; feito por João Pedro Alves 18:39:06 UTC'),  -- Cristiane
  ('00b177e0-3c8b-4e55-8f64-f57560bbbd74', 'admin', 'devolução manual de admin/dev, decisão do Victor 07/10', 'Victor Hugo; feito por João Pedro Alves 18:39:06 UTC'),  -- Fernanda Tavares #00b1
  ('e1d2863d-c975-46bd-b35f-45b1039328e3', 'admin', 'devolução manual de admin/dev, decisão do Victor 07/10', 'Victor Hugo; feito por João Pedro Alves 18:39:06 UTC'),  -- Isabela Teixeira
  ('6ed2bfc4-1d69-458d-9954-77a03902c56a', 'dev',   'devolução manual de admin/dev, decisão do Victor 07/10', 'Victor Hugo; feito por João Pedro Alves 18:39:06 UTC'),  -- Elaine Montenegro
  ('ec6d1905-200e-4efd-a172-8546f293a4bd', 'dev',   'devolução manual de admin/dev, decisão do Victor 07/10', 'Victor Hugo; feito por João Pedro Alves 18:39:06 UTC'),  -- Marcio Carvalho de Sá
  ('0f6dd53c-6d1a-4f6b-af00-dc05e6284f68', 'dev',   'devolução manual de admin/dev, decisão do Victor 07/10', 'Victor Hugo; feito por João Pedro Alves 18:39:06 UTC')   -- Aldri Santana
on conflict (perfil_id) do nothing;

-- Pré-condição (B1 do pentester: TODOS os status, não só ativo): todo perfil com admin/dev é master ou está na exceção
-- com esse mesmo cargo. Qualquer outro aborta.
do $b1$
declare v text;
begin
  select string_agg(p.nome || ' #' || left(p.id::text, 4) || ' (' || p.cargo || ', ' || p.status || ')', ', ') into v
    from public.perfis p
   where p.cargo in ('admin', 'dev')
     and not exists (select 1 from acesso.master m where m.perfil_id = p.id)
     and not exists (select 1 from acesso.excecao_admin e where e.perfil_id = p.id and e.cargo = p.cargo);
  if v is not null then
    raise exception '20261007u: admin/dev fora dos masters e da exceção nominal: %. Conferir antes de limpar.', v;
  end if;
end
$b1$;

create or replace function acesso.eh_admin() returns boolean
language sql stable security definer set search_path = '' as $f$
  select coalesce(acesso.eh_master(), false)
      or exists (select 1 from acesso.excecao_admin e join public.perfis p on p.id = e.perfil_id
                  where e.perfil_id = acesso.eu() and p.cargo = e.cargo)
$f$;
revoke all on function acesso.eh_admin() from public, anon, authenticated;

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
  select coalesce(acesso.eh_admin(), false);  -- 20261007u: admin do sistema = master ou exceção nominal
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

-- CPF: a coluna vira a capacidade cpf.ver antes de a guarda deixar de ler a coluna
create table if not exists acesso.cpf_coluna_antes_20261007 (
  id uuid primary key, nome text, status text, pode_ver_cpf_completo boolean, foto_em timestamptz not null default now()
);
alter table acesso.cpf_coluna_antes_20261007 enable row level security;
revoke all on acesso.cpf_coluna_antes_20261007 from public, anon, authenticated;
insert into acesso.cpf_coluna_antes_20261007 (id, nome, status, pode_ver_cpf_completo)
select p.id, p.nome, p.status, p.pode_ver_cpf_completo from public.perfis p where p.pode_ver_cpf_completo
on conflict (id) do nothing;
insert into acesso.capacidade (perfil_id, chave)
select f.id, 'cpf.ver' from acesso.cpf_coluna_antes_20261007 f where f.status = 'ativo'
on conflict do nothing;
update public.perfis set pode_ver_cpf_completo = false, atualizado_em = now() where pode_ver_cpf_completo;

create or replace function public.gp_pode_ver_cpf()
 returns boolean language sql stable security definer set search_path to 'public'
as $function$
  select coalesce(acesso.tem('cpf.ver'), false);  -- 20261007u: CPF completo é só a capacidade cpf.ver
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
  ) OR coalesce(acesso.eh_admin(), false) OR coalesce(case  -- 20261007u
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
  select coalesce(acesso.eh_admin(), false)  -- 20261007u
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
  ) or coalesce(acesso.pode_editar('educacional'), false) or coalesce(acesso.eh_admin(), false);  -- 20261007u
$function$;

create or replace function public.pa_pode_pedir()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(public.gp_eh_equipe(), false) and (exists (
    select 1 from public.perfis p
     where p.id = (select auth.uid()) and p.status = 'ativo'
       and p.cargo in ('gestor', 'operador') and 'pedidos_alteracao' = any(coalesce(p.areas, '{}')))
    or coalesce(acesso.pode_editar('educacional'), false) or coalesce(acesso.eh_admin(), false));  -- 20261007u
$function$;

create or replace function mkt.pode_ver(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_ver('marketing', acesso.area_mkt(p_area)), false) or coalesce(acesso.eh_admin(), false);  -- 20261007u
$function$;

create or replace function mkt.pode_editar(p_area text default null)
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce(acesso.pode_editar('marketing', acesso.area_mkt(p_area)), false) or coalesce(acesso.eh_admin(), false);  -- 20261007u
$function$;

-- Gatilho em public.perfis: cargo admin/dev só master; CPF só pela capacidade; nome próprio; log
create or replace function acesso.tg_perfis_guarda() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare
  v_uid uuid := (select auth.uid());
begin
  -- B1: confere também quando só o status muda (pendente/negado com admin voltando a ativo)
  if new.cargo in ('admin', 'dev')
     and (tg_op = 'INSERT' or old.cargo is distinct from new.cargo or old.status is distinct from new.status)
     and not exists (select 1 from acesso.master m where m.perfil_id = new.id)
     and not exists (select 1 from acesso.excecao_admin e where e.perfil_id = new.id and e.cargo = new.cargo) then
    raise exception 'Cargo % é só de master (acesso.master) ou da exceção nominal. Dê acesso por departamento/área (acesso_vincular).', new.cargo
      using errcode = '42501';
  end if;
  if coalesce(new.pode_ver_cpf_completo, false)
     and (tg_op = 'INSERT' or not coalesce(old.pode_ver_cpf_completo, false)) then
    raise exception 'CPF completo agora é a capacidade cpf.ver (acesso_capacidade_definir, só master).' using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.nome is distinct from old.nome and v_uid is not null and v_uid = new.id
     and not exists (select 1 from acesso.master m where m.perfil_id = v_uid) then
    raise exception 'O nome só muda pela gestão de usuários.' using errcode = '42501';
  end if;
  if tg_op = 'INSERT'
     or (old.cargo, old.status, old.areas, old.funcoes, old.pode_ver_cpf_completo)
        is distinct from (new.cargo, new.status, new.areas, new.funcoes, new.pode_ver_cpf_completo) then
    insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
    values (v_uid, 'perfis', lower(tg_op), new.id,
            case when tg_op = 'UPDATE' then jsonb_build_object('cargo', old.cargo, 'status', old.status, 'areas', old.areas,
                                                               'funcoes', old.funcoes, 'cpf', old.pode_ver_cpf_completo) end,
            jsonb_build_object('cargo', new.cargo, 'status', new.status, 'areas', new.areas, 'funcoes', new.funcoes,
                               'cpf', new.pode_ver_cpf_completo,
                               -- B2: sem auth.uid() (rota com service_role, SQL), diz ao menos por onde entrou
                               'via', coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', current_user)));
  end if;
  return new;
end
$f$;
revoke all on function acesso.tg_perfis_guarda() from public, anon, authenticated;
drop trigger if exists acesso_guarda on public.perfis;
create trigger acesso_guarda before insert or update on public.perfis for each row execute function acesso.tg_perfis_guarda();

do $c$
begin
  if (select prosrc from pg_proc where oid = 'public.gp_is_admin()'::regprocedure) !~ 'acesso\.eh_admin' then
    raise exception '20261007u: gp_is_admin não virou master ou exceção (acesso.eh_admin)';
  end if;
  if (select count(*) from acesso.excecao_admin) <> 6 then
    raise exception '20261007u: a exceção nominal tem de ter exatamente os 6 perfis decididos';
  end if;
  if exists (select 1 from public.perfis where pode_ver_cpf_completo) then
    raise exception '20261007u: sobrou pode_ver_cpf_completo ligado';
  end if;
  if exists (select 1 from acesso.cpf_coluna_antes_20261007 f where f.status = 'ativo'
              and not exists (select 1 from acesso.capacidade c where c.perfil_id = f.id and c.chave = 'cpf.ver')) then
    raise exception '20261007u: quem tinha CPF pela coluna não ganhou cpf.ver';
  end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.perfis'::regclass and tgname = 'acesso_guarda' and tgenabled = 'O') then
    raise exception '20261007u: gatilho acesso_guarda não ficou ligado';
  end if;
end
$c$;

-- REVERSÃO (numa transação; antes de reverter a fase 2, reverter esta, porque o gatilho recusa devolver admin):
-- drop trigger if exists acesso_guarda on public.perfis;
-- (a tabela acesso.excecao_admin fica, como registro; acesso.eh_admin() sai depois de recriar os corpos)
-- update public.perfis p set pode_ver_cpf_completo = f.pode_ver_cpf_completo from acesso.cpf_coluna_antes_20261007 f where f.id = p.id;
-- delete from acesso.capacidade c using acesso.cpf_coluna_antes_20261007 f where f.id = c.perfil_id and c.chave = 'cpf.ver'
--   and c.criado_em >= '<hora da aplicação>';
-- do $v$ declare r record; begin
--   for r in select * from acesso.corpo_antes where migration = '20261007u' and tipo = 'funcao' loop execute r.definicao; end loop;
-- end $v$;
-- drop function if exists acesso.eh_admin();
