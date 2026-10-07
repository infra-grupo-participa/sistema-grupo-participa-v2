-- 20261007192446 (escrita como 20261007u) — APLICADA em 07/10/2026 — CRM: funil arquivado OCULTA os negócios dele (pedido do Arthur, 07/10/2026: "não me apresenta nada da Clint").
--
-- Antes: crm_arquivar_funil recusava funil com negócio aberto, e as listas (crm_negocios, crm_atividades, crm_desempenho,
-- Início, sino) não olhavam crm.funil.ativo — arquivar não escondia nada.
-- Agora:
--   * crm_arquivar_funil(p_funil, p_com_abertos default false): com p_com_abertos = true o gestor arquiva mesmo com
--     negócio aberto. Nada é apagado nem fechado: os negócios ficam congelados e ocultos.
--   * crm_desarquivar_funil(p_funil): traz o funil e tudo o que estava oculto de volta.
--   * Negócio de funil arquivado (e atividade, nota, notificação e log ligados a ele) sai de: crm_negocios,
--     crm_atividades, crm_desempenho, crm_funil_resumo (funil arquivado = não encontrado), crm_notificacoes (sino),
--     crm_jornada, crm_eventos, crm.contatos_metricas (lista de contatos/Início), crm.notificar_prazos (cron não cobra),
--     crm.supressao_motivo e crm.estrategia_candidatos ("em negociação" não conta oculto),
--     crm.hotmart_processar (compra aprovada não fecha negócio oculto).
--   * Acesso (pode_ver_pessoa, contatos_visiveis, pessoas_do_vendedor) NÃO muda: é visibilidade de contato, não lista.
--
-- Cada função existente é recriada a partir do corpo VIVO (pg_get_functiondef) com remendo pontual; aborta se o md5 do
-- corpo vivo não for o esperado ou se o trecho não aparecer exatamente 1 vez. ACL preservada (create or replace).
-- Reversão: desarquivar o funil (dado) ou reaplicar os corpos anteriores (md5 no cabeçalho de cada remendo).

set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function pg_temp.remendar(p_fn regprocedure, p_md5 text, p_pares jsonb) returns void
language plpgsql as $f$
declare v text := pg_get_functiondef(p_fn); par jsonb; n int;
begin
  if md5(v) <> p_md5 then raise exception 'premissa: % mudou (md5 vivo %, esperado %)', p_fn, md5(v), p_md5; end if;
  for par in select x from jsonb_array_elements(p_pares) x loop
    n := (length(v) - length(replace(v, par ->> 0, ''))) / length(par ->> 0);
    if n <> 1 then raise exception 'premissa: trecho aparece % vez(es) em %: %', n, p_fn, left(par ->> 0, 120); end if;
    v := replace(v, par ->> 0, par ->> 1);
  end loop;
  execute v;
end $f$;

-- 1. helpers (SECURITY DEFINER: a RLS de negócio/atividade do vendedor não pode esconder o funil do filtro)
create or replace function crm.negocio_oculto(p_id text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if p_id is null or p_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  return coalesce((select not f.ativo from crm.negocio n join crm.funil f on f.id = n.funil_id where n.id = p_id::uuid), false);
end $$;
revoke execute on function crm.negocio_oculto(text) from public, anon;
grant execute on function crm.negocio_oculto(text) to authenticated, service_role;

create or replace function crm.notificacao_oculta(p_gatilho text, p_ref text, p_href text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
begin
  if p_href ~ 'negocio=' then
    return crm.negocio_oculto(substring(p_href from 'negocio=([0-9a-fA-F-]{36})'));
  end if;
  if p_gatilho = 'atividade_vencendo' and p_ref ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return coalesce((select crm.negocio_oculto(a.negocio_id::text) from crm.atividade a where a.id = p_ref::uuid), false);
  end if;
  return false;
end $$;
revoke execute on function crm.notificacao_oculta(text, text, text) from public, anon;
grant execute on function crm.notificacao_oculta(text, text, text) to authenticated, service_role;

-- 2. arquivar (assinatura nova: drop + create) e desarquivar
do $$ begin
  if md5(pg_get_functiondef('public.crm_arquivar_funil(uuid)'::regprocedure)) <> '7e4549c92b87060d247f9248afab9bd1' then
    raise exception 'premissa: crm_arquivar_funil(uuid) mudou';
  end if;
end $$;
drop function public.crm_arquivar_funil(uuid);

create function public.crm_arquivar_funil(p_funil uuid, p_com_abertos boolean default false)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_r jsonb; f crm.funil%rowtype; v_abertos int; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor arquiva funis.'); end if;
  select * into f from crm.funil x where x.id = p_funil and x.ativo for update;
  if not found then return crm.res(false, 'Funil não encontrado.'); end if;
  select count(*) into v_abertos from crm.negocio n where n.funil_id = p_funil and n.status = 'aberto';
  if v_abertos > 0 and not coalesce(p_com_abertos, false) then
    return crm.res(false, format('Funil com %s negócio(s) aberto(s). Confirme para arquivar mesmo assim: eles ficam ocultos até desarquivar.', v_abertos),
                   jsonb_build_object('abertos', v_abertos));
  end if;
  perform set_config('crm.resumo', format('Arquivou o funil %s%s', f.nome,
                     case when v_abertos > 0 then format(' (%s negócio(s) aberto(s) ocultos)', v_abertos) else '' end), true);
  update crm.funil x set ativo = false, arquivado_em = now() where x.id = p_funil;
  return crm.res(true, case when v_abertos > 0
                            then format('Funil arquivado. %s negócio(s) aberto(s) ficaram ocultos; desarquive para trazê-los de volta.', v_abertos)
                            else 'Funil arquivado.' end,
                 jsonb_build_object('ocultos', v_abertos));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke execute on function public.crm_arquivar_funil(uuid, boolean) from public, anon;
grant execute on function public.crm_arquivar_funil(uuid, boolean) to authenticated, service_role;

create or replace function public.crm_desarquivar_funil(p_funil uuid)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_r jsonb; f crm.funil%rowtype; v_abertos int; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor desarquiva funis.'); end if;
  select * into f from crm.funil x where x.id = p_funil and not x.ativo for update;
  if not found then return crm.res(false, 'Funil arquivado não encontrado.'); end if;
  select count(*) into v_abertos from crm.negocio n where n.funil_id = p_funil and n.status = 'aberto';
  perform set_config('crm.resumo', format('Desarquivou o funil %s', f.nome), true);
  update crm.funil x set ativo = true, arquivado_em = null where x.id = p_funil;
  return crm.res(true, format('Funil desarquivado. %s negócio(s) aberto(s) voltaram.', v_abertos), jsonb_build_object('abertos', v_abertos));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;
revoke execute on function public.crm_desarquivar_funil(uuid) from public, anon;
grant execute on function public.crm_desarquivar_funil(uuid) to authenticated, service_role;

-- 3. listas
select pg_temp.remendar('public.crm_negocios(uuid,text,uuid,integer,integer)', '1667fb5648101d0474d2f23df9c25396', jsonb_build_array(
  jsonb_build_array($a$     where (p_funil is null or n.funil_id = p_funil)$a$,
                    $b$     join crm.funil fv on fv.id = n.funil_id and fv.ativo
     where (p_funil is null or n.funil_id = p_funil)$b$)));

select pg_temp.remendar('public.crm_atividades(timestamptz,uuid,integer,integer)', '046f98e9403e51e360a1b4c65cd3e79d', jsonb_build_array(
  jsonb_build_array($a$       and (v_g is null or a.pessoa_id = any(v_g))$a$,
                    $b$       and (v_g is null or a.pessoa_id = any(v_g))
       and not crm.negocio_oculto(a.negocio_id::text)$b$)));

select pg_temp.remendar('public.crm_desempenho(timestamptz,timestamptz)', '85358d13d5009faf64b71c6b9e1994d3', jsonb_build_array(
  jsonb_build_array($a$      from crm.negocio n$a$,
                    $b$      from crm.negocio n
      join crm.funil fv on fv.id = n.funil_id and fv.ativo$b$),
  jsonb_build_array($a$     where (a.concluida_em >= v_desde and a.concluida_em < v_ate) or a.concluida_em is null$a$,
                    $b$     where ((a.concluida_em >= v_desde and a.concluida_em < v_ate) or a.concluida_em is null)
       and not crm.negocio_oculto(a.negocio_id::text)$b$)));

select pg_temp.remendar('public.crm_funil_resumo(uuid)', 'f0cce0462bad2b9a2727f5e2217e9a5a', jsonb_build_array(
  jsonb_build_array($a$    from crm.funil f where f.id = p_funil;$a$,
                    $b$    from crm.funil f where f.id = p_funil and f.ativo;$b$)));

select pg_temp.remendar('public.crm_notificacoes(integer)', '67f7a120e7fe30512a971ab12e5b060e', jsonb_build_array(
  jsonb_build_array($a$     where n.perfil_id = auth.uid()$a$,
                    $b$     where n.perfil_id = auth.uid()
       and not crm.notificacao_oculta(n.gatilho, n.ref_id, n.href)$b$)));

select pg_temp.remendar('public.crm_jornada(uuid,integer)', '0c324cd8730f0492903f0e1601eec9e2', jsonb_build_array(
  jsonb_build_array($a$       from crm.negocio n join crm.funil f on f.id = n.funil_id$a$,
                    $b$       from crm.negocio n join crm.funil f on f.id = n.funil_id and f.ativo$b$),
  jsonb_build_array($a$       join crm.funil f on f.id = n.funil_id
       left join crm.etapa_funil ep$a$,
                    $b$       join crm.funil f on f.id = n.funil_id and f.ativo
       left join crm.etapa_funil ep$b$),
  jsonb_build_array($a$      where a.pessoa_id = any(v_g) and a.concluida_em is not null$a$,
                    $b$      where a.pessoa_id = any(v_g) and a.concluida_em is not null and not crm.negocio_oculto(a.negocio_id::text)$b$),
  jsonb_build_array($a$      where nt.pessoa_id = any(v_g)$a$,
                    $b$      where nt.pessoa_id = any(v_g) and not crm.negocio_oculto(nt.negocio_id::text)$b$)));

select pg_temp.remendar('public.crm_eventos(uuid,timestamptz,integer)', '664dbebd01d7cb7d62dc3ea0d5d3e54e', jsonb_build_array(
  jsonb_build_array($a$      left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'),$a$,
                    $b$      left join crm.etapa_funil ep on l.acao = 'moveu_etapa' and ep.id::text = l.dados->>'etapa_para'
     where not crm.negocio_oculto(case l.entidade when 'negocio' then l.entidade_id
                                                  when 'nota' then nt.negocio_id::text
                                                  when 'atividade' then atv.negocio_id::text end)),$b$)));

select pg_temp.remendar('crm.contatos_metricas(uuid[])', 'e09910f6fddc19319ec0028d3deda43d', jsonb_build_array(
  jsonb_build_array($a$            from g join crm.negocio n on n.pessoa_id = g.membro$a$,
                    $b$            from g join crm.negocio n on n.pessoa_id = g.membro
            join crm.funil fv on fv.id = n.funil_id and fv.ativo$b$),
  jsonb_build_array($a$           join crm.funil f on f.id = n.funil_id$a$,
                    $b$           join crm.funil f on f.id = n.funil_id and f.ativo$b$)));

-- 4. regras (cron, supressão, estratégias, Hotmart)
select pg_temp.remendar('crm.notificar_prazos()', '6a64b7228c3169737aa10489246a7168', jsonb_build_array(
  jsonb_build_array($a$    from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id$a$,
                    $b$    from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id
    join crm.funil fv on fv.id = n.funil_id and fv.ativo$b$),
  jsonb_build_array($a$where a.concluida_em is null and not a.cancelada and a.vence_em > now()$a$,
                    $b$where a.concluida_em is null and not a.cancelada and not crm.negocio_oculto(a.negocio_id::text) and a.vence_em > now()$b$)));

select pg_temp.remendar('crm.supressao_motivo(uuid,text)', '42fc0b47256d02066e89a1bbf09c8c91', jsonb_build_array(
  jsonb_build_array($a$  if exists (select 1 from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id$a$,
                    $b$  if exists (select 1 from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id join crm.funil fv on fv.id = n.funil_id and fv.ativo$b$)));

select pg_temp.remendar('crm.estrategia_candidatos(jsonb)', '1f1361c1f240a851dcb132f0aa56aa27', jsonb_build_array(
  jsonb_build_array($a$from crm.negocio n where v_ex_neg and n.status = 'aberto'$a$,
                    $b$from crm.negocio n join crm.funil fv on fv.id = n.funil_id and fv.ativo where v_ex_neg and n.status = 'aberto'$b$)));

select pg_temp.remendar('crm.hotmart_processar(jsonb)', '9a928a7ae5e5c92a94a31828c01d0395', jsonb_build_array(
  jsonb_build_array($a$      select x.* into n from crm.negocio x join crm.projeto_ativacao pa on pa.funil_id = x.funil_id$a$,
                    $b$      select x.* into n from crm.negocio x join crm.projeto_ativacao pa on pa.funil_id = x.funil_id
        join crm.funil fx on fx.id = x.funil_id and fx.ativo$b$),
  jsonb_build_array($a$           and not exists (select 1 from crm.projeto_ativacao pa where pa.funil_id = x.funil_id)$a$,
                    $b$           and not exists (select 1 from crm.projeto_ativacao pa where pa.funil_id = x.funil_id)
           and exists (select 1 from crm.funil fx where fx.id = x.funil_id and fx.ativo)$b$)));
