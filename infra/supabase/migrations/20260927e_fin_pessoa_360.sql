-- 20260927e — Pessoa 360 no financeiro: uma linha por PESSOA (componente conexo de
-- fin.identidade), não por e-mail. Junta todas as transações de todos os e-mails dela,
-- de onde veio (1ª compra, oferta, origem sck, época), o caminho que fez (sinal → saldo →
-- renovação…), cards do board, turma, GPS e acesso. Só leitura.

-- Mapa e-mail → pessoa (e-mail sem nó no grafo = pessoa de si mesmo).
create or replace view fin.vw_email_pessoa as
select substr(i.no, 3) email, i.pessoa_chave from fin.identidade i where i.no like 'e:%';
revoke all on fin.vw_email_pessoa from public, anon, authenticated;

drop function if exists public.fn_fin_hotmart_pessoas(text);
create function public.fn_fin_hotmart_pessoas(p_familia text default 'HM')
returns table (
  pessoa_chave text, nome text, emails text[], documentos text[], telefone text, cidade text,
  situacao text, aviso text,
  primeira_compra date, primeira_oferta text, origem text, fluxo text, produtos text[],
  ultima_compra_paga date, compras_pagas int, valor_pago numeric, liquido numeric,
  estornos int, valor_estornado numeric,
  parcelas_atrasadas int, valor_atrasado numeric, atrasadas_antigas int, valor_atrasado_antigo numeric,
  em_aberto int, recusadas int, ultima_tentativa date,
  no_gps boolean, turma text, acesso_ate date, acesso_hotmart_ate date,
  cards int, contato_hm_id uuid, status_card text, saldo_card numeric, canal_card text,
  solicitou_cancelamento boolean, sugestoes int)
language plpgsql stable security definer set search_path = ''
as $$
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
           -- pagamento de oferta que GERA card no board (sinal, compra cheia, saldo) depois do início do board
           max(x.dia_aprovado) filter (where x.grupo = 'pago' and x.categoria in ('sinal','compra_cheia','diferenca')) ultima_paga_card,
           bool_or(x.grupo = 'pago' and x.oferta_modo like 'HOTMART_INSTALLMENTS%'
                   and x.recorrencia is not null and x.parcelas is not null and x.recorrencia < x.parcelas
                   and x.dia_aprovado >= (now() at time zone 'America/Sao_Paulo')::date - 45) parcelado_em_curso
      from tx x
      join fin.hotmart_transacoes h on h.transacao = x.transacao
     group by x.pessoa
  ), parc as (
    -- A Hotmart cria uma transação OVERDUE nova a cada tentativa de cobrança da MESMA parcela
    -- (a recorrência 7 de uma aluna do Aurum tem 9). Parcela = e-mail × produto × oferta × recorrência;
    -- conta uma vez, e sai da dívida se foi paga (ou estornada) depois. "Desde" = 1ª tentativa.
    select x.pessoa, x.email, x.produto_id, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao) parcela,
           bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde, max(x.valor_oferta) valor
      from tx x  -- sem recorrência (pagamento único protestado/atrasado) = a própria transação é a parcela
     group by x.pessoa, x.email, x.produto_id, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), pa as (
    select p.pessoa,
           count(*) filter (where p.desde >= now() - interval '120 days')::int n_atual,
           coalesce(sum(p.valor) filter (where p.desde >= now() - interval '120 days'), 0) valor_atual,
           count(*) filter (where p.desde < now() - interval '120 days')::int n_antigas,
           coalesce(sum(p.valor) filter (where p.desde < now() - interval '120 days'), 0) valor_antigo
      from parc p where p.atrasou and not p.quitada
     group by p.pessoa
  ), flx as (
    -- caminho: categorias pagas em ordem, sem repetição consecutiva (sinal → diferenca → renovacao…)
    select z.pessoa, string_agg(z.c, ' → ' order by z.o) fluxo
      from (select y.pessoa, coalesce(y.categoria, y.papel_produto) c, y.aprovado_em o,
                   lag(coalesce(y.categoria, y.papel_produto)) over (partition by y.pessoa order by y.aprovado_em) ant
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
      join cs.vw_fin_board b on b.comprador_id = c.id and b.origem = case p_familia when 'AURUM' then 'AURUM' else 'HM' end
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
  -- LGPD (regra da 0819g): documento e telefone completos só para gp_pode_ver_cpf(); o resto vê ···1234.
  -- a chave interna pode ser um documento (rótulo = menor nó do componente): sai como HMAC com segredo do Vault (20260927g)
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
         coalesce(c.solicitou, false), coalesce(s.n, 0)
    from agg a
    left join card c on c.pessoa = a.pessoa
    left join aluno al on al.pessoa = a.pessoa
    left join sug s on s.p = a.pessoa
    left join flx f on f.pessoa = a.pessoa
    left join pa on pa.pessoa = a.pessoa
   order by coalesce(pa.valor_atual, 0) desc, coalesce(pa.valor_antigo, 0) desc, a.ultima_tentativa desc nulls last;
end $$;
revoke all on function public.fn_fin_hotmart_pessoas(text) from public, anon;
grant execute on function public.fn_fin_hotmart_pessoas(text) to authenticated;

-- Extrato de uma PESSOA: todas as transações de todos os e-mails ligados ao e-mail informado.
drop function if exists public.fn_fin_hotmart_extrato(text);
create function public.fn_fin_hotmart_extrato(p_email text)
returns table (
  transacao text, email text, produto text, oferta_codigo text, status text, grupo text, metodo text, parcelas int,
  recorrencia int, valor_oferta numeric, cobrado numeric, juros numeric, taxa_hotmart numeric,
  liquido numeric, liquido_estimado boolean, pedido_em timestamptz, aprovado_em timestamptz,
  garantia_ate timestamptz, origem_sck text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_email text := lower(trim(coalesce(p_email, '')));
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_email = '' then return; end if;
  return query
  with alvo as (
    select substr(i.no, 3) email from fin.identidade i
     where i.no like 'e:%' and i.pessoa_chave = (select pessoa_chave from fin.identidade where no = 'e:' || v_email)
    union select v_email
  )
  select t.transacao, t.email, t.produto_nome, t.oferta_codigo, t.status, t.grupo, t.metodo, t.parcelas, t.recorrencia,
         t.valor_oferta, t.valor_cobrado, t.juros, t.taxa_hotmart, t.liquido, t.liquido_estimado,
         t.pedido_em, t.aprovado_em, t.garantia_ate, t.origem_sck
    from fin.vw_transacoes t
   where t.email in (select email from alvo)
   order by t.pedido_em desc
   limit 1000;
end $$;
revoke all on function public.fn_fin_hotmart_extrato(text) from public, anon;
grant execute on function public.fn_fin_hotmart_extrato(text) to authenticated;
