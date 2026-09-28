-- 20260928z52 — Mensalidade do HM antigo (produto 3507214) à parte: regra única por pessoa, lista de quem paga sem card,
-- e o atraso dela SEPARADO do "devendo" do Programa.
-- APLICADA EM PARTE em produção 28/09: seções 1–3 (as três funções). A SEÇÃO 4 (fin.parcelas_devidas sem o 3507214)
-- NÃO foi aplicada: vai junto com o deploy do front que mostra o atraso no bloco Assinatura — antes disso o atraso
-- sumiria do card sem aparecer em lugar nenhum.
-- Conferido (usuário do Financeiro): board 165 pessoas / R$ 1.093.985 / 11 ainda pagam / atraso 120d 24 = R$ 47.949;
-- lista sem card 130 pessoas / R$ 973.668 (as 21 a menos do que 151 nunca pagaram); T29 = 81; sem origem 4.
-- Tempo (cache quente): lista 104–134 ms; RPC do board 39 ms. fn_fin_board_hotmart ≈ 1,1 s com e sem a z51 (lentidão
-- anterior, não desta migration).
-- PROVAS MEDIDAS em produção (28/09, coordenador):
--   P8 regras coincidem: familia HM → (3507214, SUBSCRIPTION) = 1.167; (não 3507214, não SUBSCRIPTION) = 17.975; nenhuma
--      linha mista. A CTE `ass` do board (SUBSCRIPTION) e esta regra (produto 3507214) contam o mesmo conjunto hoje.
--   Junção card × mensalidade (fn_fin_board_hotmart ⋈ fn_fin_board_assinatura_hm por pessoa_chave): HM = 11, AURUM = 5.
--   E1/E2 explain (analyze, buffers) do corpo de fin.assinatura_hm_por_pessoa: 33,9 ms; Bitmap Index Scan em
--      hotmart_transacoes_produto_idx (1.218 linhas), Index Scan hotmart_transacoes_pkey, identidade_pkey e
--      identidade_pessoa_idx; thb_alunos em Seq Scan (1.876 linhas, Merge Join) — no tamanho, o certo.
--   E3 §4 simulada com rollback: devendo HM ≤120 d 51 → 27 parcelas (−24 = −R$ 47.949, exatamente o atraso da
--      mensalidade); fn_fin_board_hotmart 980 → 979 ms. Decisão do João: §4 aplica ANTES do push do front.
--
-- Decisões do Marcio (28/09):
--   1. mensalidade fica à parte no card (bloco "Assinatura HM"); pago e saldo do Programa não mudam;
--   2. quem paga/pagou e não tem card aparece numa lista própria, com a turma de origem (não ganha card);
--   3. atraso da mensalidade separado do "devendo" do Programa: no bloco Assinatura, só dos últimos 120 dias;
--   4. mensalidade não dá acesso ao GPS nem passa pela fila de ativação (z51 cataloga sem trilha).
--
-- 1) fin.assinatura_hm_por_pessoa() — interna. Regra única da mensalidade por pessoa (pessoa = fin.identidade, como em
--    fin.parcelas_devidas): pago, mensalidades pagas, 1ª cobrança, última paga, ainda_paga (≤ 45 dias), atraso ≤ 120 d e
--    antigo (parcela = e-mail × oferta × coalesce(recorrencia,'t:'||transacao), conta uma vez, quitada se algum
--    pago/estornado — a MESMA deduplicação de fin.parcelas_devidas) e turma de origem:
--      calendário = fin.acoes HM com turma, 1ª cobrança em [inicio, coalesce(fim, inicio + 1 dia)), ordem prioridade, inicio desc
--      cadastro   = thb_alunos.turma_id → thb_turmas.codigo, normalizado split_part(codigo,'.',1) ("T29.2" = "T29")
--      origem     = a mais antiga das duas pelo número; senão a que existir; senão NULL ("sem origem").
-- 2) public.fn_fin_assinatura_hm_sem_card() — RPC da lista: quem pagou mensalidade e não tem card (nem HM nem Aurum).
-- 3) public.fn_fin_board_assinatura_hm() — RPC que o board chama UMA vez por abertura, junto de fn_fin_board_hotmart:
--    atraso da mensalidade (≤ 120 d) por pessoa_chave (a mesma chave opaca do board). Assim fn_fin_board_hotmart NÃO é
--    redefinida (o corpo vivo diverge do repo desde a z46).
-- 4) fin.parcelas_devidas passa a EXCLUIR o 3507214 — por replace sobre o corpo VIGENTE (pg_get_functiondef), com guarda.
--    Atinge TODOS os consumidores: fn_fin_board_hotmart (devendo do card, ordem, assinatura_ativa), fn_fin_hotmart_pessoas
--    (situação devendo/inadimplencia_antiga, parcelas_atrasadas) e fn_fin_mapa_alunos (situação atrasado).
--
-- REVERSÃO:
--   do $r$ declare d text; begin
--     d := pg_get_functiondef('fin.parcelas_devidas(text)'::regprocedure);
--     execute replace(d, E'\n       and t.produto_id <> ''3507214''  -- z52: mensalidade do HM antigo fica fora do devendo do Programa', '');
--   end $r$;
--   drop function if exists public.fn_fin_board_assinatura_hm();
--   drop function if exists public.fn_fin_assinatura_hm_sem_card();
--   drop function if exists fin.assinatura_hm_por_pessoa();

-- ─── 1. Regra única da mensalidade por pessoa (interna) ─────────────────────────────────────────────────────────────
create or replace function fin.assinatura_hm_por_pessoa()
returns table (
  pessoa text, nome text, emails text[], documento text, telefone text,
  cobrancas int, mensalidades_pagas int, pago numeric,
  primeira_em timestamptz, primeira date, ultima_paga date, ainda_paga boolean,
  atraso_120d_n int, atraso_120d_valor numeric, atraso_antigo_n int, atraso_antigo_valor numeric,
  turma_calendario text, turma_cadastro text, turma_origem text, origem_regra text)
language sql stable set search_path = ''
as $$
  with tx as materialized (
    -- produto 3507214 = mensalidade do HM antigo (definição do Marcio). Índice hotmart_transacoes_produto_idx.
    select coalesce(ip.pessoa_chave, 'e:' || t.email) pessoa, t.email, t.nome, t.oferta_codigo, t.recorrencia,
           t.transacao, t.grupo, coalesce(t.pedido_em, t.aprovado_em) cobrada_em, t.pedido_em, t.dia_aprovado,
           t.valor_oferta, h.comprador_documento doc, h.comprador_telefone tel
      from fin.vw_transacoes t
      join fin.hotmart_transacoes h on h.transacao = t.transacao
      left join fin.identidade ip on ip.no = 'e:' || t.email
     where t.produto_id = '3507214' and t.email is not null
  ), agg as (
    select x.pessoa,
           (array_agg(x.nome order by x.cobrada_em desc nulls last) filter (where x.nome is not null))[1] nome,
           array_agg(distinct x.email) emails,
           (array_agg(x.doc order by x.cobrada_em desc nulls last) filter (where x.doc is not null))[1] doc,
           (array_agg(x.tel order by x.cobrada_em desc nulls last) filter (where x.tel is not null))[1] tel,
           count(*)::int cobrancas,
           count(*) filter (where x.grupo = 'pago')::int pagas,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) pago,
           min(x.cobrada_em) primeira_em,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ultima_paga
      from tx x
     group by x.pessoa
  ), parc as (
    -- MESMA deduplicação de fin.parcelas_devidas: a Hotmart cria uma transação OVERDUE por tentativa da mesma parcela.
    select x.pessoa, bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde, max(x.valor_oferta) valor
      from tx x
     group by x.pessoa, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), dv as (
    select p.pessoa,
           count(*) filter (where p.desde >= now() - interval '120 days')::int n_atual,
           coalesce(sum(p.valor) filter (where p.desde >= now() - interval '120 days'), 0) v_atual,
           count(*) filter (where p.desde < now() - interval '120 days')::int n_antigo,
           coalesce(sum(p.valor) filter (where p.desde < now() - interval '120 days'), 0) v_antigo
      from parc p
     where p.atrasou and not p.quitada
     group by p.pessoa
  ), em as (
    -- todos os e-mails da pessoa (os da mensalidade + os da identidade), para achar o cadastro de aluno
    select a.pessoa, unnest(a.emails) email from agg a
    union
    select i.pessoa_chave, substr(i.no, 3) from fin.identidade i
     where i.no like 'e:%' and i.pessoa_chave in (select a.pessoa from agg a)
  ), cad as (
    select e.pessoa,
           (array_agg(split_part(tt.codigo, '.', 1)
                      order by substring(split_part(tt.codigo, '.', 1) from '[0-9]+')::int nulls last))[1] turma
      from em e
      join public.thb_alunos al on lower(trim(al.email)) = e.email
      join public.thb_turmas tt on tt.id = al.turma_id
     group by e.pessoa
  ), orig as (
    select a.pessoa, cal.turma t_cal, c.turma t_cad,
           substring(cal.turma from '[0-9]+')::int n_cal, substring(c.turma from '[0-9]+')::int n_cad
      from agg a
      left join cad c on c.pessoa = a.pessoa
      left join lateral (
        select split_part(ac.turma, '.', 1) turma
          from fin.acoes ac
         where ac.produto = 'HM' and ac.turma is not null
           and a.primeira_em >= ac.inicio and a.primeira_em < coalesce(ac.fim, ac.inicio + interval '1 day')
         order by ac.prioridade, ac.inicio desc
         limit 1) cal on true
  )
  select a.pessoa, a.nome, a.emails, a.doc, a.tel,
         a.cobrancas, a.pagas, a.pago,
         a.primeira_em, (a.primeira_em at time zone 'America/Sao_Paulo')::date, a.ultima_paga,
         coalesce(a.ultima_paga >= (now() at time zone 'America/Sao_Paulo')::date - 45, false),
         coalesce(d.n_atual, 0), coalesce(d.v_atual, 0), coalesce(d.n_antigo, 0), coalesce(d.v_antigo, 0),
         o.t_cal, o.t_cad,
         -- regra do vault: pessoa de turma antiga nunca é associada a turma nova → a de MENOR número
         case when o.t_cal is null then o.t_cad
              when o.t_cad is null then o.t_cal
              when coalesce(o.n_cad, 2147483647) < coalesce(o.n_cal, 2147483647) then o.t_cad
              else o.t_cal end,
         case when o.t_cal is null and o.t_cad is null then 'sem origem'
              when o.t_cal is null then 'cadastro'
              when o.t_cad is null then 'calendário'
              when o.t_cal = o.t_cad then 'calendário e cadastro'
              when coalesce(o.n_cad, 2147483647) < coalesce(o.n_cal, 2147483647) then 'cadastro'
              else 'calendário' end
    from agg a
    left join dv d on d.pessoa = a.pessoa
    left join orig o on o.pessoa = a.pessoa;
$$;
revoke all on function fin.assinatura_hm_por_pessoa() from public, anon, authenticated;

-- ─── 2. Lista: pagou mensalidade e não tem card (nem HM nem Aurum) ──────────────────────────────────────────────────
create or replace function public.fn_fin_assinatura_hm_sem_card()
returns table (
  pessoa_chave text, nome text, emails text[], documento text, telefone text,
  turma_origem text, origem_regra text, turma_calendario text, turma_cadastro text,
  primeira date, ultima_paga date, mensalidades_pagas int, pago numeric, ainda_paga boolean,
  atraso_120d_n int, atraso_120d_valor numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_cpf boolean;
begin
  if auth.uid() is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_cpf := coalesce(public.gp_pode_ver_cpf(), false);
  return query
  with board as (
    -- card de qualquer família (HM ou Aurum), pela pessoa — mesmo critério de fn_fin_programa_sem_card (z22)
    select distinct coalesce(i.pessoa_chave, 'e:' || lower(trim(b.email))) pk
      from cs.vw_fin_board b
      left join fin.identidade i on i.no = 'e:' || lower(trim(b.email))
  )
  -- LGPD (regra da 0819g): documento e telefone completos só para gp_pode_ver_cpf(); o resto vê ···1234.
  select fin.chave_opaca(a.pessoa), fin.nome_proprio(a.nome), a.emails,
         case when v_cpf then a.documento
              when a.documento is not null
                then case when length(a.documento) = 14 then 'CNPJ ···' else 'CPF ···' end || right(a.documento, 4) end,
         case when v_cpf then a.telefone
              when a.telefone is not null then '···' || right(regexp_replace(a.telefone, '\D', '', 'g'), 4) end,
         a.turma_origem, a.origem_regra, a.turma_calendario, a.turma_cadastro,
         a.primeira, a.ultima_paga, a.mensalidades_pagas, a.pago, a.ainda_paga,
         a.atraso_120d_n, a.atraso_120d_valor
    from fin.assinatura_hm_por_pessoa() a
   where a.mensalidades_pagas > 0
     and not exists (select 1 from board b where b.pk = a.pessoa)
   order by a.ainda_paga desc, a.atraso_120d_valor desc, a.pago desc;
end $$;
revoke all on function public.fn_fin_assinatura_hm_sem_card() from public, anon;
grant execute on function public.fn_fin_assinatura_hm_sem_card() to authenticated;

-- ─── 3. Board: mensalidade por pessoa, 1 chamada por abertura ───────────────────────────────────────────────────────
-- Casa com fn_fin_board_hotmart por pessoa_chave (fin.chave_opaca da mesma fin.identidade). Sem dado pessoal.
-- Universo limitado ao produto legado 3507214 (~165 pessoas): devolve todas, sem varrer cs.vw_fin_board de novo.
create or replace function public.fn_fin_board_assinatura_hm()
returns table (
  pessoa_chave text, mensalidades_pagas int, pago numeric, primeira date, ultima_paga date, ainda_paga boolean,
  atraso_120d_n int, atraso_120d_valor numeric, turma_origem text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select fin.chave_opaca(a.pessoa), a.mensalidades_pagas, a.pago, a.primeira, a.ultima_paga, a.ainda_paga,
         a.atraso_120d_n, a.atraso_120d_valor, a.turma_origem
    from fin.assinatura_hm_por_pessoa() a;
end $$;
revoke all on function public.fn_fin_board_assinatura_hm() from public, anon;
grant execute on function public.fn_fin_board_assinatura_hm() to authenticated;

-- ─── 4. "Devendo" do Programa sem a mensalidade — replace no corpo VIGENTE, com guarda ──────────────────────────────
do $do$
declare
  d text;
  a1 text := 'where t.familia = p_familia and t.email is not null';
  b1 text := E'where t.familia = p_familia and t.email is not null\n       and t.produto_id <> ''3507214''  -- z52: mensalidade do HM antigo fica fora do devendo do Programa';
begin
  d := pg_get_functiondef('fin.parcelas_devidas(text)'::regprocedure);
  if position('z52: mensalidade' in d) > 0 then
    raise notice 'z52: fin.parcelas_devidas já exclui o 3507214';
  elsif (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 then
    raise exception 'z52: filtro da família não encontrado (ou repetido) no corpo vigente de fin.parcelas_devidas';
  else
    execute replace(d, a1, b1);
  end if;
end $do$;
revoke all on function fin.parcelas_devidas(text) from public, anon, authenticated;


-- ═══ PROVA (só SELECT). Rodar como postgres — fin.* é interna. ═════════════════════════════════════════════════════
/*
-- P0) ANTES de aplicar: guardar o devendo HM atual (para P6).
select sum(n_atual) n_atual, sum(valor_atual) valor_atual, sum(n_antigas) n_antigas, sum(valor_antigo) valor_antigo
  from fin.parcelas_devidas('HM');

-- P1) Números do coordenador. Esperado: pessoas 165 · pago ≈ 1.090.000 · ainda_pagam 11 ·
--     atraso 120d 7 pessoas / 24 / 47.949 · atraso total 38 / 96 / 202.819 · com_origem 160.
select count(*) pessoas, count(*) filter (where mensalidades_pagas > 0) com_pagamento, sum(pago) pago,
       count(*) filter (where ainda_paga) ainda_pagam,
       count(*) filter (where atraso_120d_n > 0) atraso120_pessoas, sum(atraso_120d_n) atraso120_n, sum(atraso_120d_valor) atraso120_valor,
       count(*) filter (where atraso_120d_n + atraso_antigo_n > 0) atraso_pessoas,
       sum(atraso_120d_n + atraso_antigo_n) atraso_n, sum(atraso_120d_valor + atraso_antigo_valor) atraso_valor,
       count(*) filter (where turma_origem is not null) com_origem
  from fin.assinatura_hm_por_pessoa();

-- P2) Card. Esperado: sem card nenhum 151 / R$ 973.668 · com card HM 11 · com card Aurum 5 · ainda pagam sem card HM 8.
with a as (select * from fin.assinatura_hm_por_pessoa()),
b as (select distinct coalesce(i.pessoa_chave, 'e:' || lower(trim(v.email))) pk, v.origem
        from cs.vw_fin_board v left join fin.identidade i on i.no = 'e:' || lower(trim(v.email)))
select count(*) filter (where not exists (select 1 from b where b.pk = a.pessoa)) sem_card,
       sum(a.pago) filter (where not exists (select 1 from b where b.pk = a.pessoa)) sem_card_pago,
       count(*) filter (where not exists (select 1 from b where b.pk = a.pessoa) and a.mensalidades_pagas > 0) sem_card_com_pagamento,
       count(*) filter (where exists (select 1 from b where b.pk = a.pessoa and b.origem = 'HM')) card_hm,
       count(*) filter (where exists (select 1 from b where b.pk = a.pessoa and b.origem = 'AURUM')) card_aurum,
       count(*) filter (where a.ainda_paga and not exists (select 1 from b where b.pk = a.pessoa and b.origem = 'HM')) ainda_paga_sem_card_hm
  from a;

-- P3) Turma de origem. Esperado: T29 = 80 / ≈ R$ 331 mil · NULL (sem origem) = 5.
select turma_origem, origem_regra, count(*), sum(pago) from fin.assinatura_hm_por_pessoa() group by 1, 2 order by 3 desc;

-- P4) Minha divergência da regra literal (sem "turma is not null" no calendário): pessoas cuja ação vencedora não tem
--     turma. Esperado: 0 — se > 0, o 160 do coordenador e o meu diferem por isto.
select count(*) from fin.assinatura_hm_por_pessoa() a
 where (select ac.turma from fin.acoes ac
         where ac.produto = 'HM' and a.primeira_em >= ac.inicio and a.primeira_em < coalesce(ac.fim, ac.inicio + interval '1 day')
         order by ac.prioridade, ac.inicio desc limit 1) is null
   and a.turma_calendario is not null;

-- P5) Códigos de turma do cadastro que não são "T<n>" (a comparação "pelo número" não vale para eles).
select turma_cadastro, count(*) from fin.assinatura_hm_por_pessoa() where turma_cadastro !~ '^T[0-9]+$' group by 1;

-- P6) DEPOIS de aplicar: devendo HM − P0 = −(atraso da mensalidade). Esperado: n_atual −24 / valor_atual −47.949 ·
--     n_antigas −72 / valor_antigo −154.870 (se P1 bater).
select sum(n_atual), sum(valor_atual), sum(n_antigas), sum(valor_antigo) from fin.parcelas_devidas('HM');

-- P7) Impacto nos consumidores: pessoas com atraso ≤120d de mensalidade que deixam de estar "devendo" em
--     fn_fin_board_hotmart / fn_fin_hotmart_pessoas / fn_fin_mapa_alunos (≤ 7).
select count(*) from fin.assinatura_hm_por_pessoa() a
  left join fin.parcelas_devidas('HM') d on d.pessoa = a.pessoa
 where a.atraso_120d_n > 0 and coalesce(d.n_atual, 0) = 0;

-- P8) Regra do board (CTE ass: familia HM + oferta_modo SUBSCRIPTION) × regra desta migration (produto 3507214).
--     Esperado: só (true, true) = 1.165. Linha (false, true) ou (true, false) = as duas regras divergem.
select produto_id = '3507214' eh_3507214, oferta_modo is not distinct from 'SUBSCRIPTION' eh_subscription, count(*)
  from fin.vw_transacoes where familia = 'HM' group by 1, 2;

-- P9) Fila de ativação: compras do 3507214 que a fila JÁ mostra (o fallback por nome "%holding%masters%" casa o nome do
--     produto independentemente do catálogo). Rodar ANTES e DEPOIS da z51; esperado igual antes/depois.
select f.categoria, f.bucket, f.aluno_novo, count(*)
  from public.fn_hm_fila() f join public.compras c on c.id = f.compra_id
 where c.produto_id::text = '3507214' group by 1, 2, 3;

-- P10) Corpo VIVO das funções que decidem card/fila/trilha, só as linhas que citam catálogo (preciso disto para provar
--      que 'renovacao' + product_type NULL + concede_trilha false não cria card nem concede trilha).
select p.oid::regprocedure fn, l.n, l.linha
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace,
       regexp_split_to_table(p.prosrc, E'\n') with ordinality l(linha, n)
 where ns.nspname || '.' || p.proname in ('cs.fn_seed_contato_hm','public.fn_hm_fila','cs.fn_hm_programa',
         'cs.fn_hm_produto_da_oferta','cs.fn_hm_pagamento_do_produto','cs.fn_hm_lancar_compra',
         'cs.fn_hm_provisionar_aluno','public.fn_fin_saude')
   and l.linha ~* 'renovacao|product_type|concede_trilha|recorrente|categoria|holding'
 order by 1, 2;
select p.oid::regprocedure from pg_proc p where p.prosrc ilike '%concede_trilha%';
select tgname, tgfoid::regprocedure from pg_trigger where tgrelid = 'public.compras'::regclass and not tgisinternal;

-- ─── EXPLAIN (corpo solto, sem a chamada da função). Meta: lista ≤ 200 ms; board não piora. ───────────────────────
-- E1) Lista (corpo de fin.assinatura_hm_por_pessoa + filtro de card da RPC).
explain (analyze, buffers)
with tx as materialized (
  select coalesce(ip.pessoa_chave, 'e:' || t.email) pessoa, t.email, t.nome, t.oferta_codigo, t.recorrencia,
         t.transacao, t.grupo, coalesce(t.pedido_em, t.aprovado_em) cobrada_em, t.pedido_em, t.dia_aprovado,
         t.valor_oferta, h.comprador_documento doc, h.comprador_telefone tel
    from fin.vw_transacoes t
    join fin.hotmart_transacoes h on h.transacao = t.transacao
    left join fin.identidade ip on ip.no = 'e:' || t.email
   where t.produto_id = '3507214' and t.email is not null
), agg as (
  select x.pessoa,
         (array_agg(x.nome order by x.cobrada_em desc nulls last) filter (where x.nome is not null))[1] nome,
         array_agg(distinct x.email) emails,
         (array_agg(x.doc order by x.cobrada_em desc nulls last) filter (where x.doc is not null))[1] doc,
         (array_agg(x.tel order by x.cobrada_em desc nulls last) filter (where x.tel is not null))[1] tel,
         count(*)::int cobrancas, count(*) filter (where x.grupo = 'pago')::int pagas,
         coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) pago,
         min(x.cobrada_em) primeira_em, max(x.dia_aprovado) filter (where x.grupo = 'pago') ultima_paga
    from tx x group by x.pessoa
), parc as (
  select x.pessoa, bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'atrasado') atrasou,
         min(x.pedido_em) desde, max(x.valor_oferta) valor
    from tx x group by x.pessoa, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
), dv as (
  select p.pessoa,
         count(*) filter (where p.desde >= now() - interval '120 days')::int n_atual,
         coalesce(sum(p.valor) filter (where p.desde >= now() - interval '120 days'), 0) v_atual
    from parc p where p.atrasou and not p.quitada group by p.pessoa
), em as (
  select a.pessoa, unnest(a.emails) email from agg a
  union
  select i.pessoa_chave, substr(i.no, 3) from fin.identidade i
   where i.no like 'e:%' and i.pessoa_chave in (select a.pessoa from agg a)
), cad as (
  select e.pessoa, (array_agg(split_part(tt.codigo, '.', 1)
                    order by substring(split_part(tt.codigo, '.', 1) from '[0-9]+')::int nulls last))[1] turma
    from em e
    join public.thb_alunos al on lower(trim(al.email)) = e.email
    join public.thb_turmas tt on tt.id = al.turma_id
   group by e.pessoa
), orig as (
  select a.pessoa, cal.turma t_cal, c.turma t_cad
    from agg a
    left join cad c on c.pessoa = a.pessoa
    left join lateral (select split_part(ac.turma, '.', 1) turma from fin.acoes ac
                        where ac.produto = 'HM' and ac.turma is not null
                          and a.primeira_em >= ac.inicio and a.primeira_em < coalesce(ac.fim, ac.inicio + interval '1 day')
                        order by ac.prioridade, ac.inicio desc limit 1) cal on true
), board as (
  select distinct coalesce(i.pessoa_chave, 'e:' || lower(trim(b.email))) pk
    from cs.vw_fin_board b left join fin.identidade i on i.no = 'e:' || lower(trim(b.email))
)
select fin.chave_opaca(a.pessoa), fin.nome_proprio(a.nome), a.emails, a.doc, a.tel, o.t_cal, o.t_cad,
       a.pagas, a.pago, a.ultima_paga, coalesce(d.n_atual, 0), coalesce(d.v_atual, 0)
  from agg a
  left join dv d on d.pessoa = a.pessoa
  left join orig o on o.pessoa = a.pessoa
 where a.pagas > 0 and not exists (select 1 from board b where b.pk = a.pessoa);
-- Procurar: Index Scan em hotmart_transacoes_produto_idx (ou Bitmap) com Index Cond produto_id = '3507214';
-- Index Scan em thb_alunos pela expressão lower(TRIM(BOTH FROM email)); fin.identidade pela PK.

-- E2) Board novo (RPC fn_fin_board_assinatura_hm) = E1 sem o CTE board e sem nome/documento/telefone: medir com a
--     chamada, pois o corpo é o de E1 → explain (analyze, buffers) select * from fin.assinatura_hm_por_pessoa();

-- E3) Board existente ANTES e DEPOIS (a única mudança nele é o predicado a mais em fin.parcelas_devidas):
--     corpo solto de parcelas_devidas com o predicado novo:
explain (analyze, buffers)
with tx as (
  select coalesce(ip.pessoa_chave, 'e:' || t.email) pessoa, t.email, t.produto_id, t.oferta_codigo,
         t.recorrencia, t.transacao, t.grupo, t.pedido_em, t.valor_oferta
    from fin.vw_transacoes t
    left join fin.identidade ip on ip.no = 'e:' || t.email
   where t.familia = 'HM' and t.email is not null
     and t.produto_id <> '3507214'
), parc as (
  select x.pessoa, bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'atrasado') atrasou,
         min(x.pedido_em) desde, max(x.valor_oferta) valor
    from tx x group by x.pessoa, x.email, x.produto_id, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
)
select p.pessoa, count(*) filter (where p.desde >= now() - interval '120 days')::int
  from parc p where p.atrasou and not p.quitada group by p.pessoa;
--     e o board inteiro com JWT de financeiro, antes e depois (tempo total):
--     begin; set local role authenticated; set local request.jwt.claims = '{"sub":"<uuid financeiro>"}';
--     explain (analyze, buffers) select * from public.fn_fin_board_hotmart(); rollback;
*/
