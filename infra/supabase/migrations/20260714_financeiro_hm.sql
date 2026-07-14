-- Módulo Financeiro — contas a receber do Holding Master.
--
-- Contexto: o pacote HM custa R$ 15.000. O aluno paga um SINAL de R$ 300 na
-- Hotmart (sinalização de compra) e o SALDO de R$ 14.700 conforme acordo com o
-- financeiro. A engine de cálculo (pró-rata, crédito, razão de pagamentos) já
-- existia no schema `cs` (sistema de ativação); aqui não a duplicamos — só
-- expomos ao app do Grupo Participa.
--
-- Por que RPC e não tabela/view direta: o schema `cs` NÃO é exposto ao PostgREST
-- (authenticated não tem USAGE nele; só o role `disparos_app` acessa). Então o
-- acesso é por função SECURITY DEFINER com guard de permissão explícito — mesmo
-- padrão de fn_aluno_360.
--
-- Aplicada em produção em 2026-07-14.

-- ---------------------------------------------------------------------------
-- 1) Permissões — área 'financeiro' no modelo cargo + areas + funcoes
--    Nota: ao contrário de gp_pode_editar(), 'visualizador' NÃO entra aqui.
--    Quem tem visão geral de leitura não enxerga dinheiro.
-- ---------------------------------------------------------------------------
create or replace function public.gp_pode_ver_financeiro()
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and (p.cargo in ('dev','admin')
           or (p.cargo in ('gestor','operador') and 'financeiro' = any(coalesce(p.areas,'{}'))))
  );
$$;

create or replace function public.gp_pode_operar_financeiro()
returns boolean language sql stable security definer set search_path to 'public'
as $$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and (p.cargo in ('dev','admin')
           or (p.cargo = 'gestor' and 'financeiro' = any(coalesce(p.areas,'{}')))
           or (p.cargo = 'operador'
               and 'financeiro' = any(coalesce(p.areas,'{}'))
               and 'financeiro.operar' = any(coalesce(p.funcoes,'{}'))))
  );
$$;

grant execute on function public.gp_pode_ver_financeiro()    to authenticated;
grant execute on function public.gp_pode_operar_financeiro() to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Canal de aquisição
--    É a TAG DE ORIGEM gravada por cs.fn_tag_hm_origem — fonte de verdade do
--    sistema de ativação. Não criamos taxonomia paralela: devolvemos a tag
--    literal, a mesma que o CANAIS_FIXOS da UI de ativação filtra. 153 dos 154
--    cards da T39 têm exatamente uma tag de origem; a ordem abaixo só desempata
--    o caso restante.
-- ---------------------------------------------------------------------------
create or replace function cs.fn_hm_canal(p_tags text[])
returns text language sql immutable set search_path to ''
as $$
  select case
    when 'HM - Programa de Implementação' = any(p_tags) then 'HM - Programa de Implementação'
    when 'HT ATM'                         = any(p_tags) then 'HT ATM'
    when 'HT28'                           = any(p_tags) then 'HT28'
    when 'HT27'                           = any(p_tags) then 'HT27'
    when 'HT26'                           = any(p_tags) then 'HT26'
    when 'Ex aluno Direto ao Ponto'       = any(p_tags) then 'Ex aluno Direto ao Ponto'
    when 'Live Direto ao Ponto'           = any(p_tags) then 'Live Direto ao Ponto'
    when 'Imersão POA'                    = any(p_tags) then 'Imersão POA'
    when 'Venda direta'                   = any(p_tags) then 'Venda direta'
    else 'Não classificado'
  end;
$$;

-- ---------------------------------------------------------------------------
-- 3) View de contas a receber — uma linha por card HM
--    bruto   = o que o aluno pagou (cs.hm_pagamentos.valor)
--    líquido = o que caiu na conta (compras.valor_liquido; a Hotmart já tirou a
--              taxa). Casamos pela transação Hotmart.
--    taxa    = bruto − líquido (o que a Hotmart reteve DA EMPRESA). NÃO inclui
--              taxa_parcelamento — isso é juro que o ALUNO paga para parcelar,
--              não sai do caixa da empresa.
-- ---------------------------------------------------------------------------
create or replace view cs.vw_fin_contas_receber as
with pg as (
  select p.comprador_id, p.categoria,
         p.valor                                      as bruto,
         coalesce(c.valor_liquido, p.valor)           as liquido,
         p.valor - coalesce(c.valor_liquido, p.valor) as taxas,
         p.pago_em, p.metodo_pagamento, p.transacao, p.parcela
  from cs.hm_pagamentos p
  left join public.compras c on c.hotmart_transaction = p.transacao
),
-- Total soma TODOS os lançamentos (bate com f.pago e com o extrato). As colunas
-- sinal/saldo são recortes só para exibição — um comprador pode ter 2 sinais.
total as (
  select comprador_id, sum(bruto) as bruto, sum(liquido) as liquido, sum(taxas) as taxas
  from pg group by comprador_id
),
sinal as (
  select distinct on (comprador_id)
         comprador_id, bruto, liquido, taxas, pago_em, metodo_pagamento, transacao
  from pg where categoria = 'sinal'
  order by comprador_id, pago_em
),
saldo as (
  select comprador_id,
         sum(bruto) as bruto, sum(liquido) as liquido, sum(taxas) as taxas,
         max(pago_em) as ultimo_pago_em, min(pago_em) as primeiro_pago_em,
         count(*)::int as lancamentos, max(metodo_pagamento) as metodo_pagamento
  from pg where categoria in ('saldo','compra_cheia','mensalidade')
  group by comprador_id
),
reembolso as (
  select c.comprador_id, max(c.atualizado_em) as em,
         string_agg(distinct c.status::text, ', ') as status,
         sum(coalesce(c.preco,0)) as valor
  from public.compras c
  where c.status in ('REFUNDED','CHARGEBACK','PROTEST')
  group by c.comprador_id
)
select
  f.contato_hm_id, f.comprador_id, ch.aluno_id,
  cp.nome, cp.email, cp.telefone, cp.documento,
  f.turma, f.turma_origem, cs.fn_hm_canal(ch.tags) as canal, f.publico, ch.tags,
  e.nome as estagio_nome, e.aba as estagio_aba,

  s.bruto as sinal_bruto, s.liquido as sinal_liquido, s.taxas as sinal_taxas,
  s.pago_em as sinal_pago_em, s.metodo_pagamento as sinal_metodo, s.transacao as sinal_transacao,

  coalesce(sd.bruto, 0)   as saldo_pago_bruto,
  coalesce(sd.liquido, 0) as saldo_pago_liquido,
  coalesce(sd.taxas, 0)   as saldo_taxas,
  sd.ultimo_pago_em       as saldo_pago_em,
  sd.metodo_pagamento     as saldo_metodo,
  coalesce(sd.lancamentos, 0) as saldo_lancamentos,

  coalesce(t.bruto, 0)   as total_pago_bruto,
  coalesce(t.liquido, 0) as total_pago_liquido,
  coalesce(f.pacote_cravado, f.pacote_regra) as pacote,
  f.credito, f.saldo_a_perseguir as saldo_a_pagar, f.pago_pct,

  -- o acordo combinado pelo financeiro (mesmas colunas que a ativação já lê)
  ch.pagamento_previsto_em as vencimento,
  ch.acordo, ch.pagamento_meio, ch.pagamento_forma, ch.pagamento_parcelas,
  f.parcelas_pagas, f.parcelas_contratadas, f.valor_parcela,
  case when ch.pagamento_previsto_em is not null and coalesce(f.saldo_a_perseguir,0) > 0
       then (current_date - ch.pagamento_previsto_em) end as dias_atraso,

  f.oferta_saldo_codigo as oferta_codigo,
  o.valor as oferta_valor, o.link as oferta_link, o.recorrente as oferta_recorrente,
  ch.link_saldo_enviado_em as oferta_enviada_em,

  ch.cancelamento_em, ch.cancelamento_motivo, ch.cancelamento_efetivado_em, ch.quitado_em,
  rb.em as reembolso_em, rb.status as reembolso_status, rb.valor as reembolso_valor,

  f.ultimo_pagamento_em, f.situacao as situacao_ativacao,

  case
    when rb.em is not null                        then 'reembolsado'
    when ch.cancelamento_efetivado_em is not null then 'cancelado'
    when ch.cancelamento_em is not null           then 'cancelamento_solicitado'
    when ch.quitado_em is not null
      or coalesce(f.saldo_a_perseguir, 1) <= 0    then 'quitado'
    when coalesce(f.parcelas_pagas,0) > 0         then 'em_pagamento'
    when ch.pagamento_previsto_em is not null
     and ch.pagamento_previsto_em < current_date  then 'vencido'
    when ch.pagamento_previsto_em is not null     then 'a_vencer'
    when ch.link_saldo_enviado_em is not null     then 'oferta_enviada'
    else 'sem_acordo'
  end as status_financeiro

from cs.vw_hm_financeiro f
join cs.contatos_hm ch     on ch.id = f.contato_hm_id
join public.compradores cp on cp.id = f.comprador_id
left join cs.estagios e    on e.id = ch.estagio_id
left join total t          on t.comprador_id = f.comprador_id
left join sinal s          on s.comprador_id = f.comprador_id
left join saldo sd         on sd.comprador_id = f.comprador_id
left join reembolso rb     on rb.comprador_id = f.comprador_id
left join cs.hm_ofertas_saldo o on o.codigo = f.oferta_saldo_codigo;

-- ---------------------------------------------------------------------------
-- 4) RPCs consumidas pelo app (web/modules/financeiro/ui/financeiro-data.ts)
-- ---------------------------------------------------------------------------
create or replace function public.fn_fin_contas_receber(p_turma text default null)
returns table (
  contato_hm_id uuid, comprador_id uuid, aluno_id uuid,
  nome varchar, email varchar, telefone varchar, documento varchar,
  turma text, turma_origem text, canal text, publico text, tags text[],
  estagio_nome text, estagio_aba text,
  sinal_bruto numeric, sinal_liquido numeric, sinal_taxas numeric,
  sinal_pago_em timestamptz, sinal_metodo text, sinal_transacao text,
  saldo_pago_bruto numeric, saldo_pago_liquido numeric, saldo_taxas numeric,
  saldo_pago_em timestamptz, saldo_metodo text, saldo_lancamentos int,
  total_pago_bruto numeric, total_pago_liquido numeric,
  pacote numeric, credito numeric, saldo_a_pagar numeric, pago_pct numeric,
  vencimento date, acordo text, pagamento_meio text, pagamento_forma text,
  pagamento_parcelas int, parcelas_pagas int, parcelas_contratadas int,
  valor_parcela numeric, dias_atraso int,
  oferta_codigo text, oferta_valor numeric, oferta_link text,
  oferta_recorrente boolean, oferta_enviada_em timestamptz,
  cancelamento_em timestamptz, cancelamento_motivo text,
  cancelamento_efetivado_em timestamptz, quitado_em timestamptz,
  reembolso_em timestamptz, reembolso_status text, reembolso_valor numeric,
  ultimo_pagamento_em timestamptz, situacao_ativacao text, status_financeiro text
)
language sql stable security definer set search_path to 'public','cs'
as $$
  select v.contato_hm_id, v.comprador_id, v.aluno_id,
         v.nome, v.email, v.telefone, v.documento,
         v.turma, v.turma_origem, v.canal, v.publico, v.tags,
         v.estagio_nome, v.estagio_aba,
         v.sinal_bruto, v.sinal_liquido, v.sinal_taxas,
         v.sinal_pago_em, v.sinal_metodo, v.sinal_transacao,
         v.saldo_pago_bruto, v.saldo_pago_liquido, v.saldo_taxas,
         v.saldo_pago_em, v.saldo_metodo, v.saldo_lancamentos,
         v.total_pago_bruto, v.total_pago_liquido,
         v.pacote, v.credito, v.saldo_a_pagar, v.pago_pct,
         v.vencimento, v.acordo, v.pagamento_meio, v.pagamento_forma,
         v.pagamento_parcelas, v.parcelas_pagas, v.parcelas_contratadas,
         v.valor_parcela, v.dias_atraso,
         v.oferta_codigo, v.oferta_valor, v.oferta_link,
         v.oferta_recorrente, v.oferta_enviada_em,
         v.cancelamento_em, v.cancelamento_motivo,
         v.cancelamento_efetivado_em, v.quitado_em,
         v.reembolso_em, v.reembolso_status, v.reembolso_valor,
         v.ultimo_pagamento_em, v.situacao_ativacao, v.status_financeiro
  from cs.vw_fin_contas_receber v
  where public.gp_pode_ver_financeiro()
    and (p_turma is null or v.turma = p_turma)
  order by v.saldo_a_pagar desc nulls last, v.nome;
$$;

create or replace function public.fn_fin_turmas()
returns table (turma text, alunos int, atual boolean)
language sql stable security definer set search_path to 'public','cs'
as $$
  select ch.turma, count(*)::int,
         ch.turma = (select trim(both '"' from valor::text) from cs.config where chave='hm_turma_atual')
  from cs.contatos_hm ch
  where public.gp_pode_ver_financeiro() and ch.turma is not null
  group by ch.turma
  order by (regexp_replace(ch.turma,'\D','','g'))::int desc;
$$;

drop function if exists public.fn_fin_extrato(uuid);
create function public.fn_fin_extrato(p_comprador_id uuid)
returns table (
  id uuid, categoria text, valor_bruto numeric, valor_liquido numeric,
  taxas numeric, juros_parcelamento numeric, pago_em timestamptz, origem text,
  transacao text, oferta_codigo text, metodo_pagamento text, parcela smallint,
  obs text, autor text,
  produto_nome varchar, compra_status varchar, compra_parcelas smallint,
  compra_data_vencimento date
)
language sql stable security definer set search_path to 'public','cs'
as $$
  select p.id, p.categoria, p.valor,
         coalesce(c.valor_liquido, p.valor),
         -- taxa que a Hotmart reteve da empresa (= bruto − líquido)
         p.valor - coalesce(c.valor_liquido, p.valor),
         -- juros que o ALUNO pagou para parcelar; não é custo da empresa
         coalesce(c.taxa_parcelamento, 0),
         p.pago_em, p.origem, p.transacao, p.oferta_codigo,
         p.metodo_pagamento, p.parcela, p.obs, p.autor,
         c.produto_nome, c.status, c.parcelas, c.data_vencimento
  from cs.hm_pagamentos p
  left join public.compras c on c.hotmart_transaction = p.transacao
  where public.gp_pode_ver_financeiro() and p.comprador_id = p_comprador_id
  order by p.pago_em desc;
$$;

create or replace function public.fn_fin_ofertas()
returns table (codigo text, valor numeric, recorrente boolean, link text, ativo boolean, usos int)
language sql stable security definer set search_path to 'public','cs'
as $$
  select o.codigo, o.valor, o.recorrente, o.link, o.ativo,
         (select count(*)::int from cs.contatos_hm ch where ch.oferta_saldo_codigo = o.codigo)
  from cs.hm_ofertas_saldo o
  where public.gp_pode_ver_financeiro()
  order by o.recorrente, o.valor;
$$;

-- Escrita: grava nas MESMAS colunas do card que o sistema de ativação já lê,
-- então comercial e financeiro enxergam o mesmo estado. Sem tabela paralela.
create or replace function public.fn_fin_salvar_acordo(
  p_contato_hm_id uuid,
  p_vencimento    date default null,
  p_acordo        text default null,
  p_meio          text default null,
  p_forma         text default null,
  p_parcelas      int  default null
)
returns jsonb
language plpgsql security definer set search_path to 'public','cs'
as $$
declare
  v_antes cs.contatos_hm%rowtype;
  v_autor text;
begin
  if not public.gp_pode_operar_financeiro() then
    return jsonb_build_object('ok', false, 'erro', 'sem_permissao');
  end if;

  select * into v_antes from cs.contatos_hm where id = p_contato_hm_id;
  if not found then
    return jsonb_build_object('ok', false, 'erro', 'contato_nao_encontrado');
  end if;

  select coalesce(p.nome, p.email, 'financeiro') into v_autor
  from public.perfis p where p.id = (select auth.uid());

  update cs.contatos_hm set
    pagamento_previsto_em = p_vencimento,
    acordo                = p_acordo,
    pagamento_meio        = p_meio,
    pagamento_forma       = p_forma,
    pagamento_parcelas    = p_parcelas,
    atualizado_em         = now()
  where id = p_contato_hm_id;

  -- Trilha: o financeiro mexe em dinheiro, todo acordo fica registrado (antes/depois).
  insert into public.thb_system_events (tipo, fonte, titulo, detalhe, aluno_id)
  values ('info', 'financeiro', 'Acordo de pagamento registrado',
    jsonb_build_object(
      'contato_hm_id', p_contato_hm_id,
      'comprador_id',  v_antes.comprador_id,
      'autor',         coalesce(v_autor, '?'),
      'autor_id',      (select auth.uid()),
      'antes', jsonb_build_object(
        'vencimento', v_antes.pagamento_previsto_em, 'acordo', v_antes.acordo,
        'meio', v_antes.pagamento_meio, 'forma', v_antes.pagamento_forma,
        'parcelas', v_antes.pagamento_parcelas),
      'depois', jsonb_build_object(
        'vencimento', p_vencimento, 'acordo', p_acordo,
        'meio', p_meio, 'forma', p_forma, 'parcelas', p_parcelas)),
    v_antes.aluno_id);

  return jsonb_build_object('ok', true);
end;
$$;

-- SECURITY DEFINER: só authenticated executa (guard interno gp_pode_*_financeiro).
-- Revoga de PUBLIC para não expor a anon/roles não previstos (advisor).
revoke execute on function public.fn_fin_contas_receber(text) from public;
revoke execute on function public.fn_fin_turmas()            from public;
revoke execute on function public.fn_fin_extrato(uuid)       from public;
revoke execute on function public.fn_fin_ofertas()           from public;
revoke execute on function public.fn_fin_salvar_acordo(uuid, date, text, text, text, int) from public;
revoke execute on function public.gp_pode_ver_financeiro()    from public;
revoke execute on function public.gp_pode_operar_financeiro() from public;

grant execute on function public.fn_fin_contas_receber(text) to authenticated;
grant execute on function public.fn_fin_turmas()            to authenticated;
grant execute on function public.fn_fin_extrato(uuid)       to authenticated;
grant execute on function public.fn_fin_ofertas()           to authenticated;
grant execute on function public.fn_fin_salvar_acordo(uuid, date, text, text, text, int) to authenticated;
