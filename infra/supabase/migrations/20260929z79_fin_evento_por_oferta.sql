-- 20260929z79 — Venda de evento cai no funil (card) e na trajetória PELA OFERTA, sem marcação manual
--
-- Por quê (Marcio, 29/09): a venda de um evento tem que ir sozinha para o funil certo.
-- Caso real: 2º Encontro Acelera Holding (28/09/2026, 19h), ofertas HM 506c1lz1 R$ 1.499,
-- 3kojl3fv R$ 1.249, mhfkfbdi R$ 999 (produto 5064314). Um aluno pagou 3kojl3fv em 29/09 10:37.
--   * fn_fin_trajetoria atribuía por categoria+produto+janela (fin.evento_produtos) e depois
--     "dia do evento"; a Imersão HT32 (holding_total, 26–30/09, 5064314 é 'oferta' do
--     holding_total) está na janela => a venda do encontro caía na HT32.
--   * fin.vw_acao_card: link de venda > dia do evento > comercial > janela; não olhava oferta.
--     O 2º Encontro nem existia em fin.eventos; o funil 135 só pegava por marcação manual (z78).
-- Agora:
--   1. fin.eventos ganha o 2º Encontro (categoria nova 'encontro_acelera'), as 3 ofertas vão
--      para fin.evento_ofertas e fin.acoes 135 passa a apontar para o evento.
--   2. REGRA POR OFERTA, prioridade máxima nas duas pontas:
--      a) fn_fin_trajetoria: lateral "evo" (oferta cadastrada em fin.evento_ofertas) antes de
--         ev0; ev0..ev3 só rodam se evo for nulo. Regra 'oferta do evento' — ou 'ingresso do
--         evento' quando o produto é ingresso da categoria (fin.evento_produtos papel
--         'ingresso'), para não rebaixar a papel 'compra' os ingressos das clínicas que já
--         estão em fin.evento_ofertas (z4).
--      b) fin.vw_acao_card: oferta_codigo atravessa cand/primeira/base/retorno/evento; lateral
--         "o" = fin.acoes ligada ao evento da oferta (produto = origem do card); sem ação
--         ligada, nome do evento + canal por categoria (igual a d). Ordem: manual > migrado >
--         oferta > link de venda > dia do evento > comercial > janela. Mesma coisa no retorno.
--         Colunas da view: mesmas 11, mesma ordem.
--   fin.acao_card_manual NÃO é tocada (as linhas da z78 continuam; decisão do Marcio).
--
-- Guardas (falham ANTES de gravar): CHECK em fin.eventos.categoria no vivo; fin.acoes 135 é o
-- 2º Encontro e não aponta para outro evento; oferta já ligada a OUTRO evento; corpo vivo de
-- fn_fin_trajetoria = o corpo base desta migration (sem comentários/espaços); view viva tem
-- as 11 colunas e o retorno_ok da z77.
--
-- Escala: fin.evento_ofertas tem ~11 linhas (8 da z4 + as do vivo) e ganha 3. Já tem PK
-- (evento_id, oferta_codigo) e o índice único evento_ofertas_oferta_uq (oferta_codigo) (z4):
-- NÃO precisa de índice novo; com 14 linhas cabe em 1 página e o planner faz Seq Scan (mais
-- barato que o índice nesse tamanho). O lookup é 1 por transação da pessoa (trajetória) e 1
-- por linha de evento da view (~384 cards + dezenas de retornos). Custo novo por item, não
-- por base; o índice único garante no máximo 1 evento por oferta.
-- Meta (orquestrador mede, antes/depois): explain (analyze, buffers) select * from
-- fin.vw_acao_card; — base z75 ~122–135 ms; aceitar até +10 ms.
--
-- Reversão (numa transação):
--   1. fn_fin_trajetoria: create or replace com o corpo em v_base_trajetoria (guarda abaixo,
--      é o corpo vivo de 29/09) + mesmo cabeçalho/grants desta migration.
--   2. fin.vw_acao_card: create or replace view com o texto da z75 + a troca da z77
--      (colunas idênticas, create or replace basta) + revoke all ... from public, anon, authenticated.
--   3. update fin.acoes set evento_id = null where id = 135;
--      delete from fin.evento_ofertas where oferta_codigo in ('506c1lz1','3kojl3fv','mhfkfbdi');
--      delete from fin.eventos where categoria = 'encontro_acelera' and inicio = '2026-09-28';
--      (linha criada por esta migration; se algo passou a referenciá-la — ex. fin.eventos_planejados —
--       a FK recusa o delete: então deixe a linha e reverta só 1–2 e as ofertas.)
-- Nenhuma linha existente é apagada ou alterada, exceto fin.acoes 135 (evento_id null -> id novo).

-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_ck   text;
  v_src  text;
  v_fn   record;
  v_cols text;
  v_def  text;
  v_ev   bigint;
  v_base_trajetoria text := $esp$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with alvo as (
    select lower(trim(p_email)) email
  ), emails as (
    select distinct coalesce(substr(i2.no, 3), a.email) email
      from alvo a
      left join fin.identidade i on i.no = 'e:' || a.email
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
  ), evs as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    select t.*, coalesce(t.dia_aprovado, t.dia_pedido) d, cat.categoria cat
      from emails e
      join fin.vw_transacoes t on t.email = e.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.grupo in ('pago','estornado','atrasado','em_aberto') and coalesce(t.recorrencia, 1) = 1
  )
  select x.d, x.familia, x.produto_nome, x.oferta_codigo,
         case x.grupo when 'pago' then 'pago' when 'estornado' then 'estornado' when 'atrasado' then 'em atraso' else 'em aberto' end,
         round(x.valor_oferta * case when x.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(x.parcelas, 1) else 1 end, 2),
         x.parcelas,
         case when ev.regra = 'ingresso do evento' then 'ingresso'
              when x.produto_id = '5064314' and x.d >= date '2026-06-25' and coalesce(x.cat, '') not in ('renovacao','reserva') then 'programa'
              else 'compra' end,
         ev.id, ev.nome, ev.categoria,
         tor.turma,
         ev.regra
    from tx x
    left join lateral (
      select e.id, e.nome, e.categoria, case when ep.papel = 'ingresso' then 'ingresso do evento' else 'oferta do evento' end regra
        from evs e
        join fin.evento_produtos ep on ep.categoria = e.categoria and ep.produto_id = x.produto_id
       where (ep.papel = 'ingresso' and x.d between e.ing_de and e.venda_ate)
          or (ep.papel = 'oferta' and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate)
       order by (ep.papel = 'oferta') desc, e.venda_ate, e.inicio limit 1
    ) ev0 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'dia do evento'::text regra
        from fin.eventos e
       where ev0.id is null and e.setor = 'educacao'
         and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
         and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1
    ) ev1 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'depois do evento'::text regra
        from fin.eventos e
       where ev0.id is null and ev1.id is null and e.setor = 'educacao'
         and e.venda_ate < x.d and e.venda_ate >= x.d - 30
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by e.venda_ate desc limit 1
    ) ev2 on true
    left join lateral (
      select null::bigint id, a.nome, 'aurum_turma'::text categoria, 'lançamento da turma Aurum'::text regra
        from fin.acoes a
       where ev0.id is null and ev1.id is null and ev2.id is null and x.familia = 'AURUM'
         and a.produto = 'AURUM' and a.prioridade = 50
         and (x.d::timestamp at time zone 'America/Sao_Paulo') >= a.inicio and (x.d::timestamp at time zone 'America/Sao_Paulo') < a.fim
       limit 1
    ) ev3 on true
    cross join lateral (select coalesce(ev0.id, ev1.id, ev2.id) id, coalesce(ev0.nome, ev1.nome, ev2.nome, ev3.nome) nome,
                               coalesce(ev0.categoria, ev1.categoria, ev2.categoria, ev3.categoria) categoria,
                               coalesce(ev0.regra, ev1.regra, ev2.regra, ev3.regra) regra) ev
    left join lateral (select a.turma from fin.acoes a
                        where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) >= a.inicio
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) < a.fim
                        order by a.prioridade desc, a.inicio desc limit 1) tor on true
   order by x.d, x.pedido_em;
end
$esp$;
begin
  -- 0.1 categoria nova: CHECK de memória apaga valor em silêncio — se houver CHECK vivo que cite
  --     categoria, PARA e mostra a definição (pg_get_constraintdef) para a troca ser feita sobre ela.
  select string_agg(c.conname || ': ' || pg_get_constraintdef(c.oid), ' | ') into v_ck
    from pg_constraint c
   where c.conrelid = 'fin.eventos'::regclass and c.contype = 'c'
     and pg_get_constraintdef(c.oid) ilike '%categoria%'
     and pg_get_constraintdef(c.oid) not ilike '%encontro_acelera%';
  if v_ck is not null then
    raise exception 'z79: fin.eventos tem CHECK em categoria sem ''encontro_acelera'': %', v_ck;
  end if;

  -- 0.2 fin.acoes 135 é o 2º Encontro e não aponta para outro evento
  select e.id into v_ev from fin.eventos e where e.categoria = 'encontro_acelera' and e.inicio = date '2026-09-28';
  if not exists (select 1 from fin.acoes a
                  where a.id = 135 and a.nome like '2º Encontro Acelera Holding%'
                    and (a.evento_id is null or a.evento_id = v_ev)) then
    raise exception 'z79: fin.acoes 135 não é o 2º Encontro Acelera Holding ou já aponta para outro evento';
  end if;

  -- 0.3 oferta já ligada a OUTRO evento (índice único em oferta_codigo faria o insert sumir em silêncio)
  select string_agg(eo.oferta_codigo || ' -> evento ' || eo.evento_id, ', ') into v_ck
    from fin.evento_ofertas eo
   where eo.oferta_codigo in ('506c1lz1','3kojl3fv','mhfkfbdi')
     and eo.evento_id is distinct from v_ev;
  if v_ck is not null then
    raise exception 'z79: oferta já ligada a outro evento: %', v_ck;
  end if;

  -- 0.4 corpo vivo de fn_fin_trajetoria = base desta migration (ou já é a versão z79)
  select p.prosrc, p.provolatile, p.prosecdef, p.proconfig into v_fn
    from pg_proc p where p.oid = 'public.fn_fin_trajetoria(text)'::regprocedure;
  if position('evo on true' in v_fn.prosrc) = 0
     and regexp_replace(regexp_replace(v_fn.prosrc, '--[^\n]*', '', 'g'), '\s+', '', 'g')
      <> regexp_replace(regexp_replace(v_base_trajetoria, '--[^\n]*', '', 'g'), '\s+', '', 'g') then
    raise exception 'z79: corpo vivo de public.fn_fin_trajetoria diverge do corpo base desta migration';
  end if;
  if v_fn.provolatile <> 's' or not v_fn.prosecdef
     or coalesce(array_to_string(v_fn.proconfig, ','), '') not like 'search_path=%' then
    raise exception 'z79: atributos vivos de fn_fin_trajetoria mudaram (volatile %, definer %, config %)',
      v_fn.provolatile, v_fn.prosecdef, v_fn.proconfig;
  end if;

  -- 0.5 view viva: 11 colunas na ordem da z75 e retorno_ok da z77
  select string_agg(a.attname, ',' order by a.attnum) into v_cols
    from pg_attribute a where a.attrelid = 'fin.vw_acao_card'::regclass and a.attnum > 0 and not a.attisdropped;
  if v_cols <> 'contato_hm_id,acao_nome,acao_data,acao_regra,acao_canal,captado_em,captado_sck,voltou_nome,voltou_data,voltou_regra,voltou_transacao' then
    raise exception 'z79: colunas vivas de fin.vw_acao_card diferentes da z75: %', v_cols;
  end if;
  v_def := pg_get_viewdef('fin.vw_acao_card'::regclass, true);
  if position('evento_ofertas' in v_def) = 0
     and (position('ARRAY[''sinal''::text, ''compra_cheia''::text]' in v_def) = 0
          or position('''diferenca''::text]))' in v_def) > 0
          or position('acao_card_manual' in v_def) = 0) then
    raise exception 'z79: fin.vw_acao_card viva não é a z75 + z77';
  end if;
end $guarda$;


-- ─── 1. Evento, ofertas e ligação da ação 135 ───────────────────────────────────────────────
insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, codigo, fonte, observacao, turma_hm, automatico)
values ('2º Encontro Acelera Holding', 'encontro_acelera', 'educacao',
        date '2026-09-28', date '2026-09-28', date '2026-09-28', date '2026-09-28',
        null, 'ofertas do Arthur no WhatsApp 28/09',
        'ao vivo 28/09 19h; ofertas HM (5064314) 506c1lz1 R$ 1.499 · 3kojl3fv R$ 1.249 · mhfkfbdi R$ 999; funil = fin.acoes 135',
        'T41', false)
on conflict (categoria, inicio) do nothing;

insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao)
select e.id, o.oferta, o.obs
  from (values
    ('506c1lz1', '2º Encontro Acelera — HM R$ 1.499'),
    ('3kojl3fv', '2º Encontro Acelera — HM R$ 1.249'),
    ('mhfkfbdi', '2º Encontro Acelera — HM R$ 999')
  ) o(oferta, obs)
  join fin.eventos e on e.categoria = 'encontro_acelera' and e.inicio = date '2026-09-28'
on conflict do nothing;

update fin.acoes a
   set evento_id = e.id
  from fin.eventos e
 where a.id = 135
   and e.categoria = 'encontro_acelera' and e.inicio = date '2026-09-28'
   and a.evento_id is distinct from e.id;

do $confere$
declare v_n int; v_a bigint; v_e bigint;
begin
  select e.id into v_e from fin.eventos e where e.categoria = 'encontro_acelera' and e.inicio = date '2026-09-28';
  select count(*) into v_n from fin.evento_ofertas eo
   where eo.evento_id = v_e and eo.oferta_codigo in ('506c1lz1','3kojl3fv','mhfkfbdi');
  select a.evento_id into v_a from fin.acoes a where a.id = 135;
  if v_e is null or v_n <> 3 or v_a is distinct from v_e then
    raise exception 'z79: cadastro incompleto (evento %, ofertas %/3, acoes 135 -> %)', v_e, v_n, v_a;
  end if;
end $confere$;


-- ─── 2a. fn_fin_trajetoria: oferta do evento antes de qualquer janela ────────────────────────
create or replace function public.fn_fin_trajetoria(p_email text)
returns table (dia date, familia text, produto text, oferta text, situacao text, valor numeric, parcelas int,
               papel text, evento_id bigint, evento text, evento_categoria text, turma text, regra_evento text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with alvo as (
    select lower(trim(p_email)) email
  ), emails as (
    select distinct coalesce(substr(i2.no, 3), a.email) email
      from alvo a
      left join fin.identidade i on i.no = 'e:' || a.email
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
  ), evs as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    select t.*, coalesce(t.dia_aprovado, t.dia_pedido) d, cat.categoria cat
      from emails e
      join fin.vw_transacoes t on t.email = e.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.grupo in ('pago','estornado','atrasado','em_aberto') and coalesce(t.recorrencia, 1) = 1
  )
  select x.d, x.familia, x.produto_nome, x.oferta_codigo,
         case x.grupo when 'pago' then 'pago' when 'estornado' then 'estornado' when 'atrasado' then 'em atraso' else 'em aberto' end,
         round(x.valor_oferta * case when x.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(x.parcelas, 1) else 1 end, 2),
         x.parcelas,
         case when ev.regra = 'ingresso do evento' then 'ingresso'
              when x.produto_id = '5064314' and x.d >= date '2026-06-25' and coalesce(x.cat, '') not in ('renovacao','reserva') then 'programa'
              else 'compra' end,
         ev.id, ev.nome, ev.categoria,
         tor.turma,
         ev.regra
    from tx x
    -- z79: oferta cadastrada para o evento (fin.evento_ofertas; índice único em oferta_codigo) vence qualquer janela
    left join lateral (
      select e.id, e.nome, e.categoria,
             case when exists (select 1 from fin.evento_produtos ep
                                where ep.categoria = e.categoria and ep.produto_id = x.produto_id and ep.papel = 'ingresso')
                  then 'ingresso do evento' else 'oferta do evento' end regra
        from fin.evento_ofertas eo
        join fin.eventos e on e.id = eo.evento_id
       where eo.oferta_codigo = x.oferta_codigo
       limit 1
    ) evo on true
    left join lateral (
      select e.id, e.nome, e.categoria, case when ep.papel = 'ingresso' then 'ingresso do evento' else 'oferta do evento' end regra
        from evs e
        join fin.evento_produtos ep on ep.categoria = e.categoria and ep.produto_id = x.produto_id
       where evo.id is null
         and ((ep.papel = 'ingresso' and x.d between e.ing_de and e.venda_ate)
           or (ep.papel = 'oferta' and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate))
       order by (ep.papel = 'oferta') desc, e.venda_ate, e.inicio limit 1
    ) ev0 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'dia do evento'::text regra
        from fin.eventos e
       where evo.id is null and ev0.id is null and e.setor = 'educacao'
         and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
         and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1
    ) ev1 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'depois do evento'::text regra
        from fin.eventos e
       where evo.id is null and ev0.id is null and ev1.id is null and e.setor = 'educacao'
         and e.venda_ate < x.d and e.venda_ate >= x.d - 30
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by e.venda_ate desc limit 1
    ) ev2 on true
    left join lateral (
      select null::bigint id, a.nome, 'aurum_turma'::text categoria, 'lançamento da turma Aurum'::text regra
        from fin.acoes a
       where evo.id is null and ev0.id is null and ev1.id is null and ev2.id is null and x.familia = 'AURUM'
         and a.produto = 'AURUM' and a.prioridade = 50
         and (x.d::timestamp at time zone 'America/Sao_Paulo') >= a.inicio and (x.d::timestamp at time zone 'America/Sao_Paulo') < a.fim
       limit 1
    ) ev3 on true
    cross join lateral (select coalesce(evo.id, ev0.id, ev1.id, ev2.id) id,
                               coalesce(evo.nome, ev0.nome, ev1.nome, ev2.nome, ev3.nome) nome,
                               coalesce(evo.categoria, ev0.categoria, ev1.categoria, ev2.categoria, ev3.categoria) categoria,
                               coalesce(evo.regra, ev0.regra, ev1.regra, ev2.regra, ev3.regra) regra) ev
    left join lateral (select a.turma from fin.acoes a
                        where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) >= a.inicio
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) < a.fim
                        order by a.prioridade desc, a.inicio desc limit 1) tor on true
   order by x.d, x.pedido_em;
end
$$;
revoke all on function public.fn_fin_trajetoria(text) from public, anon;
grant execute on function public.fn_fin_trajetoria(text) to authenticated;


-- ─── 2b. fin.vw_acao_card: oferta do evento antes do link de venda ───────────────────────────
-- Texto = z75 + troca da z77 (retorno_ok sem 'diferenca'); mudanças z79 marcadas.
create or replace view fin.vw_acao_card as
 WITH card AS (
         SELECT b_1.contato_hm_id,
            b_1.origem,
            lower(TRIM(BOTH FROM b_1.email)) AS email,
            ch.criado_em AS entrada
           FROM cs.vw_fin_board b_1
             JOIN cs.contatos_hm ch ON ch.id = b_1.contato_hm_id
        ), emails AS (
         SELECT c.contato_hm_id,
            COALESCE(substr(i2.no, 3), c.email) AS email
           FROM card c
             LEFT JOIN fin.identidade i ON i.no = ('e:'::text || c.email)
             LEFT JOIN fin.identidade i2 ON i2.pessoa_chave = i.pessoa_chave AND i2.no ~~ 'e:%'::text
        ), cand AS (
         SELECT c.contato_hm_id,
            c.origem,
            t.transacao,
            t.aprovado_em,
            t.dia_aprovado,
            t.origem_sck,
            t.oferta_codigo,
            t.migrado,
            t.categoria,
            t.grupo,
            t.entrada_ok,
            t.retorno_ok
           FROM card c
             JOIN emails e ON e.contato_hm_id = c.contato_hm_id
             JOIN LATERAL ( SELECT x.transacao,
                    COALESCE(x.aprovado_em, x.pedido_em) AS aprovado_em,
                    COALESCE(x.dia_aprovado, x.dia_pedido) AS dia_aprovado,
                    x.origem_sck,
                    x.oferta_codigo,
                    c.origem = 'HM'::text AND COALESCE(x.dia_aprovado, x.dia_pedido) < '2026-06-25'::date AS migrado,
                    cat.categoria,
                    x.grupo,
                        CASE
                            WHEN c.origem = 'HM'::text THEN x.produto_id = '5064314'::text AND (COALESCE(cat.categoria, ''::text) <> ALL (ARRAY['renovacao'::text, 'reserva'::text])) AND (COALESCE(x.dia_aprovado, x.dia_pedido) >= '2026-06-25'::date OR x.grupo = 'pago'::text)
                            ELSE x.grupo = 'pago'::text
                        END AS entrada_ok,
                    COALESCE((c.origem <> 'HM'::text OR x.produto_id = '5064314'::text)
                        AND (x.grupo = ANY (ARRAY['pago'::text, 'em_aberto'::text, 'atrasado'::text]))
                        AND (cat.categoria = ANY (ARRAY['sinal'::text, 'compra_cheia'::text]))
                        AND COALESCE(x.recorrencia, 1) = 1
                        AND x.oferta_modo IS DISTINCT FROM 'SUBSCRIPTION'::text
                        AND COALESCE(x.aprovado_em, x.pedido_em) >= (now() - '90 days'::interval), false) AS retorno_ok
                   FROM fin.vw_transacoes x
                     LEFT JOIN public.hm_product_catalog cat ON cat.offer_code = x.oferta_codigo
                  WHERE x.email = e.email AND x.familia = c.origem) t ON true
          WHERE t.entrada_ok OR t.retorno_ok
        ), primeira AS (
         SELECT DISTINCT ON (t.contato_hm_id) t.contato_hm_id,
            t.transacao,
            t.aprovado_em,
            t.dia_aprovado,
            t.origem_sck,
            t.oferta_codigo,
            t.migrado
           FROM cand t
          WHERE t.entrada_ok
          ORDER BY t.contato_hm_id, (COALESCE(t.origem = 'HM'::text AND NOT t.migrado, false)) DESC, (t.grupo = ANY (ARRAY['pago'::text, 'estornado'::text, 'em_aberto'::text, 'atrasado'::text])) DESC, (COALESCE(t.origem <> 'HM'::text AND (t.categoria = ANY (ARRAY['sinal'::text, 'compra_cheia'::text])), false)) DESC, (t.dia_aprovado >= '2026-01-01'::date) DESC, t.aprovado_em
        ), base AS (
         SELECT c.contato_hm_id,
            c.origem,
            c.email,
            c.entrada,
            p.transacao,
            p.aprovado_em,
            p.dia_aprovado,
            p.origem_sck,
            p.oferta_codigo,
            COALESCE(p.migrado, false) AS migrado,
            COALESCE(p.aprovado_em, c.entrada) AS quando,
            COALESCE(p.origem_sck ~~* '%comercial%'::text OR p.origem_sck ~~* '%jonathan%'::text, false) AS comercial
           FROM card c
             LEFT JOIN primeira p ON p.contato_hm_id = c.contato_hm_id
        ), retorno AS (
         SELECT DISTINCT ON (b.contato_hm_id) b.contato_hm_id,
            b.origem,
            t.transacao,
            t.aprovado_em AS quando,
            t.origem_sck,
            t.oferta_codigo
           FROM base b
             JOIN cand t ON t.contato_hm_id = b.contato_hm_id
          WHERE t.retorno_ok AND t.transacao IS DISTINCT FROM b.transacao AND (b.aprovado_em IS NULL OR t.aprovado_em > b.aprovado_em)
          ORDER BY b.contato_hm_id, t.aprovado_em DESC, t.transacao DESC
        ), evento AS (
         SELECT 'entrada'::text AS papel,
            b.contato_hm_id,
            b.origem,
            b.quando,
            b.origem_sck,
            b.comercial,
            b.transacao,
            b.oferta_codigo
           FROM base b
        UNION ALL
         SELECT 'retorno'::text AS papel,
            r.contato_hm_id,
            r.origem,
            r.quando,
            r.origem_sck,
            COALESCE(r.origem_sck ~~* '%comercial%'::text OR r.origem_sck ~~* '%jonathan%'::text, false) AS comercial,
            r.transacao,
            r.oferta_codigo
           FROM retorno r
        ), regra AS (
         SELECT ev.papel,
            ev.contato_hm_id,
            ev.quando,
            ev.comercial,
            ev.transacao,
            o.nome AS o_nome,
            o.inicio AS o_inicio,
            o.canal AS o_canal,
            s.nome AS s_nome,
            s.inicio AS s_inicio,
            s.canal AS s_canal,
            j.nome AS j_nome,
            j.inicio AS j_inicio,
            j.canal AS j_canal,
            d.nome AS d_nome,
            d.inicio AS d_inicio,
            d.canal AS d_canal
           FROM evento ev
             -- z79: oferta cadastrada para o evento (fin.evento_ofertas) -> ação ligada ao evento; sem ação, o evento
             LEFT JOIN LATERAL ( SELECT COALESCE(ao.nome, e.nome) AS nome,
                    (COALESCE(e.carrinho_inicio, e.inicio)::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS inicio,
                    COALESCE(ao.canal,
                        CASE e.categoria
                            WHEN 'jornada'::text THEN 'Jornada'::text
                            WHEN 'holding_total'::text THEN 'Holding Total'::text
                            WHEN 'certificacao'::text THEN 'Holding Total'::text
                            WHEN 'live_hm'::text THEN 'Live Direto ao Ponto'::text
                            WHEN 'clinica'::text THEN 'Clínica'::text
                            WHEN 'imersao'::text THEN 'Imersão'::text
                            WHEN 'encontro_thb'::text THEN 'Encontro THB'::text
                            WHEN 'encontro_acelera'::text THEN 'Acelera Holding'::text
                            WHEN 'aurum_plus'::text THEN 'Aurum+'::text
                            WHEN 'congresso'::text THEN 'Congresso'::text
                            WHEN 'diamantes'::text THEN 'Diamantes'::text
                            WHEN 'residencia'::text THEN 'Residência'::text
                            WHEN 'workshop'::text THEN 'Residência'::text
                            WHEN 'lancamento_cnhf'::text THEN 'CNHF'::text
                            ELSE e.categoria
                        END) AS canal
                   FROM fin.evento_ofertas eo
                     JOIN fin.eventos e ON e.id = eo.evento_id
                     LEFT JOIN LATERAL ( SELECT a.nome,
                            a.canal
                           FROM fin.acoes a
                          WHERE a.evento_id = e.id AND a.produto = ev.origem
                          ORDER BY a.prioridade, a.id
                         LIMIT 1) ao ON true
                  WHERE eo.oferta_codigo = ev.oferta_codigo
                 LIMIT 1) o ON true
             LEFT JOIN LATERAL ( SELECT a.nome,
                    a.inicio,
                    a.canal
                   FROM fin.acoes a
                  WHERE a.produto = ev.origem AND a.sck_regex IS NOT NULL AND ev.origem_sck ~* a.sck_regex
                  ORDER BY a.prioridade, a.id
                 LIMIT 1) s ON true
             LEFT JOIN LATERAL ( SELECT a.nome,
                    a.inicio,
                    a.canal,
                    a.turma
                   FROM fin.acoes a
                  WHERE a.produto = ev.origem AND a.inicio IS NOT NULL AND a.fim IS NOT NULL AND ev.quando >= a.inicio AND ev.quando < a.fim
                  ORDER BY a.prioridade, a.id
                 LIMIT 1) j ON true
             LEFT JOIN LATERAL ( SELECT COALESCE(ae.nome, e.nome) AS nome,
                    (COALESCE(e.carrinho_inicio, e.inicio)::timestamp without time zone AT TIME ZONE 'America/Sao_Paulo'::text) AS inicio,
                    COALESCE(ae.canal,
                        CASE e.categoria
                            WHEN 'jornada'::text THEN 'Jornada'::text
                            WHEN 'holding_total'::text THEN 'Holding Total'::text
                            WHEN 'certificacao'::text THEN 'Holding Total'::text
                            WHEN 'live_hm'::text THEN 'Live Direto ao Ponto'::text
                            WHEN 'clinica'::text THEN 'Clínica'::text
                            WHEN 'imersao'::text THEN 'Imersão'::text
                            WHEN 'encontro_thb'::text THEN 'Encontro THB'::text
                            WHEN 'encontro_acelera'::text THEN 'Acelera Holding'::text
                            WHEN 'aurum_plus'::text THEN 'Aurum+'::text
                            WHEN 'congresso'::text THEN 'Congresso'::text
                            WHEN 'diamantes'::text THEN 'Diamantes'::text
                            WHEN 'residencia'::text THEN 'Residência'::text
                            WHEN 'workshop'::text THEN 'Residência'::text
                            WHEN 'lancamento_cnhf'::text THEN 'CNHF'::text
                            ELSE e.categoria
                        END) AS canal
                   FROM fin.eventos e
                     LEFT JOIN LATERAL ( SELECT a.nome,
                            a.canal
                           FROM fin.acoes a
                          WHERE a.evento_id = e.id AND a.produto = ev.origem
                          ORDER BY a.prioridade, a.id
                         LIMIT 1) ae ON true
                  WHERE e.setor = 'educacao'::text AND NOT (ev.origem = 'HM'::text AND (e.categoria = ANY (ARRAY['aurum_plus'::text, 'diamantes'::text]))) AND (e.venda_ate - COALESCE(e.carrinho_inicio, e.inicio)) <= 10 AND (ev.quando AT TIME ZONE 'America/Sao_Paulo'::text)::date >= COALESCE(e.carrinho_inicio, e.inicio) AND (ev.quando AT TIME ZONE 'America/Sao_Paulo'::text)::date <= e.venda_ate
                  ORDER BY (e.venda_ate - COALESCE(e.carrinho_inicio, e.inicio)), e.inicio DESC
                 LIMIT 1) d ON true
        ), saida AS (
         SELECT b.contato_hm_id,
                CASE
                    WHEN am.nome IS NOT NULL THEN am.nome
                    WHEN b.migrado THEN 'Migrados (HM R$ 15 mil antes de 25/06/2026)'::text
                    ELSE COALESCE(ra.o_nome, ra.s_nome, ra.d_nome,
                    CASE
                        WHEN b.comercial THEN 'Comercial (venda direta)'::text
                        ELSE NULL::text
                    END, ra.j_nome, 'Base (fora de evento)'::text)
                END AS acao_nome,
            COALESCE(am.inicio, ra.o_inicio, ra.s_inicio, ra.d_inicio,
                CASE
                    WHEN b.comercial THEN b.quando
                    ELSE NULL::timestamp with time zone
                END, ra.j_inicio, b.quando) AS acao_data,
                CASE
                    WHEN am.nome IS NOT NULL THEN 'ajuste manual: '::text || m.motivo
                    WHEN b.migrado THEN ('migrado: comprou o HM R$ 15 mil antes do Programa ('::text || COALESCE(ra.o_nome, ra.s_nome, ra.d_nome, ra.j_nome, 'fora de evento'::text)) || ')'::text
                    WHEN ra.o_nome IS NOT NULL THEN 'oferta do evento'::text
                    WHEN ra.s_nome IS NOT NULL THEN 'link de venda'::text
                    WHEN ra.d_nome IS NOT NULL AND b.aprovado_em IS NULL THEN 'data de entrada no board (dia do evento)'::text
                    WHEN ra.d_nome IS NOT NULL THEN 'dia do evento'::text
                    WHEN b.comercial THEN 'link do comercial'::text
                    WHEN ra.j_nome IS NOT NULL AND b.aprovado_em IS NULL THEN 'data de entrada no board'::text
                    WHEN ra.j_nome IS NOT NULL THEN 'depois do evento (turma)'::text
                    WHEN b.aprovado_em IS NULL THEN 'sem compra paga'::text
                    ELSE 'fora de evento'::text
                END AS acao_regra,
            COALESCE(am.canal, ra.o_canal, ra.s_canal, ra.d_canal,
                CASE
                    WHEN b.comercial THEN 'Comercial'::text
                    ELSE NULL::text
                END, ra.j_canal, 'Base (fora de evento)'::text) AS acao_canal,
            b.dia_aprovado AS captado_em,
            b.origem_sck AS captado_sck,
                CASE
                    WHEN rr.contato_hm_id IS NOT NULL THEN COALESCE(rr.o_nome, rr.s_nome, rr.d_nome,
                    CASE
                        WHEN rr.comercial THEN 'Comercial (venda direta)'::text
                        ELSE NULL::text
                    END, rr.j_nome, 'Base (fora de evento)'::text)
                    ELSE NULL::text
                END AS r_nome,
            COALESCE(rr.o_inicio, rr.s_inicio, rr.d_inicio,
                CASE
                    WHEN rr.comercial THEN rr.quando
                    ELSE NULL::timestamp with time zone
                END, rr.j_inicio, rr.quando) AS r_data,
                CASE
                    WHEN rr.contato_hm_id IS NULL THEN NULL::text
                    WHEN rr.o_nome IS NOT NULL THEN 'oferta do evento'::text
                    WHEN rr.s_nome IS NOT NULL THEN 'link de venda'::text
                    WHEN rr.d_nome IS NOT NULL THEN 'dia do evento'::text
                    WHEN rr.comercial THEN 'link do comercial'::text
                    WHEN rr.j_nome IS NOT NULL THEN 'depois do evento (turma)'::text
                    ELSE 'fora de evento'::text
                END AS r_regra,
            rr.transacao AS r_transacao
           FROM base b
             LEFT JOIN fin.acao_card_manual m ON m.contato_hm_id = b.contato_hm_id
             LEFT JOIN fin.acoes am ON am.id = m.acao_id
             LEFT JOIN regra ra ON ra.contato_hm_id = b.contato_hm_id AND ra.papel = 'entrada'::text
             LEFT JOIN regra rr ON rr.contato_hm_id = b.contato_hm_id AND rr.papel = 'retorno'::text
        )
 SELECT o.contato_hm_id,
    o.acao_nome,
    o.acao_data,
    o.acao_regra,
    o.acao_canal,
    o.captado_em,
    o.captado_sck,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_nome
            ELSE NULL::text
        END AS voltou_nome,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_data
            ELSE NULL::timestamp with time zone
        END AS voltou_data,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_regra
            ELSE NULL::text
        END AS voltou_regra,
        CASE
            WHEN o.r_nome IS DISTINCT FROM o.acao_nome THEN o.r_transacao
            ELSE NULL::text
        END AS voltou_transacao
   FROM saida o;

-- create or replace preserva o ACL; reafirma o padrão (view só via funções definer).
revoke all on fin.vw_acao_card from public, anon, authenticated;


-- ─── Conferência (orquestrador; NÃO faz parte da aplicação) ──────────────────────────────────
-- ANTES de aplicar:  create table z79_antes as select * from fin.vw_acao_card;   (numa sessão; ou temp)
-- DEPOIS:
-- C1) quantos cards mudaram e para onde:
--   select a.acao_regra de, d.acao_regra para, a.acao_nome de_nome, d.acao_nome para_nome, count(*)
--     from z79_antes a join fin.vw_acao_card d using (contato_hm_id)
--    where (a.acao_nome, a.acao_regra, a.voltou_nome) is distinct from (d.acao_nome, d.acao_regra, d.voltou_nome)
--    group by 1,2,3,4 order by 5 desc;
-- C2) as vendas das 3 ofertas: evento e regra na trajetória (como admin: set_config request.jwt.claims, ver z67 §1)
--   select distinct t.email from fin.vw_transacoes t where t.oferta_codigo in ('506c1lz1','3kojl3fv','mhfkfbdi');
--   select dia, oferta, papel, evento, regra_evento from public.fn_fin_trajetoria('<email>')
--    where oferta in ('506c1lz1','3kojl3fv','mhfkfbdi');   -- esperado: 2º Encontro Acelera Holding · oferta do evento · programa
-- C3) clínicas não regrediram: para 1 comprador de cada oferta de clínica da z4, papel continua 'ingresso'.
-- E1) explain (analyze, buffers) select * from fin.vw_acao_card;   -- colar; meta <= ~145 ms
-- E2) begin; select set_config('request.jwt.claims', '{"sub":"<admin>","role":"authenticated"}', true);
--     explain (analyze) select * from public.fn_fin_trajetoria('<email>'); rollback;
-- (Nenhum UPDATE/DELETE com explain analyze aqui: executaria.)
