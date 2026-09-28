-- 20260928z58 — SEGURANÇA: fecha funções SECURITY DEFINER de public que qualquer visitante (anon) executava.
--
-- Achados do kirad (28/09), confirmados pelo coordenador em produção: função em `public` é exposta pela API; o
-- `create function` dá EXECUTE a PUBLIC por padrão; estas não têm guarda no corpo.
--   CRÍTICO  app_aplicar_matricula / app_revogar_matricula — anon concedia/revogava curso de qualquer usuário
--            (app_matriculas); app_user_id_por_email — anon achava o uuid pelo e-mail (cadeia do ataque).
--   ALTO     fn_respondi_hm_form / fn_grupo_hm_evento — anon forjava respostas de formulário e entrada/saída de grupo.
--   MÉDIO    fn_log_evento_hotmart, fn_log_hotmart_evento, fn_log_webhook, fn_alerta_hotmart — forja de auditoria;
--            fn_recalcular_situacao_acesso — recálculo em massa disparado por anon; fn_hm_pagamentos — pagamento
--            por compra_id; tem_permissao — mapear permissões de qualquer usuário.
--
-- Quem chama (conferido 28/09): edge functions hotmart-events-webhook, respondi-hm-webhook e grupo-hm-webhook usam
-- SUPABASE_SERVICE_ROLE_KEY (sistema-disparos-participa e infra/supabase/functions) → continuam funcionando.
-- app_* : nenhum chamador no código desta máquina; logs 24 h só os testes do pentest; pg_stat ~0 chamadas.
-- fn_hm_pagamentos: web/modules/alunos/ui/acesso-hm-data.ts (equipe logada) → mantém authenticated.
-- NÃO mexe em fn_central_match (formulário público de placas depende de anon; devolve só id/casamento).
--
-- REVERSÃO: grant execute on function <assinatura> to public;  (reabre — só com decisão explícita)

-- 1) Só service_role (robôs): tira PUBLIC, anon e authenticated
do $do$
declare f text;
begin
  foreach f in array array[
    'public.app_aplicar_matricula(uuid,uuid,text,integer)',
    'public.app_revogar_matricula(uuid,uuid)',
    'public.app_user_id_por_email(text)',
    'public.fn_respondi_hm_form(text,text,text,jsonb,numeric)',
    'public.fn_grupo_hm_evento(text,text,text,text)',
    'public.fn_log_evento_hotmart(text,text,text,jsonb)',
    'public.fn_log_hotmart_evento(text,text,text,jsonb)',
    'public.fn_log_webhook(text,text,jsonb)',
    'public.fn_alerta_hotmart(text,text,text,text)',
    'public.fn_recalcular_situacao_acesso()'
  ] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $do$;

-- 2) Equipe logada continua; visitante não
do $do$
declare f text;
begin
  foreach f in array array[
    'public.fn_hm_pagamentos(uuid[])',
    'public.tem_permissao(uuid,text)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $do$;

-- Conferência (falha → rollback)
do $chk$
begin
  if has_function_privilege('anon','public.app_aplicar_matricula(uuid,uuid,text,integer)','execute')
     or has_function_privilege('authenticated','public.app_aplicar_matricula(uuid,uuid,text,integer)','execute')
     or has_function_privilege('anon','public.fn_respondi_hm_form(text,text,text,jsonb,numeric)','execute')
     or has_function_privilege('anon','public.fn_log_evento_hotmart(text,text,text,jsonb)','execute')
     or has_function_privilege('anon','public.fn_hm_pagamentos(uuid[])','execute')
     or has_function_privilege('anon','public.tem_permissao(uuid,text)','execute') then
    raise exception 'z58: ainda aberto a anon/authenticated';
  end if;
  if not has_function_privilege('service_role','public.fn_log_evento_hotmart(text,text,text,jsonb)','execute')
     or not has_function_privilege('service_role','public.fn_alerta_hotmart(text,text,text,text)','execute')
     or not has_function_privilege('authenticated','public.fn_hm_pagamentos(uuid[])','execute') then
    raise exception 'z58: tirou acesso de quem precisa (service_role/authenticated)';
  end if;
end $chk$;
