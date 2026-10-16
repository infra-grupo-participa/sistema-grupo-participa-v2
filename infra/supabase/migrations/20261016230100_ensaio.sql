-- Ensaio de 20261016230000 + 230100 + 230200 numa transação DESFEITA (rollback). Sem dado pessoal: e-mail fictício .invalid.
-- Rodar: python3 <executor que só aceita arquivo terminado em rollback> este arquivo. Resultado do ensaio de 16/10/2026: ver 20261016230100.explain.md
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '00 antes de tudo', (select jsonb_build_object(
  'hotmart_linhas', count(*) filter (where e.ref_tipo = 'hotmart.transacao'),
  'grupos_duplicados', (select count(*) from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x),
  'hotmart_sem_evento_id', count(*) filter (where e.ref_tipo = 'hotmart.transacao' and e.evento_id is null),
  'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio')) from pessoas.eventos e)::text;
-- ===== 20261016230000 (sem concurrently, dentro da transação do ensaio) =====
create index if not exists eventos_hotmart_ref_idx on pessoas.eventos (ref_id, tipo) where ref_tipo = 'hotmart.transacao';
-- ===== 20261016230100 =====
-- 20261016230100: setor pelo produto e idempotência da linha do tempo da Hotmart (pessoa única)
--
-- STATUS: NÃO APLICADA. Terminal Hotmart (back-end-sr), 16/10/2026, branch victor-hotmart-setor. Depende de 20261016230000 (índice).
-- ORDEM: aplicar ANTES da 230200 (a limpeza só fica limpa se o webhook já parou de duplicar).
-- POR QUE (medido em 16/10/2026):
--   1) a carga marcava pela conta e não pelo setor: SV e Croqui vendidos na academy caíram em evento de educação (2 linhas: 1 Croqui em
--      encontro_thb, 1 em holding_total) e a conta escritório nunca recebe evento (fin.trajetoria_nucleo só lê a academy);
--   2) 13 grupos (26 linhas: 7 checkout e 6 reembolso) com o mesmo ref_id e tipo: 6 webhook x carga e 7 webhook x webhook (duas
--      ingestões, 'webhook' e 'sync', com chaves diferentes em crm.hotmart_processado; o passo 3 sempre inserindo).
-- O QUE FAZ (3 funções; nenhuma tabela, view, policy ou grant de tabela alterado):
--   pessoas.hotmart_setor(produto)        NOVA. 'escritorio' para família ESCRITORIO/ESCRITORIO_SOLUCOES; senão null.
--   pessoas.carga_fin_hotmart(...)        MESMA assinatura (create or replace, sem sobrecarga). Mudanças: grava detalhe.setor; evento de
--                                         educação nunca fica em venda de escritório (vira null; evento de setor escritório fica);
--                                         conta escritório e vendas de escritório não passam mais por fin.trajetoria_nucleo; a
--                                         reivindicação da linha do webhook também grava o setor. O resto é igual ao corpo vigente.
--   crm.hotmart_processar(jsonb)          MESMA assinatura. SÓ o passo 3 muda: antes de inserir confere se já existe linha do mesmo ref_id e
--                                         tipo (lock de aviso por transação+tipo contra duas entregas ao mesmo tempo) e grava detalhe.setor.
--                                         Passos 1, 2 e 4 em diante idênticos ao corpo vigente (pg_get_functiondef de 16/10/2026).
-- QUEM LÊ (grep nos repos e no banco, 16/10): leitores de pessoas.eventos tipo compra/checkout/reembolso usam só tipo, quando e pessoa
--   (crm.contatos_metricas: max(quando); crm_jornada lê a Hotmart direto do financeiro). Nenhum lê fonte_id, evento_id ou detalhe.setor.
-- AS 5 PERGUNTAS: escala = uma consulta por índice por webhook (~dezenas/hora) e por transação na carga; índice = 20261016230000
--   (Index Scan no ensaio); frequência = por evento de venda; repetição = a mesma transação em duas ingestões agora grava uma só;
--   reversão = 20261016230100_reversao.sql (volta os corpos vigentes de 16/10 e remove a função nova; linhas já gravadas ficam).
-- ENSAIO: 20261016230100_ensaio.sql (transação desfeita). Detalhe: 20261016230100.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('pessoas.eventos_hotmart_ref_idx') and i.indisvalid and i.indisready) then
    raise exception '20261016230100: falta o índice eventos_hotmart_ref_idx (20261016230000) existente, válido e pronto; sem ele cada consulta varre a tabela';
  end if;
  if (select count(*) from fin.produtos where familia in ('ESCRITORIO', 'ESCRITORIO_SOLUCOES')) <> 6 then
    raise exception '20261016230100: esperava 6 produtos de escritório em fin.produtos (medido em 16/10); revisar antes de aplicar';
  end if;
end $g$;

create or replace function pessoas.hotmart_setor(p_produto_id text)
 returns text
 language sql
 stable
 set search_path = ''
as $f$
  -- 'escritorio' quando o produto é de família ESCRITORIO (SV, Croqui e SV com a Elaine vendidos na conta academy) ou ESCRITORIO_SOLUCOES
  -- (conta escritório). Qualquer outro produto devolve null: NÃO afirma 'educacao' (a família OUTROS inclui itens a confirmar, como o
  -- produto 3595938 Holding Familiar).
  select 'escritorio'::text from fin.produtos p where p.produto_id = p_produto_id and p.familia in ('ESCRITORIO', 'ESCRITORIO_SOLUCOES')
$f$;
revoke all on function pessoas.hotmart_setor(text) from public, anon, authenticated;
comment on function pessoas.hotmart_setor(text) is '20261016230100: setor pelo produto (fin.produtos.familia). escritorio ou null.';

CREATE OR REPLACE FUNCTION pessoas.carga_fin_hotmart(p_execucao bigint, p_conta text, p_limite integer DEFAULT 1000, p_novos boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- Uma execução por conta (fontes hotmart_academy e hotmart_escritorio). Toda leitura da tabela de transações segue a forma
-- canônica que a trava fin.trava_conta_hotmart exige (regra 9 do plano de ação): (select * from ... where conta = p_conta).
-- A trava conta o nome da tabela até dentro de texto; por isso o valor de fonte_tabela é montado por concatenação (v_tab).
-- 20261016230100: o setor vem do PRODUTO (pessoas.hotmart_setor), não da conta: venda de SV/Croqui na conta academy é escritório e não
--   recebe evento de educação; a conta escritório não passa mais pelo fin.trajetoria_nucleo (que só lê a academy e nunca devolvia nada).
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_tipo text; v_ev bigint; v_setor text;
  v_tab constant text := 'fin.hotmart' || '_transacoes';
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  if p_conta not in ('academy', 'escritorio') then raise exception 'conta inválida' using errcode = '22023'; end if;
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'hotmart_' || p_conta), '');
  if p_limite not between 1 and 2000 then raise exception 'limite entre 1 e 2.000' using errcode = '22023'; end if;
  create temp table if not exists _carga_hm_lote (transacao text primary key) on commit drop;
  create temp table if not exists _carga_hm_ev (transacao text primary key, evento_id bigint) on commit drop;
  delete from pg_temp._carga_hm_lote; delete from pg_temp._carga_hm_ev;
  insert into pg_temp._carga_hm_lote
  select t.transacao from (select * from fin.hotmart_transacoes where conta = p_conta) t
   where (not p_novos and t.transacao > v_cur)
      or (p_novos and not exists (select 1 from pessoas.eventos e
                                   where e.fonte_tabela = v_tab and e.fonte_id = t.transacao
                                     and e.tipo = case when t.status in ('COMPLETE', 'APPROVED') then 'compra'
                                                       when t.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                                                       else 'checkout' end))
   order by t.transacao limit p_limite;
  -- evento pela regra do financeiro (mesma janela/oferta que os funis usam), por lote de e-mails. Só conta academy (a regra só lê ela)
  -- e sem as vendas de produto de escritório (o evento delas é de educação e seria descartado abaixo).
  if p_conta = 'academy' then
    insert into pg_temp._carga_hm_ev
    select distinct on (j.transacao) j.transacao, j.evento_id
      from fin.trajetoria_nucleo(array(select distinct lower(btrim(t.comprador_email))
                                         from (select * from fin.hotmart_transacoes where conta = p_conta) t
                                         join pg_temp._carga_hm_lote l using (transacao)
                                        where t.comprador_email is not null and pessoas.hotmart_setor(t.produto_id) is null)) j
      join pg_temp._carga_hm_lote l on l.transacao = j.transacao
     where j.evento_id is not null
     order by j.transacao;
  end if;

  for r in select t.* from (select * from fin.hotmart_transacoes where conta = p_conta) t
             join pg_temp._carga_hm_lote l using (transacao) order by t.transacao loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.transacao); v_ate := r.transacao;
    v := pessoas._casar_email_seguro(r.comprador_nome, r.comprador_email, r.comprador_telefone, 'hotmart');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_tipo := case when r.status in ('COMPLETE', 'APPROVED') then 'compra'
                   when r.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                   else 'checkout' end;
    v_ev := null;
    select e.evento_id into v_ev from pg_temp._carga_hm_ev e where e.transacao = r.transacao;
    v_setor := pessoas.hotmart_setor(r.produto_id);
    if v_setor = 'escritorio' and v_ev is not null
       and not exists (select 1 from fin.eventos fe where fe.id = v_ev and fe.setor = 'escritorio') then v_ev := null; end if;
    -- a linha que o webhook já gravou desta transação/tipo recebe a fonte (uma só), em vez de criar outra
    update pessoas.eventos x set fonte_tabela = v_tab, fonte_id = r.transacao, evento_id = coalesce(x.evento_id, v_ev),
           detalhe = case when v_setor is not null then x.detalhe || jsonb_build_object('setor', v_setor) else x.detalhe end
     where x.id = (select min(y.id) from pessoas.eventos y
                    where y.ref_tipo = 'hotmart.transacao' and y.ref_id = r.transacao and y.tipo = v_tipo and y.fonte_id is null)
       and not exists (select 1 from pessoas.eventos z where z.fonte_tabela = v_tab and z.fonte_id = r.transacao and z.tipo = v_tipo);
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, v_tipo, 'hotmart', v_ev, 'hotmart.transacao', left(r.transacao, 80), v_tab, left(r.transacao, 120),
            coalesce(r.aprovado_em, r.pedido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('conta', p_conta, 'produto', left(r.produto_id, 40),
                                                 'oferta', left(r.oferta_codigo, 40), 'status', left(r.status, 30), 'setor', v_setor)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $function$;

CREATE OR REPLACE FUNCTION crm.hotmart_processar(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_chave text := p ->> 'chave';
  v_classe text := p ->> 'classe';
  v_tx text := p ->> 'transacao';
  v_quando timestamptz := coalesce((p ->> 'quando')::timestamptz, now());
  v_desde timestamptz;
  v_email text := pessoas.norm_email(p ->> 'email');
  v_tel text := pessoas.norm_telefone(p ->> 'telefone');
  v_nome text := nullif(left(btrim(coalesce(p ->> 'nome', '')), 160), '');
  v_ins int; v_res jsonb; v_pessoa uuid; v_atual uuid; v_g uuid[];
  pc crm.produto_comercial%rowtype; v_linha_nome text; v_oferta text; v_orfa boolean := false; v_valor numeric;
  n crm.negocio%rowtype; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pcid uuid; v_camp uuid; v_neg uuid;
  v_tipo_ev text; v_det jsonb;
  v_criados int := 0; v_abertos int := 0; v_funis int := 0; v_resultado text; v_rotulo text; v_sinc boolean;
begin
  -- 1. idempotência (PK). Reprocesso explícito ('forcar') reaproveita a linha.
  if coalesce((p ->> 'forcar')::boolean, false) then
    update crm.hotmart_processado x set resultado = 'processando', processado_em = now(), tentativas = x.tentativas + 1
     where x.chave = v_chave;
  else
    insert into crm.hotmart_processado (chave, fonte, ref, conta, classe, transacao, produto_id, oferta_codigo, quando)
    values (v_chave, p ->> 'fonte', p ->> 'ref', p ->> 'conta', v_classe, v_tx, p ->> 'produto_id', p ->> 'oferta_codigo', v_quando)
    on conflict (chave) do nothing;
    get diagnostics v_ins = row_count;
    if v_ins = 0 then return 'duplicado'; end if;
  end if;

  perform set_config('crm.canal', 'hotmart', true); -- crm.tg_log: autor_tipo 'integracao'
  select c.hotmart_desde into v_desde from crm.config c; -- crm.hotmart_entrada garante não nulo

  -- 2. pessoa por e-mail (F0). Sem e-mail não há pessoa (o webhook sempre manda; medido 0 sem e-mail em PURCHASE_*).
  if v_email is null then
    v_resultado := 'sem_email';
  elsif v_quando < v_desde - interval '1 hour' and v_classe <> 'reembolso' and v_classe <> 'chargeback' then
    v_resultado := 'antes_do_corte'; -- D8: sem retroativo (reembolso de venda antiga ainda marca o negócio, se houver)
  end if;
  if v_resultado is not null then
    update crm.hotmart_processado x set resultado = v_resultado where x.chave = v_chave;
    return v_resultado;
  end if;

  v_res := pessoas.resolver(v_nome, v_email, v_tel, null, false, null);
  v_pessoa := (v_res ->> 'pessoa_id')::uuid;
  perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, 'hotmart');
  if v_tel is not null then perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), 'hotmart'); end if;
  v_atual := pessoas.atual(v_pessoa);
  v_g := pessoas.grupo(v_atual);

  -- 3. jornada da pessoa (toda classe, todo produto das 2 contas)
  -- 20261016230100: idempotente por (transação, tipo). O mesmo ref_id e tipo chegava por duas ingestões (webhook e varredura 'sync',
  --   chaves diferentes em crm.hotmart_processado) e virava duas linhas (13 grupos medidos em 16/10). Agora, se já existe linha
  --   desta transação e tipo (do webhook OU da carga pessoas.carga_fin_hotmart), não grava outra. A linha segue sem fonte_id: a carga
  --   continua reivindicando e preenchendo o evento_id dela. A marca de setor sai do produto, não da conta.
  v_tipo_ev := case when v_classe = 'aprovada' then 'compra'
                    when v_classe in ('reembolso', 'chargeback', 'disputa') then 'reembolso' else 'checkout' end;
  if v_tx is not null then
    perform pg_advisory_xact_lock(hashtext('hotmart.evento:' || left(v_tx, 80) || ':' || v_tipo_ev));
  end if;
  if v_tx is null
     or not exists (select 1 from pessoas.eventos y
                     where y.ref_tipo = 'hotmart.transacao' and y.ref_id = left(v_tx, 80) and y.tipo = v_tipo_ev) then
    v_det := jsonb_strip_nulls(jsonb_build_object('classe', v_classe, 'conta', p ->> 'conta', 'produto', p ->> 'produto_id',
                            'oferta', p ->> 'oferta_codigo', 'valor', p -> 'valor', 'metodo', p ->> 'metodo',
                            'recorrencia', p -> 'recorrencia', 'sck', p ->> 'sck', 'casou_por', v_res ->> 'como',
                            'setor', pessoas.hotmart_setor(p ->> 'produto_id')));
    insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe, quando)
    values (v_atual, v_tipo_ev,
            'hotmart', case when v_tx is not null then 'hotmart.transacao' else 'hotmart.evento' end,
            left(coalesce(v_tx, p ->> 'ref'), 80), v_det, v_quando);
  end if;

  -- 4. camada comercial: só produto vinculado ao comercial com linha
  -- 20261008z01: vínculo por OFERTA (crm.oferta_linha, ativo) tem precedência sobre o do produto
  select p ->> 'produto_id', true, ol.nome_comercial, ol.linha, l.escada, ol.agrupador_id, ol.vinculado_por, ol.vinculado_em
    into pc
    from crm.oferta_linha ol join crm.linha l on l.chave = ol.linha
   where ol.oferta_codigo = p ->> 'oferta_codigo' and ol.ativo;
  if not found then
    select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
  end if;
  if not found then
    update crm.hotmart_processado x set resultado = 'jornada: produto fora do comercial', pessoa_id = v_atual where x.chave = v_chave;
    return 'jornada: produto fora do comercial';
  end if;
  select l.nome into v_linha_nome from crm.linha l where l.chave = pc.linha;

  -- oferta: só entra no negócio se estiver no catálogo (FK fin.ofertas). Fora = aviso (catalogar no mesmo dia).
  if p ->> 'oferta_codigo' is not null then
    select o.oferta_codigo into v_oferta from fin.ofertas o where o.oferta_codigo = p ->> 'oferta_codigo';
    if v_oferta is null then
      v_orfa := true;
      select pr.sincroniza into v_sinc from fin.produtos pr where pr.produto_id = pc.produto_id;
      perform crm.slack_enfileirar('oferta_orfa', p ->> 'oferta_codigo',
        -- 20261007a: aviso sem dado de pessoa (nunca teve), agora com link para Produtos
        format(':label: *Oferta fora do catálogo* · %s · oferta %s (conta %s) · catalogar hoje%s · <https://grupoparticipa.app.br/comercial/produtos|Abrir Produtos>',
               crm.slack_esc(coalesce(pc.nome_comercial, v_linha_nome)), crm.slack_esc(p ->> 'oferta_codigo'),
               crm.slack_esc(p ->> 'conta'),
               case when coalesce(v_sinc, false) then '' else ' (o produto está com sincronização de ofertas desligada no Financeiro)' end));
    end if;
  end if;
  v_valor := coalesce((p ->> 'valor')::numeric,
                      (select o.preco from fin.ofertas o where o.oferta_codigo = v_oferta),
                      (select l.ticket_ref from crm.linha l where l.chave = pc.linha), 0);
  v_valor := greatest(round(v_valor, 2), 0);

  -- 5. por classe
  if v_classe = 'aprovada' then
    if coalesce((p ->> 'recorrencia')::numeric, 1) > 1 then
      v_resultado := 'jornada: recorrência ' || (p ->> 'recorrencia') || ' não é venda nova';
    elsif v_tx is null then
      v_resultado := 'jornada: aprovada sem transação';
    elsif exists (select 1 from crm.negocio x where x.transacao_ganho = v_tx) then
      v_resultado := 'ja_ganho';
    else
      -- 20261007e: compra de produto da OFERTA de um projeto fecha o negócio de ATIVAÇÃO dele (mesmo dono);
      -- funil de ativação fica fora da regra geral por linha (o ingresso tem a linha do projeto e não é ganho)
      select x.* into n from crm.negocio x join crm.projeto_ativacao pa on pa.funil_id = x.funil_id
        join crm.funil fx on fx.id = x.funil_id and fx.ativo
       where x.pessoa_id = any(v_g) and x.status = 'aberto' and (p ->> 'produto_id') = any(pa.hotmart_oferta)
       order by x.criado_em, x.id
       limit 1 for update of x;
      if not found then
        select * into n from crm.negocio x
         where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
           and not exists (select 1 from crm.projeto_ativacao pa where pa.funil_id = x.funil_id)
           and exists (select 1 from crm.funil fx where fx.id = x.funil_id and fx.ativo)
         order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
         limit 1 for update;
      end if;
      if found then
        select e.id into v_etapa from crm.etapa_funil e
         where e.funil_id = n.funil_id and e.papel = 'fechado' and e.arquivada_em is null;
        perform set_config('crm.resumo', format('Venda aprovada na Hotmart (transação %s): negócio ganho', v_tx), true);
        perform set_config('crm.ganho_hotmart', 'on', true);
        update crm.negocio x
           set status = 'ganho', etapa_id = v_etapa, etapa_desde = now(), fechado_em = v_quando, transacao_ganho = v_tx,
               valor = v_valor, oferta_codigo = coalesce(v_oferta, x.oferta_codigo), ultima_interacao_em = now(),
               atualizado_em = now()
         where x.id = n.id;
        perform set_config('crm.ganho_hotmart', 'off', true);
        v_neg := n.id; v_resultado := 'ganho';
      else
        -- 20261006191824 (D8, decisão do Victor 06/10/2026): compra aprovada SEM negócio aberto da pessoa na linha
        -- NÃO cria negócio ganho nem contato comercial. A compra fica na jornada (pessoas.eventos tipo 'compra',
        -- gravado no passo 3, e crm_jornada lê as transações do financeiro). Ganho no CRM = venda que o comercial trabalhou.
        v_resultado := 'jornada: compra sem negócio aberto (não cria ganho)';
      end if;
    end if;

  elsif v_classe in ('carrinho_abandonado', 'compra_em_aberto', 'cartao_recusado', 'expirada') then
    if v_quando < now() - interval '48 hours' then
      v_resultado := 'jornada: checkout com mais de 48 h';
    elsif exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = any(v_g) and x.opt_out) then
      v_resultado := 'jornada: opt-out';
    elsif exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'ganho'
                     and x.fechado_em > now() - interval '30 days')
       or exists (select 1 from pessoas.eventos e
                   where e.pessoa_id = any(v_g) and e.tipo = 'compra' and e.fonte = 'hotmart'
                     and e.quando > now() - interval '30 days'
                     -- 20261008z01: a compra conta pela linha da OFERTA (se vinculada), senão pela do produto
                     and coalesce((select ol.linha from crm.oferta_linha ol where ol.oferta_codigo = e.detalhe ->> 'oferta' and ol.ativo),
                                  (select y.linha from crm.produto_comercial y
                                    where y.produto_id = e.detalhe ->> 'produto' and y.no_comercial)) = pc.linha) then
      -- 20261006191824: compra direta não vira mais negócio ganho; a compra na jornada também conta
      v_resultado := 'jornada: já comprou a linha em 30 dias';
    else
      for f in select x.* from crm.funil x
                where x.ativo and x.tipo = 'hotmart' and x.linha = pc.linha and v_classe = any(x.eventos_hotmart)
                  and (pc.agrupador_id is null or x.agrupador_id = pc.agrupador_id)
                order by x.criado_em, x.id loop
        v_funis := v_funis + 1;
        perform pg_advisory_xact_lock(hashtext('crm.dist:' || f.id::text)); -- mesmo lock de crm_criar_negocio (F2)
        if exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.funil_id = f.id and x.status = 'aberto') then
          v_abertos := v_abertos + 1;
          continue;
        end if;
        select e.id into v_etapa from crm.etapa_funil e where e.funil_id = f.id and e.arquivada_em is null order by e.ordem limit 1;
        continue when v_etapa is null;
        v_dono := crm.escolher_dono(v_atual, f.id);
        v_pcid := crm.garantir_pc(v_atual);
        if v_dono is not null then
          perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição, Hotmart)', crm.nome_pessoa(v_atual), crm.nome_perfil(v_dono)), true);
          update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pcid and x.dono_id is null;
        end if;
        select c.id into v_camp from crm.campanha c where c.funil_id = f.id and c.ativa and c.canal = 'hotmart' order by c.criado_em limit 1;
        v_rotulo := case v_classe when 'carrinho_abandonado' then 'carrinho abandonado' when 'compra_em_aberto' then 'boleto/pix gerado'
                                  when 'cartao_recusado' then 'cartão recusado' else 'pagamento expirado' end;
        perform set_config('crm.resumo', format('Hotmart: %s → negócio em %s (dono: %s)', v_rotulo, f.nome, crm.nome_perfil(v_dono)), true);
        insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, oferta_codigo, campos, utm,
                                 ultima_interacao_em)
        values (v_atual, f.id, v_etapa, v_camp, pc.linha, v_classe, v_dono, v_valor, v_oferta,
                jsonb_build_object('origem', 'Hotmart · ' || v_rotulo),
                case when p ->> 'sck' is not null then jsonb_build_object('sck', p ->> 'sck') else '{}'::jsonb end, null)
        returning id into v_neg;
        v_criados := v_criados + 1;
      end loop;
      v_resultado := case when v_criados > 0 then 'negocio_criado: ' || v_criados
                          when v_abertos > 0 then 'ja_aberto'
                          when v_funis = 0 then 'jornada: nenhum funil hotmart da linha escuta ' || v_classe
                          else 'jornada: funil sem etapa' end;
    end if;

  elsif v_classe in ('reembolso', 'chargeback') then
    perform set_config('crm.resumo', format('Hotmart: %s da transação %s', v_classe, coalesce(v_tx, '?')), true);
    update crm.negocio x set reembolsado_em = coalesce(x.reembolsado_em, now()), atualizado_em = now()
     where v_tx is not null and x.transacao_ganho = v_tx and x.reembolsado_em is null
     returning * into n;
    if found then
      v_neg := n.id; v_resultado := v_classe || '_marcado';
      -- 20261007a (decisão do Arthur 07/10/2026): aviso no Slack sem nome nem e-mail da pessoa; resumo + link da ficha
      perform crm.slack_enfileirar(v_classe, coalesce(v_tx, v_chave),
        crm.slack_texto_negocio(':rotating_light:', case when v_classe = 'reembolso' then 'Reembolso' else 'Chargeback' end,
                                n.id, coalesce(v_linha_nome, pc.linha), pc.nome_comercial, p ->> 'metodo'));
    else
      v_resultado := 'jornada: sem negócio ganho desta transação';
    end if;

  elsif v_classe = 'disputa' then
    select * into n from crm.negocio x where v_tx is not null and x.transacao_ganho = v_tx;
    if found then
      v_neg := n.id; v_resultado := 'disputa_avisada';
      -- 20261007a: idem (sem nome nem e-mail)
      perform crm.slack_enfileirar('disputa', coalesce(v_tx, v_chave),
        crm.slack_texto_negocio(':warning:', 'Disputa aberta na Hotmart',
                                n.id, coalesce(v_linha_nome, pc.linha), pc.nome_comercial, p ->> 'metodo'));
    else
      v_resultado := 'jornada: disputa sem negócio ganho';
    end if;
  end if;

  perform set_config('crm.resumo', '', true);
  update crm.hotmart_processado x
     set resultado = left(coalesce(v_resultado, 'ok'), 300), pessoa_id = v_atual, negocio_id = v_neg, oferta_orfa = v_orfa
   where x.chave = v_chave;
  return v_resultado;
end
$function$;

insert into pg_temp._z_out(passo, linha) select '01 depois da 230100 (A)', (select jsonb_build_object(
  'hotmart_linhas', count(*) filter (where e.ref_tipo = 'hotmart.transacao'),
  'grupos_duplicados', (select count(*) from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x),
  'hotmart_sem_evento_id', count(*) filter (where e.ref_tipo = 'hotmart.transacao' and e.evento_id is null),
  'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio')) from pessoas.eventos e)::text;
insert into pg_temp._z_out(passo, linha) select '01b depois da 230100: pendências da 230200 (A)', (select jsonb_build_object(
  'escritorio_sem_setor', (select count(*) from pessoas.eventos e where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio'),
  'escritorio_com_evento_educacao', (select count(*) from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'),
  'backup_existe', (select count(*) from pg_class where relname = 'pessoas__eventos__20261016')))::text;
do $x$
declare r text; v_ref text;
begin
  select ref_id into v_ref from pessoas.eventos where ref_tipo = 'hotmart.transacao' and fonte_id is null limit 1;
  for r in execute format('explain (analyze, buffers) select min(y.id) from pessoas.eventos y where y.ref_tipo = %L and y.ref_id = %L and y.tipo = %L and y.fonte_id is null', 'hotmart.transacao', v_ref, 'compra') loop
    insert into pg_temp._z_out(passo, linha) values ('02 explain do claim e da conferência de idempotência', r);
  end loop;
end $x$;
insert into pg_temp._z_out(passo, linha) select '03 relogio antes da 230200', clock_timestamp()::text;
-- ===== 20261016230200 =====
-- 20261016230200: corrige os eventos Hotmart já gravados na linha do tempo (duplicados, evento de educação em venda de escritório, setor)
--
-- STATUS: NÃO APLICADA. Terminal Hotmart (back-end-sr), 16/10/2026, branch victor-hotmart-setor. Depende de 20261016230000 e 20261016230100.
-- REVISADA após o pentest de 16/10 (PENTEST-HOTMART-SETOR-2026-10-16.md): guarda de premissa exata, pós-condição, backup do passo 3 e
--   guarda de índice válido.
-- ORDEM: depois da 230100 (senão o webhook recria duplicata no meio da limpeza).
-- POR QUE (medido em 16/10/2026): 13 grupos de linhas com o mesmo ref_id e tipo (7 checkout, 6 reembolso; nenhum com pessoas diferentes,
--   nenhum com mais de 2 linhas); 2 linhas de venda de produto de escritório (família ESCRITORIO na academy) presas a evento de educação
--   (1 Croqui em encontro_thb, 1 em holding_total); 578 linhas de produto de escritório sem a marca de setor.
-- O QUE FAZ (só pessoas.eventos, 3 passos, reversível; cada linha tocada vai antes ao backup com um motivo):
--   1. Duplicados (motivo duplicado_removido): por (ref_id, tipo) de ref_tipo 'hotmart.transacao', fica UMA linha (a que tem fonte_id;
--      empate: a de menor id) e as outras saem.
--   2. Evento de educação em venda de escritório (motivo evento_educacao_em_escritorio): evento_id vira null. Não se atribui outro
--      evento: a regra do financeiro não tem evento de escritório para essa venda.
--   3. Setor (motivo setor_marcado): detalhe.setor = 'escritorio' nas linhas de produto de família ESCRITORIO/ESCRITORIO_SOLUCOES, com a
--      linha anterior guardada no backup (id e detalhe) para a reversão voltar SÓ essas linhas. UPDATE só do que difere.
-- GUARDA DE PREMISSA (aborta se qualquer uma falhar): índice eventos_hotmart_ref_idx válido e pronto; no máximo 13 grupos duplicados;
--   nenhum grupo com mais de uma pessoa ou mais de 2 linhas; exatamente 2 linhas de escritório com evento de educação; backup ainda não existe.
-- PÓS-CONDIÇÃO (aborta e desfaz tudo se falhar): sem grupo duplicado; backup com 13 duplicado_removido, 2 evento_educacao_em_escritorio e
--   tantas setor_marcado quantas linhas ficaram marcadas; nenhuma linha de escritório sem setor.
-- NÃO FAZ: não reclassifica o produto 3595938 (Holding Familiar, família OUTROS: a confirmar) nem o 1537308 (Croqui Estrutural para
--   Holding Familiar, família OUTROS, 0 transações); não toca em linha de outro tipo de evento; não mexe em pessoas nem identificadores.
-- AS 5 PERGUNTAS: escala = ~7,5 mil linhas Hotmart de 641 mil (índice parcial da 230000; o passo 3 lê a tabela inteira UMA vez, sem filtro
--   de índice); índice = eventos_hotmart_ref_idx; frequência = única; repetição = recusada pela guarda (o backup já existe) e, se o backup
--   for removido, os UPDATEs só tocam o que difere; reversão = 20261016230200_reversao.sql (reinsere do backup, restaura evento_id e o
--   detalhe das linhas marcadas pelo passo 3).
-- Backup: schema arquivo, dono Victor Hugo, prazo 90 dias (2027-01-14), RLS ligado e sem policy. Não é lido por função viva.
--   O prazo está só no comentário da tabela: falta o card que lembra de apagar (ver docs/pessoa-unica/hotmart-setor-e-idempotencia.md).
-- ENSAIO: 20261016230100_ensaio.sql. Detalhe: 20261016230200.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare v_grupos int; v_multi int; v_alvo2 int;
begin
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('pessoas.eventos_hotmart_ref_idx') and i.indisvalid and i.indisready)
     or to_regprocedure('pessoas.hotmart_setor(text)') is null then
    raise exception '20261016230200: falta o índice da 230000 (existente, válido e pronto) ou a função da 230100; aplicar nessa ordem';
  end if;
  select count(*), count(*) filter (where n > 2 or p > 1) into v_grupos, v_multi
    from (select count(*) n, count(distinct pessoa_id) p from pessoas.eventos
           where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x;
  if v_grupos > 13 then
    raise exception '20261016230200: % grupos duplicados (medido: 13 em 16/10); a regra de limpeza precisa de revisão', v_grupos;
  end if;
  if v_multi > 0 then
    raise exception '20261016230200: % grupo(s) duplicado(s) com mais de 2 linhas ou com pessoas diferentes; a regra de limpeza não vale', v_multi;
  end if;
  select count(*) into v_alvo2 from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio';
  if v_alvo2 <> 2 then
    raise exception '20261016230200: % venda(s) de escritório com evento de educação (medido: exatamente 2 em 16/10)', v_alvo2;
  end if;
  if to_regclass('arquivo.pessoas__eventos__20261016') is not null then
    raise exception '20261016230200: o backup arquivo.pessoas__eventos__20261016 já existe; esta migration já rodou?';
  end if;
end $g$;

create table arquivo.pessoas__eventos__20261016 as
  select e.*, null::text as motivo from pessoas.eventos e where false;
alter table arquivo.pessoas__eventos__20261016 enable row level security;
revoke all on arquivo.pessoas__eventos__20261016 from public, anon, authenticated;
comment on table arquivo.pessoas__eventos__20261016 is
  '20261016230200: linhas de pessoas.eventos tiradas ou alteradas na correção da Hotmart (motivo: duplicado_removido, evento_educacao_em_escritorio, setor_marcado). dono: Victor Hugo · prazo: 2027-01-14 (90 dias) · reversão: 20261016230200_reversao.sql';

-- 1. duplicados: sai a sobra, fica uma
with d as (
  select e.id,
         row_number() over (partition by e.ref_id, e.tipo order by (e.fonte_id is not null) desc, e.id) as rn
    from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao'
     and (e.ref_id, e.tipo) in (select ref_id, tipo from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1)
), apagadas as (
  delete from pessoas.eventos e using d where e.id = d.id and d.rn > 1 returning e.*
)
insert into arquivo.pessoas__eventos__20261016 select a.*, 'duplicado_removido' from apagadas a;

-- 2. evento de educação em venda de escritório: copia a linha para o backup e zera o evento_id
with alvo as (
  select e.id from pessoas.eventos e
    join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016 select e.*, 'evento_educacao_em_escritorio' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set evento_id = null from salva where x.id = salva.id and x.evento_id is not null;

-- 3. setor pelo produto (aditivo): a linha anterior vai ao backup, para a reversão voltar só as linhas marcadas aqui
with alvo as (
  select e.id from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio'
     and e.detalhe ->> 'setor' is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016 select e.*, 'setor_marcado' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set detalhe = x.detalhe || jsonb_build_object('setor', 'escritorio')
  from salva where x.id = salva.id and x.detalhe ->> 'setor' is distinct from 'escritorio';

-- pós-condição: se qualquer número fugir do medido, a transação inteira é desfeita
do $p$
declare v_dup int; v_n1 int; v_n2 int; v_n3 int; v_total int; v_sem int;
begin
  select count(*) into v_dup from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x;
  select count(*) filter (where motivo = 'duplicado_removido'), count(*) filter (where motivo = 'evento_educacao_em_escritorio'),
         count(*) filter (where motivo = 'setor_marcado'), count(*)
    into v_n1, v_n2, v_n3, v_total from arquivo.pessoas__eventos__20261016;
  select count(*) into v_sem from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio';
  if v_dup <> 0 then raise exception '20261016230200: ainda há % grupo(s) duplicado(s); desfeito', v_dup; end if;
  if v_n1 <> 13 or v_n2 <> 2 then
    raise exception '20261016230200: backup com % duplicado_removido e % evento_educacao_em_escritorio (esperado 13 e 2); desfeito', v_n1, v_n2;
  end if;
  if v_total <> 15 + v_n3 then raise exception '20261016230200: backup com % linhas (esperado 15 + % setor_marcado); desfeito', v_total, v_n3; end if;
  if v_sem <> 0 then raise exception '20261016230200: % linha(s) de escritório continuam sem setor; desfeito', v_sem; end if;
end $p$;

insert into pg_temp._z_out(passo, linha) select '04 relogio depois da 230200', clock_timestamp()::text;
insert into pg_temp._z_out(passo, linha) select '05 depois da 230200 (C)', (select jsonb_build_object(
  'hotmart_linhas', count(*) filter (where e.ref_tipo = 'hotmart.transacao'),
  'grupos_duplicados', (select count(*) from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x),
  'hotmart_sem_evento_id', count(*) filter (where e.ref_tipo = 'hotmart.transacao' and e.evento_id is null),
  'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio')) from pessoas.eventos e)::text;
insert into pg_temp._z_out(passo, linha) select '05b depois da 230200: pendências (C)', (select jsonb_build_object(
  'escritorio_sem_setor', (select count(*) from pessoas.eventos e where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio'),
  'escritorio_com_evento_educacao', (select count(*) from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'),
  'backup_existe', (select count(*) from pg_class where relname = 'pessoas__eventos__20261016')))::text;
insert into pg_temp._z_out(passo, linha) select '05c backup por motivo', (select jsonb_object_agg(motivo, n) from (select motivo, count(*) n from arquivo.pessoas__eventos__20261016 group by 1) x)::text;
-- webhook x webhook: mesma transação e tipo, chaves diferentes (dado fictício; nada pessoal)
do $x$
declare v text; i int; p jsonb; k text[] := array['ens-1', 'ens-2', 'ens-3'];
begin
  for i in 1 .. 3 loop
    p := jsonb_build_object('chave', k[i], 'fonte', case when i = 2 then 'sync' else 'webhook' end, 'ref', 'ens-ref', 'conta', 'academy',
           'classe', case when i = 3 then 'reembolso' else 'carrinho_abandonado' end, 'transacao', 'HP-ENSAIO-0001', 'produto_id', '1663254',
           'oferta_codigo', 'ens', 'quando', now(), 'email', 'ensaio.hotmart@ensaio.invalid', 'nome', 'Ensaio');
    begin
      v := crm.hotmart_processar(p);
      insert into pg_temp._z_out(passo, linha) values ('07 webhook chamada ' || i, v);
    exception when others then
      insert into pg_temp._z_out(passo, linha) values ('07 webhook chamada ' || i, 'ERRO ' || sqlstate);
    end;
  end loop;
end $x$;
insert into pg_temp._z_out(passo, linha) select '08 linhas da transação de ensaio por tipo (esperado checkout 1, reembolso 1) e setor', (select jsonb_agg(jsonb_build_object('tipo', tipo, 'setor', detalhe ->> 'setor') order by tipo) from pessoas.eventos where ref_id = 'HP-ENSAIO-0001')::text;
-- ===== reversão da 230200 =====
-- Reversão de 20261016230200: devolve as linhas tiradas, restaura o evento_id e volta o setor SÓ das linhas que o passo 3 marcou.
-- Lê o backup arquivo.pessoas__eventos__20261016 (não apaga o backup: ele vale até 2027-01-14).
-- Linhas que o webhook ou a carga gravaram depois da 230200 NÃO são tocadas: o setor só volta nas linhas com motivo setor_marcado, por id,
-- e só a chave setor (o resto do detalhe, inclusive o que mudou depois, fica).
set local lock_timeout = '5s';
set local statement_timeout = '60s';
insert into pessoas.eventos overriding system value
  select a.id, a.pessoa_id, a.tipo, a.projeto_id, a.origem_id, a.fonte, a.ref_tipo, a.ref_id, a.detalhe, a.quando, a.por, a.evento_id, a.turma_id, a.fonte_tabela, a.fonte_id
    from arquivo.pessoas__eventos__20261016 a where a.motivo = 'duplicado_removido'
  on conflict do nothing;
update pessoas.eventos x set evento_id = a.evento_id
  from arquivo.pessoas__eventos__20261016 a
 where a.motivo = 'evento_educacao_em_escritorio' and a.id = x.id and x.evento_id is distinct from a.evento_id;
update pessoas.eventos x
   set detalhe = case when a.detalhe ? 'setor' then x.detalhe || jsonb_build_object('setor', a.detalhe -> 'setor') else x.detalhe - 'setor' end
  from arquivo.pessoas__eventos__20261016 a
 where a.motivo = 'setor_marcado' and a.id = x.id and x.detalhe -> 'setor' is distinct from a.detalhe -> 'setor';

insert into pg_temp._z_out(passo, linha) select '06 depois da reversão da 230200 (D, esperado A mais 2 linhas e 2 setores do webhook de ensaio)', (select jsonb_build_object(
  'hotmart_linhas', count(*) filter (where e.ref_tipo = 'hotmart.transacao'),
  'grupos_duplicados', (select count(*) from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x),
  'hotmart_sem_evento_id', count(*) filter (where e.ref_tipo = 'hotmart.transacao' and e.evento_id is null),
  'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio')) from pessoas.eventos e)::text;
insert into pg_temp._z_out(passo, linha) select '06b depois da reversão: pendências (D)', (select jsonb_build_object(
  'escritorio_sem_setor', (select count(*) from pessoas.eventos e where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio'),
  'escritorio_com_evento_educacao', (select count(*) from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'),
  'backup_existe', (select count(*) from pg_class where relname = 'pessoas__eventos__20261016')))::text;
insert into pg_temp._z_out(passo, linha) select '06d linhas do webhook de ensaio depois da reversão (esperado: setor escritorio nas duas, a reversão só volta os id do backup)', (select jsonb_agg(jsonb_build_object('tipo', tipo, 'setor', detalhe ->> 'setor') order by tipo) from pessoas.eventos where ref_id = 'HP-ENSAIO-0001')::text;
-- guarda: um grupo duplicado com pessoas diferentes tem de abortar a 230200 (backup apagado só dentro do ensaio)
drop table arquivo.pessoas__eventos__20261016;
update pessoas.eventos set pessoa_id = (select id from pessoas.pessoas where id <> (select pessoa_id from pessoas.eventos where id = x.id) limit 1)
  from (select max(id) id from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1 limit 1) x
 where pessoas.eventos.id = x.id;
do $t$
begin
  execute $m$-- 20261016230200: corrige os eventos Hotmart já gravados na linha do tempo (duplicados, evento de educação em venda de escritório, setor)
--
-- STATUS: NÃO APLICADA. Terminal Hotmart (back-end-sr), 16/10/2026, branch victor-hotmart-setor. Depende de 20261016230000 e 20261016230100.
-- REVISADA após o pentest de 16/10 (PENTEST-HOTMART-SETOR-2026-10-16.md): guarda de premissa exata, pós-condição, backup do passo 3 e
--   guarda de índice válido.
-- ORDEM: depois da 230100 (senão o webhook recria duplicata no meio da limpeza).
-- POR QUE (medido em 16/10/2026): 13 grupos de linhas com o mesmo ref_id e tipo (7 checkout, 6 reembolso; nenhum com pessoas diferentes,
--   nenhum com mais de 2 linhas); 2 linhas de venda de produto de escritório (família ESCRITORIO na academy) presas a evento de educação
--   (1 Croqui em encontro_thb, 1 em holding_total); 578 linhas de produto de escritório sem a marca de setor.
-- O QUE FAZ (só pessoas.eventos, 3 passos, reversível; cada linha tocada vai antes ao backup com um motivo):
--   1. Duplicados (motivo duplicado_removido): por (ref_id, tipo) de ref_tipo 'hotmart.transacao', fica UMA linha (a que tem fonte_id;
--      empate: a de menor id) e as outras saem.
--   2. Evento de educação em venda de escritório (motivo evento_educacao_em_escritorio): evento_id vira null. Não se atribui outro
--      evento: a regra do financeiro não tem evento de escritório para essa venda.
--   3. Setor (motivo setor_marcado): detalhe.setor = 'escritorio' nas linhas de produto de família ESCRITORIO/ESCRITORIO_SOLUCOES, com a
--      linha anterior guardada no backup (id e detalhe) para a reversão voltar SÓ essas linhas. UPDATE só do que difere.
-- GUARDA DE PREMISSA (aborta se qualquer uma falhar): índice eventos_hotmart_ref_idx válido e pronto; no máximo 13 grupos duplicados;
--   nenhum grupo com mais de uma pessoa ou mais de 2 linhas; exatamente 2 linhas de escritório com evento de educação; backup ainda não existe.
-- PÓS-CONDIÇÃO (aborta e desfaz tudo se falhar): sem grupo duplicado; backup com 13 duplicado_removido, 2 evento_educacao_em_escritorio e
--   tantas setor_marcado quantas linhas ficaram marcadas; nenhuma linha de escritório sem setor.
-- NÃO FAZ: não reclassifica o produto 3595938 (Holding Familiar, família OUTROS: a confirmar) nem o 1537308 (Croqui Estrutural para
--   Holding Familiar, família OUTROS, 0 transações); não toca em linha de outro tipo de evento; não mexe em pessoas nem identificadores.
-- AS 5 PERGUNTAS: escala = ~7,5 mil linhas Hotmart de 641 mil (índice parcial da 230000; o passo 3 lê a tabela inteira UMA vez, sem filtro
--   de índice); índice = eventos_hotmart_ref_idx; frequência = única; repetição = recusada pela guarda (o backup já existe) e, se o backup
--   for removido, os UPDATEs só tocam o que difere; reversão = 20261016230200_reversao.sql (reinsere do backup, restaura evento_id e o
--   detalhe das linhas marcadas pelo passo 3).
-- Backup: schema arquivo, dono Victor Hugo, prazo 90 dias (2027-01-14), RLS ligado e sem policy. Não é lido por função viva.
--   O prazo está só no comentário da tabela: falta o card que lembra de apagar (ver docs/pessoa-unica/hotmart-setor-e-idempotencia.md).
-- ENSAIO: 20261016230100_ensaio.sql. Detalhe: 20261016230200.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare v_grupos int; v_multi int; v_alvo2 int;
begin
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('pessoas.eventos_hotmart_ref_idx') and i.indisvalid and i.indisready)
     or to_regprocedure('pessoas.hotmart_setor(text)') is null then
    raise exception '20261016230200: falta o índice da 230000 (existente, válido e pronto) ou a função da 230100; aplicar nessa ordem';
  end if;
  select count(*), count(*) filter (where n > 2 or p > 1) into v_grupos, v_multi
    from (select count(*) n, count(distinct pessoa_id) p from pessoas.eventos
           where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x;
  if v_grupos > 13 then
    raise exception '20261016230200: % grupos duplicados (medido: 13 em 16/10); a regra de limpeza precisa de revisão', v_grupos;
  end if;
  if v_multi > 0 then
    raise exception '20261016230200: % grupo(s) duplicado(s) com mais de 2 linhas ou com pessoas diferentes; a regra de limpeza não vale', v_multi;
  end if;
  select count(*) into v_alvo2 from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio';
  if v_alvo2 <> 2 then
    raise exception '20261016230200: % venda(s) de escritório com evento de educação (medido: exatamente 2 em 16/10)', v_alvo2;
  end if;
  if to_regclass('arquivo.pessoas__eventos__20261016') is not null then
    raise exception '20261016230200: o backup arquivo.pessoas__eventos__20261016 já existe; esta migration já rodou?';
  end if;
end $g$;

create table arquivo.pessoas__eventos__20261016 as
  select e.*, null::text as motivo from pessoas.eventos e where false;
alter table arquivo.pessoas__eventos__20261016 enable row level security;
revoke all on arquivo.pessoas__eventos__20261016 from public, anon, authenticated;
comment on table arquivo.pessoas__eventos__20261016 is
  '20261016230200: linhas de pessoas.eventos tiradas ou alteradas na correção da Hotmart (motivo: duplicado_removido, evento_educacao_em_escritorio, setor_marcado). dono: Victor Hugo · prazo: 2027-01-14 (90 dias) · reversão: 20261016230200_reversao.sql';

-- 1. duplicados: sai a sobra, fica uma
with d as (
  select e.id,
         row_number() over (partition by e.ref_id, e.tipo order by (e.fonte_id is not null) desc, e.id) as rn
    from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao'
     and (e.ref_id, e.tipo) in (select ref_id, tipo from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1)
), apagadas as (
  delete from pessoas.eventos e using d where e.id = d.id and d.rn > 1 returning e.*
)
insert into arquivo.pessoas__eventos__20261016 select a.*, 'duplicado_removido' from apagadas a;

-- 2. evento de educação em venda de escritório: copia a linha para o backup e zera o evento_id
with alvo as (
  select e.id from pessoas.eventos e
    join fin.eventos fe on fe.id = e.evento_id
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016 select e.*, 'evento_educacao_em_escritorio' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set evento_id = null from salva where x.id = salva.id and x.evento_id is not null;

-- 3. setor pelo produto (aditivo): a linha anterior vai ao backup, para a reversão voltar só as linhas marcadas aqui
with alvo as (
  select e.id from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio'
     and e.detalhe ->> 'setor' is distinct from 'escritorio'
), salva as (
  insert into arquivo.pessoas__eventos__20261016 select e.*, 'setor_marcado' from pessoas.eventos e join alvo using (id) returning id
)
update pessoas.eventos x set detalhe = x.detalhe || jsonb_build_object('setor', 'escritorio')
  from salva where x.id = salva.id and x.detalhe ->> 'setor' is distinct from 'escritorio';

-- pós-condição: se qualquer número fugir do medido, a transação inteira é desfeita
do $p$
declare v_dup int; v_n1 int; v_n2 int; v_n3 int; v_total int; v_sem int;
begin
  select count(*) into v_dup from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x;
  select count(*) filter (where motivo = 'duplicado_removido'), count(*) filter (where motivo = 'evento_educacao_em_escritorio'),
         count(*) filter (where motivo = 'setor_marcado'), count(*)
    into v_n1, v_n2, v_n3, v_total from arquivo.pessoas__eventos__20261016;
  select count(*) into v_sem from pessoas.eventos e
   where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio';
  if v_dup <> 0 then raise exception '20261016230200: ainda há % grupo(s) duplicado(s); desfeito', v_dup; end if;
  if v_n1 <> 13 or v_n2 <> 2 then
    raise exception '20261016230200: backup com % duplicado_removido e % evento_educacao_em_escritorio (esperado 13 e 2); desfeito', v_n1, v_n2;
  end if;
  if v_total <> 15 + v_n3 then raise exception '20261016230200: backup com % linhas (esperado 15 + % setor_marcado); desfeito', v_total, v_n3; end if;
  if v_sem <> 0 then raise exception '20261016230200: % linha(s) de escritório continuam sem setor; desfeito', v_sem; end if;
end $p$;
$m$;
  insert into pg_temp._z_out(passo, linha) values ('06c guarda de pessoas diferentes', 'NAO ABORTOU');
exception when others then
  insert into pg_temp._z_out(passo, linha) values ('06c guarda de pessoas diferentes', 'abortou: ' || sqlerrm);
end $t$;
-- carga: academy (execução 71 reaberta dentro da transação) e escritório (72)
do $x$
declare a jsonb; e bigint; t0 timestamptz; f text; n int;
begin
  foreach f in array array['hotmart_academy', 'hotmart_escritorio'] loop
    a := pessoas.carga_abrir(f, 'pessoas', 'ensaio 230100');
    e := (a ->> 'execucao')::bigint;
    insert into pg_temp._z_out(passo, linha) values ('09 carga_abrir ' || f, a::text);
    for n in 1 .. 2 loop
      t0 := clock_timestamp();
      begin
        a := pessoas.carga_fin_hotmart(e, substr(f, 9), 1000);
        insert into pg_temp._z_out(passo, linha) values ('10 ' || f || ' lote ' || n, a::text || ' ms=' || round(extract(epoch from clock_timestamp() - t0) * 1000));
      exception when others then
        insert into pg_temp._z_out(passo, linha) values ('10 ' || f || ' lote ' || n, 'ERRO ' || sqlstate || ' ' || sqlerrm);
      end;
    end loop;
  end loop;
end $x$;
insert into pg_temp._z_out(passo, linha) select '11 depois da carga (E)', (select jsonb_build_object(
  'hotmart_linhas', count(*) filter (where e.ref_tipo = 'hotmart.transacao'),
  'grupos_duplicados', (select count(*) from (select 1 from pessoas.eventos where ref_tipo = 'hotmart.transacao' group by ref_id, tipo having count(*) > 1) x),
  'hotmart_sem_evento_id', count(*) filter (where e.ref_tipo = 'hotmart.transacao' and e.evento_id is null),
  'com_setor_escritorio', count(*) filter (where e.detalhe ->> 'setor' = 'escritorio')) from pessoas.eventos e)::text;
insert into pg_temp._z_out(passo, linha) select '11b depois da carga: pendências (E)', (select jsonb_build_object(
  'escritorio_sem_setor', (select count(*) from pessoas.eventos e where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and e.detalhe ->> 'setor' is distinct from 'escritorio'),
  'escritorio_com_evento_educacao', (select count(*) from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id where e.ref_tipo = 'hotmart.transacao' and pessoas.hotmart_setor(e.detalhe ->> 'produto') = 'escritorio' and fe.setor is distinct from 'escritorio'),
  'backup_existe', (select count(*) from pg_class where relname = 'pessoas__eventos__20261016')))::text;
insert into pg_temp._z_out(passo, linha) select '12 linhas de escritório criadas pela carga com evento de educação (esperado 0)', (select count(*) from pessoas.eventos e join fin.eventos fe on fe.id = e.evento_id where e.fonte_tabela = 'fin.hotmart' || '_transacoes' and e.detalhe ->> 'setor' = 'escritorio' and fe.setor is distinct from 'escritorio')::text;
-- ===== reversão da 230100 (prova que volta) =====
-- Reversão de 20261016230100: volta os corpos vigentes de 16/10/2026 (pg_get_functiondef) e remove pessoas.hotmart_setor.
-- Não mexe nas linhas já gravadas (detalhe.setor fica; é aditivo). Recria com o mesmo nome e a mesma assinatura (sem sobrecarga).
set local lock_timeout = '5s';
CREATE OR REPLACE FUNCTION pessoas.carga_fin_hotmart(p_execucao bigint, p_conta text, p_limite integer DEFAULT 1000, p_novos boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- Uma execução por conta (fontes hotmart_academy e hotmart_escritorio). Toda leitura da tabela de transações segue a forma
-- canônica que a trava fin.trava_conta_hotmart exige (regra 9 do plano de ação): (select * from ... where conta = p_conta).
-- A trava conta o nome da tabela até dentro de texto; por isso o valor de fonte_tabela é montado por concatenação (v_tab).
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_tipo text; v_ev bigint;
  v_tab constant text := 'fin.hotmart' || '_transacoes';
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  if p_conta not in ('academy', 'escritorio') then raise exception 'conta inválida' using errcode = '22023'; end if;
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'hotmart_' || p_conta), '');
  if p_limite not between 1 and 2000 then raise exception 'limite entre 1 e 2.000' using errcode = '22023'; end if;
  create temp table if not exists _carga_hm_lote (transacao text primary key) on commit drop;
  create temp table if not exists _carga_hm_ev (transacao text primary key, evento_id bigint) on commit drop;
  delete from pg_temp._carga_hm_lote; delete from pg_temp._carga_hm_ev;
  insert into pg_temp._carga_hm_lote
  select t.transacao from (select * from fin.hotmart_transacoes where conta = p_conta) t
   where (not p_novos and t.transacao > v_cur)
      or (p_novos and not exists (select 1 from pessoas.eventos e
                                   where e.fonte_tabela = v_tab and e.fonte_id = t.transacao
                                     and e.tipo = case when t.status in ('COMPLETE', 'APPROVED') then 'compra'
                                                       when t.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                                                       else 'checkout' end))
   order by t.transacao limit p_limite;
  -- evento pela regra do financeiro (mesma janela/oferta que os funis usam), por lote de e-mails
  insert into pg_temp._carga_hm_ev
  select distinct on (j.transacao) j.transacao, j.evento_id
    from fin.trajetoria_nucleo(array(select distinct lower(btrim(t.comprador_email))
                                       from (select * from fin.hotmart_transacoes where conta = p_conta) t
                                       join pg_temp._carga_hm_lote l using (transacao) where t.comprador_email is not null)) j
    join pg_temp._carga_hm_lote l on l.transacao = j.transacao
   where j.evento_id is not null
   order by j.transacao;

  for r in select t.* from (select * from fin.hotmart_transacoes where conta = p_conta) t
             join pg_temp._carga_hm_lote l using (transacao) order by t.transacao loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.transacao); v_ate := r.transacao;
    v := pessoas._casar_email_seguro(r.comprador_nome, r.comprador_email, r.comprador_telefone, 'hotmart');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_tipo := case when r.status in ('COMPLETE', 'APPROVED') then 'compra'
                   when r.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                   else 'checkout' end;
    v_ev := null;
    select e.evento_id into v_ev from pg_temp._carga_hm_ev e where e.transacao = r.transacao;
    -- a linha que o webhook já gravou desta transação/tipo recebe a fonte (uma só), em vez de criar outra
    update pessoas.eventos x set fonte_tabela = v_tab, fonte_id = r.transacao, evento_id = coalesce(x.evento_id, v_ev)
     where x.id = (select min(y.id) from pessoas.eventos y
                    where y.ref_tipo = 'hotmart.transacao' and y.ref_id = r.transacao and y.tipo = v_tipo and y.fonte_id is null)
       and not exists (select 1 from pessoas.eventos z where z.fonte_tabela = v_tab and z.fonte_id = r.transacao and z.tipo = v_tipo);
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, v_tipo, 'hotmart', v_ev, 'hotmart.transacao', left(r.transacao, 80), v_tab, left(r.transacao, 120),
            coalesce(r.aprovado_em, r.pedido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('conta', p_conta, 'produto', left(r.produto_id, 40),
                                                 'oferta', left(r.oferta_codigo, 40), 'status', left(r.status, 30))))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $function$;

CREATE OR REPLACE FUNCTION crm.hotmart_processar(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_chave text := p ->> 'chave';
  v_classe text := p ->> 'classe';
  v_tx text := p ->> 'transacao';
  v_quando timestamptz := coalesce((p ->> 'quando')::timestamptz, now());
  v_desde timestamptz;
  v_email text := pessoas.norm_email(p ->> 'email');
  v_tel text := pessoas.norm_telefone(p ->> 'telefone');
  v_nome text := nullif(left(btrim(coalesce(p ->> 'nome', '')), 160), '');
  v_ins int; v_res jsonb; v_pessoa uuid; v_atual uuid; v_g uuid[];
  pc crm.produto_comercial%rowtype; v_linha_nome text; v_oferta text; v_orfa boolean := false; v_valor numeric;
  n crm.negocio%rowtype; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pcid uuid; v_camp uuid; v_neg uuid;
  v_criados int := 0; v_abertos int := 0; v_funis int := 0; v_resultado text; v_rotulo text; v_sinc boolean;
begin
  -- 1. idempotência (PK). Reprocesso explícito ('forcar') reaproveita a linha.
  if coalesce((p ->> 'forcar')::boolean, false) then
    update crm.hotmart_processado x set resultado = 'processando', processado_em = now(), tentativas = x.tentativas + 1
     where x.chave = v_chave;
  else
    insert into crm.hotmart_processado (chave, fonte, ref, conta, classe, transacao, produto_id, oferta_codigo, quando)
    values (v_chave, p ->> 'fonte', p ->> 'ref', p ->> 'conta', v_classe, v_tx, p ->> 'produto_id', p ->> 'oferta_codigo', v_quando)
    on conflict (chave) do nothing;
    get diagnostics v_ins = row_count;
    if v_ins = 0 then return 'duplicado'; end if;
  end if;

  perform set_config('crm.canal', 'hotmart', true); -- crm.tg_log: autor_tipo 'integracao'
  select c.hotmart_desde into v_desde from crm.config c; -- crm.hotmart_entrada garante não nulo

  -- 2. pessoa por e-mail (F0). Sem e-mail não há pessoa (o webhook sempre manda; medido 0 sem e-mail em PURCHASE_*).
  if v_email is null then
    v_resultado := 'sem_email';
  elsif v_quando < v_desde - interval '1 hour' and v_classe <> 'reembolso' and v_classe <> 'chargeback' then
    v_resultado := 'antes_do_corte'; -- D8: sem retroativo (reembolso de venda antiga ainda marca o negócio, se houver)
  end if;
  if v_resultado is not null then
    update crm.hotmart_processado x set resultado = v_resultado where x.chave = v_chave;
    return v_resultado;
  end if;

  v_res := pessoas.resolver(v_nome, v_email, v_tel, null, false, null);
  v_pessoa := (v_res ->> 'pessoa_id')::uuid;
  perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, 'hotmart');
  if v_tel is not null then perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), 'hotmart'); end if;
  v_atual := pessoas.atual(v_pessoa);
  v_g := pessoas.grupo(v_atual);

  -- 3. jornada da pessoa (toda classe, todo produto das 2 contas)
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe, quando)
  values (v_atual,
          case when v_classe = 'aprovada' then 'compra'
               when v_classe in ('reembolso', 'chargeback', 'disputa') then 'reembolso' else 'checkout' end,
          'hotmart', case when v_tx is not null then 'hotmart.transacao' else 'hotmart.evento' end,
          left(coalesce(v_tx, p ->> 'ref'), 80),
          jsonb_strip_nulls(jsonb_build_object('classe', v_classe, 'conta', p ->> 'conta', 'produto', p ->> 'produto_id',
                            'oferta', p ->> 'oferta_codigo', 'valor', p -> 'valor', 'metodo', p ->> 'metodo',
                            'recorrencia', p -> 'recorrencia', 'sck', p ->> 'sck', 'casou_por', v_res ->> 'como')),
          v_quando);

  -- 4. camada comercial: só produto vinculado ao comercial com linha
  -- 20261008z01: vínculo por OFERTA (crm.oferta_linha, ativo) tem precedência sobre o do produto
  select p ->> 'produto_id', true, ol.nome_comercial, ol.linha, l.escada, ol.agrupador_id, ol.vinculado_por, ol.vinculado_em
    into pc
    from crm.oferta_linha ol join crm.linha l on l.chave = ol.linha
   where ol.oferta_codigo = p ->> 'oferta_codigo' and ol.ativo;
  if not found then
    select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
  end if;
  if not found then
    update crm.hotmart_processado x set resultado = 'jornada: produto fora do comercial', pessoa_id = v_atual where x.chave = v_chave;
    return 'jornada: produto fora do comercial';
  end if;
  select l.nome into v_linha_nome from crm.linha l where l.chave = pc.linha;

  -- oferta: só entra no negócio se estiver no catálogo (FK fin.ofertas). Fora = aviso (catalogar no mesmo dia).
  if p ->> 'oferta_codigo' is not null then
    select o.oferta_codigo into v_oferta from fin.ofertas o where o.oferta_codigo = p ->> 'oferta_codigo';
    if v_oferta is null then
      v_orfa := true;
      select pr.sincroniza into v_sinc from fin.produtos pr where pr.produto_id = pc.produto_id;
      perform crm.slack_enfileirar('oferta_orfa', p ->> 'oferta_codigo',
        -- 20261007a: aviso sem dado de pessoa (nunca teve), agora com link para Produtos
        format(':label: *Oferta fora do catálogo* · %s · oferta %s (conta %s) · catalogar hoje%s · <https://grupoparticipa.app.br/comercial/produtos|Abrir Produtos>',
               crm.slack_esc(coalesce(pc.nome_comercial, v_linha_nome)), crm.slack_esc(p ->> 'oferta_codigo'),
               crm.slack_esc(p ->> 'conta'),
               case when coalesce(v_sinc, false) then '' else ' (o produto está com sincronização de ofertas desligada no Financeiro)' end));
    end if;
  end if;
  v_valor := coalesce((p ->> 'valor')::numeric,
                      (select o.preco from fin.ofertas o where o.oferta_codigo = v_oferta),
                      (select l.ticket_ref from crm.linha l where l.chave = pc.linha), 0);
  v_valor := greatest(round(v_valor, 2), 0);

  -- 5. por classe
  if v_classe = 'aprovada' then
    if coalesce((p ->> 'recorrencia')::numeric, 1) > 1 then
      v_resultado := 'jornada: recorrência ' || (p ->> 'recorrencia') || ' não é venda nova';
    elsif v_tx is null then
      v_resultado := 'jornada: aprovada sem transação';
    elsif exists (select 1 from crm.negocio x where x.transacao_ganho = v_tx) then
      v_resultado := 'ja_ganho';
    else
      -- 20261007e: compra de produto da OFERTA de um projeto fecha o negócio de ATIVAÇÃO dele (mesmo dono);
      -- funil de ativação fica fora da regra geral por linha (o ingresso tem a linha do projeto e não é ganho)
      select x.* into n from crm.negocio x join crm.projeto_ativacao pa on pa.funil_id = x.funil_id
        join crm.funil fx on fx.id = x.funil_id and fx.ativo
       where x.pessoa_id = any(v_g) and x.status = 'aberto' and (p ->> 'produto_id') = any(pa.hotmart_oferta)
       order by x.criado_em, x.id
       limit 1 for update of x;
      if not found then
        select * into n from crm.negocio x
         where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
           and not exists (select 1 from crm.projeto_ativacao pa where pa.funil_id = x.funil_id)
           and exists (select 1 from crm.funil fx where fx.id = x.funil_id and fx.ativo)
         order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
         limit 1 for update;
      end if;
      if found then
        select e.id into v_etapa from crm.etapa_funil e
         where e.funil_id = n.funil_id and e.papel = 'fechado' and e.arquivada_em is null;
        perform set_config('crm.resumo', format('Venda aprovada na Hotmart (transação %s): negócio ganho', v_tx), true);
        perform set_config('crm.ganho_hotmart', 'on', true);
        update crm.negocio x
           set status = 'ganho', etapa_id = v_etapa, etapa_desde = now(), fechado_em = v_quando, transacao_ganho = v_tx,
               valor = v_valor, oferta_codigo = coalesce(v_oferta, x.oferta_codigo), ultima_interacao_em = now(),
               atualizado_em = now()
         where x.id = n.id;
        perform set_config('crm.ganho_hotmart', 'off', true);
        v_neg := n.id; v_resultado := 'ganho';
      else
        -- 20261006191824 (D8, decisão do Victor 06/10/2026): compra aprovada SEM negócio aberto da pessoa na linha
        -- NÃO cria negócio ganho nem contato comercial. A compra fica na jornada (pessoas.eventos tipo 'compra',
        -- gravado no passo 3, e crm_jornada lê fin.hotmart_transacoes). Ganho no CRM = venda que o comercial trabalhou.
        v_resultado := 'jornada: compra sem negócio aberto (não cria ganho)';
      end if;
    end if;

  elsif v_classe in ('carrinho_abandonado', 'compra_em_aberto', 'cartao_recusado', 'expirada') then
    if v_quando < now() - interval '48 hours' then
      v_resultado := 'jornada: checkout com mais de 48 h';
    elsif exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = any(v_g) and x.opt_out) then
      v_resultado := 'jornada: opt-out';
    elsif exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'ganho'
                     and x.fechado_em > now() - interval '30 days')
       or exists (select 1 from pessoas.eventos e
                   where e.pessoa_id = any(v_g) and e.tipo = 'compra' and e.fonte = 'hotmart'
                     and e.quando > now() - interval '30 days'
                     -- 20261008z01: a compra conta pela linha da OFERTA (se vinculada), senão pela do produto
                     and coalesce((select ol.linha from crm.oferta_linha ol where ol.oferta_codigo = e.detalhe ->> 'oferta' and ol.ativo),
                                  (select y.linha from crm.produto_comercial y
                                    where y.produto_id = e.detalhe ->> 'produto' and y.no_comercial)) = pc.linha) then
      -- 20261006191824: compra direta não vira mais negócio ganho; a compra na jornada também conta
      v_resultado := 'jornada: já comprou a linha em 30 dias';
    else
      for f in select x.* from crm.funil x
                where x.ativo and x.tipo = 'hotmart' and x.linha = pc.linha and v_classe = any(x.eventos_hotmart)
                  and (pc.agrupador_id is null or x.agrupador_id = pc.agrupador_id)
                order by x.criado_em, x.id loop
        v_funis := v_funis + 1;
        perform pg_advisory_xact_lock(hashtext('crm.dist:' || f.id::text)); -- mesmo lock de crm_criar_negocio (F2)
        if exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.funil_id = f.id and x.status = 'aberto') then
          v_abertos := v_abertos + 1;
          continue;
        end if;
        select e.id into v_etapa from crm.etapa_funil e where e.funil_id = f.id and e.arquivada_em is null order by e.ordem limit 1;
        continue when v_etapa is null;
        v_dono := crm.escolher_dono(v_atual, f.id);
        v_pcid := crm.garantir_pc(v_atual);
        if v_dono is not null then
          perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição, Hotmart)', crm.nome_pessoa(v_atual), crm.nome_perfil(v_dono)), true);
          update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pcid and x.dono_id is null;
        end if;
        select c.id into v_camp from crm.campanha c where c.funil_id = f.id and c.ativa and c.canal = 'hotmart' order by c.criado_em limit 1;
        v_rotulo := case v_classe when 'carrinho_abandonado' then 'carrinho abandonado' when 'compra_em_aberto' then 'boleto/pix gerado'
                                  when 'cartao_recusado' then 'cartão recusado' else 'pagamento expirado' end;
        perform set_config('crm.resumo', format('Hotmart: %s → negócio em %s (dono: %s)', v_rotulo, f.nome, crm.nome_perfil(v_dono)), true);
        insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, oferta_codigo, campos, utm,
                                 ultima_interacao_em)
        values (v_atual, f.id, v_etapa, v_camp, pc.linha, v_classe, v_dono, v_valor, v_oferta,
                jsonb_build_object('origem', 'Hotmart · ' || v_rotulo),
                case when p ->> 'sck' is not null then jsonb_build_object('sck', p ->> 'sck') else '{}'::jsonb end, null)
        returning id into v_neg;
        v_criados := v_criados + 1;
      end loop;
      v_resultado := case when v_criados > 0 then 'negocio_criado: ' || v_criados
                          when v_abertos > 0 then 'ja_aberto'
                          when v_funis = 0 then 'jornada: nenhum funil hotmart da linha escuta ' || v_classe
                          else 'jornada: funil sem etapa' end;
    end if;

  elsif v_classe in ('reembolso', 'chargeback') then
    perform set_config('crm.resumo', format('Hotmart: %s da transação %s', v_classe, coalesce(v_tx, '?')), true);
    update crm.negocio x set reembolsado_em = coalesce(x.reembolsado_em, now()), atualizado_em = now()
     where v_tx is not null and x.transacao_ganho = v_tx and x.reembolsado_em is null
     returning * into n;
    if found then
      v_neg := n.id; v_resultado := v_classe || '_marcado';
      -- 20261007a (decisão do Arthur 07/10/2026): aviso no Slack sem nome nem e-mail da pessoa; resumo + link da ficha
      perform crm.slack_enfileirar(v_classe, coalesce(v_tx, v_chave),
        crm.slack_texto_negocio(':rotating_light:', case when v_classe = 'reembolso' then 'Reembolso' else 'Chargeback' end,
                                n.id, coalesce(v_linha_nome, pc.linha), pc.nome_comercial, p ->> 'metodo'));
    else
      v_resultado := 'jornada: sem negócio ganho desta transação';
    end if;

  elsif v_classe = 'disputa' then
    select * into n from crm.negocio x where v_tx is not null and x.transacao_ganho = v_tx;
    if found then
      v_neg := n.id; v_resultado := 'disputa_avisada';
      -- 20261007a: idem (sem nome nem e-mail)
      perform crm.slack_enfileirar('disputa', coalesce(v_tx, v_chave),
        crm.slack_texto_negocio(':warning:', 'Disputa aberta na Hotmart',
                                n.id, coalesce(v_linha_nome, pc.linha), pc.nome_comercial, p ->> 'metodo'));
    else
      v_resultado := 'jornada: disputa sem negócio ganho';
    end if;
  end if;

  perform set_config('crm.resumo', '', true);
  update crm.hotmart_processado x
     set resultado = left(coalesce(v_resultado, 'ok'), 300), pessoa_id = v_atual, negocio_id = v_neg, oferta_orfa = v_orfa
   where x.chave = v_chave;
  return v_resultado;
end
$function$;

drop function if exists pessoas.hotmart_setor(text);

insert into pg_temp._z_out(passo, linha) select '13 funções depois da reversão da 230100 (hotmart_setor deve ser 0)', (select count(*) from pg_proc where pronamespace = 'pessoas'::regnamespace and proname = 'hotmart_setor')::text;
select passo, linha from pg_temp._z_out order by em;
rollback;
