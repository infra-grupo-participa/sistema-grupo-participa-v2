-- 20261008233100: CRM, envio de WhatsApp pelo Claude (MCP do Comercial), com as travas no servidor
--
-- STATUS: APLICADA em produção em 08/10/2026 (versão 20261008233100 gravada em schema_migrations). Ensaio 31/31 ok.
--
-- POR QUE
--   Decisão do Arthur (08/10/2026, "A."): liberar o envio de WhatsApp pelo Claude via MCP, pedido do Marcos (abrir
--   conversa com template pelo número oficial e seguir em texto livre depois da resposta; ou texto livre direto pelo
--   número QR). Regras aprovadas: só gestor ou dono do contato (D6); limites anti-ban dos números QR; cada envio
--   registrado como "enviado pelo Claude"; o Claude confirma com o usuário antes de cada envio (descrição da ferramenta).
--
-- O QUE FAZ
--   a. crm.config: mcp_envio_ligado (kill-switch próprio, default true, independente de envio_ligado),
--      mcp_envio_limite_hora (30 envios por usuário por hora) e mcp_envio_intervalo_contato_s (1 envio por contato a
--      cada 20 s).
--   b. crm.mensagem.origem ('mcp' ou null) + índice parcial (autor_id, em) where origem = 'mcp' (limite por hora).
--      crm.mensagem_json devolve 'origem' (a bolha mostra "via Claude").
--   c. crm.mcp_canal(p_atual, p_canal): número de envio. O pedido; senão o da conversa mais recente da pessoa (não
--      excluída); senão o oficial. Mesma regra de public.crm_enviar_mensagem. Sem grant para a API.
--      crm.mcp_conversa(p_canal, p_atual): a conversa que o envio usaria (mesma escolha de crm.whatsapp_conversa_para,
--      só leitura, sem criar). A janela de 24 h é contada POR NÚMERO e ignora conversa excluída.
--   d. public.crm_mcp_numeros(): números que a pessoa pode usar (nome, Oficial/QR, status, 4 últimos dígitos, envia?).
--   e. public.crm_mcp_templates(p_busca, p_limite): templates aprovados do número oficial (nome, idioma, categoria,
--      variáveis, prévia do texto, usavel = até 1 variável, que é o primeiro nome preenchido pelo CRM).
--   f. public.crm_mcp_situacao_conversa(p_contato, p_canal, p_template): pode texto livre? (QR sempre; oficial só com
--      a janela aberta), quando a janela fecha, destinatário (nome + 4 últimos dígitos), bloqueios, prévia do template.
--   g. public.crm_mcp_enviar_whatsapp(p_contato, p_chave, p_texto, p_template, p_canal): só pelo MCP (claim
--      gp_canal = 'mcp'). crm.guarda_escrita (leitor, escrita_ligada) → mcp_envio_ligado → chave obrigatória e
--      idempotente → D6 → opt-out → limites do MCP (por usuário/hora e por contato/intervalo, com advisory lock) →
--      número e template → janela de 24 h no oficial ("precisa template") → public.crm_enviar_mensagem (as travas da
--      tela: envio_ligado, evolution_ligado, número conectado, anti-ban/massa no trigger crm.tg_mensagem_canal, fila).
--      Marca a mensagem com origem = 'mcp'. Autor = dono do token (auth.uid()). Registro: crm.log_registrar já grava
--      canal/autor_tipo 'mcp' e o resumo NÃO tem o texto da mensagem.
--   h. public.crm_mcp_rpc: + as 4 RPCs na lista 'operar'. crm_enviar_mensagem continua FORA da lista.
--   i. Grants: RPCs novas só authenticated/service_role (revoke de PUBLIC e anon); helpers crm.* sem grant.
--
-- FILA: a mensagem entra em crm.mensagem com status 'na_fila'. O atalho de envio (crm.whatsapp_disparar_envio /
--   crm.evolution_disparar_envio) usa pg_net, que só envia depois do COMMIT; o cron de 1 min só vê linha commitada.
--
-- REVERSÃO: 20261008233100_reversao.sql. Kill-switch: crm.config.mcp_envio_ligado = false (ou mcp_ligado = false).

do $$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crm_mcp_rpc(uuid,text,jsonb)'::regprocedure)
     is distinct from '9753efed2b1ea8b07a68b5629931d407' then
    raise exception 'premissa: public.crm_mcp_rpc mudou desde a leitura (md5 9753efed…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'crm.mensagem_json(crm.mensagem,uuid)'::regprocedure)
     is distinct from '628ca5e6b7ae7eff56f44078bb77b718' then
    raise exception 'premissa: crm.mensagem_json mudou desde a leitura (md5 628ca5e6…)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.crm_enviar_mensagem(uuid,text,uuid,text,text,uuid,uuid)'::regprocedure)
     is distinct from '4be7d653b4f8d028947fb2ed87d92713' then
    raise exception 'premissa: public.crm_enviar_mensagem mudou desde a leitura (md5 4be7d653…)';
  end if;
  if exists (select 1 from information_schema.columns where table_schema = 'crm'
               and ((table_name = 'config' and column_name in ('mcp_envio_ligado', 'mcp_envio_limite_hora', 'mcp_envio_intervalo_contato_s'))
                 or (table_name = 'mensagem' and column_name = 'origem'))) then
    raise exception 'premissa: colunas novas já existem';
  end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace
               and p.proname in ('crm_mcp_numeros', 'crm_mcp_templates', 'crm_mcp_situacao_conversa', 'crm_mcp_enviar_whatsapp')) then
    raise exception 'premissa: RPCs crm_mcp_* de WhatsApp já existem';
  end if;
  if (select count(*) from crm.config) <> 1 then
    raise exception 'premissa: crm.config precisa ter exatamente 1 linha';
  end if;
end $$;

-- ─── a. config ──────────────────────────────────────────────────────────────────────────────────────────────────────
alter table crm.config
  add column mcp_envio_ligado boolean not null default true,
  add column mcp_envio_limite_hora smallint not null default 30 check (mcp_envio_limite_hora between 1 and 500),
  add column mcp_envio_intervalo_contato_s smallint not null default 20 check (mcp_envio_intervalo_contato_s between 0 and 3600);

-- ─── b. origem da mensagem ──────────────────────────────────────────────────────────────────────────────────────────
alter table crm.mensagem add column origem text check (origem in ('mcp'));
create index mensagem_mcp_autor_idx on crm.mensagem (autor_id, em desc) where origem = 'mcp';

create or replace function crm.mensagem_json(m crm.mensagem, p_contato uuid)
 returns jsonb
 language sql
 immutable
 set search_path to ''
as $function$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao, 'tipo', m.tipo, 'texto', m.texto, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id,
    'canalId', m.numero_id, 'externa', m.externa, 'origem', m.origem,  -- 20261009060000: 'mcp' = enviada pelo Claude
    'midia', case when m.midia_status is not null then jsonb_build_object(
               'status', m.midia_status, 'caminho', case when m.midia_status = 'ok' then m.midia_caminho end,
               'mime', m.midia_mime, 'tamanho', m.midia_tamanho, 'nome', m.midia_nome) end);
$function$;

-- ─── c. helpers (sem grant) ─────────────────────────────────────────────────────────────────────────────────────────
create function crm.mcp_canal(p_atual uuid, p_canal uuid)
 returns crm.numero_whatsapp
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare n crm.numero_whatsapp%rowtype;
begin
  -- mesma escolha de public.crm_enviar_mensagem: o pedido; senão a conversa mais recente; senão o oficial
  if p_canal is not null then
    select * into n from crm.numero_whatsapp x where x.id = p_canal;
    return n;
  end if;
  select x.* into n from crm.conversa k join crm.numero_whatsapp x on x.id = k.numero_id
   where k.pessoa_id = any(crm.grupo_rapido(p_atual)) and x.ativo and k.excluida_em is null
   order by k.ultima_em desc nulls last, k.criado_em desc limit 1;
  if not found then
    select x.* into n from crm.numero_whatsapp x join crm.config c on c.whatsapp_numero_id = x.id;
  end if;
  return n;
end
$function$;
revoke all on function crm.mcp_canal(uuid, uuid) from public, anon, authenticated;

create function crm.mcp_conversa(p_canal uuid, p_atual uuid)
 returns crm.conversa
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  -- mesma escolha de crm.whatsapp_conversa_para, só leitura (não cria conversa)
  select c.* from crm.conversa c
   where c.numero_id = p_canal and c.pessoa_id = any(crm.grupo_rapido(p_atual)) and c.excluida_em is null
   order by c.ultima_em desc nulls last, c.criado_em desc limit 1;
$function$;
revoke all on function crm.mcp_conversa(uuid, uuid) from public, anon, authenticated;

create function crm.mcp_template(p_canal uuid, p_template text)
 returns crm.template
 language sql
 stable
 security definer
 set search_path to ''
as $function$
  -- por id (uuid) ou pelo nome no provedor; só aprovado, ativo, marketing/utility, do número pedido
  select t.* from crm.template t
   where t.numero_id = p_canal and t.aprovado and t.ativo and t.categoria in ('marketing', 'utility')
     and (case when btrim(coalesce(p_template, '')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
               then t.id = btrim(p_template)::uuid
               else lower(t.nome_provedor) = lower(btrim(coalesce(p_template, ''))) end)
   order by t.idioma = 'pt_BR' desc, t.sincronizado_em desc limit 1;
$function$;
revoke all on function crm.mcp_template(uuid, text) from public, anon, authenticated;

-- ─── d. números ─────────────────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_mcp_numeros()
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); c crm.config%rowtype; v jsonb; v_escreve boolean := coalesce(crm.pode_escrever(), false);
begin
  perform crm.exige_comercial();
  select * into c from crm.config;
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', n.id, 'nome', n.nome, 'tipo', case when n.provedor = 'infobip' then 'Oficial' else 'QR' end,
           'status', n.status, 'final', right(regexp_replace(coalesce(n.numero, ''), '\D', '', 'g'), 4),
           'padrao', n.id = c.whatsapp_numero_id,
           'envia', v_escreve and coalesce(c.mcp_envio_ligado, false) and coalesce(c.envio_ligado, false) and n.envia
                    and case when n.provedor = 'evolution' then coalesce(c.evolution_ligado, false) and n.status = 'conectado'
                             else coalesce(c.whatsapp_ligado, false) end,
           'textoLivre', case when n.provedor = 'evolution' then 'sempre' else 'só com a janela de 24 h aberta (senão template)' end)
           order by (n.provedor = 'infobip') desc, n.criado_em), '[]'::jsonb)
    into v
    from crm.numero_whatsapp n
   where n.ativo and n.envia
     and (n.provedor = 'infobip' or n.dono_id is null or n.dono_id = v_eu or coalesce(crm.eh_gestor(v_eu), false));
  return crm.res(true, null, jsonb_build_object(
    'podeEnviar', v_escreve and coalesce(c.mcp_envio_ligado, false),
    'envioPeloClaudeLigado', coalesce(c.mcp_envio_ligado, false),
    'limites', jsonb_build_object('porHora', c.mcp_envio_limite_hora, 'intervaloContatoSeg', c.mcp_envio_intervalo_contato_s,
                                  'qrPorMinuto', c.evolution_limite_minuto, 'qrPorHora', c.evolution_limite_hora,
                                  'qrPrimeirosContatosHora', c.evolution_novos_hora),
    'numeros', v));
end
$function$;
revoke all on function public.crm_mcp_numeros() from public, anon;
grant execute on function public.crm_mcp_numeros() to authenticated, service_role;

-- ─── e. templates ───────────────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_mcp_templates(p_busca text default null, p_limite integer default 50)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_lim int := least(greatest(coalesce(p_limite, 50), 1), 200); v_b text := nullif(lower(btrim(coalesce(p_busca, ''))), '');
        v jsonb; v_total int;
begin
  perform crm.exige_comercial();
  if v_b is not null and length(v_b) > 80 then return crm.res(false, 'Busca longa demais.'); end if;
  select count(*) into v_total
    from crm.template t join crm.config c on c.whatsapp_numero_id = t.numero_id
   where t.aprovado and t.ativo and t.categoria in ('marketing', 'utility')
     and (v_b is null or strpos(lower(t.nome_provedor), v_b) > 0 or strpos(lower(coalesce(t.texto, '')), v_b) > 0);
  select coalesce(jsonb_agg(x.j order by x.nome), '[]'::jsonb) into v
    from (select t.nome_provedor as nome, jsonb_build_object(
                   'id', t.id, 'nome', t.nome_provedor, 'idioma', t.idioma, 'categoria', t.categoria, 'variaveis', t.variaveis,
                   'usavel', t.variaveis <= 1,
                   'previa', left(coalesce(t.texto, ''), 300) || case when length(coalesce(t.texto, '')) > 300 then '…' else '' end) as j
            from crm.template t join crm.config c on c.whatsapp_numero_id = t.numero_id
           where t.aprovado and t.ativo and t.categoria in ('marketing', 'utility')
             and (v_b is null or strpos(lower(t.nome_provedor), v_b) > 0 or strpos(lower(coalesce(t.texto, '')), v_b) > 0)
           order by t.nome_provedor limit v_lim) x;
  return crm.res(true, null, jsonb_build_object('total', v_total, 'temMais', v_total > v_lim, 'templates', v));
end
$function$;
revoke all on function public.crm_mcp_templates(text, integer) from public, anon;
grant execute on function public.crm_mcp_templates(text, integer) to authenticated, service_role;

-- ─── f. situação da conversa ────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_mcp_situacao_conversa(p_contato uuid, p_canal uuid default null, p_template text default null)
 returns jsonb
 language plpgsql
 stable
 security definer
 set search_path to ''
as $function$
declare v_atual uuid; n crm.numero_whatsapp%rowtype; cv crm.conversa%rowtype; c crm.config%rowtype; t crm.template%rowtype;
        v_aberta boolean; v_bloqueio text; v_prev jsonb; v_rend jsonb;
begin
  perform crm.exige_comercial();
  v_atual := pessoas.atual(p_contato);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then return crm.res(false, 'Contato não encontrado.'); end if;
  if not coalesce(crm.pode_escrever_pessoa(v_atual), false) then
    return crm.res(false, 'Este contato não é seu (envio só para o dono do contato ou gestor).');
  end if;
  select * into c from crm.config;
  n := crm.mcp_canal(v_atual, p_canal);
  if n.id is null then return crm.res(false, 'Número de WhatsApp não encontrado.'); end if;
  cv := crm.mcp_conversa(n.id, v_atual);
  v_aberta := cv.ultima_entrada_em is not null and cv.ultima_entrada_em > now() - interval '24 hours';
  v_bloqueio := case
    when not coalesce(c.mcp_envio_ligado, false) then 'Envio de WhatsApp pelo Claude desligado.'
    when not coalesce(c.envio_ligado, false) then 'Envio de WhatsApp desligado.'
    when not n.ativo or not n.envia then 'Este número não envia pelo CRM.'
    when n.provedor = 'evolution' and not coalesce(c.evolution_ligado, false) then 'WhatsApp por QR desligado.'
    when n.provedor = 'evolution' and n.status <> 'conectado' then 'Número desconectado: o gestor reconecta em Configurações.'
    when n.provedor = 'infobip' and not coalesce(c.whatsapp_ligado, false) then 'WhatsApp desligado.'
    when coalesce(crm.pessoa_optout(v_atual), false) then 'Contato pediu para não receber mensagens.'
  end;
  if p_template is not null then
    if n.provedor <> 'infobip' then
      v_prev := jsonb_build_object('ok', false, 'msg', 'Template é só do número oficial. Neste número, escreva a mensagem.');
    else
      t := crm.mcp_template(n.id, p_template);
      if t.id is null then
        v_prev := jsonb_build_object('ok', false, 'msg', 'Template não encontrado ou não aprovado no número oficial.');
      else
        v_rend := crm.template_render(t, v_atual, null);
        v_prev := case when (v_rend ->> 'ok')::boolean
                       then jsonb_build_object('ok', true, 'templateId', t.id, 'nome', t.nome_provedor, 'texto', v_rend ->> 'texto')
                       else jsonb_build_object('ok', false, 'msg', v_rend ->> 'msg') end;
      end if;
    end if;
  end if;
  return crm.res(true, null, jsonb_build_object(
    'contatoId', v_atual,
    'destinatario', jsonb_build_object('nome', crm.nome_pessoa(v_atual),
                                       'telefoneFinal', case when cv.telefone is not null then right(cv.telefone, 4) end),
    'numero', jsonb_build_object('id', n.id, 'nome', n.nome, 'tipo', case when n.provedor = 'infobip' then 'Oficial' else 'QR' end,
                                 'status', n.status, 'final', right(regexp_replace(coalesce(n.numero, ''), '\D', '', 'g'), 4)),
    'temConversaNesteNumero', cv.id is not null,
    'ultimaMensagemDoClienteEm', cv.ultima_entrada_em,
    'podeTextoLivre', n.provedor = 'evolution' or v_aberta,
    'precisaTemplate', n.provedor = 'infobip' and not v_aberta,
    'janelaFechaEm', case when n.provedor = 'infobip' and v_aberta then cv.ultima_entrada_em + interval '24 hours' end,
    'bloqueio', v_bloqueio,
    'template', v_prev));
end
$function$;
revoke all on function public.crm_mcp_situacao_conversa(uuid, uuid, text) from public, anon;
grant execute on function public.crm_mcp_situacao_conversa(uuid, uuid, text) to authenticated, service_role;

-- ─── g. envio pelo Claude ───────────────────────────────────────────────────────────────────────────────────────────
create function public.crm_mcp_enviar_whatsapp(p_contato uuid, p_chave uuid, p_texto text default null,
                                               p_template text default null, p_canal uuid default null)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; c crm.config%rowtype; v_atual uuid; n crm.numero_whatsapp%rowtype;
        cv crm.conversa%rowtype; t crm.template%rowtype; v_n int; v_dup uuid; v_dup_autor uuid; v_id uuid; v_texto text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if v_eu is null or coalesce(auth.jwt() ->> 'gp_canal', '') <> 'mcp' then
    return crm.res(false, 'Envio pelo Claude só pelo MCP do Comercial.');
  end if;
  select * into c from crm.config;
  if not coalesce(c.mcp_envio_ligado, false) then return crm.res(false, 'Envio de WhatsApp pelo Claude desligado.'); end if;
  if p_chave is null then return crm.res(false, 'Informe chave_idempotencia (um UUID novo por envio).'); end if;
  v_texto := nullif(btrim(coalesce(p_texto, '')), '');
  if (v_texto is null) = (nullif(btrim(coalesce(p_template, '')), '') is null) then
    return crm.res(false, 'Informe texto OU template (um dos dois).');
  end if;
  -- idempotência antes dos limites: o retry da mesma chave devolve a mesma mensagem
  select m.id, m.autor_id into v_dup, v_dup_autor from crm.mensagem m where m.chave = p_chave;
  if v_dup is not null then
    if v_dup_autor is distinct from v_eu then return crm.res(false, 'Chave de envio inválida.'); end if;
    return crm.res(true, 'Mensagem já enviada (mesma chave).', jsonb_build_object('mensagemId', v_dup, 'repetida', true));
  end if;
  v_atual := pessoas.atual(p_contato);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then return crm.res(false, 'Contato não encontrado.'); end if;
  if not coalesce(crm.pode_escrever_pessoa(v_atual), false) then
    return crm.res(false, 'Este contato não é seu (envio só para o dono do contato ou gestor).');
  end if;
  if coalesce(crm.pessoa_optout(v_atual), false) then return crm.res(false, 'Contato pediu para não receber mensagens.'); end if;
  -- limites do MCP (serializados por usuário e por contato até o commit)
  perform pg_advisory_xact_lock(hashtext('crm.mcp.envio.autor'), hashtext(v_eu::text));
  perform pg_advisory_xact_lock(hashtext('crm.mcp.envio.contato'), hashtext(v_atual::text));
  select count(*) into v_n from crm.mensagem m
   where m.origem = 'mcp' and m.autor_id = v_eu and m.em > now() - interval '1 hour';
  if v_n >= c.mcp_envio_limite_hora then
    return crm.res(false, format('Limite do Claude: %s envios por hora por pessoa. Tente mais tarde.', c.mcp_envio_limite_hora));
  end if;
  if c.mcp_envio_intervalo_contato_s > 0 and exists (
       select 1 from crm.mensagem m
        where m.pessoa_id = any(crm.grupo_rapido(v_atual)) and m.origem = 'mcp'
          and m.em > now() - make_interval(secs => c.mcp_envio_intervalo_contato_s)) then
    return crm.res(false, format('Espere %s s entre mensagens do Claude para o mesmo contato.', c.mcp_envio_intervalo_contato_s));
  end if;
  n := crm.mcp_canal(v_atual, p_canal);
  if n.id is null then return crm.res(false, 'Número de WhatsApp não encontrado.'); end if;
  if p_template is not null and btrim(p_template) <> '' then
    if n.provedor <> 'infobip' then return crm.res(false, 'Template é só do número oficial. Neste número, escreva a mensagem.'); end if;
    t := crm.mcp_template(n.id, p_template);
    if t.id is null then return crm.res(false, 'Template não encontrado ou não aprovado no número oficial.'); end if;
    if t.variaveis > 1 then return crm.res(false, 'Template com mais de 1 variável (link) só sai por ficha de disparo.'); end if;
  elsif n.provedor = 'infobip' then
    cv := crm.mcp_conversa(n.id, v_atual);
    if cv.ultima_entrada_em is null or cv.ultima_entrada_em <= now() - interval '24 hours' then
      return crm.res(false, 'Janela de 24 h fechada neste número: precisa template. Veja comercial_templates_whatsapp.');
    end if;
  end if;
  -- as travas da tela (envio_ligado, evolution_ligado, número conectado, anti-ban e massa no trigger) e a fila
  v_r := public.crm_enviar_mensagem(v_atual, v_texto, t.id, null, null, p_chave, n.id);
  if coalesce((v_r ->> 'ok')::boolean, false) and coalesce((v_r ->> 'repetida')::boolean, false) is false then
    v_id := (v_r ->> 'mensagemId')::uuid;
    update crm.mensagem m set origem = 'mcp' where m.id = v_id;
    return crm.res(true, 'Mensagem na fila de envio (enviada pelo Claude).', jsonb_build_object(
      'mensagemId', v_id, 'numero', jsonb_build_object('id', n.id, 'nome', n.nome,
                                                       'tipo', case when n.provedor = 'infobip' then 'Oficial' else 'QR' end),
      'template', case when t.id is not null then t.nome_provedor end));
  end if;
  return v_r;
end
$function$;
revoke all on function public.crm_mcp_enviar_whatsapp(uuid, uuid, text, text, uuid) from public, anon;
grant execute on function public.crm_mcp_enviar_whatsapp(uuid, uuid, text, text, uuid) to authenticated, service_role;

-- ─── h. lista do MCP ────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.crm_mcp_rpc(p_token uuid, p_rpc text, p_params jsonb default '{}'::jsonb)
 returns jsonb
 language plpgsql
 set search_path to ''
as $function$
declare
  c_ler    constant text[] := array['crm_funis', 'crm_funil_resumo', 'crm_negocios', 'crm_contatos', 'crm_jornada',
                                    'crm_atividades', 'crm_desempenho', 'crm_mensagens'];
  -- 20261009060000: + WhatsApp pelo Claude (crm_mcp_*). crm_enviar_mensagem continua fora: o envio passa pelas travas do MCP.
  c_operar constant text[] := array['crm_criar_atividade', 'crm_adicionar_nota', 'crm_mover_etapa', 'crm_concluir_atividade',
                                    'crm_criar_contato', 'crm_editar_contato', 'crm_tags_contato', 'crm_reabrir_atividade',
                                    'crm_mcp_numeros', 'crm_mcp_templates', 'crm_mcp_situacao_conversa', 'crm_mcp_enviar_whatsapp'];
  s jsonb; v_oid oid; v_n int; v_fora text; v_args text; v jsonb; v_role text; v_claims text[];
begin
  if p_rpc is null or not (p_rpc = any(c_ler || c_operar)) then
    raise exception 'Função fora da lista do MCP.' using errcode = '42501';
  end if;
  if p_params is not null and jsonb_typeof(p_params) <> 'object' then
    raise exception 'Parâmetros precisam ser objeto.' using errcode = '22023';
  end if;
  s := public.crm_mcp_sessao(p_token);
  if s is null then
    raise exception 'Token do MCP inválido, revogado ou expirado.' using errcode = '28000';
  end if;
  if p_rpc = any(c_operar) and not coalesce((s -> 'escopos') ? 'operar', false) then
    raise exception 'Este token não tem o escopo operar.' using errcode = '42501';
  end if;

  select min(p.oid), count(*) into v_oid, v_n
    from pg_catalog.pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.proname = p_rpc;
  if v_n <> 1 then
    raise exception 'Função do CRM indisponível.' using errcode = '42883';
  end if;

  -- 20261009050000: parâmetro array (ex.: text[]) aceita array JSON; o resto segue como literal tipado.
  with a as (
    select x.nome, pg_catalog.format_type(x.tipo, null) as tipo
      from pg_catalog.pg_proc p,
           unnest(p.proargnames[1:p.pronargs], p.proargtypes::oid[]) as x(nome, tipo)
     where p.oid = v_oid
  )
  select string_agg(e.key, ', ') filter (where a.nome is null),
         string_agg(case when a.tipo like '%[]' and jsonb_typeof(e.value) = 'array'
                         then format('%I => array(select pg_catalog.jsonb_array_elements_text(%L::jsonb))::%s',
                                     a.nome, e.value::text, a.tipo)
                         else format('%I => %L::%s', a.nome, e.value #>> '{}', a.tipo) end, ', ')
           filter (where a.nome is not null)
    into v_fora, v_args
    from jsonb_each(coalesce(p_params, '{}'::jsonb)) e
    left join a on a.nome = e.key;
  if v_fora is not null then
    raise exception 'Parâmetro desconhecido: %', v_fora using errcode = '22023';
  end if;

  -- Bloco com EXCEPTION = subtransação: se a RPC falhar, role e claims voltam sozinhos; no sucesso, volta à mão.
  v_role := current_user;
  v_claims := array[current_setting('request.jwt.claims', true), current_setting('request.jwt.claim.sub', true),
                    current_setting('request.jwt.claim.role', true), current_setting('request.jwt.claim.email', true)];
  begin
    perform pg_catalog.set_config('request.jwt.claims', jsonb_build_object(
              'sub', s ->> 'perfilId', 'role', 'authenticated', 'aud', 'authenticated', 'email', s ->> 'email',
              'is_anonymous', false, 'gp_canal', 'mcp', 'gp_mcp_token', p_token)::text, true);
    perform pg_catalog.set_config('request.jwt.claim.sub', s ->> 'perfilId', true);
    perform pg_catalog.set_config('request.jwt.claim.role', 'authenticated', true);
    perform pg_catalog.set_config('request.jwt.claim.email', s ->> 'email', true);
    set local role authenticated;

    execute format('select public.%I(%s)', p_rpc, coalesce(v_args, '')) into v;

    execute format('set local role %I', v_role);
    perform pg_catalog.set_config('request.jwt.claims', coalesce(v_claims[1], ''), true);
    perform pg_catalog.set_config('request.jwt.claim.sub', coalesce(v_claims[2], ''), true);
    perform pg_catalog.set_config('request.jwt.claim.role', coalesce(v_claims[3], ''), true);
    perform pg_catalog.set_config('request.jwt.claim.email', coalesce(v_claims[4], ''), true);
  exception when others then
    raise;
  end;
  return v;
end
$function$;
revoke all on function public.crm_mcp_rpc(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.crm_mcp_rpc(uuid, text, jsonb) to service_role;
