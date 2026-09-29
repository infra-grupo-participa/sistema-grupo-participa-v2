-- 20260930z90.backup-antes.sql — estado vivo ANTES do apply da z90 (lido em 29/09/2026 22:55 UTC).
-- NÃO é migration: é a fonte da reversão da z90 (ver REVERSÃO no cabeçalho da z90).
-- Sem segredo: as funções citam só NOMES de segredos do Vault; nenhum valor. Sem dado pessoal.
-- Ordem de reposição: 1) trava (v_aprovados antigos) → 2) funis → 3) credencial/enfileirar → 4) crons (cron.alter_job).
-- (antes da 1–3: renomear sincroniza→ativa e dropar visivel_funis/ativa gerada, conforme a REVERSÃO.)

-- fin.trava_conta_hotmart_violacao(oid,oid)  md5(prosrc)=be13743875a7cbbacc5092a7cda4f0bf
CREATE OR REPLACE FUNCTION fin.trava_conta_hotmart_violacao(p_classid oid, p_objid oid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  -- nome (regprocedure/regclass com schema) | md5 do corpo cru (prosrc; view: pg_get_viewdef com search_path '')
  v_aprovados constant text[] := array[
    -- leem fin.vw_transacoes_contas (conta por linha, pela conta do evento/família)
    'public.fn_fin_funis()|b72ed7dda46ecc1c6ff0c0ebf835e2a0',
    'public.fn_fin_funil_compradores(bigint)|f354c46da0d29c173d46daf52d7c1421',
    'public.fn_fin_hotmart_funis(text,date,date)|a36eed87268bb5ca192b3857d9e8476c',
    -- views do espelho (filtro de conta no WHERE final, fora da forma canônica)
    'fin.vw_transacoes|cda2f17094687e5ccb47447a98acc2ca',
    'fin.vw_transacoes_escritorio|3c0fbd675bf280e1a26c813bf3ce7692',
    'fin.vw_transacoes_contas|6f8931078a38ff6327519c86f953c788',
    'fin.hotmart_transacoes_identidade|189be8b9849b529e25fdc6ccf36fae6f'
    -- escritores de fin.hotmart_transacoes no banco: nenhum (a edge hotmart-sync não é objeto do banco)
  ];
  v_obj  text;
  v_src  text;
  v_s    text := '';
  v_tot  int;
  v_ok   int;
  i int := 1; j int; k int; d int;
begin
  if p_classid = 'pg_catalog.pg_proc'::regclass then
    if p_objid in ('fin.trava_conta_hotmart_violacao(oid,oid)'::regprocedure, 'fin.trava_conta_hotmart()'::regprocedure) then
      return null;  -- a própria trava cita os nomes nas regras
    end if;
    select p.oid::regprocedure::text, coalesce(nullif(p.prosrc, ''), pg_get_functiondef(p.oid))
      into v_obj, v_src
      from pg_catalog.pg_proc p where p.oid = p_objid and p.prolang not in (12, 13);  -- internal, c
  elsif p_classid = 'pg_catalog.pg_class'::regclass then
    select c.oid::regclass::text, pg_get_viewdef(c.oid)
      into v_obj, v_src
      from pg_catalog.pg_class c where c.oid = p_objid and c.relkind in ('v', 'm');
  end if;
  if v_src is null or v_src !~* '(hotmart_transacoes|vw_transacoes_contas)' then
    return null;  -- caminho rápido: a imensa maioria das DDL para aqui
  end if;
  if (v_obj || '|' || md5(v_src)) = any (v_aprovados) then
    return null;
  end if;

  -- tira comentários (-- e /* */ aninhado) respeitando literais '...' ('' escapado); literais ficam
  loop
    j := regexp_instr(v_src, '''|--|/\*', i);
    if j = 0 then v_s := v_s || substr(v_src, i); exit; end if;
    v_s := v_s || substr(v_src, i, j - i);
    if substr(v_src, j, 1) = '''' then
      k := j + 1;
      loop
        k := regexp_instr(v_src, '''', k);
        exit when k = 0 or substr(v_src, k + 1, 1) <> '''';
        k := k + 2;
      end loop;
      if k = 0 then v_s := v_s || substr(v_src, j); exit; end if;
      v_s := v_s || substr(v_src, j, k - j + 1);
      i := k + 1;
    elsif substr(v_src, j, 2) = '--' then
      k := strpos(substr(v_src, j), chr(10));
      exit when k = 0;
      v_s := v_s || ' ';
      i := j + k - 1;
    else
      d := 1; k := j + 2;
      while d > 0 loop
        k := regexp_instr(v_src, '/\*|\*/', k);
        exit when k = 0;
        d := d + case when substr(v_src, k, 2) = '/*' then 1 else -1 end;
        k := k + 2;
      end loop;
      exit when k = 0;
      v_s := v_s || ' ';
      i := k;
    end if;
  end loop;

  if v_s ~* '\mvw_transacoes_contas\M' then
    return format('%s lê fin.vw_transacoes_contas (todas as contas) e não está em v_aprovados de fin.trava_conta_hotmart_violacao (md5 do corpo: %s)',
                  v_obj, md5(v_src));
  end if;
  v_tot := (select count(*) from regexp_matches(v_s, '\mhotmart_transacoes\M(?!\s*[.%])', 'gi'));
  v_ok  := (select count(*) from regexp_matches(v_s,
             '\mhotmart_transacoes\s+where\s+\(*((fin\.)?hotmart_transacoes\.)?conta\s*=\s*(''[a-z][a-z0-9_]*''|[pv]_[a-z0-9_]+\M)', 'gi'));
  if v_tot > v_ok then
    return format('%s: %s de %s citação(ões) de fin.hotmart_transacoes fora da forma "(select * from fin.hotmart_transacoes where conta = ''<conta>'')" (md5 do corpo: %s)',
                  v_obj, v_tot - v_ok, v_tot, md5(v_src));
  end if;
  return null;
end
$function$
;

-- fin.hotmart_credenciais_conta(text)  md5(prosrc)=5f7516a3336de1fce85c5a2463839e12
CREATE OR REPLACE FUNCTION fin.hotmart_credenciais_conta(p_conta text)
 RETURNS TABLE(basic text, chave_sync text)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (select s.decrypted_secret
            from fin.hotmart_contas c
            join vault.decrypted_secrets s on s.name = c.vault_nome
           where c.conta = p_conta and c.ativa),
         (select decrypted_secret from vault.decrypted_secrets where name = 'fin_hotmart_sync_chave');
$function$
;

-- fin.hotmart_sync_enfileirar(integer)  md5(prosrc)=f06f1b29e896a805d9a1332aefc0ae4d
CREATE OR REPLACE FUNCTION fin.hotmart_sync_enfileirar(p_dias integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo)
  select p.conta, p.produto_id, g::date, least(g::date + 59, v_hoje), 'rotina'
    from fin.produtos p
    cross join generate_series(v_hoje - p_dias, v_hoje, interval '60 days') g
   where p.sincroniza and exists (select 1 from fin.hotmart_contas c where c.conta = p.conta and c.ativa)
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$
;

-- public.fn_fin_funil_compradores(bigint)  md5(prosrc)=f354c46da0d29c173d46daf52d7c1421
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
    select x.*, coalesce((select max(y.venda_ate) from fin.eventos y where y.categoria = x.categoria and y.inicio < x.inicio) + 1, x.inicio - 60) ing_de, case when x.setor = 'escritorio' and x.inicio >= date '2025-01-01' then 'escritorio' else 'academy' end conta_ev
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
        join fin.hotmart_transacoes t0 on t0.conta = e.conta_ev and t0.oferta_codigo = eo0.oferta_codigo
       where eo0.evento_id = e.id
         and not exists (select 1 from fin.evento_produtos ep where ep.categoria = e.categoria and ep.produto_id = t0.produto_id)
    ) p on true
    join fin.vw_transacoes_contas t on t.produto_id = p.produto_id and t.conta = e.conta_ev
     and (p.na_categoria or exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)) and t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1
     and ((p.papel = 'oferta' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)))
       or (p.papel = 'ingresso' and (exists (select 1 from fin.evento_ofertas eo where eo.evento_id = e.id and eo.oferta_codigo = t.oferta_codigo)
                                        or (not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
                                            and (t.aprovado_em at time zone 'America/Sao_Paulo')::date between e.ing_de and e.venda_ate))))
    join fin.hotmart_transacoes h on h.transacao = t.transacao and h.conta = t.conta
   order by p.papel desc, t.aprovado_em;
end $function$
;

-- public.fn_fin_funis()  md5(prosrc)=b72ed7dda46ecc1c6ff0c0ebf835e2a0
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
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de, case when e.setor = 'escritorio' and e.inicio >= date '2025-01-01' then 'escritorio' else 'academy' end conta_ev
      from fin.eventos e
  ), tx as (
    select t.conta, t.transacao, t.produto_id, t.oferta_codigo, t.email, t.grupo, (t.aprovado_em at time zone 'America/Sao_Paulo')::date dia,
           t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end valor,
           coalesce(t.liquido, t.valor_oferta - coalesce(t.taxa_hotmart, 0))
             * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end liq
      from fin.vw_transacoes_contas t
     where t.grupo in ('pago','estornado') and coalesce(t.recorrencia, 1) = 1 and t.email is not null
  ), casado as materialized (
    select e.id, p.papel, e.conta_ev, x.*
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
                 then 'ingresso' else 'oferta' end, e.conta_ev,
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
      from casado c where c.conta = c.conta_ev group by c.id
  )
  select e.id, e.nome, e.categoria, e.setor, e.inicio, e.fim, e.carrinho_inicio, e.venda_ate, e.ing_de,
         coalesce(a.ing_n, 0), round(coalesce(a.ing_b, 0), 2), round(coalesce(a.ing_l, 0), 2),
         coalesce(a.of_n, 0), coalesce(a.of_p, 0), coalesce(a.of_e, 0), round(coalesce(a.of_b, 0), 2), round(coalesce(a.of_l, 0), 2),
         coalesce(a.pess, 0), round(coalesce(a.ing_b, 0) + coalesce(a.of_b, 0), 2), round(coalesce(a.ing_l, 0) + coalesce(a.of_l, 0), 2),
         e.ref_vendas, e.ref_valor, e.ref_tipo, e.ref_fonte, e.observacao, (e.setor = 'escritorio' and e.inicio >= date '2025-01-01' and not exists (select 1 from fin.hotmart_contas hc where hc.conta = 'escritorio' and hc.ativa)), round(coalesce(a.liq_conf, 0), 2)
    from ev e left join agg a on a.id = e.id
   order by e.inicio desc;
end $function$
;

-- public.fn_fin_hotmart_funis(text,date,date)  md5(prosrc)=a36eed87268bb5ca192b3857d9e8476c
CREATE OR REPLACE FUNCTION public.fn_fin_hotmart_funis(p_familia text DEFAULT 'HM'::text, p_inicio date DEFAULT NULL::date, p_fim date DEFAULT NULL::date)
 RETURNS TABLE(funil text, vale_de date, vale_ate date, vendas integer, compradores integer, valor_oferta numeric, cobrado_cliente numeric, juros numeric, taxa_hotmart numeric, liquido numeric, estornos integer, valor_estornado numeric, recusadas integer, boletos integer, parcelado integer, parcelas_media numeric, entra_rapido numeric, retido numeric, retido_a_liberar numeric, custo_antecipacao numeric, liquido_total numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        v_ini  date := coalesce(p_inicio, date '2021-01-01');
        v_fim  date := coalesce(p_fim, v_hoje); v_conta text := case when exists (select 1 from fin.produtos p where p.familia = p_familia and p.conta = 'escritorio') and not exists (select 1 from fin.produtos p where p.familia = p_familia and p.conta <> 'escritorio') then 'escritorio' else 'academy' end;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with t as (
    select x.grupo, x.email, x.valor_oferta, x.valor_cobrado, x.juros, x.taxa_hotmart, x.liquido, x.parcelas,
           coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes_contas x where x.conta = v_conta and x.familia = p_familia
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

-- Crons (sem segredo). Repor com: select cron.alter_job(job_id := <id>, command := $cmd$<texto>$cmd$);
-- cron 57 fin-hotmart-rotina-todos (7 * * * *) md5=d59c72ba787e1a9a674af9290400ffd6
/*

  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo, status, tentativas)
  select '*', (now() at time zone 'America/Sao_Paulo')::date - 3, (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
   where not exists (select 1 from fin.hotmart_sync_fila where produto_id = '*' and tipo = 'rotina' and status in ('pendente','processando'))

*/
-- cron 61 fin-hotmart-rotina-todos-45dias (43 3 * * *) md5=fe0f14187f22a6d80ed4693467bba0a2
/*

  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo, status, tentativas)
  select '*', (now() at time zone 'America/Sao_Paulo')::date - 45, (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
   where not exists (
     select 1 from fin.hotmart_sync_fila
      where produto_id = '*' and tipo = 'rotina' and status in ('pendente','processando')
        and inicio = (now() at time zone 'America/Sao_Paulo')::date - 45
        and fim    = (now() at time zone 'America/Sao_Paulo')::date
   )

*/
