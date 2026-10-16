-- Ensaio de 20261017050200_dados_atm_pertence_renov.sql numa transação DESFEITA (rollback), sobre produção.
-- Roda antes a 20261017050100 (o de-para) dentro da mesma transação. Sem dado pessoal na saída: e-mails fictícios @example.invalid,
-- telefone fictício terminado em 99991357, só contagens.
-- Prova: o e-mail e o telefone de uma aplicação do /renov da chave passam a ser reconhecidos (antes não); origem fora do de-para e outra chave
-- não são; só master marca (jessica e anônimo barrados); marcar de verdade tira a aplicação da contagem de teste ativo (dados.teste_ativo);
-- as marcações reais existentes continuam reconhecidas igual (regressão); a reversão devolve o corpo (md5 7945...).
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
  return 'passou: ' || left(coalesce(v, 'null'), 900);
exception when others then return sqlstate || ' ' || left(sqlerrm, 300);
end $t$;
grant execute on function pg_temp.tenta(uuid, text) to authenticated, anon;
-- registra uma linha como o papel pedido (o papel volta ao que era)
create function pg_temp.foto(p_rotulo text, p_id uuid, p_sql text) returns void language plpgsql as $t$
begin
  insert into pg_temp._z_out(passo, linha) values (p_rotulo, pg_temp.tenta(p_id, p_sql));
end $t$;
grant execute on function pg_temp.foto(text, uuid, text) to authenticated, anon;

set local session_replication_role = replica;
insert into pg_temp._z_out(passo, linha) select '00 md5 do corpo vivo', md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '00 ACL', coalesce(proacl::text, '(nula)') from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure;
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem) values ('Zz Teste', 'zz.renov1@example.invalid', '(21) 99999-1357', 'renovar-holding-masters', 'renov-thb');
insert into metodo.renov_aplicacoes (nome, email, telefone, opcao, origem) values ('Zz Teste', 'zz.renov2@example.invalid', '(21) 99999-1358', 'renovar-holding-masters', 'origem-fora-do-depara');

insert into pg_temp._z_out(passo, linha) select '00 aplicações fictícias', count(*)::text from metodo.renov_aplicacoes where email like 'zz.%@example.invalid';
insert into pg_temp._z_out(passo, linha) select '00 marcações ativas reais por chave', string_agg(chave || ' ' || n, ' | ' order by chave) from (select chave, count(*) n from dados.marcacoes_teste where desmarcado_em is null group by 1) x;
-- ===== M3 (de-para) =====
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050100: falta metodo.origem_etiqueta (20261014200000)';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null then
    raise exception '20261017050100: falta metodo.renov_aplicacoes (20261016163924, Arthur)';
  end if;
  if exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb') then
    raise exception '20261017050100: renov-thb já está no de-para; revisar';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-thb-2026-10' and modelo = 'acao-black') then
    raise exception '20261017050100: black-thb-2026-10 não existe como acao-black';
  end if;
  if exists (select 1 from metodo.pesquisa_respostas where origem = 'renov-thb') then
    raise exception '20261017050100: já existe pesquisa_respostas com origem renov-thb; o gatilho passaria a etiquetar essas linhas. Revisar';
  end if;
end
$g$;

insert into metodo.origem_etiqueta (origem, etiqueta) values ('renov-thb', 'black-thb-2026-10');

insert into pg_temp._z_out(passo, linha) select '10 ANTES e-mail da aplicação, chave certa (esperado antes false, depois true)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '10 ANTES telefone da aplicação, chave certa (esperado antes false, depois true)', dados.atm_pertence('black-thb-2026-10', 'fone', '99991357')::text;
insert into pg_temp._z_out(passo, linha) select '10 ANTES e-mail da aplicação com origem fora do de-para (esperado false)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov2@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '10 ANTES e-mail da aplicação em OUTRA chave (esperado false)', dados.atm_pertence('atm-elaine-1-2026-10', 'email', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '10 ANTES telefone da aplicação em OUTRA chave (esperado false)', dados.atm_pertence('atm-elaine-1-2026-10', 'fone', '99991357')::text;
insert into pg_temp._z_out(passo, linha) select '10 ANTES e-mail sem relação (esperado false)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.nada@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '10 ANTES tipo inválido (esperado false)', dados.atm_pertence('black-thb-2026-10', 'outro', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha)
select '11 regressão ANTES (marcações reais reconhecidas / total)', string_agg(chave || ' ' || tipo || ': ' || ok || '/' || total, ' | ' order by chave, tipo)
  from (select chave, tipo, count(*) total, count(*) filter (where dados.atm_pertence(chave, tipo, valor)) ok
          from dados.marcacoes_teste where desmarcado_em is null and not (valor like 'zz%' or valor = '99991357') group by 1, 2) x;
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select dados.atm_pertence(''black-thb-2026-10'', ''email'', ''zz.renov1@example.invalid'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time)' then
        insert into pg_temp._z_out (passo, linha) values ('12 explain ANTES valor só no renov #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select dados.atm_pertence(''black-thb-2026-10'', ''email'', ''zz.nada@example.invalid'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time)' then
        insert into pg_temp._z_out (passo, linha) values ('13 explain ANTES valor inexistente #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;

-- ===== corpo da migration =====
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('dados.atm_pertence(text,text,text)') is null then
    raise exception '20261017050200: dados.atm_pertence(text,text,text) não existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure) <> '7945be0a410031528e24bd21a4c876ca' then
    raise exception '20261017050200: o corpo vivo de dados.atm_pertence mudou desde a leitura de 16/10/2026; reler e refazer a partir dele';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050200: faltam metodo.renov_aplicacoes (20261016163924, Arthur) ou metodo.origem_etiqueta';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050200: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100); sem ele o ramo novo nunca casa';
  end if;
end
$g$;

create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261008191000; número da foto do grupo em 20261008200000; aplicações do /renov em 20261017050200
  select case p_tipo
    when 'email' then
         exists (select 1 from metodo.renov_aplicacoes a join metodo.origem_etiqueta o on o.origem = a.origem
                  where o.etiqueta = p_chave and lower(btrim(a.email)) = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from metodo.renov_aplicacoes a join metodo.origem_etiqueta o on o.origem = a.origem
                  where o.etiqueta = p_chave and right(controle.fone_key(a.telefone), 8) = p_valor)
      or exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$function$;

-- a ACL não pode ter mudado (create or replace a preserva; conferido aqui)
do $a$
begin
  if has_function_privilege('anon', 'dados.atm_pertence(text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.atm_pertence(text,text,text)', 'execute')
     or has_function_privilege('service_role', 'dados.atm_pertence(text,text,text)', 'execute') then
    raise exception '20261017050200: dados.atm_pertence ficou executável por anon, authenticated ou service_role';
  end if;
end
$a$;

insert into pg_temp._z_out(passo, linha) select '20 md5 do corpo depois', md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '20 ACL depois', coalesce(proacl::text, '(nula)') from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS e-mail da aplicação, chave certa (esperado antes false, depois true)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS telefone da aplicação, chave certa (esperado antes false, depois true)', dados.atm_pertence('black-thb-2026-10', 'fone', '99991357')::text;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS e-mail da aplicação com origem fora do de-para (esperado false)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov2@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS e-mail da aplicação em OUTRA chave (esperado false)', dados.atm_pertence('atm-elaine-1-2026-10', 'email', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS telefone da aplicação em OUTRA chave (esperado false)', dados.atm_pertence('atm-elaine-1-2026-10', 'fone', '99991357')::text;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS e-mail sem relação (esperado false)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.nada@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '21 DEPOIS tipo inválido (esperado false)', dados.atm_pertence('black-thb-2026-10', 'outro', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha)
select '22 regressão DEPOIS (marcações reais reconhecidas / total; tem que ser igual à ANTES)', string_agg(chave || ' ' || tipo || ': ' || ok || '/' || total, ' | ' order by chave, tipo)
  from (select chave, tipo, count(*) total, count(*) filter (where dados.atm_pertence(chave, tipo, valor)) ok
          from dados.marcacoes_teste where desmarcado_em is null and not (valor like 'zz%' or valor = '99991357') group by 1, 2) x;
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select dados.atm_pertence(''black-thb-2026-10'', ''email'', ''zz.renov1@example.invalid'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time)' then
        insert into pg_temp._z_out (passo, linha) values ('23 explain DEPOIS valor só no renov #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;
do $x$ declare r record; n int; begin
  for n in 1..2 loop
    for r in execute 'explain (analyze, buffers) select dados.atm_pertence(''black-thb-2026-10'', ''email'', ''zz.nada@example.invalid'')' loop
      if r."QUERY PLAN" ~ '(Execution Time|Planning Time)' then
        insert into pg_temp._z_out (passo, linha) values ('24 explain DEPOIS valor inexistente #' || n, r."QUERY PLAN");
      end if;
    end loop;
  end loop;
end $x$;

-- permissões: quem NÃO pode chamar direto
set local role authenticated;
select pg_temp.foto('25 authenticated chama atm_pertence direto (esperado 42501)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov1@example.invalid')::text$q$);reset role;
select set_config('request.jwt.claims', '', true);

set local role anon;
select pg_temp.foto('26 anon chama atm_pertence direto (esperado 42501)', null, $q$select dados.atm_pertence('black-thb-2026-10', 'email', 'x')::text$q$);reset role;
select set_config('request.jwt.claims', '', true);

-- o caminho real de quem marca: dados_marcar_teste
set local role authenticated;
select pg_temp.foto('30 master marca o e-mail da aplicação (esperado passou: 1)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.renov1@example.invalid', null, 'teste')::text$q$);
select pg_temp.foto('31 master marca o telefone da aplicação (esperado passou: 1)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', null, '(21) 99999-1357', 'teste')::text$q$);
select pg_temp.foto('32 master marca de novo o e-mail (idempotente, esperado passou: 0)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.renov1@example.invalid', null, 'teste')::text$q$);
select pg_temp.foto('33 master marca e-mail sem relação (esperado P0002)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.nada@example.invalid', null, 'teste')::text$q$);
select pg_temp.foto('34 master marca e-mail de aplicação com origem fora do de-para (esperado P0002)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.renov2@example.invalid', null, 'teste')::text$q$);
select pg_temp.foto('35 jessica (não master) tenta marcar (esperado 42501)', '012bbcd3-cade-4889-a6ff-4804ed15c36d', $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.renov1@example.invalid', null, 'teste')::text$q$);
select pg_temp.foto('36 anônimo tenta marcar (esperado 42501)', null, $q$select public.dados_marcar_teste('black-thb-2026-10', 'zz.renov1@example.invalid', null, 'teste')::text$q$);
reset role;
select set_config('request.jwt.claims', '', true);

insert into pg_temp._z_out(passo, linha) select '37 dados.teste_ativo do e-mail e do telefone fictícios (esperado true / true)', dados.teste_ativo('black-thb-2026-10', 'zz.renov1@example.invalid', null)::text || ' / ' || dados.teste_ativo('black-thb-2026-10', null, '(21) 99999-1357')::text;
insert into pg_temp._z_out(passo, linha) select '38 teste_ativo noutra chave (esperado false)', dados.teste_ativo('atm-elaine-1-2026-10', 'zz.renov1@example.invalid', null)::text;
set local role authenticated;
select pg_temp.foto('39 master desmarca o e-mail (esperado passou: 1)', '81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select public.dados_desmarcar_teste('black-thb-2026-10', 'zz.renov1@example.invalid', null)::text$q$);reset role;
select set_config('request.jwt.claims', '', true);

insert into pg_temp._z_out(passo, linha) select '39 teste_ativo do e-mail depois de desmarcar (esperado false)', dados.teste_ativo('black-thb-2026-10', 'zz.renov1@example.invalid', null)::text;
-- a guarda reexecutada com a migration aplicada tem que abortar
create temp table _g (txt text);
insert into pg_temp._g values ($zz$
do $g$
begin
  if to_regprocedure('dados.atm_pertence(text,text,text)') is null then
    raise exception '20261017050200: dados.atm_pertence(text,text,text) não existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure) <> '7945be0a410031528e24bd21a4c876ca' then
    raise exception '20261017050200: o corpo vivo de dados.atm_pertence mudou desde a leitura de 16/10/2026; reler e refazer a partir dele';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050200: faltam metodo.renov_aplicacoes (20261016163924, Arthur) ou metodo.origem_etiqueta';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050200: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100); sem ele o ramo novo nunca casa';
  end if;
end
$g$;
$zz$);
do $n$ begin
  begin execute (select txt from pg_temp._g); insert into pg_temp._z_out(passo, linha) values ('40 reaplicar sem reverter', 'NAO ABORTOU (erro!)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('40 reaplicar sem reverter', 'abortou: ' || left(sqlerrm, 160)); end;
end $n$;
-- reversão ensaiada
-- Reversão da 20261017050200: devolve o corpo de dados.atm_pertence lido do banco vivo em 16/10/2026 (md5 do corpo 7945be0a410031528e24bd21a4c876ca).
-- A ACL não muda (create or replace a preserva).
create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008191000; número da foto do grupo em 20261008200000
  select case p_tipo
    when 'email' then
         exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$function$;
delete from supabase_migrations.schema_migrations where version = '20261017050200';

insert into pg_temp._z_out(passo, linha) select '50 md5 do corpo depois da reversão (esperado 7945be0a410031528e24bd21a4c876ca)', md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '50 ACL depois da reversão', coalesce(proacl::text, '(nula)') from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO e-mail da aplicação, chave certa (esperado antes false, depois true)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO telefone da aplicação, chave certa (esperado antes false, depois true)', dados.atm_pertence('black-thb-2026-10', 'fone', '99991357')::text;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO e-mail da aplicação com origem fora do de-para (esperado false)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.renov2@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO e-mail da aplicação em OUTRA chave (esperado false)', dados.atm_pertence('atm-elaine-1-2026-10', 'email', 'zz.renov1@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO telefone da aplicação em OUTRA chave (esperado false)', dados.atm_pertence('atm-elaine-1-2026-10', 'fone', '99991357')::text;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO e-mail sem relação (esperado false)', dados.atm_pertence('black-thb-2026-10', 'email', 'zz.nada@example.invalid')::text;
insert into pg_temp._z_out(passo, linha) select '51 DEPOIS DA REVERSÃO tipo inválido (esperado false)', dados.atm_pertence('black-thb-2026-10', 'outro', 'zz.renov1@example.invalid')::text;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
