-- 20261006191824: CRM Comercial: tira os negócios "ganhos" retroativos da carga Hotmart, compra direta não cria
-- ganho daqui para frente e a lista do vendedor deixa de mostrar contato sem dono e sem negócio aberto.
--
-- STATUS: APLICADA em 06/10/2026 (ensaio no banco real antes: 24 OK; depois: 1.026 negócios, 0 ganhos, 2.648 contatos, backup 2.640). Decidida pelo Victor em 06/10/2026. Ensaio: 20261006191824_ensaio.sql (begin … rollback).
-- Notas: 20261006191824.explain.md. Doc: docs/projetos/comercial/hotmart-sem-retroativo-2026-10-06.md.
--
-- O PROBLEMA: em 06/10/2026 12:39:07 UTC (09:39 Brasília) a config passou a hotmart_ligado = true com
--   hotmart_desde = 2026-01-01 (crm.log id 1920721). Em 2 minutos o crm.hotmart_processar criou 2.640 negócios
--   status 'ganho', origem 'compra_aprovada', sem dono, nos 4 funis "Checkout e recuperação · HT/HM/Acelera/Aurum",
--   um por compra aprovada desde 01/01, e 1.742 contatos comerciais só de compra. Contraria a D8 do Arthur
--   ("sem negócio retroativo", backend-arquitetura.md §D8), infla as vendas do comercial e estoura as listas.
--
-- O QUE FAZ:
--   1. Seleciona com precisão os negócios da carga retroativa (todas as condições juntas):
--      origem 'compra_aprovada', status 'ganho', dono_id nulo, funil tipo 'hotmart', criado entre o marco e marco+10 min,
--      e uma linha em crm.hotmart_processado com negocio_id = o negócio, classe 'aprovada', resultado
--      'ganho: negócio novo', processada no mesmo intervalo, com aprovação (quando) ANTES do marco.
--      E nunca tocado por gente: sem atividade, sem nota, sem linha de crm.log de autor 'pessoa' ou 'mcp'.
--   2. Backup completo em arquivo.*_20261006 (mesma estrutura das tabelas de origem, para restaurar com insert … select):
--      crm_negocio_retro_20261006 (os negócios), crm_hotmart_processado_retro_20261006 (as linhas que apontam para eles,
--      inclusive chargeback/disputa), crm_log_retro_20261006 (cópia do histórico deles; o crm.log é imutável e fica),
--      crm_atividade_retro_20261006, crm_nota_retro_20261006, crm_notificacao_retro_20261006 (0 linhas em 06/10, criadas
--      para a prova ficar completa), crm_slack_fila_retro_20261006 (avisos de chargeback/disputa dessas transações).
--   3. Tira os negócios de crm.negocio (1 linha "excluiu" por negócio em crm.log, canal 'migracao', com o motivo) e
--      em crm.hotmart_processado zera negocio_id e marca o resultado com "· arquivado 20261006191824".
--      As PESSOAS e os contatos comerciais continuam; a compra continua na ficha (pessoas.eventos 'compra' e
--      crm_jornada, que lê fin.hotmart_transacoes). Nada em fin.* nem em cs.* é tocado.
--   4. crm.hotmart_processar: compra aprovada SEM negócio aberto da pessoa na linha não cria negócio ganho nem contato
--      comercial (resultado 'jornada: compra sem negócio aberto (não cria ganho)'). COM negócio aberto, ele vira ganho
--      como antes. Carrinho, cartão recusado, boleto/pix e expirada continuam criando negócio aberto. A regra
--      "quem comprou a linha em 30 dias não entra em recuperação" passa a olhar também a compra na jornada.
--   5. public.crm_contatos: na LISTA (sem p_busca), o vendedor deixa de ver contato sem dono que não tem negócio aberto
--      (nem negócio sem dono, que ele já enxerga no funil). Na BUSCA (p_busca), continua vendo todo sem dono. Gestor vê
--      tudo. Máscara de e-mail/telefone, RLS e crm.pode_ver_pessoa (ficha) NÃO mudam.
--
-- O QUE NÃO FAZ: não mexe em fin.hotmart_transacoes, na trava fin.trava_conta_hotmart, em cs.hotmart_eventos, nos
--   triggers da F3, em crm.config (hotmart_desde continua 2026-01-01: o backfill semanal só gera jornada), nos funis
--   (o evento 'compra_aprovada' dos funis passa a não ter efeito), em pessoas.* nem em crm.pessoa_comercial.
--   crm.linha não tem unidade (CSM/Escritório): registrado como pendência no doc, sem coluna nova.
--
-- GUARDA: aborta se o marco de crm.log mudou, se o corpo vivo de hotmart_processar ou crm_contatos não for o lido em
--   06/10 (md5 do pg_get_functiondef), se as tabelas de backup já existirem, ou se a seleção não der exatamente 2.640
--   negócios (número medido em 06/10; se mudou, remedir e regerar antes de aplicar).
-- LOCK: linhas dos 2.640 negócios (ninguém mexe neles) e create or replace das 2 funções (instantâneo).
-- REVERSÃO: bloco no fim deste arquivo (comentado).

do $guarda$
declare v_n int;
begin
  if not exists (select 1 from crm.log l where l.id = 1920721 and l.entidade = 'config'
                    and l.em = '2026-10-06 12:39:07.927731+00'
                    and l.mudancas @> '[{"campo": "hotmart_ligado", "para": true}]'::jsonb) then
    raise exception '20261006191824: marco de crm.log (id 1920721, hotmart ligado em 06/10 12:39:07 UTC) não confere';
  end if;
  if md5(pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) <> '2ecc46733e92a5268621c7bb7baeb9bd' then
    raise exception '20261006191824: corpo vivo de crm.hotmart_processar mudou desde 06/10 (md5 diferente); reler e regerar';
  end if;
  if md5(pg_get_functiondef('public.crm_contatos(text,integer,integer)'::regprocedure)) <> '59751a23c6f4769264ba3a7c046ce7f4' then
    raise exception '20261006191824: corpo vivo de public.crm_contatos mudou desde 06/10 (md5 diferente); reler e regerar';
  end if;
  if exists (select 1 from pg_class c join pg_namespace s on s.oid = c.relnamespace
              where s.nspname = 'arquivo' and c.relname like 'crm\_%\_retro\_20261006') then
    raise exception '20261006191824: já existe tabela arquivo.crm_*_retro_20261006 (migration já rodou?)';
  end if;
end
$guarda$;

-- ─── 1. Seleção ───────────────────────────────────────────────────────────────────────────────────────────────────
create temp table _retro on commit drop as
with marco as (select '2026-10-06 12:39:07.927731+00'::timestamptz m)
select n.id
  from crm.negocio n
  join crm.funil f on f.id = n.funil_id
 cross join marco
 where n.origem = 'compra_aprovada' and n.status = 'ganho' and n.dono_id is null and f.tipo = 'hotmart'
   and n.criado_em >= marco.m and n.criado_em < marco.m + interval '10 minutes'
   and exists (select 1 from crm.hotmart_processado h
                where h.negocio_id = n.id and h.classe = 'aprovada' and h.resultado = 'ganho: negócio novo'
                  and h.quando < marco.m
                  and h.processado_em >= marco.m and h.processado_em < marco.m + interval '10 minutes')
   and not exists (select 1 from crm.atividade a where a.negocio_id = n.id)
   and not exists (select 1 from crm.nota x where x.negocio_id = n.id)
   and not exists (select 1 from crm.log l where l.entidade = 'negocio' and l.entidade_id = n.id::text
                                             and l.autor_tipo in ('pessoa', 'mcp'));
create unique index on _retro (id);

do $conta$
declare v_n int := (select count(*) from _retro);
begin
  if v_n <> 2640 then
    raise exception '20261006191824: seleção deu % negócios (esperado 2.640, medido em 06/10); remedir antes de aplicar', v_n;
  end if;
end
$conta$;

-- ─── 2. Backup completo (arquivo.*, sem acesso pela API) ───────────────────────────────────────────────────────────
create table arquivo.crm_negocio_retro_20261006 as
  select n.* from crm.negocio n where n.id in (select id from _retro);
create table arquivo.crm_hotmart_processado_retro_20261006 as
  select h.* from crm.hotmart_processado h where h.negocio_id in (select id from _retro);
create table arquivo.crm_log_retro_20261006 as
  select l.* from crm.log l where l.entidade = 'negocio' and l.entidade_id in (select id::text from _retro);
create table arquivo.crm_atividade_retro_20261006 as
  select a.* from crm.atividade a where a.negocio_id in (select id from _retro);
create table arquivo.crm_nota_retro_20261006 as
  select x.* from crm.nota x where x.negocio_id in (select id from _retro);
create table arquivo.crm_notificacao_retro_20261006 as
  select x.* from crm.notificacao x where x.ref_id in (select id::text from _retro);
create table arquivo.crm_slack_fila_retro_20261006 as
  select s.* from crm.slack_fila s
   where s.ref in (select n.transacao_ganho from crm.negocio n where n.id in (select id from _retro));

do $perm$
declare t text;
begin
  foreach t in array array['crm_negocio_retro_20261006', 'crm_hotmart_processado_retro_20261006', 'crm_log_retro_20261006',
                           'crm_atividade_retro_20261006', 'crm_nota_retro_20261006', 'crm_notificacao_retro_20261006',
                           'crm_slack_fila_retro_20261006'] loop
    execute format('revoke all on table arquivo.%I from public, anon, authenticated, service_role', t);
    execute format('comment on table arquivo.%I is %L', t,
      'Backup de 20261006191824 (negócios ganhos retroativos da carga Hotmart de 06/10/2026, D8). Nunca DROP sem decisão do Victor.');
  end loop;
end
$perm$;

do $confere_backup$
begin
  if (select count(*) from arquivo.crm_negocio_retro_20261006) <> (select count(*) from _retro) then
    raise exception '20261006191824: backup de negócios incompleto';
  end if;
  if (select count(*) from arquivo.crm_atividade_retro_20261006) + (select count(*) from arquivo.crm_nota_retro_20261006) > 0 then
    raise exception '20261006191824: há atividade/nota nos negócios selecionados (não deveria: a seleção exclui)';
  end if;
end
$confere_backup$;

-- ─── 3. Tira os negócios (1 linha de crm.log por negócio, com motivo) ───────────────────────────────────────────────
update crm.hotmart_processado h
   set negocio_id = null, resultado = left(h.resultado || ' · arquivado 20261006191824', 300)
 where h.negocio_id in (select id from _retro);

do $tira$
declare r record;
begin
  perform set_config('crm.canal', 'migracao', true);
  for r in select id from _retro order by id loop
    perform set_config('crm.resumo',
      'Negócio ganho retroativo da carga Hotmart de 06/10 (D8) arquivado em arquivo.crm_negocio_retro_20261006', true);
    delete from crm.negocio n where n.id = r.id;
  end loop;
  perform set_config('crm.resumo', '', true);
  perform set_config('crm.canal', '', true);
end
$tira$;

-- ─── 4. Compra aprovada sem negócio aberto não cria ganho ──────────────────────────────────────────────────────────
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
  select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
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
        format(':label: *Oferta fora do catálogo* · %s · oferta %s (conta %s). Catalogar hoje em Comercial › Produtos%s.',
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
      select * into n from crm.negocio x
       where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
       order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
       limit 1 for update;
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
                    join crm.produto_comercial y on y.produto_id = e.detalhe ->> 'produto' and y.no_comercial and y.linha = pc.linha
                   where e.pessoa_id = any(v_g) and e.tipo = 'compra' and e.fonte = 'hotmart'
                     and e.quando > now() - interval '30 days') then
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
      perform crm.slack_enfileirar(v_classe, coalesce(v_tx, v_chave),
        format(':rotating_light: *%s* · %s · %s · R$ %s · vendedor: %s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|abrir negócio>',
               case when v_classe = 'reembolso' then 'Reembolso' else 'Chargeback' end,
               crm.slack_esc(crm.primeiro_nome(v_atual)), crm.slack_esc(coalesce(v_linha_nome, pc.linha)),
               to_char(n.valor, 'FM999G999G990D00'), crm.slack_esc(crm.nome_perfil(n.dono_id)), n.id));
    else
      v_resultado := 'jornada: sem negócio ganho desta transação';
    end if;

  elsif v_classe = 'disputa' then
    select * into n from crm.negocio x where v_tx is not null and x.transacao_ganho = v_tx;
    if found then
      v_neg := n.id; v_resultado := 'disputa_avisada';
      perform crm.slack_enfileirar('disputa', coalesce(v_tx, v_chave),
        format(':warning: *Disputa aberta na Hotmart* · %s · %s · R$ %s · vendedor: %s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|abrir negócio>',
               crm.slack_esc(crm.primeiro_nome(v_atual)), crm.slack_esc(coalesce(v_linha_nome, pc.linha)),
               to_char(n.valor, 'FM999G999G990D00'), crm.slack_esc(crm.nome_perfil(n.dono_id)), n.id));
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
$function$

;

-- Grants: os mesmos de antes (só postgres executa; quem chama é o trigger da F3). Reafirmados.
revoke all on function crm.hotmart_processar(jsonb) from public, anon, authenticated, service_role;

-- ─── 5. Lista do vendedor sem o sem-dono parado ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crm_contatos(p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_t text := nullif(btrim(coalesce(p_busca, '')), '');
  v_email text; v_fk text; v_like text; v_ids uuid[];
  v jsonb;
begin
  perform crm.exige_comercial();
  if v_t is not null then
    if length(v_t) < 3 then return jsonb_build_object('itens', '[]'::jsonb, 'temMais', false); end if;
    v_email := pessoas.norm_email(v_t);
    v_fk := pessoas.chave_telefone(v_t);
    v_like := case when v_email is null and v_fk is null
                   then '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
    -- candidatos por índice (mesmas expressões da F0), depois o grupo de cada um
    v_ids := array(
      select distinct pessoas.atual(s.x) from (
        select i.pessoa_id x from pessoas.identificadores i where v_email is not null and i.tipo = 'email' and i.chave = v_email
        union select i.pessoa_id from pessoas.identificadores i where v_fk is not null and i.tipo = 'telefone' and i.chave = v_fk
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_email is not null and lower(btrim(a.email)) = v_email and a.email is not null and a.email <> ''
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_email is not null and lower(btrim((c.email)::text)) = v_email
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_fk is not null and controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = v_fk and a.cancelado_em is null
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_fk is not null and controle.fone_key((c.telefone)::text) = v_fk and c.telefone is not null
        union (select p.id from pessoas.pessoas p where v_like is not null and p.nome is not null and p.nome ilike v_like limit 200)
        union (select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
                where v_like is not null and a.nome ilike v_like limit 200)
      ) s);
    v_ids := array(select g from unnest(v_ids) u, unnest(pessoas.grupo(u)) g);
  end if;

  select coalesce(jsonb_agg(x.j order by x.criado_em desc, x.pid), '[]'::jsonb) into v from (
    select pc.criado_em, pc.pessoa_id pid, jsonb_build_object(
             'id', atu.id, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when pc.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when pc.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(al.cidade, cp.endereco_cidade::text),
             'uf', case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em) j
      from (select pc0.*, (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())) completo
              from crm.pessoa_comercial pc0
              join pessoas.pessoas pp on pp.id = pc0.pessoa_id
             where (v_ids is null or pc0.pessoa_id = any(v_ids))
               and (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())
                    -- 20261006191824: sem dono só entra na LISTA do vendedor se tiver negócio aberto (ou negócio sem dono,
                    -- que o vendedor já vê no funil). Na BUSCA (p_busca) continua valendo todo sem dono, como antes.
                    or (pc0.dono_id is null
                        and (v_ids is not null
                             or exists (select 1 from crm.negocio n
                                         where n.pessoa_id in (pc0.pessoa_id, pessoas.atual(pc0.pessoa_id))
                                           and (n.status = 'aberto' or n.dono_id is null)))))
               and (pp.situacao <> 'mesclada'   -- alias: vale a linha da pessoa atual, se ela tiver camada comercial
                    or not exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = pessoas.atual(pc0.pessoa_id)))
             order by pc0.criado_em desc, pc0.pessoa_id
             limit v_lim + 1 offset v_off) pc
      cross join lateral (select pessoas.atual(pc.pessoa_id) id) atu
      cross join lateral pessoas.dados(atu.id) d
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id) x;
  return jsonb_build_object('itens', coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v) with ordinality t(e, o) where o <= v_lim), '[]'::jsonb),
                            'temMais', jsonb_array_length(v) > v_lim);
end
$function$

;

-- Grants: os mesmos de antes (authenticated e service_role executam; public/anon não). Reafirmados.
revoke all on function public.crm_contatos(text, integer, integer) from public, anon;
grant execute on function public.crm_contatos(text, integer, integer) to authenticated, service_role;

do $confere$
begin
  if exists (select 1 from crm.negocio n where n.id in (select id from _retro)) then
    raise exception '20261006191824: sobrou negócio selecionado em crm.negocio';
  end if;
  if exists (select 1 from crm.hotmart_processado h where h.negocio_id in (select id from _retro)) then
    raise exception '20261006191824: crm.hotmart_processado ainda aponta para negócio arquivado';
  end if;
  if position('não cria ganho' in pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) = 0
     or position('''compra_aprovada'', ''ganho''' in pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) > 0 then
    raise exception '20261006191824: crm.hotmart_processar não ficou com a regra nova';
  end if;
  if has_function_privilege('anon', 'public.crm_contatos(text,integer,integer)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'crm.hotmart_processar(jsonb)'::regprocedure, 'execute') then
    raise exception '20261006191824: permissão errada nas funções recriadas';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não roda; copiar e executar em begin … commit se precisar desfazer) ═════════════════════════════════
-- 1. Funções: recriar crm.hotmart_processar e public.crm_contatos com o corpo de antes (pg_get_functiondef de 06/10,
--    md5 2ecc46733e92a5268621c7bb7baeb9bd e 59751a23c6f4769264ba3a7c046ce7f4; corpos em 20261006043612_crm_f3_hotmart.sql
--    e 20261005s_crm_f1_leitura.sql, conferir contra o md5).
-- 2. Negócios (o log de "criou" de cada um fica um a mais; o crm.log é imutável):
--    set local crm.canal = 'migracao';
--    insert into crm.negocio select * from arquivo.crm_negocio_retro_20261006;
--      (os triggers BEFORE de crm.negocio validam ganho: rodar com  select set_config('crm.ganho_hotmart', 'on', true);
--       antes do insert e 'off' depois, igual ao crm.hotmart_processar)
--    update crm.hotmart_processado h set negocio_id = b.negocio_id, resultado = b.resultado
--      from arquivo.crm_hotmart_processado_retro_20261006 b where b.chave = h.chave;
-- 3. As tabelas arquivo.crm_*_retro_20261006 ficam (nunca DROP sem decisão do Victor).
