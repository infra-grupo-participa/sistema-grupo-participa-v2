-- 20261006160401: Pedidos de alteração (etapa 2), a Isabela aprova pela tela de pedidos e o pedido marca "autoaprovado"
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006160401_ensaio.sql (begin … rollback). Notas: 20261006160401.explain.md.
-- Independente das 20261006160402/03/04.
--
-- DECISÃO DO VICTOR (06/10/2026, noite): a Isabela Teixeira APROVA pela tela de pedidos (aba "Aprovar"), sem aviso no
-- Slack. Pode aprovar o próprio pedido; fica registrado quem aprovou e a tela mostra o selo "aprovou o próprio pedido".
-- Ela MANTÉM os acessos que já tem (é admin, vê a Central no sistema e edita a planilha): nada é fechado para ela.
--
-- ESTADO EM PRODUÇÃO: a Isabela JÁ FOI inserida em pa_aprovadores em 06/10/2026 19:08 UTC, por pedido direto do Victor
-- (insert … on conflict do nothing, fora desta migration). Por isso o passo 1 é idempotente e a guarda aceita as duas
-- situações (ela presente ou não).
--
-- O QUE FAZ
--   1. Garante a Isabela (perfil e1d2863d-c975-46bd-b35f-45b1039328e3) em pa_aprovadores (on conflict do nothing: em
--      produção ela já está lá desde 06/10 19:08 UTC). Com isso pa_eh_aprovador(),
--      pa_meu_papel().pode_aprovar, pa_fila, pa_decidir e pa_marcar_aplicado passam a valer para ela (nenhuma função
--      dessas muda). O aviso do Slack (20261006160402) NÃO lê pa_aprovadores: o destinatário é pa_config.slack_destinos.
--   2. pa_linha (portanto pa_fila e pa_meus_pedidos) devolve também `autoaprovado boolean`: true quando o pedido foi
--      aprovado (status aprovado ou aplicado) e decidido_por = solicitado_por. Recusa do próprio pedido não conta.
--      Os demais campos não mudam.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha em pa_aprovadores; pa_linha lê 1 pedido por PK (a fila tem limite de 500, hoje 2 pedidos).
--   índice: nenhum novo; a comparação é na própria linha já lida.
--   frequência: a fila é lida ao abrir a aba; o insert roda uma vez.
--   repetição: o insert é idempotente (on conflict do nothing); rodar de novo para no md5 de pa_linha (que já mudou).
--   reversão: bloco REVERSÃO no fim (só o corpo vivo de pa_linha; a Isabela FICA como aprovadora, decisão do Victor).
--
-- BASE: pa_linha recriada a partir do corpo VIVO (pg_get_functiondef lido em 06/10/2026), conferido pelo md5 na guarda.
-- Quem lê fora do v2: ninguém (grep de pa_pedidos/pa_linha/pa_fila em disparos-thb, controle-de-eventos,
-- departamento-de-marketing, gp-operacoes e dashboard-ht sem ocorrência).

set local lock_timeout = '5s';

-- ═══ 0. Guarda: o banco tem que estar como foi lido em 06/10/2026 ═══
do $guarda$
begin
  if md5(pg_get_functiondef('public.pa_linha(bigint,boolean)'::regprocedure)) <> '24124fa127d6d7ad158148fbc4aa8900' then
    raise exception '20261006160401: corpo vivo de pa_linha mudou desde 06/10/2026 (md5 diferente): reler e regerar';
  end if;
  if not exists (select 1 from public.perfis
                  where id = 'e1d2863d-c975-46bd-b35f-45b1039328e3' and nome = 'Isabela Teixeira' and status = 'ativo') then
    raise exception '20261006160401: perfil da Isabela Teixeira não encontrado ou inativo';
  end if;
end
$guarda$;

-- ═══ 1. Isabela aprova (em produção ela já está; não duplica nem falha) ═══
insert into public.pa_aprovadores (perfil_id) values ('e1d2863d-c975-46bd-b35f-45b1039328e3')
on conflict (perfil_id) do nothing;

-- ═══ 2. pa_linha com `autoaprovado` ═══
CREATE OR REPLACE FUNCTION public.pa_linha(p_id bigint, p_aprovador boolean)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r public.pa_pedidos%rowtype;
  v_doc boolean := public.pa_pode_ver_doc();
  v_agora jsonb;
  v_conflito boolean := false;
  v_sai_vinculado boolean;
begin
  select * into r from public.pa_pedidos where id = p_id;
  if not found then return null; end if;
  if p_aprovador and r.status in ('pendente', 'erro') then
    if r.tipo = 'alterar_dado' and r.aluno_id is not null then
      v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
      v_conflito := v_agora is distinct from r.valor_atual;
    elsif r.tipo = 'trocar_socio' then
      v_sai_vinculado := r.aluno_id is not null and r.socio_sai_id is not null
                         and public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id);
      v_conflito := not v_sai_vinculado;
    end if;
  end if;
  return json_build_object(
    'id', r.id, 'tipo', r.tipo, 'status', r.status,
    'aluno_id', r.aluno_id, 'aluno_nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
    'aluno', case when p_aprovador and r.aluno_id is not null then public.pa_resumo_aluno(r.aluno_id) end,
    'campo', r.campo,
    'de', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, r.valor_atual, v_doc) end,
    'para', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, coalesce(r.valor_aplicado, r.valor_novo), v_doc) end,
    'agora', case when p_aprovador and r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, v_agora, v_doc) end,
    'valor_novo', case when p_aprovador and (r.campo <> 'documento' or v_doc) then r.valor_novo end,
    'conflito', v_conflito,
    'socio_sai_id', r.socio_sai_id, 'socio_sai_nome', r.socio_sai_nome,
    'socio_sai_vinculado', v_sai_vinculado,
    'socio_entra_id', r.socio_entra_id, 'socio_entra_nome', r.socio_entra_nome,
    'socio_entra_novo', case when r.socio_entra_novo is null then null
                             else r.socio_entra_novo || jsonb_build_object('documento',
                                    public.pa_mascara_doc(r.socio_entra_novo ->> 'documento', v_doc)) end,
    'descricao', r.descricao, 'motivo', r.motivo, 'evidencia', r.evidencia,
    'solicitado_em', r.solicitado_em,
    'solicitado_por_nome', (select p.nome from public.perfis p where p.id = r.solicitado_por),
    'decidido_em', r.decidido_em,
    'decidido_por_nome', (select p.nome from public.perfis p where p.id = r.decidido_por),
    'motivo_recusa', r.motivo_recusa, 'conflito_confirmado', r.conflito_confirmado,
    -- 20261006160401: quem decidiu é quem pediu (a Isabela pode aprovar o próprio pedido). Só aprovação conta.
    'autoaprovado', coalesce(r.status in ('aprovado', 'aplicado') and r.decidido_por = r.solicitado_por, false),
    'aplicado_em', r.aplicado_em, 'erro_msg', r.erro_msg,
    'planilha_status', r.planilha_status, 'planilha_em', r.planilha_em, 'planilha_erro', r.planilha_erro,
    'ra_caso_id', r.ra_caso_id,
    'historico', case when p_aprovador then coalesce((
       select json_agg(json_build_object('acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em, h.id)
         from public.pa_historico h left join public.perfis hp on hp.id = h.por
        where h.pedido_id = r.id), '[]'::json) end);
end
$function$;

-- ═══ 3. Conferência: grants iguais aos de antes (create or replace não mexe neles) e campo novo presente ═══
do $confere$
begin
  if has_function_privilege('authenticated', 'public.pa_linha(bigint,boolean)', 'execute')
     or has_function_privilege('anon', 'public.pa_linha(bigint,boolean)', 'execute') then
    raise exception '20261006160401: pa_linha ficou exposta para anon/authenticated';
  end if;
  if position('''autoaprovado''' in pg_get_functiondef('public.pa_linha(bigint,boolean)'::regprocedure)) = 0 then
    raise exception '20261006160401: pa_linha sem o campo autoaprovado';
  end if;
  if (select count(*) from public.pa_aprovadores
       where perfil_id in ('e1d2863d-c975-46bd-b35f-45b1039328e3', '81d2eaee-cce1-4058-8714-439b0fc6f970')) <> 2 then
    raise exception '20261006160401: aprovadores diferentes do esperado (Victor e Isabela)';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- Volta pa_linha ao corpo vivo lido em 06/10/2026: a tela deixa de receber `autoaprovado` (o selo some).
-- A Isabela NÃO sai de pa_aprovadores: ela continua aprovadora (decisão do Victor, 06/10/2026; foi inserida em produção
-- antes desta migration). Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- CREATE OR REPLACE FUNCTION public.pa_linha(p_id bigint, p_aprovador boolean)
--  RETURNS json
--  LANGUAGE plpgsql
--  STABLE SECURITY DEFINER
--  SET search_path TO ''
-- AS $function$
-- declare
--   r public.pa_pedidos%rowtype;
--   v_doc boolean := public.pa_pode_ver_doc();
--   v_agora jsonb;
--   v_conflito boolean := false;
--   v_sai_vinculado boolean;
-- begin
--   select * into r from public.pa_pedidos where id = p_id;
--   if not found then return null; end if;
--   if p_aprovador and r.status in ('pendente', 'erro') then
--     if r.tipo = 'alterar_dado' and r.aluno_id is not null then
--       v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
--       v_conflito := v_agora is distinct from r.valor_atual;
--     elsif r.tipo = 'trocar_socio' then
--       v_sai_vinculado := r.aluno_id is not null and r.socio_sai_id is not null
--                          and public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id);
--       v_conflito := not v_sai_vinculado;
--     end if;
--   end if;
--   return json_build_object(
--     'id', r.id, 'tipo', r.tipo, 'status', r.status,
--     'aluno_id', r.aluno_id, 'aluno_nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
--     'aluno', case when p_aprovador and r.aluno_id is not null then public.pa_resumo_aluno(r.aluno_id) end,
--     'campo', r.campo,
--     'de', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, r.valor_atual, v_doc) end,
--     'para', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, coalesce(r.valor_aplicado, r.valor_novo), v_doc) end,
--     'agora', case when p_aprovador and r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, v_agora, v_doc) end,
--     'valor_novo', case when p_aprovador and (r.campo <> 'documento' or v_doc) then r.valor_novo end,
--     'conflito', v_conflito,
--     'socio_sai_id', r.socio_sai_id, 'socio_sai_nome', r.socio_sai_nome,
--     'socio_sai_vinculado', v_sai_vinculado,
--     'socio_entra_id', r.socio_entra_id, 'socio_entra_nome', r.socio_entra_nome,
--     'socio_entra_novo', case when r.socio_entra_novo is null then null
--                              else r.socio_entra_novo || jsonb_build_object('documento',
--                                     public.pa_mascara_doc(r.socio_entra_novo ->> 'documento', v_doc)) end,
--     'descricao', r.descricao, 'motivo', r.motivo, 'evidencia', r.evidencia,
--     'solicitado_em', r.solicitado_em,
--     'solicitado_por_nome', (select p.nome from public.perfis p where p.id = r.solicitado_por),
--     'decidido_em', r.decidido_em,
--     'decidido_por_nome', (select p.nome from public.perfis p where p.id = r.decidido_por),
--     'motivo_recusa', r.motivo_recusa, 'conflito_confirmado', r.conflito_confirmado,
--     'aplicado_em', r.aplicado_em, 'erro_msg', r.erro_msg,
--     'planilha_status', r.planilha_status, 'planilha_em', r.planilha_em, 'planilha_erro', r.planilha_erro,
--     'ra_caso_id', r.ra_caso_id,
--     'historico', case when p_aprovador then coalesce((
--        select json_agg(json_build_object('acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em, h.id)
--          from public.pa_historico h left join public.perfis hp on hp.id = h.por
--         where h.pedido_id = r.id), '[]'::json) end);
-- end
-- $function$;
