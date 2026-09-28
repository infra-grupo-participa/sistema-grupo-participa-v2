-- 20260928z36 — Nota de confiança dos dados financeiros (João, 28/09: "rodadas e rodadas de polimento; ao final gere um
-- score de confiança; enquanto não bater 100%, roda mais uma vez").
-- fn_fin_qualidade_dados(): uma linha por checagem (universo, problemas, % ok, exemplo). A nota é a MÉDIA das
-- checagens (cada uma pesa igual). Guarda gp_pode_ver_financeiro. Só leitura. (Revisada na rodada 2: nome ruim, pacote,
-- Aurum desde jul/2026. Rodada 4: 'incalculável' vira linha informativa, fora da média.)
create or replace function public.fn_fin_qualidade_dados()
returns table (checagem text, universo int, problemas int, pct_ok numeric, exemplo text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with board as (select * from public.fn_fin_board(null, null)),
  hm as (select * from public.fn_fin_board_hotmart()),
  pessoa_card as (
    select b.contato_hm_id, b.origem, coalesce(i.pessoa_chave, 'e:' || lower(btrim(b.email))) pk, b.nome
      from board b left join fin.identidade i on i.no = 'e:' || lower(btrim(b.email))
  ),
  pagos_prog as (
    select count(distinct coalesce(i.pessoa_chave, 'e:' || t.email))::int n
      from fin.vw_transacoes t left join fin.identidade i on i.no = 'e:' || t.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.produto_id = '5064314' and t.grupo = 'pago' and t.dia_aprovado >= date '2026-06-25'
       and coalesce(cat.categoria, '') not in ('renovacao','reserva')
  ),
  pagos_aurum as (
    select count(distinct coalesce(i.pessoa_chave, 'e:' || t.email))::int n
      from fin.vw_transacoes t left join fin.identidade i on i.no = 'e:' || t.email
     where t.familia = 'AURUM' and t.grupo = 'pago' and t.dia_aprovado >= date '2026-07-01' and coalesce(t.recorrencia, 1) = 1
  ),
  sem_hm as (select * from public.fn_fin_programa_sem_card('HM')),
  -- o board do Aurum começa em jul/2026 (A11); jan–jun (A9/A10) têm contrato próprio e ficam em "pagaram sem card"
  sem_au as (select * from public.fn_fin_programa_sem_card('AURUM') s where s.primeira >= date '2026-07-01'),
  orfas as (select * from public.fn_fin_ofertas_sem_catalogo()),
  compras26 as (
    select count(*)::int n from public.compras k join fin.produtos p on p.produto_id = k.produto_id::text and p.familia in ('HM','AURUM')
     where k.status in ('APPROVED','COMPLETE','COMPLETED') and coalesce(k.data_aprovacao, k.data_compra) >= timestamptz '2026-01-01 03:00+00'
  ),
  cpf_duplo as (
    select i.pessoa_chave, count(*) n from fin.identidade i where i.no ~ '^d:\d{11}$' group by 1 having count(*) > 1
  ),
  compradores_dup as (
    select regexp_replace(cp.documento, '\D', '', 'g') doc, count(distinct cp.id) n
      from public.compradores cp join board b on b.comprador_id = cp.id
     where length(regexp_replace(coalesce(cp.documento, ''), '\D', '', 'g')) = 11
     group by 1
  ),
  classif as (
    select count(*) filter (where p.familia = 'A_CLASSIFICAR')::int sem, count(*)::int tot
      from fin.vw_transacoes t join fin.produtos p on p.produto_id = t.produto_id where t.grupo = 'pago'
  )
  select x.checagem, x.universo, x.problemas,
         case when x.checagem like 'Pendência de decisão%' then null  -- informativa: fora da nota
              when coalesce(x.universo, 0) = 0 then 100.0
              else greatest(0, round(100.0 * (1 - x.problemas::numeric / x.universo), 1)) end,
         x.exemplo
    from (
    select 'Nome da pessoa (sem escritório, apelido ou repetição)'::text,
           (select count(*) from board)::int,
           (select count(*) from board b where fin.nome_ruim(b.nome)
               or lower(public.unaccent('public.unaccent'::regdictionary, b.nome)) ~ '(\m\w+\M) \1\M')::int,
           null::numeric,
           (select string_agg(b.nome, ', ') from (select nome from board where fin.nome_ruim(nome)
               or lower(public.unaccent('public.unaccent'::regdictionary, nome)) ~ '(\m\w+\M) \1\M' limit 3) b)
    union all
    select 'Uma pessoa, um card por produto',
           (select count(*) from pessoa_card)::int,
           (select coalesce(sum(n - 1), 0) from (select count(*) n from pessoa_card group by pk, origem having count(*) > 1) x)::int,
           null, (select string_agg(nome, ', ') from (select max(nome) nome from pessoa_card group by pk, origem having count(*) > 1 limit 3) x)
    union all
    select 'Pagou o Programa (HM) e tem card', (select n from pagos_prog), (select count(*) from sem_hm)::int, null,
           (select string_agg(nome, ', ') from (select nome from sem_hm limit 3) x)
    union all
    select 'Pagou o Aurum (desde jul/2026) e tem card', (select n from pagos_aurum), (select count(*) from sem_au)::int, null,
           (select string_agg(nome, ', ') from (select nome from sem_au limit 3) x)
    union all
    select 'Pagamento com oferta no catálogo (webhook lança)', (select n from compras26), (select coalesce(sum(pagamentos), 0) from orfas)::int, null,
           (select string_agg(oferta, ', ') from orfas)
    union all
    select 'Board bate com a Hotmart (HM)', (select count(*) from hm where hm.origem = 'HM')::int,
           (select count(*) from hm where hm.diverge is true)::int, null, null
    union all
    select 'Uma pessoa, um CPF (sem fusão suspeita)', (select count(distinct pessoa_chave) from fin.identidade)::int,
           (select count(*) from cpf_duplo)::int, null, null
    union all
    select 'Comprador sem cadastro duplicado (mesmo CPF)', (select count(*) from compradores_dup)::int,
           (select count(*) from compradores_dup where n > 1)::int, null, null
    union all
    select 'Venda paga em produto classificado', (select tot from classif), (select sem from classif), null, null
    union all
    select 'Card com turma', (select count(*) from board)::int, (select count(*) from board where turma is null)::int, null, null
    union all
    select 'Card com ação de origem', (select count(*) from board)::int,
           (select count(*) from board where acao_nome is null or acao_nome like 'Base%')::int, null, null
    union all
    select 'Card com pacote (quem pagou)', (select count(*) from board where total_pago_bruto > 0)::int,
           (select count(*) from board where total_pago_bruto > 0 and coalesce(pacote, 0) = 0
               and status_financeiro not in ('reembolsado','cancelado','incalculavel'))::int, null,
           (select string_agg(nome, ', ') from (select nome from board where total_pago_bruto > 0 and coalesce(pacote, 0) = 0
               and status_financeiro not in ('reembolsado','cancelado','incalculavel') limit 3) x)
    union all
    -- ex-aluno cujo crédito do pro rata o sistema não sabe calcular: o board mostra "incalculável" em vez de inventar.
    -- A regra nova do pro rata (João, 27/09) espera a aprovação dos números lado a lado — pendência, não erro de dado.
    select 'Pendência de decisão: pacote incalculável (pro rata de ex-aluno)',
           (select count(*) from board where total_pago_bruto > 0)::int,
           (select count(*) from board where total_pago_bruto > 0 and status_financeiro = 'incalculavel')::int, null,
           (select string_agg(nome, ', ') from (select nome from board where total_pago_bruto > 0
               and status_financeiro = 'incalculavel' limit 5) x)
    union all
    select 'Card com telefone', (select count(*) from board)::int,
           (select count(*) from board b left join hm on hm.contato_hm_id = b.contato_hm_id
             where nullif(btrim(hm.telefone), '') is null)::int, null, null
  ) x(checagem, universo, problemas, pct_ok, exemplo);
end $$;
revoke all on function public.fn_fin_qualidade_dados() from public, anon;
grant execute on function public.fn_fin_qualidade_dados() to authenticated;
