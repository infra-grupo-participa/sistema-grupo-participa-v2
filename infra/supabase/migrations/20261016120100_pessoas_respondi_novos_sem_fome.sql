-- 20261016120100: pessoas.carga_respondi e pessoas.carga_aluno_historico no modo "só novos" não ficam presas em linha que nunca vira evento
--
-- STATUS: APLICADA 16/10/2026 ~12:33 UTC em produção (versão 20261016120100 em schema_migrations; md5 dos corpos conferidos depois).
--   Escrita pelo back-end-sr em 16/10/2026, refeita no mesmo dia depois do achado 1 do pentester. Independente de 20261016120000
--   (a procedure funciona sem esta), mas sem ela as fontes 'respondi' e 'aluno_historico' relêem para sempre as linhas descartadas.
--   Ensaio: 20261016120000_ensaio.sql (traz as duas migrations). Reversão: 20261016120100_reversao.sql. Detalhe: 20261016120100.explain.md.
--
-- POR QUE: no modo p_novos a função lê as 200 primeiras linhas sem evento. Quem não tem e-mail válido nunca vira pessoa
--   (pessoas._casar_email_seguro devolve pessoa nula e a linha é só contada como pulada), logo nunca ganha evento e fica na janela para sempre.
--   Medido em 16/10/2026: respondi tem 3.505 respostas sem evento e 3.496 delas não têm e-mail válido (a 1ª versão desta migration filtrava por
--   "8 dígitos no telefone" e deixava passar 853 dessas); aluno_historico tem 29 linhas sem evento, todas com e-mail inválido.
-- O QUE MUDA (só o WHERE/ORDER BY do modo p_novos; carga inicial e cursor idênticos):
--   1. respondi, p_novos: só considera resposta com e-mail normalizado válido e de até 320 caracteres, o MESMO critério do descarte
--      (length(pessoas.norm_email(left(coalesce(email, dados->>'email'), 1000))) <= 320). Ordena pelas mais recentes (respondido_em).
--   2. aluno_historico, p_novos: o mesmo critério sobre email_norm. As 29 linhas deixam de ser relidas e nunca geram 'sem_avanco' falso.
--   Assinaturas, search_path, acl e retorno iguais. Corpos anteriores (md5 cc382c4c995d9d475c2e984f8203b4fd e 65ab8c104745e404dc33a1d5d943e79f) estão na reversão.
-- AS 5 PERGUNTAS: escala = 23 mil respostas e 7,6 mil linhas de histórico, 200 por execução; índice = eventos_fonte_unico no anti-join (sem índice
--   novo; o filtro roda sobre as ~3,5 mil respostas sem evento); frequência = 1×/hora, só pelo job pessoas-incremental (desligado); repetição =
--   idempotente (on conflict do nothing); reversão = 20261016120100_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> 'cc382c4c995d9d475c2e984f8203b4fd' then
    raise exception '20261016120100: o corpo de pessoas.carga_respondi não é o esperado (md5 cc382c4c995d9d475c2e984f8203b4fd). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure) <> '65ab8c104745e404dc33a1d5d943e79f' then
    raise exception '20261016120100: o corpo de pessoas.carga_aluno_historico não é o esperado (md5 65ab8c104745e404dc33a1d5d943e79f). Reler antes de aplicar.';
  end if;
end
$g$;

create or replace function pessoas.carga_respondi(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_s uuid; v_turma smallint;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'respondi'), '');
  for r in select x.uuid, x.form_slug, x.respondido_em, x.email, x.telefone, x.dados, f.familia, f.turma_codigo f_turma
             from respondi.respostas x left join respondi.formularios f on f.slug = x.form_slug
            where (not p_novos and x.uuid::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta')
                   -- mesmo descarte de pessoas._casar_email_seguro: e-mail normalizado válido e de até 320 caracteres. Quem não passa aqui nunca vira
                   -- pessoa nem evento e travaria a janela de 200 (medido em 16/10/2026: 3.505 sem evento, 3.496 delas não passam)
                   and length(pessoas.norm_email(left(coalesce(x.email, x.dados->>'email'), 1000))) <= 320)
            -- só novos: as mais recentes primeiro, para uma linha antiga que não casa nunca tapar a janela; carga inicial: pelo uuid, como antes
            order by case when p_novos then -extract(epoch from coalesce(x.respondido_em, timestamptz 'epoch')) end, x.uuid::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.uuid::text); v_ate := r.uuid::text;
    v := pessoas._casar_email_seguro(r.dados->>'nome', coalesce(r.email, r.dados->>'email'), coalesce(r.telefone, r.dados->>'telefone'), 'respondi');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_turma := (select t.id from public.thb_turmas t where t.codigo = coalesce(r.f_turma, r.dados->>'turma_codigo'));
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'resposta', 'respondi', v_turma, 'respondi.respostas', r.uuid::text, coalesce(r.respondido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('formulario', left(r.form_slug, 40), 'familia', left(r.familia, 40),
                                                 'parcial', case when r.dados->>'parcial' = 'true' then true end)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    -- formulário de sócio: o sócio vira pessoa (por e-mail) e "sócio de" quem respondeu (o titular)
    if pessoas.norm_email(r.dados->>'socio_email') is not null then
      v := pessoas._casar_email_seguro(r.dados->>'socio_nome', r.dados->>'socio_email', r.dados->>'socio_telefone', 'respondi');
      v_s := (v->>'pessoa_id')::uuid;
      if v_s is not null and v_s <> v_p then
        if (v->>'nova')::boolean then n_n := n_n + 1; end if;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
        values (v_s, 'vinculo', 'respondi', v_turma, 'respondi.respostas', r.uuid::text || ':socio', coalesce(r.respondido_em, now()),
                jsonb_build_object('relacao', 'socio_de', 'formulario', left(r.form_slug, 40)))
        on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
        get diagnostics n_x = row_count; n_e := n_e + n_x;
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_s, v_p, v_turma, 'respondi.respostas', r.uuid::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

create or replace function pessoas.carga_aluno_historico(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_chave text; v_quando timestamptz;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'aluno_historico'), '');
  -- cursor = md5(e-mail):turma (o espelho é regravado todo dia e os ids mudam)
  for r in select md5(h.email_norm) || ':' || coalesce(h.turma, '') k, h.*
             from controle.aluno_historico h
            where h.email_norm is not null
              and ((not p_novos and md5(h.email_norm) || ':' || coalesce(h.turma, '') > v_cur)
                   -- mesmo descarte de pessoas._casar_email_seguro (e-mail normalizado válido, até 320): as 29 linhas de e-mail inválido da carga
                   -- inicial nunca viram evento e eram relidas toda hora (medido em 16/10/2026)
                   or (p_novos and length(pessoas.norm_email(left(h.email_norm, 1000))) <= 320
                       and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'controle.aluno_historico'
                                                 and e.fonte_id = md5(h.email_norm) || ':' || coalesce(h.turma, '') and e.tipo = 'ativacao')))
            order by 1 limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas._casar_email_seguro(r.nome, r.email_norm, null, 'importacao');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_quando := case when r.primeira_compra ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                          and pg_input_is_valid(substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2), 'date')
                     then (substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2))::date::timestamp at time zone 'America/Sao_Paulo' end;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao',
            (select t.id from public.thb_turmas t where t.codigo = replace(r.turma, '.R', 'R')),
            'controle.aluno_historico', r.k, coalesce(v_quando, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'turma_fonte', left(r.turma, 20), 'data_estimada', v_quando is null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if nullif(btrim(r.turma_aurum), '') is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', (select t.id from public.thb_turmas t where t.codigo = btrim(r.turma_aurum)),
              'controle.aluno_historico', md5(r.email_norm) || ':' || left(btrim(r.turma_aurum), 20), coalesce(v_quando, now()),
              jsonb_build_object('programa', 'aurum', 'turma_fonte', left(btrim(r.turma_aurum), 20)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> '149b00e7a0d02de0b7b4a402c9e84ed7' then
    raise exception '20261016120100: o corpo gravado de carga_respondi não bate com o esperado (md5 149b00e7a0d02de0b7b4a402c9e84ed7).';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_aluno_historico(bigint,integer,boolean)'::regprocedure) <> 'cae0c7825b3ff8c98291a91c755804df' then
    raise exception '20261016120100: o corpo gravado de carga_aluno_historico não bate com o esperado (md5 cae0c7825b3ff8c98291a91c755804df).';
  end if;
  if has_function_privilege('anon', 'pessoas.carga_respondi(bigint,integer,boolean)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_respondi(bigint,integer,boolean)', 'execute')
     or has_function_privilege('service_role', 'pessoas.carga_respondi(bigint,integer,boolean)', 'execute')
     or has_function_privilege('anon', 'pessoas.carga_aluno_historico(bigint,integer,boolean)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_aluno_historico(bigint,integer,boolean)', 'execute')
     or has_function_privilege('service_role', 'pessoas.carga_aluno_historico(bigint,integer,boolean)', 'execute') then
    raise exception '20261016120100: carga_respondi ou carga_aluno_historico executável por anon/authenticated/service_role.';
  end if;
end
$g$;
