-- Ensaio de 20261014210200 (planilha de ativação) com dado FICTÍCIO (@exemplo.invalid), numa transação DESFEITA, sobre o
-- banco com os grupos A e B aplicados.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
begin;
set local lock_timeout = '5s';
set local statement_timeout = '60s';
create temp table _z_out (em serial, passo text, linha text);
-- ===== 20261014210200 =====
-- 20261014210200: carga da planilha "Alunos T1-T42 Ativação" (alunos e sócios por turma) para a pessoa única
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014150034 (ex-170000: controle de carga,
--   casar_email) e de pessoas.relacoes (20261014150003). Ensaio: 20261014210200_ensaio.sql (dado fictício).
--   Script: infra/scripts/pessoa-unica/carga_planilha.py (lê a planilha com a conta do Victor, manda as linhas como parâmetro).
--
-- POR QUE: fonte nova do Victor (14/10/2026): planilha 1bxr71O3UKo0fdPfNXPEYNs9ZWrHNooXALxmvCXa6Ak8. A base compilada
--   "Alunos e sócios T1 - T40" (espelho controle.aluno_historico) vai até a T40, com T39 e T40 incompletas, e não tem T41
--   nem T42; a ativação tem todas as turmas e as abas de sócios.
-- O QUE FAZ:
--   pessoas.planilha_linha   estágio: uma linha por (aba, e-mail) de aluno ou (aba, e-mail do titular, e-mail do sócio).
--                            Só e-mail, telefone, nome, turma (do nome da aba), data e o papel. Documento e CPF NÃO entram
--                            (o script nem lê essas colunas).
--   carga_planilha_estagio   grava um lote no estágio (idempotente; valores validados antes do CHECK).
--   carga_planilha_pessoas   estágio -> pessoa (casar_email), evento 'ativacao' (aluno, com turma) ou 'vinculo' + relação
--                            'socio_de' (sócio -> titular). Sócio cuja aba só traz o NOME do titular (abas antigas): entra
--                            o vínculo na turma e a relação fica pendente (nome não casa pessoa; o nome fica no estágio). fonte_tabela 'pessoas.planilha_linha', fonte_id = chave do estágio.
--   Turma pelo nome da aba (T42, T29.2, T17R...); a que não existe em public.thb_turmas (T42, T10.1) fica sem turma_id e
--   com o texto em detalhe.turma (pergunta: criar T42 em thb_turmas é decisão do dono da Central).
-- AS 5 PERGUNTAS: escala = ~9 mil linhas (8.834 e-mails em 104 abas, censo ETAPA 1); índice = PK chave + parcial dos
--   pendentes; frequência = 1 carga + recarga manual quando a planilha mudar; repetição = idempotente; reversão =
--   20261014210200_reversao.sql (estágio e funções saem; pessoa não se apaga).
-- ACESSO: RLS ligada, sem policy e sem grant; funções SECURITY INVOKER sem execute para anon/authenticated/service_role.

set local lock_timeout = '5s';

do $g$
begin
  if to_regprocedure('pessoas.casar_email(text,text,text,text)') is null or to_regclass('pessoas.relacoes') is null then
    raise exception '20261014210200: falta a estrutura da carga (20261014150034) ou pessoas.relacoes (20261014150003).';
  end if;
  if to_regclass('pessoas.planilha_linha') is not null then raise exception '20261014210200: já aplicada.'; end if;
end
$g$;

insert into pessoas.carga_chave (fonte, ligada, por) values ('ativacao_planilha', true, 'migration 20261014210200')
on conflict (fonte) do nothing;

create table pessoas.planilha_linha (
  chave             text primary key check (chave ~ '^[0-9a-f]{32}$'),
  planilha          text not null check (planilha ~ '^[A-Za-z0-9_-]{20,80}$'),
  aba               text not null check (length(aba) between 1 and 120),
  papel             text not null check (papel in ('aluno', 'socio')),
  turma             text check (turma is null or turma ~ '^[TA][0-9]+(\.[0-9]+|R)?$'),
  email             text check (email is null or length(email) <= 320),
  telefone          text check (telefone is null or telefone ~ '^[0-9]{10,11}$'),
  nome              text check (nome is null or length(nome) <= 160),
  titular_email     text check (titular_email is null or length(titular_email) <= 320),
  titular_nome      text check (titular_nome is null or length(titular_nome) <= 160),
  data              date,
  pendente          boolean not null default true,
  pessoa_id         uuid references pessoas.pessoas(id) on delete restrict,
  titular_pessoa_id uuid references pessoas.pessoas(id) on delete restrict,
  carregado_em      timestamptz not null default now(),
  processado_em     timestamptz
);
alter table pessoas.planilha_linha enable row level security;
create index planilha_linha_pendente_idx on pessoas.planilha_linha (chave) where pendente;
revoke all on pessoas.planilha_linha from public, anon, authenticated, service_role;
comment on table pessoas.planilha_linha is 'Estágio da planilha Alunos T1-T42 Ativação: aluno por turma e sócio de titular. Sem documento/CPF.';

-- grava um lote no estágio. p_linhas = [{aba, papel, turma, email, telefone, nome, titular_email, titular_nome, data}]
create function pessoas.carga_planilha_estagio(p_execucao bigint, p_planilha text, p_linhas jsonb) returns jsonb
language plpgsql set search_path to '' as $f$
declare v_t0 timestamptz := clock_timestamp(); v_lidas int; v_ins int; v_upd int; v_desc int;
begin
  if not pessoas.carga_ligada('ativacao_planilha') then raise exception 'carga desligada' using errcode = 'P0001'; end if;
  if not exists (select 1 from pessoas.carga_execucao where id = p_execucao and fonte = 'ativacao_planilha' and fase = 'estagio' and status = 'rodando') then
    raise exception 'execução % não está rodando (estagio/ativacao_planilha)', p_execucao using errcode = 'P0001';
  end if;
  if p_planilha !~ '^[A-Za-z0-9_-]{20,80}$' then raise exception 'planilha inválida' using errcode = '22023'; end if;
  if jsonb_typeof(p_linhas) <> 'array' or jsonb_array_length(p_linhas) > 2000 then
    raise exception 'lote inválido (array de até 2.000 linhas)' using errcode = '22023';
  end if;
  v_lidas := jsonb_array_length(p_linhas);
  with e as (
    select el from jsonb_array_elements(p_linhas) el where jsonb_typeof(el) = 'object'
  ), x0 as (
    select left(btrim(el->>'aba'), 120) aba,
           case when el->>'papel' in ('aluno', 'socio') then el->>'papel' end papel,
           case when el->>'turma' ~ '^[TA][0-9]{1,3}(\.[0-9]{1,2}|R)?$' then el->>'turma' end turma,
           pessoas.norm_email(left(el->>'email', 1000)) email0,
           pessoas.norm_email(left(el->>'titular_email', 1000)) tit0,
           pessoas.norm_telefone(left(el->>'telefone', 40)) telefone,
           nullif(left(btrim(coalesce(el->>'nome', '')), 160), '') nome,
           nullif(left(btrim(coalesce(el->>'titular_nome', '')), 160), '') titular_nome,
           case when pg_input_is_valid(el->>'data', 'date') then (el->>'data')::date end data
      from e
  ), x as (
    select distinct on (chave) *
      from (select md5(p_planilha || '|' || aba || '|' || coalesce(tit0, '') || '|' || email0) chave, *
              from x0
             where aba <> '' and papel is not null and email0 is not null and length(email0) <= 320
               and (tit0 is null or length(tit0) <= 320)) y
     order by chave
  ), up as (
    insert into pessoas.planilha_linha as c (chave, planilha, aba, papel, turma, email, telefone, nome, titular_email, titular_nome, data)
    select chave, p_planilha, aba, papel, turma, email0, telefone, nome, case when papel = 'socio' then tit0 end, titular_nome, data from x
    on conflict (chave) do update
       set turma = excluded.turma, telefone = excluded.telefone, nome = excluded.nome, titular_nome = excluded.titular_nome,
           data = excluded.data, pendente = true
     where (c.turma, c.telefone, c.nome, c.titular_nome, c.data)
           is distinct from (excluded.turma, excluded.telefone, excluded.nome, excluded.titular_nome, excluded.data)
    returning (xmax = 0) inserida
  )
  select count(*) filter (where inserida), count(*) filter (where not inserida) into v_ins, v_upd from up;
  v_desc := v_lidas - (select count(*) from jsonb_array_elements(p_linhas) el
                        where jsonb_typeof(el) = 'object' and pessoas.norm_email(left(el->>'email', 1000)) is not null);
  insert into pessoas.carga_lote (execucao_id, lidas, inseridas, atualizadas, iguais, detalhe, ms)
  values (p_execucao, v_lidas, v_ins, v_upd, v_lidas - v_ins - v_upd, jsonb_build_object('sem_email_valido', v_desc),
          (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
  update pessoas.carga_execucao set lotes = lotes + 1, lidas = lidas + v_lidas, inseridas = inseridas + v_ins,
         atualizadas = atualizadas + v_upd, iguais = iguais + (v_lidas - v_ins - v_upd), atualizada_em = now()
   where id = p_execucao;
  return jsonb_build_object('lidas', v_lidas, 'inseridas', v_ins, 'atualizadas', v_upd, 'sem_email_valido', v_desc,
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $f$;

-- estágio -> pessoas: aluno = ativacao na turma; sócio = vinculo + relação socio_de com o titular
create function pessoas.carga_planilha_pessoas(p_execucao bigint, p_limite integer default 1000) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); r record; v jsonb; v_p uuid; v_tit uuid; v_turma smallint;
  n_l int := 0; n_n int := 0; n_c int := 0; n_e int := 0; n_r int := 0; n_x int;
begin
  if not pessoas.carga_ligada('ativacao_planilha') then raise exception 'carga desligada' using errcode = 'P0001'; end if;
  if not exists (select 1 from pessoas.carga_execucao where id = p_execucao and fonte = 'ativacao_planilha' and fase = 'pessoas' and status = 'rodando') then
    raise exception 'execução % não está rodando (pessoas/ativacao_planilha)', p_execucao using errcode = 'P0001';
  end if;
  if p_limite not between 1 and 2000 then raise exception 'limite entre 1 e 2.000' using errcode = '22023'; end if;
  for r in select * from pessoas.planilha_linha where pendente order by chave limit p_limite for update skip locked loop
    n_l := n_l + 1;
    v := pessoas.casar_email(r.nome, r.email, r.telefone, 'importacao');
    v_p := (v->>'pessoa_id')::uuid;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_turma := (select t.id from public.thb_turmas t where t.codigo = r.turma);
    v_tit := null;
    if r.papel = 'aluno' then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', v_turma, 'pessoas.planilha_linha', r.chave,
              coalesce(r.data::timestamp at time zone 'America/Sao_Paulo', now()),
              jsonb_strip_nulls(jsonb_build_object('origem', 'ativacao_planilha', 'turma', r.turma, 'aba', left(r.aba, 120),
                                                   'data_estimada', r.data is null)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    else
      if r.titular_email is not null then
        v := pessoas.casar_email(r.titular_nome, r.titular_email, null, 'importacao');
        v_tit := (v->>'pessoa_id')::uuid;
        if (v->>'nova')::boolean then n_n := n_n + 1; end if;
      end if;
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'vinculo', 'importacao', v_turma, 'pessoas.planilha_linha', r.chave,
              coalesce(r.data::timestamp at time zone 'America/Sao_Paulo', now()),
              jsonb_strip_nulls(jsonb_build_object('relacao', 'socio_de', 'origem', 'ativacao_planilha', 'turma', r.turma, 'aba', left(r.aba, 120),
                                                   'titular_pendente', case when v_tit is null then true end)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
      if v_tit is not null and v_tit <> v_p then
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_p, v_tit, v_turma, 'pessoas.planilha_linha', r.chave)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
    update pessoas.planilha_linha set pendente = false, processado_em = now(), pessoa_id = v_p, titular_pessoa_id = v_tit where chave = r.chave;
  end loop;
  insert into pessoas.carga_lote (execucao_id, lidas, inseridas, atualizadas, iguais, detalhe, ms)
  values (p_execucao, n_l, n_n, n_c, 0, jsonb_build_object('eventos', n_e, 'relacoes', n_r), (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
  update pessoas.carga_execucao set lotes = lotes + 1, lidas = lidas + n_l, inseridas = inseridas + n_n, atualizadas = atualizadas + n_c, atualizada_em = now()
   where id = p_execucao;
  return jsonb_build_object('lidas', n_l, 'pessoas_novas', n_n, 'casadas', n_c, 'eventos', n_e, 'relacoes', n_r,
                            'restam', (select count(*) from pessoas.planilha_linha where pendente),
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $f$;

revoke all on function pessoas.carga_planilha_estagio(bigint, text, jsonb), pessoas.carga_planilha_pessoas(bigint, integer)
  from public, anon, authenticated, service_role;

do $g$
begin
  if has_function_privilege('anon', 'pessoas.carga_planilha_estagio(bigint,text,jsonb)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_planilha_pessoas(bigint,integer)', 'execute')
     or has_table_privilege('anon', 'pessoas.planilha_linha', 'select') or has_table_privilege('authenticated', 'pessoas.planilha_linha', 'select') then
    raise exception '20261014210200: algo da carga da planilha ficou aberto para anon/authenticated.';
  end if;
end
$g$;

-- ===== testes =====
create temp table _z_l as select '[
 {"aba":"T42 - HT 32 - Set/26","papel":"aluno","turma":"T42","email":"ensaio-a1@exemplo.invalid","nome":"Aluno Um","telefone":"(11) 99999-0001","data":"2026-09-20"},
 {"aba":"T41 - Acelera Holding - Set/26","papel":"aluno","turma":"T41","email":"ensaio-a2@exemplo.invalid","nome":"Aluno Dois"},
 {"aba":"T41 - Acelera Holding - Set/26","papel":"aluno","turma":"T41","email":"ENSAIO-A2@exemplo.invalid ","nome":"Aluno Dois repetido"},
 {"aba":"Sócios T42 -  Set/26","papel":"socio","turma":"T42","email":"ensaio-s1@exemplo.invalid","nome":"Sócio Um","titular_email":"ensaio-a1@exemplo.invalid","titular_nome":"Aluno Um"},
 {"aba":"Sócios T42 -  Set/26","papel":"socio","turma":"T42","email":"ensaio-s2@exemplo.invalid","nome":"Sócio sem titular"},
 {"aba":"T42 - HT 32 - Set/26","papel":"aluno","turma":"T42","email":"nao-e-email","nome":"Inválido"},
 {"aba":"T42 - HT 32 - Set/26","papel":"chefe","turma":"X9","email":"ensaio-a3@exemplo.invalid","data":"2026-02-30"}
]'::jsonb j;
create temp table _z_e as select (pessoas.carga_abrir('ativacao_planilha', 'estagio', 'ensaio')->>'execucao')::bigint id;
insert into pg_temp._z_out(passo, linha) select '10 estágio 1ª passada (esperado 4 inseridas: a1, a2 uma vez, s1, s2 sem titular)', pessoas.carga_planilha_estagio((select id from pg_temp._z_e), '1bxr71O3UKo0fdPfNXPEYNs9ZWrHNooXALxmvCXa6Ak8', (select j from pg_temp._z_l))::text;
insert into pg_temp._z_out(passo, linha) select '11 estágio 2ª passada (0 inseridas)', pessoas.carga_planilha_estagio((select id from pg_temp._z_e), '1bxr71O3UKo0fdPfNXPEYNs9ZWrHNooXALxmvCXa6Ak8', (select j from pg_temp._z_l))::text;
select pessoas.carga_fechar((select id from pg_temp._z_e), 'ok');
create temp table _z_p as select (pessoas.carga_abrir('ativacao_planilha', 'pessoas', 'ensaio')->>'execucao')::bigint id;
insert into pg_temp._z_out(passo, linha) select '20 pessoas', pessoas.carga_planilha_pessoas((select id from pg_temp._z_p), 1000)::text;
update pessoas.planilha_linha set pendente = true;
insert into pg_temp._z_out(passo, linha) select '21 reprocessar (0 eventos, 0 relações novas)', pessoas.carga_planilha_pessoas((select id from pg_temp._z_p), 1000)::text;
insert into pg_temp._z_out(passo, linha) select '22 eventos (ativacao 2, vinculo 2) / relação sócio de (1: só quem tem e-mail do titular)', (select string_agg(tipo || ' ' || n, ', ' order by tipo) from (select tipo, count(*) n from pessoas.eventos where fonte_tabela = 'pessoas.planilha_linha' group by 1) x) || ' / ' || (select count(*) from pessoas.relacoes where fonte_tabela = 'pessoas.planilha_linha');
insert into pg_temp._z_out(passo, linha) select '23 T41 com turma_id / T42 sem turma_id e com o texto', (select count(*) from pessoas.eventos e join public.thb_turmas t on t.id = e.turma_id where e.fonte_tabela = 'pessoas.planilha_linha' and t.codigo = 'T41') || ' / ' || (select count(*) from pessoas.eventos where fonte_tabela = 'pessoas.planilha_linha' and turma_id is null and detalhe->>'turma' = 'T42');
insert into pg_temp._z_out(passo, linha) select '25 sócio sem titular: vínculo com titular_pendente', (select count(*) from pessoas.eventos where fonte_tabela = 'pessoas.planilha_linha' and detalhe->>'titular_pendente' = 'true')::text;
insert into pg_temp._z_out(passo, linha) select '24 nada aberto para anon/authenticated', (not has_table_privilege('anon', 'pessoas.planilha_linha', 'select') and not has_function_privilege('authenticated', 'pessoas.carga_planilha_pessoas(bigint,integer)', 'execute'))::text;
-- ===== reversão =====
-- Reversão de 20261014210200 (carga da planilha de ativação). NÃO apaga pessoa nem evento já carregado; medir antes com
--   select count(*) from pessoas.eventos where fonte_tabela = 'pessoas.planilha_linha';
set local lock_timeout = '5s';
drop function if exists pessoas.carga_planilha_pessoas(bigint, integer);
drop function if exists pessoas.carga_planilha_estagio(bigint, text, jsonb);
drop table if exists pessoas.planilha_linha;
delete from pessoas.carga_chave where fonte = 'ativacao_planilha' and por = 'migration 20261014210200';

insert into pg_temp._z_out(passo, linha) select '90 depois da reversão', coalesce(to_regclass('pessoas.planilha_linha')::text, 'sem estágio') || ' / ' || coalesce(to_regprocedure('pessoas.carga_planilha_pessoas(bigint,integer)')::text, 'sem função');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
