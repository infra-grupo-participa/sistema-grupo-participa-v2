-- Reversão de 20261016120100: volta pessoas.carga_respondi ao corpo anterior (md5 cc382c4c995d9d475c2e984f8203b4fd).
-- Rodar com o job pessoas-incremental desligado ou numa janela em que ele não esteja executando.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> '10823ee791c2358f7c0ead4ec2c2eb98' then
    raise exception 'reversão 20261016120100: o corpo atual não é o desta migration (md5 10823ee791c2358f7c0ead4ec2c2eb98); não sobrescrever.';
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
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta'))
            order by x.uuid::text limit p_limite loop
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

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'pessoas.carga_respondi(bigint,integer,boolean)'::regprocedure) <> 'cc382c4c995d9d475c2e984f8203b4fd' then
    raise exception 'reversão 20261016120100: o corpo não voltou ao anterior (md5 cc382c4c995d9d475c2e984f8203b4fd).';
  end if;
end
$g$;
-- depois: delete from supabase_migrations.schema_migrations where version = '20261016120100';
