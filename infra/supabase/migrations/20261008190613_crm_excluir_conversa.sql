-- 20261008190613 crm_excluir_conversa — APLICADA em 08/10/2026 (md5 dos statements gravados = 890d65fad58295fe90084829dfe99275 = este arquivo SEM estas 4 linhas de cabeçalho).
-- Exclusão lógica de conversa do WhatsApp pelo gestor do Comercial (public.crm_excluir_conversa) + filtro da excluída
-- em todas as leituras (lista, mensagens, MCP, contadores, janela de 24 h, notificação, status, mídia). Escrita como 20261008ex.
-- Ensaio: 20261008190613_ensaio.sql · decisões e medidas: 20261008190613.explain.md
set local lock_timeout = '3s';
set local statement_timeout = '30s';

-- Premissa: corpos vivos lidos em 08/10/2026 (pg_get_functiondef). Mudou algum → aborta antes de tocar em nada.
do $g$
declare r record;
begin
  for r in select * from (values
    ('public.crm_conversas(integer)', '47c90ac279d84ff65ee175b83a283e8e'),
    ('public.crm_mensagens(uuid,integer)', '572fd8e62ba2b7684f74b0b48f415452'),
    ('crm.whatsapp_conversa_para(uuid,uuid)', 'fa90ce211c3943566f40febd76fd1d57'),
    ('crm.whatsapp_entrada(jsonb)', '16ec199f068f3318c8260d88fb9a9a18'),
    ('crm.evolution_entrada(jsonb)', '40707e7c46c7868f4fed9a64be6e7ecb'),
    ('public.crm_enviar_mensagem(uuid,text,uuid,text,text,uuid,uuid)', 'feb09147f027f37d36352aaa4699f5c5'),
    ('crm.notificacao_oculta(text,text,text)', '309b167483f2b2218f471bda20dc6e18'),
    ('public.crm_fichas(integer)', 'b5c1c78e45ab6ccdbd0d2e1601da85fa'),
    ('public.crm_whatsapp_status()', 'd05ca791eaf17d152d1d4b26853447dd'),
    ('public.crm_integracoes_status()', 'c109db22bd612c87beefe6df877649b8'),
    ('crm.template_render(crm.template,uuid,text)', 'f76c093b5593d7e60b77d4afeb6505a0'),
    ('crm.midia_pode_ver(text)', '54a67c504e3cf0c9f8622c2dab257666')
  ) v(fn, esperado) loop
    if md5(pg_get_functiondef(r.fn::regprocedure)) <> r.esperado then
      raise exception 'premissa: % mudou (md5 vivo %, esperado %)', r.fn, md5(pg_get_functiondef(r.fn::regprocedure)), r.esperado;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name in ('conversa', 'mensagem')
              and column_name like 'excluida%') then
    raise exception 'premissa: colunas excluida_* já existem';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'crm.conversa'::regclass and conname = 'conversa_numero_id_telefone_key') then
    raise exception 'premissa: crm.conversa sem a unique conversa_numero_id_telefone_key';
  end if;
  if to_regprocedure('public.crm_excluir_conversa(uuid,text)') is not null then
    raise exception 'premissa: public.crm_excluir_conversa já existe';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'crm.log'::regclass and conname = 'log_entidade_check')
     is distinct from 'CHECK ((entidade = ANY (ARRAY[''negocio''::text, ''contato''::text, ''atividade''::text, ''mensagem''::text, ''nota''::text, ''funil''::text, ''etapa''::text, ''campanha''::text, ''agrupador''::text, ''projeto''::text, ''motivo''::text, ''ficha''::text, ''fila''::text, ''produto''::text, ''oferta''::text, ''distribuicao''::text, ''link''::text, ''dashboard''::text, ''painel''::text, ''preferencias''::text, ''vendedor''::text, ''config''::text, ''estrategia''::text])))' then
    raise exception 'premissa: crm.log.log_entidade_check mudou';
  end if;
  if to_regprocedure('crm.eh_gestor(uuid)') is null or to_regprocedure('crm.guarda_escrita()') is null
     or to_regprocedure('crm.log_registrar(text,text,text,uuid,text,jsonb)') is null then
    raise exception 'premissa: helpers do CRM ausentes';
  end if;
end $g$;

-- ── 1. Marca de exclusão (lógica: nada é apagado do banco) ──
alter table crm.conversa
  add column excluida_em timestamptz,
  add column excluida_por uuid,
  add column excluida_motivo text,
  add constraint conversa_exclusao_check check (excluida_em is not null or (excluida_por is null and excluida_motivo is null)),
  add constraint conversa_excluida_motivo_check check (excluida_motivo is null or char_length(btrim(excluida_motivo)) between 5 and 300);
alter table crm.mensagem
  add column excluida_em timestamptz,
  add column excluida_por uuid,
  add column excluida_motivo text,
  add constraint mensagem_exclusao_check check (excluida_em is not null or (excluida_por is null and excluida_motivo is null)),
  add constraint mensagem_excluida_motivo_check check (excluida_motivo is null or char_length(btrim(excluida_motivo)) between 5 and 300);
comment on column crm.conversa.excluida_em is
  'Exclusão lógica (crm_excluir_conversa, só gestor). Excluída some de toda leitura; mensagem nova do mesmo número/telefone nasce em conversa nova.';
comment on column crm.mensagem.excluida_em is
  'Exclusão lógica junto com a conversa (crm_excluir_conversa). Segue contando só nas travas de envio (anti-ban, disparo 48 h): a mensagem saiu de verdade.';

-- ── 2. Uma conversa VIVA por número + telefone (a excluída fica no histórico e não trava a nova) ──
alter table crm.conversa drop constraint conversa_numero_id_telefone_key;
create unique index conversa_numero_telefone_viva_key on crm.conversa (numero_id, telefone) where excluida_em is null;

-- ── 3. RLS: excluída não é lida nem pela API das funções invoker ──
drop policy conversa_ler on crm.conversa;
create policy conversa_ler on crm.conversa for select to authenticated
  using (excluida_em is null
         and ((select crm.eh_gestor()) or ((select crm.eh_vendedor()) and pessoa_id in (select crm.pessoas_do_vendedor()))));
drop policy mensagem_ler on crm.mensagem;
create policy mensagem_ler on crm.mensagem for select to authenticated
  using (excluida_em is null
         and ((select crm.eh_gestor()) or ((select crm.eh_vendedor()) and pessoa_id in (select crm.pessoas_do_vendedor()))));

-- ── 4. Registro de alterações aceita a entidade 'conversa' ──
alter table crm.log drop constraint log_entidade_check;
alter table crm.log add constraint log_entidade_check check (entidade = any (array['negocio', 'contato', 'atividade', 'mensagem',
  'nota', 'funil', 'etapa', 'campanha', 'agrupador', 'projeto', 'motivo', 'ficha', 'fila', 'produto', 'oferta', 'distribuicao',
  'link', 'dashboard', 'painel', 'preferencias', 'vendedor', 'config', 'estrategia', 'conversa']));

-- ── 5. Leituras: trechos trocados no corpo VIVO (cada trecho tem de aparecer exatamente `qtd` vezes, senão aborta) ──
-- Fora de propósito (a mensagem excluída saiu de verdade para o WhatsApp do cliente):
--   crm.tg_mensagem_canal (limites anti-ban por número), crm.supressao_motivo (disparo nas últimas 48 h) e
--   crm.chaves_contato (telefone para opt-out) seguem contando a excluída.
do $p$
declare r record; d text; n int;
begin
  for r in select * from (values
    -- lista de Conversas (contadores, "esperando", janela de 24 h) + ids das conversas vivas para o menu Excluir
    (1, 'public.crm_conversas(integer)',
     $a$from crm.conversa x where x.ultima_mensagem_id is not null order by$a$,
     $b$from crm.conversa x where x.ultima_mensagem_id is not null and x.excluida_em is null order by$b$, 1),
    (2, 'public.crm_conversas(integer)',
     $a$array_agg(distinct c.numero_id) canais$a$,
     $b$array_agg(distinct c.numero_id) canais,
               jsonb_agg(jsonb_build_object('id', c.id, 'canalId', c.numero_id) order by c.ultima_em desc) convs$b$, 1),
    (3, 'public.crm_conversas(integer)',
     $a$'canais', to_jsonb(g.canais))$a$,
     $b$'canais', to_jsonb(g.canais), 'conversas', g.convs)$b$, 1),
    -- mensagens do contato (Conversas, aba Conversa do negócio e da ficha, MCP comercial_conversa_whatsapp)
    (4, 'public.crm_mensagens(uuid,integer)',
     $a$from crm.mensagem x where x.pessoa_id = any(v_g) order by$a$,
     $b$from crm.mensagem x where x.pessoa_id = any(v_g) and x.excluida_em is null order by$b$, 1),
    -- conversa de envio: nunca a excluída (envio novo abre conversa nova, janela de 24 h do zero)
    (5, 'crm.whatsapp_conversa_para(uuid,uuid)',
     $a$where c.numero_id = p_numero and c.pessoa_id = any(v_g)$a$,
     $b$where c.numero_id = p_numero and c.pessoa_id = any(v_g) and c.excluida_em is null$b$, 1),
    (6, 'crm.whatsapp_conversa_para(uuid,uuid)',
     $a$on conflict (numero_id, telefone) do nothing returning id into v;$a$,
     $b$on conflict (numero_id, telefone) where excluida_em is null do nothing returning id into v;$b$, 1),
    (7, 'crm.whatsapp_conversa_para(uuid,uuid)',
     $a$where c.numero_id = p_numero and c.telefone = v_tel;$a$,
     $b$where c.numero_id = p_numero and c.telefone = v_tel and c.excluida_em is null;$b$, 1),
    -- entrada Infobip: mensagem nova depois da exclusão cria conversa nova
    (8, 'crm.whatsapp_entrada(jsonb)',
     $a$where x.numero_id = v_num.id and x.telefone = v_de for update$a$,
     $b$where x.numero_id = v_num.id and x.telefone = v_de and x.excluida_em is null for update$b$, 2),
    (9, 'crm.whatsapp_entrada(jsonb)',
     $a$on conflict (numero_id, telefone) do nothing;$a$,
     $b$on conflict (numero_id, telefone) where excluida_em is null do nothing;$b$, 1),
    -- entrada Evolution (QR): idem
    (10, 'crm.evolution_entrada(jsonb)',
     $a$where x.numero_id = n.id and x.telefone = v_de for update$a$,
     $b$where x.numero_id = n.id and x.telefone = v_de and x.excluida_em is null for update$b$, 2),
    (11, 'crm.evolution_entrada(jsonb)',
     $a$on conflict (numero_id, telefone) do nothing;$a$,
     $b$on conflict (numero_id, telefone) where excluida_em is null do nothing;$b$, 1),
    -- número da resposta: o da conversa viva mais recente
    (12, 'public.crm_enviar_mensagem(uuid,text,uuid,text,text,uuid,uuid)',
     $a$where k.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.ativo$a$,
     $b$where k.pessoa_id = any(crm.grupo_rapido(v_atual)) and x.ativo and k.excluida_em is null$b$, 1),
    -- sino: "Respondeu no WhatsApp" de mensagem excluída some
    (13, 'crm.notificacao_oculta(text,text,text)',
     $a$  return false;
end$a$,
     $b$  if p_gatilho = 'lead_respondeu' and p_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return coalesce((select m.excluida_em is not null from crm.mensagem m where m.id = p_ref::uuid), false);
  end if;
  return false;
end$b$, 1),
    -- resultado dos disparos (entregues/lidas/respostas)
    (14, 'public.crm_fichas(integer)',
     $a$from crm.mensagem m where m.ficha_id = f.id and f.status = 'enviada')$a$,
     $b$from crm.mensagem m where m.ficha_id = f.id and f.status = 'enviada' and m.excluida_em is null)$b$, 1),
    (15, 'public.crm_fichas(integer)',
     $a$e.conversa_id = m.conversa_id and e.direcao = 'entrada'$a$,
     $b$e.conversa_id = m.conversa_id and e.direcao = 'entrada' and e.excluida_em is null$b$, 1),
    -- status do WhatsApp (na fila, falhas de hoje)
    (16, 'public.crm_whatsapp_status()',
     $a$from crm.mensagem m where m.status = $a$,
     $b$from crm.mensagem m where m.excluida_em is null and m.status = $b$, 2),
    -- aba Integrações (última mensagem, 24 h, falhas por número)
    (17, 'public.crm_integracoes_status()',
     $a$from crm.mensagem x where x.numero_id = n.id)$a$,
     $b$from crm.mensagem x where x.numero_id = n.id and x.excluida_em is null)$b$, 1),
    (18, 'public.crm_integracoes_status()',
     $a$where z.numero_id = n.id and z.em >= v_24h$a$,
     $b$where z.numero_id = n.id and z.em >= v_24h and z.excluida_em is null$b$, 1),
    (19, 'public.crm_integracoes_status()',
     $a$from crm.mensagem y where y.numero_id = n.id and y.em >= v_24h)$a$,
     $b$from crm.mensagem y where y.numero_id = n.id and y.em >= v_24h and y.excluida_em is null)$b$, 1),
    -- nome do perfil do WhatsApp para template
    (20, 'crm.template_render(crm.template,uuid,text)',
     $a$where c.pessoa_id = any(v_g) and c.nome_perfil is not null$a$,
     $b$where c.pessoa_id = any(v_g) and c.nome_perfil is not null and c.excluida_em is null$b$, 1),
    -- arquivo de mensagem excluída não abre mais (policy do bucket crm-midia)
    (21, 'crm.midia_pode_ver(text)',
     $a$where m.midia_caminho = p_nome and m.midia_status = 'ok'$a$,
     $b$where m.midia_caminho = p_nome and m.midia_status = 'ok' and m.excluida_em is null$b$, 1)
  ) v(ordem, fn, velho, novo, qtd) order by ordem loop
    d := pg_get_functiondef(r.fn::regprocedure);
    n := (length(d) - length(replace(d, r.velho, ''))) / length(r.velho);
    if n <> r.qtd then
      raise exception 'patch %: trecho de % aparece % vez(es), esperado %', r.ordem, r.fn, n, r.qtd;
    end if;
    execute replace(d, r.velho, r.novo);   -- create or replace com a mesma assinatura: ACL preservada
  end loop;
end $p$;

-- ── 6. RPC de escrita: exclusão lógica pelo gestor ──
create function public.crm_excluir_conversa(p_conversa uuid, p_motivo text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_eu uuid := auth.uid(); v_r jsonb; v_motivo text := btrim(coalesce(p_motivo, '')); cv crm.conversa%rowtype;
  v_n int; v_midias text[];
begin
  -- leitor recusado aqui (20261008151801); escrita desligada e quem não é do Comercial também
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  -- gestor DE VERDADE (crm.config.gestores). crm.eh_gestor() sem argumento também aceita o leitor: não serve aqui.
  if not coalesce(crm.eh_gestor(v_eu), false) then
    return crm.res(false, 'Só o gestor do Comercial exclui conversa.', null);
  end if;
  if char_length(v_motivo) < 5 then return crm.res(false, 'Escreva o motivo (mínimo 5 caracteres).', null); end if;
  if char_length(v_motivo) > 300 then return crm.res(false, 'Motivo longo demais (máximo 300 caracteres).', null); end if;
  if p_conversa is null then return crm.res(false, 'Conversa não encontrada.', null); end if;

  -- trava a conversa: a entrada (whatsapp_/evolution_entrada) também faz `for update` nela, então mensagem que chega
  -- durante a exclusão ou entra antes (e é excluída junto) ou espera e cai numa conversa nova.
  select * into cv from crm.conversa x where x.id = p_conversa for update;
  if not found then return crm.res(false, 'Conversa não encontrada.', null); end if;
  if cv.excluida_em is not null then return crm.res(false, 'Esta conversa já foi excluída.', null); end if;

  update crm.mensagem m
     set excluida_em = now(), excluida_por = v_eu, excluida_motivo = v_motivo,
         -- o que ainda não saiu não sai mais; arquivo pendente não é mais baixado
         status = case when m.status = 'na_fila' then 'falhou' else m.status end,
         status_em = case when m.status = 'na_fila' then now() else m.status_em end,
         erro = case when m.status = 'na_fila' then 'Conversa excluída antes do envio.' else m.erro end,
         midia_status = case when m.midia_status = 'pendente' then 'falhou' else m.midia_status end,
         midia_erro = case when m.midia_status = 'pendente' then 'Conversa excluída.' else m.midia_erro end
   where m.conversa_id = cv.id and m.excluida_em is null;
  get diagnostics v_n = row_count;

  update crm.conversa x
     set excluida_em = now(), excluida_por = v_eu, excluida_motivo = v_motivo, nao_lidas = 0
   where x.id = cv.id;

  -- arquivos no bucket crm-midia que só estas mensagens usam (o servidor apaga com service role depois do ok)
  select coalesce(array_agg(distinct m.midia_caminho), '{}') into v_midias
    from crm.mensagem m
   where m.conversa_id = cv.id and m.midia_caminho is not null
     and not exists (select 1 from crm.mensagem o where o.midia_caminho = m.midia_caminho and o.conversa_id <> cv.id);

  -- registro: quem (autor do log), quando, motivo e quantas mensagens. Sem conteúdo, sem telefone, sem pessoa
  -- (a jornada do contato não ganha linha de algo que sumiu).
  perform crm.log_registrar('excluiu', 'conversa', cv.id::text, null,
                            format('Excluiu conversa do WhatsApp (%s mensagens). Motivo: %s', v_n, v_motivo),
                            jsonb_build_object('mensagens', v_n, 'motivo', v_motivo, 'canal_id', cv.numero_id,
                                               'midias', cardinality(v_midias)));

  -- telas abertas (Conversas, negócio, ficha) recarregam: payload sem dado pessoal
  begin
    perform realtime.send(jsonb_build_object('t', 'conversa'), 'mudou', 'crm:caixa', true);
  exception when others then
    raise warning 'crm_excluir_conversa (aviso realtime): %', sqlstate;
  end;

  return crm.res(true, format('Conversa excluída (%s mensagens).', v_n),
                 jsonb_build_object('mensagens', v_n, 'midias', to_jsonb(v_midias)));
end
$function$;
comment on function public.crm_excluir_conversa(uuid, text) is
  'Exclusão lógica de uma crm.conversa e das mensagens dela. Só gestor (crm.config.gestores); leitor e vendedor recusados. Motivo 5-300 caracteres. Devolve {ok, msg, mensagens, midias[]} (caminhos no bucket crm-midia para o servidor apagar).';
revoke execute on function public.crm_excluir_conversa(uuid, text) from public, anon;
grant execute on function public.crm_excluir_conversa(uuid, text) to authenticated, service_role;
