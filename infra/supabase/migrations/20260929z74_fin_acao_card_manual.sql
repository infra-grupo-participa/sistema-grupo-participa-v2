-- 20260929z74 — Ação do card definida à mão (correção de funil)
--
-- Por quê: em 29/09 o Marcio pediu que quem comprou HM em 28–29/09 fosse para a
-- ação "2º Encontro Acelera Holding (28/09/2026)" (fin.acoes id 135). A regra
-- automática (link de venda > dia do evento > comercial > janela) põe essas
-- pessoas na Imersão HT32, porque o link usado foi o da Imersão. Não havia como
-- corrigir um card sem mexer na regra de todos.
--
-- O que faz: tabela fin.acao_card_manual (1 linha por card) que VENCE a regra
-- automática em fin.vw_acao_card. O motivo aparece em acao_regra.
-- Reversão: delete from fin.acao_card_manual where ...; (o card volta à regra).
-- Escala: dezenas de linhas, lida por PK via hash join sobre 384 cards.

create table if not exists fin.acao_card_manual (
  contato_hm_id uuid primary key references cs.contatos_hm(id) on delete cascade,
  acao_id       integer not null references fin.acoes(id),
  motivo        text not null check (length(btrim(motivo)) > 0),
  definido_por  text not null,
  definido_em   timestamptz not null default now()
);

alter table fin.acao_card_manual enable row level security;
revoke all on fin.acao_card_manual from public, anon, authenticated;

comment on table fin.acao_card_manual is
  'Ação do card definida à mão; vence a regra automática de fin.vw_acao_card. Apagar a linha devolve o card à regra.';

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
        ), primeira AS (
         SELECT DISTINCT ON (c.contato_hm_id) c.contato_hm_id,
            t.aprovado_em,
            t.dia_aprovado,
            t.origem_sck,
            t.migrado
           FROM card c
             JOIN emails e ON e.contato_hm_id = c.contato_hm_id
             JOIN LATERAL ( SELECT COALESCE(x.aprovado_em, x.pedido_em) AS aprovado_em,
                    COALESCE(x.dia_aprovado, x.dia_pedido) AS dia_aprovado,
                    x.origem_sck,
                    c.origem = 'HM'::text AND COALESCE(x.dia_aprovado, x.dia_pedido) < '2026-06-25'::date AS migrado,
                    cat.categoria,
                    x.grupo
                   FROM fin.vw_transacoes x
                     LEFT JOIN hm_product_catalog cat ON cat.offer_code = x.oferta_codigo
                  WHERE x.email = e.email AND x.familia = c.origem AND
                        CASE
                            WHEN c.origem = 'HM'::text THEN x.produto_id = '5064314'::text AND (COALESCE(cat.categoria, ''::text) <> ALL (ARRAY['renovacao'::text, 'reserva'::text])) AND (COALESCE(x.dia_aprovado, x.dia_pedido) >= '2026-06-25'::date OR x.grupo = 'pago'::text)
                            ELSE x.grupo = 'pago'::text
                        END) t ON true
          ORDER BY c.contato_hm_id, (COALESCE(c.origem = 'HM'::text AND NOT t.migrado, false)) DESC, (t.grupo = ANY (ARRAY['pago'::text, 'estornado'::text, 'em_aberto'::text, 'atrasado'::text])) DESC, (COALESCE(c.origem <> 'HM'::text AND (t.categoria = ANY (ARRAY['sinal'::text, 'compra_cheia'::text])), false)) DESC, (t.dia_aprovado >= '2026-01-01'::date) DESC, t.aprovado_em
        ), base AS (
         SELECT c.contato_hm_id,
            c.origem,
            c.email,
            c.entrada,
            p.aprovado_em,
            p.dia_aprovado,
            p.origem_sck,
            COALESCE(p.migrado, false) AS migrado,
            COALESCE(p.aprovado_em, c.entrada) AS quando,
            COALESCE(p.origem_sck ~~* '%comercial%'::text OR p.origem_sck ~~* '%jonathan%'::text, false) AS comercial
           FROM card c
             LEFT JOIN primeira p ON p.contato_hm_id = c.contato_hm_id
        )
 SELECT b.contato_hm_id,
        CASE
            WHEN am.nome IS NOT NULL THEN am.nome
            WHEN b.migrado THEN 'Migrados (HM R$ 15 mil antes de 25/06/2026)'::text
            ELSE COALESCE(s.nome, d.nome,
            CASE
                WHEN b.comercial THEN 'Comercial (venda direta)'::text
                ELSE NULL::text
            END, j.nome, 'Base (fora de evento)'::text)
        END AS acao_nome,
    COALESCE(am.inicio, s.inicio, d.inicio,
        CASE
            WHEN b.comercial THEN b.quando
            ELSE NULL::timestamp with time zone
        END, j.inicio, b.quando) AS acao_data,
        CASE
            WHEN am.nome IS NOT NULL THEN 'ajuste manual: '::text || m.motivo
            WHEN b.migrado THEN ('migrado: comprou o HM R$ 15 mil antes do Programa ('::text || COALESCE(s.nome, d.nome, j.nome, 'fora de evento'::text)) || ')'::text
            WHEN s.nome IS NOT NULL THEN 'link de venda'::text
            WHEN d.nome IS NOT NULL AND b.aprovado_em IS NULL THEN 'data de entrada no board (dia do evento)'::text
            WHEN d.nome IS NOT NULL THEN 'dia do evento'::text
            WHEN b.comercial THEN 'link do comercial'::text
            WHEN j.nome IS NOT NULL AND b.aprovado_em IS NULL THEN 'data de entrada no board'::text
            WHEN j.nome IS NOT NULL THEN 'depois do evento (turma)'::text
            WHEN b.aprovado_em IS NULL THEN 'sem compra paga'::text
            ELSE 'fora de evento'::text
        END AS acao_regra,
    COALESCE(am.canal, s.canal, d.canal,
        CASE
            WHEN b.comercial THEN 'Comercial'::text
            ELSE NULL::text
        END, j.canal, 'Base (fora de evento)'::text) AS acao_canal,
    b.dia_aprovado AS captado_em,
    b.origem_sck AS captado_sck
   FROM base b
     LEFT JOIN fin.acao_card_manual m ON m.contato_hm_id = b.contato_hm_id
     LEFT JOIN fin.acoes am ON am.id = m.acao_id
     LEFT JOIN LATERAL ( SELECT a.nome,
            a.inicio,
            a.canal
           FROM fin.acoes a
          WHERE a.produto = b.origem AND a.sck_regex IS NOT NULL AND b.origem_sck ~* a.sck_regex
          ORDER BY a.prioridade, a.id
         LIMIT 1) s ON true
     LEFT JOIN LATERAL ( SELECT a.nome,
            a.inicio,
            a.canal,
            a.turma
           FROM fin.acoes a
          WHERE a.produto = b.origem AND a.inicio IS NOT NULL AND a.fim IS NOT NULL AND b.quando >= a.inicio AND b.quando < a.fim
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
                  WHERE a.evento_id = e.id AND a.produto = b.origem
                  ORDER BY a.prioridade, a.id
                 LIMIT 1) ae ON true
          WHERE e.setor = 'educacao'::text AND NOT (b.origem = 'HM'::text AND (e.categoria = ANY (ARRAY['aurum_plus'::text, 'diamantes'::text]))) AND (e.venda_ate - COALESCE(e.carrinho_inicio, e.inicio)) <= 10 AND (b.quando AT TIME ZONE 'America/Sao_Paulo'::text)::date >= COALESCE(e.carrinho_inicio, e.inicio) AND (b.quando AT TIME ZONE 'America/Sao_Paulo'::text)::date <= e.venda_ate
          ORDER BY (e.venda_ate - COALESCE(e.carrinho_inicio, e.inicio)), e.inicio DESC
         LIMIT 1) d ON true;

-- Pedido do Marcio (29/09): quem comprou HM em 28/09 e 29/09 vai para o 2º Encontro.
-- Critério: card HM com transação do produto 5064314 (não parcela recorrente)
-- pedida ou aprovada desde 28/09 00:00 (Brasília). Parcelas de saldo antigo ficam onde estão.
insert into fin.acao_card_manual (contato_hm_id, acao_id, motivo, definido_por)
select distinct b.contato_hm_id, 135,
       'comprou em 28–29/09, funil do 2º Encontro Acelera (pedido do Marcio em 29/09)',
       'migration 20260929z74'
  from cs.vw_fin_board b
  join fin.vw_transacoes x on lower(trim(x.email)) = lower(trim(b.email))
 where b.origem = 'HM'
   and x.produto_id = '5064314'
   and coalesce(x.recorrencia, 1) = 1
   and greatest(x.pedido_em, coalesce(x.aprovado_em, x.pedido_em)) >= timestamptz '2026-09-28 00:00-03'
on conflict (contato_hm_id) do nothing;
