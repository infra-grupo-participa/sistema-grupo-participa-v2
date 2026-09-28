-- 20260928z44 — Nome do card é o da pessoa do card, não o do último cadastro que passou pelo e-mail (polimento, rodada 3).
-- Medido: 343 cards com pagamento; 15 com o 1º nome diferente de quem pagou na Hotmart — 12 são razão social ou variação
-- do mesmo nome (já tratados por fin.nome_exibicao), 3 são pessoas diferentes:
--   · e-mail de escritório: o cadastro public.compradores foi sobrescrito com o nome/CPF de OUTRA pessoa do escritório,
--     mas quem paga o HM é o dono do card — e o aluno vinculado ao card é ele.
--   · 2 cards pagos por terceiro (secretária, cônjuge): o card é do dono do e-mail. Continua o nome do dono.
-- Regra: com aluno vinculado ao card e 1º nome diferente do cadastro, vale o nome do aluno (a pessoa do programa).
-- Só exibição: public.compradores / thb_alunos / cs não mudam.
create or replace function fin.nome_do_card(p_nome text, p_email text, p_aluno_nome text)
returns text language sql stable set search_path = '' as $$
  select fin.nome_exibicao(
           case when p_aluno_nome is not null and not fin.nome_ruim(p_aluno_nome)
                 and split_part(lower(public.unaccent('public.unaccent'::regdictionary, btrim(coalesce(p_nome, '')))), ' ', 1)
                  <> split_part(lower(public.unaccent('public.unaccent'::regdictionary, btrim(p_aluno_nome))), ' ', 1)
                then p_aluno_nome else p_nome end,
           p_email)
$$;

create or replace function public.fn_fin_board(p_turma text default null::text, p_produto text default null::text)
 returns table(origem text, contato_hm_id uuid, comprador_id uuid, aluno_id uuid, nome character varying, email character varying, turma text, turma_origem text, canal text, publico text, produto text, estagio_chave text, estagio_nome text, estagio_aba text, vendedor text, status_financeiro text, faixa text, pacote numeric, total_pago_bruto numeric, total_pago_liquido numeric, sinal_bruto numeric, saldo_pago_bruto numeric, saldo_a_pagar numeric, credito numeric, pago_pct numeric, vencimento date, dias_atraso integer, entrou_estagio_em timestamp with time zone, dias_no_estagio integer, solicitou_cancelamento boolean, cancelamento_em timestamp with time zone, cancelamento_efetivado_em timestamp with time zone, quitado_em timestamp with time zone, reembolso_em timestamp with time zone, reembolso_valor numeric, oferta_codigo text, oferta_enviada_em timestamp with time zone, ultimo_pagamento_em timestamp with time zone, aurum_excecao boolean, aurum_excecao_motivo text, aurum_rotulo_operador text, acao_nome text, acao_data timestamp with time zone, reuniao_resultado text, intencao_pagamento text, intencao_pagamento_obs text, reuniao_motivo_tipo text, reuniao_retomar_em date, pacote_regra numeric, divergencia_regra numeric, acao_regra text, captado_em date, captado_sck text)
 language sql
 stable security definer
 set search_path to 'public', 'cs'
as $function$
  select
    b.origem, b.contato_hm_id, b.comprador_id, b.aluno_id,
    fin.nome_do_card(b.nome, b.email, alu.nome)::character varying, b.email,
    coalesce(tu.turma, b.turma), b.turma_origem,
    case when b.canal is null or b.canal = 'Não classificado' then coalesce(a.acao_canal, b.canal) else b.canal end,
    b.publico, b.produto,
    e.chave as estagio_chave,
    b.estagio_nome, b.estagio_aba, b.vendedor,
    b.status_financeiro, b.faixa,
    b.pacote, b.total_pago_bruto, b.total_pago_liquido,
    b.sinal_bruto, b.saldo_pago_bruto,
    b.saldo_a_pagar, b.credito, b.pago_pct,
    b.vencimento, b.dias_atraso,
    b.entrou_estagio_em, b.dias_no_estagio,
    b.solicitou_cancelamento, b.cancelamento_em, b.cancelamento_efetivado_em,
    b.quitado_em, b.reembolso_em, b.reembolso_valor,
    b.oferta_codigo, b.oferta_enviada_em, b.ultimo_pagamento_em,
    b.aurum_excecao, b.aurum_excecao_motivo, b.aurum_rotulo_operador,
    a.acao_nome, a.acao_data,
    b.reuniao_resultado, b.intencao_pagamento, b.intencao_pagamento_obs,
    b.reuniao_motivo_tipo, b.reuniao_retomar_em,
    b.pacote_regra, b.divergencia_regra,
    a.acao_regra, a.captado_em, a.captado_sck
  from cs.vw_fin_board b
  left join cs.estagios e on e.id = b.estagio_id
  left join fin.vw_acao_card a on a.contato_hm_id = b.contato_hm_id
  left join fin.vw_turma_origem_card tu on tu.contato_hm_id = b.contato_hm_id
  left join public.thb_alunos alu on alu.id = b.aluno_id
  where coalesce(public.gp_pode_ver_financeiro(), false)
    and (p_turma is null or coalesce(tu.turma, b.turma) = p_turma)
    and (p_produto is null or b.origem = p_produto)
    -- card gêmeo: o cadastro tem alias para outro cadastro que já tem card do mesmo produto
    and not exists (
      select 1 from cs.hm_comprador_alias al
        join cs.contatos_hm cx on cx.id = b.contato_hm_id
        join cs.contatos_hm cc on cc.comprador_id = al.canonico_id and cc.produto = cx.produto
       where al.comprador_id = b.comprador_id)
  order by b.saldo_a_pagar desc nulls last, b.nome;
$function$;
