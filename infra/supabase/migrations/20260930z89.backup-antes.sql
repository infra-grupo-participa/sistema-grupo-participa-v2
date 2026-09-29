-- BACKUP z89 antes do apply — gerado 2026-09-29 18:30:28 (America/Sao_Paulo), projeto mbvybujpkwuorhtdzcde
-- 20 funcoes distintas (bloco 6: 4; bloco 6b: 17 entradas, fn_fin_funis repetida do bloco 6) + 2 views + relacl

-- FUNCAO fin.assinatura_hm_por_pessoa()  md5(prosrc)=8af4af488136d4b1efd3cfd8adb621a0
CREATE OR REPLACE FUNCTION fin.assinatura_hm_por_pessoa()
 RETURNS TABLE(pessoa text, nome text, emails text[], documento text, telefone text, cobrancas integer, mensalidades_pagas integer, pago numeric, primeira_em timestamp with time zone, primeira date, ultima_paga date, ainda_paga boolean, atraso_120d_n integer, atraso_120d_valor numeric, atraso_antigo_n integer, atraso_antigo_valor numeric, turma_calendario text, turma_cadastro text, turma_origem text, origem_regra text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with tx as materialized (
    select coalesce(ip.pessoa_chave, 'e:' || t.email) pessoa, t.email, t.nome, t.oferta_codigo, t.recorrencia,
           t.transacao, t.grupo, coalesce(t.pedido_em, t.aprovado_em) cobrada_em, t.pedido_em, t.dia_aprovado,
           t.valor_oferta, h.comprador_documento doc, h.comprador_telefone tel
      from fin.vw_transacoes t
      join fin.hotmart_transacoes h on h.transacao = t.transacao
      left join fin.identidade ip on ip.no = 'e:' || t.email
     where t.produto_id = '3507214' and t.email is not null
  ), agg as (
    select x.pessoa,
           (array_agg(x.nome order by x.cobrada_em desc nulls last) filter (where x.nome is not null))[1] nome,
           array_agg(distinct x.email) emails,
           (array_agg(x.doc order by x.cobrada_em desc nulls last) filter (where x.doc is not null))[1] doc,
           (array_agg(x.tel order by x.cobrada_em desc nulls last) filter (where x.tel is not null))[1] tel,
           count(*)::int cobrancas,
           count(*) filter (where x.grupo = 'pago')::int pagas,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) pago,
           min(x.cobrada_em) primeira_em,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ultima_paga
      from tx x
     group by x.pessoa
  ), parc as (
    select x.pessoa, bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde, max(x.valor_oferta) valor
      from tx x
     group by x.pessoa, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), dv as (
    select p.pessoa,
           count(*) filter (where p.desde >= now() - interval '120 days')::int n_atual,
           coalesce(sum(p.valor) filter (where p.desde >= now() - interval '120 days'), 0) v_atual,
           count(*) filter (where p.desde < now() - interval '120 days')::int n_antigo,
           coalesce(sum(p.valor) filter (where p.desde < now() - interval '120 days'), 0) v_antigo
      from parc p
     where p.atrasou and not p.quitada
     group by p.pessoa
  ), em as (
    select a.pessoa, unnest(a.emails) email from agg a
    union
    select i.pessoa_chave, substr(i.no, 3) from fin.identidade i
     where i.no like 'e:%' and i.pessoa_chave in (select a.pessoa from agg a)
  ), cad as (
    select e.pessoa,
           (array_agg(split_part(tt.codigo, '.', 1)
                      order by substring(split_part(tt.codigo, '.', 1) from '[0-9]+')::int nulls last))[1] turma
      from em e
      join public.thb_alunos al on lower(trim(al.email)) = e.email
      join public.thb_turmas tt on tt.id = al.turma_id
     group by e.pessoa
  ), orig as (
    select a.pessoa, cal.turma t_cal, c.turma t_cad,
           substring(cal.turma from '[0-9]+')::int n_cal, substring(c.turma from '[0-9]+')::int n_cad
      from agg a
      left join cad c on c.pessoa = a.pessoa
      left join lateral (
        select split_part(ac.turma, '.', 1) turma
          from fin.acoes ac
         where ac.produto = 'HM' and ac.turma is not null
           and a.primeira_em >= ac.inicio and a.primeira_em < coalesce(ac.fim, ac.inicio + interval '1 day')
         order by ac.prioridade, ac.inicio desc
         limit 1) cal on true
  )
  select a.pessoa, a.nome, a.emails, a.doc, a.tel,
         a.cobrancas, a.pagas, a.pago,
         a.primeira_em, (a.primeira_em at time zone 'America/Sao_Paulo')::date, a.ultima_paga,
         coalesce(a.ultima_paga >= (now() at time zone 'America/Sao_Paulo')::date - 45, false),
         coalesce(d.n_atual, 0), coalesce(d.v_atual, 0), coalesce(d.n_antigo, 0), coalesce(d.v_antigo, 0),
         o.t_cal, o.t_cad,
         case when o.t_cal is null then o.t_cad
              when o.t_cad is null then o.t_cal
              when coalesce(o.n_cad, 2147483647) < coalesce(o.n_cal, 2147483647) then o.t_cad
              else o.t_cal end,
         case when o.t_cal is null and o.t_cad is null then 'sem origem'
              when o.t_cal is null then 'cadastro'
              when o.t_cad is null then 'calendário'
              when o.t_cal = o.t_cad then 'calendário e cadastro'
              when coalesce(o.n_cad, 2147483647) < coalesce(o.n_cal, 2147483647) then 'cadastro'
              else 'calendário' end
    from agg a
    left join dv d on d.pessoa = a.pessoa
    left join orig o on o.pessoa = a.pessoa;
$function$
;

-- FUNCAO fin.hotmart_sync_enfileirar(integer)  md5(prosrc)=972725823548d1945a0edfc415a8ed61
CREATE OR REPLACE FUNCTION fin.hotmart_sync_enfileirar(p_dias integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
  select p.produto_id, g::date, least(g::date + 59, v_hoje), 'rotina'
    from fin.produtos p
    cross join generate_series(v_hoje - p_dias, v_hoje, interval '60 days') g
   where p.sincroniza
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$
;

-- FUNCAO fin.informados_catalogo()  md5(prosrc)=8a89da0000b51c0f4154ff94297c1ead
CREATE OR REPLACE FUNCTION fin.informados_catalogo()
 RETURNS TABLE(produto_id text, nome text, chave text)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p.produto_id, p.nome, fin.informado_chave_nome(p.nome) from fin.produtos p
  union
  select p.produto_id, p.nome, fin.informado_chave_nome(t.produto_nome)
    from fin.produtos p
    cross join lateral (select h.produto_nome from fin.hotmart_transacoes h
                         where h.produto_id = p.produto_id and h.aprovado_em is not null and h.produto_nome is not null
                         order by h.aprovado_em desc limit 1) t
$function$
;

-- FUNCAO fin.informados_cobertura(timestamp with time zone)  md5(prosrc)=4eeab481dc6455df29ffb69cda492a5b
CREATE OR REPLACE FUNCTION fin.informados_cobertura(p_corte timestamp with time zone)
 RETURNS TABLE(ref text, de date, ate date)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_dia date;
  v_tol int;
begin
  if p_corte is null then
    raise exception 'fin.informados_cobertura: corte obrigatório' using errcode = 'P0001';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null then
    raise exception 'fin.informados_cobertura: premissa tolerancia_atraso_dias ausente' using errcode = 'P0002';
  end if;

  return query
  with g as (
    select r.id, r.produto_ids, r.acordo_desde de,
           max(r.data_prevista) over (partition by coalesce(r.identificador1, r.id::text), r.produto_ids, r.acordo_desde)
             + v_tol ate
      from fin.recebimentos_informados r
     where r.via_hotmart and r.arquivado_em is null
  ), par as materialized (
    select distinct o.email, o.oferta_codigo, g.de, g.ate
      from g
      join fin.informados_alvos() a on a.id = g.id
      cross join lateral (
        select lower(trim(h.comprador_email)) email, h.oferta_codigo
          from fin.hotmart_transacoes h
         where lower(trim(h.comprador_email)) = any (a.emails)
           and h.produto_id = any (g.produto_ids)
           and h.recorrencia is not null and h.oferta_codigo is not null
           and h.status in ('APPROVED','COMPLETE')
           and h.aprovado_em > p_corte - interval '120 days' and h.aprovado_em <= p_corte
        union
        select lower(trim(h.comprador_email)), h.oferta_codigo
          from fin.hotmart_transacoes h
         where regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs)
           and h.produto_id = any (g.produto_ids)
           and h.recorrencia is not null and h.oferta_codigo is not null and h.comprador_email is not null
           and h.status in ('APPROVED','COMPLETE')
           and h.aprovado_em > p_corte - interval '120 days' and h.aprovado_em <= p_corte
      ) o
  ), chave as materialized (
    select x.email, x.oferta_codigo, fin.chave_opaca('rc:' || x.email || '|' || x.oferta_codigo) ref
      from (select distinct par.email, par.oferta_codigo from par) x
  )
  select chave.ref, par.de, par.ate
    from par join chave on chave.email = par.email and chave.oferta_codigo = par.oferta_codigo;
end $function$
;

-- FUNCAO fin.informados_situacao(timestamp with time zone)  md5(prosrc)=21153124466d8491aab7e2cfc103f1c4
CREATE OR REPLACE FUNCTION fin.informados_situacao(p_corte timestamp with time zone)
 RETURNS TABLE(id uuid, situacao text, recebido_hotmart numeric, acumulado_acordo numeric, valor_provisionado numeric, data_efetiva date)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_dia  date;
  v_tol  int;
  v_conc numeric;
begin
  if p_corte is null then
    raise exception 'fin.informados_situacao: corte obrigatório' using errcode = 'P0001';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor into v_conc from fin.premissas_receber pr
   where pr.chave = 'tolerancia_conciliacao' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null or v_conc is null then
    raise exception 'fin.informados_situacao: premissa de tolerância ausente em fin.premissas_receber' using errcode = 'P0002';
  end if;

  return query
  with viva as (
    select r.id, r.data_prevista, r.valor, r.via_hotmart, r.produto_ids, r.acordo_desde, r.baixa_manual_em,
           sum(r.valor) over (partition by coalesce(r.identificador1, r.id::text), r.produto_ids, r.acordo_desde
                              order by r.data_prevista range between unbounded preceding and current row) acum
      from fin.recebimentos_informados r
     where r.arquivado_em is null
  ), rec as (
    select a.id, s.recebido
      from fin.informados_alvos() a
      join viva v on v.id = a.id
      cross join lateral (
        select coalesce(sum(t.liquido), 0) recebido
          from fin.vw_transacoes t
         where t.transacao = any (array(
                 select h.transacao from fin.hotmart_transacoes h
                  where lower(trim(h.comprador_email)) = any (a.emails)
                    and h.status in ('APPROVED','COMPLETE') and h.produto_id = any (v.produto_ids)
                 union
                 select h.transacao from fin.hotmart_transacoes h
                  where regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs)
                    and h.status in ('APPROVED','COMPLETE') and h.produto_id = any (v.produto_ids)))
           and t.aprovado_em <= p_corte
           and t.dia_aprovado >= v.acordo_desde
      ) s
  ), sit as (
    select v.id, v.data_prevista, v.valor, v.via_hotmart, v.acum, rec.recebido,
           case when v.baixa_manual_em is not null then 'baixado_fora'
                when v.via_hotmart and coalesce(rec.recebido, 0) >= v.acum * (1 - v_conc) then 'realizado_hotmart'
                when v.data_prevista + v_tol < v_dia then 'em_atraso_cobrar'
                else 'a_receber' end s
      from viva v
      left join rec on rec.id = v.id
  )
  select sit.id, sit.s,
         case when sit.via_hotmart then coalesce(sit.recebido, 0) end,
         sit.acum,
         case when sit.s in ('baixado_fora','realizado_hotmart') then 0::numeric
              when sit.via_hotmart then greatest(0::numeric, least(sit.valor, sit.acum - coalesce(sit.recebido, 0)))
              else sit.valor end,
         case when sit.s = 'a_receber' then greatest(sit.data_prevista, v_dia + 1) end
    from sit
  union all
  select r.id, 'arquivado'::text, null::numeric, null::numeric, 0::numeric, null::date
    from fin.recebimentos_informados r
   where r.arquivado_em is not null;
end $function$
;

-- FUNCAO fin.nome_da_pessoa(text)  md5(prosrc)=fb0f2a86d08d8bb642a4b98f148a762b
CREATE OR REPLACE FUNCTION fin.nome_da_pessoa(p_email text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with em as (
    select distinct coalesce(substr(i2.no, 3), lower(btrim(p_email))) email
      from (select lower(btrim(p_email)) e) x
      left join fin.identidade i on i.no = 'e:' || x.e
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
  ), cpfs as (
    select distinct regexp_replace(h.comprador_documento, '\D', '', 'g') cpf
      from em join fin.hotmart_transacoes h on lower(btrim(h.comprador_email)) = em.email
     where length(regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g')) = 11
  ), nomes as (
    select btrim(h.comprador_nome) nome from em join fin.hotmart_transacoes h on lower(btrim(h.comprador_email)) = em.email
    union all
    select btrim(h.comprador_nome) from cpfs join fin.hotmart_transacoes h
        on regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = cpfs.cpf
    union all
    select btrim(a.nome) from em join public.thb_alunos a on lower(btrim(a.email)) = em.email
    union all
    select btrim(c.nome) from em join public.compradores c on lower(btrim(c.email)) = em.email
  )
  select fin.nome_proprio(fin.nome_sem_repeticao(n.nome))
    from nomes n
   where not fin.nome_ruim(n.nome)
   group by lower(fin.nome_sem_repeticao(n.nome)), n.nome
   order by count(*) desc, length(n.nome) desc
   limit 1
$function$
;

-- FUNCAO fin.recalcular_identidade()  md5(prosrc)=d57232b856cd387e4137bc12c0fea902
CREATE OR REPLACE FUNCTION fin.recalcular_identidade()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rodada int := 0; v_mudou bigint; r jsonb;
begin
  truncate fin.identidade_aresta;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'd:' || t.comprador_documento, 'hotmart'
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null and length(t.comprador_documento) in (11, 14)
     and t.status in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'u:' || t.comprador_ucode, 'hotmart'
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null and t.comprador_ucode is not null
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'd:' || regexp_replace(c.documento, '\D', '', 'g'), 'compradores'
    from public.compradores c
   where c.email is not null and length(regexp_replace(coalesce(c.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'u:' || c.hotmart_ucode, 'compradores'
    from public.compradores c where c.email is not null and c.hotmart_ucode is not null
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(a.email)), 'd:' || regexp_replace(a.documento, '\D', '', 'g'), 'thb_alunos'
    from public.thb_alunos a
   where a.email is not null and length(regexp_replace(coalesce(a.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(a.email)), 'e:' || lower(trim(c.email)), 'thb_alunos.comprador_id'
    from public.thb_alunos a join public.compradores c on c.id = a.comprador_id
   where a.email is not null and c.email is not null and lower(trim(a.email)) <> lower(trim(c.email))
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c1.email)), 'e:' || lower(trim(c2.email)), 'cs.hm_comprador_alias'
    from cs.hm_comprador_alias al
    join public.compradores c1 on c1.id = al.comprador_id
    join public.compradores c2 on c2.id = al.canonico_id
   where c1.email is not null and c2.email is not null
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(i.email)), 'd:' || regexp_replace(i.documento, '\D', '', 'g'), 'cs.hotmart_identidade'
    from cs.hotmart_identidade i
   where i.email is not null and length(regexp_replace(coalesce(i.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(u.email), 'e:' || lower(trim(a.email)), 'gps.membros(titular)'
    from gps.membros m
    join auth.users u on u.id = m.user_id
    join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
   where m.papel = 'titular' and u.email is not null and a.email is not null
     and lower(u.email) <> lower(trim(a.email))
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(ci.email)), 'd:' || regexp_replace(ci.documento, '\D', '', 'g'), 'cs.central_alunos_import'
    from cs.central_alunos_import ci
   where ci.email is not null and length(regexp_replace(coalesce(ci.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  -- (removida) rede.perfis.aluno_thb_email é autodeclarado: não é fonte de identidade
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(su.email)), 'e:' || lower(u.email), 'sip_users.auth_id'
    from public.sip_users su join auth.users u on u.id = su.auth_id
   where su.email is not null and u.email is not null and lower(trim(su.email)) <> lower(u.email)
  on conflict do nothing;

  truncate fin.identidade_revisao;
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'documento ligado a ' || x.n || ' e-mails (provável escritório/contador) — não juntado', x.n
    from (select b as no, count(distinct a) n from fin.identidade_aresta where b like 'd:%' and a like 'e:%' group by b) x
   where x.n > 6;
  -- z42: ponte entre CPFs (e-mail de escritório/cônjuge) nunca junta duas pessoas
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'ponte entre CPFs: e-mail ligado a ' || x.n || ' CPFs diferentes — não juntado', null
    from (select e.no, count(distinct e.cpf) n
            from (select a no, b cpf from fin.identidade_aresta where a like 'e:%' and b ~ '^d:\d{11}$'
                  union select b, a from fin.identidade_aresta where b like 'e:%' and a ~ '^d:\d{11}$') e
           where e.cpf not in (select valor from fin.identidade_bloqueio)
             and e.cpf not in (select no from fin.identidade_revisao)
           group by e.no having count(distinct e.cpf) > 1) x
  on conflict (no) do nothing;
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'CNPJ ponte entre CPFs: alcança ' || x.n || ' CPFs pelos e-mails — não juntado', null
    from (select c.b no, count(distinct p.b) n
            from fin.identidade_aresta c
            join fin.identidade_aresta p on p.a = c.a and p.b ~ '^d:\d{11}$'
           where c.b ~ '^d:\d{14}$' and c.a like 'e:%'
             and c.a not in (select no from fin.identidade_revisao)
             and p.b not in (select valor from fin.identidade_bloqueio)
             and p.b not in (select no from fin.identidade_revisao)
           group by c.b having count(distinct p.b) > 1) x
  on conflict (no) do nothing;
  insert into fin.identidade_revisao (no, motivo, emails)
  select b.valor, 'bloqueado: ' || b.motivo, null from fin.identidade_bloqueio b
  on conflict (no) do nothing;
  delete from fin.identidade_aresta ar
   where ar.a in (select no from fin.identidade_revisao) or ar.b in (select no from fin.identidade_revisao);

  truncate fin.identidade;
  insert into fin.identidade (no, pessoa_chave)
  select n, n from (select a n from fin.identidade_aresta union select b from fin.identidade_aresta) x;
  insert into fin.identidade (no, pessoa_chave)
  select distinct 'e:' || lower(trim(t.comprador_email)), 'e:' || lower(trim(t.comprador_email))
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null
  on conflict (no) do nothing;

  loop
    v_rodada := v_rodada + 1;
    if v_rodada > 40 then
      raise exception 'fin.recalcular_identidade: não convergiu em 40 rodadas. Nada confirmado.';
    end if;
    with viz as (
      select ar.a no, i.pessoa_chave rot from fin.identidade_aresta ar join fin.identidade i on i.no = ar.b
      union all
      select ar.b, i.pessoa_chave from fin.identidade_aresta ar join fin.identidade i on i.no = ar.a
    ), menor as (select no, min(rot) rot from viz group by no)
    update fin.identidade i set pessoa_chave = m.rot
      from menor m where m.no = i.no and m.rot < i.pessoa_chave;
    get diagnostics v_mudou = row_count;
    exit when v_mudou = 0;
  end loop;

  truncate fin.identidade_sugestao;
  -- CPF digitado em tentativa NÃO paga não junta ninguém (qualquer um digita o CPF de outro),
  -- mas vira sugestão para a equipe conferir: é o caso comum de quem tenta com um e-mail e paga com outro.
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(x.p, y.p), greatest(x.p, y.p), 'mesmo_documento_tentativa', x.doc
    from (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes_identidade t
            join fin.identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
             and t.status not in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
             and 'd:' || t.comprador_documento not in (select no from fin.identidade_revisao)) x
    join (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes_identidade t
            join fin.identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
          union
          select substr(i.no, 3), i.pessoa_chave from fin.identidade i where i.no like 'd:%') y
      on y.doc = x.doc and y.p <> x.p
  on conflict do nothing;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_telefone', right(t1.comprador_telefone, 11)
    from fin.hotmart_transacoes_identidade t1
    join fin.hotmart_transacoes_identidade t2 on right(t2.comprador_telefone, 11) = right(t1.comprador_telefone, 11)
                                   and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join fin.identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join fin.identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(t1.comprador_telefone) >= 10 and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_nome', t1.comprador_nome
    from fin.hotmart_transacoes_identidade t1
    join fin.hotmart_transacoes_identidade t2
      on lower(public.unaccent(trim(t2.comprador_nome))) = lower(public.unaccent(trim(t1.comprador_nome)))
     and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join fin.identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join fin.identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(trim(t1.comprador_nome)) >= 8 and position(' ' in trim(t1.comprador_nome)) > 0
     and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;

  update fin.identidade set calculado_em = now();
  select jsonb_build_object(
    'rodadas', v_rodada,
    'nos', (select count(*) from fin.identidade),
    'pessoas', (select count(distinct pessoa_chave) from fin.identidade),
    'emails_hotmart', (select count(distinct lower(trim(comprador_email))) from fin.hotmart_transacoes),
    'pessoas_hotmart', (select count(distinct i.pessoa_chave) from fin.identidade i
                          where i.no in (select 'e:' || lower(trim(comprador_email)) from fin.hotmart_transacoes)),
    'arestas', (select count(*) from fin.identidade_aresta),
    'revisao', (select count(*) from fin.identidade_revisao),
    'sugestoes', (select count(*) from fin.identidade_sugestao)) into r;
  return r;
end $function$
;

-- FUNCAO fin.resolver_ofertas_eventos(boolean,integer,text[])  md5(prosrc)=8ebbc75c70885e9d4bee429abe24b2e2
CREATE OR REPLACE FUNCTION fin.resolver_ofertas_eventos(p_gravar boolean DEFAULT false, p_dias integer DEFAULT 45, p_ofertas text[] DEFAULT NULL::text[])
 RETURNS TABLE(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
-- z83: contrato (saldo/migração/renovação), ingresso pelo próximo evento da categoria, palavras-chave no nome,
--      janela só com >= 3 vendas pagas e nome que não contradiz.
-- z85: palavra-chave só vale para evento que começa até 1ª venda + 7 dias (ingresso isento: pré-venda);
--      sck conta só vendas PAGAS; nome/palavras/ingresso exigem >= 1 venda paga;
--      sugestão da fila: nome > janela única > ingresso > palavras > sck > janela mais curta.
declare
  v_desde timestamptz := now() - make_interval(days => greatest(coalesce(p_dias, 45), 1));
  v_cod   text[];
  v_of    jsonb := '{}'::jsonb;
  v_tem_ofertas boolean := to_regclass('fin.ofertas') is not null;
  v_res   jsonb;
begin
  if p_ofertas is not null and coalesce(p_gravar, false) then
    raise exception 'p_ofertas é só para conferência: use p_gravar = false.' using errcode = '22023';
  end if;

  if p_ofertas is not null then
    select coalesce(array_agg(distinct c.oc), '{}') into v_cod
      from unnest(p_ofertas) c(oc) where c.oc is not null;
  else
    select coalesce(array_agg(distinct t.oferta_codigo), '{}') into v_cod
      from fin.hotmart_transacoes t
     where t.pedido_em >= v_desde
       and t.oferta_codigo is not null
       and t.status in ('APPROVED','COMPLETE','PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED')
       and coalesce(t.recorrencia, 1) <= 1
       and not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
       and not exists (select 1 from fin.oferta_evento_fila f
                        where f.oferta_codigo = t.oferta_codigo and f.status in ('confirmada','rejeitada'));
  end if;
  if cardinality(v_cod) = 0 then
    return;
  end if;

  if v_tem_ofertas then
    execute 'select coalesce(jsonb_object_agg(o.oferta_codigo, jsonb_build_object(''nome'', o.nome, ''main'', o.is_main_offer)), ''{}''::jsonb)
               from fin.ofertas o where o.oferta_codigo = any($1)'
       into v_of using v_cod;
  end if;

  with tx as (
    select t.transacao tr, t.oferta_codigo oc, t.produto_id, t.produto_nome, t.origem_sck sck,
           (coalesce(t.aprovado_em, t.pedido_em) at time zone 'America/Sao_Paulo')::date d,
           t.status in ('APPROVED','COMPLETE') pago,
           coalesce(p.familia, 'OUTRO') familia
      from unnest(v_cod) c(oc)
      join fin.hotmart_transacoes t on t.oferta_codigo = c.oc
      left join fin.produtos p on p.produto_id = t.produto_id
     where t.status in ('APPROVED','COMPLETE','PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED',
                        'OVERDUE','PROTESTED','REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK')
       and coalesce(t.recorrencia, 1) <= 1
       and coalesce(t.aprovado_em, t.pedido_em) is not null
  ), ofr0 as (
    select x.oc, min(x.produto_id) produto_id, min(x.produto_nome) produto_nome, min(x.familia) familia,
           count(*)::int n, count(*) filter (where x.pago)::int n_pagas,
           count(*) filter (where coalesce(x.sck, '') <> '')::int n_com_sck,
           min(x.d) primeira, max(x.d) ultima,
           percentile_disc(0.9) within group (order by x.d) p90
      from tx x
     group by x.oc
  ), ofr as (
    select o.*,
           v_of -> o.oc ->> 'nome' oferta_nome,
           fin.oferta_normaliza(v_of -> o.oc ->> 'nome') nome_n,
           fin.oferta_palavras(v_of -> o.oc ->> 'nome') kw,
           exists (select 1 from fin.evento_produtos ep where ep.produto_id = o.produto_id and ep.papel = 'ingresso') eh_ingresso
      from ofr0 o
  ), ev as (
    select e.id, e.nome, e.categoria, e.setor, e.inicio,
           coalesce(e.carrinho_inicio, e.inicio) ref_de,
           coalesce(e.carrinho_inicio, e.inicio) - 2 ja_de, e.venda_ate ja_ate,
           coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de,
           fin.oferta_normaliza(e.codigo) cod_n,
           fin.oferta_normaliza(e.nome) evn_n,
           fin.oferta_palavras(coalesce(e.nome, '') || ' ' || coalesce(e.codigo, '')) kw
      from fin.eventos e
  ), sv as (
    select x.oc, x.tr, min(a.evento_id) ev_id
      from tx x
      join fin.acoes a on a.evento_id is not null and a.sck_regex is not null and x.sck ~* a.sck_regex
     where x.pago
     group by x.oc, x.tr
    having count(distinct a.evento_id) = 1
  ), sck as (
    select distinct on (s.oc) s.oc, s.ev_id, count(*)::int n_sck
      from sv s
     group by s.oc, s.ev_id
     order by s.oc, count(*) desc, s.ev_id
  ), pw as (
    select x.oc, e.id, e.ja_de, e.ja_ate, count(*)::int n
      from tx x
      join ev e on e.setor = 'educacao' and x.d between e.ja_de and e.ja_ate
               and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
     group by x.oc, e.id, e.ja_de, e.ja_ate
  ), pd as (
    select distinct a.oc
      from pw a
      join pw b on b.oc = a.oc and a.ja_ate < b.ja_de
      join ofr o on o.oc = a.oc
     where a.n >= greatest(1, ceil(o.n * 0.1)) and b.n >= greatest(1, ceil(o.n * 0.1))
  ), jw as (
    select o.oc, e.id, e.nome, e.ja_de, e.ja_ate,
           count(*) filter (where x.d between e.ja_de and e.ja_ate + 7)::int n_dentro
      from ofr o
      join ev e on e.setor = 'educacao' and o.primeira between e.ja_de and e.ja_ate
               and not (o.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
      join tx x on x.oc = o.oc
     where not o.eh_ingresso
     group by o.oc, e.id, e.nome, e.ja_de, e.ja_ate
  ), jwa as (
    select j.oc, count(*)::int n_ev, min(j.id) id, min(j.n_dentro) n_dentro,
           (array_agg(j.id order by (j.ja_ate - j.ja_de), j.id))[1] melhor,
           jsonb_agg(jsonb_build_object('evento_id', j.id, 'nome', j.nome, 'de', j.ja_de, 'ate', j.ja_ate,
                                        'vendas_dentro', j.n_dentro) order by (j.ja_ate - j.ja_de), j.id) cands
      from jw j
     group by j.oc
  ), ing as (
    select x.oc, e.id, count(*)::int n
      from tx x
      join ofr o on o.oc = x.oc and o.eh_ingresso
      join fin.evento_produtos ep on ep.produto_id = x.produto_id and ep.papel = 'ingresso'
      join ev e on e.categoria = ep.categoria and x.d between e.ing_de and e.ja_ate
     group by x.oc, e.id
  ), ingr as (
    select distinct on (i.oc) i.oc, i.id, i.n,
           jsonb_agg(jsonb_build_object('evento_id', i.id, 'vendas', i.n)) over (partition by i.oc) cands
      from ing i
     order by i.oc, i.n desc, i.id
  ), nm as (
    select o.oc, count(*)::int n_ev, min(e.id) id,
           jsonb_agg(jsonb_build_object('evento_id', e.id, 'nome', e.nome) order by e.id) cands
      from ofr o
      join ev e on o.primeira between e.ja_de and e.ja_ate
     where length(o.nome_n) > 2
       and ((length(e.cod_n) >= 3 and position(' ' || e.cod_n || ' ' in ' ' || o.nome_n || ' ') > 0)
         or (length(e.evn_n) >= 8 and position(' ' || e.evn_n || ' ' in ' ' || o.nome_n || ' ') > 0))
     group by o.oc
  ), kws as (
    select o.oc, e.id, e.nome,
           cardinality(array(select unnest(o.kw) intersect select unnest(e.kw))) score,
           (o.eh_ingresso or e.inicio <= o.primeira + 7) no_prazo
      from ofr o
      join ev e on o.primeira between e.ref_de - 60 and e.ja_ate + 60
     where cardinality(o.kw) > 0 and cardinality(e.kw) > 0
  ), kwr as (
    select distinct on (k.oc) k.oc, k.id, k.nome, k.score,
           coalesce(lead(k.score) over (partition by k.oc order by k.score desc, k.id), 0) segundo
      from kws k
     where k.score > 0
     order by k.oc, k.score desc, k.id
  ), kwp as (
    select distinct on (k.oc) k.oc, k.id, k.nome, k.score,
           coalesce(lead(k.score) over (partition by k.oc order by k.score desc, k.id), 0) segundo
      from kws k
     where k.score > 0 and k.no_prazo
     order by k.oc, k.score desc, k.id
  ), dec as (
    select o.*, s.ev_id sck_ev, coalesce(s.n_sck, 0) n_sck,
           j.n_ev j_n, j.id j_id, j.n_dentro j_dentro, j.melhor j_melhor, j.cands j_cands,
           m.n_ev nm_n, m.id nm_id, m.cands nm_cands,
           g.id ing_id, g.n ing_n, g.cands ing_cands,
           kp.id kw_id, kp.nome kw_nome, coalesce(kp.score, 0) kw_score, coalesce(kp.segundo, 0) kw_segundo,
           case when k.score > k.segundo then k.id end kw_melhor,
           case when kp.score > kp.segundo then kp.id end kw_sug,
           (kp.score >= 2 and kp.score > kp.segundo) kw_liga,
           (o.nome_n ~ '(^| )(saldo|migracao|renovacao)( |$)') contrato,
           coalesce((v_of -> o.oc ->> 'main')::boolean, false) main,
           (o.ultima - o.primeira) > 60 espalhada,
           (pd.oc is not null and not o.eh_ingresso) duas_janelas
      from ofr o
      left join sck s on s.oc = o.oc
      left join jwa j on j.oc = o.oc
      left join nm m on m.oc = o.oc
      left join ingr g on g.oc = o.oc
      left join kwr k on k.oc = o.oc
      left join kwp kp on kp.oc = o.oc
      left join pd on pd.oc = o.oc
  ), cls as (
    select d.*,
           coalesce(d.contrato and coalesce(d.nm_n, 0) <> 1, false) r_contrato,
           coalesce(d.contrato and d.nm_n = 1, false) r_contrato_fila,
           coalesce(d.main or d.espalhada or d.duas_janelas, false) r_perene,
           coalesce(d.n_pagas >= 3 and d.sck_ev is not null and d.n_sck >= 0.8 * d.n_pagas, false) r_sck,
           coalesce(d.nm_n = 1 and d.n_pagas >= 1, false) r_nome,
           coalesce(d.kw_liga and d.n_pagas >= 1, false) r_kw,
           coalesce(d.eh_ingresso and d.n_pagas >= 1 and d.ing_id is not null and d.ing_n >= 0.9 * d.n
              and (d.kw_melhor is null or d.kw_melhor = d.ing_id), false) r_ing,
           coalesce(not d.eh_ingresso and d.j_n = 1 and d.j_dentro >= 0.9 * d.n and d.n_pagas >= 3
              and (d.kw_melhor is null or d.kw_melhor = d.j_id), false) r_jan
      from dec d
  ), res as (
    select c.*,
           case when c.r_contrato then 'contrato'
                when c.r_contrato_fila then 'fila'
                when c.r_perene then 'perene'
                when c.r_sck or c.r_nome or c.r_kw or c.r_ing or c.r_jan then 'ligar'
                when c.n >= 2 then 'fila'
                else 'ignorar' end dcs,
           case when c.r_contrato then 'contrato:nome'
                when c.r_contrato_fila then 'fila:contrato_com_nome_de_evento'
                when c.r_perene then
                  'perene:' || concat_ws('+', case when c.main then 'main_offer' end,
                                              case when c.espalhada then 'mais_de_60_dias' end,
                                              case when c.duas_janelas then 'duas_janelas' end)
                when c.r_sck then 'auto:sck'
                when c.r_nome or c.r_kw then 'auto:nome'
                when c.r_ing or c.r_jan then 'auto:janela'
                when c.n >= 2 then
                  case when c.n_pagas = 0 then 'fila:sem_venda_paga'
                       when c.eh_ingresso and c.ing_id is null then 'fila:sem_evento'
                       when c.eh_ingresso and c.ing_n < 0.9 * c.n then 'fila:ingresso_dividido'
                       when c.eh_ingresso then 'fila:nome_contradiz'
                       when c.j_n is null then 'fila:sem_evento'
                       when c.j_n > 1 then 'fila:varios_eventos'
                       when c.kw_melhor is not null and c.kw_melhor <> c.j_id then 'fila:nome_contradiz'
                       when c.n_pagas < 3 then 'fila:poucas_vendas'
                       else 'fila:sinal_fraco' end
                else 'sem_sinal' end sn,
           case when c.r_sck then c.sck_ev
                when c.r_nome then c.nm_id
                when c.r_kw then c.kw_id
                when c.r_ing then c.ing_id
                when c.r_jan then c.j_id end ev_ligar,
           coalesce(case when c.nm_n = 1 then c.nm_id end,
                    case when c.j_n = 1 then c.j_id end,
                    case when c.eh_ingresso then c.ing_id end,
                    c.kw_sug, c.sck_ev, c.j_melhor) sug,
           case when c.eh_ingresso then c.ing_id is null else c.j_n is null end sem_evento
      from cls c
  )
  select jsonb_agg(jsonb_build_object(
           'oferta_codigo', r.oc,
           'decisao', r.dcs,
           'sinal', r.sn,
           'evento_id', case when r.dcs = 'ligar' then r.ev_ligar when r.dcs = 'fila' then r.sug end,
           'detalhe', jsonb_build_object(
              'produto_id', r.produto_id, 'produto_nome', r.produto_nome, 'oferta_nome', r.oferta_nome,
              'n_vendas', r.n, 'n_pagas', r.n_pagas, 'n_com_sck', r.n_com_sck,
              'primeira_venda', r.primeira, 'ultima_venda', r.ultima, 'p90_venda', r.p90,
              'regra', case when r.r_ing then 'ingresso' when r.r_jan then 'janela'
                            when r.r_kw and not r.r_nome then 'palavras' when r.r_nome then 'nome' end,
              'contrato', r.contrato,
              'sck', jsonb_build_object('evento_id', r.sck_ev, 'vendas', r.n_sck, 'base', 'pagas'),
              'janela', jsonb_build_object('n_eventos', coalesce(r.j_n, 0), 'candidatos', r.j_cands),
              'ingresso', jsonb_build_object('eh_ingresso', r.eh_ingresso, 'evento_id', r.ing_id, 'vendas', r.ing_n,
                                             'candidatos', r.ing_cands),
              'nome', jsonb_build_object('n_eventos', coalesce(r.nm_n, 0), 'candidatos', r.nm_cands,
                                         'fonte', case when v_tem_ofertas then 'fin.ofertas' else 'fin.ofertas ausente' end),
              'palavras', jsonb_build_object('oferta', to_jsonb(r.kw), 'evento_id', r.kw_id, 'evento', r.kw_nome,
                                             'comuns', r.kw_score, 'segundo', r.kw_segundo,
                                             'lider_sem_prazo', r.kw_melhor),
              'perene', jsonb_build_object('main_offer', r.main, 'mais_de_60_dias', r.espalhada, 'duas_janelas', r.duas_janelas),
              'sugestao_evento_id', case when r.dcs = 'fila' then r.sug end,
              'proposta_evento', case when r.dcs = 'fila' and r.sem_evento and not r.contrato then jsonb_build_object(
                  'nome', coalesce(r.oferta_nome, r.produto_nome),
                  'categoria', (select ep.categoria from fin.evento_produtos ep
                                 where ep.produto_id = r.produto_id
                                 order by (ep.papel = 'ingresso') desc, ep.categoria limit 1),
                  'carrinho_inicio', r.primeira,
                  'venda_ate', r.p90) end,
              'calculado_em', now())))
    into v_res
    from res r;

  if v_res is null then
    return;
  end if;

  if coalesce(p_gravar, false) then
    insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao, origem, sinais, criado_em)
    select r.evento_id, r.oferta_codigo, 'ligada sozinha pelo resolvedor (' || r.sinal || ')', r.sinal, r.detalhe, now()
      from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
     where r.decisao = 'ligar' and r.evento_id is not null
    on conflict do nothing;

    insert into fin.oferta_evento_fila as f (oferta_codigo, produto_id, sugestao_evento_id, proposta_evento, sinais, n_vendas)
    select r.oferta_codigo, r.detalhe ->> 'produto_id', r.evento_id, r.detalhe -> 'proposta_evento', r.detalhe,
           (r.detalhe ->> 'n_vendas')::int
      from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
     where r.decisao = 'fila'
    on conflict on constraint oferta_evento_fila_pkey do update
       set produto_id = excluded.produto_id,
           sugestao_evento_id = excluded.sugestao_evento_id,
           proposta_evento = excluded.proposta_evento,
           sinais = excluded.sinais,
           n_vendas = excluded.n_vendas
     where f.status = 'pendente';
  end if;

  return query
  select r.oferta_codigo, r.decisao, r.evento_id, r.sinal, r.detalhe
    from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
   order by r.decisao, r.oferta_codigo;
end
$function$
;

-- FUNCAO fn_fin_board_hotmart()  md5(prosrc)=4487f430664b69ef88d22c0ff0eafdae
CREATE OR REPLACE FUNCTION public.fn_fin_board_hotmart()
 RETURNS TABLE(contato_hm_id uuid, origem text, encontrado boolean, pessoa_chave text, cards_da_pessoa integer, vendas_pagas integer, pago_bruto numeric, taxa_hotmart numeric, coproducao numeric, liquido numeric, cobrado_cliente numeric, juros numeric, parcelas_max integer, forma_pagamento_principal text, ultimo_pagamento_em date, ultimo_pagamento_valor numeric, parcelas_devidas integer, valor_devido numeric, devido_antigo numeric, estornos integer, valor_estornado numeric, falta_no_board integer, valor_falta_no_board numeric, board_sem_hotmart integer, diverge boolean, sincronizado_em timestamp with time zone, assinatura_mensalidades integer, assinatura_valor numeric, assinatura_de date, assinatura_ate date, assinatura_ativa boolean, outros_pagamentos integer, outros_valor numeric, outros_formas text, outros_ultimo date, telefone text, boleto_aberto_n integer, boleto_aberto_valor numeric, boleto_aberto_em date, boleto_aberto_categoria text, boleto_aberto_metodo text, boletos_abertos jsonb)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with card as (
    select b.contato_hm_id, b.origem, b.comprador_id, i.pessoa_chave pessoa
      from cs.vw_fin_board b
      left join public.compradores c on c.id = b.comprador_id
      left join fin.identidade i on i.no = 'e:' || lower(trim(c.email))
  ), nc as (
    select k.pessoa, k.origem, count(*)::int n from card k where k.pessoa is not null group by k.pessoa, k.origem
  ), em as (
    -- todos os e-mails da pessoa, por família do card
    select distinct n.pessoa, n.origem familia, substr(i.no, 3) email
      from nc n
      join fin.identidade i on i.pessoa_chave = n.pessoa and i.no like 'e:%'
  ), tx as (
    select e.pessoa, e.familia, t.transacao, t.grupo, t.metodo, t.parcelas, t.valor_oferta, t.valor_cobrado,
           t.juros, t.taxa_hotmart, t.liquido, t.aprovado_em, t.dia_aprovado,
           not exists (select 1 from cs.hm_pagamentos hp where hp.transacao = t.transacao) sem_board
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = e.familia
     where t.grupo in ('pago','estornado')
       -- periodo_do_card (z46): compra anterior ao 1º pagamento do card é turma de origem, não falta
       and coalesce(t.aprovado_em, t.pedido_em) >= coalesce(
             (select min(hp.pago_em) from card k2 join cs.hm_pagamentos hp on hp.comprador_id = k2.comprador_id
               where k2.pessoa = e.pessoa and k2.origem = e.familia
                 and cs.fn_hm_pagamento_do_produto(hp.oferta_codigo, k2.origem)) - interval '1 day',
             '-infinity'::timestamptz)
       and exists (select 1 from public.hm_product_catalog cat
                    where cat.offer_code = t.oferta_codigo and cat.categoria in ('sinal','diferenca','compra_cheia'))
  ), v as (
    select x.pessoa, x.familia,
           count(*) filter (where x.grupo = 'pago')::int pagas,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) bruto,
           coalesce(sum(x.taxa_hotmart) filter (where x.grupo = 'pago'), 0) taxa,
           greatest(coalesce(sum(x.valor_oferta - coalesce(x.taxa_hotmart, 0) - x.liquido) filter (where x.grupo = 'pago'), 0), 0) copro,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liq,
           coalesce(sum(x.valor_cobrado) filter (where x.grupo = 'pago'), 0) cobrado,
           coalesce(sum(x.juros) filter (where x.grupo = 'pago'), 0) juros,
           max(x.parcelas) filter (where x.grupo = 'pago') parcelas_max,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ult_em,
           (array_agg(x.valor_oferta order by x.aprovado_em desc nulls last) filter (where x.grupo = 'pago'))[1] ult_valor,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'estornado'), 0) estornado,
           count(*) filter (where x.grupo = 'pago' and x.sem_board)::int falta,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago' and x.sem_board), 0) valor_falta
      from tx x
     group by x.pessoa, x.familia
  ), fp as (
    select distinct on (m.pessoa, m.familia) m.pessoa, m.familia, m.metodo
      from (select y.pessoa, y.familia, y.metodo, count(*) n, max(y.aprovado_em) ult
              from tx y where y.grupo = 'pago' and y.metodo is not null
             group by y.pessoa, y.familia, y.metodo) m
     order by m.pessoa, m.familia, m.n desc, m.ult desc nulls last
  ), dv as (
    select 'HM'::text familia, d.pessoa, d.n_atual, d.valor_atual, d.valor_antigo from fin.parcelas_devidas('HM') d
    union all
    select 'AURUM'::text, d.pessoa, d.n_atual, d.valor_atual, d.valor_antigo from fin.parcelas_devidas('AURUM') d
  ), bsh as (
    select k.contato_hm_id, k.origem, count(*)::int n
      from card k
      join cs.hm_pagamentos p on p.comprador_id = k.comprador_id and p.origem = 'hotmart'
     where cs.fn_hm_pagamento_do_produto(p.oferta_codigo, k.origem)
       and (not exists (select 1 from fin.vw_transacoes t where t.transacao = p.transacao)
            or exists (select 1 from fin.vw_transacoes t where t.transacao = p.transacao and t.grupo = 'estornado'))
     group by k.contato_hm_id, k.origem
  ), ass as (
    select e.pessoa, count(*)::int n, coalesce(sum(t.valor_oferta), 0) valor,
           min(t.dia_aprovado) de, max(t.dia_aprovado) ate
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = 'HM'
     where e.familia = 'HM' and t.grupo = 'pago' and t.oferta_modo = 'SUBSCRIPTION'
     group by e.pessoa
  ), ou as (
    select e.pessoa, e.familia, count(*)::int n, coalesce(sum(t.valor_oferta), 0) valor, max(t.dia_aprovado) ult,
           string_agg(distinct fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta), ' · ') formas
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = e.familia
     where t.grupo = 'pago'
       and not (e.familia = 'HM' and t.oferta_modo is not distinct from 'SUBSCRIPTION')
       and not exists (select 1 from public.hm_product_catalog cat
                        where cat.offer_code = t.oferta_codigo and cat.categoria in ('sinal','diferenca','compra_cheia'))
     group by e.pessoa, e.familia
  ), bol as (
    -- z76: + lista (jsonb) de todos os boletos/Pix em aberto, mais recente primeiro
    select e.pessoa, e.familia, count(*)::int n, coalesce(sum(t.valor_oferta), 0) valor, max(t.dia_pedido) em,
           (array_agg(fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta) order by t.pedido_em desc))[1] categoria,
           (array_agg(t.metodo order by t.pedido_em desc))[1] metodo,
           jsonb_agg(jsonb_build_object(
             'valor', t.valor_oferta,
             'categoria', (select min(c.categoria::text) from public.hm_product_catalog c where c.offer_code = t.oferta_codigo),
             'rotulo', fin.oferta_categoria(t.oferta_codigo, t.oferta_modo, t.valor_oferta),
             'oferta_codigo', t.oferta_codigo,
             'metodo', t.metodo,
             'pedido_em', t.dia_pedido) order by t.pedido_em desc) lista
      from em e
      join fin.vw_transacoes t on t.email = e.email and t.familia = e.familia
     where t.grupo = 'em_aberto' and t.dia_pedido >= (now() at time zone 'America/Sao_Paulo')::date - 30
     group by e.pessoa, e.familia
  ), tel as (
    select distinct on (e.pessoa) e.pessoa, h.comprador_telefone
      from em e
      join fin.hotmart_transacoes h on lower(trim(h.comprador_email)) = e.email
     where h.comprador_telefone is not null
     order by e.pessoa, h.pedido_em desc
  ), tel_card as (
    select k.contato_hm_id,
           coalesce(nullif(trim(cp.telefone), ''),
                    (select nullif(trim(a.telefone), '') from public.thb_alunos a
                      where lower(trim(a.email)) = lower(trim(cp.email)) and nullif(trim(a.telefone), '') is not null limit 1)) telefone
      from card k
      join public.compradores cp on cp.id = k.comprador_id
  ), sinc as (
    select max(h.atualizado_em) em, (now() at time zone 'America/Sao_Paulo')::date hoje from fin.hotmart_transacoes h
  )
  select k.contato_hm_id, k.origem, k.pessoa is not null,
         case when k.pessoa is not null then fin.chave_opaca(k.pessoa) end,
         coalesce(n.n, 0),
         coalesce(v.pagas, 0), coalesce(v.bruto, 0), coalesce(v.taxa, 0), coalesce(v.copro, 0), coalesce(v.liq, 0),
         coalesce(v.cobrado, 0), coalesce(v.juros, 0), v.parcelas_max, fp.metodo,
         v.ult_em, v.ult_valor,
         coalesce(dv.n_atual, 0), coalesce(dv.valor_atual, 0), coalesce(dv.valor_antigo, 0),
         coalesce(v.estornos, 0), coalesce(v.estornado, 0),
         coalesce(v.falta, 0), coalesce(v.valor_falta, 0), coalesce(bsh.n, 0),
         case when k.origem = 'HM' and k.pessoa is not null
              then coalesce(v.falta, 0) > 0 or coalesce(bsh.n, 0) > 0 end,
         sinc.em,
         coalesce(ass.n, 0), coalesce(ass.valor, 0), ass.de, ass.ate,
         case when k.origem = 'HM' and k.pessoa is not null
              then coalesce(ass.ate >= sinc.hoje - 45, false) and coalesce(dv.n_atual, 0) = 0 end,
         coalesce(ou.n, 0), coalesce(ou.valor, 0), ou.formas, ou.ult,
         case when coalesce(public.gp_pode_ver_cpf(), false) then coalesce(tl.comprador_telefone, tc.telefone)
              when coalesce(tl.comprador_telefone, tc.telefone) is not null
                then '···' || right(regexp_replace(coalesce(tl.comprador_telefone, tc.telefone), '\D', '', 'g'), 4) end,
         coalesce(bo.n, 0), coalesce(bo.valor, 0), bo.em, bo.categoria, bo.metodo,
         bo.lista
    from card k
    cross join sinc
    left join nc n on n.pessoa = k.pessoa and n.origem = k.origem
    left join v on v.pessoa = k.pessoa and v.familia = k.origem
    left join fp on fp.pessoa = k.pessoa and fp.familia = k.origem
    left join dv on dv.pessoa = k.pessoa and dv.familia = k.origem
    left join bsh on bsh.contato_hm_id = k.contato_hm_id and bsh.origem = k.origem
    left join ass on ass.pessoa = k.pessoa and k.origem = 'HM'
    left join ou on ou.pessoa = k.pessoa and ou.familia = k.origem
    left join bol bo on bo.pessoa = k.pessoa and bo.familia = k.origem
    left join tel tl on tl.pessoa = k.pessoa
    left join tel_card tc on tc.contato_hm_id = k.contato_hm_id
   order by k.origem, coalesce(dv.valor_atual, 0) desc, coalesce(v.valor_falta, 0) desc;
end $function$
;

-- FUNCAO fn_fin_caixa_hotmart_totais(date,date)  md5(prosrc)=534eb1c96a79dc3b1aa82eeb29cd7080
CREATE OR REPLACE FUNCTION public.fn_fin_caixa_hotmart_totais(p_inicio date, p_fim date)
 RETURNS TABLE(liquido numeric, retido numeric, custo_antecipacao numeric, entra_rapido numeric, retido_a_liberar numeric, liquido_total numeric, n_vendas integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_hoje    date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini_ts  timestamptz;
  v_fim_ts  timestamptz;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_inicio is null or p_fim is null then
    raise exception 'Informe início e fim.' using errcode = '22023';
  end if;
  if p_fim < p_inicio then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  if p_fim - p_inicio > 400 then raise exception 'Janela máxima de 400 dias.' using errcode = '22023'; end if;
  v_ini_ts := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim_ts := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  return query
  with d as (
    select t.dia_aprovado dia, coalesce(sum(t.liquido), 0) liquido, count(*)::int n
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts
     group by t.dia_aprovado
  )
  select coalesce(sum(d.liquido), 0), coalesce(sum(r.retido), 0), coalesce(sum(r.custo_antecipacao), 0),
         coalesce(sum(r.entra_rapido), 0),
         coalesce(sum(case when r.libera_em > v_hoje then r.retido else 0 end), 0),
         coalesce(sum(r.liquido_total), 0),
         coalesce(sum(d.n), 0)::int
    from d
    left join lateral fin.recebimento(d.dia, d.liquido) r on true;
end $function$
;

-- FUNCAO fn_fin_caixa_hotmart(date,date)  md5(prosrc)=6b3798631d4fa6bfaaed8c7e89c549b3
CREATE OR REPLACE FUNCTION public.fn_fin_caixa_hotmart(p_inicio date, p_fim date)
 RETURNS TABLE(dia date, liquido numeric, retido numeric, custo_antecipacao numeric, entra_rapido numeric, entra_em date, retido_a_liberar numeric, libera_em date, situacao_d2 text, situacao_retido text, n_vendas integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_hoje    date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ini_ts  timestamptz;
  v_fim_ts  timestamptz;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_inicio is null or p_fim is null then
    raise exception 'Informe início e fim.' using errcode = '22023';
  end if;
  if p_fim < p_inicio then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  if p_fim - p_inicio > 400 then raise exception 'Janela máxima de 400 dias.' using errcode = '22023'; end if;
  v_ini_ts := p_inicio::timestamp at time zone 'America/Sao_Paulo';
  v_fim_ts := (p_fim + 1)::timestamp at time zone 'America/Sao_Paulo';
  return query
  with d as (
    select t.dia_aprovado dia, coalesce(sum(t.liquido), 0) liquido, count(*)::int n_vendas
      from fin.vw_transacoes t
     where t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em >= v_ini_ts and t.aprovado_em < v_fim_ts
     group by t.dia_aprovado
  )
  select d.dia, d.liquido, r.retido, r.custo_antecipacao, r.entra_rapido, r.entra_em,
         case when r.libera_em > v_hoje then r.retido else 0 end,
         r.libera_em,
         case when r.entra_em <= v_hoje then 'recebido' else 'a_receber' end,
         case when r.libera_em <= v_hoje then 'liberado' else 'em_garantia' end,
         d.n_vendas
    from d
    left join lateral fin.recebimento(d.dia, d.liquido) r on true
   order by d.dia;
end $function$
;

-- FUNCAO fn_fin_diamante_servicos()  md5(prosrc)=c34dceaf09c1031f41c45d6c91ac31e3
CREATE OR REPLACE FUNCTION public.fn_fin_diamante_servicos()
 RETURNS TABLE(pessoa_chave text, nome text, nome_compra text, nome_empresa boolean, cliente_cadastro boolean, email text, emails text[], telefone text, nivel text, servico text, ofertas text[], desconhecida boolean, primeira_paga date, ultima_paga date, pagamentos integer, total_pago numeric, liquido numeric, mensalidade numeric, devendo_n integer, devendo_valor numeric, devendo_desde date, antigo_n integer, antigo_valor numeric, antigo_desde date, coberto_n integer, coberto_valor numeric, estornos integer, tentativas integer, ultima_tentativa date, meses jsonb, situacao text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with base as (
    select t.*, ip.pessoa_chave grafo,
           coalesce(o.servico, dp.servico, 'desconhecida') serv, coalesce(o.geracao, dp.geracao) geracao,
           (o.oferta_codigo is null and dp.produto_id is null) descon
      from fin.vw_transacoes t
      join fin.produtos p on p.produto_id = t.produto_id and p.papel = 'servico'
      left join fin.identidade ip on ip.no = 'e:' || t.email
      left join fin.diamante_ofertas o on o.oferta_codigo = t.oferta_codigo
      left join fin.diamante_produtos dp on dp.produto_id = t.produto_id
     where t.email is not null
  ), cli_grafo as (
    select i.pessoa_chave grafo, min(dc.cliente_slug) slug
      from fin.identidade i join fin.diamante_clientes dc on 'e:' || dc.email = i.no
     group by i.pessoa_chave having count(distinct dc.cliente_slug) = 1
  ), tx as (
    select coalesce('c:' || dc.cliente_slug, 'c:' || cg.slug, b.grafo, 'e:' || b.email) pessoa, b.*
      from base b
      left join fin.diamante_clientes dc on dc.email = b.email
      left join cli_grafo cg on cg.grafo = b.grafo
  ), parc as (
    select x.pessoa, x.serv, x.geracao, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao) parcela,
           bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'pago') paga, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde,
           (array_agg(x.valor_oferta order by x.pedido_em))[1] valor
      from tx x
     group by x.pessoa, x.serv, x.geracao, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), extra as (
    select x.pessoa, x.serv, sum(x.valor_oferta - p.valor) valor
      from tx x
      join parc p on p.pessoa = x.pessoa and p.email = x.email and p.oferta_codigo = x.oferta_codigo
                 and p.parcela = coalesce(x.recorrencia::text, 't:' || x.transacao)
     where x.grupo = 'pago' and x.valor_oferta > 1.5 * p.valor and coalesce(x.geracao, '') not in ('regularizacao','acordo')
     group by x.pessoa, x.serv
  ), cred_serv as (
    select c.pessoa, c.serv, sum(c.valor) valor from (
      select e.pessoa, e.serv, e.valor from extra e
      union all
      select x.pessoa, x.serv, x.valor_oferta from tx x where x.grupo = 'pago' and x.geracao = 'regularizacao'
    ) c group by c.pessoa, c.serv
  ), cred_acordo as (
    select x.pessoa, sum(x.valor_oferta) valor from tx x where x.grupo = 'pago' and x.geracao = 'acordo' group by x.pessoa
  ), aberta as (
    select p.*, sum(p.valor) over (partition by p.pessoa, p.serv order by p.desde, p.parcela rows unbounded preceding) acum_serv
      from parc p
     where p.atrasou and not p.quitada and coalesce(p.geracao, '') not in ('regularizacao','acordo')
  ), aberta2 as (
    select a.*, (a.acum_serv <= coalesce(cs.valor, 0) + 0.01) coberta_serv
      from aberta a left join cred_serv cs on cs.pessoa = a.pessoa and cs.serv = a.serv
  ), aberta3 as (
    select a.*, sum(case when a.coberta_serv then 0 else a.valor end)
                  over (partition by a.pessoa order by a.desde, a.serv, a.parcela rows unbounded preceding) acum_pessoa
      from aberta2 a
  ), aberta4 as (
    select a.*, (a.coberta_serv or a.acum_pessoa <= coalesce(ca.valor, 0) + 0.01) coberta
      from aberta3 a left join cred_acordo ca on ca.pessoa = a.pessoa
  ), devida as (
    select a.* from aberta4 a where not a.coberta
  ), cob as (
    select a.pessoa, a.serv, count(*)::int n, sum(a.valor) valor from aberta4 a where a.coberta group by a.pessoa, a.serv
  ), div as (
    select d.pessoa, d.serv,
           count(*) filter (where d.desde >= now() - interval '120 days')::int n,
           coalesce(sum(d.valor) filter (where d.desde >= now() - interval '120 days'), 0) valor,
           min(d.desde) filter (where d.desde >= now() - interval '120 days') desde,
           count(*) filter (where d.desde < now() - interval '120 days')::int an,
           coalesce(sum(d.valor) filter (where d.desde < now() - interval '120 days'), 0) avalor,
           min(d.desde) filter (where d.desde < now() - interval '120 days') adesde
      from devida d group by d.pessoa, d.serv
  ), mes as (
    select m.pessoa, m.serv, jsonb_object_agg(m.mes, m.estado) meses
      from (select p.pessoa, p.serv, to_char(p.desde at time zone 'America/Sao_Paulo', 'YYYY-MM') mes,
                   case when bool_or(dv.parcela is not null) then 'atrasado'
                        when bool_or(p.paga) then 'pago'
                        when bool_or(cb.parcela is not null) then 'coberto'
                        when bool_or(p.quitada) then 'estornado'
                        else 'tentativa' end estado
              from parc p
              left join devida dv on dv.pessoa = p.pessoa and dv.serv = p.serv and dv.email = p.email
                                 and dv.oferta_codigo = p.oferta_codigo and dv.parcela = p.parcela
              left join aberta4 cb on cb.coberta and cb.pessoa = p.pessoa and cb.serv = p.serv and cb.email = p.email
                                 and cb.oferta_codigo = p.oferta_codigo and cb.parcela = p.parcela
             where p.desde >= now() - interval '24 months'
             group by 1, 2, 3) m
     group by m.pessoa, m.serv
  ), agg as (
    select x.pessoa, x.serv,
           array_agg(distinct x.oferta_codigo) ofertas,
           bool_or(x.descon) descon,
           min(x.dia_aprovado) filter (where x.grupo = 'pago') prim,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ult,
           count(*) filter (where x.grupo = 'pago')::int pagos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) total,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liq,
           (array_agg(x.valor_oferta order by x.aprovado_em desc) filter (where x.grupo = 'pago' and coalesce(x.geracao, '') <> 'regularizacao'))[1] mens,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           count(*)::int tentativas,
           max(x.dia_pedido) ult_tent
      from tx x
     group by x.pessoa, x.serv
  ), ems as (
    select distinct z.pessoa, z.email from (
      select x.pessoa, x.email from tx x
      union select x.pessoa, substr(i.no, 3) from tx x join fin.identidade i on i.pessoa_chave = x.grafo and i.no like 'e:%'
      union select 'c:' || dc.cliente_slug, dc.email from fin.diamante_clientes dc
    ) z where z.pessoa in (select pessoa from tx)
  ), aluno as (
    select e.pessoa,
           (array_agg(a.nivel_resultado order by array_position(
              array['diamante_vermelho','diamante','platina','ouro','profissional','em_formacao','pessoal','iniciante'], a.nivel_resultado)
              ) filter (where a.nivel_resultado is not null))[1] nivel,
           (array_agg(a.nome order by (a.nivel_resultado is null), a.nome))[1] nome
      from ems e join public.thb_alunos a on lower(trim(a.email)) = e.email
     group by e.pessoa
  ), pes as (
    select x.pessoa,
           (array_agg(x.nome order by x.pedido_em desc))[1] nome_hotmart,
           (array_agg(x.email order by x.pedido_em desc))[1] email,
           (array_agg(h.comprador_telefone order by x.pedido_em desc) filter (where h.comprador_telefone is not null))[1] tel
      from tx x join fin.hotmart_transacoes h on h.transacao = x.transacao
     group by x.pessoa
  ), cad as (
    select 'c:' || dc.cliente_slug pessoa, min(dc.nome) nome from fin.diamante_clientes dc group by dc.cliente_slug
  )
  select a.pessoa,
         fin.nome_proprio(coalesce(cd.nome, al.nome, pe.nome_hotmart)),
         case when fin.nome_proprio(pe.nome_hotmart) is distinct from fin.nome_proprio(coalesce(cd.nome, al.nome, pe.nome_hotmart))
              then fin.nome_proprio(pe.nome_hotmart) end,
         fin.nome_de_empresa(coalesce(cd.nome, al.nome, pe.nome_hotmart)),
         (cd.nome is not null),
         pe.email,
         (select array_agg(e.email order by e.email) from ems e where e.pessoa = a.pessoa),
         case when coalesce(public.gp_pode_ver_cpf(), false) then pe.tel
              when pe.tel is not null then '···' || right(regexp_replace(pe.tel, '\D', '', 'g'), 4) end,
         al.nivel,
         a.serv, a.ofertas, a.descon,
         a.prim, a.ult, a.pagos, a.total, a.liq, a.mens,
         coalesce(d.n, 0), coalesce(d.valor, 0), (d.desde at time zone 'America/Sao_Paulo')::date,
         coalesce(d.an, 0), coalesce(d.avalor, 0), (d.adesde at time zone 'America/Sao_Paulo')::date,
         coalesce(cb.n, 0), coalesce(cb.valor, 0), a.estornos, a.tentativas, a.ult_tent, coalesce(ms.meses, '{}'::jsonb),
         case when coalesce(d.n, 0) > 0 then 'devendo'
              when a.pagos = 0 then 'nunca_pagou'
              when a.ult >= v_hoje - 40 then case when coalesce(d.an, 0) > 0 then 'devendo' else 'em_dia' end
              when coalesce(d.an, 0) > 0 then 'parou_devendo'
              else 'encerrado' end
    from agg a
    join pes pe on pe.pessoa = a.pessoa
    left join cad cd on cd.pessoa = a.pessoa
    left join aluno al on al.pessoa = a.pessoa
    left join div d on d.pessoa = a.pessoa and d.serv = a.serv
    left join cob cb on cb.pessoa = a.pessoa and cb.serv = a.serv
    left join mes ms on ms.pessoa = a.pessoa and ms.serv = a.serv;
end $function$
;

-- FUNCAO fn_fin_funil_compradores(bigint)  md5(prosrc)=4d37da9419f77f6bb6e1f959130160ba
CREATE OR REPLACE FUNCTION public.fn_fin_funil_compradores(p_evento_id bigint)
 RETURNS TABLE(papel text, produto text, oferta text, dia date, situacao text, valor numeric, liquido numeric, nome text, email text, telefone text, parcelas integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with e as (
    select x.*, coalesce((select max(y.venda_ate) from fin.eventos y where y.categoria = x.categoria and y.inicio < x.inicio) + 1, x.inicio - 60) ing_de
      from fin.eventos x where x.id = p_evento_id
  )
  select p.papel, t.produto_nome, t.oferta_codigo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date,
         t.grupo,
         round(t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2),
         round(coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
               * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2),
         fin.nome_exibicao(t.nome, t.email), t.email,
         case when coalesce(public.gp_pode_ver_cpf(), false) then h.comprador_telefone
              when h.comprador_telefone is not null then '···' || right(h.comprador_telefone, 4) end,
         t.parcelas
    from e
    join lateral (
      -- z85: produtos da categoria + produtos de ofertas ligadas a ESTE evento que a categoria não tem
      select ep.papel, ep.produto_id, true na_categoria
        from fin.evento_produtos ep
       where ep.categoria = e.categoria
      union all
      select distinct
             case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'ingresso')
                  and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = t0.produto_id and p2.papel = 'oferta')
                 then 'ingresso' else 'oferta' end,
             t0.produto_id, false
        from fin.evento_ofertas eo0
        join fin.hotmart_transacoes t0 on t0.oferta_codigo = eo0.oferta_codigo
       where eo0.evento_id = e.id
         and not exists (select 1 from fin.evento_produtos ep where ep.categoria = e.categoria and ep.produto_id = t0.produto_id)
    ) p on true
    join fin.vw_transacoes t on t.produto_id = p.produto_id
     and (p.na_categoria or exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)) and t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1
     and ((p.papel = 'oferta' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))
       or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between e.ing_de and e.venda_ate))))
    join fin.hotmart_transacoes h on h.transacao = t.transacao
   order by p.papel desc, t.aprovado_em;
end $function$
;

-- FUNCAO fn_fin_funis()  md5(prosrc)=c4a28cc58fd5fc380be41203d154325d
CREATE OR REPLACE FUNCTION public.fn_fin_funis()
 RETURNS TABLE(evento_id bigint, nome text, categoria text, setor text, inicio date, fim date, carrinho_inicio date, venda_ate date, ingresso_de date, ingressos integer, ingressos_bruto numeric, ingressos_liquido numeric, oferta_vendas integer, oferta_compradores integer, oferta_estornos integer, oferta_bruto numeric, oferta_liquido numeric, compradores integer, bruto numeric, liquido numeric, ref_vendas integer, ref_valor numeric, ref_tipo text, ref_fonte text, observacao text, conta_ausente boolean, liquido_conferencia numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with ev as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    select t.transacao, t.produto_id, t.oferta_codigo, t.email, t.grupo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date dia,
           t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end valor,
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
             * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end liq
      from fin.vw_transacoes t
     where t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1 and t.email is not null
  ), casado as (
    select e.id, p.papel, x.*
      from ev e
      join fin.evento_produtos p on p.categoria = e.categoria
      join tx x on x.produto_id = p.produto_id
       and ((p.papel = 'oferta'   and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
                                            and x.dia between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))
         or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = x.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = x.oferta_codigo)
                                            and x.dia between e.ing_de and e.venda_ate))))
    union all
    -- z85: venda de oferta ligada ao evento (fin.evento_ofertas) cujo produto a categoria do evento não tem
    select e.id,
           case when exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'ingresso')
                  and not exists (select 1 from fin.evento_produtos p2 where p2.produto_id = x.produto_id and p2.papel = 'oferta')
                 then 'ingresso' else 'oferta' end,
           x.*
      from fin.evento_ofertas eo
      join ev e on e.id = eo.evento_id
      join tx x on x.oferta_codigo = eo.oferta_codigo
     where not exists (select 1 from fin.evento_produtos p where p.categoria = e.categoria and p.produto_id = x.produto_id)
  ), agg as (
    select c.id,
           count(*) filter (where c.papel = 'ingresso' and c.grupo = 'pago')::int ing_n,
           coalesce(sum(c.valor) filter (where c.papel = 'ingresso' and c.grupo = 'pago'), 0) ing_b,
           coalesce(sum(c.liq) filter (where c.papel = 'ingresso' and c.grupo = 'pago'), 0) ing_l,
           count(*) filter (where c.papel = 'oferta' and c.grupo = 'pago')::int of_n,
           count(distinct c.email) filter (where c.papel = 'oferta' and c.grupo = 'pago')::int of_p,
           count(*) filter (where c.papel = 'oferta' and c.grupo = 'estornado')::int of_e,
           coalesce(sum(c.valor) filter (where c.papel = 'oferta' and c.grupo = 'pago'), 0) of_b,
           coalesce(sum(c.liq) filter (where c.papel = 'oferta' and c.grupo = 'pago'), 0) of_l,
           count(distinct c.email) filter (where c.grupo = 'pago')::int pess,
           coalesce(sum(c.liq), 0) liq_conf
      from casado c group by c.id
  )
  select e.id, e.nome, e.categoria, e.setor, e.inicio, e.fim, e.carrinho_inicio, e.venda_ate, e.ing_de,
         coalesce(a.ing_n, 0), round(coalesce(a.ing_b, 0), 2), round(coalesce(a.ing_l, 0), 2),
         coalesce(a.of_n, 0), coalesce(a.of_p, 0), coalesce(a.of_e, 0), round(coalesce(a.of_b, 0), 2), round(coalesce(a.of_l, 0), 2),
         coalesce(a.pess, 0), round(coalesce(a.ing_b, 0) + coalesce(a.of_b, 0), 2), round(coalesce(a.ing_l, 0) + coalesce(a.of_l, 0), 2),
         e.ref_vendas, e.ref_valor, e.ref_tipo, e.ref_fonte, e.observacao, (e.setor = 'escritorio' and e.inicio >= date '2025-01-01'), round(coalesce(a.liq_conf, 0), 2)
    from ev e left join agg a on a.id = e.id
   order by e.inicio desc;
end $function$
;

-- FUNCAO fn_fin_hotmart_funis(text,date,date)  md5(prosrc)=f74a829822e01739565baf93ca0993ea
CREATE OR REPLACE FUNCTION public.fn_fin_hotmart_funis(p_familia text DEFAULT 'HM'::text, p_inicio date DEFAULT NULL::date, p_fim date DEFAULT NULL::date)
 RETURNS TABLE(funil text, vale_de date, vale_ate date, vendas integer, compradores integer, valor_oferta numeric, cobrado_cliente numeric, juros numeric, taxa_hotmart numeric, liquido numeric, estornos integer, valor_estornado numeric, recusadas integer, boletos integer, parcelado integer, parcelas_media numeric, entra_rapido numeric, retido numeric, retido_a_liberar numeric, custo_antecipacao numeric, liquido_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        v_ini  date := coalesce(p_inicio, date '2021-01-01');
        v_fim  date := coalesce(p_fim, v_hoje);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with t as (
    select x.grupo, x.email, x.valor_oferta, x.valor_cobrado, x.juros, x.taxa_hotmart, x.liquido, x.parcelas,
           coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes x where x.familia = p_familia
  ), tf as (
    select t.*, coalesce(f.nome, 'Sem funil') funil_nome, f.vale_de f_de, f.vale_ate f_ate
      from t left join fin.funis f on f.familia = p_familia and t.dia_ref between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.dia_ref between v_ini and v_fim
  ), g as (
    select tf.funil_nome, min(tf.f_de) f_de, max(tf.f_ate) f_ate,
           count(*) filter (where tf.grupo = 'pago')::int n_vendas,
           count(distinct tf.email) filter (where tf.grupo = 'pago')::int n_compradores,
           coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'pago'), 0) s_oferta,
           coalesce(sum(tf.valor_cobrado) filter (where tf.grupo = 'pago'), 0) s_cobrado,
           coalesce(sum(tf.juros) filter (where tf.grupo = 'pago'), 0) s_juros,
           coalesce(sum(tf.taxa_hotmart) filter (where tf.grupo = 'pago'), 0) s_taxa,
           coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0) s_liquido,
           count(*) filter (where tf.grupo = 'estornado')::int n_estornos,
           coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'estornado'), 0) s_estornado,
           count(*) filter (where tf.grupo = 'recusado')::int n_recusadas,
           count(*) filter (where tf.grupo in ('em_aberto','expirado'))::int n_boletos,
           count(*) filter (where tf.grupo = 'pago' and coalesce(tf.parcelas, 1) > 1)::int n_parcelado,
           round(avg(coalesce(tf.parcelas, 1)) filter (where tf.grupo = 'pago'), 1) m_parcelas
      from tf group by tf.funil_nome
  ), pd as (
    select tf.funil_nome, tf.dia_ref, coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0) liq
      from tf group by tf.funil_nome, tf.dia_ref
  ), rec as (
    select pd.funil_nome,
           bool_and(r.liquido_total is not null) completo,
           sum(r.entra_rapido) s_entra, sum(r.retido) s_retido,
           coalesce(sum(r.retido) filter (where r.libera_em > v_hoje), 0) s_a_liberar,
           sum(r.custo_antecipacao) s_custo, sum(r.liquido_total) s_total
      from pd left join lateral fin.recebimento(pd.dia_ref, pd.liq) r on true
     group by pd.funil_nome
  )
  select g.funil_nome, g.f_de, g.f_ate, g.n_vendas, g.n_compradores, g.s_oferta, g.s_cobrado, g.s_juros, g.s_taxa,
         g.s_liquido, g.n_estornos, g.s_estornado, g.n_recusadas, g.n_boletos, g.n_parcelado, g.m_parcelas,
         case when rec.completo then rec.s_entra end,
         case when rec.completo then rec.s_retido end,
         case when rec.completo then rec.s_a_liberar end,
         case when rec.completo then rec.s_custo end,
         case when rec.completo then rec.s_total end
    from g left join rec on rec.funil_nome = g.funil_nome
   order by g.f_de nulls last;
end $function$
;

-- FUNCAO fn_fin_hotmart_identidade()  md5(prosrc)=b72673295c7d3337a5d2176bf3efe9c0
CREATE OR REPLACE FUNCTION public.fn_fin_hotmart_identidade()
 RETURNS TABLE(tipo text, motivo text, evidencia text, pessoa_a text, emails_a text[], nomes_a text[], pessoa_b text, emails_b text[], nomes_b text[], pago_a numeric, pago_b numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with emails as (
    select i.pessoa_chave p, array_agg(distinct substr(i.no, 3)) em from fin.identidade i where i.no like 'e:%' group by 1
  ), nomes as (
    select i.pessoa_chave p, array_agg(distinct t.comprador_nome) nm,
           coalesce(sum(coalesce(t.valor_base, t.valor_cobrado)) filter (where t.status in ('APPROVED','COMPLETE')), 0) pago
      from fin.identidade i join fin.hotmart_transacoes t on 'e:' || lower(trim(t.comprador_email)) = i.no
     group by 1
  )
  select 'sugestao', s.motivo,
         case when s.motivo in ('mesmo_telefone', 'mesmo_documento_tentativa') and not coalesce(public.gp_pode_ver_cpf(), false)
              then '···' || right(s.evidencia, 4) else s.evidencia end,
         fin.chave_opaca(s.pessoa_a), ea.em, na.nm, fin.chave_opaca(s.pessoa_b), eb.em, nb.nm, coalesce(na.pago, 0), coalesce(nb.pago, 0)
    from fin.identidade_sugestao s
    left join emails ea on ea.p = s.pessoa_a left join nomes na on na.p = s.pessoa_a
    left join emails eb on eb.p = s.pessoa_b left join nomes nb on nb.p = s.pessoa_b
  union all
  select 'revisao', r.motivo, case when r.no like 'd:%' then '···' || right(r.no, 4) else r.no end,
         fin.chave_opaca(r.no), null, null, null, null, null, null, null
    from fin.identidade_revisao r
   order by 1, 2;
end $function$
;

-- FUNCAO fn_fin_hotmart_pessoas(text)  md5(prosrc)=3a772aa8b7ce1968d73d52a7f39006a7
CREATE OR REPLACE FUNCTION public.fn_fin_hotmart_pessoas(p_familia text DEFAULT 'HM'::text)
 RETURNS TABLE(pessoa_chave text, nome text, emails text[], documentos text[], telefone text, cidade text, situacao text, aviso text, primeira_compra date, primeira_oferta text, origem text, fluxo text, produtos text[], ultima_compra_paga date, compras_pagas integer, valor_pago numeric, liquido numeric, estornos integer, valor_estornado numeric, parcelas_atrasadas integer, valor_atrasado numeric, atrasadas_antigas integer, valor_atrasado_antigo numeric, em_aberto integer, recusadas integer, ultima_tentativa date, no_gps boolean, turma text, acesso_ate date, acesso_hotmart_ate date, cards integer, contato_hm_id uuid, status_card text, saldo_card numeric, canal_card text, solicitou_cancelamento boolean, sugestoes integer, cobrado_cliente numeric, juros numeric, taxa_hotmart numeric, coproducao numeric, vendas_parceladas integer, parcelas_max integer, forma_pagamento_principal text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with tx as (
    select coalesce(ip.pessoa_chave, 'e:' || t.email) pessoa, t.*, cat.categoria
      from fin.vw_transacoes t
      left join fin.identidade ip on ip.no = 'e:' || t.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.familia = p_familia and t.email is not null
  ), agg as (
    select x.pessoa,
           (array_agg(x.nome order by x.pedido_em desc))[1] nome,
           array_agg(distinct x.email) emails,
           array_remove(array_agg(distinct h.comprador_documento), null) docs,
           (array_agg(h.comprador_telefone order by x.pedido_em desc) filter (where h.comprador_telefone is not null))[1] tel,
           (array_agg(coalesce(h.comprador_cidade || '/' || h.comprador_uf, h.comprador_uf) order by x.pedido_em desc)
              filter (where h.comprador_cidade is not null or h.comprador_uf is not null))[1] cidade,
           min(x.dia_aprovado) filter (where x.grupo in ('pago','estornado')) primeira,
           (array_agg(x.oferta_codigo order by x.aprovado_em) filter (where x.grupo in ('pago','estornado')))[1] primeira_oferta,
           (array_agg(x.origem_sck order by x.aprovado_em) filter (where x.grupo in ('pago','estornado') and x.origem_sck is not null))[1] origem,
           array_agg(distinct x.produto_nome) filter (where x.grupo = 'pago') produtos,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ultima_paga,
           count(*) filter (where x.grupo = 'pago')::int pagas,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) valor_pago,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liquido,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'estornado'), 0) valor_estornado,
           max(x.aprovado_em) filter (where x.grupo = 'estornado') ultimo_estorno,
           max(x.aprovado_em) filter (where x.grupo = 'pago') ultimo_pago,
           count(*) filter (where x.grupo = 'em_aberto')::int em_aberto,
           count(*) filter (where x.grupo = 'recusado')::int recusadas,
           max(x.dia_pedido) ultima_tentativa,
           max(x.dia_aprovado) filter (where x.grupo = 'pago' and x.categoria in ('sinal','compra_cheia','diferenca')) ultima_paga_card,
           bool_or(x.grupo = 'pago' and x.oferta_modo like 'HOTMART_INSTALLMENTS%'
                   and x.recorrencia is not null and x.parcelas is not null and x.recorrencia < x.parcelas
                   and x.dia_aprovado >= (now() at time zone 'America/Sao_Paulo')::date - 45) parcelado_em_curso,
           coalesce(sum(x.valor_cobrado) filter (where x.grupo = 'pago'), 0) cobrado,
           coalesce(sum(x.juros) filter (where x.grupo = 'pago'), 0) juros,
           coalesce(sum(x.taxa_hotmart) filter (where x.grupo = 'pago'), 0) taxa,
           greatest(coalesce(sum(x.valor_oferta - coalesce(x.taxa_hotmart, 0) - x.liquido) filter (where x.grupo = 'pago'), 0), 0) coproducao,
           count(*) filter (where x.grupo = 'pago' and x.parcelas > 1)::int parceladas,
           max(x.parcelas) filter (where x.grupo = 'pago') parcelas_max
      from tx x
      join fin.hotmart_transacoes h on h.transacao = x.transacao
     group by x.pessoa
  ), fp as (
    select distinct on (m.pessoa) m.pessoa, m.metodo
      from (select y.pessoa, y.metodo, count(*) n, max(y.aprovado_em) ult
              from tx y where y.grupo = 'pago' and y.metodo is not null
             group by y.pessoa, y.metodo) m
     order by m.pessoa, m.n desc, m.ult desc nulls last
  ), pa as (
    select d.pessoa, d.n_atual, d.valor_atual, d.n_antigas, d.valor_antigo
      from fin.parcelas_devidas(p_familia) d
  ), flx as (
    select z.pessoa, string_agg(z.c, ' → ' order by z.o) fluxo
      from (select y.pessoa, fin.oferta_categoria(y.oferta_codigo, y.oferta_modo, y.valor_oferta) c, y.aprovado_em o,
                   lag(fin.oferta_categoria(y.oferta_codigo, y.oferta_modo, y.valor_oferta)) over (partition by y.pessoa order by y.aprovado_em) ant
              from tx y where y.grupo = 'pago') z
     where z.ant is distinct from z.c
     group by z.pessoa
  ), email_pessoa as (
    select a.pessoa, unnest(a.emails) email from agg a
    union
    select i.pessoa_chave, substr(i.no, 3) from fin.identidade i
     where i.no like 'e:%' and i.pessoa_chave in (select pessoa from agg)
  ), card as (
    select e.pessoa, count(*)::int n,
           (array_agg(b.contato_hm_id order by b.saldo_a_pagar desc nulls last))[1] contato_hm_id,
           (array_agg(b.status_financeiro order by b.saldo_a_pagar desc nulls last))[1] status,
           sum(b.saldo_a_pagar) saldo, (array_agg(b.canal order by b.saldo_a_pagar desc nulls last))[1] canal,
           bool_or(coalesce(b.solicitou_cancelamento, false)) solicitou
      from email_pessoa e
      join public.compradores c on lower(trim(c.email)) = e.email
      join cs.vw_fin_board b on b.comprador_id = c.id and b.origem = p_familia
     group by e.pessoa
  ), aluno as (
    select e.pessoa, max(a.data_expiracao) acesso,
           (array_agg(tt.codigo order by a.data_expiracao desc nulls last) filter (where tt.codigo is not null))[1] turma,
           bool_or(exists (select 1 from gps.membros m where m.aluno_id = a.id or m.pessoa_aluno_id = a.id)) no_gps
      from email_pessoa e
      join public.thb_alunos a on lower(trim(a.email)) = e.email
      left join public.thb_turmas tt on tt.id = a.turma_id
     group by e.pessoa
  ), sug as (
    select p, count(*)::int n from (select pessoa_a p from fin.identidade_sugestao union all select pessoa_b from fin.identidade_sugestao) s group by p
  )
  select fin.chave_opaca(a.pessoa), a.nome, a.emails,
         case when coalesce(public.gp_pode_ver_cpf(), false) then a.docs
              else array(select case when length(d) = 14 then 'CNPJ ···' else 'CPF ···' end || right(d, 4) from unnest(a.docs) d) end,
         case when coalesce(public.gp_pode_ver_cpf(), false) then a.tel
              when a.tel is not null then '···' || right(a.tel, 4) end,
         a.cidade,
         case
           when a.pagas = 0 and a.estornos > 0 then 'reembolsado'
           when coalesce(c.solicitou, false) then 'negociacao_cancelamento'
           when coalesce(pa.n_atual, 0) > 0 then 'devendo'
           when a.estornos > 0 and a.ultimo_estorno > coalesce(a.ultimo_pago, '-infinity') then 'reembolsado'
           when coalesce(c.saldo, 0) > 0.5 or a.parcelado_em_curso then 'em_pagamento'
           when a.pagas > 0 and a.ultima_paga >= (now() at time zone 'America/Sao_Paulo')::date - 365 then 'ativo'
           when coalesce(pa.n_antigas, 0) > 0 then 'inadimplencia_antiga'
           when a.pagas > 0 then 'vencido'
           when a.em_aberto > 0 then 'boleto_em_aberto'
           else 'so_tentou'
         end,
         case
           when coalesce(al.no_gps, false) and (coalesce(pa.n_atual, 0) > 0 or a.estornos > 0 or coalesce(c.solicitou, false))
             then 'Está no GPS e tem pendência financeira — não mexer no acesso, resolver com o João'
           when c.pessoa is null and p_familia = 'HM' and a.ultima_paga_card >= date '2026-06-25'
             then 'Pagou na Hotmart depois de 25/06 e não tem card no board'
           when coalesce(s.n, 0) > 0
             then 'Possível mesma pessoa com outro e-mail (telefone, nome ou CPF de tentativa igual) — conferir'
         end,
         a.primeira, a.primeira_oferta, a.origem, f.fluxo, a.produtos,
         a.ultima_paga, a.pagas, a.valor_pago, a.liquido, a.estornos, a.valor_estornado,
         coalesce(pa.n_atual, 0), coalesce(pa.valor_atual, 0), coalesce(pa.n_antigas, 0), coalesce(pa.valor_antigo, 0),
         a.em_aberto, a.recusadas, a.ultima_tentativa,
         coalesce(al.no_gps, false), al.turma, al.acesso, a.ultima_paga + 365,
         coalesce(c.n, 0), c.contato_hm_id, c.status, c.saldo, c.canal,
         coalesce(c.solicitou, false), coalesce(s.n, 0),
         a.cobrado, a.juros, a.taxa, a.coproducao,
         a.parceladas, a.parcelas_max, fp.metodo
    from agg a
    left join card c on c.pessoa = a.pessoa
    left join aluno al on al.pessoa = a.pessoa
    left join sug s on s.p = a.pessoa
    left join flx f on f.pessoa = a.pessoa
    left join pa on pa.pessoa = a.pessoa
    left join fp on fp.pessoa = a.pessoa
   order by coalesce(pa.valor_atual, 0) desc, coalesce(pa.valor_antigo, 0) desc, a.ultima_tentativa desc nulls last;
end $function$
;

-- FUNCAO fn_fin_hotmart_sync_status()  md5(prosrc)=63555ec9bba204e65b7833b1ba3bf8a1
CREATE OR REPLACE FUNCTION public.fn_fin_hotmart_sync_status()
 RETURNS TABLE(transacoes integer, ultima_atualizacao timestamp with time zone, janelas_pendentes integer, janelas_com_erro integer, primeira_venda date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select (select count(*) from fin.hotmart_transacoes)::int,
         (select max(atualizado_em) from fin.hotmart_transacoes),
         (select count(*) from fin.hotmart_sync_fila where status in ('pendente','processando'))::int,
         (select count(*) from fin.hotmart_sync_fila where status = 'erro')::int,
         (select min(dia_aprovado) from fin.vw_transacoes where grupo = 'pago');
end $function$
;

-- FUNCAO fn_fin_programa_sem_card(text)  md5(prosrc)=bd57f052d1a16a67d592af53885a07b8
CREATE OR REPLACE FUNCTION public.fn_fin_programa_sem_card(p_familia text DEFAULT 'HM'::text)
 RETURNS TABLE(nome text, email text, telefone text, primeira date, valor numeric, ofertas text, fora_do_catalogo boolean, acao text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with pagos as (
    select coalesce(i.pessoa_chave, 'e:' || t.email) pk, t.email, t.nome, t.transacao, t.aprovado_em, t.dia_aprovado,
           t.valor_oferta, t.oferta_codigo, cat.offer_code is null fora, t.origem_sck
      from fin.vw_transacoes t
      left join fin.identidade i on i.no = 'e:' || t.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.grupo = 'pago' and coalesce(t.recorrencia, 1) = 1
       and coalesce(cat.categoria, '') not in ('renovacao','reserva')
       and ((p_familia = 'HM' and t.produto_id = '5064314' and t.dia_aprovado >= date '2026-06-25')
         or (p_familia = 'AURUM' and t.familia = 'AURUM' and t.dia_aprovado >= date '2026-01-01'))
  ), board as (
    select distinct coalesce(i.pessoa_chave, 'e:' || lower(trim(b.email))) pk
      from cs.vw_fin_board b left join fin.identidade i on i.no = 'e:' || lower(trim(b.email))
     where b.origem = p_familia
  ), pessoa as (
    select p.pk, min(p.aprovado_em) primeira_em, sum(p.valor_oferta) valor,
           string_agg(distinct p.oferta_codigo, ', ') ofertas, bool_or(p.fora) fora,
           (array_agg(p.email order by p.aprovado_em))[1] email, (array_agg(p.nome order by p.aprovado_em))[1] nome,
           (array_agg(p.transacao order by p.aprovado_em))[1] transacao
      from pagos p where not exists (select 1 from board b where b.pk = p.pk)
     group by p.pk
  )
  select fin.nome_exibicao(x.nome, x.email), x.email,
         case when coalesce(public.gp_pode_ver_cpf(), false) then h.comprador_telefone
              when h.comprador_telefone is not null then '···' || right(h.comprador_telefone, 4) end,
         (x.primeira_em at time zone 'America/Sao_Paulo')::date, round(x.valor, 2), x.ofertas, x.fora,
         (select a.nome from fin.acoes a
           where a.produto = p_familia and a.inicio is not null and a.fim is not null
             and x.primeira_em >= a.inicio and x.primeira_em < a.fim
           order by a.prioridade, a.id limit 1)
    from pessoa x
    left join fin.hotmart_transacoes h on h.transacao = x.transacao
   order by x.primeira_em;
end $function$
;

-- FUNCAO fn_fin_receber_previsto_realizado(integer)  md5(prosrc)=a5fb0ebc38fc04fb4b567770eae7dd57
CREATE OR REPLACE FUNCTION public.fn_fin_receber_previsto_realizado(p_semanas integer DEFAULT 8)
 RETURNS TABLE(linha text, semana_de date, semana_ate date, janela_de date, janela_ate date, foto_em timestamp with time zone, bloco smallint, grupo text, previsto numeric, previsto_bruto numeric, realizado numeric, desvio numeric, acerto_pct numeric, chave_premissa text, perda_medida numeric, premissa_atual numeric, cobrancas_resolvidas integer, cobrancas_perdidas integer, valor_resolvido numeric, valor_perdido numeric, nota text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_seg  date;
  v_tol  int;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_semanas is null or p_semanas < 1 or p_semanas > 52 then
    raise exception 'Semanas: de 1 a 52.' using errcode = '22023';
  end if;
  v_seg := (date_trunc('week', v_hoje::timestamp))::date;
  v_tol := fin.premissa('tolerancia_atraso_dias', v_hoje, 'base')::int;
  if v_tol is null then
    raise exception 'Premissa tolerancia_atraso_dias ausente.' using errcode = 'P0002';
  end if;
  return query
  with fw as materialized (
    select s.de, s.de + 6 ate, c.foto_em, c.corte, c.dia,
           case when c.foto_em is not null then greatest(s.de, c.dia + 1) end j0, s.de + 6 j1,
           (c.foto_em at time zone 'America/Sao_Paulo')::date > c.dia reconstruida
      from (select v_seg - 7 * g.n de from generate_series(1, p_semanas) g(n)) s
      left join lateral (
        select c.foto_em, c.corte, c.dia from fin.receber_fotos_cabecalho c
         where c.cenario = 'base' and c.dia <= s.de and c.dia > s.de - 7
         order by c.dia desc, c.foto_em desc limit 1
      ) c on true
  ), itens as materialized (
    select fw.de, f.bloco, f.grupo, f.ref, f.origem_dia, f.componente, f.data_caixa, f.valor, f.valor_bruto
      from fw join fin.receber_fotos f on f.foto_em = fw.foto_em
     where f.situacao = 'a_receber'
  ), prev as (
    select i.de, i.bloco, i.grupo, sum(i.valor) previsto, sum(i.valor_bruto) previsto_bruto
      from itens i join fw on fw.de = i.de
     where i.data_caixa between fw.j0 and fw.j1
     group by 1, 2, 3
  ), r1 as (
    select fw.de, 1::smallint bloco, 'Vendas já realizadas'::text grupo, sum(v.valor) realizado
      from fw cross join lateral fin.receber_vendas_realizadas(fw.corte) v
     where fw.foto_em is not null and v.data_caixa between fw.j0 and fw.j1
     group by fw.de
  ), tx as materialized (
    select fw.de, t.transacao, t.email, t.oferta_codigo, t.oferta_modo, t.produto_id, t.recorrencia, t.dia_aprovado,
           t.liquido
      from fw
      join fin.vw_transacoes t
        on t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > fw.corte
       and t.aprovado_em < (fw.j1 + 1)::timestamp at time zone 'America/Sao_Paulo'
     where fw.foto_em is not null
  ), inf as materialized (
    select distinct i.de, i.ref::uuid id, i.grupo from itens i where i.bloco = 5
  ), alvo as materialized (
    select a.id, a.emails, a.docs from fin.informados_alvos() a where a.id in (select inf.id from inf)
  ), m5 as (
    select distinct on (x.de, x.transacao) x.de, x.transacao, inf.grupo
      from tx x
      join inf on inf.de = x.de
      join fin.recebimentos_informados r on r.id = inf.id and r.via_hotmart
      join alvo a on a.id = inf.id
      join fin.hotmart_transacoes h on h.transacao = x.transacao
     where x.produto_id = any (r.produto_ids) and x.dia_aprovado >= r.acordo_desde
       and (lower(trim(h.comprador_email)) = any (a.emails)
            or regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs))
     order by x.de, x.transacao, r.data_prevista, r.id
  ), rc as materialized (
    select y.email, y.oferta_codigo, fin.chave_opaca('rc:' || y.email || '|' || y.oferta_codigo) ref
      from (select distinct x.email, x.oferta_codigo from tx x
             where x.recorrencia >= 2 and x.email is not null and x.oferta_codigo is not null
               and (x.oferta_modo in ('SUBSCRIPTION','MULTIPLE_PAYMENTS') or x.oferta_modo like 'HOTMART_INSTALLMENTS%')) y
  ), g2 as materialized (
    select distinct on (fw.de, f.ref) fw.de, f.ref, f.grupo
      from fw join fin.receber_fotos f on f.foto_em = fw.foto_em
     where f.bloco = 2
     order by fw.de, f.ref, f.grupo
  ), atrib as (
    select x.de, x.dia_aprovado, x.liquido,
           case when m5.transacao is not null then 5 when g2.ref is not null then 2 end::smallint bloco,
           coalesce(m5.grupo, g2.grupo, 'Fora da foto (vendas novas e outros)') grupo
      from tx x
      left join m5 on m5.de = x.de and m5.transacao = x.transacao
      left join rc on x.recorrencia >= 2 and rc.email = x.email and rc.oferta_codigo = x.oferta_codigo
                  and (x.oferta_modo in ('SUBSCRIPTION','MULTIPLE_PAYMENTS') or x.oferta_modo like 'HOTMART_INSTALLMENTS%')
      left join g2 on g2.de = x.de and g2.ref = rc.ref
  ), rpos as (
    select d.de, d.bloco, d.grupo,
           sum(case when r.entra_em between fw.j0 and fw.j1 then r.entra_rapido else 0 end
               + case when r.libera_em between fw.j0 and fw.j1 then r.retido else 0 end) realizado
      from (select a.de, a.bloco, a.grupo, a.dia_aprovado, sum(a.liquido) liq
              from atrib a group by 1, 2, 3, 4) d
      join fw on fw.de = d.de
      cross join lateral fin.recebimento(d.dia_aprovado, d.liq) r
     group by 1, 2, 3
  ), r5b as (
    select inf.de, 5::smallint bloco, inf.grupo, sum(r.valor) realizado
      from inf
      join fw on fw.de = inf.de
      join fin.recebimentos_informados r on r.id = inf.id
     where r.baixa_manual_em between fw.j0 and fw.j1
     group by 1, 2, 3
  ), r7b as (
    select i7.de, 7::smallint bloco, i7.grupo, sum(r.valor) realizado
      from (select distinct i.de, i.ref::uuid id, i.grupo from itens i where i.bloco = 7) i7
      join fw on fw.de = i7.de
      join fin.recebimentos_informados r on r.id = i7.id
     where r.baixa_manual_em between fw.j0 and fw.j1
     group by 1, 2, 3
  ), rea as (
    select u.de, u.bloco, u.grupo, sum(u.realizado) realizado
      from (select * from r1 union all select * from rpos union all select * from r5b union all select * from r7b) u
     group by 1, 2, 3
  ), sem as (
    select fw.de, fw.ate, fw.j0, fw.j1, fw.foto_em, coalesce(p.bloco, r.bloco) bloco, coalesce(p.grupo, r.grupo) grupo,
           p.previsto, p.previsto_bruto,
           case when coalesce(p.bloco, r.bloco) in (3, 4, 6) then null else coalesce(r.realizado, 0) end realizado,
           case when fw.reconstruida then 'foto reconstruída (dados de hoje)' end nota
      from fw
      join (prev p full join rea r on r.de = p.de and coalesce(r.bloco, 0) = coalesce(p.bloco, 0) and r.grupo = p.grupo)
        on fw.de = coalesce(p.de, r.de)
     where fw.foto_em is not null and (p.previsto is not null or coalesce(r.realizado, 0) <> 0)
  ), coorte as (
    select i.de, i.grupo, i.ref, i.origem_dia, sum(i.valor_bruto) vb
      from itens i join fw on fw.de = i.de
     where i.bloco = 2 and i.origem_dia between fw.de and fw.ate
     group by 1, 2, 3, 4
  ), res as materialized (
    select fw.de, c.foto_em
      from fw
      cross join lateral (
        select c.foto_em from fin.receber_fotos_cabecalho c
         where c.cenario = 'base' and c.dia > fw.ate + v_tol
         order by c.dia, c.foto_em limit 1
      ) c
     where fw.foto_em is not null
  ), rf as materialized (
    select res.de, f.ref, f.origem_dia, bool_or(f.situacao = 'realizada') pago, bool_or(f.situacao = 'em_atraso_fora') atraso,
           bool_or(f.situacao = 'coberta_informado') coberta, bool_or(f.situacao = 'a_receber') aberta
      from res join fin.receber_fotos f on f.foto_em = res.foto_em and f.bloco = 2
     group by 1, 2, 3
  ), rref as (
    select rf.de, rf.ref, bool_or(rf.pago and rf.origem_dia is null) pago_sem_venc from rf group by 1, 2
  ), est as (
    select co.grupo, co.vb,
           case when res.foto_em is null then 'pendente'
                when x.pago then 'paga'
                when x.coberta then 'fora'
                when x.atraso then 'perdida'
                when x.aberta then 'pendente'
                when y.pago_sem_venc then 'paga'
                when y.ref is null then 'perdida'
                else 'fora' end st
      from coorte co
      left join res on res.de = co.de
      left join rf x on x.de = co.de and x.ref = co.ref and x.origem_dia = co.origem_dia
      left join rref y on y.de = co.de and y.ref = co.ref
  ), perda as (
    select e.grupo, count(*) filter (where e.st in ('paga','perdida'))::int resolvidas,
           count(*) filter (where e.st = 'perdida')::int perdidas,
           coalesce(sum(e.vb) filter (where e.st in ('paga','perdida')), 0) v_res,
           coalesce(sum(e.vb) filter (where e.st = 'perdida'), 0) v_perd
      from est e group by 1
  )
  select 'semana'::text, s.de, s.ate, s.j0, s.j1, s.foto_em, s.bloco, s.grupo, s.previsto, s.previsto_bruto, s.realizado,
         s.realizado - coalesce(s.previsto, 0),
         case when s.previsto > 0 and s.realizado is not null
              then pg_catalog.round(greatest(0::numeric, 100 * (1 - abs(s.realizado - s.previsto) / s.previsto)), 1) end,
         null::text, null::numeric, null::numeric, null::int, null::int, null::numeric, null::numeric, s.nota
    from sem s
  union all
  select 'semana'::text, fw.de, fw.ate, null::date, null::date, null::timestamptz, null::smallint, null::text,
         null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, null::text, null::numeric,
         null::numeric, null::int, null::int, null::numeric, null::numeric, 'sem foto base no início da semana'::text
    from fw where fw.foto_em is null
  union all
  select 'perda'::text, null::date, null::date, null::date, null::date, null::timestamptz, 2::smallint, pe.grupo,
         null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, m.chave,
         case when pe.v_res > 0 then pg_catalog.round(pe.v_perd / pe.v_res, 4) end,
         fin.premissa(m.chave, v_hoje, 'base'),
         pe.resolvidas, pe.perdidas, pe.v_res, pe.v_perd,
         'sugestão medida (não grava): perdidas ÷ resolvidas, por valor, nas ' || p_semanas || ' semanas'
    from perda pe
    left join (values ('Assinaturas Serviço Diamante'::text,         'perda_mensal:servico_diamante'::text),
                      ('Assinaturas Holding - Holding Masters'::text, 'perda_mensal:holding_hm'::text),
                      ('Outras assinaturas'::text,                    'perda_mensal:outras_assinaturas'::text),
                      ('Parcelas a vencer HM'::text,                  'perda_mensal:parcelas_hm'::text),
                      ('Parcelas a vencer Aurum'::text,               'perda_mensal:parcelas_aurum'::text),
                      ('Parcelas a vencer outros'::text,              'perda_mensal:parcelas_outros'::text)
              ) m(grupo, chave) on m.grupo = pe.grupo
   order by 1 desc, 2 desc nulls last, 7 nulls last, 8;
end $function$
;

-- VIEW fin.hotmart_transacoes_identidade  reloptions=null  relacl={postgres=arwdDxtm/postgres}  owner=postgres
create or replace view fin.hotmart_transacoes_identidade as
 SELECT transacao,
    produto_id,
    produto_nome,
    oferta_codigo,
    oferta_modo,
    status,
    eh_assinatura,
    recorrencia,
    metodo,
    tipo_pagamento,
    parcelas,
    moeda,
    valor_cobrado,
    valor_base,
    juros_parcelamento,
    taxa_hotmart,
    liquido_produtor,
    comissoes,
    pedido_em,
    aprovado_em,
    garantia_ate,
    origem_sck,
    comprador_email,
    comprador_nome,
    comprador_ucode,
    bruto_json,
    detalhes_em,
    primeiro_visto_em,
    atualizado_em,
    comprador_documento,
    comprador_documento_tipo,
    comprador_telefone,
    comprador_cidade,
    comprador_uf,
    participantes
   FROM fin.hotmart_transacoes t
  WHERE (NOT (EXISTS ( SELECT 1
           FROM fin.produtos p
          WHERE ((p.produto_id = t.produto_id) AND (p.familia = 'A_CLASSIFICAR'::text)))));

-- VIEW fin.vw_transacoes  reloptions=null  relacl={postgres=arwdDxtm/postgres}  owner=postgres
create or replace view fin.vw_transacoes as
 SELECT t.transacao,
    t.produto_id,
    COALESCE(p.familia, 'OUTRO'::text) AS familia,
    COALESCE(p.papel, 'desconhecido'::text) AS papel_produto,
    t.produto_nome,
    t.oferta_codigo,
    t.oferta_modo,
    t.status,
    t.recorrencia,
    t.metodo,
    t.tipo_pagamento,
    t.parcelas,
    COALESCE(t.valor_base, (NULLIF((t.bruto_json #>> '{purchase,hotmart_fee,base}'::text[]), ''::text))::numeric, t.valor_cobrado) AS valor_oferta,
    t.valor_cobrado,
    GREATEST(COALESCE(t.juros_parcelamento, (0)::numeric), (t.valor_cobrado - COALESCE(t.valor_base, (NULLIF((t.bruto_json #>> '{purchase,hotmart_fee,base}'::text[]), ''::text))::numeric, t.valor_cobrado)), (0)::numeric) AS juros,
    t.taxa_hotmart,
        CASE
            WHEN (t.status = ANY (ARRAY['APPROVED'::text, 'COMPLETE'::text])) THEN COALESCE(t.liquido_produtor, (COALESCE(t.valor_base, (NULLIF((t.bruto_json #>> '{purchase,hotmart_fee,base}'::text[]), ''::text))::numeric, t.valor_cobrado) - COALESCE(t.taxa_hotmart, (0)::numeric)))
            ELSE NULL::numeric
        END AS liquido,
    ((t.status = ANY (ARRAY['APPROVED'::text, 'COMPLETE'::text])) AND (t.liquido_produtor IS NULL)) AS liquido_estimado,
        CASE
            WHEN (t.status = ANY (ARRAY['APPROVED'::text, 'COMPLETE'::text])) THEN 'pago'::text
            WHEN (t.status = ANY (ARRAY['REFUNDED'::text, 'PARTIALLY_REFUNDED'::text, 'CHARGEBACK'::text])) THEN 'estornado'::text
            WHEN (t.status = ANY (ARRAY['OVERDUE'::text, 'PROTESTED'::text])) THEN 'atrasado'::text
            WHEN (t.status = ANY (ARRAY['PRINTED_BILLET'::text, 'WAITING_PAYMENT'::text, 'UNDER_ANALISYS'::text, 'STARTED'::text])) THEN 'em_aberto'::text
            WHEN (t.status = ANY (ARRAY['CANCELLED'::text, 'NO_FUNDS'::text, 'BLOCKED'::text])) THEN 'recusado'::text
            WHEN (t.status = 'EXPIRED'::text) THEN 'expirado'::text
            ELSE 'outro'::text
        END AS grupo,
    t.pedido_em,
    t.aprovado_em,
    t.garantia_ate,
    ((t.pedido_em AT TIME ZONE 'America/Sao_Paulo'::text))::date AS dia_pedido,
    ((t.aprovado_em AT TIME ZONE 'America/Sao_Paulo'::text))::date AS dia_aprovado,
    t.origem_sck,
    lower(TRIM(BOTH FROM t.comprador_email)) AS email,
    t.comprador_nome AS nome,
    t.atualizado_em
   FROM (fin.hotmart_transacoes t
     LEFT JOIN fin.produtos p ON ((p.produto_id = t.produto_id)));
