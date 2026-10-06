-- 20261006n_crm_ajustes — pendências pequenas do CRM Comercial. NÃO APLICADA (ver 20261006n.explain.md).
--
-- 1. crm_salvar_funil: payload SEM a chave `distribuicao` dava "Campo obrigatório vazio" (jsonb_typeof(NULL) = NULL →
--    v_prop NULL → insert de crm.funil.distribuicao_propria NOT NULL → 23502). Ausente = sem distribuição própria.
-- 2. crm_config: expõe `mcpLigado` (crm.config.mcp_ligado) para a aba "Conectar ao Claude" avisar quando está desligado.
-- 5. crm_jornada: eventos de checkout de pessoas.eventos (carrinho abandonado etc.) viram ponto próprio 'checkout'.
--
-- Cada função é recriada a partir do corpo VIVO (pg_get_functiondef), mesma assinatura (sem sobrecarga), mesmas
-- opções (volatilidade, SECURITY, search_path) e mesmos grants de antes: postgres, service_role, authenticated.

-- Guarda de premissa: o corpo VIVO (prosrc) tem de ser exatamente o lido em 06/10/2026. Se alguém mexeu, aborta.
do $g$
declare r record;
begin
  for r in select * from (values
      ('public.crm_salvar_funil(jsonb)', '55d363c984c01727751596cd95eb27ac'),
      ('public.crm_config()', '4ef97efd7f7bbe21ad9447244baf770b'),
      ('public.crm_jornada(uuid,integer)', '3f57f989e150f1bda7b829bf202de1b6')) v(sig, esperado)
  loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception '20261006n: corpo vivo de % mudou (md5 esperado %). Releia pg_get_functiondef antes de aplicar.', r.sig, r.esperado;
    end if;
  end loop;
end
$g$;

-- 1 ────────────────────────────────────────────────────────────────────────────────
create or replace function public.crm_salvar_funil(p_funil jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; v_prob text; v_id uuid; v_ag uuid; v_novo boolean; v_prop boolean;
        v_nome text; v_et jsonb; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor cria ou edita funis.'); end if;
  if jsonb_typeof(p_funil) is distinct from 'object' then return crm.res(false, 'Funil inválido.'); end if;
  v_prob := crm.validar_funil(p_funil);
  if v_prob is not null then return crm.res(false, v_prob); end if;
  v_ag := crm.uuid_ou_null(p_funil ->> 'agrupadorId');
  if v_ag is null or not exists (select 1 from crm.agrupador a where a.id = v_ag and a.arquivado_em is null) then
    return crm.res(false, 'Escolha o agrupador.');
  end if;
  if not exists (select 1 from crm.linha l where l.chave = p_funil ->> 'produto') then return crm.res(false, 'Produto inválido.'); end if;
  -- 20261006n: chave ausente = sem distribuição própria (jsonb_typeof(null) é NULL e virava 23502 no insert)
  v_prop := coalesce(jsonb_typeof(p_funil -> 'distribuicao') = 'array', false);
  if v_prop and exists (select 1 from jsonb_array_elements(p_funil -> 'distribuicao') x
                         where coalesce((x ->> 'percentual')::int, 0) > 0
                           and not exists (select 1 from crm.vendedor v where v.perfil_id = crm.uuid_ou_null(x ->> 'vendedorId'))) then
    return crm.res(false, 'Só vendedor cadastrado recebe leads.');
  end if;
  v_nome := btrim(p_funil ->> 'nome');
  v_et := p_funil -> 'etapas';
  v_id := crm.uuid_ou_null(p_funil ->> 'id');
  v_novo := v_id is null or not exists (select 1 from crm.funil f where f.id = v_id);
  if not v_novo and not exists (select 1 from crm.funil f where f.id = v_id and f.ativo) then
    return crm.res(false, 'Funil não encontrado.');
  end if;

  if v_novo then
    perform set_config('crm.resumo', format('Criou o funil %s (%s etapas)', v_nome, jsonb_array_length(v_et)), true);
    insert into crm.funil (nome, icone, projeto, agrupador_id, linha, tipo, eventos_hotmart, distribuicao_propria, criado_por)
    values (v_nome, coalesce(nullif(p_funil ->> 'icone', ''), 'kanban'), nullif(p_funil ->> 'projeto', ''), v_ag,
            p_funil ->> 'produto', coalesce(p_funil ->> 'tipo', 'manual'),
            array(select jsonb_array_elements_text(case when jsonb_typeof(p_funil -> 'eventosHotmart') = 'array' then p_funil -> 'eventosHotmart' else '[]'::jsonb end)),
            v_prop, v_eu)
    returning id into v_id;
  else
    -- etapa removida (ou que vira Ganho) com negócio aberto
    if exists (select 1 from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id
                where n.funil_id = v_id and n.status = 'aberto' and e.arquivada_em is null
                  and not exists (select 1 from crm.etapas_payload(v_et) x where x.id = e.id)) then
      return crm.res(false, 'Há negócio aberto numa etapa removida. Mova os negócios antes.');
    end if;
    if exists (select 1 from crm.negocio n join crm.etapas_payload(v_et) x on x.id = n.etapa_id
                where n.funil_id = v_id and n.status = 'aberto' and x.papel = 'fechado') then
      return crm.res(false, 'Há negócio aberto na etapa que virou Ganho. Mova os negócios antes.');
    end if;
    perform set_config('crm.resumo', format('Editou o funil %s', v_nome), true);
    update crm.funil f set nome = v_nome, icone = coalesce(nullif(p_funil ->> 'icone', ''), f.icone), projeto = nullif(p_funil ->> 'projeto', ''),
                           agrupador_id = v_ag, linha = p_funil ->> 'produto', tipo = coalesce(p_funil ->> 'tipo', f.tipo),
                           eventos_hotmart = array(select jsonb_array_elements_text(case when jsonb_typeof(p_funil -> 'eventosHotmart') = 'array' then p_funil -> 'eventosHotmart' else '[]'::jsonb end)),
                           distribuicao_propria = v_prop
     where f.id = v_id
       and (f.nome, f.icone, f.projeto, f.agrupador_id, f.linha, f.tipo, f.eventos_hotmart, f.distribuicao_propria) is distinct from
           (v_nome, coalesce(nullif(p_funil ->> 'icone', ''), f.icone), nullif(p_funil ->> 'projeto', ''), v_ag, p_funil ->> 'produto',
            coalesce(p_funil ->> 'tipo', f.tipo),
            array(select jsonb_array_elements_text(case when jsonb_typeof(p_funil -> 'eventosHotmart') = 'array' then p_funil -> 'eventosHotmart' else '[]'::jsonb end)),
            v_prop);
    -- arquiva as removidas
    update crm.etapa_funil e set arquivada_em = now()
     where e.funil_id = v_id and e.arquivada_em is null and not exists (select 1 from crm.etapas_payload(v_et) x where x.id = e.id);
    -- passo 1: tira do caminho quem muda de ordem/nome; Ganho que deixa de ser Ganho já recebe o papel novo
    update crm.etapa_funil e set ordem = e.ordem + 1000,
                                 nome = case when lower(e.nome) <> lower(x.nome) then '~' || e.id::text else e.nome end,
                                 papel = case when e.papel = 'fechado' and x.papel <> 'fechado' then x.papel else e.papel end
      from crm.etapas_payload(v_et) x
     where x.id = e.id and e.funil_id = v_id and e.arquivada_em is null
       and (e.ordem <> x.ord or lower(e.nome) <> lower(x.nome) or (e.papel = 'fechado' and x.papel <> 'fechado'));
    -- passo 2: valores finais
    update crm.etapa_funil e set ordem = x.ord, nome = x.nome, papel = x.papel, cor = x.cor, sla_atencao_min = x.sla_a,
                                 sla_critico_min = x.sla_c, campos_obrigatorios = x.campos, criterio = x.criterio
      from crm.etapas_payload(v_et) x
     where x.id = e.id and e.funil_id = v_id and e.arquivada_em is null
       and (e.ordem, e.nome, e.papel, e.cor, e.sla_atencao_min, e.sla_critico_min, e.campos_obrigatorios, e.criterio)
           is distinct from (x.ord, x.nome, x.papel, x.cor, x.sla_a, x.sla_c, x.campos, x.criterio);
  end if;
  -- etapas novas
  insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min, campos_obrigatorios, criterio)
  select v_id, x.ord, x.nome, x.papel, x.cor, x.sla_a, x.sla_c, x.campos, x.criterio
    from crm.etapas_payload(v_et) x
   where x.id is null or not exists (select 1 from crm.etapa_funil e where e.id = x.id and e.funil_id = v_id and e.arquivada_em is null)
   order by x.ord;
  -- campanhas: edita as do funil, cria as novas, inativa as removidas
  update crm.campanha c set nome = x.nome, canal = x.canal, regra = x.regra, ativa = x.ativa
    from crm.campanhas_payload(p_funil -> 'campanhas') x
   where x.id = c.id and c.funil_id = v_id and (c.nome, c.canal, c.regra, c.ativa) is distinct from (x.nome, x.canal, x.regra, x.ativa);
  insert into crm.campanha (funil_id, nome, canal, regra, ativa)
  select v_id, x.nome, x.canal, x.regra, x.ativa from crm.campanhas_payload(p_funil -> 'campanhas') x
   where x.id is null or not exists (select 1 from crm.campanha c where c.id = x.id and c.funil_id = v_id);
  update crm.campanha c set ativa = false
   where c.funil_id = v_id and c.ativa and not exists (select 1 from crm.campanhas_payload(p_funil -> 'campanhas') x where x.id = c.id);
  -- distribuição própria (a constraint trigger confere a soma no fim da transação)
  if v_prop then
    insert into crm.distribuicao (funil_id, vendedor_id, percentual, ativo)
    select v_id, crm.uuid_ou_null(x ->> 'vendedorId'), coalesce((x ->> 'percentual')::int, 0), true
      from jsonb_array_elements(p_funil -> 'distribuicao') x
     where exists (select 1 from crm.vendedor v where v.perfil_id = crm.uuid_ou_null(x ->> 'vendedorId'))
    on conflict (coalesce(funil_id, '00000000-0000-0000-0000-000000000000'::uuid), vendedor_id)
    do update set percentual = excluded.percentual, ativo = true, atualizado_em = now()
     where (crm.distribuicao.percentual, crm.distribuicao.ativo) is distinct from (excluded.percentual, true);
    update crm.distribuicao d set ativo = false, atualizado_em = now()
     where d.funil_id = v_id and d.ativo
       and not exists (select 1 from jsonb_array_elements(p_funil -> 'distribuicao') x where crm.uuid_ou_null(x ->> 'vendedorId') = d.vendedor_id);
  else
    update crm.distribuicao d set ativo = false, atualizado_em = now() where d.funil_id = v_id and d.ativo;
  end if;
  return crm.res(true, case when v_novo then 'Funil criado.' else 'Funil atualizado.' end, jsonb_build_object('funilId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke all on function public.crm_salvar_funil(jsonb) from public, anon;
grant execute on function public.crm_salvar_funil(jsonb) to authenticated, service_role;

-- 2 ────────────────────────────────────────────────────────────────────────────────
create or replace function public.crm_config()
 returns jsonb
 language plpgsql
 stable
 set search_path to ''
AS $function$
declare v jsonb;
begin
  perform crm.exige_comercial();
  select jsonb_build_object('horarioContato', coalesce(c.horario_contato, ''), 'limiteNegociosAbertos', c.limite_negocios_abertos,
                            'escritaLigada', c.escrita_ligada, 'mcpLigado', c.mcp_ligado)
    into v from crm.config c;
  return v;
end
$function$;
revoke all on function public.crm_config() from public, anon;
grant execute on function public.crm_config() to authenticated, service_role;

-- 5 ────────────────────────────────────────────────────────────────────────────────
create or replace function public.crm_jornada(p_pessoa uuid, p_limite integer default 500)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_atual uuid; v_g uuid[]; v_emails text[]; v_fks text[]; v_fks1 text[]; v_compr uuid[];
  v_ac boolean; v_sf boolean; v_rs boolean; v_un boolean;
  v jsonb;
begin
  perform crm.exige_comercial();
  if p_pessoa is null or not coalesce(crm.pode_ver_pessoa(p_pessoa), false) then
    raise exception 'Sem acesso a esta pessoa.' using errcode = '42501';
  end if;
  select coalesce(c.activecampaign_ligado, false), coalesce(c.sendflow_ligado, false), coalesce(c.respondi_ligado, false),
         coalesce(c.unnichat_ligado, false)
    into v_ac, v_sf, v_rs, v_un from crm.config c;
  v_ac := coalesce(v_ac, false); v_sf := coalesce(v_sf, false); v_rs := coalesce(v_rs, false); v_un := coalesce(v_un, false);
  v_atual := pessoas.atual(p_pessoa);
  v_g := pessoas.grupo(v_atual);

  v_compr := array(
    select p.comprador_id from pessoas.pessoas p where p.id = any(v_g) and p.comprador_id is not null
    union select a.comprador_id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
           where p.id = any(v_g) and a.comprador_id is not null);
  v_emails := array(
    select e from (
      select pessoas.norm_email(a.email) e from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id where p.id = any(v_g)
      union select pessoas.norm_email((c.email)::text) from public.compradores c where c.id = any(v_compr)
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'email'
    ) s where e is not null);
  -- e-mails irmãos pelo grafo fin.identidade (por chave, no momento da leitura; recalculado de hora em hora)
  v_emails := array(
    select distinct e from (
      select unnest(v_emails) e
      union select substr(i2.no, 3) from fin.identidade i1 join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i1.no = any(array(select 'e:' || x from unnest(v_emails) x)) and i2.no like 'e:%'
    ) s where e is not null limit 20);
  v_fks := array(
    select k from (
      select controle.fone_key(coalesce(a.telefone_e164, a.telefone)) k from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
       where p.id = any(v_g)
      union select controle.fone_key((c.telefone)::text) from public.compradores c where c.id = any(v_compr) and c.telefone is not null
      union select i.chave from pessoas.identificadores i where i.pessoa_id = any(v_g) and i.tipo = 'telefone'
    ) s where k is not null limit 10);
  -- F5: evento só com telefone (grupo, Respondi sem e-mail) é da pessoa só se a chave tem EXATAMENTE 1 candidato
  -- (manual §7: telefone nunca junta duas pessoas). Calculado só se alguma fonte por telefone estiver ligada.
  if v_sf or v_rs then
    v_fks1 := array(select k from unnest(v_fks) k where (select count(*) from pessoas.candidatos_telefone(k)) = 1);
  else
    v_fks1 := '{}';
  end if;

  with pts as (
    -- inscrição (origem com a UTM daquela entrada)
    (select 'or-' || o.id id, 'inscricao' tipo, o.quando em,
            'Inscrição' || coalesce(' · ' || pr.sigla, '') titulo, o.campanha detalhe, 'formulario' fonte,
            lower(pr.sigla) lancamento, null::text produto,
            jsonb_build_object('source', o.utm_source, 'medium', o.utm_medium, 'campaign', o.utm_campaign, 'content', o.utm_content) utm,
            null::numeric valor, null::uuid negocio_id
       from pessoas.origens o left join mkt.projetos pr on pr.id = o.projeto_id
      where o.pessoa_id = any(v_g) order by o.quando desc limit v_lim)
    union all
    (select 'ev-' || e.id, 'pesquisa', e.quando, case e.tipo when 'mql' then 'Qualificou como MQL' else 'Não qualificou (MQL)' end,
            null, 'formulario', lower(pr.sigla), null, null, null, null
       from pessoas.eventos e left join mkt.projetos pr on pr.id = e.projeto_id
      where e.pessoa_id = any(v_g) and e.tipo in ('mql', 'nao_mql') order by e.quando desc limit v_lim)
    union all
    -- Hotmart: compra, reembolso, checkout (índice hotmart_transacoes_email_idx = lower(btrim(comprador_email)))
    (select 'hm-' || h.transacao,
            case when h.status in ('APPROVED', 'COMPLETE') then 'compra'
                 when h.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED') then 'reembolso' else 'checkout' end,
            coalesce(h.aprovado_em, h.pedido_em),
            case when h.status in ('APPROVED', 'COMPLETE') then 'Compra aprovada'
                 when h.status in ('REFUNDED', 'PARTIALLY_REFUNDED') then 'Reembolso'
                 when h.status = 'CHARGEBACK' then 'Chargeback'
                 when h.status in ('WAITING_PAYMENT', 'PRINTED_BILLET') then 'Boleto/Pix gerado'
                 when h.status = 'EXPIRED' then 'Pagamento expirado'
                 when h.status = 'CANCELLED' then 'Compra cancelada'
                 else 'Checkout: ' || lower(h.status) end || coalesce(' · ' || h.produto_nome, ''),
            nullif(concat_ws(' · ', 'oferta ' || h.oferta_codigo, h.metodo), ''), 'hotmart', null, pcm.linha,
            case when h.origem_sck is not null then jsonb_build_object('sck', h.origem_sck) end,
            h.valor_cobrado, null
       from (select * from fin.hotmart_transacoes where conta = 'academy'
             union all
             select * from fin.hotmart_transacoes where conta = 'escritorio') h
       left join crm.produto_comercial pcm on pcm.produto_id = h.produto_id and pcm.no_comercial
      where lower(btrim(h.comprador_email)) = any(v_emails)
      order by coalesce(h.aprovado_em, h.pedido_em) desc nulls last limit v_lim)
    union all
    -- 20261006n: checkout como ponto próprio (pessoas.eventos tipo 'checkout': carrinho abandonado, cartão recusado…).
    -- Transação Hotmart que o bloco 'hm-' acima já mostra (mesma transação, e-mail da pessoa) não repete.
    -- Índice eventos_pessoa_idx (pessoa_id, quando); dedupe pela PK hotmart_transacoes_pkey, na forma por conta
    -- exigida pela trava fin.trava_conta_hotmart (mesmas 2 contas do bloco 'hm-').
    (select 'pc-' || e.id, 'checkout', e.quando,
            case e.detalhe ->> 'classe'
              when 'carrinho_abandonado' then 'Carrinho abandonado'
              when 'cartao_recusado' then 'Cartão recusado'
              when 'expirada' then 'Pagamento expirado'
              when 'compra_em_aberto' then 'Boleto/Pix gerado'
              else 'Checkout' || coalesce(': ' || replace(e.detalhe ->> 'classe', '_', ' '), '') end
            || coalesce(' · ' || pcm.nome_comercial, ''),
            nullif(concat_ws(' · ', 'oferta ' || (e.detalhe ->> 'oferta'), e.detalhe ->> 'metodo'), ''),
            coalesce(e.fonte, 'hotmart'), lower(pr.sigla), pcm.linha,
            case when e.detalhe ->> 'sck' is not null then jsonb_build_object('sck', e.detalhe ->> 'sck') end,
            case when jsonb_typeof(e.detalhe -> 'valor') = 'number' then (e.detalhe ->> 'valor')::numeric end, null
       from pessoas.eventos e
       left join mkt.projetos pr on pr.id = e.projeto_id
       left join crm.produto_comercial pcm on pcm.produto_id = e.detalhe ->> 'produto' and pcm.no_comercial
      where e.pessoa_id = any(v_g) and e.tipo = 'checkout'
        and not (coalesce(e.ref_tipo, '') = 'hotmart.transacao'
                 and exists (select 1
                               from (select * from fin.hotmart_transacoes where conta = 'academy'
                                     union all
                                     select * from fin.hotmart_transacoes where conta = 'escritorio') h
                              where h.transacao = e.ref_id and lower(btrim(h.comprador_email)) = any(v_emails)))
      order by e.quando desc limit v_lim)
    union all
    -- lista do ActiveCampaign (índice ix_lead_active_email_lower). F5: kill-switch activecampaign_ligado.
    (select 'ac-' || la.id, 'lista', coalesce(la.opt_in_at, la.atualizado_em), 'Entrou na lista' || coalesce(' · ' || la.origem, ''),
            la.segmento, 'activecampaign', null, null,
            jsonb_build_object('source', la.utm_source, 'campaign', la.utm_campaign, 'content', la.utm_content), null, null
       from controle.lead_active la
      where v_ac and lower(btrim(la.email)) = any(v_emails)
      order by coalesce(la.opt_in_at, la.atualizado_em) desc limit v_lim)
    union all
    -- grupos de WhatsApp (índice ix_geu_fone, chave controle.fone_key). F5: sendflow_ligado + chave com 1 candidato.
    (select 'gr-' || g.id, 'grupo', g.ocorreu_em,
            case g.tipo when 'entrada' then 'Entrou no grupo' else 'Saiu do grupo' end || coalesce(' · ' || g.group_name, ''),
            g.segmento, 'sendflow', null, null, null, null, null
       from controle.grupo_evento_unificado g
      where v_sf and g.fone_key = any(v_fks1)
      order by g.ocorreu_em desc limit v_lim)
    union all
    -- pesquisas/formulários (índice respostas_email_idx; e-mail já normalizado na fonte). Nunca cpf/respostas.
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            null, 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email = any(v_emails)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: resposta SEM e-mail, pelo telefone com 1 candidato (índice ix_respostas_fone_sem_email, predicado repetido)
    (select 'rs-' || r.uuid, 'pesquisa', r.respondido_em, 'Respondeu: ' || coalesce(r.form_slug, 'formulário'),
            'casado pelo telefone', 'respondi', null, null, null, null, null
       from respondi.respostas r
      where v_rs and r.email is null and r.telefone is not null and controle.fone_key(r.telefone) = any(v_fks1)
      order by r.respondido_em desc limit v_lim)
    union all
    -- F5: Unnichat legado (controle.unnichat_evento, parado desde 08/09) pelo e-mail do contato (ix_unnichat_evento_email)
    (select 'un-' || u.id, (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).tipo_ponto, u.recebido_em,
            (crm.ponto_integracao('unnichat', u.tipo, null, u.tag_nome)).titulo, null, 'unnichat', null, null, null, null, null
       from controle.unnichat_evento u
      where v_un and lower(btrim((u.payload -> 'contact') ->> 'email')) = any(v_emails)
      order by u.recebido_em desc limit v_lim)
    union all
    -- F5: eventos de webhook já casados com a pessoa (crm.evento_jornada), cada fonte com o seu kill-switch
    (select 'ie-' || ie.id, (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).tipo_ponto, ie.ocorreu_em,
            (crm.ponto_integracao(ie.fonte, ie.tipo, ie.lista, ie.tag)).titulo, null, ie.fonte, null, null,
            ie.dados -> 'utm', null, null
       from crm.evento_jornada ie
      where ie.pessoa_id = any(v_g)
        and ((ie.fonte = 'activecampaign' and v_ac) or (ie.fonte = 'sendflow' and v_sf)
             or (ie.fonte = 'unnichat' and v_un) or (ie.fonte = 'respondi' and v_rs))
      order by ie.ocorreu_em desc limit v_lim)
    union all
    -- mini-CRM do CS (só leitura; D4 coexistir)
    (select 'cs-' || c.id, 'nota', coalesce(c.ultimo_contato_em, c.atualizado_em, c.criado_em),
            'CS: ' || coalesce(es.nome, 'sem estágio') || coalesce(' · ' || c.evento, ''),
            case when c.responsavel is not null then 'responsável: ' || c.responsavel end, 'crm', null, null, null, null, null
       from cs.contatos c left join cs.estagios es on es.id = c.estagio_id
      where c.comprador_id = any(v_compr))
    union all
    -- CRM: negócios (mesma regra da policy de negócio)
    (select 'ng-' || n.id, 'negocio', n.criado_em, 'Negócio criado · ' || f.nome, null, 'crm', f.projeto, n.linha,
            case when n.utm <> '{}'::jsonb then n.utm end, null, n.id
       from crm.negocio n join crm.funil f on f.id = n.funil_id
      where n.pessoa_id = any(v_g) and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by n.criado_em desc limit v_lim)
    union all
    (select 'lg-' || l.id, 'negocio', l.em,
            case l.acao when 'moveu_etapa' then 'Moveu para ' || coalesce(ep.nome, 'outra etapa')
                        when 'marcou_ganho' then 'Ganho' when 'marcou_perdido' then 'Perdido'
                        else 'Troca de dono' end || ' · ' || f.nome,
            l.resumo, 'crm', f.projeto, n.linha, null,
            case when l.acao = 'marcou_ganho' then n.valor end, n.id
       from crm.log l
       join crm.negocio n on n.id::text = l.entidade_id
       join crm.funil f on f.id = n.funil_id
       left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
      where l.pessoa_id = any(v_g) and l.entidade = 'negocio'
        and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
        and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by l.em desc limit v_lim)
    union all
    (select 'at-' || a.id, case when a.tipo in ('whatsapp', 'ligacao', 'email') then 'conversa' else 'nota' end, a.concluida_em,
            a.titulo || ' · concluída', a.resultado, 'crm', null, null, null, null, a.negocio_id
       from crm.atividade a
      where a.pessoa_id = any(v_g) and a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
      order by a.concluida_em desc limit v_lim)
    union all
    (select 'nt-' || nt.id, 'nota', nt.em, 'Nota interna', nt.texto, 'crm', null, null, null, null, nt.negocio_id
       from crm.nota nt
      where nt.pessoa_id = any(v_g)
      order by nt.em desc limit v_lim)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id, 'contatoId', v_atual, 'tipo', p.tipo, 'em', p.em, 'titulo', p.titulo, 'detalhe', p.detalhe,
           'fonte', p.fonte, 'lancamento', p.lancamento, 'produto', p.produto, 'utm', p.utm, 'valor', p.valor,
           'negocioId', p.negocio_id) order by p.em desc nulls last, p.id), '[]'::jsonb)
    into v
    from (select * from pts where pts.em is not null order by pts.em desc limit v_lim) p;
  return v;
end
$function$;
revoke all on function public.crm_jornada(uuid, integer) from public, anon;
grant execute on function public.crm_jornada(uuid, integer) to authenticated, service_role;
