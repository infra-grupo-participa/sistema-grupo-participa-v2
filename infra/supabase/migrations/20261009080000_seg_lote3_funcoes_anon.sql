-- Segurança do banco principal — lote 3 (09/10/2026, card ClickUp 17tya50fqb1)
-- Status: APLICADA em 09/10/2026 via apply_migration "seg_lote3_funcoes_anon".
--
-- O que fecha: 21 funções SECURITY DEFINER que anon (sem login) executava, classe C da auditoria do kirad
-- (scratchpad lote3-classificacao-p1/p2): chamadas só com login, só pelo servidor/cron (dono postgres), ou por ninguém.
-- Conferido no catálogo em 09/10: nenhuma é usada em view, policy ou cron.job.
--   11 ficam com authenticated (front logado chama): is_monitor (Central), fn_hm_* / fn_turma_* / gp_can_liberar_hm (v2),
--      is_sip_auth_user / get_effective_user (SIP), garantir_perfil (Rede), resposta_duplicada (Workbook).
--   10 só service_role: 9 rotinas do plantão GPS (cron/edge com segredo) + workbook.registrar_lead (sem chamador).
--
-- NÃO entra (fica para outro passo, decisão/código):
--   classe D — wb_central_* (4), comunidade_cadastrar, cnhf_buscar_por_telefone, cnhf_conferir_email (área de membros CNHF
--   identifica só por e-mail), gps.entrada_pelo_codigo (flag entrada_codigo_ativa=false hoje); cnhf_resultados (confirmar dono).
--   central.criar_token_senha_autoatendimento já foi fechada em 20261009070000.
-- Reversão: 20261009080000_seg_lote3_reversao.sql (restaura do retrato arquivo.acl_retrato_seg_lote3).

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

create table if not exists arquivo.acl_retrato_seg_lote3 (
  objeto text not null, grantee text not null, privilegio text not null,
  gravado_em timestamptz not null default now()
);
revoke all on arquivo.acl_retrato_seg_lote3 from public, anon, authenticated;
insert into arquivo.acl_retrato_seg_lote3 (objeto, grantee, privilegio)
select p.oid::regprocedure::text,
       case when a.grantee = 0 then 'public' else a.grantee::regrole::text end,
       a.privilege_type
from pg_proc p
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
where a.grantee <> p.proowner
  and p.oid in (
      'central.is_monitor()'::regprocedure,
      'public.fn_hm_liberar(uuid, boolean)'::regprocedure,
      'public.fn_hm_ignorar(uuid, text, boolean)'::regprocedure,
      'public.fn_hm_set_turma(uuid, smallint)'::regprocedure,
      'public.fn_turma_criar(text, text, boolean)'::regprocedure,
      'public.fn_turma_set_atual(smallint)'::regprocedure,
      'public.gp_can_liberar_hm()'::regprocedure,
      'public.is_sip_auth_user()'::regprocedure,
      'rede.garantir_perfil()'::regprocedure,
      'sip.get_effective_user(uuid)'::regprocedure,
      'workbook.resposta_duplicada(uuid, text, text)'::regprocedure,
      'gps.plantao_aviso_mentora_pendente(text)'::regprocedure,
      'gps.plantao_email_sala_pendente(text)'::regprocedure,
      'gps.plantao_escrita_liberada()'::regprocedure,
      'gps.plantao_expurgar(text)'::regprocedure,
      'gps.plantao_marcar_aviso_mentora(text, uuid)'::regprocedure,
      'gps.plantao_marcar_email_sala(text, uuid)'::regprocedure,
      'gps.plantao_marcar_nps_enviado(text, uuid)'::regprocedure,
      'gps.plantao_nps_pendente(text, integer)'::regprocedure,
      'gps.plantao_reconciliar_elegibilidade(text)'::regprocedure,
      'workbook.registrar_lead(text, text, text)'::regprocedure);

revoke execute on function
  central.is_monitor(),
  public.fn_hm_liberar(uuid, boolean),
  public.fn_hm_ignorar(uuid, text, boolean),
  public.fn_hm_set_turma(uuid, smallint),
  public.fn_turma_criar(text, text, boolean),
  public.fn_turma_set_atual(smallint),
  public.gp_can_liberar_hm(),
  public.is_sip_auth_user(),
  rede.garantir_perfil(),
  sip.get_effective_user(uuid),
  workbook.resposta_duplicada(uuid, text, text),
  gps.plantao_aviso_mentora_pendente(text),
  gps.plantao_email_sala_pendente(text),
  gps.plantao_escrita_liberada(),
  gps.plantao_expurgar(text),
  gps.plantao_marcar_aviso_mentora(text, uuid),
  gps.plantao_marcar_email_sala(text, uuid),
  gps.plantao_marcar_nps_enviado(text, uuid),
  gps.plantao_nps_pendente(text, integer),
  gps.plantao_reconciliar_elegibilidade(text),
  workbook.registrar_lead(text, text, text)
from public, anon, authenticated;

grant execute on function
  central.is_monitor(),
  public.fn_hm_liberar(uuid, boolean),
  public.fn_hm_ignorar(uuid, text, boolean),
  public.fn_hm_set_turma(uuid, smallint),
  public.fn_turma_criar(text, text, boolean),
  public.fn_turma_set_atual(smallint),
  public.gp_can_liberar_hm(),
  public.is_sip_auth_user(),
  rede.garantir_perfil(),
  sip.get_effective_user(uuid),
  workbook.resposta_duplicada(uuid, text, text)
to authenticated, service_role;

grant execute on function
  gps.plantao_aviso_mentora_pendente(text),
  gps.plantao_email_sala_pendente(text),
  gps.plantao_escrita_liberada(),
  gps.plantao_expurgar(text),
  gps.plantao_marcar_aviso_mentora(text, uuid),
  gps.plantao_marcar_email_sala(text, uuid),
  gps.plantao_marcar_nps_enviado(text, uuid),
  gps.plantao_nps_pendente(text, integer),
  gps.plantao_reconciliar_elegibilidade(text),
  workbook.registrar_lead(text, text, text)
to service_role;

do $pos$
begin
  if exists (select 1 from pg_proc p where p.oid in (
      'central.is_monitor()'::regprocedure,
      'public.fn_hm_liberar(uuid, boolean)'::regprocedure,
      'public.fn_hm_ignorar(uuid, text, boolean)'::regprocedure,
      'public.fn_hm_set_turma(uuid, smallint)'::regprocedure,
      'public.fn_turma_criar(text, text, boolean)'::regprocedure,
      'public.fn_turma_set_atual(smallint)'::regprocedure,
      'public.gp_can_liberar_hm()'::regprocedure,
      'public.is_sip_auth_user()'::regprocedure,
      'rede.garantir_perfil()'::regprocedure,
      'sip.get_effective_user(uuid)'::regprocedure,
      'workbook.resposta_duplicada(uuid, text, text)'::regprocedure,
      'gps.plantao_aviso_mentora_pendente(text)'::regprocedure,
      'gps.plantao_email_sala_pendente(text)'::regprocedure,
      'gps.plantao_escrita_liberada()'::regprocedure,
      'gps.plantao_expurgar(text)'::regprocedure,
      'gps.plantao_marcar_aviso_mentora(text, uuid)'::regprocedure,
      'gps.plantao_marcar_email_sala(text, uuid)'::regprocedure,
      'gps.plantao_marcar_nps_enviado(text, uuid)'::regprocedure,
      'gps.plantao_nps_pendente(text, integer)'::regprocedure,
      'gps.plantao_reconciliar_elegibilidade(text)'::regprocedure,
      'workbook.registrar_lead(text, text, text)'::regprocedure)
      and has_function_privilege('anon', p.oid, 'execute')) then
    raise exception 'seg_lote3: ainda há função executável por anon';
  end if;
end
$pos$;

commit;
