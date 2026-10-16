-- Ensaio de 20261017003000_dados_atm_resumo_grupo_aptos.sql (transação desfeita, sobre produção). Só agregados na saída: nenhum nome,
-- e-mail ou telefone. Personas no papel authenticated com JWT: Victor (master, contato.ver), jessica (contato.ver, não master),
-- QA Tráfego e Deborah (sem contato.ver); anon e service_role. Mede o tempo do resumo antes e depois, compara todas as colunas
-- antigas do resumo (têm de ficar iguais) e o valor novo com a contagem de aptos da RPC dados_atm_grupo_leads.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '120s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
create temp table _z_snap (quando text, quem text, chave text, j text) on commit drop;
grant all on pg_temp._z_out, pg_temp._z_snap to authenticated, anon, service_role;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon, service_role;
create function pg_temp.tenta(p_id uuid, p_sql text) returns text language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', case when p_id is null then '{"role":"anon"}' else jsonb_build_object('sub', p_id, 'role', 'authenticated')::text end, true);
  execute p_sql into v;
  return 'passou: ' || left(coalesce(v, 'null'), 900);
exception when others then return sqlstate || ' ' || sqlerrm;
end $t$;
grant execute on function pg_temp.tenta(uuid, text) to authenticated, anon, service_role;
-- foto do resumo (sem atualizado_em) por persona e chave: texto jsonb, ou sqlstate
create function pg_temp.foto(p_quando text, p_quem text, p_id uuid, p_chave text, p_de date default null, p_ate date default null) returns void language plpgsql as $t$
declare v text;
begin
  perform set_config('request.jwt.claims', case when p_quem = 'service_role' then '{"role":"service_role"}' when p_id is null then '{"role":"anon"}' else jsonb_build_object('sub', p_id, 'role', 'authenticated')::text end, true);
  begin
    select (to_jsonb(r) - 'atualizado_em')::text into strict v from public.dados_atm_resumo(p_chave, p_de, p_ate) r;
  exception when others then v := 'ERRO ' || sqlstate || ' ' || sqlerrm;
  end;
  insert into pg_temp._z_snap values (p_quando, p_quem, p_chave || coalesce(p_de::text, '') || coalesce(p_ate::text, ''), v);
end $t$;
grant execute on function pg_temp.foto(text, text, uuid, text, date, date) to authenticated, anon, service_role;

-- ANTES: fotos e tempo
set local role authenticated;
select pg_temp.foto('antes', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'black-thb-2026-10');
select pg_temp.foto('antes', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'atm-elaine-1-2026-10');
select pg_temp.foto('antes', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'black-thb-2026-10', '2026-10-14', '2026-10-15');
select pg_temp.foto('antes', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'atm-elaine-1-2026-10', '2026-10-10', '2026-10-12');
select pg_temp.foto('antes', 'jessica', '012bbcd3-cade-4889-a6ff-4804ed15c36d', 'black-thb-2026-10');
select pg_temp.foto('antes', 'qa', '6e8d878d-086c-4b12-bef7-c424d89d85b6', 'black-thb-2026-10');
select pg_temp.foto('antes', 'deborah', '5231a48f-a2d9-4c5f-8ee4-cde459aa7a9e', 'black-thb-2026-10');
select pg_temp.foto('antes', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'black-friday-2026-10');
reset role;
set local role anon;
select pg_temp.foto('antes', 'anon', null, 'black-thb-2026-10');
reset role;
set local role service_role;
select pg_temp.foto('antes', 'service_role', null, 'atm-elaine-1-2026-10');
reset role;

do $x$ declare r record; n int; c text; p record; begin
  for p in select * from (values ('victor','81d2eaee-cce1-4058-8714-439b0fc6f970'),('qa_sem_contato_ver','6e8d878d-086c-4b12-bef7-c424d89d85b6')) v(quem, id) loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', p.id::uuid, 'role', 'authenticated')::text, true);
    foreach c in array array['black-thb-2026-10', 'atm-elaine-1-2026-10'] loop
      for n in 1..3 loop
        for r in execute format('explain (analyze) select * from public.dados_atm_resumo(%L)', c) loop
          if r."QUERY PLAN" ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('1 antes tempo ' || p.quem || ' ' || c || ' #' || n, r."QUERY PLAN"); end if;
        end loop;
      end loop;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

-- A MIGRATION
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure)
      is distinct from 'ef79ceaf4be011738937f8adc3a8451a' then
    raise exception '20261017003000: corpo vivo de dados_atm_resumo mudou; revisar';
  end if;
  if to_regprocedure('dados.atm_leads(text)') is null or to_regclass('dados.v_grupo_pessoas_todos') is null
     or to_regclass('dados.lista_membros') is null or to_regprocedure('acesso.tem(text)') is null then
    raise exception '20261017003000: dependência ausente';
  end if;
end
$g$;

drop function public.dados_atm_resumo(text, date, date);

create function public.dados_atm_resumo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text, disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric, custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint, pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint, receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric, atualizado_em timestamp with time zone, periodo_de date, periodo_ate date, leads_teste integer, grupo_teste integer, vendas_teste integer, receita_teste_bruta numeric, grupo_entradas_aproximadas integer, grupo_foto_em timestamp with time zone, grupo_no_grupo integer, custo_trafego_centavos bigint, investimento_total_centavos bigint, grupo_aptos integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  -- 20261017003000: grupo_aptos só para quem vê contato (a conta dos aptos nem roda para os outros)
  v_ver boolean := coalesce(acesso.tem('contato.ver'), false);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with disp as (
    -- 20261009210000: e-mail e grupo não têm custo por disparo (custo nulo = sem custo, não falta); só canal pago
    -- (whatsapp_api, sms, ligacao) sem custo deixa o custo incompleto
    select count(*)::int as qtd,
           count(*) filter (where x.custo_centavos is null and x.canal not in ('email', 'grupo'))::int as sem,
           case when count(*) > 0 then coalesce(sum(x.custo_centavos), 0) end::bigint as custo,
           sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
       and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
  ),
  -- 20261009230000: tráfego pago das campanhas ligadas ao projeto (mkt_trafego, conta em BRL), por dia de veiculação
  tf as (
    select round(coalesce(sum(dd.gasto), 0) * 100)::bigint as custo
      from mkt_trafego.desempenho_dia dd
      join mkt_trafego.campanhas c on c.id = dd.campanha_id
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
     where c.projeto_id = d.projeto_id
       and dd.dia >= coalesce(v_de, '-infinity'::date) and dd.dia <= coalesce(v_ate, 'infinity'::date)
  ),
  inv as (select coalesce(disp.custo, 0) + tf.custo as total from disp cross join tf),
  -- 20261017003000: atm_leads lido uma vez; lt é o período (como antes) e ap_ld, sem período, é a base da conta dos aptos
  la as materialized (select * from dados.atm_leads(d.chave) x),
  lt as (select * from la x where x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ld as (select * from lt where not lt.teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim)::int as entradas,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.entrada_aproximada)::int as aprox,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.no_grupo)::int as no_agora,
           (select max(f.concluido_em) from dados.grupo_fotos f join dados.dashboard_grupos dg on dg.id = f.grupo_id
             where dg.chave = d.chave and f.etapa = 'feito') as foto_em,
           count(*) filter (where g.entrou_em is not null and g.saiu_em >= g.entrou_em
                              and g.saiu_em >= v_ini and g.saiu_em < v_fim)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  gt as (
    select count(*)::int as n from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave and e.teste and e.entrou_em >= v_ini and e.entrou_em < v_fim
  ),
  -- 20261017003000: aptos do grupo = a mesma conta da coluna apto de public.dados_atm_grupo_leads (20261016234500), só a contagem:
  -- números do grupo no período, sem teste, que estão na lista do disparo pelo telefone ou pelo e-mail achado na base de leads ou
  -- na Central de Alunos. Se mudar lá, mudar aqui (o ensaio compara as duas). `where v_ver` desliga tudo para quem não vê contato.
  ap_g as (
    select p.fone8, p.pessoa_id
      from dados.v_grupo_pessoas_todos p
     where v_ver and p.chave = d.chave and p.entrou_em >= v_ini and p.entrou_em < v_fim and not p.teste
  ),
  ap_lst as materialized (
    select distinct right(controle.fone_key(a.telefone), 8) as fk8
      from dados.lista_membros m
      join public.thb_alunos a on pessoas.norm_email(a.email) = m.email_norm
     where v_ver and m.chave = d.chave and a.telefone is not null
  ),
  ap_ld as materialized (
    select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id, x.email, x.primeiro_em
      from la x
     where v_ver and not coalesce(x.teste, false)
  ),
  ap_ce as materialized (
    select distinct on (t.fk8) t.fk8, t.email
      from (select right(controle.fone_key(f.tel), 8) as fk8, pessoas.norm_email(a.email) as email, a.eh_socio, a.id
              from public.thb_alunos a
             cross join lateral (values (a.telefone), (a.telefone_e164), (a.telefone_profissional)) f(tel)
             where v_ver and nullif(btrim(f.tel), '') is not null) t
     where length(t.fk8) = 8 and t.fk8 in (select g.fone8 from ap_g g)
     order by t.fk8, exists (select 1 from dados.lista_membros m where m.chave = d.chave and m.email_norm = t.email) desc, t.eh_socio, t.id
  ),
  ap as (
    select count(*)::int as n
      from (select (l.fk8 is not null) as em_lista, b.email as b_email, k.email as k_email
              from ap_g g
              left join ap_lst l on l.fk8 = g.fone8
              left join lateral (select y.email from ap_ld y
                                  where y.fk8 = g.fone8 or (g.pessoa_id is not null and y.pessoa_id = g.pessoa_id)
                                  order by (y.fk8 = g.fone8) desc, y.primeiro_em limit 1) b on true
              left join ap_ce k on k.fk8 = g.fone8) c
     where c.em_lista or exists (select 1 from dados.lista_membros m
                                  where m.chave = d.chave and m.email_norm is not null
                                    and m.email_norm = any (array[pessoas.norm_email(c.b_email), pessoas.norm_email(c.k_email)]))
  ),
  pc as (select y.email from dados.atm_pre_checkout(d.chave) y where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select * from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  txt as (select count(*)::int as n, coalesce(sum(v.valor_bruto) filter (where v.moeda = 'BRL'), 0)::numeric(14,2) as bruta
            from dados.atm_vendas_todas(d.chave) v
           where v.teste and v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from lt where lt.teste) as leads_teste,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  -- 20261009230000: completo = há investimento (disparo ou tráfego) e nenhum disparo pago sem custo
  k as (select ((disp.qtd > 0 or tf.custo > 0) and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta
          from disp cross join tf)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         -- 20261009230000 (decisão do Victor): CPL, CAC e ROAS sobre o investimento total (tráfego + disparo)
         case when k.completo and ag.leads > 0 then round(inv.total::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(inv.total::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and inv.total > 0 then round(ag.bruta * 100 / inv.total, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and inv.total > 0 then round(ag.liq * 100 / inv.total, 2)::numeric(10,2) end,
         now(),
         v_de, v_ate, ag.leads_teste, case when gr.fonte then gt.n end,
         case when k.tem_oferta then txt.n end, case when k.tem_oferta then txt.bruta end,
         case when gr.fonte then gr.aprox end, gr.foto_em, case when gr.fonte then gr.no_agora end,
         tf.custo, inv.total,
         case when gr.fonte and v_ver then ap.n end
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join gt cross join txt cross join k
         cross join tf cross join inv cross join ap
   where pr.id = d.projeto_id;
end
$function$;

comment on function public.dados_atm_resumo(text, date, date) is
  '20261017003000: números do funil do dashboard ATM e das Ações da Black. grupo_aptos = números do grupo que estão na lista do disparo (mesma conta de dados_atm_grupo_leads.apto), só com contato.ver.';

revoke all on function public.dados_atm_resumo(text, date, date) from public, anon;
grant execute on function public.dados_atm_resumo(text, date, date) to authenticated, service_role;

-- DEPOIS: fotos e tempo
insert into pg_temp._z_out (passo, linha) select '2 acl do resumo', (select proacl::text from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure);
insert into pg_temp._z_out (passo, linha) select '2 search_path e segurança do resumo', (select proconfig::text || ' definer=' || prosecdef::text || ' volatilidade=' || provolatile::text from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure);
set local role authenticated;
select pg_temp.foto('depois', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'black-thb-2026-10');
select pg_temp.foto('depois', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'atm-elaine-1-2026-10');
select pg_temp.foto('depois', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'black-thb-2026-10', '2026-10-14', '2026-10-15');
select pg_temp.foto('depois', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'atm-elaine-1-2026-10', '2026-10-10', '2026-10-12');
select pg_temp.foto('depois', 'jessica', '012bbcd3-cade-4889-a6ff-4804ed15c36d', 'black-thb-2026-10');
select pg_temp.foto('depois', 'qa', '6e8d878d-086c-4b12-bef7-c424d89d85b6', 'black-thb-2026-10');
select pg_temp.foto('depois', 'deborah', '5231a48f-a2d9-4c5f-8ee4-cde459aa7a9e', 'black-thb-2026-10');
select pg_temp.foto('depois', 'victor', '81d2eaee-cce1-4058-8714-439b0fc6f970', 'black-friday-2026-10');
reset role;
set local role anon;
select pg_temp.foto('depois', 'anon', null, 'black-thb-2026-10');
reset role;
set local role service_role;
select pg_temp.foto('depois', 'service_role', null, 'atm-elaine-1-2026-10');
reset role;

do $x$ declare r record; n int; c text; p record; begin
  for p in select * from (values ('victor','81d2eaee-cce1-4058-8714-439b0fc6f970'),('qa_sem_contato_ver','6e8d878d-086c-4b12-bef7-c424d89d85b6')) v(quem, id) loop
    perform set_config('request.jwt.claims', jsonb_build_object('sub', p.id::uuid, 'role', 'authenticated')::text, true);
    foreach c in array array['black-thb-2026-10', 'atm-elaine-1-2026-10'] loop
      for n in 1..3 loop
        for r in execute format('explain (analyze) select * from public.dados_atm_resumo(%L)', c) loop
          if r."QUERY PLAN" ~ 'Execution Time' then insert into pg_temp._z_out (passo, linha) values ('3 depois tempo ' || p.quem || ' ' || c || ' #' || n, r."QUERY PLAN"); end if;
        end loop;
      end loop;
    end loop;
  end loop;
end $x$;
select set_config('request.jwt.claims', '', true);

-- COMPARAÇÕES
insert into pg_temp._z_out (passo, linha)
select '4 colunas antigas iguais antes x depois: ' || a.quem || ' ' || a.chave,
       case when a.j like 'ERRO%' or d.j like 'ERRO%' then 'sem foto: antes=' || left(a.j, 60) || ' | depois=' || left(d.j, 60)
            else ((a.j::jsonb) = ((d.j::jsonb) - 'grupo_aptos'))::text end
  from pg_temp._z_snap a join pg_temp._z_snap d on d.quando = 'depois' and d.quem = a.quem and d.chave = a.chave
 where a.quando = 'antes' order by 1;
insert into pg_temp._z_out (passo, linha)
select '5 grupo_aptos e grupo_entradas depois: ' || d.quem || ' ' || d.chave,
       case when d.j like 'ERRO%' then left(d.j, 80)
            else 'grupo_aptos=' || coalesce((d.j::jsonb)->>'grupo_aptos', 'nulo') || ' grupo_entradas=' || coalesce((d.j::jsonb)->>'grupo_entradas', 'nulo') end
  from pg_temp._z_snap d where d.quando = 'depois' order by 1;
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '6 resumo x RPC black-thb Victor', pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object(
  'resumo_aptos', (select grupo_aptos from public.dados_atm_resumo('black-thb-2026-10')), 'rpc_aptos', (select count(*) filter (where apto) from public.dados_atm_grupo_leads('black-thb-2026-10')),
  'resumo_entradas', (select grupo_entradas from public.dados_atm_resumo('black-thb-2026-10')), 'rpc_linhas', (select count(*) from public.dados_atm_grupo_leads('black-thb-2026-10')))::text$q$);
insert into pg_temp._z_out (passo, linha) select '6 resumo x RPC atm Victor', pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object(
  'resumo_aptos', (select grupo_aptos from public.dados_atm_resumo('atm-elaine-1-2026-10')), 'rpc_aptos', (select count(*) filter (where apto) from public.dados_atm_grupo_leads('atm-elaine-1-2026-10')),
  'resumo_entradas', (select grupo_entradas from public.dados_atm_resumo('atm-elaine-1-2026-10')), 'rpc_linhas', (select count(*) from public.dados_atm_grupo_leads('atm-elaine-1-2026-10')))::text$q$);
insert into pg_temp._z_out (passo, linha) select '6 resumo x RPC black-thb 14 a 15/10 Victor', pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object(
  'resumo_aptos', (select grupo_aptos from public.dados_atm_resumo('black-thb-2026-10', '2026-10-14', '2026-10-15')), 'rpc_aptos', (select count(*) filter (where apto) from public.dados_atm_grupo_leads('black-thb-2026-10', '2026-10-14', '2026-10-15')),
  'resumo_entradas', (select grupo_entradas from public.dados_atm_resumo('black-thb-2026-10', '2026-10-14', '2026-10-15')), 'rpc_linhas', (select count(*) from public.dados_atm_grupo_leads('black-thb-2026-10', '2026-10-14', '2026-10-15')))::text$q$);
insert into pg_temp._z_out (passo, linha) select '6 resumo x RPC atm 10 a 12/10 Victor', pg_temp.tenta('81d2eaee-cce1-4058-8714-439b0fc6f970', $q$select jsonb_build_object(
  'resumo_aptos', (select grupo_aptos from public.dados_atm_resumo('atm-elaine-1-2026-10', '2026-10-10', '2026-10-12')), 'rpc_aptos', (select count(*) filter (where apto) from public.dados_atm_grupo_leads('atm-elaine-1-2026-10', '2026-10-10', '2026-10-12')),
  'resumo_entradas', (select grupo_entradas from public.dados_atm_resumo('atm-elaine-1-2026-10', '2026-10-10', '2026-10-12')), 'rpc_linhas', (select count(*) from public.dados_atm_grupo_leads('atm-elaine-1-2026-10', '2026-10-10', '2026-10-12')))::text$q$);
insert into pg_temp._z_out (passo, linha) select '6 resumo x RPC black-thb jessica', pg_temp.tenta('012bbcd3-cade-4889-a6ff-4804ed15c36d', $q$select jsonb_build_object(
  'resumo_aptos', (select grupo_aptos from public.dados_atm_resumo('black-thb-2026-10')), 'rpc_aptos', (select count(*) filter (where apto) from public.dados_atm_grupo_leads('black-thb-2026-10')),
  'resumo_entradas', (select grupo_entradas from public.dados_atm_resumo('black-thb-2026-10')), 'rpc_linhas', (select count(*) from public.dados_atm_grupo_leads('black-thb-2026-10')))::text$q$);
reset role;
select set_config('request.jwt.claims', '', true);

-- reversão ensaiada (o texto de 20261017003000_reversao.sql)
set local lock_timeout = '3s';
set local statement_timeout = '10s';

drop function if exists public.dados_atm_resumo(text, date, date);

create function public.dados_atm_resumo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date)
 RETURNS TABLE(chave text, projeto_id bigint, projeto_sigla text, projeto_nome text, oferta_codigo text, disparos_qtd integer, disparos_enviados integer, leads integer, grupo_tem_fonte boolean, grupo_entradas integer, grupo_saidas integer, grupo_pct numeric, evasao_pct numeric, custo_disparo_centavos bigint, disparos_sem_custo integer, custo_completo boolean, cpl_centavos bigint, pre_checkout_pessoas integer, vendas integer, vendas_fora_brl integer, compradores integer, compradores_no_pre_checkout integer, conversao_pre_checkout_pct numeric, cac_centavos bigint, receita_bruta numeric, receita_liquida numeric, roas numeric, roas_liquido numeric, atualizado_em timestamp with time zone, periodo_de date, periodo_ate date, leads_teste integer, grupo_teste integer, vendas_teste integer, receita_teste_bruta numeric, grupo_entradas_aproximadas integer, grupo_foto_em timestamp with time zone, grupo_no_grupo integer, custo_trafego_centavos bigint, investimento_total_centavos bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_de date; v_ate date; v_ini timestamptz; v_fim timestamptz;
begin
  select x.de, x.ate, x.ini, x.fim into v_de, v_ate, v_ini, v_fim
    from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with disp as (
    -- 20261009210000: e-mail e grupo não têm custo por disparo (custo nulo = sem custo, não falta); só canal pago
    -- (whatsapp_api, sms, ligacao) sem custo deixa o custo incompleto
    select count(*)::int as qtd,
           count(*) filter (where x.custo_centavos is null and x.canal not in ('email', 'grupo'))::int as sem,
           case when count(*) > 0 then coalesce(sum(x.custo_centavos), 0) end::bigint as custo,
           sum(x.tamanho_lista)::int as enviados
      from mkt_mensageria.disparos x
     where x.projeto_id = d.projeto_id and x.arquivado_em is null
       and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
  ),
  -- 20261009230000: tráfego pago das campanhas ligadas ao projeto (mkt_trafego, conta em BRL), por dia de veiculação
  tf as (
    select round(coalesce(sum(dd.gasto), 0) * 100)::bigint as custo
      from mkt_trafego.desempenho_dia dd
      join mkt_trafego.campanhas c on c.id = dd.campanha_id
      join mkt_trafego.contas ct on ct.id = c.conta_id and ct.moeda = 'BRL'
     where c.projeto_id = d.projeto_id
       and dd.dia >= coalesce(v_de, '-infinity'::date) and dd.dia <= coalesce(v_ate, 'infinity'::date)
  ),
  inv as (select coalesce(disp.custo, 0) + tf.custo as total from disp cross join tf),
  lt as (select * from dados.atm_leads(d.chave) x where x.primeiro_em >= v_ini and x.primeiro_em < v_fim),
  ld as (select * from lt where not lt.teste),
  gr as (
    select exists (select 1 from dados.dashboard_grupos g where g.chave = d.chave) as fonte,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim)::int as entradas,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.entrada_aproximada)::int as aprox,
           count(*) filter (where g.entrou_em >= v_ini and g.entrou_em < v_fim and g.no_grupo)::int as no_agora,
           (select max(f.concluido_em) from dados.grupo_fotos f join dados.dashboard_grupos dg on dg.id = f.grupo_id
             where dg.chave = d.chave and f.etapa = 'feito') as foto_em,
           count(*) filter (where g.entrou_em is not null and g.saiu_em >= g.entrou_em
                              and g.saiu_em >= v_ini and g.saiu_em < v_fim)::int as saidas
      from dados.v_grupo_pessoas g where g.chave = d.chave
  ),
  gt as (
    select count(*)::int as n from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave and e.teste and e.entrou_em >= v_ini and e.entrou_em < v_fim
  ),
  pc as (select y.email from dados.atm_pre_checkout(d.chave) y where y.primeiro_em >= v_ini and y.primeiro_em < v_fim),
  tx as (select * from dados.atm_vendas(d.chave) v where v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  txt as (select count(*)::int as n, coalesce(sum(v.valor_bruto) filter (where v.moeda = 'BRL'), 0)::numeric(14,2) as bruta
            from dados.atm_vendas_todas(d.chave) v
           where v.teste and v.aprovado_em >= v_ini and v.aprovado_em < v_fim),
  ag as (
    select (select count(*)::int from ld) as leads,
           (select count(*)::int from lt where lt.teste) as leads_teste,
           (select count(*)::int from pc) as pc,
           (select count(*)::int from tx) as vendas,
           (select count(*)::int from tx where tx.moeda <> 'BRL') as fora,
           (select count(distinct tx.email)::int from tx) as comp,
           (select count(distinct tx.email)::int from tx where exists (select 1 from pc where pc.email = tx.email)) as comp_pc,
           (select coalesce(sum(tx.valor_bruto), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as bruta,
           (select coalesce(sum(tx.valor_liquido), 0) from tx where tx.moeda = 'BRL')::numeric(14,2) as liq
  ),
  -- 20261009230000: completo = há investimento (disparo ou tráfego) e nenhum disparo pago sem custo
  k as (select ((disp.qtd > 0 or tf.custo > 0) and disp.sem = 0) as completo, d.oferta_codigo is not null as tem_oferta
          from disp cross join tf)
  select d.chave, pr.id, pr.sigla, pr.nome, d.oferta_codigo,
         disp.qtd, disp.enviados, ag.leads,
         gr.fonte,
         case when gr.fonte then gr.entradas end,
         case when gr.fonte then gr.saidas end,
         case when gr.fonte and ag.leads > 0 then round(gr.entradas::numeric * 100 / ag.leads, 2)::numeric(7,2) end,
         case when gr.fonte and gr.entradas > 0 then round(gr.saidas::numeric * 100 / gr.entradas, 2)::numeric(7,2) end,
         disp.custo, disp.sem, k.completo,
         -- 20261009230000 (decisão do Victor): CPL, CAC e ROAS sobre o investimento total (tráfego + disparo)
         case when k.completo and ag.leads > 0 then round(inv.total::numeric / ag.leads)::bigint end,
         ag.pc,
         case when k.tem_oferta then ag.vendas end,
         case when k.tem_oferta then ag.fora end,
         case when k.tem_oferta then ag.comp end,
         case when k.tem_oferta then ag.comp_pc end,
         case when k.tem_oferta and ag.pc > 0 then round(ag.comp::numeric * 100 / ag.pc, 2)::numeric(7,2) end,
         case when k.tem_oferta and k.completo and ag.vendas > 0 then round(inv.total::numeric / ag.vendas)::bigint end,
         case when k.tem_oferta then ag.bruta end,
         case when k.tem_oferta then ag.liq end,
         case when k.tem_oferta and k.completo and inv.total > 0 then round(ag.bruta * 100 / inv.total, 2)::numeric(10,2) end,
         case when k.tem_oferta and k.completo and inv.total > 0 then round(ag.liq * 100 / inv.total, 2)::numeric(10,2) end,
         now(),
         v_de, v_ate, ag.leads_teste, case when gr.fonte then gt.n end,
         case when k.tem_oferta then txt.n end, case when k.tem_oferta then txt.bruta end,
         case when gr.fonte then gr.aprox end, gr.foto_em, case when gr.fonte then gr.no_agora end,
         tf.custo, inv.total
    from mkt.projetos pr cross join disp cross join ag cross join gr cross join gt cross join txt cross join k
         cross join tf cross join inv
   where pr.id = d.projeto_id;
end
$function$;

comment on function public.dados_atm_resumo(text, date, date) is null;
revoke all on function public.dados_atm_resumo(text, date, date) from public, anon;
grant execute on function public.dados_atm_resumo(text, date, date) to authenticated, service_role;

insert into pg_temp._z_out (passo, linha) select '7 depois da reversão: retorno tem grupo_aptos?', (pg_get_function_result('public.dados_atm_resumo(text,date,date)'::regprocedure) like '%grupo_aptos%')::text;
insert into pg_temp._z_out (passo, linha) select '7 depois da reversão: md5 do corpo = o de antes?', (select (md5(prosrc) = 'ef79ceaf4be011738937f8adc3a8451a')::text from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure);
insert into pg_temp._z_out (passo, linha) select '7 depois da reversão: acl', (select proacl::text from pg_proc where oid = 'public.dados_atm_resumo(text,date,date)'::regprocedure);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
