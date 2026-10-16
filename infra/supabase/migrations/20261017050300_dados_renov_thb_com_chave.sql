-- 20261017050300: public.dados_renov_thb(p_chave, p_incluir_teste), a RPC do painel /renov passa a ser DA AÇÃO (chave), igual ao resto do dashboard.
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-renov-padrao). Só foi rodado o ENSAIO (begin ... rollback).
--   Ensaio: 20261017050300_ensaio.sql. Reversão: 20261017050300_reversao.sql. Detalhe: 20261017050300.explain.md.
--
-- POR QUE: a versão de hoje, dados_renov_thb(boolean) (20261016173552), (1) tem as ofertas nv5f10zq/wftji6dl e a conta 'academy' fixas no SQL,
--   (2) não passa pela guarda do dashboard (dados.atm_cadastro: qualquer usuário autenticado chama; o contato só é filtrado por contato.ver),
--   (3) conta venda por regra própria (todas as aprovadas, inclusive recorrências, sem vendas_desde), então pode divergir do card Vendas da ação,
--   (4) só conhece o teste pela coluna metodo.renov_aplicacoes.teste, não pela marcação padrão do dashboard (dados.marcacoes_teste).
-- O QUE FAZ: cria uma versão NOVA AO LADO da antiga (a doc de banco manda: função que substitui outra liga em 2 etapas). A antiga
--   (boolean) NÃO é tocada aqui; sai numa migration própria, depois que o front novo estiver publicado e uma execução real provar esta.
--   Assinatura nova: (p_chave text, p_incluir_teste boolean default false). Mesmo retorno jsonb, com as MESMAS chaves da v2 e mais:
--     chave, sem_oferta, vendas_total, valor_total, vendas_fora_brl; por aplicação: teste_coluna, teste_marcado.
--   Regras:
--     guarda      dados.atm_cadastro(p_chave): 42501 para quem não é da equipe, P0002 para chave fora do cadastro ou de outro modelo.
--     ofertas     dados.dashboards da chave: oferta_codigo + ofertas_extra, conta_hotmart (não há mais código fixo no SQL).
--     vendas      dados.transacoes(conta, oferta) (a mesma fonte do card, com o ramo do webhook), pago + primeira + vendas_desde, e o comprador
--                 marcado como teste (dados.teste_ativo) sai, a menos que p_incluir_teste. Logo vendas_total/valor_total fecham com o card Vendas.
--                 O código da oferta de cada venda vem de fin.hotmart_transacoes ou, se só o webhook conhece, do payload do webhook.
--     aplicações  metodo.renov_aplicacoes cuja origem aponta, em metodo.origem_etiqueta, para p_chave (20261017050100).
--     teste       a.teste (coluna legada) OU e-mail @advmais.com OU marcação ativa da chave por e-mail ou pelos 8 últimos dígitos do telefone.
--     contato     nome, e-mail e telefone só com acesso.tem('contato.ver'), como antes.
--     aplicaram_e_pagaram agora por e-mail distinto (já era na v2).
-- QUEM CHAMA: o painel PainelRenovThb (web/modules/infra/acoes/ui). Nenhum outro sistema (grep em 16/10/2026).
-- COMO VOLTAR: 20261017050300_reversao.sql (apaga só a função nova; a antiga segue como está).
-- AS 5 PERGUNTAS: escala = 11 aplicações e 1 acesso hoje; a lista de aplicações tem limite 500 e a de vendas 50; as vendas vêm da mesma fonte do
--   card (a que o resumo da ação já lê em cerca de 1 s). índice = as leituras de renov_aplicacoes são por varredura (tabela pequena, 11 linhas),
--   a de marcacoes_teste usa o índice marcacoes_teste_chave_idx. frequência = ao abrir o painel, no Atualizar e ao ligar "ver testes"
--   (o front lê 1 vez por ação do usuário, nunca em laço). repetição = 1 chamada alimenta o painel todo. reversão = arquivo.
-- DADO PESSOAL: nome, e-mail e telefone saem só com contato.ver. A função grava nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('public.dados_renov_thb(text,boolean)') is not null then
    raise exception '20261017050300: public.dados_renov_thb(text,boolean) já existe; revisar';
  end if;
  if to_regprocedure('public.dados_renov_thb(boolean)') is null then
    raise exception '20261017050300: falta a versão atual dados_renov_thb(boolean) (20261016173552)';
  end if;
  if to_regprocedure('dados.atm_cadastro(text)') is null or to_regprocedure('dados.teste_ativo(text,text,text)') is null
     or to_regprocedure('dados.transacoes(text,text)') is null then
    raise exception '20261017050300: faltam dados.atm_cadastro, dados.teste_ativo ou dados.transacoes';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.renov_visitas') is null then
    raise exception '20261017050300: faltam metodo.renov_aplicacoes (20261016163924) ou metodo.renov_visitas (20261016172921)';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050300: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100)';
  end if;
  if not exists (select 1 from dados.dashboards where chave = 'black-thb-2026-10' and modelo = 'acao-black' and oferta_codigo is not null) then
    raise exception '20261017050300: black-thb-2026-10 sem oferta ligada (20261017050000)';
  end if;
end
$g$;

create function public.dados_renov_thb(p_chave text, p_incluir_teste boolean default false)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe; P0002 chave fora do cadastro ou outro modelo
  v_conta text := d.conta_hotmart;
  v_ofertas text[] := case when d.oferta_codigo is null then '{}'::text[] else array[d.oferta_codigo] || coalesce(d.ofertas_extra, '{}'::text[]) end;
  v_ver boolean := coalesce(acesso.tem('contato.ver'), false);
  v jsonb;
begin
  with base as (
    select a.*, lower(a.email) like '%@advmais.com' as advmais, m.marcado,
           (a.teste or lower(a.email) like '%@advmais.com' or m.marcado) as teste_efetivo
    from metodo.renov_aplicacoes a
    join metodo.origem_etiqueta o on o.origem = a.origem and o.etiqueta = p_chave
    cross join lateral (select dados.teste_ativo(p_chave, a.email, a.telefone) as marcado) m
  ), ap as (
    select * from base where p_incluir_teste or not teste_efetivo
  ), reais as (
    select * from base where not teste_efetivo
  ), mapa as (
    select distinct on (x.transacao) x.transacao, x.oferta_codigo
    from (
      select t.transacao, t.oferta_codigo
        from (select * from fin.hotmart_transacoes where conta = v_conta) t
       where t.oferta_codigo = any (v_ofertas)
      union all
      select e.transacao, e.payload #>> '{data,purchase,offer,code}'
        from cs.hotmart_eventos e
       where v_conta = 'academy' and e.transacao is not null and e.evento like 'PURCHASE%'
         and e.payload #>> '{data,purchase,offer,code}' = any (v_ofertas)
         and not exists (select 1 from (select * from fin.hotmart_transacoes where conta = v_conta) h where h.transacao = e.transacao)
    ) x
    order by x.transacao, x.oferta_codigo
  ), vd as (
    select t.transacao, t.status, t.valor_bruto, t.moeda, coalesce(t.aprovado_em, t.pedido_em) as em, t.email, t.nome,
           mp.oferta_codigo as oferta, dados.teste_ativo(p_chave, t.email, null) as teste_v
    from dados.transacoes(v_conta, d.oferta_codigo) t
    left join mapa mp on mp.transacao = t.transacao
    where d.oferta_codigo is not null and t.pago and t.primeira
      and (d.vendas_desde is null or coalesce(t.pedido_em, t.aprovado_em) >= d.vendas_desde)
  ), vdv as (
    select * from vd where p_incluir_teste or not teste_v
  ), ap_mais as (
    select ap.*,
           exists (select 1 from vdv where vdv.email = lower(ap.email)) as pagou,
           case when ap.visitante is null then null
                else (select count(*) from metodo.renov_visitas rv where rv.visitante = ap.visitante and rv.criado_em <= ap.criado_em) end as acessos_antes
    from ap
  ), vis as (
    select count(*) as acessos, count(distinct visitante) as visitantes from metodo.renov_visitas
  )
  select jsonb_build_object(
    'atualizado_em', now(),
    'chave', p_chave,
    'sem_oferta', d.oferta_codigo is null,
    'aplicacoes_total', (select count(*) from reais),
    'por_opcao', (select coalesce(jsonb_object_agg(opcao, n), '{}'::jsonb) from (select opcao, count(*) n from reais group by opcao) x),
    'aplicaram_e_pagaram', (select count(distinct lower(r.email)) from reais r where r.opcao <> 'nao-renovar' and exists (select 1 from vdv where vdv.email = lower(r.email))),
    'acessos', (select acessos from vis),
    'visitantes', (select visitantes from vis),
    'visitantes_que_aplicaram', (select count(distinct visitante) from reais where visitante is not null),
    'vendas', (select coalesce(jsonb_agg(jsonb_build_object('oferta', o.cod, 'vendas', coalesce(s.n, 0), 'valor', coalesce(s.v, 0)) order by o.ord), '[]'::jsonb)
               from unnest(v_ofertas) with ordinality o(cod, ord)
               left join (select oferta, count(*) n, sum(valor_bruto) filter (where moeda = 'BRL') v from vdv group by oferta) s on s.oferta = o.cod),
    'vendas_total', (select count(*) from vdv),
    'valor_total', (select coalesce(sum(valor_bruto) filter (where moeda = 'BRL'), 0) from vdv),
    'vendas_fora_brl', (select count(*) from vdv where moeda <> 'BRL'),
    'aplicacoes', (select coalesce(jsonb_agg(jsonb_build_object(
                     'id', id, 'criado_em', criado_em, 'opcao', opcao, 'origem', coalesce(utm_source, ''), 'pagou', pagou,
                     'teste', teste_efetivo, 'teste_fixo', advmais, 'teste_coluna', teste, 'teste_marcado', marcado,
                     'acessos_antes', acessos_antes,
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end,
                     'telefone', case when v_ver then telefone end) order by criado_em desc), '[]'::jsonb)
                   from (select * from ap_mais order by criado_em desc limit 500) l),
    'ultimas_vendas', (select coalesce(jsonb_agg(jsonb_build_object(
                     'em', em, 'oferta', oferta, 'valor', valor_bruto, 'status', status,
                     'aplicou', exists (select 1 from reais r where lower(r.email) = vd2.email),
                     'nome', case when v_ver then nome end, 'email', case when v_ver then email end) order by em desc), '[]'::jsonb)
                   from (select * from vdv order by em desc limit 50) vd2),
    've_contato', v_ver,
    'eh_master', coalesce(acesso.eh_master(), false)
  ) into v;
  return v;
end;
$function$;

revoke all on function public.dados_renov_thb(text, boolean) from public, anon;
grant execute on function public.dados_renov_thb(text, boolean) to authenticated, service_role;

comment on function public.dados_renov_thb(text, boolean) is
  'Painel do /renov da ação (chave): aplicações da página, acessos e vendas das ofertas da ação, com o teste padrão do dashboard (dados.marcacoes_teste). 16/10/2026.';

do $a$
begin
  if has_function_privilege('anon', 'public.dados_renov_thb(text,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_renov_thb(text,boolean)', 'execute') then
    raise exception '20261017050300: ACL da função nova fora do esperado (anon sem, authenticated com)';
  end if;
end
$a$;
