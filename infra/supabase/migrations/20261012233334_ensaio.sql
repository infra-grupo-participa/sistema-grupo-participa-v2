-- Ensaio de 20261012233334 (transação desfeita). Fotografa as 14 RPCs presenciais e da Clínica Miami com a chave da Clínica, a da Black
-- e uma inexistente, antes e depois da trava: número de linhas e md5 das linhas (o dado pessoal não sai do banco, só o md5).
-- A marcar_teste usa uma pessoa que não existe, então nunca grava. Depois roda a reversão e confere que os corpos voltaram.
begin;
create temp table _z_out (em bigserial, fase text, chave text, rpc text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
create function pg_temp._z_foto(p_sql text) returns text language plpgsql as $f$
declare v text;
begin
  execute format('select count(*) || '' linhas '' || coalesce(md5(string_agg(t::text, ''|'' order by t::text)), ''-'') from (%s) t', p_sql) into v;
  return v;
exception when others then
  return 'ERRO ' || sqlstate || ' ' || sqlerrm;
end
$f$;
grant execute on function pg_temp._z_foto(text) to anon;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', '00000000-0000-4000-8000-0000000000ff', true)$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('black-friday-2026-10', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('black-friday-2026-10', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'black', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('black-friday-2026-10', '00000000-0000-4000-8000-0000000000ff', true)$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('nao-existe', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('nao-existe', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'inexistente', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('nao-existe', '00000000-0000-4000-8000-0000000000ff', true)$s$));
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica-fora-da-equipe', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica-fora-da-equipe', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', '00000000-0000-4000-8000-0000000000ff', true)$s$));
select set_config('request.jwt.claims', '{}', true);
set local role anon;
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('1 antes', 'clinica-anon', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
reset role;
insert into pg_temp._z_out (fase, chave, rpc, linha) select '1 antes', '-', 'corpos', md5(string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and (p.proname like 'dados_presencial%' or p.proname like 'dados_miami%');

-- ===== MIGRATION =====
-- 20261012233334: trava de modelo nas RPCs do dashboard presencial (dados_presencial_*) e da Clínica Miami (dados_miami_*)
--
-- STATUS: ver 20261012233334.explain.md.
-- POR QUE: risco do §5 do pentester na migration A da Black (20261012231649). As 14 RPCs abaixo só checavam
--   dados.cadastro (equipe + chave ativa), ou nem isso no caso da marcar_teste, e rodavam com a chave de qualquer modelo.
--   Com a chave da Black (jornada-captacao), dados_presencial_leads passaria a devolver nome, e-mail e telefone dos
--   pré-checkouts do projeto 4 por uma RPC que não foi revisada para a Black. Decisão do Maestro (13/10/2026), com a
--   autorização do Victor. Vai ao ar antes da B da Black (20261013130000).
-- O QUE FAZ:
--   1. dados.presencial_cadastro(p_chave): dados.cadastro + modelo presencial-base (P0002 se for outro), igual à atm_cadastro.
--   2. As 13 RPCs de leitura trocam dados.cadastro por dados.presencial_cadastro. Nada mais muda no corpo.
--   3. dados_presencial_marcar_teste (lê dados.dashboards direto) passa a exigir o modelo presencial-base.
--   Os corpos abaixo são os vivos em 13/10/2026 (pg_get_functiondef), conferidos por md5 na guarda. O create or replace
--   mantém dono e permissões.
-- AS 5 PERGUNTAS: escala: 1 função nova e 14 trocadas, sem tabela; índice: nenhum novo (a trava lê dados.dashboards pela
--   chave, que é PK); frequência: a abertura do dashboard presencial; repetição: a guarda recusa rodar de novo (o md5 muda),
--   de propósito; reversão: 20261012233334_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare
  r record;
begin
  for r in select * from (values
    ('public.dados_miami_diamantes(text)', '21aaac1cf342dff6aa66f2062be94dce'),
    ('public.dados_miami_interesse(text)', 'fb84c84c07073ffec799e8bf37e16919'),
    ('public.dados_presencial_compradores_perfil(text)', 'e58dc42304f885abe4044d8b465e20ad'),
    ('public.dados_presencial_disparos(text)', 'e2bcf87a8c396dc8d9ca77643bcbe84c'),
    ('public.dados_presencial_leads(text)', '667e0e4255e9f4f079f8d26053ac0534'),
    ('public.dados_presencial_marcar_teste(text,uuid,boolean)', '4a0eb550e499b40c3bf903833264bc0e'),
    ('public.dados_presencial_pagamentos(text)', '845d1e4efcaac7212e98277a4bb3e89d'),
    ('public.dados_presencial_pendencias(text)', 'b8af74e3016ee0c057af2d9e2bc99889'),
    ('public.dados_presencial_pendencias_pessoas(text,text)', '31679bee08dbba2cf603eda40f76da50'),
    ('public.dados_presencial_resumo(text)', 'c8e7051801da180cb6ae15855c5ee4c1'),
    ('public.dados_presencial_serie_diaria(text)', 'e008e47a08450daa43cbb3ee8818077f'),
    ('public.dados_presencial_serie_vendas(text)', 'ae441a5de12eab7deaae4a1faeef6e9c'),
    ('public.dados_presencial_vendas(text)', '0b2ffd70e07f9ab77d78ea3e996fe607'),
    ('public.dados_presencial_vendas_por_hora(text)', '12eaff0912c643793ca276d44d3834e5')
  ) v(sig, h) loop
    if (select md5(prosrc) from pg_proc where oid = r.sig::regprocedure) is distinct from r.h then
      raise exception '20261012233334: corpo vivo de % mudou. Reler.', r.sig;
    end if;
  end loop;
  if (select md5(prosrc) from pg_proc where oid = 'dados.cadastro(text)'::regprocedure) <> 'dd7dc3b59ecc65784b1302955a8a7fe2' then
    raise exception '20261012233334: dados.cadastro mudou. Reler.';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'clinica-miami-2026-12' and modelo = 'presencial-base') then
    raise exception '20261012233334: a Clínica Miami não está como presencial-base. Reler.';
  end if;
end
$g$;

-- 1. trava do modelo presencial
create or replace function dados.presencial_cadastro(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
declare
  r dados.dashboards := dados.cadastro(p_chave);   -- 42501 sem acesso, P0002 chave fora do cadastro
begin
  if r.modelo is distinct from 'presencial-base' then
    raise exception 'dashboard de outro modelo' using errcode = 'P0002';
  end if;
  return r;
end
$function$;
revoke all on function dados.presencial_cadastro(text) from public, anon, authenticated, service_role;

-- 2 e 3. as 14 RPCs (corpo vivo, só a linha da trava trocada)
-- dados_miami_diamantes(text)
CREATE OR REPLACE FUNCTION public.dados_miami_diamantes(p_chave text)
 RETURNS TABLE(lista_ordem integer, lista_nome text, status text, casamento text, resposta_uuid uuid, respondido_em timestamp with time zone, n_respostas integer, nome_formulario text, email text, telefone text, grupo text, situacao text, situacao_codigo text, chegada text, chegada_data date, retorno text, retorno_data date, aeroporto text, hospedagem text, acompanhado text, acompanhantes text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
  v_slug text := (select f.form_slug from dados.dashboard_formularios f where f.chave = d.chave and f.papel = 'diamantes');
begin
  return query
  with r as (
    select x.uuid, x.respondido_em, x.email, x.telefone, x.respostas,
           coalesce(nullif(x.email, ''), nullif(right(x.telefone, 8), ''), x.uuid::text) as pessoa
      from respondi.respostas x
     where v_slug is not null and x.form_slug = v_slug
  ),
  p as (  -- uma linha por pessoa: a resposta mais recente
    select distinct on (r.pessoa) r.*, count(*) over (partition by r.pessoa)::int as n,
           dados.respondi_valor(r.respostas, 'Nome completo') as nome_f
      from r
     order by r.pessoa, r.respondido_em desc, r.uuid
  ),
  l as (
    select lp.ordem, lp.nome, lp.resposta_uuid_manual, dados.nome_tokens(lp.nome) as tk
      from dados.dashboard_lista_pessoas lp
     where lp.chave = d.chave and lp.lista = 'diamantes'
  ),
  par as (  -- cada nome da lista com a sua resposta (manual vence; senão a mais recente que casa pelo nome)
    select l.ordem, l.nome, m.uuid, m.casamento
      from l
      left join lateral (
        select p.uuid, case when p.uuid = l.resposta_uuid_manual then 'manual' else 'nome' end as casamento
          from p
         where p.uuid = l.resposta_uuid_manual
            or (l.resposta_uuid_manual is null and dados.nome_casa(l.tk, dados.nome_tokens(p.nome_f)))
         order by (p.uuid = l.resposta_uuid_manual) desc, p.respondido_em desc
         limit 1) m on true
  ),
  linhas as (
    select par.ordem, par.nome, case when par.uuid is null then 'pendente' else 'respondeu' end as st, par.casamento, par.uuid
      from par
    union all
    select null, null, 'fora_da_lista', null, p.uuid
      from p
     where not exists (select 1 from par where par.uuid = p.uuid)
  )
  select li.ordem, li.nome, li.st, li.casamento, p.uuid, p.respondido_em, p.n, p.nome_f, p.email, p.telefone,
         dados.respondi_valor(p.respostas, 'Qual é o seu grupo'),
         v.sit,
         case when v.sit like 'Já estou confirmado%' then 'confirmado'
              when v.sit like 'Estou me organizando%' then 'organizando'
              when v.sit like 'Já sei que não%' then 'nao_vai' end,
         v.cheg, dados.data_br(v.cheg), v.ret, dados.data_br(v.ret),
         dados.respondi_valor(p.respostas, 'Em qual aeroporto você chegará'),
         dados.respondi_valor(p.respostas, 'Onde você ficará hospedado'),
         dados.respondi_valor(p.respostas, 'Você estará acompanhado'),
         dados.respondi_valor(p.respostas, 'Quantas pessoas irão com você')
    from linhas li
    left join p on p.uuid = li.uuid
    left join lateral (select dados.respondi_valor(p.respostas, 'Acerca dos eventos internacionais') as sit,
                              dados.respondi_valor(p.respostas, 'Qual a sua data de chegada') as cheg,
                              dados.respondi_valor(p.respostas, 'Qual a sua data de retorno') as ret) v on true
   order by li.ordem nulls last, p.respondido_em, p.uuid;
end
$function$;

-- dados_miami_interesse(text)
CREATE OR REPLACE FUNCTION public.dados_miami_interesse(p_chave text)
 RETURNS TABLE(resposta_uuid uuid, respondido_em timestamp with time zone, n_respostas integer, nome text, email text, telefone text, turma text, passaporte text, visto text, planos text, comprou_passagem text, data_passagem text, confirma_pre_venda text, deseja_programa text, comprou boolean, compra_status text, compra_transacao text, compra_em timestamp with time zone, casou_por text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
  v_slug text := (select f.form_slug from dados.dashboard_formularios f where f.chave = d.chave and f.papel = 'interesse');
begin
  return query
  with r as (
    select x.uuid, x.respondido_em, x.email, x.telefone, x.respostas,
           coalesce(nullif(x.email, ''), nullif(right(x.telefone, 8), ''), x.uuid::text) as pessoa
      from respondi.respostas x
     where v_slug is not null and x.form_slug = v_slug
  ),
  p as (
    select distinct on (r.pessoa) r.*, count(*) over (partition by r.pessoa)::int as n
      from r
     order by r.pessoa, r.respondido_em desc, r.uuid
  ),
  t as (
    select tr.transacao, tr.status_grupo, coalesce(tr.aprovado_em, tr.pedido_em) as em,
           lower(btrim(tr.email)) as email, right(regexp_replace(coalesce(tr.telefone, ''), '\D', '', 'g'), 8) as fone8,
           case tr.status_grupo when 'pago' then 1 when 'em_aberto' then 2 when 'atrasado' then 3 when 'estornado' then 4
                                when 'recusado' then 5 when 'expirado' then 6 else 7 end as prio
      from dados.transacoes(d.conta_hotmart, d.oferta_codigo) tr
     where v_slug is not null
  )
  select p.uuid, p.respondido_em, p.n,
         dados.respondi_valor(p.respostas, 'Qual é o seu nome completo'), p.email, p.telefone,
         dados.respondi_valor(p.respostas, 'Qual é a sua turma'),
         dados.respondi_valor(p.respostas, 'Você tem passaporte válido'),
         dados.respondi_valor(p.respostas, 'Você tem visto americano válido'),
         dados.respondi_valor(p.respostas, 'Quais são os seus planos para a viagem'),
         dados.respondi_valor(p.respostas, 'Você já comprou a sua passagem'),
         dados.respondi_valor(p.respostas, 'Qual é a data da sua passagem'),
         dados.respondi_valor(p.respostas, 'Você confirma que fará a inscrição na pré-venda'),
         dados.respondi_valor(p.respostas, 'Você deseja participar do programa Holding Trip Miami'),
         coalesce(c.status_grupo = 'pago', false), c.status_grupo, c.transacao, c.em, c.por
    from p
    left join lateral (
      select t.transacao, t.status_grupo, t.em,
             case when t.email = nullif(lower(btrim(p.email)), '') then 'email' else 'telefone' end as por
        from t
       where t.email = nullif(lower(btrim(p.email)), '')
          or (length(t.fone8) = 8 and length(coalesce(p.telefone, '')) >= 10 and t.fone8 = right(p.telefone, 8))
       order by t.prio, (t.email = nullif(lower(btrim(p.email)), '')) desc, t.em desc nulls last, t.transacao
       limit 1) c on true
   order by coalesce(c.status_grupo = 'pago', false), p.respondido_em desc, p.uuid;
end
$function$;

-- dados_presencial_compradores_perfil(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_compradores_perfil(p_chave text)
 RETURNS TABLE(dimensao text, valor text, compradores integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  with tx as (
    select t.email, x.documento, t.telefone
      from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
      left join dados.transacoes_extra(d.conta_hotmart, d.oferta_codigo) x on x.transacao = t.transacao
     where t.pago and t.email is not null
  ), comp as (
    select tx.email, max(tx.documento) as documento, max(tx.telefone) as telefone from tx group by tx.email
  ), al as materialized (
    select al0.turma_id, al0.instrucao, al0.cancelado_em, al0.eh_socio, al0.atualizado_em,
           nullif(lower(btrim(al0.email)), '') as em,
           nullif(regexp_replace(coalesce(al0.documento, ''), '\D', '', 'g'), '') as doc,
           case when length(regexp_replace(coalesce(al0.telefone_e164, al0.telefone, ''), '\D', '', 'g')) >= 11
                then right(regexp_replace(coalesce(al0.telefone_e164, al0.telefone, ''), '\D', '', 'g'), 11) end as tel11
      from public.thb_alunos al0
  ), cn as (
    select c.email,
           nullif(regexp_replace(coalesce(c.documento, ''), '\D', '', 'g'), '') as doc,
           case when length(regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g')) >= 11
                then right(regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g'), 11) end as tel11
      from comp c
  ), cand as (
    select cn.email, al.*, 1 as prio, 'email'::text as k from cn join al on al.em = cn.email
    union all
    select cn.email, al.*, 2, 'documento' from cn join al on al.doc = cn.doc where length(cn.doc) >= 11
    union all
    select cn.email, al.*, 3, 'telefone' from cn join al on al.tel11 = cn.tel11
  ), m as (
    select distinct on (cand.email) cand.email, cand.turma_id, cand.instrucao, cand.k
      from cand
     order by cand.email, cand.prio, (cand.cancelado_em is null) desc, coalesce(cand.eh_socio, false),
              cand.atualizado_em desc nulls last
  ), pf as (
    select cn.email, tu.codigo as turma, nullif(btrim(m.instrucao), '') as instrucao, m.k as casou_por
      from cn
      left join m on m.email = cn.email
      left join public.thb_turmas tu on tu.id = m.turma_id
  )
  select 'turma'::text, case when pf.casou_por is null then 'Não é aluno'
                             else coalesce(pf.turma, 'Aluno sem turma') end, count(*)::int
    from pf group by 2
  union all
  select 'instrucao', case when pf.casou_por is null then 'Não é aluno'
                           else coalesce(pf.instrucao, 'Aluno sem instrução') end, count(*)::int
    from pf group by 2
  union all
  select 'casamento', coalesce(pf.casou_por, 'nao_casou'), count(*)::int
    from pf group by 2
  order by 1, 3 desc, 2;
end
$function$;

-- dados_presencial_disparos(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_disparos(p_chave text)
 RETURNS TABLE(disparo_id bigint, dia date, nome text, canal text, ferramenta text, tamanho_lista integer, entregues integer, lidas integer, cliques integer, falhas integer, custo_centavos bigint, entrega_pct numeric, leitura_pct numeric, clique_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  select x.id, (x.enviado_em at time zone 'America/Sao_Paulo')::date, x.campanha, x.canal, f.nome,
         x.tamanho_lista, x.entregues, x.lidas, x.cliques, x.falhas, x.custo_centavos::bigint,
         case when x.tamanho_lista > 0 then round(x.entregues::numeric * 100 / x.tamanho_lista, 2)::numeric(7,2) end,
         case when x.entregues > 0 then round(x.lidas::numeric * 100 / x.entregues, 2)::numeric(7,2) end,
         case when x.entregues > 0 then round(x.cliques::numeric * 100 / x.entregues, 2)::numeric(7,2) end
    from mkt_mensageria.disparos x
    left join mkt_mensageria.ferramentas f on f.id = x.ferramenta_id
   where x.projeto_id = d.projeto_id and x.arquivado_em is null
   order by x.enviado_em desc, x.id desc;
end
$function$;

-- dados_presencial_leads(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_leads(p_chave text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, instrucao text, turma text, comprou boolean, pessoa_id uuid, teste boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  -- 20261007te: quem é teste continua na lista (teste = true) e não conta nos números
  return query
  with pagos as (select distinct t.email from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago)
  select pc.email, pc.nome, pc.telefone, pc.primeiro_em, pc.fonte, pc.utm_source, pc.utm_medium, pc.utm_campaign,
         pc.utm_content, pc.utm_term, pf.instrucao, pf.turma,
         exists (select 1 from pagos g where g.email = pc.email),
         pc.pessoa_id, pc.teste
    from dados.pre_checkout_todos(d.chave, d.projeto_id, d.lista_ac) pc
    left join lateral dados.perfil(pc.email) pf on true
   order by pc.primeiro_em desc;
end
$function$;

-- dados_presencial_marcar_teste(text,uuid,boolean)
CREATE OR REPLACE FUNCTION public.dados_presencial_marcar_teste(p_chave text, p_pessoa_id uuid, p_teste boolean)
 RETURNS TABLE(pessoa_id uuid, teste boolean, alterado boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_autor uuid := acesso.eu();
  d dados.dashboards;
  v_antes boolean;
  v_pessoa uuid;
begin
  if v_autor is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if p_pessoa_id is null or p_teste is null then
    raise exception 'pessoa e teste são obrigatórios' using errcode = '22023';
  end if;
  select * into d from dados.dashboards x where x.chave = p_chave and x.ativo
     and x.modelo = 'presencial-base';   -- 20261013120000: só o modelo presencial-base
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  v_pessoa := pessoas.atual(p_pessoa_id);   -- marca e loga na pessoa final, se foi mesclada
  -- a pessoa tem de ser um pré-checkout deste dashboard (mesmas duas fontes e filtros de dados.pre_checkout_todos)
  if not exists (select 1 from pessoas.eventos e
                  where e.tipo = 'pre_checkout'
                    and (e.projeto_id = d.projeto_id or e.detalhe ->> 'chave_evento' = d.chave)
                    and pessoas.atual(e.pessoa_id) = v_pessoa)
     and not exists (select 1 from crm.evento_jornada j
                      where d.lista_ac is not null and j.lista = d.lista_ac
                        and j.email_norm is not null and nullif(btrim(j.email_norm), '') is not null
                        and lower(btrim(j.email_norm)) not like '%@exemplo.invalid'
                        and pessoas.atual(j.pessoa_id) = v_pessoa) then
    raise exception 'pessoa não é pré-checkout deste dashboard' using errcode = 'P0002';
  end if;

  select p.teste into v_antes from pessoas.pessoas p where p.id = v_pessoa for update;
  if not found then
    raise exception 'pessoa não encontrada' using errcode = 'P0002';
  end if;
  if coalesce(v_antes, false) = p_teste then
    return query select v_pessoa, p_teste, false;
    return;
  end if;

  update pessoas.pessoas p set teste = p_teste, atualizado_em = now() where p.id = v_pessoa;
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values (v_autor, 'pessoas.pessoas', case when p_teste then 'marcar_teste' else 'desmarcar_teste' end, null,
          jsonb_build_object('pessoa_id', v_pessoa, 'teste', coalesce(v_antes, false)),
          jsonb_build_object('pessoa_id', v_pessoa, 'pessoa_id_recebido', p_pessoa_id, 'teste', p_teste, 'dashboard', d.chave, 'via', 'dados_presencial_marcar_teste'));
  return query select v_pessoa, p_teste, true;
end
$function$;

-- dados_presencial_pagamentos(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_pagamentos(p_chave text)
 RETURNS TABLE(forma text, forma_nome text, parcelas integer, vendas integer, receita_bruta numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  select coalesce(x.forma, 'NAO_INFORMADO'),
         case coalesce(x.forma, 'NAO_INFORMADO')
           when 'CREDIT_CARD' then 'Cartão de crédito'
           when 'PIX' then 'Pix'
           when 'BILLET' then 'Boleto'
           when 'HOTMART_INSTALLMENTS' then 'Parcelado Hotmart'
           when 'FINANCED_BILLET' then 'Boleto financiado'
           when 'HYBRID' then 'Híbrido'
           when 'WALLET' then 'Saldo Hotmart'
           when 'APPLE_PAY' then 'Apple Pay'
           when 'GOOGLE_PAY' then 'Google Pay'
           when 'SAMSUNG_PAY' then 'Samsung Pay'
           when 'PAYPAL' then 'PayPal'
           when 'DIRECT_DEBIT' then 'Débito em conta'
           when 'CASH_PAYMENT' then 'Pagamento em dinheiro'
           when 'NAO_INFORMADO' then 'Não informado'
           else x.forma end,
         coalesce(x.parcelas, 1),
         (count(*) filter (where t.primeira))::int,
         coalesce(sum(t.valor_bruto) filter (where t.moeda = 'BRL'), 0)::numeric(14,2)
    from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
    left join dados.transacoes_extra(d.conta_hotmart, d.oferta_codigo) x on x.transacao = t.transacao
   where t.pago
   group by 1, 2, 3
   order by 4 desc, 1, 3;
end
$function$;

-- dados_presencial_pendencias(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_pendencias(p_chave text)
 RETURNS TABLE(grupo text, categoria text, pessoas integer, transacoes integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  with p as (select * from dados.pendencias(d.conta_hotmart, d.oferta_codigo)),
       g as (select x.grupo from (values ('nao_pago'), ('cancelada')) x(grupo))
  select g.grupo, 'total'::text, (select count(distinct p.email)::int from p where p.grupo = g.grupo),
         (select count(*)::int from p where p.grupo = g.grupo)
    from g
  union all
  select p.grupo, p.categoria, count(distinct p.email)::int, count(*)::int
    from p group by p.grupo, p.categoria
  order by 1 desc, 2;
end
$function$;

-- dados_presencial_pendencias_pessoas(text,text)
CREATE OR REPLACE FUNCTION public.dados_presencial_pendencias_pessoas(p_chave text, p_grupo text)
 RETURNS TABLE(email text, nome text, telefone text, categorias text, transacoes integer, valor_bruto numeric, ultimo_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  if p_grupo is null or p_grupo not in ('nao_pago', 'cancelada') then
    raise exception 'grupo inválido' using errcode = '22023';
  end if;
  return query
  select p.email,
         (array_agg(p.nome order by p.quando desc) filter (where p.nome is not null))[1],
         (array_agg(p.telefone order by p.quando desc) filter (where p.telefone is not null))[1],
         string_agg(distinct p.categoria, ', ' order by p.categoria),
         count(*)::int,
         (array_agg(p.valor_bruto order by p.quando desc))[1],
         max(p.quando)
    from dados.pendencias(d.conta_hotmart, d.oferta_codigo) p
   where p.grupo = p_grupo
   group by p.email
   order by max(p.quando) desc nulls last, p.email;
end
$function$;

-- dados_presencial_resumo(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_resumo(p_chave text)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, evento_inicio date, evento_fim date, oferta_codigo text, disparos_qtd integer, disparos_sem_custo integer, custo_disparo_centavos bigint, custo_completo boolean, pre_checkout_pessoas integer, custo_por_pre_checkout_centavos bigint, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pct numeric, receita_bruta numeric, receita_liquida numeric, cac_centavos bigint, atualizado_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
  ), pc as (
    select y.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
  ), tx as (
    select t.* from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago
  ), ag as (
    select (select count(*)::int from pc) as pessoas,
           (select count(*)::int from tx where tx.primeira) as vendas,
           (select count(*)::int from tx where tx.primeira and tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  )
  select d.chave, pr.id, pr.sigla, pr.nome, pr.evento_inicio, pr.evento_fim, d.oferta_codigo,
         disp.qtd, disp.sem, disp.custo, (disp.qtd > 0 and disp.sem = 0), ag.pessoas,
         case when disp.qtd > 0 and disp.sem = 0 and ag.pessoas > 0 then round(disp.custo::numeric / ag.pessoas)::bigint end,
         ag.vendas, ag.fora, ag.comp, ag.comp_pc,
         case when ag.pessoas > 0 then round(ag.comp::numeric * 100 / ag.pessoas, 2)::numeric(7,2) end,
         ag.bruta, ag.liq,
         case when disp.qtd > 0 and disp.sem = 0 and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         now()
    from mkt.projetos pr cross join disp cross join ag
   where pr.id = d.projeto_id;
end
$function$;

-- dados_presencial_serie_diaria(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_serie_diaria(p_chave text)
 RETURNS TABLE(dia date, pre_checkout integer, pedidos integer, vendas integer, abandonos integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with pc as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
                from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x),
       tx as (select * from dados.transacoes(d.conta_hotmart, d.oferta_codigo)),
       ped as (select t.dia_pedido as dia, count(distinct t.email)::int as n from tx t group by 1),
       ven as (select t.dia_aprovado as dia, count(*)::int as n from tx t where t.pago and t.primeira group by 1),
       ini as (select least((select min(pc.dia) from pc), (select min(t.dia_pedido) from tx t),
                            (select min(t.dia_aprovado) from tx t where t.pago)) as d0)
  select g.dia::date,
         (select count(*)::int from pc where pc.dia = g.dia),
         coalesce((select ped.n from ped where ped.dia = g.dia), 0),
         coalesce((select ven.n from ven where ven.dia = g.dia), 0),
         null::integer
    from ini cross join lateral generate_series(ini.d0, greatest(ini.d0, v_hoje), interval '1 day') g(dia)
   where ini.d0 is not null
   order by 1;
end
$function$;

-- dados_presencial_serie_vendas(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_serie_vendas(p_chave text)
 RETURNS TABLE(dia date, pre_checkout integer, vendas integer, receita_bruta numeric, vendas_acumuladas integer, receita_acumulada numeric, conversao_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with pc as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
                from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x),
       tx as (select * from dados.transacoes(d.conta_hotmart, d.oferta_codigo)),
       ini as (select least((select min(pc.dia) from pc), (select min(t.dia_pedido) from tx t),
                            (select min(t.dia_aprovado) from tx t where t.pago)) as d0),
       base as (
         select g.dia::date as dia,
                (select count(*)::int from pc where pc.dia = g.dia) as pc,
                (select count(*)::int from tx t where t.pago and t.primeira and t.dia_aprovado = g.dia) as ven,
                (select coalesce(sum(t.valor_bruto), 0) from tx t
                  where t.pago and t.moeda = 'BRL' and t.dia_aprovado = g.dia)::numeric(14,2) as rec
           from ini cross join lateral generate_series(ini.d0, greatest(ini.d0, v_hoje), interval '1 day') g(dia)
          where ini.d0 is not null
       )
  select b.dia, b.pc, b.ven, b.rec,
         (sum(b.ven) over (order by b.dia))::int,
         (sum(b.rec) over (order by b.dia))::numeric(14,2),
         case when b.pc > 0 then round(b.ven::numeric * 100 / b.pc, 2)::numeric(7,2) end
    from base b
   order by b.dia;
end
$function$;

-- dados_presencial_vendas(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_vendas(p_chave text)
 RETURNS TABLE(transacao text, status_grupo text, status_hotmart text, dia_pedido date, dia_aprovado date, moeda text, valor_bruto numeric, valor_liquido numeric, email text, nome text, telefone text, estado text, instrucao text, turma text, no_pre_checkout boolean, entrou_grupo boolean, grupo_fonte text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  with pc as (select x.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x)
  select t.transacao, t.status_grupo, t.status, t.dia_pedido, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido,
         t.email, t.nome, t.telefone, t.estado, pf.instrucao, pf.turma,
         exists (select 1 from pc where pc.email = t.email),
         null::boolean, 'sem_fonte'::text
    from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
    left join lateral dados.perfil(t.email) pf on true
   order by coalesce(t.dia_aprovado, t.dia_pedido) desc, t.transacao;
end
$function$;

-- dados_presencial_vendas_por_hora(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_vendas_por_hora(p_chave text)
 RETURNS TABLE(hora integer, vendas integer, receita_bruta numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- 20261013120000: só o modelo presencial-base
begin
  return query
  with tx as (select extract(hour from (t.aprovado_em at time zone 'America/Sao_Paulo'))::int as h, t.primeira,
                     t.moeda, t.valor_bruto
                from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
               where t.pago and t.aprovado_em is not null)
  select g.h,
         (select count(*)::int from tx where tx.h = g.h and tx.primeira),
         (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.h = g.h and tx.moeda = 'BRL')::numeric(14,2)
    from generate_series(0, 23) g(h)
   order by 1;
end
$function$;

do $c$
declare
  r record;
  n int := 0;
begin
  for r in select p.oid::regprocedure::text sig, p.prosrc from pg_proc p join pg_namespace s on s.oid = p.pronamespace
            where s.nspname = 'public' and (p.proname like 'dados_presencial%' or p.proname like 'dados_miami%') loop
    n := n + 1;
    if r.sig = 'dados_presencial_marcar_teste(text,uuid,boolean)' then
      if r.prosrc not like '%x.modelo = ''presencial-base''%' then
        raise exception '20261012233334: % sem trava', r.sig;
      end if;
    elsif r.prosrc not like '%dados.presencial_cadastro(p_chave)%' or r.prosrc like '%dados.cadastro(%' then
      raise exception '20261012233334: % sem trava', r.sig;
    end if;
    if has_function_privilege('anon', r.sig, 'execute') or not has_function_privilege('authenticated', r.sig, 'execute') then
      raise exception '20261012233334: permissões de % mudaram', r.sig;
    end if;
  end loop;
  if n <> 14 then
    raise exception '20261012233334: esperava 14 RPCs, achei %', n;
  end if;
  if has_function_privilege('authenticated', 'dados.presencial_cadastro(text)', 'execute')
     or has_function_privilege('anon', 'dados.presencial_cadastro(text)', 'execute') then
    raise exception '20261012233334: presencial_cadastro com grant';
  end if;
end
$c$;

-- ===== TESTES =====
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', '00000000-0000-4000-8000-0000000000ff', true)$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('black-friday-2026-10', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('black-friday-2026-10', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'black', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('black-friday-2026-10', '00000000-0000-4000-8000-0000000000ff', true)$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('nao-existe', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('nao-existe', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'inexistente', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('nao-existe', '00000000-0000-4000-8000-0000000000ff', true)$s$));
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica-fora-da-equipe', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica-fora-da-equipe', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', '00000000-0000-4000-8000-0000000000ff', true)$s$));
select set_config('request.jwt.claims', '{}', true);
set local role anon;
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('2 depois', 'clinica-anon', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
reset role;
insert into pg_temp._z_out (fase, chave, rpc, linha) select '2 depois', '-', 'corpos', md5(string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and (p.proname like 'dados_presencial%' or p.proname like 'dados_miami%');

-- ===== REVERSÃO =====
-- Reversão de 20261012233334. Numa transação. Volta os 14 corpos de antes (vivos em 13/10/2026) e apaga dados.presencial_cadastro.
-- ATENÇÃO: sem a trava, as RPCs presenciais voltam a aceitar a chave da Black. Não reverter com a B da Black no ar
-- sem antes decidir com o pentester.

-- dados_miami_diamantes(text)
CREATE OR REPLACE FUNCTION public.dados_miami_diamantes(p_chave text)
 RETURNS TABLE(lista_ordem integer, lista_nome text, status text, casamento text, resposta_uuid uuid, respondido_em timestamp with time zone, n_respostas integer, nome_formulario text, email text, telefone text, grupo text, situacao text, situacao_codigo text, chegada text, chegada_data date, retorno text, retorno_data date, aeroporto text, hospedagem text, acompanhado text, acompanhantes text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_slug text := (select f.form_slug from dados.dashboard_formularios f where f.chave = d.chave and f.papel = 'diamantes');
begin
  return query
  with r as (
    select x.uuid, x.respondido_em, x.email, x.telefone, x.respostas,
           coalesce(nullif(x.email, ''), nullif(right(x.telefone, 8), ''), x.uuid::text) as pessoa
      from respondi.respostas x
     where v_slug is not null and x.form_slug = v_slug
  ),
  p as (  -- uma linha por pessoa: a resposta mais recente
    select distinct on (r.pessoa) r.*, count(*) over (partition by r.pessoa)::int as n,
           dados.respondi_valor(r.respostas, 'Nome completo') as nome_f
      from r
     order by r.pessoa, r.respondido_em desc, r.uuid
  ),
  l as (
    select lp.ordem, lp.nome, lp.resposta_uuid_manual, dados.nome_tokens(lp.nome) as tk
      from dados.dashboard_lista_pessoas lp
     where lp.chave = d.chave and lp.lista = 'diamantes'
  ),
  par as (  -- cada nome da lista com a sua resposta (manual vence; senão a mais recente que casa pelo nome)
    select l.ordem, l.nome, m.uuid, m.casamento
      from l
      left join lateral (
        select p.uuid, case when p.uuid = l.resposta_uuid_manual then 'manual' else 'nome' end as casamento
          from p
         where p.uuid = l.resposta_uuid_manual
            or (l.resposta_uuid_manual is null and dados.nome_casa(l.tk, dados.nome_tokens(p.nome_f)))
         order by (p.uuid = l.resposta_uuid_manual) desc, p.respondido_em desc
         limit 1) m on true
  ),
  linhas as (
    select par.ordem, par.nome, case when par.uuid is null then 'pendente' else 'respondeu' end as st, par.casamento, par.uuid
      from par
    union all
    select null, null, 'fora_da_lista', null, p.uuid
      from p
     where not exists (select 1 from par where par.uuid = p.uuid)
  )
  select li.ordem, li.nome, li.st, li.casamento, p.uuid, p.respondido_em, p.n, p.nome_f, p.email, p.telefone,
         dados.respondi_valor(p.respostas, 'Qual é o seu grupo'),
         v.sit,
         case when v.sit like 'Já estou confirmado%' then 'confirmado'
              when v.sit like 'Estou me organizando%' then 'organizando'
              when v.sit like 'Já sei que não%' then 'nao_vai' end,
         v.cheg, dados.data_br(v.cheg), v.ret, dados.data_br(v.ret),
         dados.respondi_valor(p.respostas, 'Em qual aeroporto você chegará'),
         dados.respondi_valor(p.respostas, 'Onde você ficará hospedado'),
         dados.respondi_valor(p.respostas, 'Você estará acompanhado'),
         dados.respondi_valor(p.respostas, 'Quantas pessoas irão com você')
    from linhas li
    left join p on p.uuid = li.uuid
    left join lateral (select dados.respondi_valor(p.respostas, 'Acerca dos eventos internacionais') as sit,
                              dados.respondi_valor(p.respostas, 'Qual a sua data de chegada') as cheg,
                              dados.respondi_valor(p.respostas, 'Qual a sua data de retorno') as ret) v on true
   order by li.ordem nulls last, p.respondido_em, p.uuid;
end
$function$;

-- dados_miami_interesse(text)
CREATE OR REPLACE FUNCTION public.dados_miami_interesse(p_chave text)
 RETURNS TABLE(resposta_uuid uuid, respondido_em timestamp with time zone, n_respostas integer, nome text, email text, telefone text, turma text, passaporte text, visto text, planos text, comprou_passagem text, data_passagem text, confirma_pre_venda text, deseja_programa text, comprou boolean, compra_status text, compra_transacao text, compra_em timestamp with time zone, casou_por text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_slug text := (select f.form_slug from dados.dashboard_formularios f where f.chave = d.chave and f.papel = 'interesse');
begin
  return query
  with r as (
    select x.uuid, x.respondido_em, x.email, x.telefone, x.respostas,
           coalesce(nullif(x.email, ''), nullif(right(x.telefone, 8), ''), x.uuid::text) as pessoa
      from respondi.respostas x
     where v_slug is not null and x.form_slug = v_slug
  ),
  p as (
    select distinct on (r.pessoa) r.*, count(*) over (partition by r.pessoa)::int as n
      from r
     order by r.pessoa, r.respondido_em desc, r.uuid
  ),
  t as (
    select tr.transacao, tr.status_grupo, coalesce(tr.aprovado_em, tr.pedido_em) as em,
           lower(btrim(tr.email)) as email, right(regexp_replace(coalesce(tr.telefone, ''), '\D', '', 'g'), 8) as fone8,
           case tr.status_grupo when 'pago' then 1 when 'em_aberto' then 2 when 'atrasado' then 3 when 'estornado' then 4
                                when 'recusado' then 5 when 'expirado' then 6 else 7 end as prio
      from dados.transacoes(d.conta_hotmart, d.oferta_codigo) tr
     where v_slug is not null
  )
  select p.uuid, p.respondido_em, p.n,
         dados.respondi_valor(p.respostas, 'Qual é o seu nome completo'), p.email, p.telefone,
         dados.respondi_valor(p.respostas, 'Qual é a sua turma'),
         dados.respondi_valor(p.respostas, 'Você tem passaporte válido'),
         dados.respondi_valor(p.respostas, 'Você tem visto americano válido'),
         dados.respondi_valor(p.respostas, 'Quais são os seus planos para a viagem'),
         dados.respondi_valor(p.respostas, 'Você já comprou a sua passagem'),
         dados.respondi_valor(p.respostas, 'Qual é a data da sua passagem'),
         dados.respondi_valor(p.respostas, 'Você confirma que fará a inscrição na pré-venda'),
         dados.respondi_valor(p.respostas, 'Você deseja participar do programa Holding Trip Miami'),
         coalesce(c.status_grupo = 'pago', false), c.status_grupo, c.transacao, c.em, c.por
    from p
    left join lateral (
      select t.transacao, t.status_grupo, t.em,
             case when t.email = nullif(lower(btrim(p.email)), '') then 'email' else 'telefone' end as por
        from t
       where t.email = nullif(lower(btrim(p.email)), '')
          or (length(t.fone8) = 8 and length(coalesce(p.telefone, '')) >= 10 and t.fone8 = right(p.telefone, 8))
       order by t.prio, (t.email = nullif(lower(btrim(p.email)), '')) desc, t.em desc nulls last, t.transacao
       limit 1) c on true
   order by coalesce(c.status_grupo = 'pago', false), p.respondido_em desc, p.uuid;
end
$function$;

-- dados_presencial_compradores_perfil(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_compradores_perfil(p_chave text)
 RETURNS TABLE(dimensao text, valor text, compradores integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with tx as (
    select t.email, x.documento, t.telefone
      from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
      left join dados.transacoes_extra(d.conta_hotmart, d.oferta_codigo) x on x.transacao = t.transacao
     where t.pago and t.email is not null
  ), comp as (
    select tx.email, max(tx.documento) as documento, max(tx.telefone) as telefone from tx group by tx.email
  ), al as materialized (
    select al0.turma_id, al0.instrucao, al0.cancelado_em, al0.eh_socio, al0.atualizado_em,
           nullif(lower(btrim(al0.email)), '') as em,
           nullif(regexp_replace(coalesce(al0.documento, ''), '\D', '', 'g'), '') as doc,
           case when length(regexp_replace(coalesce(al0.telefone_e164, al0.telefone, ''), '\D', '', 'g')) >= 11
                then right(regexp_replace(coalesce(al0.telefone_e164, al0.telefone, ''), '\D', '', 'g'), 11) end as tel11
      from public.thb_alunos al0
  ), cn as (
    select c.email,
           nullif(regexp_replace(coalesce(c.documento, ''), '\D', '', 'g'), '') as doc,
           case when length(regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g')) >= 11
                then right(regexp_replace(coalesce(c.telefone, ''), '\D', '', 'g'), 11) end as tel11
      from comp c
  ), cand as (
    select cn.email, al.*, 1 as prio, 'email'::text as k from cn join al on al.em = cn.email
    union all
    select cn.email, al.*, 2, 'documento' from cn join al on al.doc = cn.doc where length(cn.doc) >= 11
    union all
    select cn.email, al.*, 3, 'telefone' from cn join al on al.tel11 = cn.tel11
  ), m as (
    select distinct on (cand.email) cand.email, cand.turma_id, cand.instrucao, cand.k
      from cand
     order by cand.email, cand.prio, (cand.cancelado_em is null) desc, coalesce(cand.eh_socio, false),
              cand.atualizado_em desc nulls last
  ), pf as (
    select cn.email, tu.codigo as turma, nullif(btrim(m.instrucao), '') as instrucao, m.k as casou_por
      from cn
      left join m on m.email = cn.email
      left join public.thb_turmas tu on tu.id = m.turma_id
  )
  select 'turma'::text, case when pf.casou_por is null then 'Não é aluno'
                             else coalesce(pf.turma, 'Aluno sem turma') end, count(*)::int
    from pf group by 2
  union all
  select 'instrucao', case when pf.casou_por is null then 'Não é aluno'
                           else coalesce(pf.instrucao, 'Aluno sem instrução') end, count(*)::int
    from pf group by 2
  union all
  select 'casamento', coalesce(pf.casou_por, 'nao_casou'), count(*)::int
    from pf group by 2
  order by 1, 3 desc, 2;
end
$function$;

-- dados_presencial_disparos(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_disparos(p_chave text)
 RETURNS TABLE(disparo_id bigint, dia date, nome text, canal text, ferramenta text, tamanho_lista integer, entregues integer, lidas integer, cliques integer, falhas integer, custo_centavos bigint, entrega_pct numeric, leitura_pct numeric, clique_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  select x.id, (x.enviado_em at time zone 'America/Sao_Paulo')::date, x.campanha, x.canal, f.nome,
         x.tamanho_lista, x.entregues, x.lidas, x.cliques, x.falhas, x.custo_centavos::bigint,
         case when x.tamanho_lista > 0 then round(x.entregues::numeric * 100 / x.tamanho_lista, 2)::numeric(7,2) end,
         case when x.entregues > 0 then round(x.lidas::numeric * 100 / x.entregues, 2)::numeric(7,2) end,
         case when x.entregues > 0 then round(x.cliques::numeric * 100 / x.entregues, 2)::numeric(7,2) end
    from mkt_mensageria.disparos x
    left join mkt_mensageria.ferramentas f on f.id = x.ferramenta_id
   where x.projeto_id = d.projeto_id and x.arquivado_em is null
   order by x.enviado_em desc, x.id desc;
end
$function$;

-- dados_presencial_leads(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_leads(p_chave text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, instrucao text, turma text, comprou boolean, pessoa_id uuid, teste boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  -- 20261007te: quem é teste continua na lista (teste = true) e não conta nos números
  return query
  with pagos as (select distinct t.email from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago)
  select pc.email, pc.nome, pc.telefone, pc.primeiro_em, pc.fonte, pc.utm_source, pc.utm_medium, pc.utm_campaign,
         pc.utm_content, pc.utm_term, pf.instrucao, pf.turma,
         exists (select 1 from pagos g where g.email = pc.email),
         pc.pessoa_id, pc.teste
    from dados.pre_checkout_todos(d.chave, d.projeto_id, d.lista_ac) pc
    left join lateral dados.perfil(pc.email) pf on true
   order by pc.primeiro_em desc;
end
$function$;

-- dados_presencial_marcar_teste(text,uuid,boolean)
CREATE OR REPLACE FUNCTION public.dados_presencial_marcar_teste(p_chave text, p_pessoa_id uuid, p_teste boolean)
 RETURNS TABLE(pessoa_id uuid, teste boolean, alterado boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_autor uuid := acesso.eu();
  d dados.dashboards;
  v_antes boolean;
  v_pessoa uuid;
begin
  if v_autor is null or not coalesce(acesso.eh_master(), false) then
    raise exception 'sem acesso' using errcode = '42501';
  end if;
  if p_pessoa_id is null or p_teste is null then
    raise exception 'pessoa e teste são obrigatórios' using errcode = '22023';
  end if;
  select * into d from dados.dashboards x where x.chave = p_chave and x.ativo;
  if not found then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  v_pessoa := pessoas.atual(p_pessoa_id);   -- marca e loga na pessoa final, se foi mesclada
  -- a pessoa tem de ser um pré-checkout deste dashboard (mesmas duas fontes e filtros de dados.pre_checkout_todos)
  if not exists (select 1 from pessoas.eventos e
                  where e.tipo = 'pre_checkout'
                    and (e.projeto_id = d.projeto_id or e.detalhe ->> 'chave_evento' = d.chave)
                    and pessoas.atual(e.pessoa_id) = v_pessoa)
     and not exists (select 1 from crm.evento_jornada j
                      where d.lista_ac is not null and j.lista = d.lista_ac
                        and j.email_norm is not null and nullif(btrim(j.email_norm), '') is not null
                        and lower(btrim(j.email_norm)) not like '%@exemplo.invalid'
                        and pessoas.atual(j.pessoa_id) = v_pessoa) then
    raise exception 'pessoa não é pré-checkout deste dashboard' using errcode = 'P0002';
  end if;

  select p.teste into v_antes from pessoas.pessoas p where p.id = v_pessoa for update;
  if not found then
    raise exception 'pessoa não encontrada' using errcode = 'P0002';
  end if;
  if coalesce(v_antes, false) = p_teste then
    return query select v_pessoa, p_teste, false;
    return;
  end if;

  update pessoas.pessoas p set teste = p_teste, atualizado_em = now() where p.id = v_pessoa;
  insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
  values (v_autor, 'pessoas.pessoas', case when p_teste then 'marcar_teste' else 'desmarcar_teste' end, null,
          jsonb_build_object('pessoa_id', v_pessoa, 'teste', coalesce(v_antes, false)),
          jsonb_build_object('pessoa_id', v_pessoa, 'pessoa_id_recebido', p_pessoa_id, 'teste', p_teste, 'dashboard', d.chave, 'via', 'dados_presencial_marcar_teste'));
  return query select v_pessoa, p_teste, true;
end
$function$;

-- dados_presencial_pagamentos(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_pagamentos(p_chave text)
 RETURNS TABLE(forma text, forma_nome text, parcelas integer, vendas integer, receita_bruta numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  select coalesce(x.forma, 'NAO_INFORMADO'),
         case coalesce(x.forma, 'NAO_INFORMADO')
           when 'CREDIT_CARD' then 'Cartão de crédito'
           when 'PIX' then 'Pix'
           when 'BILLET' then 'Boleto'
           when 'HOTMART_INSTALLMENTS' then 'Parcelado Hotmart'
           when 'FINANCED_BILLET' then 'Boleto financiado'
           when 'HYBRID' then 'Híbrido'
           when 'WALLET' then 'Saldo Hotmart'
           when 'APPLE_PAY' then 'Apple Pay'
           when 'GOOGLE_PAY' then 'Google Pay'
           when 'SAMSUNG_PAY' then 'Samsung Pay'
           when 'PAYPAL' then 'PayPal'
           when 'DIRECT_DEBIT' then 'Débito em conta'
           when 'CASH_PAYMENT' then 'Pagamento em dinheiro'
           when 'NAO_INFORMADO' then 'Não informado'
           else x.forma end,
         coalesce(x.parcelas, 1),
         (count(*) filter (where t.primeira))::int,
         coalesce(sum(t.valor_bruto) filter (where t.moeda = 'BRL'), 0)::numeric(14,2)
    from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
    left join dados.transacoes_extra(d.conta_hotmart, d.oferta_codigo) x on x.transacao = t.transacao
   where t.pago
   group by 1, 2, 3
   order by 4 desc, 1, 3;
end
$function$;

-- dados_presencial_pendencias(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_pendencias(p_chave text)
 RETURNS TABLE(grupo text, categoria text, pessoas integer, transacoes integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with p as (select * from dados.pendencias(d.conta_hotmart, d.oferta_codigo)),
       g as (select x.grupo from (values ('nao_pago'), ('cancelada')) x(grupo))
  select g.grupo, 'total'::text, (select count(distinct p.email)::int from p where p.grupo = g.grupo),
         (select count(*)::int from p where p.grupo = g.grupo)
    from g
  union all
  select p.grupo, p.categoria, count(distinct p.email)::int, count(*)::int
    from p group by p.grupo, p.categoria
  order by 1 desc, 2;
end
$function$;

-- dados_presencial_pendencias_pessoas(text,text)
CREATE OR REPLACE FUNCTION public.dados_presencial_pendencias_pessoas(p_chave text, p_grupo text)
 RETURNS TABLE(email text, nome text, telefone text, categorias text, transacoes integer, valor_bruto numeric, ultimo_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  if p_grupo is null or p_grupo not in ('nao_pago', 'cancelada') then
    raise exception 'grupo inválido' using errcode = '22023';
  end if;
  return query
  select p.email,
         (array_agg(p.nome order by p.quando desc) filter (where p.nome is not null))[1],
         (array_agg(p.telefone order by p.quando desc) filter (where p.telefone is not null))[1],
         string_agg(distinct p.categoria, ', ' order by p.categoria),
         count(*)::int,
         (array_agg(p.valor_bruto order by p.quando desc))[1],
         max(p.quando)
    from dados.pendencias(d.conta_hotmart, d.oferta_codigo) p
   where p.grupo = p_grupo
   group by p.email
   order by max(p.quando) desc nulls last, p.email;
end
$function$;

-- dados_presencial_resumo(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_resumo(p_chave text)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, evento_inicio date, evento_fim date, oferta_codigo text, disparos_qtd integer, disparos_sem_custo integer, custo_disparo_centavos bigint, custo_completo boolean, pre_checkout_pessoas integer, custo_por_pre_checkout_centavos bigint, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pct numeric, receita_bruta numeric, receita_liquida numeric, cac_centavos bigint, atualizado_em timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with disp as (
    select count(*)::int as qtd, count(*) filter (where x.custo_centavos is null)::int as sem,
           sum(x.custo_centavos)::bigint as custo
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
  ), pc as (
    select y.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
  ), tx as (
    select t.* from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t where t.pago
  ), ag as (
    select (select count(*)::int from pc) as pessoas,
           (select count(*)::int from tx where tx.primeira) as vendas,
           (select count(*)::int from tx where tx.primeira and tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  )
  select d.chave, pr.id, pr.sigla, pr.nome, pr.evento_inicio, pr.evento_fim, d.oferta_codigo,
         disp.qtd, disp.sem, disp.custo, (disp.qtd > 0 and disp.sem = 0), ag.pessoas,
         case when disp.qtd > 0 and disp.sem = 0 and ag.pessoas > 0 then round(disp.custo::numeric / ag.pessoas)::bigint end,
         ag.vendas, ag.fora, ag.comp, ag.comp_pc,
         case when ag.pessoas > 0 then round(ag.comp::numeric * 100 / ag.pessoas, 2)::numeric(7,2) end,
         ag.bruta, ag.liq,
         case when disp.qtd > 0 and disp.sem = 0 and ag.vendas > 0 then round(disp.custo::numeric / ag.vendas)::bigint end,
         now()
    from mkt.projetos pr cross join disp cross join ag
   where pr.id = d.projeto_id;
end
$function$;

-- dados_presencial_serie_diaria(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_serie_diaria(p_chave text)
 RETURNS TABLE(dia date, pre_checkout integer, pedidos integer, vendas integer, abandonos integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with pc as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
                from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x),
       tx as (select * from dados.transacoes(d.conta_hotmart, d.oferta_codigo)),
       ped as (select t.dia_pedido as dia, count(distinct t.email)::int as n from tx t group by 1),
       ven as (select t.dia_aprovado as dia, count(*)::int as n from tx t where t.pago and t.primeira group by 1),
       ini as (select least((select min(pc.dia) from pc), (select min(t.dia_pedido) from tx t),
                            (select min(t.dia_aprovado) from tx t where t.pago)) as d0)
  select g.dia::date,
         (select count(*)::int from pc where pc.dia = g.dia),
         coalesce((select ped.n from ped where ped.dia = g.dia), 0),
         coalesce((select ven.n from ven where ven.dia = g.dia), 0),
         null::integer
    from ini cross join lateral generate_series(ini.d0, greatest(ini.d0, v_hoje), interval '1 day') g(dia)
   where ini.d0 is not null
   order by 1;
end
$function$;

-- dados_presencial_serie_vendas(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_serie_vendas(p_chave text)
 RETURNS TABLE(dia date, pre_checkout integer, vendas integer, receita_bruta numeric, vendas_acumuladas integer, receita_acumulada numeric, conversao_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  return query
  with pc as (select (x.primeiro_em at time zone 'America/Sao_Paulo')::date as dia
                from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x),
       tx as (select * from dados.transacoes(d.conta_hotmart, d.oferta_codigo)),
       ini as (select least((select min(pc.dia) from pc), (select min(t.dia_pedido) from tx t),
                            (select min(t.dia_aprovado) from tx t where t.pago)) as d0),
       base as (
         select g.dia::date as dia,
                (select count(*)::int from pc where pc.dia = g.dia) as pc,
                (select count(*)::int from tx t where t.pago and t.primeira and t.dia_aprovado = g.dia) as ven,
                (select coalesce(sum(t.valor_bruto), 0) from tx t
                  where t.pago and t.moeda = 'BRL' and t.dia_aprovado = g.dia)::numeric(14,2) as rec
           from ini cross join lateral generate_series(ini.d0, greatest(ini.d0, v_hoje), interval '1 day') g(dia)
          where ini.d0 is not null
       )
  select b.dia, b.pc, b.ven, b.rec,
         (sum(b.ven) over (order by b.dia))::int,
         (sum(b.rec) over (order by b.dia))::numeric(14,2),
         case when b.pc > 0 then round(b.ven::numeric * 100 / b.pc, 2)::numeric(7,2) end
    from base b
   order by b.dia;
end
$function$;

-- dados_presencial_vendas(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_vendas(p_chave text)
 RETURNS TABLE(transacao text, status_grupo text, status_hotmart text, dia_pedido date, dia_aprovado date, moeda text, valor_bruto numeric, valor_liquido numeric, email text, nome text, telefone text, estado text, instrucao text, turma text, no_pre_checkout boolean, entrou_grupo boolean, grupo_fonte text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with pc as (select x.email from dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) x)
  select t.transacao, t.status_grupo, t.status, t.dia_pedido, t.dia_aprovado, t.moeda, t.valor_bruto, t.valor_liquido,
         t.email, t.nome, t.telefone, t.estado, pf.instrucao, pf.turma,
         exists (select 1 from pc where pc.email = t.email),
         null::boolean, 'sem_fonte'::text
    from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
    left join lateral dados.perfil(t.email) pf on true
   order by coalesce(t.dia_aprovado, t.dia_pedido) desc, t.transacao;
end
$function$;

-- dados_presencial_vendas_por_hora(text)
CREATE OR REPLACE FUNCTION public.dados_presencial_vendas_por_hora(p_chave text)
 RETURNS TABLE(hora integer, vendas integer, receita_bruta numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.cadastro(p_chave);
begin
  return query
  with tx as (select extract(hour from (t.aprovado_em at time zone 'America/Sao_Paulo'))::int as h, t.primeira,
                     t.moeda, t.valor_bruto
                from dados.transacoes(d.conta_hotmart, d.oferta_codigo) t
               where t.pago and t.aprovado_em is not null)
  select g.h,
         (select count(*)::int from tx where tx.h = g.h and tx.primeira),
         (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.h = g.h and tx.moeda = 'BRL')::numeric(14,2)
    from generate_series(0, 23) g(h)
   order by 1;
end
$function$;

drop function if exists dados.presencial_cadastro(text);
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('clinica-miami-2026-12', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', '00000000-0000-4000-8000-0000000000ff', true)$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('black-friday-2026-10')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('black-friday-2026-10', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('black-friday-2026-10', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'black', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('black-friday-2026-10', '00000000-0000-4000-8000-0000000000ff', true)$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_miami_diamantes', pg_temp._z_foto($s$select * from public.dados_miami_diamantes('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_miami_interesse', pg_temp._z_foto($s$select * from public.dados_miami_interesse('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_compradores_perfil', pg_temp._z_foto($s$select * from public.dados_presencial_compradores_perfil('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_disparos', pg_temp._z_foto($s$select * from public.dados_presencial_disparos('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_pagamentos', pg_temp._z_foto($s$select * from public.dados_presencial_pagamentos('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_pendencias', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_resumo', pg_temp._z_foto($s$select * from public.dados_presencial_resumo('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_serie_diaria', pg_temp._z_foto($s$select * from public.dados_presencial_serie_diaria('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_serie_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_serie_vendas('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_vendas', pg_temp._z_foto($s$select * from public.dados_presencial_vendas('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_vendas_por_hora', pg_temp._z_foto($s$select * from public.dados_presencial_vendas_por_hora('nao-existe')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_pendencias_pessoas:nao_pago', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('nao-existe', 'nao_pago')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_pendencias_pessoas:cancelada', pg_temp._z_foto($s$select * from public.dados_presencial_pendencias_pessoas('nao-existe', 'cancelada')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'inexistente', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('nao-existe', '00000000-0000-4000-8000-0000000000ff', true)$s$));
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica-fora-da-equipe', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica-fora-da-equipe', 'dados_presencial_marcar_teste', pg_temp._z_foto($s$select * from public.dados_presencial_marcar_teste('clinica-miami-2026-12', '00000000-0000-4000-8000-0000000000ff', true)$s$));
select set_config('request.jwt.claims', '{}', true);
set local role anon;
insert into pg_temp._z_out (fase, chave, rpc, linha) values ('3 depois da reversao', 'clinica-anon', 'dados_presencial_leads', pg_temp._z_foto($s$select * from public.dados_presencial_leads('clinica-miami-2026-12')$s$));
reset role;
insert into pg_temp._z_out (fase, chave, rpc, linha) select '3 depois da reversao', '-', 'corpos', md5(string_agg(p.oid::regprocedure::text || md5(p.prosrc) || coalesce(p.proacl::text, ''), '|' order by p.oid::regprocedure::text)) from pg_proc p join pg_namespace s on s.oid = p.pronamespace where s.nspname = 'public' and (p.proname like 'dados_presencial%' or p.proname like 'dados_miami%');

-- resumo: a Clínica tem de ficar idêntica nas três fases; a Black tem de passar a dar P0002 depois da trava e voltar na reversão
select a.chave, a.rpc, a.linha as antes,
       case when b.linha = a.linha then '=' else b.linha end as depois,
       case when c.linha = a.linha then '=' else c.linha end as depois_da_reversao
  from pg_temp._z_out a
  join pg_temp._z_out b on b.chave = a.chave and b.rpc = a.rpc and b.fase = '2 depois'
  join pg_temp._z_out c on c.chave = a.chave and c.rpc = a.rpc and c.fase = '3 depois da reversao'
 where a.fase = '1 antes'
 order by a.chave, a.rpc;
rollback;
