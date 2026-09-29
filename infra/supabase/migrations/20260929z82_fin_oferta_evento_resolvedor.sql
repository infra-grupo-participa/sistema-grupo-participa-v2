-- 20260929z82 — Oferta nova de evento se liga SOZINHA ao evento (resolvedor + fila de exceção)
--
-- Por quê (Marcio, 29/09, vinculante): o sistema tem que ficar independente de ação humana; venda de evento vai
-- sozinha para o funil certo, sem marcação manual por pessoa. Desde a z79, fin.evento_ofertas é a regra de maior
-- prioridade em fin.vw_acao_card e public.fn_fin_trajetoria ("oferta do evento"), mas só era preenchida à mão.
-- Medido 29/09 (120 dias, vendas pagas não recorrentes): 83 ofertas sem evento (2.057 vendas); 33 com a 1ª venda na
-- janela [carrinho_inicio-2, venda_ate] de exatamente 1 evento; 33 de vários; 17 de nenhum; 5 vendem por >60 dias
-- (505 vendas, perenes: nunca ligar); 42 com >=80% das vendas com sck.
--
-- O que muda:
--   (a) fin.evento_ofertas ganha origem ('manual' | 'auto:sck' | 'auto:janela' | 'auto:nome' | 'confirmado'),
--       sinais (jsonb) e criado_em. Linhas existentes = 'manual' (criado_em fica NULL = "antes da z82").
--   (b) fin.oferta_evento_fila: exceções que o resolvedor não decide sozinho (RLS on, sem grant).
--   (c) fin.resolver_ofertas_eventos(p_gravar, p_dias, p_ofertas): decide por oferta, na ordem
--       perene (veto) > sck > nome > janela > fila > ignorar. p_gravar=false só devolve (simulação).
--       Liga com "on conflict do nothing": NUNCA sobrescreve ligação existente.
--   (d) RPCs da tela (quem vê o financeiro confirma — decisão do Marcio): public.fn_fin_fila_ofertas() e
--       public.fn_fin_decidir_oferta(...).
--   (e) SEM cron e SEM backfill aqui (passo seguinte, depois da medição).
--
-- Guardas (falham ANTES de gravar): colunas vivas de fin.hotmart_transacoes, fin.eventos, fin.acoes, fin.produtos,
-- fin.evento_produtos, fin.evento_ofertas; índice ÚNICO vivo em fin.evento_ofertas(oferta_codigo) (sem ele o
-- "on conflict do nothing" deixaria uma oferta em 2 eventos); CHECKs vivos de fin.eventos (pg_get_constraintdef) só
-- em setor e aceitando 'educacao'; nenhuma coluna NOT NULL sem default em fin.eventos fora das que a RPC preenche;
-- sck_regex de fin.acoes compilam; fin.ofertas, se existir, tem oferta_codigo/nome/is_main_offer; nenhuma
-- sobrecarga viva das 3 funções com outra assinatura; fin.oferta_evento_fila, se já existir, tem o formato daqui.
--
-- Escala:
--   * Resolvedor (1x/dia quando agendado): candidatas = ofertas com venda nos últimos p_dias via índice
--     hotmart_transacoes_pedido_idx (pedido_em). Histórico das candidatas = UMA passada em fin.hotmart_transacoes
--     (hash join com unnest(v_cod)), não uma por oferta. Custo por execução ~ O(tabela) 1x/dia + O(vendas das
--     candidatas x ~150 eventos). SEM índice novo em oferta_codigo: o único leitor por oferta_codigo desta
--     migration é esse job diário; uma Seq Scan/dia não justifica índice escrito a cada venda sincronizada.
--     Critério para criar (outra migration): explain do resolvedor > 200 ms, ou tabela > ~500 mil linhas.
--   * Tela: fn_fin_fila_ofertas lê só fin.oferta_evento_fila (dezenas de linhas, limit 50) + fin.eventos por PK.
--     Não toca fin.hotmart_transacoes. fn_fin_decidir_oferta: 1 linha por PK/índice único.
--   * fin.evento_ofertas: ~14 linhas hoje; ganha dezenas/mês. Os leitores (view/trajetória) já usam o índice único.
--
-- 5 perguntas (PROTOCOLO-SUSTENTABILIDADE):
--   1. Escala: custo por oferta nova (dezenas/execução), não por base; a única varredura de base é 1x/dia no job.
--      Tela com limit 50. 10x mais transações = 10x a Seq Scan diária (~ms a dezenas de ms), sem efeito na tela.
--   2. Índice: candidatas por hotmart_transacoes_pedido_idx (pedido_em >= v_desde, coluna crua, sem função).
--      evento_ofertas por evento_ofertas_oferta_uq (oferta_codigo cru). Fila por PK. Nenhuma expressão funcional.
--      Histórico por oferta_codigo: Seq Scan consciente (ver Escala). Orquestrador cola o explain.
--   3. Frequência: resolvedor 1x/dia (cron fica para o passo seguinte; o dado muda na sincronização da Hotmart).
--      Tela: 1 chamada ao abrir a fila; decidir: 1 por clique.
--   4. Repetição: a tela chama 1 RPC que já devolve nome da oferta, sugestão e proposta; nada filtrado no cliente.
--   5. Reversão (numa transação; nada é apagado de dado humano):
--        delete from fin.evento_ofertas where origem like 'auto:%';          -- só o que o robô ligou
--        drop function if exists public.fn_fin_decidir_oferta(text, bigint, jsonb, boolean);
--        drop function if exists public.fn_fin_fila_ofertas();
--        drop function if exists fin.resolver_ofertas_eventos(boolean, integer, text[]);
--        alter table fin.oferta_evento_fila rename to oferta_evento_fila_arquivada_z82;   -- arquivar, não apagar
--        (colunas origem/sinais/criado_em de fin.evento_ofertas podem ficar: nenhum leitor antigo as usa.)
--        Ligações 'confirmado' e eventos com fonte = 'confirmado na fila' são decisão humana: revisar, não apagar.
--      Desligar sem deploy: não agendar / cron.unschedule do job (passo seguinte) — o resolvedor só grava com
--      p_gravar = true.

-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v    text;
  v_r  record;
begin
  -- 0.1 colunas vivas das tabelas lidas
  select string_agg(x.col, ', ') into v
    from (values
      ('hotmart_transacoes','transacao'), ('hotmart_transacoes','produto_id'), ('hotmart_transacoes','produto_nome'),
      ('hotmart_transacoes','oferta_codigo'), ('hotmart_transacoes','status'), ('hotmart_transacoes','recorrencia'),
      ('hotmart_transacoes','pedido_em'), ('hotmart_transacoes','aprovado_em'), ('hotmart_transacoes','origem_sck'),
      ('eventos','id'), ('eventos','nome'), ('eventos','categoria'), ('eventos','setor'), ('eventos','inicio'),
      ('eventos','fim'), ('eventos','venda_ate'), ('eventos','carrinho_inicio'), ('eventos','codigo'),
      ('eventos','fonte'), ('eventos','observacao'), ('eventos','automatico'),
      ('acoes','id'), ('acoes','evento_id'), ('acoes','sck_regex'),
      ('produtos','produto_id'), ('produtos','familia'),
      ('evento_produtos','categoria'), ('evento_produtos','produto_id'), ('evento_produtos','papel'),
      ('evento_ofertas','evento_id'), ('evento_ofertas','oferta_codigo'), ('evento_ofertas','observacao')
    ) c(tab, col0)
    cross join lateral (select c.tab || '.' || c.col0 col) x
   where not exists (select 1 from information_schema.columns i
                      where i.table_schema = 'fin' and i.table_name = c.tab and i.column_name = c.col0);
  if v is not null then
    raise exception 'z82: colunas esperadas ausentes no vivo: %', v;
  end if;

  -- 0.2 índice ÚNICO só em oferta_codigo (garante 1 evento por oferta; o "on conflict do nothing" depende dele)
  if not exists (
    select 1 from pg_index i
     where i.indrelid = 'fin.evento_ofertas'::regclass and i.indisunique and i.indnatts = 1
       and i.indpred is null and i.indexprs is null
       and (select a.attname from pg_attribute a where a.attrelid = i.indrelid and a.attnum = i.indkey[0]) = 'oferta_codigo') then
    raise exception 'z82: fin.evento_ofertas sem índice único em (oferta_codigo) — ligação automática poderia duplicar oferta';
  end if;

  -- 0.3 CHECKs vivos de fin.eventos: só o de setor, aceitando 'educacao' (a RPC cria evento setor educacao)
  select string_agg(c.conname || ': ' || pg_get_constraintdef(c.oid), ' | ') into v
    from pg_constraint c
   where c.conrelid = 'fin.eventos'::regclass and c.contype = 'c'
     and (pg_get_constraintdef(c.oid) not ilike '%setor%' or pg_get_constraintdef(c.oid) not ilike '%''educacao''%');
  if v is not null then
    raise exception 'z82: fin.eventos tem CHECK além de setor/educacao — rever antes: %', v;
  end if;

  -- 0.4 fin.eventos: nenhuma coluna NOT NULL sem default fora das que fn_fin_decidir_oferta preenche
  select string_agg(a.attname, ', ') into v
    from pg_attribute a
   where a.attrelid = 'fin.eventos'::regclass and a.attnum > 0 and not a.attisdropped
     and a.attnotnull and not a.atthasdef and a.attidentity = ''
     and a.attname not in ('nome','categoria','setor','inicio','fim','venda_ate');
  if v is not null then
    raise exception 'z82: fin.eventos tem NOT NULL sem default não coberto pela RPC: %', v;
  end if;

  -- 0.5 unique (categoria, inicio) vivo (a RPC usa on conflict (categoria, inicio))
  if not exists (
    select 1 from pg_index i
     where i.indrelid = 'fin.eventos'::regclass and i.indisunique and i.indnatts = 2 and i.indpred is null
       and (select array_agg(a.attname::text order by a.attname) from pg_attribute a
             where a.attrelid = i.indrelid and a.attnum = any(i.indkey)) = array['categoria','inicio']) then
    raise exception 'z82: fin.eventos sem unique (categoria, inicio)';
  end if;

  -- 0.6 sck_regex vivos compilam (um regex inválido derrubaria o resolvedor inteiro)
  for v_r in select a.id, a.sck_regex from fin.acoes a where a.evento_id is not null and a.sck_regex is not null loop
    begin
      perform 'x' ~* v_r.sck_regex;
    exception when others then
      raise exception 'z82: fin.acoes % tem sck_regex inválido: %', v_r.id, v_r.sck_regex;
    end;
  end loop;

  -- 0.7 fin.ofertas (z81, outro executor): se existir, tem as colunas usadas; se não existir, o resolvedor segue sem ela
  if to_regclass('fin.ofertas') is not null then
    select string_agg(c.col, ', ') into v
      from (values ('oferta_codigo'), ('nome'), ('is_main_offer')) c(col)
     where not exists (select 1 from information_schema.columns i
                        where i.table_schema = 'fin' and i.table_name = 'ofertas' and i.column_name = c.col);
    if v is not null then
      raise exception 'z82: fin.ofertas existe sem as colunas: %', v;
    end if;
  end if;

  -- 0.8 sobrecarga: nenhuma versão viva das 3 funções com outra assinatura (create or replace criaria a 2ª)
  select string_agg(n.nspname || '.' || p.proname || '(' || oidvectortypes(p.proargtypes) || ')', ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where (n.nspname = 'fin' and p.proname = 'resolver_ofertas_eventos' and oidvectortypes(p.proargtypes) <> 'boolean, integer, text[]')
      or (n.nspname = 'public' and p.proname = 'fn_fin_fila_ofertas' and oidvectortypes(p.proargtypes) <> '')
      or (n.nspname = 'public' and p.proname = 'fn_fin_decidir_oferta' and oidvectortypes(p.proargtypes) <> 'text, bigint, jsonb, boolean');
  if v is not null then
    raise exception 'z82: já existe função com outra assinatura (drop antes): %', v;
  end if;

  -- 0.9 fila: se já existir, tem que ser esta
  if to_regclass('fin.oferta_evento_fila') is not null then
    select string_agg(a.attname, ',' order by a.attnum) into v
      from pg_attribute a where a.attrelid = 'fin.oferta_evento_fila'::regclass and a.attnum > 0 and not a.attisdropped;
    if v <> 'oferta_codigo,produto_id,sugestao_evento_id,proposta_evento,sinais,n_vendas,status,decidido_por,decidido_em,criado_em' then
      raise exception 'z82: fin.oferta_evento_fila já existe com outro formato: %', v;
    end if;
  end if;

  -- 0.10 evento_ofertas.origem/sinais/criado_em: se já existirem, com o tipo daqui
  select string_agg(i.column_name || ' ' || i.data_type, ', ') into v
    from information_schema.columns i
   where i.table_schema = 'fin' and i.table_name = 'evento_ofertas'
     and ((i.column_name = 'origem' and i.data_type <> 'text')
       or (i.column_name = 'sinais' and i.data_type <> 'jsonb')
       or (i.column_name = 'criado_em' and i.data_type <> 'timestamp with time zone'));
  if v is not null then
    raise exception 'z82: fin.evento_ofertas já tem coluna com outro tipo: %', v;
  end if;

  if to_regprocedure('public.gp_pode_ver_financeiro()') is null then
    raise exception 'z82: public.gp_pode_ver_financeiro() não existe';
  end if;
end $guarda$;


-- ─── 1. fin.evento_ofertas: origem, sinais, criado_em ───────────────────────────────────────
alter table fin.evento_ofertas
  add column if not exists origem text not null default 'manual',
  add column if not exists sinais jsonb,
  add column if not exists criado_em timestamptz;           -- existentes ficam NULL (= antes da z82)
alter table fin.evento_ofertas alter column criado_em set default now();

do $ck$
begin
  if not exists (select 1 from pg_constraint c
                  where c.conrelid = 'fin.evento_ofertas'::regclass and c.conname = 'evento_ofertas_origem_ck') then
    alter table fin.evento_ofertas add constraint evento_ofertas_origem_ck
      check (origem in ('manual','auto:sck','auto:janela','auto:nome','confirmado'));
  end if;
end $ck$;


-- ─── 2. fin.oferta_evento_fila ──────────────────────────────────────────────────────────────
create table if not exists fin.oferta_evento_fila (
  oferta_codigo      text not null,
  produto_id         text,
  sugestao_evento_id bigint references fin.eventos(id) on delete set null,
  proposta_evento    jsonb,
  sinais             jsonb,
  n_vendas           int,
  status             text not null default 'pendente',
  decidido_por       uuid,
  decidido_em        timestamptz,
  criado_em          timestamptz not null default now(),
  constraint oferta_evento_fila_pkey primary key (oferta_codigo),
  constraint oferta_evento_fila_status_ck check (status in ('pendente','confirmada','rejeitada'))
);
alter table fin.oferta_evento_fila enable row level security;
revoke all on fin.oferta_evento_fila from public, anon, authenticated;


-- ─── 3. Resolvedor ──────────────────────────────────────────────────────────────────────────
-- Decisão por oferta (ordem):
--   perene (veto): vendas espalhadas > 60 dias, OU vendas em 2 janelas de eventos educação que não se sobrepõem
--                  (cada uma com >= max(1, 10% das vendas)), OU fin.ofertas.is_main_offer = true -> não liga, não vai à fila.
--   auto:sck   : >= 3 vendas e >= 80% delas com sck que casa fin.acoes.sck_regex de ações de UM só evento.
--   auto:nome  : (fin.ofertas) nome da oferta contém o código (>= 3 caracteres) ou o nome de UM evento cuja janela
--                [carrinho_inicio-2, venda_ate] contém a 1ª venda.
--   auto:janela: 1ª venda na janela [carrinho_inicio-2, venda_ate] de exatamente UM evento educação E >= 90% das
--                vendas em [carrinho_inicio-2, venda_ate+7]. (HM nunca cai em aurum_plus/diamantes, igual à view.)
--   fila       : >= 2 vendas e nenhum sinal acima. evento_id devolvido = sugestão (pode ser null);
--                proposta_evento quando nenhum evento educação cobre a 1ª venda.
--   ignorar    : 1 venda sem sinal (a regra de data da view/trajetória continua valendo).
-- Vendas consideradas: não recorrentes (recorrencia <= 1), grupos pago/em_aberto/atrasado/estornado (todo pedido
-- real conta como evidência de QUANDO a oferta vendeu). Candidata = teve pago/em aberto nos últimos p_dias.
-- p_ofertas: só conferência — avalia exatamente essas ofertas ignorando evento_ofertas/fila/p_dias; exige p_gravar=false.
create or replace function fin.resolver_ofertas_eventos(
  p_gravar  boolean default false,
  p_dias    integer default 45,
  p_ofertas text[]  default null)
returns table (oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_desde timestamptz := now() - make_interval(days => greatest(coalesce(p_dias, 45), 1));
  v_cod   text[];
  v_of    jsonb := '{}'::jsonb;
  v_tem_ofertas boolean := to_regclass('fin.ofertas') is not null;
  v_res   jsonb;
begin
  if p_ofertas is not null and coalesce(p_gravar, false) then
    raise exception 'p_ofertas é só para conferência: use p_gravar = false.' using errcode = '22023';
  end if;

  -- 1. candidatas
  if p_ofertas is not null then
    select coalesce(array_agg(distinct c.oc), '{}') into v_cod
      from unnest(p_ofertas) c(oc) where c.oc is not null;
  else
    select coalesce(array_agg(distinct t.oferta_codigo), '{}') into v_cod
      from fin.hotmart_transacoes t
     where t.pedido_em >= v_desde
       and t.oferta_codigo is not null
       and t.status in ('APPROVED','COMPLETE','PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED')
       and coalesce(t.recorrencia, 1) <= 1
       and not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = t.oferta_codigo)
       and not exists (select 1 from fin.oferta_evento_fila f
                        where f.oferta_codigo = t.oferta_codigo and f.status in ('confirmada','rejeitada'));
  end if;
  if cardinality(v_cod) = 0 then
    return;
  end if;

  -- 2. nome/main offer (fin.ofertas pode não existir: SQL dinâmico)
  if v_tem_ofertas then
    execute 'select coalesce(jsonb_object_agg(o.oferta_codigo, jsonb_build_object(''nome'', o.nome, ''main'', o.is_main_offer)), ''{}''::jsonb)
               from fin.ofertas o where o.oferta_codigo = any($1)'
       into v_of using v_cod;
  end if;

  -- 3. decisão
  with tx as (
    select t.transacao tr, t.oferta_codigo oc, t.produto_id, t.produto_nome, t.origem_sck sck,
           (coalesce(t.aprovado_em, t.pedido_em) at time zone 'America/Sao_Paulo')::date d,
           t.status in ('APPROVED','COMPLETE') pago,
           coalesce(p.familia, 'OUTRO') familia
      from unnest(v_cod) c(oc)
      join fin.hotmart_transacoes t on t.oferta_codigo = c.oc
      left join fin.produtos p on p.produto_id = t.produto_id
     where t.status in ('APPROVED','COMPLETE','PRINTED_BILLET','WAITING_PAYMENT','UNDER_ANALISYS','STARTED',
                        'OVERDUE','PROTESTED','REFUNDED','PARTIALLY_REFUNDED','CHARGEBACK')
       and coalesce(t.recorrencia, 1) <= 1
       and coalesce(t.aprovado_em, t.pedido_em) is not null
  ), ofr as (
    select x.oc, min(x.produto_id) produto_id, min(x.produto_nome) produto_nome, min(x.familia) familia,
           count(*)::int n, count(*) filter (where x.pago)::int n_pagas,
           count(*) filter (where coalesce(x.sck, '') <> '')::int n_com_sck,
           min(x.d) primeira, max(x.d) ultima,
           percentile_disc(0.9) within group (order by x.d) p90
      from tx x
     group by x.oc
  ), ev as (
    select e.id, e.nome, e.categoria, e.setor, e.codigo,
           coalesce(e.carrinho_inicio, e.inicio) - 2 ja_de, e.venda_ate ja_ate
      from fin.eventos e
  ), sv as (              -- por venda: o evento das ações cujo sck_regex casa (só se for UM evento)
    select x.oc, x.tr, min(a.evento_id) ev_id
      from tx x
      join fin.acoes a on a.evento_id is not null and a.sck_regex is not null and x.sck ~* a.sck_regex
     group by x.oc, x.tr
    having count(distinct a.evento_id) = 1
  ), sck as (
    select distinct on (s.oc) s.oc, s.ev_id, count(*)::int n_sck
      from sv s
     group by s.oc, s.ev_id
     order by s.oc, count(*) desc, s.ev_id
  ), pw as (              -- eventos educação cuja janela contém vendas da oferta
    select x.oc, e.id, e.ja_de, e.ja_ate, count(*)::int n
      from tx x
      join ev e on e.setor = 'educacao' and x.d between e.ja_de and e.ja_ate
               and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
     group by x.oc, e.id, e.ja_de, e.ja_ate
  ), pd as (              -- perene: vendas relevantes em 2 janelas que não se sobrepõem
    select distinct a.oc
      from pw a
      join pw b on b.oc = a.oc and a.ja_ate < b.ja_de
      join ofr o on o.oc = a.oc
     where a.n >= greatest(1, ceil(o.n * 0.1)) and b.n >= greatest(1, ceil(o.n * 0.1))
  ), jw as (              -- eventos educação cuja janela contém a 1ª venda
    select o.oc, e.id, e.nome, e.ja_de, e.ja_ate,
           count(*) filter (where x.d between e.ja_de and e.ja_ate + 7)::int n_dentro
      from ofr o
      join ev e on e.setor = 'educacao' and o.primeira between e.ja_de and e.ja_ate
               and not (o.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
      join tx x on x.oc = o.oc
     group by o.oc, e.id, e.nome, e.ja_de, e.ja_ate
  ), jwa as (
    select j.oc, count(*)::int n_ev, min(j.id) id, min(j.n_dentro) n_dentro,
           (array_agg(j.id order by (j.ja_ate - j.ja_de), j.id))[1] melhor,
           jsonb_agg(jsonb_build_object('evento_id', j.id, 'nome', j.nome, 'de', j.ja_de, 'ate', j.ja_ate,
                                        'vendas_dentro', j.n_dentro) order by (j.ja_ate - j.ja_de), j.id) cands
      from jw j
     group by j.oc
  ), nm as (              -- nome da oferta contém código/nome de evento cuja janela contém a 1ª venda
    select o.oc, count(*)::int n_ev, min(e.id) id,
           jsonb_agg(jsonb_build_object('evento_id', e.id, 'nome', e.nome) order by e.id) cands
      from ofr o
      cross join lateral (select ' ' || btrim(regexp_replace(lower(coalesce(v_of -> o.oc ->> 'nome', '')), '[^a-z0-9]+', ' ', 'g')) || ' ' nome_n) z
      join ev e on o.primeira between e.ja_de and e.ja_ate
      cross join lateral (select btrim(regexp_replace(lower(coalesce(e.codigo, '')), '[^a-z0-9]+', ' ', 'g')) cod_n,
                                 btrim(regexp_replace(lower(e.nome), '[^a-z0-9]+', ' ', 'g')) evn_n) w
     where length(z.nome_n) > 2
       and ((length(w.cod_n) >= 3 and position(' ' || w.cod_n || ' ' in z.nome_n) > 0)
         or (length(w.evn_n) >= 8 and position(' ' || w.evn_n || ' ' in z.nome_n) > 0))
     group by o.oc
  ), dec as (
    select o.*, s.ev_id sck_ev, coalesce(s.n_sck, 0) n_sck,
           j.n_ev j_n, j.id j_id, j.n_dentro j_dentro, j.melhor j_melhor, j.cands j_cands,
           m.n_ev nm_n, m.id nm_id, m.cands nm_cands,
           v_of -> o.oc ->> 'nome' oferta_nome,
           coalesce((v_of -> o.oc ->> 'main')::boolean, false) main,
           (o.ultima - o.primeira) > 60 espalhada,
           (pd.oc is not null) duas_janelas
      from ofr o
      left join sck s on s.oc = o.oc
      left join jwa j on j.oc = o.oc
      left join nm m on m.oc = o.oc
      left join pd on pd.oc = o.oc
  ), res as (
    select d.*,
           case when d.main or d.espalhada or d.duas_janelas then 'perene'
                when d.n >= 3 and d.sck_ev is not null and d.n_sck >= 0.8 * d.n then 'ligar'
                when d.nm_n = 1 then 'ligar'
                when d.j_n = 1 and d.j_dentro >= 0.9 * d.n then 'ligar'
                when d.n >= 2 then 'fila'
                else 'ignorar' end dcs,
           case when d.main or d.espalhada or d.duas_janelas then
                  'perene:' || concat_ws('+', case when d.main then 'main_offer' end,
                                              case when d.espalhada then 'mais_de_60_dias' end,
                                              case when d.duas_janelas then 'duas_janelas' end)
                when d.n >= 3 and d.sck_ev is not null and d.n_sck >= 0.8 * d.n then 'auto:sck'
                when d.nm_n = 1 then 'auto:nome'
                when d.j_n = 1 and d.j_dentro >= 0.9 * d.n then 'auto:janela'
                when d.n >= 2 then case when d.j_n is null then 'fila:sem_evento'
                                        when d.j_n > 1 then 'fila:varios_eventos'
                                        else 'fila:sinal_fraco' end
                else 'sem_sinal' end sn,
           coalesce(case when d.j_n = 1 then d.j_id end, d.sck_ev, d.j_melhor) sug
      from dec d
  )
  select jsonb_agg(jsonb_build_object(
           'oferta_codigo', r.oc,
           'decisao', r.dcs,
           'sinal', r.sn,
           'evento_id', case r.sn when 'auto:sck' then r.sck_ev when 'auto:nome' then r.nm_id
                                  when 'auto:janela' then r.j_id else case when r.dcs = 'fila' then r.sug end end,
           'detalhe', jsonb_build_object(
              'produto_id', r.produto_id, 'produto_nome', r.produto_nome, 'oferta_nome', r.oferta_nome,
              'n_vendas', r.n, 'n_pagas', r.n_pagas, 'n_com_sck', r.n_com_sck,
              'primeira_venda', r.primeira, 'ultima_venda', r.ultima, 'p90_venda', r.p90,
              'sck', jsonb_build_object('evento_id', r.sck_ev, 'vendas', r.n_sck),
              'janela', jsonb_build_object('n_eventos', coalesce(r.j_n, 0), 'candidatos', r.j_cands),
              'nome', jsonb_build_object('n_eventos', coalesce(r.nm_n, 0), 'candidatos', r.nm_cands,
                                         'fonte', case when v_tem_ofertas then 'fin.ofertas' else 'fin.ofertas ausente' end),
              'perene', jsonb_build_object('main_offer', r.main, 'mais_de_60_dias', r.espalhada, 'duas_janelas', r.duas_janelas),
              'sugestao_evento_id', case when r.dcs = 'fila' then r.sug end,
              'proposta_evento', case when r.dcs = 'fila' and r.j_n is null then jsonb_build_object(
                  'nome', coalesce(r.oferta_nome, r.produto_nome),
                  'categoria', (select ep.categoria from fin.evento_produtos ep
                                 where ep.produto_id = r.produto_id
                                 order by (ep.papel = 'ingresso') desc, ep.categoria limit 1),
                  'carrinho_inicio', r.primeira,
                  'venda_ate', r.p90) end,
              'calculado_em', now())))
    into v_res
    from res r;

  if v_res is null then
    return;
  end if;

  -- 4. gravação (só com p_gravar): nunca sobrescreve ligação; fila só atualiza o que ainda está pendente
  if coalesce(p_gravar, false) then
    insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao, origem, sinais, criado_em)
    select r.evento_id, r.oferta_codigo, 'ligada sozinha pelo resolvedor (' || r.sinal || ')', r.sinal, r.detalhe, now()
      from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
     where r.decisao = 'ligar' and r.evento_id is not null
    on conflict do nothing;

    insert into fin.oferta_evento_fila as f (oferta_codigo, produto_id, sugestao_evento_id, proposta_evento, sinais, n_vendas)
    select r.oferta_codigo, r.detalhe ->> 'produto_id', r.evento_id, r.detalhe -> 'proposta_evento', r.detalhe,
           (r.detalhe ->> 'n_vendas')::int
      from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
     where r.decisao = 'fila'
    on conflict on constraint oferta_evento_fila_pkey do update
       set produto_id = excluded.produto_id,
           sugestao_evento_id = excluded.sugestao_evento_id,
           proposta_evento = excluded.proposta_evento,
           sinais = excluded.sinais,
           n_vendas = excluded.n_vendas
     where f.status = 'pendente';
  end if;

  return query
  select r.oferta_codigo, r.decisao, r.evento_id, r.sinal, r.detalhe
    from jsonb_to_recordset(v_res) r(oferta_codigo text, decisao text, evento_id bigint, sinal text, detalhe jsonb)
   order by r.decisao, r.oferta_codigo;
end
$$;
revoke all on function fin.resolver_ofertas_eventos(boolean, integer, text[]) from public, anon, authenticated;
grant execute on function fin.resolver_ofertas_eventos(boolean, integer, text[]) to service_role;


-- ─── 4. RPCs da tela ────────────────────────────────────────────────────────────────────────
-- 4a. Fila pendente (até 50), sem as ofertas que o resolvedor já ligou depois.
create or replace function public.fn_fin_fila_ofertas()
returns table (oferta_codigo text, oferta_nome text, produto_id text, produto_nome text, n_vendas int,
               primeira_venda date, ultima_venda date, sugestao_evento_id bigint, sugestao_evento text,
               proposta_evento jsonb, sinais jsonb, criado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_cod text[];
  v_of  jsonb := '{}'::jsonb;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;

  select coalesce(array_agg(q.oc order by q.ord), '{}') into v_cod
    from (select f.oferta_codigo oc,
                 row_number() over (order by f.n_vendas desc nulls last, f.criado_em, f.oferta_codigo) ord
            from fin.oferta_evento_fila f
           where f.status = 'pendente'
             and not exists (select 1 from fin.evento_ofertas eo where eo.oferta_codigo = f.oferta_codigo)
           order by f.n_vendas desc nulls last, f.criado_em, f.oferta_codigo
           limit 50) q;
  if cardinality(v_cod) = 0 then
    return;
  end if;

  if to_regclass('fin.ofertas') is not null then
    execute 'select coalesce(jsonb_object_agg(o.oferta_codigo, o.nome), ''{}''::jsonb)
               from fin.ofertas o where o.oferta_codigo = any($1) and o.nome is not null'
       into v_of using v_cod;
  end if;

  return query
  select f.oferta_codigo,
         coalesce(v_of ->> f.oferta_codigo, f.sinais ->> 'oferta_nome'),
         f.produto_id,
         f.sinais ->> 'produto_nome',
         f.n_vendas,
         (f.sinais ->> 'primeira_venda')::date,
         (f.sinais ->> 'ultima_venda')::date,
         f.sugestao_evento_id,
         e.nome,
         f.proposta_evento,
         f.sinais,
         f.criado_em
    from unnest(v_cod) with ordinality c(oc, ord)
    join fin.oferta_evento_fila f on f.oferta_codigo = c.oc
    left join fin.eventos e on e.id = f.sugestao_evento_id
   order by c.ord;
end
$$;
revoke all on function public.fn_fin_fila_ofertas() from public, anon;
grant execute on function public.fn_fin_fila_ofertas() to authenticated;

-- 4b. Decidir: exatamente UMA ação — p_evento_id (confirmar), p_criar (criar evento e ligar) ou p_rejeitar.
--     p_criar = {"nome", "categoria", "inicio", "fim"?, "venda_ate"?, "carrinho_inicio"?} (datas YYYY-MM-DD).
create or replace function public.fn_fin_decidir_oferta(
  p_oferta    text,
  p_evento_id bigint  default null,
  p_criar     jsonb   default null,
  p_rejeitar  boolean default false)
returns jsonb
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_of   text := nullif(btrim(p_oferta), '');
  v_f    fin.oferta_evento_fila%rowtype;
  v_ev   bigint;
  v_lig  bigint;
  v_nome text;
  v_cat  text;
  v_ini  date;
  v_fim  date;
  v_ate  date;
  v_car  date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) or v_uid is null then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_of is null then
    raise exception 'Informe a oferta.' using errcode = '22023';
  end if;
  if (p_evento_id is not null)::int + (p_criar is not null)::int + coalesce(p_rejeitar, false)::int <> 1 then
    raise exception 'Escolha uma ação: evento existente, criar evento ou rejeitar.' using errcode = '22023';
  end if;

  select * into v_f from fin.oferta_evento_fila f where f.oferta_codigo = v_of for update;
  if not found then
    raise exception 'A oferta % não está na fila.', v_of using errcode = 'P0002';
  end if;
  if v_f.status <> 'pendente' then
    raise exception 'A oferta % já foi decidida (%).', v_of, v_f.status using errcode = '55000';
  end if;
  select eo.evento_id into v_lig from fin.evento_ofertas eo where eo.oferta_codigo = v_of;
  if v_lig is not null then
    raise exception 'A oferta % já está ligada ao evento %.', v_of, v_lig using errcode = '23505';
  end if;

  if coalesce(p_rejeitar, false) then
    update fin.oferta_evento_fila f
       set status = 'rejeitada', decidido_por = v_uid, decidido_em = now()
     where f.oferta_codigo = v_of;
    return jsonb_build_object('oferta', v_of, 'status', 'rejeitada');
  end if;

  if p_criar is not null then
    v_nome := nullif(btrim(p_criar ->> 'nome'), '');
    v_cat  := nullif(lower(btrim(p_criar ->> 'categoria')), '');
    v_ini  := nullif(btrim(p_criar ->> 'inicio'), '')::date;
    v_fim  := coalesce(nullif(btrim(p_criar ->> 'fim'), '')::date, v_ini);
    v_ate  := coalesce(nullif(btrim(p_criar ->> 'venda_ate'), '')::date, v_fim);
    v_car  := nullif(btrim(p_criar ->> 'carrinho_inicio'), '')::date;
    if v_nome is null or length(v_nome) > 200 then
      raise exception 'Nome do evento obrigatório (até 200 caracteres).' using errcode = '22023';
    end if;
    if v_cat is null or v_cat !~ '^[a-z][a-z0-9_]{1,39}$' then
      raise exception 'Categoria inválida (minúsculas, números e _).' using errcode = '22023';
    end if;
    if v_ini is null or v_fim < v_ini or (v_car is not null and v_car > v_ate) then
      raise exception 'Datas do evento inválidas.' using errcode = '22023';
    end if;

    insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, fonte, observacao, automatico)
    values (v_nome, v_cat, 'educacao', v_ini, v_fim, v_ate, v_car, 'confirmado na fila',
            'criado na fila de ofertas a partir da oferta ' || v_of || ' por ' || v_uid::text, true)
    on conflict (categoria, inicio) do nothing
    returning id into v_ev;
    if v_ev is null then
      raise exception 'Já existe evento % começando em %: escolha-o na lista.', v_cat, v_ini using errcode = '23505';
    end if;
  else
    select e.id into v_ev from fin.eventos e where e.id = p_evento_id;
    if v_ev is null then
      raise exception 'Evento % não existe.', p_evento_id using errcode = 'P0002';
    end if;
  end if;

  -- sem on conflict: se alguém ligou a oferta no meio, o índice único falha e a transação desfaz tudo (inclusive o evento criado)
  insert into fin.evento_ofertas (evento_id, oferta_codigo, observacao, origem, sinais, criado_em)
  values (v_ev, v_of, 'confirmado na fila', 'confirmado',
          coalesce(v_f.sinais, '{}'::jsonb) || jsonb_build_object('decidido_por', v_uid, 'evento_criado', p_criar is not null),
          now());

  update fin.oferta_evento_fila f
     set status = 'confirmada', decidido_por = v_uid, decidido_em = now()
   where f.oferta_codigo = v_of;

  return jsonb_build_object('oferta', v_of, 'status', 'confirmada', 'evento_id', v_ev, 'evento_criado', p_criar is not null);
end
$$;
revoke all on function public.fn_fin_decidir_oferta(text, bigint, jsonb, boolean) from public, anon;
grant execute on function public.fn_fin_decidir_oferta(text, bigint, jsonb, boolean) to authenticated;


-- ─── 5. Conferência (falha a migration se algo ficou aberto ou foi alterado) ─────────────────
do $confere$
declare v text;
begin
  -- nenhuma ligação automática nesta migration; todas as existentes = manual
  if exists (select 1 from fin.evento_ofertas eo where eo.origem <> 'manual') then
    raise exception 'z82: fin.evento_ofertas tem origem <> manual logo após a migration';
  end if;

  -- grants: anon nunca; resolvedor só service_role/dono; tabela da fila fechada
  select string_agg(x.o, ', ') into v
    from (values
      ('anon exec resolver',  has_function_privilege('anon', 'fin.resolver_ofertas_eventos(boolean,integer,text[])', 'execute')),
      ('auth exec resolver',  has_function_privilege('authenticated', 'fin.resolver_ofertas_eventos(boolean,integer,text[])', 'execute')),
      ('anon exec fila',      has_function_privilege('anon', 'public.fn_fin_fila_ofertas()', 'execute')),
      ('anon exec decidir',   has_function_privilege('anon', 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'execute')),
      ('anon tab fila',       has_table_privilege('anon', 'fin.oferta_evento_fila', 'select,insert,update,delete')),
      ('auth tab fila',       has_table_privilege('authenticated', 'fin.oferta_evento_fila', 'select,insert,update,delete')),
      ('auth tab ev_ofertas', has_table_privilege('authenticated', 'fin.evento_ofertas', 'select,insert,update,delete'))
    ) x(o, aberto)
   where x.aberto;
  if v is not null then
    raise exception 'z82: permissão aberta: %', v;
  end if;
  if not has_function_privilege('authenticated', 'public.fn_fin_fila_ofertas()', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'execute') then
    raise exception 'z82: authenticated sem execute nas RPCs da tela';
  end if;

  -- atributos: security definer + search_path vazio nas 3
  select string_agg(p.oid::regprocedure::text, ', ') into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where ((n.nspname = 'fin' and p.proname = 'resolver_ofertas_eventos')
       or (n.nspname = 'public' and p.proname in ('fn_fin_fila_ofertas','fn_fin_decidir_oferta')))
     and (not p.prosecdef or coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%');
  if v is not null then
    raise exception 'z82: função sem security definer/search_path: %', v;
  end if;
end $confere$;


-- ─── Simulação e conferência (orquestrador; NÃO faz parte da aplicação) ─────────────────────
-- Tudo abaixo com p_gravar = false é só leitura (explain analyze seguro). NUNCA explain analyze com p_gravar = true.
-- S1) distribuição (45 dias, padrão do cron):
--   select decisao, sinal, count(*) ofertas, sum((detalhe->>'n_vendas')::int) vendas
--     from fin.resolver_ofertas_eventos(false) group by 1,2 order by 1,2;
-- S2) mesma coisa no horizonte do backfill (comparar com o medido: 33 janela única / 33 vários / 17 nenhum / 5 perenes):
--   select decisao, sinal, count(*) ofertas, sum((detalhe->>'n_vendas')::int) vendas
--     from fin.resolver_ofertas_eventos(false, 120) group by 1,2 order by 1,2;
-- S3) o que seria ligado, para olho humano (evento, nome, vendas, 1ª/última):
--   select r.oferta_codigo, r.sinal, r.evento_id, e.nome evento, r.detalhe->>'oferta_nome' oferta,
--          r.detalhe->>'n_vendas' n, r.detalhe->>'primeira_venda' de, r.detalhe->>'ultima_venda' ate
--     from fin.resolver_ofertas_eventos(false, 120) r left join fin.eventos e on e.id = r.evento_id
--    where r.decisao = 'ligar' order by r.sinal, e.nome;
-- S4) ligações de 1 venda só (risco: vale para as vendas futuras da oferta):
--   select count(*) from fin.resolver_ofertas_eventos(false, 120) where decisao = 'ligar' and (detalhe->>'n_vendas')::int = 1;
-- C1) contra a verdade conhecida (as ligações manuais, avaliadas como se não existissem; p_ofertas ignora exclusões):
--   with v as (select eo.oferta_codigo, eo.evento_id from fin.evento_ofertas eo where eo.origem = 'manual')
--   select r.decisao, r.sinal, count(*) total,
--          count(*) filter (where r.evento_id = v.evento_id) acerto,
--          count(*) filter (where r.decisao = 'ligar' and r.evento_id <> v.evento_id) erro_grave,
--          string_agg(r.oferta_codigo || '->' || coalesce(r.evento_id::text, '-') || ' (certo ' || v.evento_id || ')', ', ') ofertas
--     from fin.resolver_ofertas_eventos(false, 45, array(select oferta_codigo from fin.evento_ofertas where origem = 'manual')) r
--     join v on v.oferta_codigo = r.oferta_codigo
--    group by 1,2 order by 1,2;
--   Aceite: erro_grave = 0. Esperado: 2º Encontro (3 ofertas, janela 26–28/09 sobreposta à HT32) -> fila:varios_eventos
--   com sugestão; clínicas Rio/GO/POA -> auto:janela ou fila.
-- E1) explain (analyze, buffers) select * from fin.resolver_ofertas_eventos(false);        -- 2x (cache frio/quente)
-- E2) explain (analyze, buffers) select * from fin.resolver_ofertas_eventos(false, 120);
-- E3) begin; select set_config('request.jwt.claims', '{"sub":"<admin>","role":"authenticated"}', true);
--     explain (analyze) select * from public.fn_fin_fila_ofertas(); rollback;
-- E4) tamanho que decide o índice: select count(*), pg_size_pretty(pg_relation_size('fin.hotmart_transacoes')) from fin.hotmart_transacoes;
