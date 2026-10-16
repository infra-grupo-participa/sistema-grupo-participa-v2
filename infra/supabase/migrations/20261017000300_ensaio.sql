-- Ensaio de 20261017000300: como lf (Luis), num negócio aberto de outro dono; termina em RAISE (nada fica).
-- 20261017000300: vendedor faz tudo no Comercial (operação). Gerada a partir das definições no ar em 16/10/2026.
-- Configuração (funis, canais, catálogo, distribuição, motivos de perda, tokens, Hotmart) continua só do gestor.
create or replace function crm.eh_operador() returns boolean language sql stable security definer set search_path to '' as $f$
  -- 20261017000300: quem opera o Comercial como gestor (gestor, leitor para leitura, ou vendedor ativo). Escrita do leitor para em crm.guarda_escrita().
  select coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false);
$f$;
revoke all on function crm.eh_operador() from public; grant execute on function crm.eh_operador() to authenticated, service_role;
CREATE OR REPLACE FUNCTION public.crm_adicionar_nota(p_pessoa uuid, p_negocio uuid, p_texto text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; v_atual uuid; n crm.negocio%rowtype; v_id uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if btrim(coalesce(p_texto, '')) = '' then return crm.res(false, 'Nota vazia.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if p_negocio is not null then
    select * into n from crm.negocio x where x.id = p_negocio and x.pessoa_id = any(pessoas.grupo(v_atual));
    if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
    if not (coalesce(crm.eh_operador(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  elsif not crm.pode_escrever_pessoa(v_atual) then
    return crm.res(false, 'Este contato não é seu.');
  end if;
  perform set_config('crm.resumo', format('Registrou nota em %s', crm.nome_pessoa(v_atual)), true);
  insert into crm.nota (pessoa_id, negocio_id, texto, autor_id) values (v_atual, p_negocio, btrim(p_texto), v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('notaId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_atribuir_contato(p_pessoa uuid, p_dono uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r jsonb; v_atual uuid; v_pc uuid; v_nome text; v_para text; n record;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_operador(), false) then return crm.res(false, 'Só o gestor define dono.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then return crm.res(false, 'Escreva o motivo.'); end if;
  if not crm.vendedor_ativo(p_dono) then return crm.res(false, 'Vendedor não encontrado ou inativo.'); end if;
  v_nome := crm.nome_pessoa(v_atual); v_para := crm.nome_perfil(p_dono);
  v_pc := crm.garantir_pc(v_atual);
  perform set_config('crm.resumo', left(format('Definiu %s como dono de %s. Motivo: %s', v_para, v_nome, btrim(p_motivo)), 1000), true);
  update crm.pessoa_comercial x set dono_id = p_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is distinct from p_dono;
  for n in select x.id from crm.negocio x
            where x.pessoa_id = any(pessoas.grupo(v_atual)) and x.status = 'aberto' and x.dono_id is null for update loop
    perform set_config('crm.resumo', format('Negócio de %s herdou o dono %s', v_nome, v_para), true);
    update crm.negocio x set dono_id = p_dono, atualizado_em = now() where x.id = n.id;
  end loop;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_atribuir_item_fila(p_fila uuid, p_item uuid, p_responsavel uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r jsonb; it crm.fila_item%rowtype; f crm.fila%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_operador(), false) then return crm.res(false, 'Só o gestor distribui a fila.'); end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if p_responsavel is not null and not crm.vendedor_ativo(p_responsavel) then return crm.res(false, 'Vendedor inválido ou inativo.'); end if;
  if it.responsavel_id is not distinct from p_responsavel then return crm.res(true); end if;
  perform set_config('crm.resumo', format('Fila "%s": %s passou para %s', f.nome, crm.nome_pessoa(it.pessoa_id),
                                          crm.nome_perfil(p_responsavel)), true);
  update crm.fila_item x set responsavel_id = p_responsavel, alterado_por = auth.uid(), alterado_em = now() where x.id = p_item;
  return crm.res(true);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_atualizar_item_fila(p_fila uuid, p_item uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r jsonb; v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_operador(), false);
        it crm.fila_item%rowtype; f crm.fila%rowtype; v_pend int; v_emails text[]; v_resp uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_status is null or p_status not in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta',
                                          'declinou','sem_interesse','numero_invalido') then
    return crm.res(false, 'Status inválido.');
  end if;
  select * into it from crm.fila_item x where x.id = p_item and x.fila_id = p_fila for update;
  if not found then return crm.res(false, 'Item não encontrado.'); end if;
  select * into f from crm.fila x where x.id = p_fila;
  if not (v_gestor or it.responsavel_id is not distinct from v_eu
          or (it.responsavel_id is null and coalesce(crm.eh_vendedor(), false))) then
    return crm.res(false, 'Este contato da fila é de outro vendedor.');
  end if;
  if f.encerrada_em is not null then return crm.res(false, 'Fila encerrada.'); end if;
  if it.status = p_status then return crm.res(true); end if;
  if crm.oferta_vigente_texto(f.oferta_codigo) is null then
    return crm.res(false, 'Sem oferta vigente: não se aborda. O gestor define a oferta da fila.');
  end if;
  if it.faixa in ('C', 'D') then
    select count(*) into v_pend from crm.fila_item x where x.fila_id = p_fila and x.faixa in ('A', 'B') and x.status = 'a_abordar';
    if v_pend > 0 then return crm.res(false, format('Faixas C e D só depois de A e B zeradas (faltam %s).', v_pend)); end if;
  end if;
  if p_status in ('tentando_contato', 'em_conversa', 'vai_comprar')
     and exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(it.pessoa_id))) and pc.opt_out) then
    return crm.res(false, 'Este contato pediu para não receber contato.');
  end if;
  if p_status = 'ganho' then
    v_emails := crm.emails_da_pessoa(it.pessoa_id);
    if not exists (
      select 1 from (select * from fin.hotmart_transacoes where conta = 'academy'
                     union all
                     select * from fin.hotmart_transacoes where conta = 'escritorio') h
        join crm.produto_comercial pc on pc.produto_id = h.produto_id and pc.no_comercial and pc.linha = f.linha
       where lower(btrim(h.comprador_email)) = any(v_emails) and h.status in ('APPROVED', 'COMPLETE')
         and h.aprovado_em >= f.criada_em) then
      return crm.res(false, 'Ganho só com pagamento aprovado na Hotmart (produto da fila, depois da montagem).');
    end if;
  end if;
  v_resp := coalesce(it.responsavel_id, case when not v_gestor then v_eu end);
  perform set_config('crm.resumo', format('Mudou %s na fila: %s → %s', crm.nome_pessoa(it.pessoa_id), it.status, p_status), true);
  update crm.fila_item x set status = p_status, responsavel_id = v_resp, alterado_por = v_eu, alterado_em = now()
   where x.id = p_item;
  return crm.res(true);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_cancelar_agendada(p_mensagem uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; m crm.mensagem%rowtype;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into m from crm.mensagem x where x.id = p_mensagem for update;
  if not found or m.agendada_para is null or m.excluida_em is not null or not crm.pode_escrever_pessoa(m.pessoa_id) then
    return crm.res(false, 'Mensagem agendada não encontrada.');
  end if;
  if m.autor_id is distinct from v_eu and not coalesce(crm.eh_operador(), false) then return crm.res(false, 'Só quem agendou (ou o gestor) cancela.'); end if;
  if m.status <> 'na_fila' or m.fila_em <= now() then return crm.res(false, 'A mensagem já está saindo ou já saiu.'); end if;
  update crm.mensagem x set status = 'falhou', status_em = now(), erro = 'Agendamento cancelado.',
         excluida_em = now(), excluida_por = v_eu, excluida_motivo = 'Agendamento cancelado antes do envio.'
   where x.id = m.id;
  perform crm.log_registrar('excluiu', 'mensagem', m.id::text, pessoas.atual(m.pessoa_id),
                            'Cancelou mensagem agendada para ' || crm.nome_pessoa(m.pessoa_id),
                            jsonb_build_object('agendada_para', m.agendada_para));
  return crm.res(true, 'Agendamento cancelado.');
end $function$;

CREATE OR REPLACE FUNCTION public.crm_concluir_atividade(p_atividade uuid, p_resultado text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; a crm.atividade%rowtype; v_res text; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into a from crm.atividade x where x.id = p_atividade for update;
  if not found or a.concluida_em is not null then return crm.res(false, 'Atividade não encontrada ou já concluída.'); end if;
  if not (coalesce(crm.eh_operador(), false) or a.dono_id = v_eu) then return crm.res(false, 'Esta atividade não é sua.'); end if;
  v_res := coalesce(nullif(btrim(coalesce(p_resultado, '')), ''), 'Feito');
  perform set_config('crm.resumo', left(format('Concluiu "%s" (%s) de %s', a.titulo, v_res, crm.nome_pessoa(a.pessoa_id)), 1000), true);
  update crm.atividade x set concluida_em = now(), resultado = left(v_res, 1000) where x.id = p_atividade;
  if a.negocio_id is not null then
    update crm.negocio x set ultima_interacao_em = now() where x.id = a.negocio_id;   -- coluna ignorada pelo log
  end if;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_criar_atividade(p_negocio uuid, p_pessoa uuid, p_tipo text, p_titulo text, p_vence_em timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; v_atual uuid; n crm.negocio%rowtype; v_dono uuid; v_id uuid;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if btrim(coalesce(p_titulo, '')) = '' then return crm.res(false, 'Dê um título à atividade.'); end if;
  if p_tipo is null or p_tipo not in ('whatsapp', 'ligacao', 'email', 'tarefa', 'reuniao') then
    return crm.res(false, 'Tipo de atividade inválido.');
  end if;
  if p_vence_em is null then return crm.res(false, 'Informe quando vence.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if p_negocio is not null then
    select * into n from crm.negocio x where x.id = p_negocio and x.pessoa_id = any(pessoas.grupo(v_atual));
    if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
    if not (coalesce(crm.eh_operador(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
    v_dono := coalesce(n.dono_id, v_eu);
  else
    if not crm.pode_escrever_pessoa(v_atual) then return crm.res(false, 'Este contato não é seu.'); end if;
    v_dono := v_eu;
  end if;
  perform set_config('crm.resumo', format('Agendou "%s" para %s', btrim(p_titulo), crm.nome_pessoa(v_atual)), true);
  insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, criado_por)
  values (p_negocio, v_atual, v_dono, p_tipo, btrim(p_titulo), p_vence_em, v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('atividadeId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_criar_contato(p_dados jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_r jsonb; v_eu uuid := auth.uid();
  v_nome text; v_email_in text; v_tel_in text; v_dono_in text;
  v_gestor boolean; v_dono_pedido uuid; v_dono uuid;
  v_reg jsonb; v_atual uuid; v_nova boolean; v_pc uuid; v_dono_atual uuid; v_nome_pessoa text;
  v_s text; v_c text; v_m text;
begin
  perform crm.exige_comercial();
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;

  v_nome := nullif(btrim(coalesce(p_dados ->> 'nome', '')), '');
  if v_nome is null or length(v_nome) < 2 then return crm.res(false, 'Informe o nome.'); end if;
  if length(v_nome) > 160 then return crm.res(false, 'Nome longo demais (até 160 caracteres).'); end if;
  v_email_in := nullif(btrim(coalesce(p_dados ->> 'email', '')), '');
  v_tel_in := nullif(btrim(coalesce(p_dados ->> 'telefone', '')), '');
  if v_email_in is null and v_tel_in is null then return crm.res(false, 'Informe telefone ou e-mail.'); end if;
  if v_email_in is not null and pessoas.norm_email(v_email_in) is null then return crm.res(false, 'E-mail inválido.'); end if;
  if v_tel_in is not null and pessoas.norm_telefone(v_tel_in) is null then
    return crm.res(false, 'Telefone inválido: use DDD + número (celular com 9).');
  end if;

  -- Dono: gestor escolhe (ou deixa sem); vendedor ativo é o dono do que cadastra.
  v_gestor := coalesce(crm.eh_operador(), false);
  v_dono_in := nullif(btrim(coalesce(p_dados ->> 'dono', '')), '');
  if v_dono_in is not null then
    v_dono_pedido := crm.uuid_ou_null(v_dono_in);
    if v_dono_pedido is null or not coalesce(crm.vendedor_ativo(v_dono_pedido), false) then
      return crm.res(false, 'Vendedor não encontrado ou inativo.');
    end if;
    if not v_gestor and v_dono_pedido is distinct from v_eu then
      return crm.res(false, 'Só o gestor escolhe outro dono.');
    end if;
  end if;
  v_dono := coalesce(v_dono_pedido, case when coalesce(crm.vendedor_ativo(v_eu), false) then v_eu end);

  v_reg := pessoas.registrar(jsonb_build_object('nome', v_nome, 'email', v_email_in, 'telefone', v_tel_in, 'evento', 'cadastro'),
                             'crm', v_eu);
  if not coalesce((v_reg ->> 'ok')::boolean, false) then
    return crm.res(false, coalesce(v_reg ->> 'msg', 'Não foi possível cadastrar.'));
  end if;
  v_atual := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);
  v_nova := coalesce((v_reg ->> 'nova')::boolean, false);
  v_nome_pessoa := crm.nome_pessoa(v_atual);

  if v_nova then
    perform set_config('crm.resumo', left(format('Cadastrou o contato %s (dono: %s)', v_nome_pessoa, crm.nome_perfil(v_dono)), 1000), true);
    insert into crm.pessoa_comercial (pessoa_id, dono_id) values (v_atual, v_dono) on conflict (pessoa_id) do nothing;
    perform set_config('crm.resumo', '', true);
    v_pc := crm.garantir_pc(v_atual);
    return crm.res(true, 'Contato cadastrado.', jsonb_build_object('contatoId', v_atual, 'nova', true, 'donoId', v_dono));
  end if;

  -- Já existia (casou por e-mail ou telefone): nunca troca dono.
  v_pc := crm.garantir_pc(v_atual);
  select pc.dono_id into v_dono_atual from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;
  if v_dono_atual is null and v_dono is not null then
    perform set_config('crm.resumo', left(format('Cadastro repetido de %s: dono %s', v_nome_pessoa, crm.nome_perfil(v_dono)), 1000), true);
    update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is null;
    perform set_config('crm.resumo', '', true);
    v_dono_atual := v_dono;
  end if;
  if v_dono_atual is not null and v_dono is not null and v_dono_atual <> v_dono then
    if not coalesce(crm.pode_ver_pessoa(v_atual), false) then
      return crm.res(false, format('Esse contato já está no CRM com outro dono (%s). O dono não mudou: fale com o gestor.',
                                   crm.nome_perfil(v_dono_atual)));
    end if;
    return crm.res(true, format('Esse contato já estava no CRM com outro dono (%s). O dono não mudou.', crm.nome_perfil(v_dono_atual)),
                   jsonb_build_object('contatoId', v_atual, 'nova', false, 'donoId', v_dono_atual));
  end if;
  return crm.res(true, 'Esse contato já estava no CRM: abri a ficha dele.',
                 jsonb_build_object('contatoId', v_atual, 'nova', false, 'donoId', v_dono_atual));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_criar_negocio(p_pessoa uuid, p_funil uuid, p_campanha uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r jsonb; v_atual uuid; v_g uuid[]; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pc uuid; v_utm jsonb;
        v_valor numeric; v_id uuid; v_nome text; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual)
     or not (coalesce(crm.eh_operador(), false) or coalesce(crm.pode_ver_pessoa(v_atual), false)) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  v_g := pessoas.grupo(v_atual);
  if exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and pc.opt_out) then
    return crm.res(false, 'Este contato pediu para não receber contato.');
  end if;
  select * into f from crm.funil x where x.id = p_funil and x.ativo;
  if not found then return crm.res(false, 'Funil não encontrado.'); end if;
  if p_campanha is not null and not exists (select 1 from crm.campanha c where c.id = p_campanha and c.funil_id = p_funil) then
    return crm.res(false, 'Campanha não é deste funil.');
  end if;
  perform pg_advisory_xact_lock(hashtext('crm.dist:' || p_funil::text));
  if exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.funil_id = p_funil and n.status = 'aberto') then
    return crm.res(false, 'Este contato já tem negócio aberto neste funil.');
  end if;
  select e.id into v_etapa from crm.etapa_funil e where e.funil_id = p_funil and e.arquivada_em is null order by e.ordem limit 1;
  if v_etapa is null then return crm.res(false, 'Funil sem etapas.'); end if;
  v_dono := crm.escolher_dono(v_atual, p_funil);
  v_nome := crm.nome_pessoa(v_atual);
  v_pc := crm.garantir_pc(v_atual);
  if v_dono is not null then
    perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição)', v_nome, crm.nome_perfil(v_dono)), true);
    update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is null;
  end if;
  select pc.utm_primeira into v_utm from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;
  select l.ticket_ref into v_valor from crm.linha l where l.chave = f.linha;
  perform set_config('crm.resumo', format('Criou negócio de %s em %s (dono: %s)', v_nome, f.nome, crm.nome_perfil(v_dono)), true);
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, campos, utm, ultima_interacao_em)
  values (v_atual, p_funil, v_etapa, p_campanha, f.linha, 'venda_ativa', v_dono, coalesce(v_valor, 0),
          jsonb_build_object('origem', coalesce(nullif(v_utm ->> 'source', ''), 'direto') || ' / ' || coalesce(nullif(v_utm ->> 'campaign', ''), '—')),
          coalesce(v_utm, '{}'::jsonb), null)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('negocioId', v_id, 'donoId', v_dono));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_filas(p_incluir_encerradas boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_gestor boolean := coalesce(crm.eh_operador(), false); v jsonb;
begin
  perform crm.exige_comercial();
  with f as (
    select x.* from crm.fila x where coalesce(p_incluir_encerradas, false) or x.encerrada_em is null
     order by x.criada_em desc limit 50),
  it as (
    select i.*, row_number() over (partition by i.fila_id order by i.score desc, i.id) rn
      from crm.fila_item i
     where i.fila_id in (select f.id from f) and (v_gestor or i.responsavel_id = v_eu or i.responsavel_id is null)),
  al as (select * from crm.atual_de(array(select distinct it.pessoa_id from it where it.rn <= 5000)))
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', f.id, 'nome', f.nome, 'produto', f.linha, 'criadaEm', f.criada_em,
           'ofertaVigente', crm.oferta_vigente_texto(f.oferta_codigo), 'ofertaCodigo', f.oferta_codigo,
           'projeto', f.projeto, 'encerradaEm', f.encerrada_em,
           'itens', coalesce((select jsonb_agg(jsonb_build_object(
                        'id', it.id, 'contatoId', al.atual, 'score', it.score, 'faixa', it.faixa, 'sinais', to_jsonb(it.sinais),
                        'status', it.status, 'responsavelId', it.responsavel_id, 'alteradoPor', it.alterado_por,
                        'alteradoEm', it.alterado_em) order by it.score desc, it.id)
                       from it left join al on al.pessoa_id = it.pessoa_id
                      where it.fila_id = f.id and it.rn <= 5000), '[]'::jsonb))
           order by f.criada_em desc), '[]'::jsonb)
    into v from f;
  return v;
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_jornada(p_pessoa uuid, p_limite integer DEFAULT 500)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_operador(), false);
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
       from crm.negocio n join crm.funil f on f.id = n.funil_id and f.ativo
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
       join crm.funil f on f.id = n.funil_id and f.ativo
       left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
      where l.pessoa_id = any(v_g) and l.entidade = 'negocio'
        and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
        and (v_gestor or n.dono_id = v_eu or n.dono_id is null)
      order by l.em desc limit v_lim)
    union all
    (select 'at-' || a.id, case when a.tipo in ('whatsapp', 'ligacao', 'email') then 'conversa' else 'nota' end, a.concluida_em,
            a.titulo || ' · concluída', a.resultado, 'crm', null, null, null, null, a.negocio_id
       from crm.atividade a
      where a.pessoa_id = any(v_g) and a.concluida_em is not null and not crm.negocio_oculto(a.negocio_id::text) and (v_gestor or a.dono_id = v_eu)
      order by a.concluida_em desc limit v_lim)
    union all
    (select 'nt-' || nt.id, 'nota', nt.em, 'Nota interna', nt.texto, 'crm', null, null, null, null, nt.negocio_id
       from crm.nota nt
      where nt.pessoa_id = any(v_g) and not crm.negocio_oculto(nt.negocio_id::text)
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

CREATE OR REPLACE FUNCTION public.crm_marcar_perdido(p_negocio uuid, p_motivo text, p_nota text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; m crm.motivo_perda%rowtype; v_nome text; v_pc uuid;
        a record; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Só negócio aberto pode ser perdido.'); end if;
  if not (coalesce(crm.eh_operador(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  if n.status <> 'aberto' then return crm.res(false, 'Só negócio aberto pode ser perdido.'); end if;
  select * into m from crm.motivo_perda x where x.chave = p_motivo and x.ativo;
  if not found then return crm.res(false, 'Motivo fora do cadastro não existe.'); end if;
  v_nome := crm.nome_pessoa(n.pessoa_id);
  perform set_config('crm.resumo', format('Marcou %s como perdido: %s', v_nome, m.rotulo), true);
  update crm.negocio x set status = 'perdido', motivo_perda = m.chave, nota_perda = nullif(btrim(coalesce(p_nota, '')), ''),
                           fechado_em = now(), atualizado_em = now()
   where x.id = p_negocio;
  for a in select x.id, x.titulo from crm.atividade x where x.negocio_id = p_negocio and x.concluida_em is null for update loop
    perform set_config('crm.resumo', format('Cancelou "%s" de %s: negócio perdido', a.titulo, v_nome), true);
    update crm.atividade x set concluida_em = now(), resultado = 'Cancelada: negócio perdido', cancelada = true where x.id = a.id;
  end loop;
  if m.bloqueia then
    v_pc := crm.garantir_pc(n.pessoa_id);
    perform set_config('crm.resumo', format('%s foi para a lista de bloqueio (%s)', v_nome, m.rotulo), true);
    update crm.pessoa_comercial x set opt_out = true, opt_out_em = now(), opt_out_motivo = left(m.rotulo, 200), atualizado_em = now()
     where x.pessoa_id = v_pc and not x.opt_out;
  end if;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_mcp_negocio_campos(p_negocio uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  n record; px record; v_linhas jsonb; v_campos jsonb; v_obrig jsonb; v_falta jsonb; v_pode boolean;
begin
  perform crm.exige_comercial();
  -- RLS de crm.negocio (negocio_ler): gestor/leitor vê todos; vendedor os seus e os sem dono.
  select x.id, x.pessoa_id, x.funil_id, x.etapa_id, x.status, x.dono_id, coalesce(x.campos, '{}'::jsonb) campos,
         e.nome etapa_nome, e.ordem etapa_ordem, f.nome funil_nome
    into n
    from crm.negocio x
    join crm.etapa_funil e on e.id = x.etapa_id
    join crm.funil f on f.id = x.funil_id and f.ativo
   where x.id = p_negocio;
  if not found then
    return jsonb_build_object('ok', false, 'msg', 'Negócio não encontrado ou sem acesso.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('valor', l.chave, 'rotulo', l.nome) order by l.ordem, l.chave), '[]'::jsonb)
    into v_linhas from crm.linha l where l.ativo;

  select coalesce(jsonb_agg(jsonb_build_object(
           'chave', d.chave, 'rotulo', d.rotulo, 'tipo', d.tipo,
           'opcoes', case d.tipo when 'opcao' then to_jsonb(d.opcoes) when 'linha' then v_linhas end,
           'valor', n.campos -> d.chave) order by d.ordem, d.chave), '[]'::jsonb)
    into v_campos from crm.campo_def d where d.ativo;

  -- Próxima etapa (mesma ordem do funil, não arquivada). Obrigatórios = acumulados até ela (regra de crm.campos_faltando).
  select e.id, e.nome, e.papel, e.ordem into px
    from crm.etapa_funil e
   where e.funil_id = n.funil_id and e.arquivada_em is null and e.ordem > n.etapa_ordem
   order by e.ordem, e.id limit 1;
  if px.id is not null then
    with ex as (
      select u.c, min(e.ordem::int * 1000 + u.o) k
        from crm.etapa_funil e
       cross join lateral unnest(e.campos_obrigatorios) with ordinality u(c, o)
       where e.funil_id = n.funil_id and e.arquivada_em is null and e.ordem <= px.ordem
       group by u.c)
    select coalesce(jsonb_agg(ex.c order by ex.k), '[]'::jsonb),
           coalesce(jsonb_agg(ex.c order by ex.k) filter (where nullif(btrim(coalesce(n.campos ->> ex.c, '')), '') is null), '[]'::jsonb)
      into v_obrig, v_falta
      from ex;
  end if;

  v_pode := coalesce(crm.pode_escrever(), false) and (coalesce(crm.eh_operador(), false) or n.dono_id = v_eu);

  return jsonb_build_object(
    'ok', true,
    'negocio', jsonb_build_object('id', n.id, 'contatoId', n.pessoa_id, 'funilId', n.funil_id, 'funilNome', n.funil_nome,
                                  'etapaId', n.etapa_id, 'etapaNome', n.etapa_nome, 'status', n.status, 'donoId', n.dono_id),
    'podeEditar', v_pode,
    'campos', v_campos,
    'proximaEtapa', case when px.id is null then null
                         else jsonb_build_object('id', px.id, 'nome', px.nome, 'papel', px.papel,
                                                 'obrigatorios', v_obrig, 'faltando', v_falta) end);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_mover_etapa(p_negocio uuid, p_etapa uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; e crm.etapa_funil%rowtype; v_de text; v_falta text;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
  if not (coalesce(crm.eh_operador(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  if n.etapa_id = p_etapa then return crm.res(true); end if;
  if n.status <> 'aberto' then return crm.res(false, 'Negócio encerrado não muda de etapa.'); end if;
  select * into e from crm.etapa_funil x where x.id = p_etapa and x.funil_id = n.funil_id and x.arquivada_em is null;
  if not found then return crm.res(false, 'Etapa não existe neste funil.'); end if;
  if e.papel = 'fechado' then return crm.res(false, 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.'); end if;
  v_falta := crm.campos_faltando(n.campos, n.funil_id, p_etapa);
  if v_falta is not null then return crm.res(false, 'Preencha antes: ' || v_falta || '.'); end if;
  select x.nome into v_de from crm.etapa_funil x where x.id = n.etapa_id;
  perform set_config('crm.resumo', format('Moveu %s de %s para %s', crm.nome_pessoa(n.pessoa_id), v_de, e.nome), true);
  update crm.negocio x set etapa_id = p_etapa, etapa_desde = now(), ultima_interacao_em = now(), atualizado_em = now()
   where x.id = p_negocio;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_reabrir_atividade(p_atividade uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; a crm.atividade%rowtype; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_atividade is null then return crm.res(false, 'Atividade inválida.'); end if;
  select * into a from crm.atividade x where x.id = p_atividade for update;
  if not found or a.concluida_em is null then return crm.res(false, 'Atividade não encontrada ou ainda aberta.'); end if;
  if not (coalesce(crm.eh_operador(), false) or a.dono_id = v_eu) then return crm.res(false, 'Esta atividade não é sua.'); end if;
  perform set_config('crm.resumo', left(format('Reabriu a atividade "%s"', a.titulo), 1000), true);
  update crm.atividade x set concluida_em = null, resultado = null where x.id = p_atividade;
  perform set_config('crm.resumo', '', true);
  return crm.res(true, 'Atividade reaberta.', jsonb_build_object('atividadeId', a.id, 'venceEm', a.vence_em));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_salvar_campos(p_negocio uuid, p_campos jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; v_novo jsonb; v_qtd int;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if jsonb_typeof(p_campos) is distinct from 'object' then return crm.res(false, 'Campos inválidos.'); end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
  if not (coalesce(crm.eh_operador(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  select count(*) into v_qtd from jsonb_each(p_campos) c
   where coalesce(n.campos ->> c.key, '') is distinct from coalesce(c.value #>> '{}', '');
  if v_qtd = 0 then return crm.res(true); end if;
  v_novo := jsonb_strip_nulls(n.campos || p_campos);
  perform set_config('crm.resumo', format('Editou %s campo(s) de %s', v_qtd, crm.nome_pessoa(n.pessoa_id)), true);
  update crm.negocio x set campos = v_novo, atualizado_em = now() where x.id = p_negocio;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_transferir_dono(p_negocio uuid, p_dono uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r jsonb; n crm.negocio%rowtype; v_nome text; v_de text; v_para text; v_pc uuid; a record;
        v_s text; v_c text; v_m text; v_gestor boolean := coalesce(crm.eh_operador(), false);
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  -- 20261017000100: vendedor com o funil liberado (crm.vendedor_funil_aberto) puxa negócio ABERTO desse funil para SI MESMO
  if not v_gestor and cardinality(crm.funis_ve_todos()) = 0 then return crm.res(false, 'Troca de dono só pelo gestor do Comercial.'); end if;
  if btrim(coalesce(p_motivo, '')) = '' then return crm.res(false, 'Escreva o motivo da troca.'); end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
  if not v_gestor then
    if not (n.funil_id = any(crm.funis_ve_todos())) then return crm.res(false, 'Troca de dono só pelo gestor do Comercial.'); end if;
    if p_dono is distinct from (select auth.uid()) then return crm.res(false, 'Você só pode puxar o negócio para você mesmo.'); end if;
    if n.status <> 'aberto' then return crm.res(false, 'Só negócio aberto pode ser puxado para você.'); end if;
  end if;
  if not crm.vendedor_ativo(p_dono) then return crm.res(false, 'Vendedor não encontrado ou inativo.'); end if;
  if n.dono_id = p_dono then return crm.res(true); end if;
  v_nome := crm.nome_pessoa(n.pessoa_id); v_de := crm.nome_perfil(n.dono_id); v_para := crm.nome_perfil(p_dono);
  perform set_config('crm.resumo', left(format('Trocou o dono de %s: %s → %s. Motivo: %s', v_nome, v_de, v_para, btrim(p_motivo)), 1000), true);
  update crm.negocio x set dono_id = p_dono, atualizado_em = now() where x.id = p_negocio;
  v_pc := crm.garantir_pc(n.pessoa_id);
  perform set_config('crm.resumo', format('Dono do contato %s: %s', v_nome, v_para), true);
  update crm.pessoa_comercial x set dono_id = p_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is distinct from p_dono;
  for a in select x.id, x.titulo from crm.atividade x
            where x.negocio_id = p_negocio and x.concluida_em is null and x.dono_id is distinct from p_dono for update loop
    perform set_config('crm.resumo', format('Atividade "%s" passou para %s', a.titulo, v_para), true);
    update crm.atividade x set dono_id = p_dono where x.id = a.id;
  end loop;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

CREATE OR REPLACE FUNCTION crm.pode_escrever_pessoa(p uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_eu uuid := auth.uid(); v_g uuid[];
begin
  if p is null or v_eu is null then return false; end if;
  if not crm.pode_escrever() then return false; end if;  -- 20261008lt: leitor não escreve
  if coalesce(crm.eh_gestor(), false) then return true; end if;
  if coalesce(crm.eh_vendedor(), false) then return true; end if;  -- 20261017000300: vendedor escreve para qualquer contato
  if not coalesce(crm.eh_vendedor(), false) then return false; end if;
  v_g := pessoas.grupo(pessoas.atual(p));
  return coalesce(exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and pc.dono_id = v_eu)
               or exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.dono_id = v_eu), false);
end
$function$;

alter policy log_ler on crm.log using (( SELECT crm.eh_gestor() AS eh_gestor) OR ( SELECT crm.eh_vendedor() AS eh_vendedor));  -- 20261017000300
alter policy atividade_ler on crm.atividade using (( SELECT crm.eh_gestor() AS eh_gestor) OR ( SELECT crm.eh_vendedor() AS eh_vendedor));  -- 20261017000300
alter policy nota_ler on crm.nota using (( SELECT crm.eh_gestor() AS eh_gestor) OR ( SELECT crm.eh_vendedor() AS eh_vendedor));  -- 20261017000300
alter policy fila_item_ler on crm.fila_item using (( SELECT crm.eh_gestor() AS eh_gestor) OR ( SELECT crm.eh_vendedor() AS eh_vendedor));  -- 20261017000300
alter policy conversa_ler on crm.conversa using ((excluida_em IS NULL) AND (( SELECT crm.eh_gestor() AS eh_gestor) OR ( SELECT crm.eh_vendedor() AS eh_vendedor)));  -- 20261017000300
alter policy mensagem_ler on crm.mensagem using ((excluida_em IS NULL) AND (( SELECT crm.eh_gestor() AS eh_gestor) OR ( SELECT crm.eh_vendedor() AS eh_vendedor)));  -- 20261017000300

-- Aldri Santana (AS) e Marco (MA) viram vendedores
update public.perfis set areas = array(select distinct unnest(coalesce(areas,'{}') || '{comercial}'::text[])),
       funcoes = array(select distinct unnest(coalesce(funcoes,'{}') || '{comercial.vender}'::text[]))
 where id in ('0f6dd53c-6d1a-4f6b-af00-dc05e6284f68','85016fb8-5f7b-4474-a418-bc1ab87f870b');
insert into crm.vendedor (perfil_id, sigla, ativo) values
  ('0f6dd53c-6d1a-4f6b-af00-dc05e6284f68','as',true), ('85016fb8-5f7b-4474-a418-bc1ab87f870b','ma',true)
on conflict (perfil_id) do update set sigla = excluded.sigla, ativo = true;

create temp table _r(k text, v text); grant all on _r to authenticated;
do $t$
declare n crm.negocio%rowtype; e uuid; v_lf uuid := '9d5fb8e7-f61e-459d-be04-d103ec783c08'; v_gs uuid := '46b36c51-06a6-4062-9e8f-41d2579b50c8';
begin
  select x.* into n from crm.negocio x where x.status='aberto' and x.dono_id is not null and x.dono_id <> v_lf
     and exists (select 1 from crm.etapa_funil ef where ef.funil_id=x.funil_id and ef.id<>x.etapa_id and ef.arquivada_em is null and coalesce(ef.papel,'') not in ('ganho','perdido') and cardinality(coalesce(ef.campos_obrigatorios,'{}'))=0)
     limit 1;
  select ef.id into e from crm.etapa_funil ef where ef.funil_id=n.funil_id and ef.id<>n.etapa_id and ef.arquivada_em is null and coalesce(ef.papel,'') not in ('ganho','perdido') and cardinality(coalesce(ef.campos_obrigatorios,'{}'))=0 limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub',v_lf,'role','authenticated')::text, true);
  set local role authenticated;
  insert into _r values ('mover', public.crm_mover_etapa(n.id, e)::text);
  insert into _r values ('salvar_campos', public.crm_salvar_campos(n.id, '{}'::jsonb)::text);
  insert into _r values ('nota', public.crm_adicionar_nota(n.pessoa_id, n.id, 'ensaio')::text);
  insert into _r values ('atividade', public.crm_criar_atividade(n.id, n.pessoa_id, 'ligacao', 'ensaio', now()+interval '1 day')::text);
  insert into _r values ('trocar_dono', public.crm_transferir_dono(n.id, v_gs, 'ensaio')::text);
  insert into _r values ('atribuir_contato', public.crm_atribuir_contato(n.pessoa_id, v_gs, 'ensaio')::text);
  insert into _r values ('ve_atividades', (select count(*) from crm.atividade)::text);
  insert into _r values ('ve_conversas', (select count(*) from crm.conversa)::text);
  insert into _r values ('sessao', public.crm_sessao()::text);
  reset role;
  insert into _r values ('vendedores', (select string_agg(sigla||'='||crm.vendedor_ativo(perfil_id)::text, ',') from crm.vendedor where sigla in ('as','ma')));
end $t$;
do $f$ begin raise exception 'ENSAIO %', (select json_agg(_r) from _r); end $f$;
