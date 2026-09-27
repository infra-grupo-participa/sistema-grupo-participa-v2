-- 20260928f — Diagnóstico do pro rata de UMA pessoa (aba "Calculadora de Pro Rata", pedido do João, 27/09/2026).
-- "O cálculo do pro rata de cada aluno e o porquê": a mesma regra de fn_fin_prorata_hm (20260928d), aberta
-- pagamento a pagamento, com o motivo de cada um entrar ou não no ciclo e os avisos que mudam a conversa.
--   crédito = pago no ciclo × meses cheios restantes ÷ 12 (truncado no centavo); diferença = valor do programa − crédito.
--   ciclo = vendas HM pagas com dia_aprovado entre (vencimento − 12 meses − 60 dias) e vencimento. Sem Acelera.
--   vencimento = maior thb_alunos.data_expiracao entre os e-mails da pessoa (turma do mesmo aluno).
-- p_vencimento / p_valor_programa: SIMULAÇÃO (a equipe informa outra data ou outro valor) — nada é gravado.
-- Só leitura. Sem documento e sem telefone (regra de Pessoas). Retorna jsonb (uma pessoa).

create or replace function public.fn_fin_prorata_diagnostico(p_email text, p_vencimento date default null,
                                                              p_valor_programa numeric default 15000)
returns jsonb
language plpgsql stable security definer set search_path = ''
as $$
declare
  v_email text := lower(trim(p_email));
  v_pessoa text; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_venc date; v_venc_cad date; v_turma text; v_ini date;
  v_meses int; v_pago numeric; v_credito numeric; r jsonb; v_emails text[];
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_email is null or v_email = '' then
    raise exception 'Informe o e-mail.' using errcode = '22023';
  end if;
  if p_valor_programa is null or p_valor_programa < 0 then
    raise exception 'Valor do programa inválido.' using errcode = '22023';
  end if;

  select i.pessoa_chave into v_pessoa from fin.identidade i where i.no = 'e:' || v_email;
  v_pessoa := coalesce(v_pessoa, 'e:' || v_email);

  select array_agg(distinct e) into v_emails from (
    select substr(i.no, 3) e from fin.identidade i where i.pessoa_chave = v_pessoa and i.no like 'e:%'
    union select v_email) x;

  select max(a.data_expiracao)::date, (array_agg(tt.codigo order by a.data_expiracao desc nulls last, a.id))[1]
    into v_venc_cad, v_turma
    from public.thb_alunos a
    left join public.thb_turmas tt on tt.id = a.turma_id
   where lower(trim(a.email)) in (select unnest(v_emails)) and a.data_expiracao is not null;

  v_venc := coalesce(p_vencimento, v_venc_cad);
  v_ini := case when v_venc is not null then (v_venc - interval '12 months')::date - 60 end;
  v_meses := case when v_venc is not null and v_venc > v_hoje
                  then (extract(year from age(v_venc::timestamp, v_hoje::timestamp)) * 12
                        + extract(month from age(v_venc::timestamp, v_hoje::timestamp)))::int
                  else 0 end;

  with tx as (
    select t.*, case when t.oferta_modo = 'SUBSCRIPTION' then 'mensalidade'
                     else coalesce((select min(c.categoria) from public.hm_product_catalog c where c.offer_code = t.oferta_codigo), t.papel_produto) end forma
      from fin.vw_transacoes t
     where t.email in (select unnest(v_emails)) and t.familia in ('HM', 'ACELERA')
  ), linhas as (
    select x.*,
           (x.familia = 'HM' and x.grupo = 'pago' and v_venc is not null and x.dia_aprovado between v_ini and v_venc) entra,
           case
             when x.familia = 'ACELERA' then 'fora: Acelera Holding não entra no pro rata'
             when x.grupo = 'estornado' then 'fora: reembolsado ou chargeback'
             when x.grupo <> 'pago' then 'fora: não foi pago (' || x.grupo || ')'
             when v_venc is null then 'sem vencimento cadastrado — não dá para saber o ciclo'
             when x.dia_aprovado < v_ini then 'fora: pago antes do ciclo atual (ciclo anterior)'
             when x.dia_aprovado > v_venc then 'fora: pago depois do vencimento (próximo ciclo)'
             else 'entra: pago dentro do ciclo atual'
           end motivo
      from tx x
  )
  select coalesce(sum(l.valor_oferta) filter (where l.entra), 0),
         jsonb_build_object(
           'pagamentos', coalesce(jsonb_agg(jsonb_build_object(
               'transacao', l.transacao, 'data', coalesce(l.dia_aprovado, l.dia_pedido), 'produto', l.produto_nome,
               'familia', l.familia, 'oferta', l.oferta_codigo, 'forma', l.forma, 'metodo', l.metodo, 'parcelas', l.parcelas,
               'recorrencia', l.recorrencia, 'situacao', l.grupo, 'valor', l.valor_oferta, 'cobrado', l.valor_cobrado,
               'juros', l.juros, 'liquido', l.liquido, 'entra', l.entra, 'motivo', l.motivo, 'email', l.email)
             order by coalesce(l.aprovado_em, l.pedido_em) desc) filter (where l.grupo in ('pago','estornado') or l.dia_pedido >= v_hoje - 60), '[]'::jsonb),
           'pagamentos_no_ciclo', count(*) filter (where l.entra),
           'acelera_pago', coalesce(sum(l.valor_oferta) filter (where l.familia = 'ACELERA' and l.grupo = 'pago'), 0),
           'estornos', count(*) filter (where l.grupo = 'estornado' and l.familia = 'HM'),
           'boletos_em_aberto', count(*) filter (where l.familia = 'HM' and l.grupo = 'em_aberto' and l.dia_pedido >= v_hoje - 30),
           'boleto_em_aberto_valor', coalesce(sum(l.valor_oferta) filter (where l.familia = 'HM' and l.grupo = 'em_aberto' and l.dia_pedido >= v_hoje - 30), 0),
           'nome', (array_agg(l.nome order by coalesce(l.aprovado_em, l.pedido_em) desc))[1])
    into v_pago, r
    from linhas l;

  v_credito := trunc(v_pago * v_meses / 12, 2);

  return jsonb_build_object(
    'pessoa', jsonb_build_object(
       'nome', r->>'nome',
       'emails', to_jsonb(v_emails),
       'turma', v_turma,
       'vencimento_cadastrado', v_venc_cad,
       'vencimento_usado', v_venc,
       'vencimento_simulado', p_vencimento is not null,
       'no_gps', exists (select 1 from public.thb_alunos a join gps.membros m on m.aluno_id = a.id or m.pessoa_aluno_id = a.id
                          where lower(trim(a.email)) in (select unnest(v_emails)))),
    'ciclo', jsonb_build_object('inicio', v_ini, 'fim', v_venc, 'hoje', v_hoje, 'meses_restantes', v_meses),
    'calculo', jsonb_build_object('pago_no_ciclo', v_pago, 'pagamentos_no_ciclo', r->'pagamentos_no_ciclo',
                                  'meses_restantes', v_meses, 'credito', v_credito,
                                  'valor_programa', p_valor_programa, 'diferenca', greatest(p_valor_programa - v_credito, 0)),
    'pagamentos', r->'pagamentos',
    'board', (select jsonb_build_object('contato_hm_id', b.contato_hm_id, 'status', b.status_financeiro, 'pago', b.total_pago_bruto,
                                        'saldo', b.saldo_a_pagar, 'canal', b.canal)
                from cs.vw_fin_board b join public.compradores c on c.id = b.comprador_id
               where lower(trim(c.email)) in (select unnest(v_emails)) and b.origem = 'HM'
               order by b.saldo_a_pagar desc nulls last limit 1),
    'avisos', to_jsonb(array_remove(array[
       case when v_venc_cad is null then 'Vencimento não cadastrado na turma — confirme a data com a Isabela e simule.' end,
       case when p_vencimento is not null then 'Vencimento SIMULADO (' || to_char(p_vencimento, 'DD/MM/YYYY') || ') — o cadastrado é ' || coalesce(to_char(v_venc_cad, 'DD/MM/YYYY'), 'nenhum') || '.' end,
       case when v_venc is not null and v_venc <= v_hoje then 'O acesso já venceu: crédito zero.' end,
       case when (r->>'estornos')::int > 0 then 'Tem ' || (r->>'estornos') || ' pagamento(s) de HM reembolsado(s) — não contam.' end,
       case when (r->>'boletos_em_aberto')::int > 0 then 'Tem boleto/Pix de HM em aberto nos últimos 30 dias (R$ ' || replace(to_char((r->>'boleto_em_aberto_valor')::numeric, 'FM999999990.00'), '.', ',') || ') — pode ser a diferença já gerada.' end,
       case when (r->>'acelera_pago')::numeric > 0 then 'Pagou R$ ' || replace(to_char((r->>'acelera_pago')::numeric, 'FM999999990.00'), '.', ',') || ' no Acelera Holding — não entra no pro rata (regra do João).' end,
       case when coalesce((select count(*) from jsonb_array_elements(r->'pagamentos') p where (p->>'familia') = 'HM' and (p->>'situacao') = 'pago'), 0) = 0 then 'Nenhum pagamento de HM na Hotmart com estes e-mails — pode ter pago por fora ou com outro e-mail.' end
    ], null)));
end $$;
revoke all on function public.fn_fin_prorata_diagnostico(text, date, numeric) from public, anon;
grant execute on function public.fn_fin_prorata_diagnostico(text, date, numeric) to authenticated;
