-- 20261016230255: webhook e carga da Hotmart gravam com on conflict do nothing contra o índice único da 230250 (sem lock de aviso)
--
-- STATUS: APLICADA em 16/10/2026 16:29:48 UTC (aplica_sql.py aplicar). md5 novos: crm 039a07f39306c48b8075a2661f689676, carga
--   82d1af069062c7dd30fed492a7a56ad9 (iguais ao ensaio). Branch victor-hotmart-unico. Depende de 20261016230250 (índice único).
-- POR QUE: achados 4 e 5 do pentest da Hotmart (16/10). 4: a carga não tomava o lock do webhook e, se os dois gravassem a mesma
--   transação e tipo ao mesmo tempo, nasciam duas linhas. 5: o lock de aviso do webhook dura a transação inteira de quem chama
--   (gatilho por linha em fin.hotmart_transacoes); um sync em massa ocupa uma vaga por evento na tabela de locks (3.840 vagas medidas).
-- O QUE FAZ (2 funções, MESMA assinatura, create or replace; nenhuma tabela, policy ou grant alterado):
--   crm.hotmart_processar(jsonb)  SÓ o passo 3: sai o pg_advisory_xact_lock; o insert ganha
--                                 on conflict (ref_id, tipo) where ref_tipo = 'hotmart.transacao' do nothing. O resto é o corpo vivo
--                                 (pg_get_functiondef de 16/10/2026, md5 6171c1c2f05a314d2a0a670501348668).
--   pessoas.carga_fin_hotmart(...) ordem invertida: insere primeiro com on conflict do nothing (sem alvo: vale para a fonte e para a
--                                 transação+tipo) e, só se não inseriu, reivindica a linha que já existe (preenche fonte, evento e setor).
--                                 Como a reivindicação é um comando novo, ela já enxerga a linha do webhook gravada em paralelo: a corrida
--                                 fecha sem lock. Corpo vivo de origem com md5 0c8f685e06ad73f785bb2e13eb7855c4.
-- GUARDAS: aborta se o índice único não existir válido, ou se algum corpo vivo não for o de origem (alguém mudou a função no meio).
-- AS 5 PERGUNTAS: escala = mesma consulta por índice de antes, um insert por evento; índice = 230250; frequência = por venda e por lote
--   de carga; repetição = a mesma transação+tipo grava uma linha só, garantido pelo banco; reversão = 20261016230255_reversao.sql
--   (corpos vivos de 16/10), depois 20261016230250_reversao.sql.
-- ENSAIO: 20261016230250_ensaio.sql (cobre 230250 e 230255, transação desfeita). Detalhe: 20261016230250.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if not exists (select 1 from pg_index i where i.indexrelid = to_regclass('pessoas.eventos_hotmart_ref_unico')
                  and i.indisunique and i.indisvalid and i.indisready) then
    raise exception '230255: falta o índice único eventos_hotmart_ref_unico válido (aplicar a 230250 antes)';
  end if;
  if md5(pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) <> '6171c1c2f05a314d2a0a670501348668'
     or md5(pg_get_functiondef('pessoas.carga_fin_hotmart(bigint,text,integer,boolean)'::regprocedure)) <> '0c8f685e06ad73f785bb2e13eb7855c4' then
    raise exception '230255: corpo vivo diferente do de origem; refazer a partir do pg_get_functiondef atual';
  end if;
end $g$;

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
  -- 20261016230255: sem lock de aviso. A unicidade agora é do banco (índice único eventos_hotmart_ref_unico, 230250) e o insert
  --   abaixo tem on conflict do nothing: duas entregas ao mesmo tempo gravam uma linha só, sem ocupar a tabela de locks.
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
            left(coalesce(v_tx, p ->> 'ref'), 80), v_det, v_quando)
    on conflict (ref_id, tipo) where ref_tipo = 'hotmart.transacao' do nothing;
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
    -- 20261016230255: insere primeiro, com on conflict do nothing sem alvo (vale para os dois índices únicos: a fonte e a transação+tipo
    --   da 230250). Se a linha já existe (do webhook ou de carga anterior), a reivindicação vem DEPOIS, num comando novo, que já enxerga a
    --   linha que o webhook acabou de gravar em paralelo (o insert espera o commit dele). Fecha a corrida webhook x carga.
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, v_tipo, 'hotmart', v_ev, 'hotmart.transacao', left(r.transacao, 80), v_tab, left(r.transacao, 120),
            coalesce(r.aprovado_em, r.pedido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('conta', p_conta, 'produto', left(r.produto_id, 40),
                                                 'oferta', left(r.oferta_codigo, 40), 'status', left(r.status, 30), 'setor', v_setor)))
    on conflict do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if n_x = 0 then
      -- a linha que o webhook já gravou desta transação/tipo recebe a fonte (uma só)
      update pessoas.eventos x set fonte_tabela = v_tab, fonte_id = r.transacao, evento_id = coalesce(x.evento_id, v_ev),
             detalhe = case when v_setor is not null then x.detalhe || jsonb_build_object('setor', v_setor) else x.detalhe end
       where x.id = (select min(y.id) from pessoas.eventos y
                      where y.ref_tipo = 'hotmart.transacao' and y.ref_id = r.transacao and y.tipo = v_tipo and y.fonte_id is null)
         and not exists (select 1 from pessoas.eventos z where z.fonte_tabela = v_tab and z.fonte_id = r.transacao and z.tipo = v_tipo);
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $function$;

do $p$
begin
  if pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure) like '%pg_advisory_xact_lock(hashtext(''hotmart.evento:%'
     or pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure) not like '%on conflict (ref_id, tipo) where ref_tipo = ''hotmart.transacao'' do nothing%'
     or pg_get_functiondef('pessoas.carga_fin_hotmart(bigint,text,integer,boolean)'::regprocedure) not like '%if n_x = 0 then%' then
    raise exception '230255: pós-condição falhou, corpo novo não ficou no ar';
  end if;
end $p$;
