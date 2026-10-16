-- Ensaio de 20261017050100_metodo_origem_renov_thb.sql numa transação DESFEITA (rollback), sobre produção. Sem dado pessoal na saída.
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

insert into pg_temp._z_out(passo, linha) select '00 de-para antes', coalesce(string_agg(origem || '->' || etiqueta, ' | ' order by origem), '(vazio)') from metodo.origem_etiqueta;
insert into pg_temp._z_out(passo, linha) select '00 pesquisa_respostas com origem renov-thb', count(*)::text from metodo.pesquisa_respostas where origem = 'renov-thb';
-- ===== corpo da migration =====
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

insert into pg_temp._z_out(passo, linha) select '10 de-para depois', coalesce(string_agg(origem || '->' || etiqueta, ' | ' order by origem), '(vazio)') from metodo.origem_etiqueta;
-- a guarda reexecutada com a migration aplicada tem que abortar
create temp table _g (txt text);
insert into pg_temp._g values ($zz$
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
$zz$);
do $n$ begin
  begin execute (select txt from pg_temp._g); insert into pg_temp._z_out(passo, linha) values ('11 reaplicar sem reverter', 'NAO ABORTOU (erro!)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('11 reaplicar sem reverter', 'abortou: ' || left(sqlerrm, 160)); end;
end $n$;
-- o gatilho de pesquisa_respostas continua sem efeito (nenhuma linha com essa origem)
insert into pg_temp._z_out(passo, linha) select '12 pesquisa_respostas etiquetadas por renov-thb', count(*)::text from metodo.pesquisa_respostas where origem = 'renov-thb';
-- Reversão da 20261017050100. Tira só a linha do de-para.
delete from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10';
delete from supabase_migrations.schema_migrations where version = '20261017050100';

insert into pg_temp._z_out(passo, linha) select '20 de-para depois da reversao', coalesce(string_agg(origem || '->' || etiqueta, ' | ' order by origem), '(vazio)') from metodo.origem_etiqueta;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
