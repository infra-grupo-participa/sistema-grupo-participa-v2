-- 20261006b: Marketing > Tráfego, as 16 contas de anúncio do Meta que o token do sistema enxerga
--
-- O QUE FAZ
--   O token do Meta (Vault meta_ads_token, usuário do sistema do portfólio Grupo Participa) já está em produção e enxerga
--   16 contas, lidas da API em 06/10/2026 (GET /me/adaccounts). Esta migration:
--     1. Acrescenta em mkt_trafego.contas a UNIDADE (mkt.unidades da 20261006a: csm, escritorio, aurum, diamantes; nulo =
--        não classificada) e a marca PRINCIPAL (as principais aparecem primeiro na seleção; todas continuam selecionáveis).
--     2. Cadastra as 16 contas de forma IDEMPOTENTE por (plataforma, id): nome EXATO da API, id sem act_, plataforma meta,
--        moeda BRL, interna (dono = grupo), unidade e principal pela regra do Victor (06/10/2026): Escritório = contas
--        com "Seminário" ou "Aurum" no nome; CSM = Marcio, Holding Total, CNF, Imersões, THB, Treinamento. "CA - Tutorial"
--        = CSM e INATIVA (Victor: não vai ser usada; fora da seleção e da coleta; pode ser reativada na tela). Principais
--        (confirmadas pelo Victor): 1º Holding Total 2.0, CNF Holding Familiar, THB - Ads, Treinamento Participa,
--        Seminários - Leads. Conta que já existir: nome, unidade e principal são atualizados; ativa só muda para a
--        CA - Tutorial (inativa); obs e token_vault ficam como estão.
--     3. public.trafego_contas_listar passa a devolver unidade e principal, principais primeiro; public.trafego_conta_marcar
--        grava unidade e principal pela tela.
--   NÃO liga a coleta: nenhum cron é agendado (a conferência aborta se encontrar trafego-meta agendada).
--   Depende da 20261006a (mkt.unidades) e, por ela, da 20261005p e da 20261005r (todas NÃO aplicadas).
--
--   Padrão do repo: tabelas fechadas, acesso só por função public.trafego_* SECURITY DEFINER com search_path '' e a trava
--   mkt.pode_ver('mkt_trafego') (admin/dev).
--
-- AS 5 PERGUNTAS
--   escala: 16 contas; dezenas no futuro.   índice: o único (plataforma, conta_externa) da 20261005p.
--   frequência: lista ao abrir a Central e o cadastro do projeto.   repetição: nenhuma.   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261006b_ensaio.sql (begin … rollback). Explicação: 20261006b.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
begin
  if exists (select 1 from information_schema.columns where table_schema = 'mkt_trafego' and table_name = 'contas'
              and column_name in ('unidade', 'principal')) then
    raise exception '20261006b: já aplicada (mkt_trafego.contas já tem unidade/principal)';
  end if;
  if to_regclass('mkt.unidades') is null or to_regclass('mkt_trafego.contas') is null
     or to_regprocedure('public.trafego_contas_listar()') is null then
    raise exception '20261006b: falta a 20261006a (e a 20261005p/r): aplicar antes';
  end if;
  if not exists (select 1 from mkt.unidades where codigo = 'csm') or not exists (select 1 from mkt.unidades where codigo = 'escritorio') then
    raise exception '20261006b: mkt.unidades sem csm/escritorio';
  end if;
  if to_regprocedure('public.trafego_conta_marcar(bigint,text,boolean)') is not null then
    raise exception '20261006b: public.trafego_conta_marcar já existe';
  end if;
end
$guarda$;

-- ─── 1. Colunas ──────────────────────────────────────────────────────────────────────────────────────────────────────
alter table mkt_trafego.contas
  add column unidade text references mkt.unidades(codigo) on delete restrict,
  add column principal boolean not null default false;
comment on column mkt_trafego.contas.unidade is
  'Unidade da conta (mkt.unidades: csm, escritorio, aurum, diamantes). Nulo = não classificada. Regra do Victor (06/10/2026) '
  'para as internas: Escritório = "Seminário" ou "Aurum" no nome; CSM = Marcio, Holding Total, CNF, Imersões, THB, Treinamento. 20261006b.';
comment on column mkt_trafego.contas.principal is 'Conta principal: aparece primeiro na seleção (todas continuam selecionáveis). 20261006b.';

-- ─── 2. As 16 contas (nome exato da API em 06/10/2026; id sem act_) ─────────────────────────────────────────────────
insert into mkt_trafego.contas as c (plataforma, conta_externa, nome, dono, moeda, ativa, unidade, principal)
select 'meta', v.id, v.nome, 'grupo', 'BRL', v.ativa, v.unidade, v.principal
  from (values
    ('686822108510130',  '1º Dr. Marcio Carvalho de Sá ADS',       'csm',        false, true),
    ('363803868960273',  '2ºDr. Marcio Carvalho de Sá - 2',        'csm',        false, true),
    ('2345107592642621', '3ª Dr. Marcio Carvalho de Sá',           'csm',        false, true),
    ('1230564179214484', '4º Dr. Marcio Carvalho de Sá',           'csm',        false, true),
    ('1467134847777565', '1º Holding Total 2.0',                   'csm',        true, true),
    ('919875374390968',  'Holding Total 2.0 - Dist. de Conteúdo',  'csm',        false, true),
    ('1570090828117070', 'CNF Holding Familiar',                   'csm',        true, true),
    ('1008535771830636', 'Imersões - Vendas',                      'csm',        false, true),
    ('1767572701045744', 'THB - Ads',                              'csm',        true, true),
    ('2634066567011997', 'Treinamento Participa',                  'csm',        true, true),
    ('187642820066112',  '1ºAurum',                                'escritorio', false, true),
    ('1060867594526201', '2ºAurum Teste',                          'escritorio', false, true),
    ('505773954864951',  '3ºAurum Tutorial',                       'escritorio', false, true),
    ('989935947003541',  'Seminário - Dist. de Cont.',             'escritorio', false, true),
    ('1190477699799714', 'Seminários - Leads',                     'escritorio', true, true),
    ('2423459874841639', 'CA - Tutorial',                          'csm',         false, false)
  ) v(id, nome, unidade, principal, ativa)
on conflict (plataforma, conta_externa) do update
   set nome = excluded.nome, unidade = excluded.unidade, principal = excluded.principal,
       ativa = case when excluded.ativa then c.ativa else false end, atualizado_em = now();

-- ─── 3. Funções da tela ──────────────────────────────────────────────────────────────────────────────────────────────
-- A lista da 20261005p, agora com unidade e principal; principais primeiro (dentro de ativa e plataforma).
create or replace function public.trafego_contas_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', c.id, 'plataforma', c.plataforma, 'conta_externa', c.conta_externa, 'nome', c.nome, 'dono', c.dono,
            'cliente', c.cliente, 'moeda', c.moeda, 'ativa', c.ativa, 'obs', c.obs, 'atualizado_em', c.atualizado_em,
            'unidade', c.unidade, 'principal', c.principal,
            'campanhas', (select count(*) from mkt_trafego.campanhas k where k.conta_id = c.id))
          order by c.ativa desc, c.principal desc, c.plataforma, c.nome), '[]'::jsonb)
            from mkt_trafego.contas c);
end
$$;

-- Unidade e principal de uma conta (a tela chama depois de salvar a conta). p_unidade vazio = sem unidade. A unidade
-- precisa combinar com o dono: grupo → unidade interna (CSM, Escritório); aurum → Aurum; diamante → Diamantes.
create function public.trafego_conta_marcar(p_conta bigint, p_unidade text, p_principal boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uni text := nullif(lower(btrim(coalesce(p_unidade, ''))), '');
  v_dono text;
begin
  if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
  select dono into v_dono from mkt_trafego.contas where id = p_conta for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Conta não encontrada.'); end if;
  if v_uni is not null and not exists (select 1 from mkt.unidades u where u.codigo = v_uni and u.ativa
       and case v_dono when 'grupo' then u.tipo = 'interno' when 'aurum' then u.codigo = 'aurum' when 'diamante' then u.codigo = 'diamantes' else false end) then
    return jsonb_build_object('ok', false, 'msg', 'Unidade não combina com o dono da conta (Grupo: CSM ou Escritório; Aurum; Diamantes).');
  end if;
  update mkt_trafego.contas
     set unidade = v_uni, principal = coalesce(p_principal, false), atualizado_em = now(), atualizado_por = (select auth.uid())
   where id = p_conta;
  return jsonb_build_object('ok', true, 'msg', 'Unidade e principal da conta salvos.');
end
$$;

revoke all on function public.trafego_conta_marcar(bigint, text, boolean) from public, anon, authenticated, service_role;
grant execute on function public.trafego_conta_marcar(bigint, text, boolean) to authenticated;

-- ─── 4. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────────
do $confere$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.prosecdef, p.proconfig, p.proacl from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname in ('trafego_contas_listar', 'trafego_conta_marcar') loop
    if not (f.proconfig @> array['search_path=""']) or not f.prosecdef then raise exception '20261006b: % fora do padrão', f.sig; end if;
    if has_function_privilege('anon', f.sig, 'execute') or not has_function_privilege('authenticated', f.sig, 'execute')
       or has_function_privilege('service_role', f.sig, 'execute') then
      raise exception '20261006b: grant errado em %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261006b: PUBLIC executa %', f.sig;
    end if;
  end loop;
  if has_table_privilege('authenticated', 'mkt_trafego.contas', 'select') or has_table_privilege('anon', 'mkt_trafego.contas', 'select') then
    raise exception '20261006b: mkt_trafego.contas aberta';
  end if;
  if (select count(*) from mkt_trafego.contas where plataforma = 'meta' and conta_externa in (
        '686822108510130', '363803868960273', '2345107592642621', '1230564179214484', '1467134847777565', '919875374390968',
        '1570090828117070', '1008535771830636', '1767572701045744', '2634066567011997', '187642820066112', '1060867594526201',
        '505773954864951', '989935947003541', '1190477699799714', '2423459874841639')) <> 16 then
    raise exception '20261006b: esperava as 16 contas do Meta';
  end if;
  if (select count(*) filter (where unidade = 'csm') || '/' || count(*) filter (where unidade = 'escritorio') || '/'
             || count(*) filter (where unidade is null) || '/' || count(*) filter (where principal) || '/' || count(*) filter (where not ativa)
        from mkt_trafego.contas where plataforma = 'meta' and dono = 'grupo'
         and conta_externa in ('686822108510130', '363803868960273', '2345107592642621', '1230564179214484', '1467134847777565',
           '919875374390968', '1570090828117070', '1008535771830636', '1767572701045744', '2634066567011997', '187642820066112',
           '1060867594526201', '505773954864951', '989935947003541', '1190477699799714', '2423459874841639')) <> '11/5/0/5/1' then
    raise exception '20261006b: unidades/principais diferentes do esperado (11 CSM, 5 Escritório, 5 principais, 1 inativa)';
  end if;
  -- sem pg_cron (banco local) a checagem não se aplica
  if to_regclass('cron.job') is not null then
    if exists (select 1 from cron.job where jobname in ('trafego-meta', 'trafego-meta-hoje')) then
      raise exception '20261006b: coleta do Meta agendada (deveria continuar desligada)';
    end if;
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação; ANTES da reversão da 20261006a; apaga as 16 contas se nenhuma campanha as usa) ══════════
-- begin;
-- drop function public.trafego_conta_marcar(bigint, text, boolean);
-- create or replace function public.trafego_contas_listar() returns jsonb
-- language plpgsql stable security definer set search_path = '' as $f$
-- begin
--   if not mkt.pode_ver('mkt_trafego') then raise exception 'acesso negado' using errcode = '42501'; end if;
--   return (select coalesce(jsonb_agg(jsonb_build_object(
--             'id', c.id, 'plataforma', c.plataforma, 'conta_externa', c.conta_externa, 'nome', c.nome, 'dono', c.dono,
--             'cliente', c.cliente, 'moeda', c.moeda, 'ativa', c.ativa, 'obs', c.obs, 'atualizado_em', c.atualizado_em,
--             'campanhas', (select count(*) from mkt_trafego.campanhas k where k.conta_id = c.id))
--           order by c.ativa desc, c.plataforma, c.nome), '[]'::jsonb)
--             from mkt_trafego.contas c);
-- end
-- $f$;
-- delete from mkt_trafego.contas c where c.plataforma = 'meta' and c.conta_externa in (
--   '686822108510130', '363803868960273', '2345107592642621', '1230564179214484', '1467134847777565', '919875374390968',
--   '1570090828117070', '1008535771830636', '1767572701045744', '2634066567011997', '187642820066112', '1060867594526201',
--   '505773954864951', '989935947003541', '1190477699799714', '2423459874841639')
--   and not exists (select 1 from mkt_trafego.campanhas k where k.conta_id = c.id)
--   and not exists (select 1 from mkt_trafego.projeto_contas pc where pc.conta_id = c.id);
-- alter table mkt_trafego.contas drop column principal, drop column unidade;
-- commit;
