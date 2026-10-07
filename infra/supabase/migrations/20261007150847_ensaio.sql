-- 20261007150847_ensaio.sql — ensaio da 20261007150847 (escrita como 20261007x) em transação DESFEITA (termina em ROLLBACK).
-- Esperado: Elaine (solicitante) recebe as 9 listas, produtos = 97 (fin.produtos), em ~20 ms (antes 4.731 ms);
-- SV aparece nas duas contas ("(Escritório)" na do escritório); visualizador recebe 42501; anon sem execute.
-- Medido em 07/10/2026: 20,2 ms (1ª) e 10,6 ms (2ª).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';
-- 20261007x_crm_estrategias_opcoes.sql
-- crm_estrategia_opcoes: a lista de produtos vinha de um distinct sobre fin.hotmart_transacoes (57.885 linhas, 4,7 s
-- medidos depois de aplicar 20261007150701; teto do authenticator é 8 s). Passa a ler o catálogo fin.produtos
-- (97 linhas, com a conta). Mesma assinatura (create or replace não cria sobrecarga); corpo VIVO de 20261007150701
-- com só o bloco 'produtos' trocado. Revoke repetido por segurança.
do $$
begin
  if to_regprocedure('public.crm_estrategia_opcoes()') is null then raise exception 'premissa: crm_estrategia_opcoes ausente'; end if;
  if position('fin.hotmart_transacoes' in pg_get_functiondef('public.crm_estrategia_opcoes()'::regprocedure)) = 0 then
    raise exception 'premissa: crm_estrategia_opcoes já não lê as transações';
  end if;
  if (select count(*) from fin.produtos) < 50 then raise exception 'premissa: fin.produtos vazio'; end if;
end $$;

create or replace function public.crm_estrategia_opcoes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (coalesce(crm.estrategia_eh_gestor(), false) or coalesce(crm.pode_solicitar_estrategia(), false)) then
    raise exception 'Sem acesso às Estratégias.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'niveis', coalesce((select jsonb_agg(x order by x) from (select distinct a.nivel_resultado x from public.thb_alunos a where a.nivel_resultado is not null) s), '[]'),
    'turmas', coalesce((select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'tipo', t.tipo) order by t.tipo, t.codigo) from public.thb_turmas t), '[]'),
    'planos', coalesce((select jsonb_agg(x order by x) from (select distinct a.plano x from public.thb_alunos a where a.plano is not null and a.plano <> '') s), '[]'),
    'statusAcesso', coalesce((select jsonb_agg(x order by x) from (select distinct a.status_acesso x from public.thb_alunos a where a.status_acesso is not null) s), '[]'),
    'linhas', coalesce((select jsonb_agg(jsonb_build_object('chave', l.chave, 'nome', l.nome, 'escada', l.escada) order by l.ordem) from crm.linha l where l.ativo), '[]'),
    'produtos', coalesce((select jsonb_agg(jsonb_build_object('id', p.produto_id,
                                                                'nome', coalesce(pc.nome_comercial, p.nome) || case when p.conta = 'escritorio' then ' (Escritório)' else '' end)
                                           order by coalesce(pc.nome_comercial, p.nome), p.conta)
                          from fin.produtos p left join crm.produto_comercial pc on pc.produto_id = p.produto_id), '[]'),
    'projetos', coalesce((select jsonb_agg(x order by x) from (select distinct po.projeto x from crm.pessoa_origem po where po.projeto is not null) s), '[]'),
    'canais', coalesce((select jsonb_agg(x order by x) from (select distinct po.canal_entrada x from crm.pessoa_origem po where po.canal_entrada is not null) s), '[]'),
    'perguntas', coalesce((select jsonb_agg(jsonb_build_object('pergunta', s.p, 'formularios', s.n) order by s.n desc, s.p) from (
        select c ->> 'pergunta' p, count(distinct f.slug) n
          from respondi.formularios f, jsonb_array_elements(case jsonb_typeof(f.campos) when 'array' then f.campos else '[]'::jsonb end) c
         where c ->> 'tipo' in ('radio', 'select', 'checkbox', 'text', 'textarea') and length(c ->> 'pergunta') between 5 and 300
         group by 1 order by 2 desc limit 300) s), '[]'));
end
$$;
revoke execute on function public.crm_estrategia_opcoes() from public, anon;
grant execute on function public.crm_estrategia_opcoes() to authenticated;

create temp table _t (k text, ms numeric, v jsonb);
grant all on _t to authenticated;
select set_config('request.jwt.claims', '{"sub":"6ed2bfc4-1d69-458d-9954-77a03902c56a","role":"authenticated"}', true);
set local role authenticated;
do $t$ declare t0 timestamptz; v jsonb; begin
  t0 := clock_timestamp(); v := public.crm_estrategia_opcoes();
  insert into _t values ('elaine_opcoes_1', extract(epoch from clock_timestamp()-t0)*1000, (select jsonb_object_agg(k, jsonb_array_length(v -> k)) from jsonb_object_keys(v) k));
  t0 := clock_timestamp(); v := public.crm_estrategia_opcoes();
  insert into _t values ('elaine_opcoes_2', extract(epoch from clock_timestamp()-t0)*1000, (select jsonb_agg(p) from jsonb_array_elements(v -> 'produtos') p where p ->> 'id' in ('1663254','5238525')));
end $t$;
reset role;
select set_config('request.jwt.claims', '{"sub":"9d5fb8e7-f61e-459d-be04-d103ec783c08","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform public.crm_estrategia_opcoes(); insert into _t values ('visualizador', null, '"VAZOU"');
  exception when insufficient_privilege then insert into _t values ('visualizador', null, to_jsonb('42501: ' || sqlerrm)); end $t$;
reset role;
insert into _t select 'anon_exec', null, to_jsonb(has_function_privilege('anon', 'public.crm_estrategia_opcoes()', 'execute'));
select * from _t;
rollback;
