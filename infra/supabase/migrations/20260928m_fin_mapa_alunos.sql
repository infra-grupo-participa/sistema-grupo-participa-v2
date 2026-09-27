-- 20260928m — Mapa de alunos do HM: uma linha por PESSOA, do início do Programa até hoje (pedido do João, 27/09/2026).
-- "Mapear todo mundo desde que a gente iniciou o programa de implementação… diferenciar quem migrou… mapear passo a
-- passo, financeiro principalmente… recuperar quem só pagou o sinal e quem não está em dia." Só leitura, só visualização.
--
-- Decisões do João (27/09):
--  * "Do Programa" = pagou o HM CHEIO ou quitou o SALDO (oferta do catálogo com categoria compra_cheia/diferenca).
--    Regra do Marcio (11/09): sinal e Acelera não dão direito. Validado em 27/09: 135 dos 147 titulares do GPS pagaram
--    assim (os 12 restantes pagaram por fora/outro e-mail — aparecem com o selo "no GPS").
--  * A 2ª metade do Programa (R$ 15 mil) só é cobrada depois que o parceiro fatura R$ 150 mil: aqui aparece como
--    condicional, com os honorários contratados no GPS (gps.etapa1_clientes, fase contratado) × 150 mil.
--  * Só faturamento (sem lucro).
--
-- Universo: quem comprou ou tentou HM desde 01/01/2026 (o formato do Programa — cheio de R$ 15 mil no catálogo — começa
-- em 01/2026; sinais em 04/2026; saldos em 05/2026, medido), + todo card HM do board + todo titular do GPS.
-- Classe (programa):
--   'programa'   pagou cheio/saldo do Programa
--   'so_sinal'   pagou sinal do Programa e ainda não o cheio/saldo  → fila de recuperação
--   'renovacao'  só renovação/reserva/assinatura do HM (aluno de turma antiga renovando)
--   'hm_antigo'  comprou HM antes de 2026 e nada do Programa
--   'tentou'     só tentou (boleto/recusa) — nunca pagou nada de HM
-- Situação de pagamento (situacao):
--   quitado · em_dia · atrasado (parcela vencida ≤ 120 d) · so_sinal · cancelado · reembolsado · sem_divida
-- LGPD: telefone mascarado (···1234) salvo gp_pode_ver_cpf(); chave da pessoa = fin.chave_opaca.

create or replace function public.fn_fin_mapa_alunos()
returns table (
  pessoa_chave text, nome text, email text, emails text[], telefone text,
  programa text, situacao text,
  entrou_programa_em date, primeira_compra_em date, primeira_compra text, origem_sck text,
  canal text, vendedor text, turma text, no_gps boolean, contato_hm_id uuid, status_card text,
  pago_vida numeric, pago_programa numeric, sinal_pago numeric, pacote numeric, falta_pagar numeric,
  parcelas_devidas int, valor_devido numeric, ultimo_pagamento_em date, ultima_tentativa_em date,
  veio_do_acelera boolean, honorarios_contratados numeric, segunda_metade_liberada boolean)
language plpgsql stable security definer set search_path = ''
set enable_nestloop = off
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with tx as materialized (
    select coalesce(i.pessoa_chave, 'e:' || t.email) p, t.email, t.nome, t.transacao, t.grupo, t.dia_aprovado, t.dia_pedido,
           t.aprovado_em, t.pedido_em, t.valor_oferta, t.oferta_codigo, t.produto_nome, t.origem_sck, t.familia,
           (select c.categoria::text from public.hm_product_catalog c where c.offer_code = t.oferta_codigo limit 1) cat
      from fin.vw_transacoes t
      left join fin.identidade i on i.no = 'e:' || t.email
     where t.familia in ('HM', 'ACELERA') and t.email is not null
  ), card as materialized (
    select coalesce(i.pessoa_chave, 'e:' || lower(trim(b.email))) p, b.contato_hm_id, b.status_financeiro, b.pacote,
           b.saldo_a_pagar, b.canal, b.vendedor, b.turma, b.total_pago_bruto
      from cs.vw_fin_board b
      left join fin.identidade i on i.no = 'e:' || lower(trim(b.email))
     where b.origem = 'HM' and b.email is not null
  ), gps as materialized (
    select coalesce(i.pessoa_chave, 'e:' || lower(trim(a.email))) p, bool_or(true) no_gps,
           coalesce(sum(h.v), 0) honorarios
      from gps.membros m
      join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
      left join fin.identidade i on i.no = 'e:' || lower(trim(a.email))
      left join lateral (select sum(c.valor_honorarios) v from gps.etapa1_clientes c
                          where c.aluno_id = m.aluno_id and c.fase = 'contratado') h on m.papel = 'titular'
     where m.papel = 'titular'
     group by 1
  ), universo as materialized (
    select distinct x.p from tx x where x.familia = 'HM' and coalesce(x.dia_aprovado, x.dia_pedido) >= date '2026-01-01'
    union select k.p from card k
    union select g.p from gps g
  ), agg as materialized (
    select u.p,
      (array_agg(x.nome order by coalesce(x.aprovado_em, x.pedido_em) desc) filter (where x.nome is not null))[1] nome,
      (array_agg(x.email order by coalesce(x.aprovado_em, x.pedido_em) desc))[1] email,
      array_agg(distinct x.email) filter (where x.email is not null) emails,
      min(x.dia_aprovado) filter (where x.familia = 'HM' and x.grupo = 'pago' and x.cat in ('compra_cheia','diferenca')) entrou,
      min(x.dia_aprovado) filter (where x.familia = 'HM' and x.grupo = 'pago') primeira,
      (array_agg(coalesce(x.produto_nome, '') || ' · ' || coalesce(x.oferta_codigo, '') order by x.aprovado_em)
         filter (where x.familia = 'HM' and x.grupo = 'pago'))[1] primeira_compra,
      (array_agg(x.origem_sck order by x.aprovado_em) filter (where x.familia = 'HM' and x.grupo = 'pago' and x.origem_sck is not null))[1] sck,
      coalesce(sum(x.valor_oferta) filter (where x.familia = 'HM' and x.grupo = 'pago'), 0) pago_vida,
      coalesce(sum(x.valor_oferta) filter (where x.familia = 'HM' and x.grupo = 'pago' and x.cat in ('sinal','diferenca','compra_cheia')), 0) pago_programa,
      coalesce(sum(x.valor_oferta) filter (where x.familia = 'HM' and x.grupo = 'pago' and x.cat = 'sinal'), 0) sinal,
      coalesce(bool_or(x.familia = 'HM' and x.grupo = 'pago' and x.cat in ('compra_cheia','diferenca')), false) tem_cheio,
      coalesce(bool_or(x.familia = 'HM' and x.grupo = 'pago' and x.cat = 'sinal'), false) tem_sinal,
      coalesce(bool_or(x.familia = 'HM' and x.grupo = 'pago' and x.dia_aprovado < date '2026-01-01'), false) tem_antigo,
      coalesce(bool_or(x.familia = 'HM' and x.grupo = 'pago'), false) tem_hm,
      coalesce(bool_or(x.familia = 'ACELERA' and x.grupo = 'pago'), false) acelera,
      coalesce(bool_or(x.familia = 'HM' and x.grupo = 'estornado'), false) estornou,
      max(x.dia_aprovado) filter (where x.familia = 'HM' and x.grupo = 'pago') ult,
      max(x.dia_pedido) filter (where x.familia = 'HM' and x.grupo not in ('pago','estornado')) ult_tentativa
      from universo u
      left join tx x on x.p = u.p
     group by u.p
  ), tel as materialized (
    select distinct on (coalesce(i.pessoa_chave, 'e:' || lower(trim(h.comprador_email))))
           coalesce(i.pessoa_chave, 'e:' || lower(trim(h.comprador_email))) p, h.comprador_telefone
      from fin.hotmart_transacoes h
      left join fin.identidade i on i.no = 'e:' || lower(trim(h.comprador_email))
     where h.comprador_telefone is not null
     order by coalesce(i.pessoa_chave, 'e:' || lower(trim(h.comprador_email))), h.pedido_em desc
  ), aluno as materialized (
    select coalesce(i.pessoa_chave, 'e:' || lower(trim(a.email))) p,
           (array_agg(tt.codigo order by a.data_expiracao desc nulls last) filter (where tt.codigo is not null))[1] turma
      from public.thb_alunos a
      left join public.thb_turmas tt on tt.id = a.turma_id
      left join fin.identidade i on i.no = 'e:' || lower(trim(a.email))
     where a.email is not null
     group by 1
  ), crd as materialized (
    select k.p, (array_agg(k.contato_hm_id order by k.saldo_a_pagar desc nulls last))[1] contato_hm_id,
           (array_agg(k.status_financeiro order by k.saldo_a_pagar desc nulls last))[1] status,
           max(k.pacote) pacote, sum(k.saldo_a_pagar) saldo,
           (array_agg(k.canal order by k.saldo_a_pagar desc nulls last))[1] canal,
           (array_agg(k.vendedor order by k.saldo_a_pagar desc nulls last))[1] vendedor,
           (array_agg(k.turma order by k.saldo_a_pagar desc nulls last))[1] turma
      from card k group by k.p
  ), dv as materialized (
    select d.pessoa p, d.n_atual, d.valor_atual from fin.parcelas_devidas('HM') d
  ), calc as (
    select a.*, c.contato_hm_id, c.status status_card, c.pacote, c.saldo, c.canal, c.vendedor, coalesce(c.turma, al.turma) turma,
           coalesce(g.no_gps, false) no_gps, coalesce(g.honorarios, 0) honorarios,
           coalesce(d.n_atual, 0) n_dev, coalesce(d.valor_atual, 0) v_dev, t.comprador_telefone tel,
           case when a.tem_cheio then 'programa'
                when a.tem_sinal then 'so_sinal'
                when a.tem_antigo then 'hm_antigo'
                when a.tem_hm then 'renovacao'
                else 'tentou' end programa
      from agg a
      left join crd c on c.p = a.p
      left join gps g on g.p = a.p
      left join aluno al on al.p = a.p
      left join dv d on d.p = a.p
      left join tel t on t.p = a.p
  )
  select fin.chave_opaca(k.p), k.nome, k.email, k.emails,
         case when coalesce(public.gp_pode_ver_cpf(), false) then k.tel
              when k.tel is not null then '···' || right(k.tel, 4) end,
         k.programa,
         case
           when k.status_card in ('cancelado','reembolsado') then 'cancelado'
           when k.estornou and not k.tem_hm then 'reembolsado'
           when k.n_dev > 0 or k.status_card = 'vencido' then 'atrasado'
           when k.status_card = 'quitado' then 'quitado'
           when k.programa = 'so_sinal' then 'so_sinal'
           when k.programa = 'programa' and coalesce(k.saldo, 0) <= 0.5 then 'quitado'
           when k.programa = 'programa' then 'em_dia'
           else 'sem_divida'
         end,
         k.entrou, k.primeira, nullif(k.primeira_compra, ' · '), k.sck,
         k.canal, k.vendedor, k.turma, k.no_gps, k.contato_hm_id, k.status_card,
         k.pago_vida, k.pago_programa, k.sinal,
         coalesce(k.pacote, case when k.programa in ('programa','so_sinal') then 15000 end),
         -- falta pagar da 1ª metade: o saldo do card quando existe; senão 15 mil − o que pagou do Programa (piso 0)
         case when k.saldo is not null then greatest(k.saldo, 0)
              -- pagou a oferta de saldo/cheio sem card: o Programa está quitado (o saldo já vem com o desconto aplicado)
              when k.programa = 'programa' then 0
              when k.programa = 'so_sinal' then greatest(15000 - k.pago_programa, 0) end,
         k.n_dev, k.v_dev, k.ult, k.ult_tentativa,
         k.acelera, k.honorarios, k.honorarios >= 150000
    from calc k
   order by case k.programa when 'so_sinal' then 0 when 'programa' then 1 else 2 end, k.ult desc nulls last;
end $$;
revoke all on function public.fn_fin_mapa_alunos() from public, anon;
grant execute on function public.fn_fin_mapa_alunos() to authenticated;
