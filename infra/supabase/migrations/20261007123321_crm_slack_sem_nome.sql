-- 20261007a_crm_slack_sem_nome — avisos do CRM no Slack (#comercial) sem nome nem e-mail da pessoa
-- STATUS: APLICADA em 07/10/2026 — versão 20261007123321 (crm_slack_sem_nome), md5 do statement gravado = f548fa9ad365dba1cd13d50c640eef67
-- (= md5 deste arquivo antes desta linha de STATUS; só o comentário de STATUS mudou depois do apply)
--
-- Decisão do Arthur (07/10/2026): cada aviso traz um RESUMO e o LINK da ficha no CRM; nunca nome nem parte do e-mail.
-- Antes: ":rotating_light: *Chargeback* · <prefixo do e-mail> · Acelera Holding · R$ 1,997.00 · vendedor: sem dono · <link>".
-- Agora: emoji + tipo · linha › produto · R$ 1.997,00 (pt-BR) · forma de pagamento · vendedor: <primeiro nome do dono |
--        sem dono> · compra em DD/MM/AAAA (há N dias) · <https://grupoparticipa.app.br/comercial/funil?negocio=<id>|Abrir ficha>
-- Oferta órfã: mesmo resumo + <.../comercial/produtos|Abrir Produtos>. Erro: + <.../comercial/configuracoes#integracoes|Abrir Integrações>.
--
-- Escritores de crm.slack_fila (pg_proc vivo, 07/10/2026): crm.hotmart_processar (oferta_orfa, reembolso, chargeback,
-- disputa) e crm.hotmart_entrada (erro_hotmart). Só o texto muda; a lógica de processamento é a mesma (provado no ensaio).
-- Corpos partem do VIVO (pg_get_functiondef): hotmart_processar recriada na 20261006191824 (Victor).
-- Novas: crm.slack_brl, crm.slack_metodo, crm.slack_texto_negocio (internas: só postgres executa, como as demais crm.slack_*).
-- Reversão: recriar as duas funções com os corpos de md5 8604952e… / 1e9fb858… (em 20261007a.explain.md §Reversão) e
-- dropar as 3 helpers. Kill-switch de sempre: update crm.config set slack_ligado = false.

do $guarda$
begin
  if md5(pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) <> '8604952ead5094677bb96298b6158716' then
    raise exception '20261007a: crm.hotmart_processar mudou desde a leitura (md5 vivo ≠ 8604952e…). Reler e refazer.';
  end if;
  if md5(pg_get_functiondef('crm.hotmart_entrada(jsonb)'::regprocedure)) <> '1e9fb8581fcc231f816e200b43985163' then
    raise exception '20261007a: crm.hotmart_entrada mudou desde a leitura (md5 vivo ≠ 1e9fb858…). Reler e refazer.';
  end if;
  if to_regprocedure('crm.slack_enfileirar(text,text,text)') is null or to_regprocedure('crm.slack_esc(text)') is null then
    raise exception '20261007a: faltam crm.slack_enfileirar/crm.slack_esc (F3).';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'crm' and p.proname in ('slack_brl', 'slack_metodo', 'slack_texto_negocio')) then
    raise exception '20261007a: crm.slack_brl/slack_metodo/slack_texto_negocio já existem.';
  end if;
end
$guarda$;

-- Valor em pt-BR, independente de lc_numeric (o banco está em en_US): 1997 → "R$ 1.997,00".
create function crm.slack_brl(p numeric)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select case when p is null then null
              else 'R$ ' || translate(to_char(round(p, 2), 'FM999,999,999,990.00'), ',.', '.,') end;
$function$;

-- Forma de pagamento da Hotmart em português (valores medidos em pessoas.eventos.detalhe->>'metodo').
create function crm.slack_metodo(p text)
 returns text
 language sql
 immutable
 set search_path to ''
as $function$
  select case
    when nullif(btrim(p), '') is null or upper(p) = 'UNKNOWN' then null
    when upper(p) like 'CREDIT_CARD%' or upper(p) = 'UNKNOWN_CREDIT_CARD' then 'cartão'
    when upper(p) = 'BILLET' then 'boleto'
    when upper(p) = 'PIX' then 'Pix'
    when upper(p) = 'HOTMART_INSTALLMENTS' then 'parcelado Hotmart'
    when upper(p) = 'PAYPAL' then 'PayPal'
    when upper(p) = 'APPLE_PAY' then 'Apple Pay'
    when upper(p) = 'GOOGLE_PAY' then 'Google Pay'
    when upper(p) = 'NUPAY' then 'NuPay'
    when upper(p) = 'HYBRID' then 'híbrido'
    when upper(p) = 'HOTMART' then 'Hotmart'
    else crm.slack_esc(replace(lower(left(p, 40)), '_', ' '))
  end;
$function$;

-- Resumo de aviso de um negócio, SEM nome/e-mail da pessoa. Vendedor = primeiro nome do dono (perfil da equipe).
create function crm.slack_texto_negocio(p_emoji text, p_titulo text, p_negocio uuid, p_linha text, p_produto text, p_metodo text)
 returns text
 language sql
 stable
 set search_path to ''
as $function$
  select coalesce(
    (select format('%s *%s* · %s · %s%s · vendedor: %s%s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|Abrir ficha>',
              p_emoji, p_titulo,
              crm.slack_esc(case when nullif(btrim(p_produto), '') is null then coalesce(p_linha, '?')
                                 when p_linha is null or lower(btrim(p_produto)) = lower(btrim(p_linha)) then p_produto
                                 else p_linha || ' › ' || p_produto end),
              coalesce(crm.slack_brl(n.valor), 'valor não informado'),
              coalesce(' · ' || crm.slack_metodo(p_metodo), ''),
              crm.slack_esc(case when n.dono_id is null then 'sem dono'
                                 else coalesce(nullif(split_part(btrim(pf.nome), ' ', 1), ''), 'sem nome') end),
              case when n.fechado_em is null then ''
                   else ' · compra em ' || to_char(n.fechado_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY') || ' ('
                        || case z.dias when 0 then 'hoje' when 1 then 'há 1 dia' else 'há ' || z.dias || ' dias' end || ')' end,
              n.id)
       from crm.negocio n
       left join public.perfis pf on pf.id = n.dono_id
       cross join lateral (select (now() at time zone 'America/Sao_Paulo')::date
                                  - (n.fechado_em at time zone 'America/Sao_Paulo')::date as dias) z
      where n.id = p_negocio),
    format('%s *%s* · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|Abrir ficha>', p_emoji, p_titulo, p_negocio));
$function$;

-- crm.hotmart_processar: corpo VIVO (md5 8604952e…) com só os 3 textos de Slack trocados
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

-- crm.hotmart_entrada: corpo VIVO (md5 1e9fb858…) com só o texto do aviso de erro trocado
CREATE OR REPLACE FUNCTION crm.hotmart_entrada(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v text; v_s text; v_m text;
begin
  if p is null then return 'ignorado'; end if;
  if not coalesce((select c.hotmart_ligado from crm.config c), false) then return 'desligado'; end if;
  if (select c.hotmart_desde from crm.config c) is null then return 'desligado: falta hotmart_desde'; end if;
  begin
    v := crm.hotmart_processar(p);
  exception when others then
    get stacked diagnostics v_s = returned_sqlstate, v_m = message_text;
    v := left('erro: ' || v_s || ' ' || v_m, 300);
    begin
      insert into crm.hotmart_processado (chave, fonte, ref, conta, classe, transacao, produto_id, oferta_codigo, resultado)
      values (p ->> 'chave', p ->> 'fonte', p ->> 'ref', p ->> 'conta', p ->> 'classe', p ->> 'transacao', p ->> 'produto_id',
              p ->> 'oferta_codigo', v)
      on conflict (chave) do update
         set resultado = excluded.resultado, processado_em = now(),
             tentativas = crm.hotmart_processado.tentativas + case when coalesce((p ->> 'forcar')::boolean, false) then 1 else 0 end;
      perform crm.slack_enfileirar('erro_hotmart', p ->> 'chave',
        -- 20261007a: chave = conta + transação/id do evento (sem dado de pessoa); link para o painel Hotmart
        format(':x: *Hotmart → CRM falhou* · %s · %s (%s) · reprocessar depois de corrigir · <https://grupoparticipa.app.br/comercial/configuracoes#integracoes|Abrir Integrações>',
               crm.slack_esc(p ->> 'classe'), crm.slack_esc(p ->> 'chave'), crm.slack_esc(v_s)));
    exception when others then
      raise warning 'crm.hotmart_entrada: não registrou o erro (%): %', sqlstate, sqlerrm;
    end;
  end;
  perform set_config('crm.canal', '', true);
  perform set_config('crm.resumo', '', true);
  perform set_config('crm.ganho_hotmart', 'off', true);
  return v;
end
$function$;

-- Grants iguais aos de antes: só postgres executa (create or replace preserva o ACL das duas; as novas nascem com PUBLIC).
revoke all on function crm.slack_brl(numeric) from public, anon, authenticated, service_role;
revoke all on function crm.slack_metodo(text) from public, anon, authenticated, service_role;
revoke all on function crm.slack_texto_negocio(text, text, uuid, text, text, text) from public, anon, authenticated, service_role;
revoke all on function crm.hotmart_processar(jsonb) from public, anon, authenticated, service_role;
revoke all on function crm.hotmart_entrada(jsonb) from public, anon, authenticated, service_role;

do $confere$
declare v text;
begin
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, 'null'), ', ' order by p.proname) into v
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'crm' and p.proname in ('slack_brl', 'slack_metodo', 'slack_texto_negocio', 'hotmart_processar', 'hotmart_entrada')
     and coalesce(p.proacl::text, '') <> '{postgres=X/postgres}';
  if v is not null then raise exception '20261007a: ACL inesperado: %', v; end if;
  if crm.slack_brl(1997) <> 'R$ 1.997,00' or crm.slack_brl(2537.16) <> 'R$ 2.537,16' or crm.slack_brl(0) <> 'R$ 0,00' then
    raise exception '20261007a: crm.slack_brl não formatou em pt-BR';
  end if;
end
$confere$;
