-- 20260930z92 — Funil do ESCRITÓRIO: Sessão de Viabilidade → Croqui → Holding Familiar, por evento.
--
-- POR QUÊ
--   O setor escritório vende a Sessão de Viabilidade nos seminários (para famílias). Quem compra a Sessão pode seguir
--   para o Croqui e fechar a Holding Familiar (HF). Hoje não existe número nenhum dessa conversão. Esta migration cria:
--     fin.escritorio_funil_vendas()                 — núcleo (uma linha por VENDA, com etapa e evento), privado.
--     fin.escritorio_funil_base()                   — núcleo (uma linha por PESSOA), privado, sem grant.
--     public.fn_fin_escritorio_funil()              — uma linha por evento do escritório + 3 linhas-balde.
--     public.fn_fin_escritorio_funil_pessoas(bigint) — uma linha por pessoa de uma linha do funil.
--   Regra de negócio mora aqui; a tela só exibe. Contrato de colunas no fim de 20260930z92.explain.md.
--
-- PRODUTOS (fixos no SQL: a conta Soluções ainda não tem catálogo em fin.produtos — backfill em curso)
--   Sessão de Viabilidade: 1663254, 1664749 (academy, 2021→02/2025) · 5238525 (escritorio)
--   Croqui Estrutural:     1542521 (academy, 2021→02/2025)          · 5243340 (escritorio)
--   Holding Familiar:      3595938 (academy, 12/2023→12/2024)       · 5301413 (escritorio)
--   Produto novo = 1 linha no values prod(produto_id, conta, etapa) de fin.escritorio_funil_vendas(). É a ÚNICA
--   lista (filtro das 2 contas e etapa saem dela); produto fora dela não entra — não há fallback de etapa.
--
-- REGRAS
--   venda        = fin.vw_transacoes (academy) ∪ fin.vw_transacoes_escritorio; só 1ª cobrança (recorrencia ≤ 1);
--                  pago = grupo 'pago'; estorno = grupo 'estornado' (contado à parte, nunca é entrada nem conversão).
--                  valor = valor_oferta × parcelas quando a oferta é HOTMART_INSTALLMENTS (mesma conta de
--                  fn_fin_funil_compradores).
--   conta escritorio só entra com fin.hotmart_contas.visivel_funis = true (z90): durante o backfill o funil mostra só
--                  a academy e devolve escritorio_visivel = false (a tela avisa "dados da Soluções ainda não entram").
--   pessoa       = e-mail lower(btrim()), juntando as duas contas.
--   entrada      = 1ª Sessão paga. Sem Sessão paga: 1º Croqui pago (balde "Entrou pelo Croqui", id -2);
--                  sem Croqui: 1ª HF paga (balde "Entrou direto na HF", id -1).
--   evento       = de cada venda de Sessão (a da ENTRADA define o funil da pessoa): 1) fin.evento_ofertas ligando a oferta a evento setor 'escritorio'
--                  (mais de um: o de início mais próximo antes da venda); 2) senão, janela do evento:
--                  coalesce(carrinho_inicio, inicio) .. coalesce(venda_ate, fim) (mais de um: o de início mais recente);
--                  3) senão, balde "Sessão sem evento (perene)", id -3. Oferta ligada a evento de OUTRO setor é
--                  ignorada (Holding Total não vende Sessão) e cai na janela.
--   conversão    = por PESSOA: 1º Croqui pago com aprovado_em ≥ entrada; 1ª HF paga com aprovado_em ≥ entrada.
--                  Croqui/HF pagos ANTES da 1ª Sessão não contam como conversão daquela entrada.
--   fechou HF    = sinal pago da HF na Hotmart. Contrato 2025 fechado sem sinal (1ª parcela fora da Hotmart): NÃO
--                  entra — fin.contratos_hf vem na z93, em revisão (29/09: nenhuma tabela contrat*/hf_* no banco).
--                  Quando existir, é um UNION a mais no CTE hf desta base.
--   medianas     = dias entre as datas (America/Sao_Paulo) Sessão→Croqui (quem tem os dois) e Croqui→HF (quem tem os
--                  dois, com HF ≥ Croqui).
--
-- SEGURANÇA
--   As 2 RPCs: security definer, search_path '', guarda coalesce(gp_pode_ver_financeiro(), false) → 42501,
--   revoke public/anon, grant authenticated. Os 2 núcleos: sem definer, revoke de todos (só as RPCs, donas postgres, chamam).
--   Decisão do dono (29/09): nome, e-mail, telefone e cidade visíveis a quem vê o Financeiro. O telefone segue a MESMA
--   máscara das listas da Academy (fn_fin_funil_compradores): completo só com gp_pode_ver_cpf(); senão '···' + 4 finais.
--   Cidade/UF: bruto_json.buyer só traz email/name/ucode (conferido em 1.414 vendas destes produtos: 0 com address);
--   vêm das colunas comprador_cidade / comprador_uf (1.268 de 1.414 preenchidas).
--   Trava trava_conta_hotmart (z89): fin.escritorio_funil_vendas cita fin.hotmart_transacoes só na forma canônica, uma por conta.
--
-- AS 5 PERGUNTAS
--   escala: 1.414 vendas academy destes 4 produtos (967 pago/estornado) hoje; escritório sintético de 5.000 medido
--     (explain.md): funil 60 → 290 ms, pessoas(evento) 64 → 182 ms. Cresce linear com as vendas DESTES produtos.
--     Leitura por produto_id cai em hotmart_transacoes_produto_idx (produto_id, aprovado_em) nas 2 contas (Bitmap
--     Index Scan) — não varre as 57 mil da academy.
--   índice: nenhum novo. O parcial (produto_id, aprovado_em) where conta='escritorio' NÃO foi proposto: não houve
--     Seq Scan; o índice cheio existente já tem a mesma chave e é o escolhido com 5.000 linhas escritório.
--   custo conhecido: fn_fin_escritorio_funil_pessoas usa fin.nome_exibicao (o mesmo das listas da Academy), que para
--     nome "ruim" (empresa/dígito/1 palavra) chama fin.nome_da_pessoa: ~65 ms por nome (medido: 19 ruins de 706 =
--     1,23 s). Balde perene (110 pessoas, 7 ruins) = 504 ms quente. Pré-existente; não otimizado aqui.
--
-- GATE ANTES DE LIGAR visivel_funis DO ESCRITÓRIO (não executado aqui; passo do runbook da z90)
--   Depois do backfill, com visivel_funis ainda false NÃO dá para medir (o ramo escritório não roda). Medir numa
--   transação desfeita: begin; update fin.hotmart_contas set visivel_funis = true where conta = 'escritorio';
--   set local role authenticated; set local statement_timeout = '8s'; claims de um perfil do Financeiro;
--     select * from public.fn_fin_escritorio_funil_pessoas(-3);
--     select * from public.fn_fin_escritorio_funil_pessoas(<evento 2025+ com mais pessoas no funil>);
--     select * from public.fn_fin_escritorio_funil();
--   rollback;
--   - pessoas passou de 8 s (timeout do authenticated) → consertar fin.nome_exibicao/nome_da_pessoa ANTES de ligar.
--   - funil passou de 1 s → juntar o duplo cálculo (vendas lidas 2× no funil) ANTES de ligar.
--   frequência: tela do Financeiro, aba escritório — dezenas/dia; pessoas = 1 chamada por clique em linha.
--   repetição: 1 RPC por tela (funil) + 1 por drill-down. Nenhuma query por linha no cliente.
--   reversão: drop function public.fn_fin_escritorio_funil_pessoas(bigint); drop function public.fn_fin_escritorio_funil();
--             drop function fin.escritorio_funil_base(); drop function fin.escritorio_funil_vendas();

set local lock_timeout = '5s';

-- Núcleo 1: uma linha por VENDA (pagas e estornadas), com etapa e evento ---------------------------------------------
create or replace function fin.escritorio_funil_vendas()
 returns table(
   transacao text, conta text, produto_id text, etapa text, oferta_codigo text, grupo text,
   aprovado_em timestamptz, dia date, valor numeric, email text,
   evento_id bigint, evento_origem text,
   nome text, telefone text, cidade text, uf text)
 language sql
 stable
 set search_path to ''
as $function$
  with vis as (
    select coalesce((select hc.visivel_funis from fin.hotmart_contas hc where hc.conta = 'escritorio'), false) v
  ), prod(produto_id, conta, etapa) as (
    -- ÚNICA lista de produtos do funil. Produto fora dela não entra (sem fallback).
    values ('1663254', 'academy', 'sessao'), ('1664749', 'academy', 'sessao'), ('1542521', 'academy', 'croqui'),
           ('3595938', 'academy', 'hf'),
           ('5238525', 'escritorio', 'sessao'), ('5243340', 'escritorio', 'croqui'), ('5301413', 'escritorio', 'hf')
  ), tx as (
    select t.transacao, t.conta, t.produto_id, p.etapa, t.oferta_codigo, t.grupo, t.aprovado_em, t.email,
           coalesce(t.dia_aprovado, t.dia_pedido) dia,
           round(t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2) valor,
           h.comprador_nome, h.comprador_telefone, h.comprador_cidade, h.comprador_uf
      from prod p
      join fin.vw_transacoes t on t.produto_id = p.produto_id
      join (select * from fin.hotmart_transacoes where conta = 'academy') h on h.transacao = t.transacao
     where p.conta = 'academy'
       and t.grupo in ('pago', 'estornado') and coalesce(t.recorrencia, 1) <= 1 and t.email <> ''
    union all
    select t.transacao, t.conta, t.produto_id, p.etapa, t.oferta_codigo, t.grupo, t.aprovado_em, t.email,
           coalesce(t.dia_aprovado, t.dia_pedido) dia,
           round(t.valor_oferta * case when t.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(t.parcelas, 1) else 1 end, 2) valor,
           h.comprador_nome, h.comprador_telefone, h.comprador_cidade, h.comprador_uf
      from prod p
      join fin.vw_transacoes_escritorio t on t.produto_id = p.produto_id
      join (select * from fin.hotmart_transacoes where conta = 'escritorio') h on h.transacao = t.transacao
     where p.conta = 'escritorio'
       and t.grupo in ('pago', 'estornado') and coalesce(t.recorrencia, 1) <= 1 and t.email <> ''
       and (select v from vis)
  ), ev as (
    select e.id, e.inicio, coalesce(e.carrinho_inicio, e.inicio) de, coalesce(e.venda_ate, e.fim, e.inicio) ate
      from fin.eventos e where e.setor = 'escritorio'
  ), x as (
    select * from tx
  )
  select x.transacao, x.conta, x.produto_id, x.etapa, x.oferta_codigo, x.grupo, x.aprovado_em, x.dia, x.valor, x.email,
         case when x.etapa = 'sessao' then coalesce(lig.id, jan.id, -3) end,
         case when x.etapa = 'sessao' then case when lig.id is not null then 'oferta' when jan.id is not null then 'janela' else 'perene' end end,
         x.comprador_nome, x.comprador_telefone, x.comprador_cidade, x.comprador_uf
    from x
    left join lateral (
      select w.id from fin.evento_ofertas eo join ev w on w.id = eo.evento_id
       where eo.oferta_codigo = x.oferta_codigo
       order by (w.inicio <= x.dia) desc, abs(w.inicio - x.dia), w.id limit 1) lig on x.etapa = 'sessao'
    left join lateral (
      select w.id from ev w where x.dia between w.de and w.ate
       order by w.inicio desc, w.id limit 1) jan on x.etapa = 'sessao' and lig.id is null;
$function$;
revoke all on function fin.escritorio_funil_vendas() from public, anon, authenticated, service_role;
comment on function fin.escritorio_funil_vendas() is
  'Núcleo do funil do escritório: 1 linha por venda (pago/estornado, 1ª cobrança) de Sessão/Croqui/HF nas 2 contas, com o evento da Sessão. Privado.';

-- Núcleo 2: uma linha por PESSOA -------------------------------------------------------------------------------------
create or replace function fin.escritorio_funil_base()
 returns table(
   email text, funil_id bigint, entrada text, contas text,
   sessao_em date, sessao_valor numeric, sessao_oferta text, sessao_evento_origem text,
   croqui_em date, croqui_valor numeric, hf_em date, hf_valor numeric,
   dias_sessao_croqui integer, dias_croqui_hf integer,
   nome text, telefone text, cidade text, uf text)
 language sql
 stable
 set search_path to ''
as $function$
  with v as materialized (
    select * from fin.escritorio_funil_vendas()
  ), pago as (
    select * from v where v.grupo = 'pago' and v.aprovado_em is not null
  ), ent as (
    -- entrada: 1ª Sessão; sem Sessão, 1º Croqui; sem Croqui, 1ª HF
    select distinct on (p.email) p.*
      from pago p
     order by p.email, (p.etapa <> 'sessao'), (p.etapa <> 'croqui'), p.aprovado_em, p.transacao
  ), cq as (
    select distinct on (p.email) p.email, p.aprovado_em, p.dia, p.valor
      from pago p join ent n on n.email = p.email
     where p.etapa = 'croqui' and p.aprovado_em >= n.aprovado_em
     order by p.email, p.aprovado_em, p.transacao
  ), hf as (
    select distinct on (p.email) p.email, p.aprovado_em, p.dia, p.valor
      from pago p join ent n on n.email = p.email
     where p.etapa = 'hf' and p.aprovado_em >= n.aprovado_em
     order by p.email, p.aprovado_em, p.transacao
  ), cad as (
    -- contato: da venda mais recente da pessoa que tiver o dado (qualquer conta, paga ou estornada)
    select v.email,
           (array_agg(v.nome order by v.aprovado_em desc nulls last) filter (where coalesce(v.nome, '') <> ''))[1] nome,
           (array_agg(v.telefone order by v.aprovado_em desc nulls last) filter (where coalesce(v.telefone, '') <> ''))[1] tel,
           (array_agg(v.cidade order by v.aprovado_em desc nulls last) filter (where coalesce(v.cidade, '') <> ''))[1] cidade,
           (array_agg(v.uf order by v.aprovado_em desc nulls last) filter (where coalesce(v.uf, '') <> ''))[1] uf,
           string_agg(distinct v.conta, ',' order by v.conta) contas
      from v group by v.email
  )
  select n.email,
         case n.etapa when 'sessao' then n.evento_id when 'croqui' then -2 else -1 end,
         n.etapa,
         c.contas,
         case when n.etapa = 'sessao' then n.dia end,
         case when n.etapa = 'sessao' then n.valor end,
         case when n.etapa = 'sessao' then n.oferta_codigo end,
         n.evento_origem,
         q.dia, q.valor, h.dia, h.valor,
         case when n.etapa = 'sessao' then q.dia - n.dia end,
         case when h.aprovado_em >= q.aprovado_em then h.dia - q.dia end,
         c.nome, c.tel, c.cidade, c.uf
    from ent n
    left join cq q on q.email = n.email
    left join hf h on h.email = n.email
    left join cad c on c.email = n.email;
$function$;
revoke all on function fin.escritorio_funil_base() from public, anon, authenticated, service_role;
comment on function fin.escritorio_funil_base() is
  'Núcleo do funil do escritório (Sessão→Croqui→HF): 1 linha por pessoa (e-mail). funil_id = evento ou balde -1/-2/-3. Privado.';

-- RPC 1: uma linha por evento do escritório + baldes ----------------------------------------------------------------
create or replace function public.fn_fin_escritorio_funil()
 returns table(
   evento_id bigint, tipo text, nome text, categoria text, inicio date, fim date,
   sessoes_vendas integer, sessoes_pessoas integer, sessoes_valor numeric,
   sessoes_estornos integer, sessoes_estornos_valor numeric,
   pessoas integer,
   croqui_pessoas integer, croqui_pct numeric, croqui_valor numeric,
   hf_pessoas integer, hf_pct numeric, hf_valor numeric,
   mediana_dias_sessao_croqui numeric, mediana_dias_croqui_hf numeric,
   escritorio_visivel boolean)
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with vis as (
    select coalesce((select hc.visivel_funis from fin.hotmart_contas hc where hc.conta = 'escritorio'), false) v
  ), b as materialized (
    select * from fin.escritorio_funil_base()
  ), linhas as (
    select e.id, 'evento'::text tipo, e.nome, e.categoria, e.inicio, e.fim, 1 grupo
      from fin.eventos e where e.setor = 'escritorio'
    union all values (-3::bigint, 'perene', 'Sessão sem evento (perene)', null::text, null::date, null::date, 2),
                     (-2::bigint, 'croqui', 'Entrou pelo Croqui', null, null, null, 3),
                     (-1::bigint, 'direto_hf', 'Entrou direto na HF', null, null, null, 4)
  ), ses as (
    select * from fin.escritorio_funil_vendas() s where s.etapa = 'sessao'
  ), sa as (
    select s.evento_id ev_id,
           count(*) filter (where s.grupo = 'pago')::int vendas,
           count(distinct s.email) filter (where s.grupo = 'pago')::int pessoas_pagas,
           coalesce(sum(s.valor) filter (where s.grupo = 'pago'), 0) valor,
           count(*) filter (where s.grupo = 'estornado')::int estornos,
           coalesce(sum(s.valor) filter (where s.grupo = 'estornado'), 0) estornos_valor
      from ses s group by s.evento_id
  ), fa as (
    select b.funil_id,
           count(*)::int pessoas,
           count(b.croqui_em)::int croqui_pessoas,
           coalesce(sum(b.croqui_valor), 0) croqui_valor,
           count(b.hf_em)::int hf_pessoas,
           coalesce(sum(b.hf_valor), 0) hf_valor,
           percentile_cont(0.5) within group (order by b.dias_sessao_croqui) med_sc,
           percentile_cont(0.5) within group (order by b.dias_croqui_hf) med_ch
      from b group by b.funil_id
  )
  select l.id, l.tipo, l.nome, l.categoria, l.inicio, l.fim,
         coalesce(sa.vendas, 0), coalesce(sa.pessoas_pagas, 0), coalesce(sa.valor, 0),
         coalesce(sa.estornos, 0), coalesce(sa.estornos_valor, 0),
         coalesce(fa.pessoas, 0),
         coalesce(fa.croqui_pessoas, 0), round(100.0 * fa.croqui_pessoas / nullif(fa.pessoas, 0), 1), coalesce(fa.croqui_valor, 0),
         coalesce(fa.hf_pessoas, 0), round(100.0 * fa.hf_pessoas / nullif(fa.pessoas, 0), 1), coalesce(fa.hf_valor, 0),
         round(fa.med_sc::numeric, 1), round(fa.med_ch::numeric, 1),
         (select v from vis)
    from linhas l
    left join sa on sa.ev_id = l.id
    left join fa on fa.funil_id = l.id
   order by l.grupo, l.inicio, l.id;
end
$function$;
revoke all on function public.fn_fin_escritorio_funil() from public, anon;
grant execute on function public.fn_fin_escritorio_funil() to authenticated, service_role;
comment on function public.fn_fin_escritorio_funil() is
  'Funil do escritório (Sessão de Viabilidade → Croqui → Holding Familiar): 1 linha por evento setor escritorio + baldes -3 perene, -2 entrou pelo Croqui, -1 direto na HF. Conversão por pessoa (e-mail). Exige gp_pode_ver_financeiro().';

-- RPC 2: pessoas de uma linha do funil ------------------------------------------------------------------------------
create or replace function public.fn_fin_escritorio_funil_pessoas(p_evento bigint)
 returns table(
   evento_id bigint, nome text, email text, telefone text, cidade text, uf text,
   entrada text, etapa_alcancada text, contas text,
   sessao_em date, sessao_valor numeric, sessao_evento_origem text,
   croqui_em date, croqui_valor numeric, hf_em date, hf_valor numeric,
   dias_sessao_croqui integer, dias_croqui_hf integer)
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  v_cpf boolean := coalesce(public.gp_pode_ver_cpf(), false);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_evento is null or not (p_evento in (-1, -2, -3)
                              or exists (select 1 from fin.eventos e where e.id = p_evento and e.setor = 'escritorio')) then
    raise exception 'Linha do funil do escritório inválida: %', p_evento using errcode = '22023';
  end if;
  return query
  select b.funil_id,
         fin.nome_exibicao(b.nome, b.email),
         b.email,
         case when v_cpf then b.telefone
              when b.telefone is not null then '···' || right(b.telefone, 4) end,
         b.cidade, b.uf,
         b.entrada,
         case when b.hf_em is not null then 'hf' when b.croqui_em is not null then 'croqui' else 'sessao' end,
         b.contas,
         b.sessao_em, b.sessao_valor, b.sessao_evento_origem,
         b.croqui_em, b.croqui_valor, b.hf_em, b.hf_valor,
         b.dias_sessao_croqui, b.dias_croqui_hf
    from fin.escritorio_funil_base() b
   where b.funil_id = p_evento
   order by coalesce(b.sessao_em, b.croqui_em, b.hf_em), b.email;
end
$function$;
revoke all on function public.fn_fin_escritorio_funil_pessoas(bigint) from public, anon;
grant execute on function public.fn_fin_escritorio_funil_pessoas(bigint) to authenticated, service_role;
comment on function public.fn_fin_escritorio_funil_pessoas(bigint) is
  'Pessoas de uma linha de fn_fin_escritorio_funil (id do evento ou balde -1/-2/-3): contato (telefone mascarado sem gp_pode_ver_cpf), datas, valores e etapa alcançada. Exige gp_pode_ver_financeiro().';
