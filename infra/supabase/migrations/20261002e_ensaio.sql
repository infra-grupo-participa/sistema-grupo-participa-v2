-- Ensaio da 20261002e (rodado em 30/09/2026 via execute_sql, transação desfeita por raise ZOUT).
-- Resultado: guardas 42501 ok · lista 442/405 ms · 1885 alunos, 423 a revisar · impl confirmado 201 = 175 no GPS (162 por aluno_id + 13 por pessoa_aluno_id) + 26 sócios herdando do titular · 0 e-mail na saída · sem financeiro => 0 valores.

set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to authenticated, anon;
create function pg_temp.z_q(p_passo text, p_sql text) returns void language plpgsql as $f$
declare r record; begin for r in execute p_sql loop insert into pg_temp._z_out (passo, linha) values (p_passo, r::text); end loop; end $f$;
create function pg_temp.z_err(p_passo text, p_sql text) returns void language plpgsql as $f$
begin execute p_sql; insert into pg_temp._z_out (passo, linha) values (p_passo, 'SEM ERRO');
exception when others then insert into pg_temp._z_out (passo, linha) values (p_passo, sqlstate||' '||sqlerrm); end $f$;
grant execute on function pg_temp.z_q(text,text), pg_temp.z_err(text,text) to authenticated, anon;
select pg_temp.z_q('0.ja_existe', $q$select count(*) from pg_proc where proname in ('fn_aluno_programas_safe','fn_aluno_programa_evidencias')$q$);
create function public.fn_aluno_programas_safe()
returns table (aluno_id uuid, programas text[], status_programa jsonb, revisar_motivos text[])
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_programas_safe: acesso restrito à equipe' using errcode = '42501';
  end if;
  return query
  with al as (
    select a.id, a.socio_de_aluno_id, a.espaco_instrucao, a.plano, a.turma_aurum_id,
           nullif(lower(trim(both from a.email)), '') as email_n
      from public.thb_alunos a
     where a.cancelado_em is null
  ),
  ep as (
    select e.email, e.pessoa_chave
      from fin.vw_email_pessoa e
  ),
  pag_email as (
    select t.email,
           bool_or(t.familia = 'HM' and t.produto_id <> '446345'
                   and coalesce(t.produto_nome, '') not ilike '%curso pr_tico%')   as pg_hm,
           bool_or(c.categoria in ('compra_cheia', 'diferenca'))                  as pg_impl,
           bool_or(c.categoria in ('sinal', 'reserva'))                           as pg_sinal,
           bool_or(c.categoria is not null)                                       as pg_catalogo,
           bool_or(t.familia = 'AURUM')                                           as pg_aurum,
           bool_or(t.familia = 'PROGRAMA_DIAMANTE')                               as pg_mmd
      from fin.vw_transacoes t
      left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
     where t.grupo = 'pago'
       and t.email is not null and t.email <> ''
       and (t.familia in ('HM', 'AURUM', 'PROGRAMA_DIAMANTE') or c.categoria is not null)
     group by t.email
  ),
  pag as (
    select coalesce(ep.pessoa_chave, '#email:' || pe.email) as chave,
           bool_or(pe.pg_hm) as pg_hm, bool_or(pe.pg_impl) as pg_impl, bool_or(pe.pg_sinal) as pg_sinal,
           bool_or(pe.pg_catalogo) as pg_catalogo, bool_or(pe.pg_aurum) as pg_aurum, bool_or(pe.pg_mmd) as pg_mmd
      from pag_email pe
      left join ep on ep.email = pe.email
     group by 1
  ),
  gps_ids as (
    select m.aluno_id as id from gps.membros m
    union
    select m.pessoa_aluno_id from gps.membros m where m.pessoa_aluno_id is not null
  ),
  own as (
    select al.id, al.socio_de_aluno_id,
           (g.id is not null)                                                          as no_gps,
           coalesce(p.pg_hm, false)                                                    as pg_hm,
           coalesce(p.pg_impl, false)                                                  as pg_impl,
           coalesce(p.pg_sinal, false)                                                 as pg_sinal,
           coalesce(p.pg_hm or p.pg_catalogo, false)                                   as pg_hm_algum,
           coalesce(p.pg_aurum, false)                                                 as pg_aurum,
           coalesce(p.pg_mmd, false)                                                   as pg_mmd,
           coalesce(al.espaco_instrucao = 'holding_masters_implementacao', false)      as cad_impl,
           coalesce(al.espaco_instrucao = 'aurum' or al.turma_aurum_id is not null
                    or al.plano = 'aurum', false)                                      as cad_aurum,
           coalesce(al.espaco_instrucao = 'mastermind_diamante' or al.plano = 'diamante', false) as cad_mmd,
           coalesce(al.espaco_instrucao = 'platina' or al.plano = 'platina', false)    as cad_platina,
           coalesce(al.espaco_instrucao = 'diamante_vermelho', false)                  as cad_dv
      from al
      left join ep on ep.email = al.email_n
      left join pag p on p.chave = coalesce(ep.pessoa_chave, '#email:' || al.email_n)
      left join gps_ids g on g.id = al.id
  ),
  prog as (
    select o.id, v.programa, v.status, v.motivos
      from own o
      left join own tt on tt.id = o.socio_de_aluno_id   -- pagamento do titular cobre o sócio no GPS
      cross join lateral (values
        ('implementacao',
         case when o.no_gps                 then 'confirmado'
              when o.pg_impl or o.cad_impl  then 'a_revisar'
              when o.pg_sinal               then 'reservou' end,
         array_remove(array[
           case when o.no_gps and not (o.pg_hm_algum or coalesce(tt.pg_hm_algum, false))
                then 'impl_gps_sem_pagamento' end,
           case when not o.no_gps and o.pg_impl  then 'impl_pago_fora_gps' end,
           case when not o.no_gps and o.cad_impl then 'impl_espaco_fora_gps' end], null)),
        ('hm',
         case when o.pg_hm then 'confirmado' end,
         '{}'::text[]),
        ('aurum',
         case when o.pg_aurum and o.cad_aurum then 'confirmado'
              when o.pg_aurum or o.cad_aurum  then 'a_revisar' end,
         array_remove(array[
           case when o.pg_aurum and not o.cad_aurum then 'aurum_so_pagamento' end,
           case when o.cad_aurum and not o.pg_aurum then 'aurum_so_cadastro' end], null)),
        ('mastermind_diamante',
         case when o.pg_mmd and o.cad_mmd then 'confirmado'
              when o.pg_mmd or o.cad_mmd  then 'a_revisar' end,
         array_remove(array[
           case when o.pg_mmd and not o.cad_mmd then 'mastermind_diamante_so_pagamento' end,
           case when o.cad_mmd and not o.pg_mmd then 'mastermind_diamante_so_cadastro' end], null)),
        ('diamante_vermelho',
         case when o.cad_dv then 'confirmado_cadastro' end,
         '{}'::text[]),
        ('platina',
         case when o.cad_platina then 'confirmado_cadastro' end,
         '{}'::text[])
      ) v(programa, status, motivos)
     where v.status is not null
  ),
  herd as (
    select p.id, p.programa, p.status, p.motivos from prog p
    union all
    select s.id, p.programa, p.status, p.motivos
      from own s
      join prog p on p.id = s.socio_de_aluno_id
  ),
  por_status as (
    select h.id, h.programa, h.status,
           case h.status when 'confirmado' then 1 when 'confirmado_cadastro' then 2
                         when 'a_revisar' then 3 else 4 end                             as r,
           array_agg(distinct m.x) filter (where m.x is not null)                        as motivos
      from herd h
      left join lateral unnest(h.motivos) m(x) on true
     group by h.id, h.programa, h.status
  ),
  melhor as (
    select distinct on (ps.id, ps.programa) ps.id, ps.programa, ps.status, coalesce(ps.motivos, '{}'::text[]) as motivos
      from por_status ps
     order by ps.id, ps.programa, ps.r
  ),
  efetivo as (
    select w.id, w.programa, w.status, w.motivos
      from (select mm.id, mm.programa, mm.status, mm.motivos,
                   bool_or(mm.programa = 'implementacao' and mm.status <> 'reservou')
                     over (partition by mm.id) as tem_impl
              from melhor mm) w
     where not (w.programa = 'hm' and w.tem_impl)
  ),
  mot as (
    select e.id, array_agg(distinct x.m order by x.m) as motivos
      from efetivo e
     cross join lateral unnest(e.motivos) x(m)
     group by e.id
  )
  select al.id,
         coalesce(array_agg(e.programa
                            order by array_position(array['implementacao','hm','aurum','mastermind_diamante',
                                                          'diamante_vermelho','platina']::text[], e.programa))
                  filter (where e.programa is not null), '{}'::text[]),
         coalesce(jsonb_object_agg(e.programa, e.status) filter (where e.programa is not null), '{}'::jsonb),
         coalesce(mo.motivos, '{}'::text[])
    from al
    left join efetivo e on e.id = al.id
    left join mot mo on mo.id = al.id
   group by al.id, mo.motivos
  ;
end;
$fn$;
comment on function public.fn_aluno_programas_safe() is
  '20261002e: 1 linha por aluno ativo com programas, status por programa e motivos de revisão. Só equipe (42501). '
  'Pagamentos só da conta Hotmart academy (fin.vw_transacoes), ligados por e-mail → fin.vw_email_pessoa.pessoa_chave.';
revoke all on function public.fn_aluno_programas_safe() from public, anon;
grant execute on function public.fn_aluno_programas_safe() to authenticated;
create function public.fn_aluno_programa_evidencias(p_aluno uuid)
returns table (programa text, fonte text, descricao text, data timestamptz, valor numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
declare
  v_fin          boolean;
  v_email        text;
  v_espaco       text;
  v_plano        text;
  v_turma_aurum  smallint;
  v_socio_de     uuid;
  v_chave        text;
  v_emails       text[];
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_programa_evidencias: acesso restrito à equipe' using errcode = '42501';
  end if;
  v_fin := coalesce(public.gp_pode_ver_financeiro(), false);
  select nullif(lower(trim(both from a.email)), ''), a.espaco_instrucao, a.plano, a.turma_aurum_id, a.socio_de_aluno_id
    into v_email, v_espaco, v_plano, v_turma_aurum, v_socio_de
    from public.thb_alunos a
   where a.id = p_aluno;
  if not found then
    return;
  end if;
  if v_email is not null then
    select i.pessoa_chave into v_chave from fin.identidade i where i.no = 'e:' || v_email;
    if v_chave is not null then
      select array_agg(ep.email) into v_emails from fin.vw_email_pessoa ep where ep.pessoa_chave = v_chave;
    end if;
    v_emails := coalesce(v_emails, array[v_email]);
  end if;
  return query
  with tx as (
    select t.produto_id, t.produto_nome, t.familia, t.grupo, t.valor_cobrado,
           coalesce(t.aprovado_em, t.pedido_em) as quando,
           c.categoria, ev.nome as evento_nome
      from fin.vw_transacoes t
      left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
      left join fin.evento_ofertas eo on eo.oferta_codigo = t.oferta_codigo
      left join fin.eventos ev on ev.id = eo.evento_id
     where t.email = any(coalesce(v_emails, '{}'::text[]))
  ),
  tx_cls as (
    select tx.*,
           case when tx.categoria in ('compra_cheia', 'diferenca', 'sinal', 'reserva') then 'implementacao'
                when tx.familia = 'HM' and tx.produto_id <> '446345'
                     and coalesce(tx.produto_nome, '') not ilike '%curso pr_tico%'       then 'hm'
                when tx.familia = 'AURUM'                                                then 'aurum'
                when tx.familia = 'PROGRAMA_DIAMANTE'                                    then 'mastermind_diamante'
           end as prog,
           case when tx.evento_nome is not null or tx.familia = 'EVENTOS' then 'evento'
                when tx.familia = 'ACELERA'                                then 'acelera'
                else 'hotmart' end as fnt
      from tx
  )
  select z.programa, z.fonte, z.descricao, z.data, z.valor
    from (
      select 'implementacao'::text as programa, 'gps'::text as fonte, 'Está no GPS'::text as descricao,
             min(m.criado_em) as data, null::numeric as valor
        from gps.membros m
       where m.aluno_id = p_aluno or m.pessoa_aluno_id = p_aluno
      having count(*) > 0
      union all
      select v.prog, 'cadastro', v.descr, null::timestamptz, null::numeric
        from (values
          (case v_espaco when 'holding_masters_implementacao' then 'implementacao'
                         when 'holding_masters'               then 'hm'
                         when 'aurum'                         then 'aurum'
                         when 'mastermind_diamante'           then 'mastermind_diamante'
                         when 'platina'                       then 'platina'
                         when 'diamante_vermelho'             then 'diamante_vermelho' end,
           'Espaço de instrução: ' || v_espaco),
          (case v_plano when 'aurum' then 'aurum' when 'diamante' then 'mastermind_diamante'
                        when 'platina' then 'platina' end,
           case when v_plano <> 'aluno' then 'Plano: ' || v_plano end),
          ('aurum',
           case when v_turma_aurum is not null then 'Turma Aurum: ' || coalesce(
             (select tu.codigo::text from public.thb_turmas tu where tu.id = v_turma_aurum), v_turma_aurum::text) end)
        ) v(prog, descr)
       where v.descr is not null
      union all
      select x.prog, x.fnt,
             coalesce(x.evento_nome, x.produto_nome, 'Produto ' || x.produto_id) || ' — ' ||
             case when x.grupo = 'pago' and x.categoria in ('sinal', 'reserva') then 'sinal'
                  when x.grupo = 'pago'                                         then 'pagou'
                  else 'não pagou (' || x.grupo || ')' end,
             x.quando,
             case when v_fin then x.valor_cobrado end
        from tx_cls x
       where x.prog is not null or x.fnt in ('evento', 'acelera')
      union all
      select null::text, 'socio_de', 'Sócio de outro aluno: herda os programas do titular', null::timestamptz, null::numeric
       where v_socio_de is not null
    ) z
   order by z.data desc nulls last, z.programa, z.fonte;
end;
$fn$;
comment on function public.fn_aluno_programa_evidencias(uuid) is
  '20261002e: evidências dos programas de um aluno (GPS, cadastro, Hotmart academy, evento, Acelera, sócio). '
  'Só equipe (42501); valor só com gp_pode_ver_financeiro(); sem e-mail/documento.';
revoke all on function public.fn_aluno_programa_evidencias(uuid) from public, anon;
grant execute on function public.fn_aluno_programa_evidencias(uuid) to authenticated;
select pg_temp.z_q('1.grants', $q$select p.proname, r, has_function_privilege(r, p.oid, 'execute') from pg_proc p, unnest(array['anon','authenticated']) r where p.proname in ('fn_aluno_programas_safe','fn_aluno_programa_evidencias') order by 1,2$q$);
select set_config('z.eq', (select p.id::text from public.perfis p where p.status='ativo' and p.email ilike '%@advmais.com' and p.cargo in ('dev','admin') order by p.id limit 1), true);
select set_config('z.eqsf', (select p.id::text from public.perfis p where p.status='ativo' and p.email ilike '%@advmais.com' and p.cargo='operador' order by p.id limit 1), true);
update public.perfis set areas = array_remove(areas,'financeiro') where id = current_setting('z.eqsf')::uuid;
select set_config('z.fora', coalesce((select p.id::text from public.perfis p where not (p.email ilike '%@advmais.com') order by p.id limit 1), gen_random_uuid()::text), true);
select set_config('z.gps', (select a.id::text from public.thb_alunos a join gps.membros m on m.aluno_id = a.id where a.cancelado_em is null order by a.id limit 1), true);
set local role anon;
select pg_temp.z_err('2.guarda_anon_lista', 'select count(*) from public.fn_aluno_programas_safe()');
reset role;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.fora'), 'role','authenticated')::text, true);
select pg_temp.z_err('2.guarda_nao_equipe_lista', 'select count(*) from public.fn_aluno_programas_safe()');
select pg_temp.z_err('2.guarda_nao_equipe_evid', format('select count(*) from public.fn_aluno_programa_evidencias(%L)', current_setting('z.gps')));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eq'), 'role','authenticated')::text, true);
select set_config('z.t0', clock_timestamp()::text, true);
create temp table _z_prog on commit drop as select * from public.fn_aluno_programas_safe();
select pg_temp.z_q('3.tempo_lista_ms', $q$select round(extract(epoch from clock_timestamp() - current_setting('z.t0')::timestamptz)*1000)$q$);
select set_config('z.t0', clock_timestamp()::text, true);
select pg_temp.z_q('3.tempo_lista_2a_ms', $q$select count(*), round(extract(epoch from clock_timestamp() - current_setting('z.t0')::timestamptz)*1000) from public.fn_aluno_programas_safe()$q$);
select pg_temp.z_q('4.linhas', $q$select count(*), count(distinct aluno_id), count(*) filter (where cardinality(programas)=0) sem_programa, count(*) filter (where cardinality(programas)>1) multi from _z_prog$q$);
select pg_temp.z_q('4.por_status', $q$select k, v, count(*) from _z_prog, jsonb_each_text(status_programa) e(k,v) group by 1,2 order by 1,2$q$);
select pg_temp.z_q('4.motivos', $q$select m, count(*) from _z_prog, unnest(revisar_motivos) m group by 1 order by 2 desc$q$);
select pg_temp.z_q('4.alunos_a_revisar', $q$select count(*) from _z_prog where cardinality(revisar_motivos)>0$q$);
select pg_temp.z_q('4.impl_vs_gps', $q$select (select count(*) from _z_prog where status_programa->>'implementacao'='confirmado') impl_conf,
  (select count(distinct a.id) from public.thb_alunos a join gps.membros m on m.aluno_id=a.id where a.cancelado_em is null) gps_ativos$q$);
select set_config('z.t0', clock_timestamp()::text, true);
select pg_temp.z_q('5.evid_gps', format($q$select programa, fonte, count(*), count(valor) com_valor from public.fn_aluno_programa_evidencias(%L) group by 1,2 order by 1,2$q$, current_setting('z.gps')));
select pg_temp.z_q('5.tempo_evid_ms', $q$select round(extract(epoch from clock_timestamp() - current_setting('z.t0')::timestamptz)*1000)$q$);
select pg_temp.z_q('5.evid_email_na_saida', format($q$select count(*) from public.fn_aluno_programa_evidencias(%L) where descricao ~ '@'$q$, current_setting('z.gps')));
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.eqsf'), 'role','authenticated')::text, true);
select pg_temp.z_q('6.sem_fin_valor', format($q$select count(*), count(valor) com_valor from public.fn_aluno_programa_evidencias(%L)$q$, current_setting('z.gps')));
reset role;
do $z$ begin raise exception 'ZOUT%', (select string_agg(passo||' | '||linha, E'\n' order by em) from pg_temp._z_out); end $z$;
