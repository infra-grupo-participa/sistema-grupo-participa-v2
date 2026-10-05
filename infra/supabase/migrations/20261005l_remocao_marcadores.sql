-- 20261005l: quem pode marcar QUALQUER item da Remoção de Acessos, além do responsável e do triador.
-- Pedido do Victor (05/10/2026): a Isabela Teixeira marca Searchie, Obvio, informes, comunidade etc., como ele.
-- Ela NÃO vira triadora (triagem continua só com ra_config.triador_id). Marcação dela fica como correção
-- (corrigido = true, igual ao triador), com o histórico de quem marcou.

create table if not exists public.ra_marcadores (
  perfil_id uuid primary key references public.perfis(id),
  incluido_em timestamptz not null default now(),
  obs text
);
alter table public.ra_marcadores enable row level security;
revoke all on public.ra_marcadores from anon, authenticated;

insert into public.ra_marcadores (perfil_id, obs)
select id, 'pedido do Victor em 05/10/2026' from public.perfis where lower(email) = 'isabela@advmais.com'
on conflict (perfil_id) do nothing;

create or replace function public.ra_pode_marcar_tudo()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select public.ra_eh_triador() or exists (
    select 1 from public.ra_marcadores m join public.perfis p on p.id = m.perfil_id and p.status = 'ativo'
    where m.perfil_id = (select auth.uid()));
$$;
revoke all on function public.ra_pode_marcar_tudo() from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.ra_marcar_item(p_item uuid, p_situacao text, p_obs text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item public.ra_itens%rowtype;
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
  v_triador boolean := public.ra_pode_marcar_tudo();  -- 20261005l: triador ou ra_marcadores
  v_pendentes int;
begin
  if not public.ra_pode_ver() then
    return json_build_object('ok', false, 'msg', 'Sem acesso ao módulo Remoção de Acessos.');
  end if;
  if p_situacao not in ('pendente', 'feito', 'nao_se_aplica') then
    return json_build_object('ok', false, 'msg', 'Situação inválida.');
  end if;
  select * into v_item from public.ra_itens where id = p_item for update;
  if not found then return json_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
  if not (v_item.responsavel_id = v_uid or v_triador) then
    return json_build_object('ok', false, 'msg', 'Este item é de outro responsável.');
  end if;
  select * into v_caso from public.ra_casos where id = v_item.caso_id for update;
  if v_caso.status not in ('em_remocao', 'ajustando_acesso', 'concluido') then
    return json_build_object('ok', false, 'msg', 'Este caso ainda não passou pela triagem.');
  end if;

  update public.ra_itens
     set situacao = p_situacao,
         marcado_por = case when p_situacao = 'pendente' then null else v_uid end,
         marcado_em = case when p_situacao = 'pendente' then null else now() end,
         corrigido = (v_item.responsavel_id is distinct from v_uid),
         obs = nullif(trim(coalesce(p_obs, '')), '')
   where id = p_item;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (v_item.caso_id, 'item', v_uid, jsonb_build_object(
    'item', v_item.item, 'pessoa_id', v_item.pessoa_id, 'situacao', p_situacao,
    'correcao', v_item.responsavel_id is distinct from v_uid, 'obs', p_obs));

  select count(*) into v_pendentes from public.ra_itens where caso_id = v_item.caso_id and situacao = 'pendente';
  if v_pendentes = 0 and v_caso.status in ('em_remocao', 'ajustando_acesso') then
    update public.ra_casos set status = 'concluido', concluido_em = now() where id = v_item.caso_id;
    insert into public.ra_historico (caso_id, acao, por) values (v_item.caso_id, 'concluido', v_uid);
  elsif v_pendentes > 0 and v_caso.status = 'concluido' then
    update public.ra_casos
       set status = case when v_caso.decisao = 'manter' then 'ajustando_acesso' else 'em_remocao' end,
           concluido_em = null
     where id = v_item.caso_id;
    insert into public.ra_historico (caso_id, acao, por) values (v_item.caso_id, 'reaberto', v_uid);
  end if;
  return json_build_object('ok', true, 'msg', 'Registrado.');
end $function$;

CREATE OR REPLACE FUNCTION public.ra_caso(p_caso uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := (select auth.uid()); v_doc boolean; v_triador boolean;
begin
  if not public.ra_pode_ver() then return null; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  v_triador := public.ra_eh_triador();
  return (
    select json_build_object(
      'caso', (select to_json(y) from (
                 select c.id, c.tipo, c.status, c.nome, c.email, c.telefone,
                        public.mask_sensivel(c.documento, v_doc) as documento,
                        c.produto_nome, c.oferta_codigo, c.valor, c.hotmart_transaction,
                        c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.sugestao,
                        c.decisao_obs, c.triado_em, tp.nome as triado_por_nome, c.aluno_id, c.teste, c.origem, c.decisao,
                        c.expiracao_atual, c.expiracao_antiga, c.instrucao_atual, c.instrucao_antiga
                   from public.ra_casos c left join public.perfis tp on tp.id = c.triado_por
                  where c.id = p_caso) y),
      'pessoas', coalesce((select json_agg(json_build_object(
                    'id', p.id, 'nome', p.nome, 'email', p.email, 'papel', p.papel, 'aluno_id', p.aluno_id,
                    'itens', coalesce((select json_agg(json_build_object(
                                'id', i.id, 'item', i.item, 'rotulo', k.rotulo, 'situacao', i.situacao,
                                'responsavel', rp.nome, 'marcado_por', mp.nome, 'marcado_em', i.marcado_em,
                                'corrigido', i.corrigido, 'obs', i.obs,
                                'pode_marcar', (i.responsavel_id = v_uid or public.ra_pode_marcar_tudo())) order by k.ordem)
                              from public.ra_itens i
                              join public.ra_itens_catalogo k on k.item = i.item
                              left join public.perfis rp on rp.id = i.responsavel_id
                              left join public.perfis mp on mp.id = i.marcado_por
                             where i.pessoa_id = p.id), '[]'::json)) order by p.ordem)
                  from public.ra_pessoas p where p.caso_id = p_caso), '[]'::json),
      'historico', coalesce((select json_agg(json_build_object(
                      'acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em)
                    from public.ra_historico h left join public.perfis hp on hp.id = h.por
                   where h.caso_id = p_caso), '[]'::json),
      'pode_triar', v_triador
    )
  );
end $function$;

do $c$ begin
  if (select count(*) from public.ra_marcadores m join public.perfis p on p.id = m.perfil_id
       where lower(p.email) = 'isabela@advmais.com') <> 1 then
    raise exception 'Isabela não entrou em ra_marcadores';
  end if;
  if has_table_privilege('authenticated', 'public.ra_marcadores', 'select') then
    raise exception 'ra_marcadores nasceu aberta';
  end if;
end $c$;
