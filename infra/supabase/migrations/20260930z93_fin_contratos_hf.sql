-- 20260930z93 — Contratos Holding Familiar (HF, setor escritório / Soluções): FICHA do contrato + parcelas por etapa.
--
-- ESCRITA E ENSAIADA em 29/09/2026 (begin/rollback, ver 20260930z93.explain.md). NÃO APLICADA.
-- Depende de: z63 (informados), z73 (tipo contrato_holding_familiar, bloco 7), z84 (cron :25), z89/z90 (conta escritorio,
-- fin.vw_transacoes_escritorio). NÃO toca em fin.resolver_ofertas_eventos nem nos funis (z91/z92 de outro executor).
--
-- POR QUÊ (decisões do dono, 30/09)
--   Parte do pagamento do contrato HF cai na Hotmart (produto 5301413, conta escritorio: o sinal E, em vários contratos, parcelas); o resto vem por Pix, fora
--   de rastreio, e é baixado à mão. A z73 já trata cada PARCELA como recebimento informado (tipo contrato_holding_familiar,
--   bloco 7 da previsão). Faltava a FICHA do contrato (valor cheio lido do contrato, contato, link, assinatura) e a parcela
--   por ETAPA (contratos 2022–24: 30/30/40% dos 90%, na assinatura / minutas / registros), que fica SEM DATA — "a receber
--   na etapa X" — até alguém marcar a etapa como concluída.
--   · nome, e-mail, telefone e cidade ficam visíveis a quem vê o Financeiro (decisão do dono). Final do CPF: só gp_pode_ver_cpf().
--   · contrato de 2025 não tem sinal na Hotmart: "fecha" na 1ª parcela baixada (fechado_em = menor baixa).
--   · valor cheio vem do contrato lido (carga), nunca "sinal × 10".
--
-- O QUE FAZ
--   1) fin.contratos_hf — ficha. transacao_sinal UNIQUE e nula (contrato 2025 sem sinal). RLS ligado, sem policy, sem
--      grant; DELETE/TRUNCATE barrados por trigger; arquiva com motivo. Trilha só-acréscimo fin.contratos_hf_historico
--      (sem e-mail, telefone, final do CPF e observação — da observação fica só o md5; acao 'desfundir' com motivo).
--   2) fin.contratos_hf_sincronizar() — insert … on conflict do nothing: UMA ficha por comprador (e-mail) dos pagamentos HF PAGOS em
--      fin.vw_transacoes_escritorio (produto 5301413). Pendurada no cron que já existe (fin-oferta-evento-resolver, :25,
--      z84): o command ganha "select fin.contratos_hf_sincronizar();" NA FRENTE. Nenhum cron novo. A função nunca levanta
--      erro (WARNING + retorna -1): o resolvedor que vem depois no mesmo command não é derrubado por ela.
--      O texto do prefixo ("select fin.contratos_hf_sincronizar(); ") é o que a z91 espera no job 63 — não mudar.
--      CONCILIAÇÃO AUTOMÁTICA (dono: "tem que ser registrado automático"; baixa manual fica para o Pix), mesma função:
--        cada pagamento HF pago do comprador de uma ficha viva dá baixa na parcela em aberto do contrato quando o valor
--        bate (± R$ 1,00 ou 1%, o maior) e o vencimento está a ±45 dias (o mais próximo); parcela por etapa sem data
--        aceita o pagamento e tem a etapa concluída na data dele. recebimentos_informados.transacao_hotmart (unique)
--        guarda a transação: 1 pagamento ↔ 1 parcela. Valor = entrada do contrato → 'entrada'. O resto vai para a fila
--        fin.contratos_hf_pagamentos (situacao 'fila' + motivo) — nada é inventado. Estorno/reembolso desfaz a baixa.
--        Idempotente: 2ª execução não escreve nada nas tabelas de negócio (upsert só com mudança).
--   PENTEST 29/09 (Kirad, reprovada → corrigida aqui):
--     [ALTO] fusão só aceita pagamento HF PAGO cujo pagador tem o e-mail DA FICHA (sem bypass); casamento pagamento ×
--            ficha só pela transação do sinal ou pelo e-mail da ficha (nunca pelo e-mail de quem pagou o sinal);
--            a cada :25 a revalidação (2a) desfaz baixa cuja transação não está mais paga ou passou a casar com OUTRA
--            ficha viva (a dona vale mesmo arquivada); RPC fn_fin_contrato_hf_desfundir (operar) reabre a ficha fundida,
--            com motivo no histórico. 2ª rodada: arquivar ficha com pagamento conciliado é recusado; a fase 1 não
--            olha mais o e-mail do pagador do sinal. 3ª rodada (troca de e-mail na Hotmart): ficha criada sozinha
--            DEPOIS da baixa/entrada e sem parcelas (fin.contratos_hf_ficha_nova_vazia) não conta como "outra ficha
--            viva" na 2a nem na 2b; no mensal o pagamento conciliado fica com o contrato dono.
--     [MÉDIO] trigger informados_baixa_hotmart_trava: linha com transacao_hotmart não muda por nenhum caminho com
--            usuário logado (salvar, importar, baixar, arquivar, concluir etapa, mover de contrato, RPC futura).
--     [MÉDIO] subtransação por linha na 2a e na 2b; erros em fin.contratos_hf_sync_status, expostos nas colunas sync_*
--            da fila (e o pagamento que falhou vira linha da fila 'erro_interno: …').
--     [BAIXO] mensal só soma pagamento que casa com UM contrato (n_contratos = 1). [BAIXO] histórico sem observação.
--   3) fin.recebimentos_informados: contrato_id (FK → contratos_hf), etapa, etapa_concluida_em. data_prevista passa a
--      aceitar NULL só na parcela por etapa pendente (CHECK recebimentos_informados_data_etapa_ck). CHECK
--      recebimentos_informados_contrato_ck estendido (vivo conferido por pg_get_constraintdef; aborta se diferente).
--      Leitores de data_prevista conferidos: fin.receber_posicao filtra "data_prevista <= v_ate" (NULL fica fora — a
--      parcela sem data NÃO entra no caixa); informados_cobertura só lê via_hotmart (contrato nunca é); informados_situacao
--      ordena com NULLS LAST (acumulado das linhas datadas não muda) e dá 'a_receber' à parcela sem data.
--      Patches pelo CORPO VIVO com guarda md5(prosrc) + "trecho aparece exatamente 1 vez" (molde z90):
--        fin.informado_normalizar, fn_fin_informado_salvar, fn_fin_informados_importar (create or replace, ACL mantida);
--        fn_fin_informados_listar: RETURNS muda (+ contrato_id, etapa, etapa_concluida_em NO FIM) → drop + create +
--        revoke public/anon + grant authenticated; ACL conferida igual à de antes.
--   4) RPCs novas (security definer, search_path '', revoke public/anon, grant authenticated):
--        fn_fin_contratos_hf_mensal(p_de date, p_ate date)   leitura  gp_pode_ver_financeiro()
--        fn_fin_contrato_hf_salvar(jsonb) → uuid              escrita  gp_pode_operar_financeiro()
--        fn_fin_parcela_etapa_concluir(uuid, date)            escrita  gp_pode_operar_financeiro()
--        fn_fin_contratos_hf_pagamentos(p_so_fila boolean)    leitura  gp_pode_ver_financeiro()  (fila + status do cron)
--        fn_fin_contrato_hf_desfundir(uuid, text) → uuid      escrita  gp_pode_operar_financeiro()
--   A CARGA dos 27 contratos lidos do Drive NÃO está aqui (repo público: dado pessoal de cliente fica fora do git).
--   Ela é um script separado, fora do repo, rodado pela sessão principal depois do apply.
--
-- AS 5 PERGUNTAS
--   escala: contratos_hf = dezenas por ano (27 na planilha; 25 compradores HF na Hotmart em 29/09). informados = centenas.
--     A RPC mensal é grade contrato × mês (≤ 36 meses): 30 contratos × 12 meses = 360 linhas. 10× (300 contratos) = 3.600.
--   índice: nenhum novo. contratos_hf e recebimentos_informados são pequenos (Seq Scan é o plano certo, medido no explain).
--     Pagamentos HF: produto 5301413 pelo índice hotmart_transacoes_produto_idx (~54 linhas); sinal pela PK — provados no explain.
--     contrato_id sem índice de propósito: sem DELETE na ficha (trigger barra), a FK nunca varre o lado filho.
--   frequência: mensal = aba do Financeiro (dezenas/dia). sincronizar = 24×/dia: ~54 pagamentos do produto; a conciliação
--     só percorre os pagamentos ainda sem parcela (dezenas), cada um com 1 busca em recebimentos_informados (centenas).
--   repetição: 1 chamada de fin.informados_situacao por RPC (a mesma da lista); nenhuma query por linha.
--   reversão: abaixo.
--
-- REVERSÃO (nada se apaga; uma transação)
--   Desligar a criação automática: cron volta ao command da z84 —
--     select cron.alter_job(jobid, command := 'select count(*) from fin.resolver_ofertas_eventos(true, 45)')
--       from cron.job where jobname = 'fin-oferta-evento-resolver';
--   Reverter de verdade (depois de arquivar parcelas por etapa pendentes — senão o CHECK de data volta a falhar):
--     begin;
--     -- a) fn_fin_informados_listar: drop + create com o corpo da z73 (20260929z73 l. 639–673) + revoke/grant;
--     -- b) create or replace fin.informado_normalizar, fn_fin_informado_salvar, fn_fin_informados_importar com o corpo
--     --    da z73 (md5 vivo de antes na guarda abaixo; SALVAR pg_get_functiondef das 4 antes do apply);
--     -- c) drop function public.fn_fin_contratos_hf_mensal(date, date), public.fn_fin_contrato_hf_salvar(jsonb),
--     --    public.fn_fin_parcela_etapa_concluir(uuid, date), public.fn_fin_contratos_hf_pagamentos(boolean),
--     --    public.fn_fin_contrato_hf_desfundir(uuid, text), fin.contratos_hf_sincronizar(), fin.contratos_hf_transacoes();
--     --    drop trigger informados_baixa_hotmart_trava on fin.recebimentos_informados;
--     --    drop function fin.tg_informados_baixa_hotmart_trava();
--     --    baixas automáticas FICAM como baixas (a coluna transacao_hotmart e fin.contratos_hf_pagamentos contam de onde vieram).
--     -- Desligar só a conciliação sem reverter: não há chave — cron volta ao command da z84/z91 sem o prefixo (acima).
--     -- d) CHECKs: drop recebimentos_informados_data_etapa_ck; recebimentos_informados_contrato_ck = o texto da z73;
--     --    alter column data_prevista set not null (só passa sem parcela sem data);
--     -- e) FICAM (inertes): colunas contrato_id/etapa/etapa_concluida_em, fin.contratos_hf e o histórico
--     --    (renomear para *_arquivada_z93 se quiser tirar do caminho).
--     commit;
--
-- Estado vivo lido antes de escrever (29/09/2026 ~23:00 UTC): md5(prosrc)
--   fin.informado_normalizar(jsonb,fin.recebimentos_informados,boolean)  91d22ca0fd7b1ad83f764407233aac2d
--   public.fn_fin_informado_salvar(jsonb)                                7d08051d5730cc4a585d649746561702
--   public.fn_fin_informados_importar(jsonb,boolean)                     f3e66ddc5e1317540aa8d025c35c1aed
--   public.fn_fin_informados_listar()                                    1b6ce40e6e1e4a621b2422c326a5f959
--     proacl {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   cron fin-oferta-evento-resolver: '25 * * * *', 'select count(*) from fin.resolver_ofertas_eventos(true, 45)'
--   fin.recebimentos_informados: 0 linhas.

set local lock_timeout = '5s';

-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_def  text;
  e_ck   text := 'CHECK (CASE WHEN (tipo = ''contrato_holding_familiar''::text) THEN ((NOT via_hotmart) AND '
              || '(contrato_assinado IS NOT NULL) AND ((parcela_n IS NULL) = (parcela_de IS NULL)) AND ((parcela_n IS NULL) '
              || 'OR ((parcela_n >= 1) AND (parcela_n <= parcela_de) AND (parcela_de <= 60)))) ELSE ((parcela_n IS NULL) '
              || 'AND (parcela_de IS NULL) AND (contrato_assinado IS NULL)) END)';
begin
  if to_regclass('fin.contratos_hf') is not null
     or exists (select 1 from information_schema.columns where table_schema = 'fin'
                   and table_name = 'recebimentos_informados' and column_name in ('contrato_id','etapa','etapa_concluida_em')) then
    raise exception 'z93: já aplicada (fin.contratos_hf ou coluna contrato_id/etapa existe)';
  end if;
  if to_regclass('fin.vw_transacoes_escritorio') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'fin'
                       and table_name = 'recebimentos_informados' and column_name = 'contrato_assinado') then
    raise exception 'z93: aplicar z73 e z89 antes (contrato_assinado / vw_transacoes_escritorio ausentes)';
  end if;
  if to_regprocedure('public.gp_pode_operar_financeiro()') is null or to_regprocedure('public.gp_pode_ver_financeiro()') is null
     or to_regprocedure('public.gp_pode_ver_cpf()') is null then
    raise exception 'z93: guardas gp_pode_* ausentes';
  end if;
  select pg_get_constraintdef(c.oid) into v_def from pg_constraint c
   where c.conrelid = 'fin.recebimentos_informados'::regclass and c.conname = 'recebimentos_informados_contrato_ck';
  if v_def is null or regexp_replace(v_def, '\s+', '', 'g') <> regexp_replace(e_ck, '\s+', '', 'g') then
    raise exception 'z93: CHECK recebimentos_informados_contrato_ck vivo diferente do da z73: %', coalesce(v_def, 'ausente');
  end if;
  if not exists (select 1 from cron.job where jobname = 'fin-oferta-evento-resolver') then
    raise exception 'z93: cron fin-oferta-evento-resolver (z84) ausente';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('fn_fin_informado_salvar','fn_fin_informados_importar','fn_fin_informados_listar')) <> 3
     or (select count(*) from pg_proc p where p.pronamespace = 'fin'::regnamespace and p.proname = 'informado_normalizar') <> 1 then
    raise exception 'z93: sobrecarga viva ou função ausente nas RPCs de informados';
  end if;
end $guarda$;


-- ─── 1. Ficha do contrato ───────────────────────────────────────────────────────────────────────────────────────────
create table fin.contratos_hf (
  id               uuid primary key default gen_random_uuid(),
  transacao_sinal  text unique
                   check (transacao_sinal is null or (length(transacao_sinal) <= 64 and transacao_sinal ~ '^[A-Za-z0-9_-]+$')),
  nome             text not null check (btrim(nome) <> '' and length(nome) <= 200),
  email            text check (email is null or (length(email) <= 254 and email ~ '^[^@[:space:]]+@[^@[:space:]]+$')),
  telefone         text check (telefone is null or length(telefone) <= 40),
  cidade           text check (cidade is null or length(cidade) <= 120),
  uf               text check (uf is null or uf ~ '^[A-Z]{2}$'),
  cpf_final3       text check (cpf_final3 is null or cpf_final3 ~ '^[0-9]{3}$'),
  valor_bruto      numeric(12,2) check (valor_bruto is null or (valor_bruto > 0 and valor_bruto < 100000000)),
  valor_liquido    numeric(12,2) check (valor_liquido is null or (valor_liquido > 0 and valor_liquido < 100000000)),
  desconto_desc    text check (desconto_desc is null or length(desconto_desc) <= 200),
  entrada_valor    numeric(12,2) check (entrada_valor is null or (entrada_valor >= 0 and entrada_valor < 100000000)),
  entrada_pct      numeric(5,2) check (entrada_pct is null or entrada_pct between 0 and 100),
  data_assinatura  date check (data_assinatura is null or data_assinatura between date '2020-01-01' and date '2036-12-31'),
  assinado         text not null default 'indeterminado' check (assinado in ('sim','nao','indeterminado')),
  link_contrato    text check (link_contrato is null
                               or (length(link_contrato) <= 500
                                   and link_contrato ~ '^https://(docs|drive)\.google\.com/[A-Za-z0-9/_?=&.%#-]*$')),
  observacao       text check (observacao is null or length(observacao) <= 2000),
  origem           text not null check (origem in ('hotmart_sinal','planilha_drive')),
  arquivado_em     timestamptz,
  arquivado_por    uuid,
  arquivado_motivo text,
  criado_em        timestamptz not null default now(),
  criado_por       uuid,
  atualizado_em    timestamptz not null default now(),
  atualizado_por   uuid,
  constraint contratos_hf_arquivo_ck check ((arquivado_em is null) = (arquivado_motivo is null)
    and (arquivado_motivo is null or length(btrim(arquivado_motivo)) between 3 and 500)),
  -- contrato nascido do sinal só perde o sinal arquivado (fusão com a ficha lida do Drive)
  constraint contratos_hf_sinal_ck check (origem <> 'hotmart_sinal' or transacao_sinal is not null or arquivado_em is not null)
);
comment on table fin.contratos_hf is
  'z93: ficha do contrato Holding Familiar (escritório/Soluções). Parcelas = fin.recebimentos_informados (contrato_id). '
  'Sinal Hotmart: transacao_sinal (produto 5301413, conta escritorio). Não se apaga: arquiva. Escrita só por RPC/carga.';
alter table fin.contratos_hf enable row level security;   -- sem policy: só funções SECURITY DEFINER
revoke all on fin.contratos_hf from public, anon, authenticated;

create table fin.contratos_hf_historico (
  id          bigserial primary key,
  contrato_id uuid not null,
  acao        text not null check (acao in ('insert','update','desfundir')),
  antes       jsonb,
  depois      jsonb not null,
  por         uuid,
  motivo      text check (motivo is null or length(motivo) <= 500),
  em          timestamptz not null default now()
);
create index contratos_hf_historico_contrato_idx on fin.contratos_hf_historico (contrato_id, em);
alter table fin.contratos_hf_historico enable row level security;
revoke all on fin.contratos_hf_historico from public, anon, authenticated;
revoke all on sequence fin.contratos_hf_historico_id_seq from public, anon, authenticated;

create function fin.tg_contratos_hf_historico()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  -- contato, final do CPF e observação (texto livre, pode citar pessoa) não entram na trilha só-acréscimo — anonimizar
  -- a ficha não pode deixar cópia aqui. Da observação fica só o md5 (prova de que mudou). nome e cidade ficam
  -- (decisão do dono: visíveis a quem vê o Financeiro).
  insert into fin.contratos_hf_historico (contrato_id, acao, antes, depois, por)
  values (new.id, lower(tg_op),
          case when tg_op = 'UPDATE'
               then (to_jsonb(old) - array['email','telefone','cpf_final3','observacao'])
                    || jsonb_build_object('observacao_md5', md5(old.observacao)) end,
          (to_jsonb(new) - array['email','telefone','cpf_final3','observacao'])
            || jsonb_build_object('observacao_md5', md5(new.observacao)),
          (select auth.uid()));
  return null;
end $$;
revoke all on function fin.tg_contratos_hf_historico() from public, anon, authenticated;

create function fin.tg_contratos_hf_nao_apaga()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  raise exception 'fin.contratos_hf não se apaga: arquive com motivo (fn_fin_contrato_hf_salvar).' using errcode = 'P0001';
end $$;
revoke all on function fin.tg_contratos_hf_nao_apaga() from public, anon, authenticated;

create function fin.tg_contratos_hf_historico_so_acrescimo()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  raise exception 'fin.contratos_hf_historico é só acréscimo.' using errcode = 'P0001';
end $$;
revoke all on function fin.tg_contratos_hf_historico_so_acrescimo() from public, anon, authenticated;

create trigger contratos_hf_historico after insert or update on fin.contratos_hf
  for each row execute function fin.tg_contratos_hf_historico();
create trigger contratos_hf_nao_apaga before delete on fin.contratos_hf
  for each row execute function fin.tg_contratos_hf_nao_apaga();
create trigger contratos_hf_nao_trunca before truncate on fin.contratos_hf
  for each statement execute function fin.tg_contratos_hf_nao_apaga();
create trigger contratos_hf_historico_so_acrescimo before update or delete on fin.contratos_hf_historico
  for each row execute function fin.tg_contratos_hf_historico_so_acrescimo();
create trigger contratos_hf_historico_nao_trunca before truncate on fin.contratos_hf_historico
  for each statement execute function fin.tg_contratos_hf_historico_so_acrescimo();


-- ─── 2. Pagamentos HF na Hotmart: fichas automáticas + conciliação com as parcelas ────────────────────────────────
-- Estado da conciliação por transação (derivado; recalculado a cada :25). situacao:
--   baixou_parcela → a transação deu baixa em informado_id (espelho de recebimentos_informados.transacao_hotmart)
--   entrada        → valor igual à entrada do contrato (sinal), sem parcela a baixar
--   fila           → conferência humana; motivo diz por quê. Nada é inventado.
--   estornado      → a transação deixou de estar paga (estorno/reembolso/chargeback); a baixa que ela fez foi desfeita
create table fin.contratos_hf_pagamentos (
  transacao                   text primary key,
  contrato_id                 uuid references fin.contratos_hf (id),
  informado_id                uuid,
  situacao                    text not null check (situacao in ('baixou_parcela','entrada','fila','estornado')),
  motivo                      text check (motivo is null or length(motivo) <= 300),
  valor                       numeric(12,2),
  dia                         date,
  etapa_concluida_pela_baixa  boolean not null default false,
  atualizado_em               timestamptz not null default now(),
  constraint contratos_hf_pagamentos_baixa_ck check ((situacao = 'baixou_parcela') = (informado_id is not null))
);
comment on table fin.contratos_hf_pagamentos is
  'z93: conciliação automática dos pagamentos HF da Hotmart (5301413, conta escritorio) com as parcelas do contrato. '
  'Fila de conferência = situacao ''fila'' (fn_fin_contratos_hf_pagamentos). Escrita só por fin.contratos_hf_sincronizar.';
alter table fin.contratos_hf_pagamentos enable row level security;
revoke all on fin.contratos_hf_pagamentos from public, anon, authenticated;

-- Status da última sincronização (erro VISÍVEL, não só WARNING no log do cron). Uma linha.
create table fin.contratos_hf_sync_status (
  id         smallint primary key default 1 check (id = 1),
  ultima_em  timestamptz not null,
  fichas     int not null,
  baixas     int not null,
  desfeitas  int not null,
  erros      int not null,
  mensagem   text check (mensagem is null or length(mensagem) <= 4000)
);
comment on table fin.contratos_hf_sync_status is
  'z93: resultado da última fin.contratos_hf_sincronizar (cron :25): contagens, nº de erros e as mensagens. '
  'Exposto nas colunas sync_* de fn_fin_contratos_hf_pagamentos.';
alter table fin.contratos_hf_sync_status enable row level security;
revoke all on fin.contratos_hf_sync_status from public, anon, authenticated;

-- Pagamentos HF × ficha viva (uma linha por par; contrato_id NULL = nenhuma ficha). Casa pela transação do sinal da
-- ficha ou pelo e-mail DA FICHA — nunca pelo e-mail de quem pagou o sinal (pentest 29/09: o pagador do sinal pode não
-- ser o contratante). Regra única do mensal e da conciliação; n_contratos > 1 = ambíguo (vai para a fila).
create function fin.contratos_hf_transacoes()
returns table (contrato_id uuid, transacao text, dia date, aprovado_em timestamptz, valor numeric, liquido numeric,
               grupo text, n_contratos int)
language sql stable security invoker set search_path = ''
as $$
  with f as (
    select c.id, c.transacao_sinal, lower(c.email) e1
      from fin.contratos_hf c
     where c.arquivado_em is null
  )
  select f.id, t.transacao, t.dia_aprovado, t.aprovado_em, t.valor_oferta, t.liquido, t.grupo,
         count(f.id) over (partition by t.transacao)::int
    from fin.vw_transacoes_escritorio t
    left join f on t.transacao = f.transacao_sinal or t.email = f.e1
   where t.produto_id = '5301413'
$$;
revoke all on function fin.contratos_hf_transacoes() from public, anon, authenticated;

create function fin.contratos_hf_sincronizar()
returns int
language plpgsql volatile security invoker set search_path = ''
as $$
declare
  v_fichas    int := 0;
  v_baixas    int := 0;
  v_desfeitas int := 0;
  v_erros     int := 0;
  v_msg       text[] := '{}';
  v_travou    boolean := false;
  v_err       text;
  r           record;
  v_pid       uuid;
  v_pdata     date;
  v_tol       numeric;
  v_ent       numeric;
  v_sit       text;
  v_motivo    text;
  v_pela      boolean;
begin
  -- Fase 1 — fichas. O produto 5301413 recebe o sinal E parcelas pagas pela Hotmart (medido 29/09: 33 pagamentos de
  -- 25 compradores). Uma ficha por COMPRADOR (e-mail): a 1ª transação paga vira transacao_sinal; comprador que já tem
  -- ficha com o mesmo e-mail (viva ou arquivada, inclusive a do Drive) não ganha outra. Nunca pelo e-mail de quem pagou o
  -- sinal de outra ficha (pentest 29/09).
  begin
    insert into fin.contratos_hf (transacao_sinal, nome, email, entrada_valor, origem, assinado, observacao)
    select distinct on (coalesce(t.email, t.transacao))
           t.transacao,
           left(coalesce(nullif(btrim(t.nome), ''), '(sem nome na Hotmart)'), 200),
           case when length(t.email) <= 254 and t.email ~ '^[^@[:space:]]+@[^@[:space:]]+$' then t.email end,
           t.valor_oferta, 'hotmart_sinal', 'indeterminado',
           'Criada sozinha pelo 1º pagamento HF na Hotmart (produto 5301413) deste comprador. Valor cheio, parcelas e '
           || 'assinatura: preencher ou fundir com a ficha lida do Drive.'
      from fin.vw_transacoes_escritorio t
     where t.produto_id = '5301413' and t.grupo = 'pago'
       and t.transacao ~ '^[A-Za-z0-9_-]+$' and length(t.transacao) <= 64
       and not exists (select 1 from fin.contratos_hf c where c.transacao_sinal = t.transacao)
       and (t.email is null
            or not exists (select 1 from fin.contratos_hf c where lower(c.email) = t.email))
     order by coalesce(t.email, t.transacao), t.aprovado_em, t.transacao
    on conflict (transacao_sinal) do nothing;
    get diagnostics v_fichas = row_count;
  exception when others then
    v_erros := v_erros + 1;
    v_msg := v_msg || ('fichas: ' || sqlerrm);
  end;

  -- Fase 2 — conciliação (dono: "tem que ser registrado automático"; a baixa manual fica para o Pix). Mesma ordem de
  -- trava das RPCs de escrita: ficha, depois informados.
  begin
    perform pg_advisory_xact_lock(hashtext('fin.contratos_hf:escrita'));
    perform pg_advisory_xact_lock(hashtext('fin.recebimentos_informados:escrita'));
    v_travou := true;
  exception when others then
    v_erros := v_erros + 1;
    v_msg := v_msg || ('trava: ' || sqlerrm);
  end;

  if v_travou then
    -- 2a. revalidação a cada :25: desfaz a baixa se a transação deixou de estar PAGA ou se passou a casar com OUTRA
    --     ficha viva (desfusão, ficha duplicada, e-mail trocado). A ficha dona da baixa continua valendo mesmo
    --     arquivada (pentest 29/09, 2ª rodada). Uma subtransação por linha: uma linha ruim não derruba as outras.
    for r in
      with x as materialized (
        select c.transacao, c.contrato_id from fin.contratos_hf_transacoes() c
         where c.contrato_id is not null
      )
      select i.id, i.transacao_hotmart, coalesce(pg.etapa_concluida_pela_baixa, false) pela, p.pago
        from fin.recebimentos_informados i
        left join fin.contratos_hf_pagamentos pg on pg.transacao = i.transacao_hotmart
        cross join lateral (select exists (select 1 from fin.vw_transacoes_escritorio t
                                            where t.transacao = i.transacao_hotmart and t.grupo = 'pago') pago) p
       where i.transacao_hotmart is not null
         and (not p.pago
              or exists (select 1 from x
                          where x.transacao = i.transacao_hotmart and x.contrato_id <> i.contrato_id
                            -- ficha criada sozinha DEPOIS da baixa e sem parcelas (troca de e-mail na Hotmart) não conta
                            and not fin.contratos_hf_ficha_nova_vazia(x.contrato_id,
                                                                      coalesce(pg.atualizado_em, i.atualizado_em))))
    loop
      begin
        update fin.recebimentos_informados x
           set baixa_manual_em = null, baixa_manual_por = null, transacao_hotmart = null,
               etapa_concluida_em = case when r.pela then null else x.etapa_concluida_em end,
               data_prevista = case when r.pela then null else x.data_prevista end,
               atualizado_por = null, atualizado_em = now()
         where x.id = r.id;
        -- ainda paga (mudou de dono): a 2b reprocessa nesta mesma execução; não paga: estornado
        update fin.contratos_hf_pagamentos pg
           set situacao = case when r.pago then 'fila' else 'estornado' end,
               informado_id = null, etapa_concluida_pela_baixa = false, atualizado_em = now(),
               motivo = case when r.pago then 'revalidacao: a transação passou a casar com outra ficha viva; baixa desfeita.'
                             else 'Transação não está mais paga na Hotmart: baixa desfeita.' end
         where pg.transacao = r.transacao_hotmart;
        v_desfeitas := v_desfeitas + 1;
      exception when others then
        v_erros := v_erros + 1;
        v_msg := v_msg || ('revalidar ' || r.transacao_hotmart || ': ' || sqlerrm);
      end;
    end loop;
    begin
      update fin.contratos_hf_pagamentos pg
         set situacao = 'estornado', informado_id = null, etapa_concluida_pela_baixa = false, atualizado_em = now(),
             motivo = 'Transação não está mais paga na Hotmart.'
       where pg.situacao in ('entrada','fila')
         and not exists (select 1 from fin.vw_transacoes_escritorio t where t.transacao = pg.transacao and t.grupo = 'pago');
    exception when others then
      v_erros := v_erros + 1;
      v_msg := v_msg || ('estornos: ' || sqlerrm);
    end;

    -- 2b. cada pagamento pago ainda sem parcela, em ordem de aprovação (1 parcela ← 1 pagamento, guloso e estável).
    for r in
      select x.transacao, min(x.dia) dia, min(x.valor) valor, max(x.n_contratos) n, (array_agg(x.contrato_id))[1] cid,
             array_agg(x.contrato_id) cids, pg.contrato_id ent_cid, pg.atualizado_em ent_em
        from fin.contratos_hf_transacoes() x
        left join fin.contratos_hf_pagamentos pg on pg.transacao = x.transacao and pg.situacao = 'entrada'
       where x.grupo = 'pago'
         and not exists (select 1 from fin.recebimentos_informados i where i.transacao_hotmart = x.transacao)
       group by x.transacao, pg.contrato_id, pg.atualizado_em
       order by min(x.aprovado_em), x.transacao
    loop
      -- entrada já reconhecida fica com o contrato dela, a menos que a transação case com OUTRA ficha que não seja
      -- "nova e vazia" (troca de e-mail na Hotmart não move a entrada)
      continue when r.ent_cid is not null
                and not exists (select 1 from unnest(r.cids) c(id)
                                 where c.id is not null and c.id <> r.ent_cid
                                   and not fin.contratos_hf_ficha_nova_vazia(c.id, r.ent_em));
      begin
        v_sit := 'fila'; v_motivo := null; v_pid := null; v_pdata := null; v_pela := false;
        if r.n = 0 then
          v_motivo := 'sem_contrato: nenhuma ficha viva deste comprador.';
        elsif r.n > 1 then
          v_motivo := 'mais_de_um_contrato: o comprador está em ' || r.n || ' fichas vivas (fundir ou arquivar antes).';
          r.cid := null;
        else
          -- valor igual (± R$ 1,00 ou 1%, o maior) e vencimento a ±45 dias, o mais próximo; parcela por etapa sem data
          -- aceita (depois das datadas; entre elas, a de menor número)
          v_tol := greatest(1, round(r.valor * 0.01, 2));
          select i.id, i.data_prevista into v_pid, v_pdata
            from fin.recebimentos_informados i
           where i.contrato_id = r.cid and i.arquivado_em is null
             and i.baixa_manual_em is null and i.transacao_hotmart is null
             and abs(i.valor - r.valor) <= v_tol
             and (i.data_prevista between r.dia - 45 and r.dia + 45
                  or (i.data_prevista is null and i.etapa is not null and i.etapa_concluida_em is null))
           order by (i.data_prevista is null), abs(i.data_prevista - r.dia), i.parcela_n nulls last, i.id
           limit 1
           for update;
          if v_pid is not null then
            v_pela := v_pdata is null;
            update fin.recebimentos_informados x
               set baixa_manual_em = r.dia, baixa_manual_por = null, transacao_hotmart = r.transacao,
                   etapa_concluida_em = case when x.data_prevista is null then r.dia else x.etapa_concluida_em end,
                   data_prevista = coalesce(x.data_prevista, r.dia),
                   atualizado_por = null, atualizado_em = now()
             where x.id = v_pid;
            v_sit := 'baixou_parcela';
          else
            select c.entrada_valor into v_ent from fin.contratos_hf c where c.id = r.cid;
            if not exists (select 1 from fin.recebimentos_informados i where i.contrato_id = r.cid and i.arquivado_em is null) then
              v_motivo := 'contrato_sem_parcelas: ficha sem parcelas cadastradas (preencher o contrato).';
            elsif v_ent is not null and abs(v_ent - r.valor) <= greatest(1, round(v_ent * 0.01, 2))
                  and not exists (select 1 from fin.contratos_hf_pagamentos pg
                                   where pg.contrato_id = r.cid and pg.situacao = 'entrada' and pg.transacao <> r.transacao) then
              v_sit := 'entrada';
              v_motivo := 'Valor igual à entrada (sinal) do contrato.';
            elsif exists (select 1 from fin.recebimentos_informados i
                           where i.contrato_id = r.cid and i.arquivado_em is null and abs(i.valor - r.valor) <= v_tol
                             and i.baixa_manual_em is null and i.transacao_hotmart is null) then
              v_motivo := 'fora_da_janela: há parcela em aberto com esse valor, mas vencimento a mais de 45 dias do pagamento.';
            elsif exists (select 1 from fin.recebimentos_informados i
                           where i.contrato_id = r.cid and i.arquivado_em is null and abs(i.valor - r.valor) <= v_tol) then
              v_motivo := 'parcela_ja_baixada: as parcelas com esse valor já têm baixa (manual ou outro pagamento).';
            else
              v_motivo := 'valor_nao_bate: nenhuma parcela em aberto com esse valor (tolerância R$ 1,00 ou 1%).';
            end if;
          end if;
        end if;
        insert into fin.contratos_hf_pagamentos as pg
               (transacao, contrato_id, informado_id, situacao, motivo, valor, dia, etapa_concluida_pela_baixa)
        values (r.transacao, r.cid, v_pid, v_sit, v_motivo, r.valor, r.dia, v_pela)
        on conflict (transacao) do update
           set contrato_id = excluded.contrato_id, informado_id = excluded.informado_id, situacao = excluded.situacao,
               motivo = excluded.motivo, valor = excluded.valor, dia = excluded.dia,
               etapa_concluida_pela_baixa = excluded.etapa_concluida_pela_baixa, atualizado_em = now()
         where (pg.contrato_id, pg.informado_id, pg.situacao, pg.motivo, pg.valor, pg.dia, pg.etapa_concluida_pela_baixa)
               is distinct from
               (excluded.contrato_id, excluded.informado_id, excluded.situacao, excluded.motivo, excluded.valor,
                excluded.dia, excluded.etapa_concluida_pela_baixa);
        if v_sit = 'baixou_parcela' then v_baixas := v_baixas + 1; end if;
      exception when others then
        -- a linha volta sozinha (subtransação); o erro fica na fila, visível, e no status
        v_err := sqlerrm;
        v_erros := v_erros + 1;
        v_msg := v_msg || ('conciliar ' || r.transacao || ': ' || v_err);
        begin
          insert into fin.contratos_hf_pagamentos as pg (transacao, situacao, motivo, valor, dia)
          values (r.transacao, 'fila', left('erro_interno: ' || v_err, 300), r.valor, r.dia)
          on conflict (transacao) do update
             set situacao = 'fila', informado_id = null, contrato_id = null, etapa_concluida_pela_baixa = false,
                 motivo = excluded.motivo, atualizado_em = now()
           where pg.situacao <> 'baixou_parcela';
        exception when others then
          null;
        end;
      end;
    end loop;
  end if;

  begin
    insert into fin.contratos_hf_sync_status as s (id, ultima_em, fichas, baixas, desfeitas, erros, mensagem)
    values (1, now(), v_fichas, v_baixas, v_desfeitas, v_erros, left(nullif(array_to_string(v_msg, ' | '), ''), 4000))
    on conflict (id) do update
       set ultima_em = excluded.ultima_em, fichas = excluded.fichas, baixas = excluded.baixas,
           desfeitas = excluded.desfeitas, erros = excluded.erros, mensagem = excluded.mensagem;
  exception when others then
    raise warning 'fin.contratos_hf_sincronizar (status): % (%)', sqlerrm, sqlstate;
  end;
  if v_erros > 0 then
    raise warning 'fin.contratos_hf_sincronizar: % erro(s): %', v_erros, array_to_string(v_msg, ' | ');
  end if;
  return case when v_erros > 0 then -1 else v_fichas + v_baixas + v_desfeitas end;
end $$;
comment on function fin.contratos_hf_sincronizar() is
  'z93: (1) cria UMA ficha (origem hotmart_sinal) por comprador de pagamento HF pago (5301413, conta escritorio) ainda '
  'sem ficha; (2a) desfaz a baixa automática cuja transação deixou de estar paga ou passou a casar com OUTRA ficha viva '
  '(a dona continua valendo mesmo arquivada); (2b) concilia: pagamento pago dá baixa na parcela em aberto (valor ± R$ 1 ou 1%, vencimento ±45 d, o '
  'mais próximo; etapa sem data é concluída na data do pagamento); o resto vai para a fila (fin.contratos_hf_pagamentos). '
  'Subtransação por linha; resultado e erros em fin.contratos_hf_sync_status. Idempotente. Cron :25. Nunca levanta '
  'erro: -1 quando houve erro. Retorno = fichas criadas + baixas + baixas desfeitas.';
revoke all on function fin.contratos_hf_sincronizar() from public, anon, authenticated;

do $cron$
declare
  v_id  bigint;
  v_cmd text;
begin
  select j.jobid, j.command into v_id, v_cmd from cron.job j where j.jobname = 'fin-oferta-evento-resolver';
  if v_cmd !~ 'contratos_hf_sincronizar' then
    -- na FRENTE: o command da z84 (ou o que a z91 tiver posto) fica intacto depois do ponto e vírgula
    perform cron.alter_job(v_id, command := 'select fin.contratos_hf_sincronizar(); ' || btrim(v_cmd));
  end if;
end $cron$;


-- ─── 3. Parcelas: vínculo com a ficha e etapa ───────────────────────────────────────────────────────────────────────
alter table fin.recebimentos_informados
  add column contrato_id uuid references fin.contratos_hf (id),
  add column etapa text,
  add column etapa_concluida_em date,
  add column transacao_hotmart text;
alter table fin.recebimentos_informados alter column data_prevista drop not null;
-- baixa automática: uma transação baixa uma parcela só (e vice-versa: a parcela baixada sai da busca)
create unique index recebimentos_informados_transacao_hotmart_uk
  on fin.recebimentos_informados (transacao_hotmart) where transacao_hotmart is not null;
alter table fin.recebimentos_informados drop constraint recebimentos_informados_contrato_ck;
alter table fin.recebimentos_informados
  add constraint recebimentos_informados_contrato_ck
    check (case when tipo = 'contrato_holding_familiar'
                then not via_hotmart
                     and contrato_assinado is not null
                     and (parcela_n is null) = (parcela_de is null)
                     and (parcela_n is null or (parcela_n >= 1 and parcela_n <= parcela_de and parcela_de <= 60))
                     and (etapa is null or (btrim(etapa) <> '' and length(etapa) <= 80))
                     and (etapa_concluida_em is null or etapa is not null)
                else parcela_n is null and parcela_de is null and contrato_assinado is null
                     and contrato_id is null and etapa is null and etapa_concluida_em is null end),
  add constraint recebimentos_informados_hotmart_baixa_ck
    check (transacao_hotmart is null or (tipo = 'contrato_holding_familiar' and baixa_manual_em is not null)),
  add constraint recebimentos_informados_data_etapa_ck
    check (data_prevista is not null
           or (tipo = 'contrato_holding_familiar' and etapa is not null and etapa_concluida_em is null));
-- Baixa automática é do cron: linha com transacao_hotmart não muda por NENHUM caminho com usuário logado (salvar,
-- importar, baixar, arquivar, concluir etapa, mover de contrato e qualquer RPC futura). Só o cron (postgres,
-- auth.uid() nulo) mexe; estorno/revalidação desfazem sozinhos. (pentest 29/09, MÉDIO)
create function fin.tg_informados_baixa_hotmart_trava()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if (select auth.uid()) is not null
     and (   (tg_op = 'INSERT' and new.transacao_hotmart is not null)
          or (tg_op = 'UPDATE' and (old.transacao_hotmart is not null
                                    or new.transacao_hotmart is distinct from old.transacao_hotmart))) then
    raise exception 'Baixa automática pela Hotmart (transação %): não se altera à mão. Estorno na Hotmart desfaz sozinho.',
      coalesce(old.transacao_hotmart, new.transacao_hotmart) using errcode = 'P0001';
  end if;
  return new;
end $$;
revoke all on function fin.tg_informados_baixa_hotmart_trava() from public, anon, authenticated;
create trigger informados_baixa_hotmart_trava before insert or update on fin.recebimentos_informados
  for each row execute function fin.tg_informados_baixa_hotmart_trava();

-- Ficha "nova e vazia": criada sozinha pelo pagamento (origem hotmart_sinal) DEPOIS de p_desde e sem parcelas vivas.
-- Aparece quando a Hotmart regrava o e-mail do comprador em transações antigas (a edge hotmart-sync reescreve
-- comprador_email): não pode tirar do contrato dono as baixas/entradas que ele já tinha (Kirad, 3ª rodada).
create function fin.contratos_hf_ficha_nova_vazia(p_id uuid, p_desde timestamptz)
returns boolean
language sql stable security invoker set search_path = ''
as $$
  select exists (select 1 from fin.contratos_hf c
                  where c.id = p_id and c.origem = 'hotmart_sinal'
                    and c.criado_em > coalesce(p_desde, '-infinity'::timestamptz)
                    and not exists (select 1 from fin.recebimentos_informados r
                                     where r.contrato_id = c.id and r.arquivado_em is null))
$$;
revoke all on function fin.contratos_hf_ficha_nova_vazia(uuid, timestamptz) from public, anon, authenticated;

comment on column fin.recebimentos_informados.contrato_id is
  'z93: ficha do contrato Holding Familiar (fin.contratos_hf). Só no tipo contrato_holding_familiar.';
comment on column fin.recebimentos_informados.etapa is
  'z93: parcela por etapa ("a receber na etapa X": assinatura, minutas, registros…). Sem data até a etapa ser concluída.';
comment on column fin.recebimentos_informados.etapa_concluida_em is
  'z93: dia em que a etapa foi concluída (fn_fin_parcela_etapa_concluir). Vira a data prevista da parcela.';
comment on column fin.recebimentos_informados.transacao_hotmart is
  'z93: baixa AUTOMÁTICA pelo pagamento HF na Hotmart (fin.contratos_hf_sincronizar). NULL = baixa manual (Pix) ou em aberto. '
  'Não se altera à mão; estorno na Hotmart desfaz sozinho.';
comment on column fin.recebimentos_informados.data_prevista is
  'Vencimento. NULL só na parcela de contrato por etapa ainda não concluída (z93) — fica fora da previsão de caixa.';


-- ─── 4. Patches pelo corpo vivo (guarda md5 + trecho exatamente 1 vez) ──────────────────────────────────────────────
do $patch$
declare
  r      record;
  v_md5  text;
  v_def  text;
  v_acl  text;
  v_n    int;
  i      int;
  -- normalizar: bloco A (antes do z73) — lê contrato_id cedo, para a assinatura herdar da ficha
  n_a constant text := $b$  -- z93: ficha do contrato (fin.contratos_hf). Chave ausente mantém o atual.
  if p_criando or p ? 'contrato_id' then
    begin
      r.contrato_id := nullif(btrim(p ->> 'contrato_id'), '')::uuid;
    exception when invalid_text_representation then
      raise exception 'Contrato inválido: "%".', p ->> 'contrato_id' using errcode = 'P0001';
    end;
  end if;
  foreach v_campo in array array['parcela_n','parcela_de'] loop$b$;
  -- normalizar: bloco B — contrato_assinado ausente herda da ficha (sim → true; não/indeterminado → false)
  n_b constant text := $b$    if r.contrato_assinado is null and r.contrato_id is not null then   -- z93: herda da ficha
      select c.assinado = 'sim' into r.contrato_assinado from fin.contratos_hf c where c.id = r.contrato_id;
    end if;
    if r.contrato_assinado is null then$b$;
  -- normalizar: bloco C — etapa, conclusão, ficha viva e a checagem de data (antes no topo) só agora
  n_c constant text := $b$  -- z93: parcela por etapa (sem data até a etapa ser concluída) e vínculo com a ficha
  if p_criando or p ? 'etapa' then
    r.etapa := nullif(btrim(p ->> 'etapa'), '');
    if length(r.etapa) > 80 then
      raise exception 'Etapa longa demais (até 80 caracteres).' using errcode = 'P0001';
    end if;
  end if;
  if p_criando or p ? 'etapa_concluida_em' then
    r.etapa_concluida_em := fin.informado_data(p ->> 'etapa_concluida_em', 'Conclusão da etapa');
    if r.etapa_concluida_em is not null
       and (r.etapa_concluida_em > v_hoje or r.etapa_concluida_em < date '2020-01-01') then
      raise exception 'Conclusão da etapa fora do intervalo (de 2020 até hoje): %.', r.etapa_concluida_em
        using errcode = 'P0001';
    end if;
  end if;
  if r.tipo = 'contrato_holding_familiar' then
    if r.contrato_id is not null and r.contrato_id is distinct from p_atual.contrato_id
       and not exists (select 1 from fin.contratos_hf c where c.id = r.contrato_id and c.arquivado_em is null) then
      raise exception 'Contrato não encontrado ou arquivado.' using errcode = 'P0001';
    end if;
    if r.etapa_concluida_em is not null and r.etapa is null then
      raise exception 'Conclusão de etapa sem etapa: informe a etapa.' using errcode = 'P0001';
    end if;
    if r.etapa_concluida_em is not null and r.data_prevista is null then
      r.data_prevista := r.etapa_concluida_em;
    end if;
  else
    if (p ? 'contrato_id' and r.contrato_id is not null) or (p ? 'etapa' and r.etapa is not null)
       or (p ? 'etapa_concluida_em' and r.etapa_concluida_em is not null) then
      raise exception 'Contrato, etapa e conclusão da etapa só valem para o tipo contrato_holding_familiar.'
        using errcode = 'P0001';
    end if;
    r.contrato_id := null;
    r.etapa := null;
    r.etapa_concluida_em := null;
  end if;
  if r.data_prevista is null
     and not (r.tipo = 'contrato_holding_familiar' and r.etapa is not null and r.etapa_concluida_em is null) then
    raise exception 'Informe a data prevista.' using errcode = 'P0001';
  end if;

  if p_criando or p ? 'produtos' then$b$;
begin
  for r in
    select * from (values
      (1, 'fin.informado_normalizar(jsonb,fin.recebimentos_informados,boolean)', '91d22ca0fd7b1ad83f764407233aac2d',
          array[$x$'parcela_n','parcela_de','contrato_assinado']) then$x$,
                $x$  if r.data_prevista is null then raise exception 'Informe a data prevista.' using errcode = 'P0001'; end if;$x$,
                $x$  foreach v_campo in array array['parcela_n','parcela_de'] loop$x$,
                $x$    if r.contrato_assinado is null then$x$,
                $x$  if p_criando or p ? 'produtos' then$x$],
          array[$x$'parcela_n','parcela_de','contrato_assinado',
                       'contrato_id','etapa','etapa_concluida_em','transacao_hotmart']) then$x$,
                $x$  -- z93: "Informe a data prevista" desceu para depois do tipo (parcela por etapa fica sem data)$x$,
                n_a, n_b, n_c]),
      (2, 'public.fn_fin_informado_salvar(jsonb)', '7d08051d5730cc4a585d649746561702',
          array[$x$baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por, parcela_n, parcela_de, contrato_assinado)$x$,
                E'r.contrato_assinado)\n    returning x.id into v_id;',
                $x$r.acordo_desde, r.baixa_manual_em, r.parcela_n, r.parcela_de, r.contrato_assinado)$x$,
                $x$v_atual.parcela_n, v_atual.parcela_de, v_atual.contrato_assinado)$x$,
                $x$parcela_n = r.parcela_n, parcela_de = r.parcela_de, contrato_assinado = r.contrato_assinado,$x$],
          array[$x$baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por, parcela_n, parcela_de, contrato_assinado,
       contrato_id, etapa, etapa_concluida_em)$x$,
                E'r.contrato_assinado, r.contrato_id, r.etapa, r.etapa_concluida_em)\n    returning x.id into v_id;',
                $x$r.acordo_desde, r.baixa_manual_em, r.parcela_n, r.parcela_de, r.contrato_assinado,
      r.contrato_id, r.etapa, r.etapa_concluida_em)$x$,
                $x$v_atual.parcela_n, v_atual.parcela_de, v_atual.contrato_assinado,
      v_atual.contrato_id, v_atual.etapa, v_atual.etapa_concluida_em)$x$,
                $x$parcela_n = r.parcela_n, parcela_de = r.parcela_de, contrato_assinado = r.contrato_assinado,
         contrato_id = r.contrato_id, etapa = r.etapa, etapa_concluida_em = r.etapa_concluida_em,$x$]),
      (3, 'public.fn_fin_informados_importar(jsonb,boolean)', 'f3e66ddc5e1317540aa8d025c35c1aed',
          array[$x$baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por, parcela_n, parcela_de, contrato_assinado)$x$,
                E'r.contrato_assinado)\n    returning x.id into v_id;',
                $x$r.tipo, r.parcela_n);$x$,
                $x$x.arquivado_em is null and x.data_prevista = r.data_prevista$x$,
                $x$and x.parcela_n is not distinct from r.parcela_n)$x$],
          array[$x$baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por, parcela_n, parcela_de, contrato_assinado,
       contrato_id, etapa, etapa_concluida_em)$x$,
                E'r.contrato_assinado, r.contrato_id, r.etapa, r.etapa_concluida_em)\n    returning x.id into v_id;',
                $x$r.tipo, r.parcela_n, r.contrato_id, r.etapa);$x$,
                $x$x.arquivado_em is null and x.data_prevista is not distinct from r.data_prevista$x$,
                $x$and x.parcela_n is not distinct from r.parcela_n
                    and x.contrato_id is not distinct from r.contrato_id
                    and x.etapa is not distinct from r.etapa)$x$]),
      (4, 'public.fn_fin_informados_listar()', '1b6ce40e6e1e4a621b2422c326a5f959',
          array[$x$contrato_assinado boolean)$x$,
                $x$r.parcela_n, r.parcela_de, r.contrato_assinado   -- z73$x$],
          array[$x$contrato_assinado boolean, contrato_id uuid, etapa text, etapa_concluida_em date, transacao_hotmart text)$x$,
                $x$r.parcela_n, r.parcela_de, r.contrato_assinado,   -- z73
         r.contrato_id, r.etapa, r.etapa_concluida_em, r.transacao_hotmart   -- z93$x$])
    ) v(ordem, sig, md5_esperado, de, para)
    order by ordem
  loop
    select md5(p.prosrc), pg_get_functiondef(p.oid), p.proacl::text into v_md5, v_def, v_acl
      from pg_proc p where p.oid = r.sig::regprocedure;
    if v_md5 is distinct from r.md5_esperado then
      raise exception 'z93: corpo vivo de % mudou (md5 % <> %). Reler a função e refazer o patch.', r.sig, v_md5, r.md5_esperado;
    end if;
    for i in 1 .. array_length(r.de, 1) loop
      v_n := (length(v_def) - length(replace(v_def, r.de[i], ''))) / length(r.de[i]);
      if v_n <> 1 then
        raise exception 'z93: trecho aparece % vez(es) em % (esperado 1): %', v_n, r.sig, left(r.de[i], 80);
      end if;
      v_def := replace(v_def, r.de[i], r.para[i]);
    end loop;
    if r.ordem = 4 then
      -- RETURNS muda: drop + create; a ACL se perde no drop e é refeita abaixo (conferida igual à de antes)
      drop function public.fn_fin_informados_listar();
      execute regexp_replace(v_def, '^CREATE OR REPLACE FUNCTION', 'CREATE FUNCTION');
      revoke all on function public.fn_fin_informados_listar() from public, anon;
      grant execute on function public.fn_fin_informados_listar() to authenticated;
      if (select p.proacl::text from pg_proc p where p.oid = 'public.fn_fin_informados_listar()'::regprocedure)
         is distinct from v_acl then
        raise exception 'z93: ACL de fn_fin_informados_listar mudou: % → %', v_acl,
          (select p.proacl::text from pg_proc p where p.oid = 'public.fn_fin_informados_listar()'::regprocedure);
      end if;
    else
      execute v_def;   -- create or replace: mantém dono, ACL, security definer e proconfig
    end if;
  end loop;
end $patch$;
comment on function public.fn_fin_informados_listar() is
  'Contas a Receber (z63; contrato z73; ficha/etapa z93): recebimentos informados com situação no agora. Identificador '
  'mascarado sem gp_pode_ver_cpf(). No fim: parcela_n, parcela_de, contrato_assinado (z73), contrato_id, etapa, '
  'etapa_concluida_em, transacao_hotmart (z93) — nulos fora do contrato Holding Familiar. data_prevista NULL = parcela '
  'por etapa pendente; transacao_hotmart = baixa automática pela Hotmart.';


-- ─── 5. RPCs novas ──────────────────────────────────────────────────────────────────────────────────────────────────
create function public.fn_fin_contratos_hf_mensal(p_de date default null, p_ate date default null)
returns table (
  contrato_id uuid, mes date,
  nome text, email text, telefone text, cidade text, uf text, cpf_final3 text,
  origem text, transacao_sinal text, data_assinatura date, assinado text, fechado_em date,
  valor_bruto numeric, valor_liquido numeric, desconto_desc text, entrada_valor numeric, entrada_pct numeric,
  link_contrato text, observacao text, arquivado_em timestamptz,
  esperado numeric, caiu_manual numeric, caiu_hotmart numeric, caiu_hotmart_liquido numeric, caiu numeric,
  a_receber_etapa numeric, situacao text, parcelas jsonb)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_de   date;
  v_ate  date;
  v_fim  date;
  v_cpf  boolean;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_de  := date_trunc('month', coalesce(p_de, (v_hoje - interval '5 months')::date))::date;
  v_ate := date_trunc('month', coalesce(p_ate, (v_hoje + interval '6 months')::date))::date;
  if v_ate < v_de or v_ate > (v_de + interval '35 months')::date then
    raise exception 'Período inválido (início até fim, no máximo 36 meses).' using errcode = '22023';
  end if;
  v_fim := (v_ate + interval '1 month' - interval '1 day')::date;
  v_cpf := coalesce(public.gp_pode_ver_cpf(), false);

  return query
  with parc as materialized (
    -- parcelas vivas ligadas a uma ficha, com a situação da mesma regra da lista (1 chamada)
    select r.id, r.contrato_id cid, r.data_prevista, r.valor, r.baixa_manual_em, r.parcela_n, r.parcela_de,
           r.etapa, r.etapa_concluida_em, r.transacao_hotmart, s.situacao sit
      from fin.recebimentos_informados r
      join fin.informados_situacao(now()) s on s.id = r.id
     where r.contrato_id is not null and r.arquivado_em is null
  ), sinal as materialized (
    -- pagamentos HF pagos na Hotmart: o conciliado (baixa ou entrada) fica com o contrato dono — troca de e-mail na
    -- Hotmart não move dinheiro; o resto, com a ficha viva do comprador se for uma só (ambíguo não conta: fila)
    select distinct on (x.transacao) coalesce(o.cid, x.contrato_id) cid, x.dia dia_aprovado, x.valor valor_oferta, x.liquido
      from fin.contratos_hf_transacoes() x
      left join lateral (select pg.contrato_id cid from fin.contratos_hf_pagamentos pg
                          where pg.transacao = x.transacao and pg.situacao in ('baixou_parcela','entrada')) o on true
     where x.grupo = 'pago'
       and (o.cid is not null or (x.contrato_id is not null and x.n_contratos = 1))
     order by x.transacao
  ), esp as (
    select p.cid, date_trunc('month', p.data_prevista)::date mes, sum(p.valor) esperado,
           case when bool_or(p.sit = 'em_atraso_cobrar') then 'em_atraso_cobrar'
                when bool_or(p.sit = 'a_receber') then 'a_receber'
                else 'baixado_fora' end sit,
           jsonb_agg(jsonb_build_object('id', p.id, 'parcela_n', p.parcela_n, 'parcela_de', p.parcela_de,
                                        'valor', p.valor, 'data_prevista', p.data_prevista, 'situacao', p.sit,
                                        'baixa_manual_em', p.baixa_manual_em, 'transacao_hotmart', p.transacao_hotmart,
                                        'etapa', p.etapa,
                                        'etapa_concluida_em', p.etapa_concluida_em)
                     order by p.data_prevista, p.parcela_n, p.id) parcelas
      from parc p
     where p.data_prevista between v_de and v_fim
     group by 1, 2
  ), bx as (
    select p.cid, date_trunc('month', p.baixa_manual_em)::date mes, sum(p.valor) caiu
      from parc p
     where p.baixa_manual_em between v_de and v_fim
       and p.transacao_hotmart is null   -- a automática já está em caiu_hotmart (não conta duas vezes)
     group by 1, 2
  ), hm as (
    select s.cid, date_trunc('month', s.dia_aprovado)::date mes, sum(s.valor_oferta) bruto, sum(s.liquido) liquido
      from sinal s
     where s.dia_aprovado between v_de and v_fim
     group by 1, 2
  ), etp as (
    -- "a receber na etapa X": sem data, sem baixa — fora das células do mês
    select p.cid, sum(p.valor) total,
           jsonb_agg(jsonb_build_object('id', p.id, 'parcela_n', p.parcela_n, 'parcela_de', p.parcela_de,
                                        'valor', p.valor, 'etapa', p.etapa, 'situacao', 'a_receber_etapa')
                     order by p.parcela_n, p.id) parcelas
      from parc p
     where p.data_prevista is null and p.baixa_manual_em is null
     group by 1
  ), fech as (
    -- fecha no sinal pago (2026) ou, sem sinal (2025), na 1ª parcela baixada
    select c.id cid,
           coalesce((select min(s.dia_aprovado) from sinal s where s.cid = c.id),
                    (select min(p.baixa_manual_em) from parc p where p.cid = c.id and p.transacao_hotmart is null)) fechado_em
      from fin.contratos_hf c
  ), ativo as (
    -- arquivado só aparece se teve movimento no período (fusão/arquivo sem dinheiro some da grade)
    select c.id from fin.contratos_hf c
     where c.arquivado_em is null
        or exists (select 1 from esp where esp.cid = c.id)
        or exists (select 1 from bx where bx.cid = c.id)
        or exists (select 1 from hm where hm.cid = c.id)
  ), grade as (
    select a.id cid, m.mes::date mes
      from ativo a cross join generate_series(v_de, v_ate, interval '1 month') m(mes)
    union all
    select e.cid, null::date from etp e join ativo a on a.id = e.cid
  )
  select c.id, g.mes,
         c.nome, c.email, c.telefone, c.cidade, c.uf, case when v_cpf then c.cpf_final3 end,
         c.origem, c.transacao_sinal, c.data_assinatura, c.assinado, f.fechado_em,
         c.valor_bruto::numeric, c.valor_liquido::numeric, c.desconto_desc, c.entrada_valor::numeric, c.entrada_pct::numeric,
         c.link_contrato, c.observacao, c.arquivado_em,
         case when g.mes is not null then coalesce(esp.esperado, 0) end,
         case when g.mes is not null then coalesce(bx.caiu, 0) end,
         case when g.mes is not null then coalesce(hm.bruto, 0) end,
         case when g.mes is not null then coalesce(hm.liquido, 0) end,
         case when g.mes is not null then coalesce(bx.caiu, 0) + coalesce(hm.bruto, 0) end,
         case when g.mes is null then etp.total end,
         case when g.mes is null then 'a_receber_etapa'
              when esp.sit is not null then esp.sit
              when coalesce(bx.caiu, 0) + coalesce(hm.bruto, 0) > 0 then 'recebido_sem_parcela' end,
         case when g.mes is null then etp.parcelas else coalesce(esp.parcelas, '[]'::jsonb) end
    from grade g
    join fin.contratos_hf c on c.id = g.cid
    left join fech f on f.cid = g.cid
    left join esp on esp.cid = g.cid and esp.mes = g.mes
    left join bx  on bx.cid  = g.cid and bx.mes  = g.mes
    left join hm  on hm.cid  = g.cid and hm.mes  = g.mes
    left join etp on etp.cid = g.cid and g.mes is null
   order by c.nome, c.id, g.mes nulls last;
end $$;
comment on function public.fn_fin_contratos_hf_mensal(date, date) is
  'z93: contratos Holding Familiar × mês (grade densa, ≤ 36 meses; padrão = 5 meses atrás a 6 à frente). Por célula: '
  'esperado (parcelas com vencimento no mês), caiu (baixa manual + pagamentos HF na Hotmart no mês), situação (pior das parcelas). '
  'Linha com mes NULL = "a receber na etapa X" (parcelas sem data). Contato visível a quem vê o Financeiro; '
  'cpf_final3 só com gp_pode_ver_cpf().';
revoke all on function public.fn_fin_contratos_hf_mensal(date, date) from public, anon;
grant execute on function public.fn_fin_contratos_hf_mensal(date, date) to authenticated;

create function public.fn_fin_contrato_hf_salvar(p jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v_id    uuid;
  c       fin.contratos_hf;
  n       fin.contratos_hf;
  o       fin.contratos_hf;
  k       text;
  v_txt   text;
  v_num   numeric;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Envie o contrato como objeto.' using errcode = 'P0001';
  end if;
  for k in select jsonb_object_keys(p) loop
    if k <> all (array['id','valor_bruto','valor_liquido','desconto_desc','entrada_valor','entrada_pct',
                       'data_assinatura','assinado','link_contrato','observacao','transacao_sinal','arquivar_motivo']) then
      raise exception 'Campo desconhecido: "%".', k using errcode = 'P0001';
    end if;
  end loop;
  begin
    v_id := nullif(btrim(p ->> 'id'), '')::uuid;
  exception when others then
    raise exception 'Identificação do contrato inválida.' using errcode = 'P0001';
  end;
  if v_id is null then raise exception 'Informe o contrato (id).' using errcode = 'P0001'; end if;

  -- mesma ordem de trava em toda escrita que mexe em ficha E parcelas: ficha, depois informados
  perform pg_advisory_xact_lock(hashtext('fin.contratos_hf:escrita'));
  perform pg_advisory_xact_lock(hashtext('fin.recebimentos_informados:escrita'));
  select * into c from fin.contratos_hf x where x.id = v_id for update;
  if not found then raise exception 'Contrato não encontrado.' using errcode = 'P0001'; end if;
  if c.arquivado_em is not null then
    raise exception 'Contrato arquivado não se altera.' using errcode = 'P0001';
  end if;
  n := c;

  foreach k in array array['valor_bruto','valor_liquido','entrada_valor'] loop
    continue when not p ? k;
    v_txt := btrim(p ->> k);
    if v_txt is null or v_txt = '' then
      v_num := null;
    elsif v_txt !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' then
      raise exception 'Valor inválido em %: "%". Use número com ponto e até 2 casas (ex.: 44640.00).', k, v_txt
        using errcode = 'P0001';
    else
      v_num := v_txt::numeric;
    end if;
    if k <> 'entrada_valor' and v_num = 0 then
      raise exception 'Valor do contrato deve ser maior que zero (ou vazio).' using errcode = 'P0001';
    end if;
    case k when 'valor_bruto' then n.valor_bruto := v_num;
           when 'valor_liquido' then n.valor_liquido := v_num;
           else n.entrada_valor := v_num; end case;
  end loop;
  if p ? 'entrada_pct' then
    v_txt := btrim(p ->> 'entrada_pct');
    if v_txt is null or v_txt = '' then
      n.entrada_pct := null;
    elsif v_txt !~ '^[0-9]{1,3}(\.[0-9]{1,2})?$' or v_txt::numeric > 100 then
      raise exception 'Percentual de entrada inválido: "%" (0 a 100).', v_txt using errcode = 'P0001';
    else
      n.entrada_pct := v_txt::numeric;
    end if;
  end if;
  if p ? 'desconto_desc' then
    n.desconto_desc := nullif(btrim(p ->> 'desconto_desc'), '');
    if length(n.desconto_desc) > 200 then
      raise exception 'Descrição do desconto longa demais (até 200 caracteres).' using errcode = 'P0001';
    end if;
  end if;
  if p ? 'observacao' then
    n.observacao := nullif(btrim(p ->> 'observacao'), '');
    if length(n.observacao) > 2000 then
      raise exception 'Observação longa demais (até 2000 caracteres).' using errcode = 'P0001';
    end if;
  end if;
  if p ? 'data_assinatura' then
    n.data_assinatura := fin.informado_data(p ->> 'data_assinatura', 'Data de assinatura');
    if n.data_assinatura is not null
       and (n.data_assinatura < date '2020-01-01' or n.data_assinatura > v_hoje + 366) then
      raise exception 'Data de assinatura fora do intervalo: %.', n.data_assinatura using errcode = 'P0001';
    end if;
  end if;
  if p ? 'assinado' then
    n.assinado := btrim(p ->> 'assinado');
    if n.assinado is null or n.assinado not in ('sim','nao','indeterminado') then
      raise exception 'Assinado deve ser sim, nao ou indeterminado.' using errcode = 'P0001';
    end if;
  end if;
  if p ? 'link_contrato' then
    -- valida o que será exibido: só ASCII, só Google Docs/Drive, https (sem normalizar — texto que muda ao
    -- normalizar é recusado pela própria regex)
    n.link_contrato := nullif(btrim(p ->> 'link_contrato'), '');
    if n.link_contrato is not null
       and (length(n.link_contrato) > 500
            or n.link_contrato !~ '^https://(docs|drive)\.google\.com/[A-Za-z0-9/_?=&.%#-]*$') then
      raise exception 'Link do contrato inválido: use o link https do Google Docs/Drive.' using errcode = 'P0001';
    end if;
  end if;
  if p ? 'transacao_sinal' then
    v_txt := nullif(btrim(p ->> 'transacao_sinal'), '');
    if v_txt is distinct from c.transacao_sinal then
      if v_txt is null then
        if c.origem = 'hotmart_sinal' then
          raise exception 'Contrato criado pelo sinal não fica sem sinal: arquive-o.' using errcode = 'P0001';
        end if;
      else
        if length(v_txt) > 64 or v_txt !~ '^[A-Za-z0-9_-]+$' then
          raise exception 'Código de transação inválido.' using errcode = 'P0001';
        end if;
        -- pentest 29/09 (ALTO): a fusão só aceita pagamento HF PAGO cujo pagador tem o e-mail DESTA ficha. Sem bypass:
        -- e-mail diferente (ou ficha sem e-mail) é recusado; outro caminho, com papel mais alto, é decisão do dono.
        if not exists (select 1 from fin.vw_transacoes_escritorio t
                        where t.transacao = v_txt and t.produto_id = '5301413' and t.grupo = 'pago'
                          and c.email is not null and t.email = lower(c.email)) then
          raise exception 'Transação % recusada: tem de ser pagamento HF pago na conta do escritório por quem tem o e-mail desta ficha.',
            v_txt using errcode = 'P0001';
        end if;
        -- confirmação humana do casamento: a ficha criada sozinha pelo sinal (sem parcelas) é FUNDIDA nesta
        select * into o from fin.contratos_hf x where x.transacao_sinal = v_txt and x.id <> v_id for update;
        if found then
          if o.origem <> 'hotmart_sinal'
             or exists (select 1 from fin.recebimentos_informados r where r.contrato_id = o.id and r.arquivado_em is null) then
            raise exception 'Este sinal já pertence a outro contrato com dados próprios (%). Arquive-o antes.', o.id
              using errcode = 'P0001';
          end if;
          update fin.contratos_hf x
             set transacao_sinal = null,
                 arquivado_em = coalesce(x.arquivado_em, now()),
                 arquivado_por = coalesce(x.arquivado_por, v_uid),
                 arquivado_motivo = coalesce(x.arquivado_motivo, 'Fundido no contrato ' || v_id::text),
                 atualizado_em = now(), atualizado_por = v_uid
           where x.id = o.id;
        end if;
      end if;
      n.transacao_sinal := v_txt;
    end if;
  end if;
  if nullif(btrim(p ->> 'arquivar_motivo'), '') is not null then
    -- pentest 29/09 (2ª rodada): arquivar não pode ser um jeito de desfazer conciliação da Hotmart
    if exists (select 1 from fin.recebimentos_informados r where r.contrato_id = v_id and r.transacao_hotmart is not null) then
      raise exception 'Contrato não arquivado: tem pagamento da Hotmart conciliado: desfazer a conciliação não é permitido.'
        using errcode = 'P0001';
    end if;
    n.arquivado_motivo := btrim(p ->> 'arquivar_motivo');
    if length(n.arquivado_motivo) not between 3 and 500 then
      raise exception 'Motivo do arquivamento: de 3 a 500 caracteres.' using errcode = 'P0001';
    end if;
    n.arquivado_em := now();
    n.arquivado_por := v_uid;
  end if;

  if (n.valor_bruto, n.valor_liquido, n.desconto_desc, n.entrada_valor, n.entrada_pct, n.data_assinatura, n.assinado,
      n.link_contrato, n.observacao, n.transacao_sinal, n.arquivado_em)
     is not distinct from
     (c.valor_bruto, c.valor_liquido, c.desconto_desc, c.entrada_valor, c.entrada_pct, c.data_assinatura, c.assinado,
      c.link_contrato, c.observacao, c.transacao_sinal, c.arquivado_em) then
    return v_id;   -- nada mudou: sem escrita, sem linha de histórico
  end if;
  update fin.contratos_hf x
     set valor_bruto = n.valor_bruto, valor_liquido = n.valor_liquido, desconto_desc = n.desconto_desc,
         entrada_valor = n.entrada_valor, entrada_pct = n.entrada_pct, data_assinatura = n.data_assinatura,
         assinado = n.assinado, link_contrato = n.link_contrato, observacao = n.observacao,
         transacao_sinal = n.transacao_sinal,
         arquivado_em = n.arquivado_em, arquivado_por = n.arquivado_por, arquivado_motivo = n.arquivado_motivo,
         atualizado_em = now(), atualizado_por = v_uid
   where x.id = v_id;

  -- assinatura da ficha manda na certeza das parcelas vivas (bloco 7 da z73: assinado = certo; senão estimado)
  if n.assinado is distinct from c.assinado then
    update fin.recebimentos_informados r
       set contrato_assinado = (n.assinado = 'sim'), atualizado_por = v_uid, atualizado_em = now()
     where r.contrato_id = v_id and r.arquivado_em is null and r.transacao_hotmart is null   -- baixa automática: só o cron
       and r.contrato_assinado is distinct from (n.assinado = 'sim');
  end if;
  -- arquivar a ficha arquiva as parcelas vivas ainda não baixadas (as baixadas ficam: o dinheiro entrou)
  if n.arquivado_em is not null then
    update fin.recebimentos_informados r
       set arquivado_em = now(), arquivado_por = v_uid,
           motivo_arquivo = left('Contrato arquivado: ' || n.arquivado_motivo, 500),
           atualizado_por = v_uid, atualizado_em = now()
     where r.contrato_id = v_id and r.arquivado_em is null and r.baixa_manual_em is null;
  end if;
  return v_id;
end $$;
comment on function public.fn_fin_contrato_hf_salvar(jsonb) is
  'z93: edita a ficha do contrato HF (id obrigatório): valor_bruto, valor_liquido, desconto_desc, entrada_valor, '
  'entrada_pct, data_assinatura, assinado (sim|nao|indeterminado → contrato_assinado das parcelas vivas), link_contrato '
  '(https Google Docs/Drive), observacao, transacao_sinal (confirma o casamento; funde a ficha criada pelo sinal) e '
  'arquivar_motivo (arquiva a ficha e as parcelas vivas não baixadas). Campo ausente mantém o atual.';
revoke all on function public.fn_fin_contrato_hf_salvar(jsonb) from public, anon;
grant execute on function public.fn_fin_contrato_hf_salvar(jsonb) to authenticated;

-- Desfaz uma fusão (pentest 29/09, ALTO): a ficha p_id perde o transacao_sinal; a ficha criada pelo sinal que foi
-- arquivada "Fundido no contrato <p_id>" é reaberta com ele. As baixas automáticas NÃO são mexidas aqui: a revalidação
-- do próximo :25 (ou uma chamada a fin.contratos_hf_sincronizar) desfaz as que não casam mais com um contrato só.
create function public.fn_fin_contrato_hf_desfundir(p_id uuid, p_motivo text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_mot   text := btrim(p_motivo);
  c       fin.contratos_hf;
  o       fin.contratos_hf;
  v_tem_o boolean;
  v_tx    text;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_id is null then raise exception 'Informe o contrato.' using errcode = 'P0001'; end if;
  if v_mot is null or length(v_mot) not between 3 and 500 then
    raise exception 'Motivo da desfusão: de 3 a 500 caracteres.' using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('fin.contratos_hf:escrita'));
  perform pg_advisory_xact_lock(hashtext('fin.recebimentos_informados:escrita'));
  select * into c from fin.contratos_hf x where x.id = p_id for update;
  if not found then raise exception 'Contrato não encontrado.' using errcode = 'P0001'; end if;
  if c.arquivado_em is not null then
    raise exception 'Contrato arquivado não se altera.' using errcode = 'P0001';
  end if;
  if c.origem = 'hotmart_sinal' then
    raise exception 'Contrato criado pelo sinal: não há fusão a desfazer (arquive-o, se for o caso).' using errcode = 'P0001';
  end if;
  if c.transacao_sinal is null then
    raise exception 'Este contrato não tem sinal fundido.' using errcode = 'P0001';
  end if;
  v_tx := c.transacao_sinal;
  select * into o from fin.contratos_hf x
   where x.origem = 'hotmart_sinal' and x.transacao_sinal is null and x.arquivado_em is not null
     and x.arquivado_motivo = 'Fundido no contrato ' || p_id::text
   order by x.arquivado_em desc, x.id
   limit 1
   for update;
  v_tem_o := found;

  update fin.contratos_hf x set transacao_sinal = null, atualizado_em = now(), atualizado_por = v_uid where x.id = p_id;
  if v_tem_o then
    update fin.contratos_hf x
       set transacao_sinal = v_tx, arquivado_em = null, arquivado_por = null, arquivado_motivo = null,
           atualizado_em = now(), atualizado_por = v_uid
     where x.id = o.id;
  end if;
  insert into fin.contratos_hf_historico (contrato_id, acao, antes, depois, por, motivo)
  values (p_id, 'desfundir', jsonb_build_object('transacao_sinal', v_tx),
          jsonb_build_object('transacao_sinal', null, 'ficha_reaberta', case when v_tem_o then o.id end),
          v_uid, v_mot);
  return case when v_tem_o then o.id end;
end $$;
comment on function public.fn_fin_contrato_hf_desfundir(uuid, text) is
  'z93: desfaz a fusão de sinal na ficha p_id (operar; motivo 3–500, gravado no histórico): tira o transacao_sinal e '
  'reabre a ficha criada pelo sinal que foi fundida nela (devolve o id dela, ou NULL se não havia). Baixas automáticas: '
  'a revalidação do cron :25 desfaz as que não casam mais.';
revoke all on function public.fn_fin_contrato_hf_desfundir(uuid, text) from public, anon;
grant execute on function public.fn_fin_contrato_hf_desfundir(uuid, text) to authenticated;

create function public.fn_fin_parcela_etapa_concluir(p_id uuid, p_data date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
  v       fin.recebimentos_informados;
  v_data  date;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_id is null then raise exception 'Informe a parcela.' using errcode = 'P0001'; end if;
  if p_data is not null and (p_data > v_hoje or p_data < date '2020-01-01') then
    raise exception 'Conclusão da etapa fora do intervalo (de 2020 até hoje): %.', p_data using errcode = 'P0001';
  end if;
  perform pg_advisory_xact_lock(hashtext('fin.recebimentos_informados:escrita'));
  select * into v from fin.recebimentos_informados x where x.id = p_id for update;
  if not found then raise exception 'Parcela não encontrada.' using errcode = 'P0001'; end if;
  if v.arquivado_em is not null then
    raise exception 'Parcela arquivada não se altera.' using errcode = 'P0001';
  end if;
  if v.tipo <> 'contrato_holding_familiar' or v.etapa is null then
    raise exception 'Só parcela de contrato por etapa tem etapa a concluir.' using errcode = 'P0001';
  end if;
  if v.etapa_concluida_em is not distinct from p_data then return; end if;

  if p_data is not null then
    -- a data prevista vem da conclusão (se já havia data própria, fica a dela)
    v_data := case when v.data_prevista is null or v.data_prevista = v.etapa_concluida_em then p_data
                   else v.data_prevista end;
  else
    -- desfazer: volta a "a receber na etapa X" (sem data), se não foi baixada
    if v.baixa_manual_em is not null then
      raise exception 'Parcela já baixada: desfaça a baixa antes de reabrir a etapa.' using errcode = 'P0001';
    end if;
    v_data := case when v.data_prevista = v.etapa_concluida_em then null else v.data_prevista end;
  end if;
  update fin.recebimentos_informados x
     set etapa_concluida_em = p_data, data_prevista = v_data, atualizado_por = v_uid, atualizado_em = now()
   where x.id = p_id;
end $$;
comment on function public.fn_fin_parcela_etapa_concluir(uuid, date) is
  'z93: marca a etapa da parcela de contrato HF como concluída em p_data (≤ hoje): a parcela ganha data prevista = '
  'p_data e entra na previsão. p_data NULL desfaz (parcela volta a ficar sem data; recusa se já baixada).';
revoke all on function public.fn_fin_parcela_etapa_concluir(uuid, date) from public, anon;
grant execute on function public.fn_fin_parcela_etapa_concluir(uuid, date) to authenticated;


create function public.fn_fin_contratos_hf_pagamentos(p_so_fila boolean default true)
returns table (transacao text, dia date, valor numeric, nome_hotmart text, email_hotmart text,
               contrato_id uuid, contrato_nome text, situacao text, motivo text,
               informado_id uuid, parcela_n int, parcela_de int, atualizado_em timestamptz,
               sync_ultima_em timestamptz, sync_erros int, sync_mensagem text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select pg.transacao, pg.dia, pg.valor::numeric, t.nome, t.email, pg.contrato_id, c.nome, pg.situacao, pg.motivo,
         pg.informado_id, i.parcela_n, i.parcela_de, pg.atualizado_em,
         st.ultima_em, st.erros, st.mensagem
    from fin.contratos_hf_pagamentos pg
    left join fin.contratos_hf_sync_status st on st.id = 1
    left join fin.vw_transacoes_escritorio t on t.transacao = pg.transacao
    left join fin.contratos_hf c on c.id = pg.contrato_id
    left join fin.recebimentos_informados i on i.id = pg.informado_id
   where not coalesce(p_so_fila, true) or pg.situacao = 'fila'
   order by pg.dia desc nulls last, pg.transacao;
end $$;
comment on function public.fn_fin_contratos_hf_pagamentos(boolean) is
  'z93: conciliação dos pagamentos HF da Hotmart. p_so_fila (padrão) = só a fila de conferência (o que não casou, com o '
  'motivo); false = tudo (baixou_parcela, entrada, fila, estornado). sync_* = última sincronização (cron :25): '
  'quando, quantos erros e as mensagens — repetidos em toda linha. Leitura: gp_pode_ver_financeiro().';
revoke all on function public.fn_fin_contratos_hf_pagamentos(boolean) from public, anon;
grant execute on function public.fn_fin_contratos_hf_pagamentos(boolean) to authenticated;


-- ─── 6. Conferência (falha → desfaz tudo) ───────────────────────────────────────────────────────────────────────────
do $conf$
declare
  t text;
begin
  -- tabelas: RLS ligado e nenhum grant para public/anon/authenticated
  foreach t in array array['fin.contratos_hf','fin.contratos_hf_historico','fin.contratos_hf_pagamentos',
                            'fin.contratos_hf_sync_status'] loop
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception 'z93: RLS desligado em %', t;
    end if;
    if exists (select 1 from pg_class c, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
                where c.oid = t::regclass and a.grantee in (0::oid, 'anon'::regrole::oid, 'authenticated'::regrole::oid)) then
      raise exception 'z93: grant aberto em %', t;
    end if;
  end loop;
  -- funções internas fechadas; RPCs sem PUBLIC/anon e com authenticated; todas SECURITY DEFINER com search_path ''
  if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid in ('fin.contratos_hf_sincronizar()'::regprocedure, 'fin.tg_contratos_hf_historico()'::regprocedure,
                              'fin.contratos_hf_transacoes()'::regprocedure,
                              'fin.contratos_hf_ficha_nova_vazia(uuid,timestamptz)'::regprocedure,
                              'fin.tg_informados_baixa_hotmart_trava()'::regprocedure,
                              'fin.tg_contratos_hf_nao_apaga()'::regprocedure,
                              'fin.tg_contratos_hf_historico_so_acrescimo()'::regprocedure)
                and a.grantee in (0::oid, 'anon'::regrole::oid, 'authenticated'::regrole::oid)) then
    raise exception 'z93: função interna com grant aberto';
  end if;
  if exists (select 1 from pg_proc p, aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
              where p.oid in ('public.fn_fin_contratos_hf_mensal(date,date)'::regprocedure,
                              'public.fn_fin_contrato_hf_salvar(jsonb)'::regprocedure,
                              'public.fn_fin_parcela_etapa_concluir(uuid,date)'::regprocedure,
                              'public.fn_fin_informados_listar()'::regprocedure,
                              'public.fn_fin_contratos_hf_pagamentos(boolean)'::regprocedure,
                              'public.fn_fin_contrato_hf_desfundir(uuid,text)'::regprocedure)
                and a.grantee in (0::oid, 'anon'::regrole::oid))
     or (select count(*) from pg_proc p
          where p.oid in ('public.fn_fin_contratos_hf_mensal(date,date)'::regprocedure,
                          'public.fn_fin_contrato_hf_salvar(jsonb)'::regprocedure,
                          'public.fn_fin_parcela_etapa_concluir(uuid,date)'::regprocedure,
                          'public.fn_fin_informados_listar()'::regprocedure,
                          'public.fn_fin_contratos_hf_pagamentos(boolean)'::regprocedure,
                          'public.fn_fin_contrato_hf_desfundir(uuid,text)'::regprocedure)
            and p.prosecdef and p.proconfig = array['search_path=""']
            and has_function_privilege('authenticated', p.oid, 'execute')) <> 6 then
    raise exception 'z93: ACL/atributos das RPCs fora do molde';
  end if;
  -- trava da conta Hotmart continua ligada (z89) e nenhum objeto novo a viola
  if not exists (select 1 from pg_event_trigger where evtname = 'trava_conta_hotmart' and evtenabled <> 'D') then
    raise exception 'z93: event trigger trava_conta_hotmart desligado';
  end if;
  if (select command from cron.job where jobname = 'fin-oferta-evento-resolver') !~ '^select fin\.contratos_hf_sincronizar\(\); ' then
    raise exception 'z93: cron não ganhou a sincronização';
  end if;
  if exists (select 1 from fin.recebimentos_informados r
              where r.tipo <> 'contrato_holding_familiar' and (r.contrato_id is not null or r.etapa is not null)) then
    raise exception 'z93: linha de outro tipo com contrato/etapa';
  end if;
end $conf$;
