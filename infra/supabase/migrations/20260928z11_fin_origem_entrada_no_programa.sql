-- 20260928z11 — Origem do card do HM = ENTRADA NO PROGRAMA DE IMPLEMENTAÇÃO ASSISTIDA (João, 28/09: "a implementação
-- assistida não começou na T9… mapear onde ela começou… usa esse momento como referência").
-- Marco zero: 25/06/2026, live fechada para ex-alunos do HT (Lançamento T39). Provas: mensageria da live ("novidade: o HM
-- deixou de ser treinamento e virou programa de implementação assistida"); pasta "PROGRAMA DE IMPLEMENTAÇÃO ASSISTIDO" e
-- planilhas GPS criadas em 24/06/2026; 1ª venda do sinal R$ 300 (z391kxd9, entrada_do_programa) em 25/06/2026.
-- Medido (301 cards HM): 259 compraram oferta do Programa depois do marco; 15 tentaram (6 reembolsados, 2 cancelaram,
-- 7 boleto em aberto); 20 com HM antigo/renovação e tentativa do Programa depois do marco (reembolso/boleto);
-- 7 compraram o HM R$ 15 mil (sinal 2k + saldo) em abr–jun/2026 nas Imersões/HT20+ → "migrados".
-- O HM antigo (T1–T38) sai da origem do card e fica na trajetória da pessoa (fn_fin_trajetoria).
create or replace view fin.vw_acao_card as
with card as (
  select b.contato_hm_id, b.origem, lower(trim(b.email)) email, ch.criado_em entrada
    from cs.vw_fin_board b
    join cs.contatos_hm ch on ch.id = b.contato_hm_id
), emails as (
  select c.contato_hm_id, coalesce(substr(i2.no, 3), c.email) email
    from card c
    left join fin.identidade i on i.no = 'e:' || c.email
    left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
), primeira as (
  -- HM: a ENTRADA NO PROGRAMA (marco zero 25/06/2026, live fechada do Lançamento T39): 1ª compra OU tentativa
  -- (paga, reembolsada, boleto, recusada) de oferta do Programa no produto 5064314, fora renovação, desde o marco.
  -- Sem isso: o HM R$ 15 mil comprado antes do marco (migrado). Aurum: sinal/cheio do catálogo; senão a 1ª de 2026.
  select distinct on (c.contato_hm_id) c.contato_hm_id, t.aprovado_em, t.dia_aprovado, t.origem_sck, t.migrado
    from card c
    join emails e on e.contato_hm_id = c.contato_hm_id
    join lateral (
      select coalesce(x.aprovado_em, x.pedido_em) aprovado_em, coalesce(x.dia_aprovado, x.dia_pedido) dia_aprovado, x.origem_sck,
             (c.origem = 'HM' and coalesce(x.dia_aprovado, x.dia_pedido) < date '2026-06-25') migrado, cat.categoria, x.grupo
        from fin.vw_transacoes x
        left join public.hm_product_catalog cat on cat.offer_code = x.oferta_codigo
       where x.email = e.email and x.familia = c.origem
         and case when c.origem = 'HM'
                  then x.produto_id = '5064314' and coalesce(cat.categoria, '') not in ('renovacao','reserva')
                       and (coalesce(x.dia_aprovado, x.dia_pedido) >= date '2026-06-25' or x.grupo = 'pago')
                  else x.grupo = 'pago' end
    ) t on true
   order by c.contato_hm_id,
            coalesce(c.origem = 'HM' and not t.migrado, false) desc,   -- HM: dentro do Programa primeiro
            coalesce(c.origem <> 'HM' and t.categoria in ('sinal','compra_cheia'), false) desc,
            (t.dia_aprovado >= date '2026-01-01') desc, t.aprovado_em
), base as (
  select c.*, p.aprovado_em, p.dia_aprovado, p.origem_sck, coalesce(p.migrado, false) migrado,
         coalesce(p.aprovado_em, c.entrada) quando,
         coalesce(p.origem_sck ilike '%comercial%' or p.origem_sck ilike '%jonathan%', false) comercial
    from card c left join primeira p on p.contato_hm_id = c.contato_hm_id
)
select b.contato_hm_id,
       case when b.migrado then 'T39 · Migrados (HM R$ 15 mil antes de 25/06/2026)'
            else coalesce(s.nome, d.nome, case when b.comercial then 'Comercial (venda direta)' end, j.nome, 'Base (fora de evento)') end acao_nome,
       coalesce(s.inicio, d.inicio, case when b.comercial then b.quando end, j.inicio, b.quando) acao_data,
       case when b.migrado then 'migrado: comprou o HM R$ 15 mil antes do Programa (' || coalesce(s.nome, d.nome, j.nome, 'fora de evento') || ')'
            when s.nome is not null then 'link de venda'
            when d.nome is not null and b.aprovado_em is null then 'data de entrada no board (dia do evento)'
            when d.nome is not null then 'dia do evento'
            when b.comercial then 'link do comercial'
            when j.nome is not null and b.aprovado_em is null then 'data de entrada no board'
            when j.nome is not null then 'depois do evento (turma)'
            when b.aprovado_em is null then 'sem compra paga'
            else 'fora de evento' end acao_regra,
       coalesce(s.canal, d.canal, case when b.comercial then 'Comercial' end, j.canal, 'Base (fora de evento)') acao_canal,
       b.dia_aprovado captado_em,
       b.origem_sck captado_sck
  from base b
  left join lateral (select a.nome, a.inicio, a.canal from fin.acoes a
                      where a.produto = b.origem and a.sck_regex is not null and b.origem_sck ~* a.sck_regex
                      order by a.prioridade, a.id limit 1) s on true
  left join lateral (select a.nome, a.inicio, a.canal, a.turma from fin.acoes a
                      where a.produto = b.origem and a.inicio is not null and a.fim is not null
                        and b.quando >= a.inicio and b.quando < a.fim
                      order by a.prioridade, a.id limit 1) j on true
  -- evento acontecendo no dia (do carrinho ao fim das vendas): vence o link do comercial — vendedor vendendo no evento
  left join lateral (select coalesce(ae.nome, coalesce(case when b.origem = 'HM' and j.turma is not null then j.turma || ' · ' end, '') || e.nome) nome,
                            (coalesce(e.carrinho_inicio, e.inicio)::timestamp at time zone 'America/Sao_Paulo') inicio,
                            coalesce(ae.canal, case e.categoria
                              when 'jornada' then 'Jornada' when 'holding_total' then 'Holding Total' when 'certificacao' then 'Holding Total'
                              when 'live_hm' then 'Live Direto ao Ponto' when 'clinica' then 'Clínica' when 'imersao' then 'Imersão'
                              when 'encontro_thb' then 'Encontro THB' when 'aurum_plus' then 'Aurum+' when 'congresso' then 'Congresso'
                              when 'diamantes' then 'Diamantes' when 'residencia' then 'Residência' when 'workshop' then 'Residência'
                              when 'lancamento_cnhf' then 'CNHF' else e.categoria end) canal
                       from fin.eventos e
                       left join lateral (select a.nome, a.canal from fin.acoes a where a.evento_id = e.id and a.produto = b.origem
                                           order by a.prioridade, a.id limit 1) ae on true
                      where e.setor = 'educacao'
                        and not (b.origem = 'HM' and e.categoria in ('aurum_plus','diamantes'))  -- evento só do Aurum/Diamante não capta HM
                        and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10  -- ciclo longo de ingresso (HT23–28) não é "dia do evento"
                        and (b.quando at time zone 'America/Sao_Paulo')::date between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
                      order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1) d on true;
revoke all on fin.vw_acao_card from public, anon, authenticated;
