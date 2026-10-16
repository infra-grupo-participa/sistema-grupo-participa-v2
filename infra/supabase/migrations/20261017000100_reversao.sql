-- Reversão de 20261017000100: volta policies e funções aos corpos lidos em 16/10/2026 (antes da migration) e tira
-- crm.funis_ve_todos(), crm.pessoas_funis_ve_todos() e a tabela crm.vendedor_funil_aberto.
-- Para só TIRAR alguém de um funil, sem desfazer o desenho:
--   delete from crm.vendedor_funil_aberto where perfil_id = '<perfil>' and funil_id = '<funil>';
begin;
set local statement_timeout = '60s';

alter policy negocio_ler on crm.negocio using ((( SELECT crm.eh_gestor() AS eh_gestor) OR (( SELECT crm.eh_vendedor() AS eh_vendedor) AND ((dono_id = ( SELECT auth.uid() AS uid)) OR (dono_id IS NULL)))));
alter policy pessoa_comercial_ler on crm.pessoa_comercial using ((( SELECT crm.eh_gestor() AS eh_gestor) OR (( SELECT crm.eh_vendedor() AS eh_vendedor) AND ((dono_id = ( SELECT auth.uid() AS uid)) OR (dono_id IS NULL) OR (pessoa_id IN ( SELECT crm.pessoas_negocio_meu() AS pessoas_negocio_meu))))));

CREATE OR REPLACE FUNCTION public.crm_transferir_dono(p_negocio uuid, p_dono uuid, p_motivo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_r jsonb; n crm.negocio%rowtype; v_nome text; v_de text; v_para text; v_pc uuid; a record;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Troca de dono só pelo gestor do Comercial.'); end if;
  if btrim(coalesce(p_motivo, '')) = '' then return crm.res(false, 'Escreva o motivo da troca.'); end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
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

CREATE OR REPLACE FUNCTION crm.contatos_visiveis(p_ids uuid[])
 RETURNS TABLE(r_pessoa uuid, r_atual uuid, r_completo boolean, r_criado timestamp with time zone)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_meus uuid[];
begin
  if not coalesce(crm.eh_comercial(), false) then return; end if;
  v_meus := case when v_gestor then '{}'::uuid[] else array(select crm.pessoas_negocio_meu()) end;
  return query
  select pc0.pessoa_id, a.atual,
         coalesce(v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id = any(v_meus), false),
         pc0.criado_em
    from crm.pessoa_comercial pc0
    join pessoas.pessoas pp on pp.id = pc0.pessoa_id
   cross join lateral (select case when pp.mesclada_em is null then pp.id else pessoas.atual(pp.id) end atual) a
   where (p_ids is null or pc0.pessoa_id = any(p_ids))
     and (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id = any(v_meus)
          or (pc0.dono_id is null
              and (p_ids is not null
                   or exists (select 1 from crm.negocio n
                               where n.pessoa_id in (pc0.pessoa_id, a.atual)
                                 and (n.status = 'aberto' or n.dono_id is null)))))
     and (pp.situacao <> 'mesclada'
          or not exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = a.atual));
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_contatos(p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_leitor boolean := coalesce(crm.eh_leitor(), false);  -- 20261008lt: leitor vê tudo, e-mail/telefone mascarados
  v_lim int := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_t text := nullif(btrim(coalesce(p_busca, '')), '');
  v_email text; v_fk text; v_like text; v_ids uuid[];
  v jsonb;
begin
  perform crm.exige_comercial();
  if v_t is not null then
    if length(v_t) < 3 then return jsonb_build_object('itens', '[]'::jsonb, 'temMais', false); end if;
    v_email := pessoas.norm_email(v_t);
    v_fk := pessoas.chave_telefone(v_t);
    v_like := case when v_email is null and v_fk is null
                   then '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
    -- candidatos por índice (mesmas expressões da F0), depois o grupo de cada um
    v_ids := array(
      select distinct pessoas.atual(s.x) from (
        select i.pessoa_id x from pessoas.identificadores i where v_email is not null and i.tipo = 'email' and i.chave = v_email
        union select i.pessoa_id from pessoas.identificadores i where v_fk is not null and i.tipo = 'telefone' and i.chave = v_fk
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_email is not null and lower(btrim(a.email)) = v_email and a.email is not null and a.email <> ''
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_email is not null and lower(btrim((c.email)::text)) = v_email
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_fk is not null and controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = v_fk and a.cancelado_em is null
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_fk is not null and controle.fone_key((c.telefone)::text) = v_fk and c.telefone is not null
        union (select p.id from pessoas.pessoas p where v_like is not null and p.nome is not null and p.nome ilike v_like limit 200)
        union (select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
                where v_like is not null and a.nome ilike v_like limit 200)
      ) s);
    v_ids := array(select g from unnest(v_ids) u, unnest(pessoas.grupo(u)) g);
  end if;

  select coalesce(jsonb_agg(x.j order by x.criado_em desc, x.pid), '[]'::jsonb) into v from (
    select pc.criado_em, pc.pessoa_id pid, jsonb_build_object(
             'id', atu.id, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when pc.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when pc.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(al.cidade, cp.endereco_cidade::text),
             'uf', case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em) j
      from (select pc0.*, ((v_gestor and not v_leitor) or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())) completo
              from crm.pessoa_comercial pc0
              join pessoas.pessoas pp on pp.id = pc0.pessoa_id
             where (v_ids is null or pc0.pessoa_id = any(v_ids))
               and (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())
                    -- 20261006191824: sem dono só entra na LISTA do vendedor se tiver negócio aberto (ou negócio sem dono,
                    -- que o vendedor já vê no funil). Na BUSCA (p_busca) continua valendo todo sem dono, como antes.
                    or (pc0.dono_id is null
                        and (v_ids is not null
                             or exists (select 1 from crm.negocio n
                                         where n.pessoa_id in (pc0.pessoa_id, pessoas.atual(pc0.pessoa_id))
                                           and (n.status = 'aberto' or n.dono_id is null)))))
               and (pp.situacao <> 'mesclada'   -- alias: vale a linha da pessoa atual, se ela tiver camada comercial
                    or not exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = pessoas.atual(pc0.pessoa_id)))
             order by pc0.criado_em desc, pc0.pessoa_id
             limit v_lim + 1 offset v_off) pc
      cross join lateral (select pessoas.atual(pc.pessoa_id) id) atu
      cross join lateral pessoas.dados(atu.id) d
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id) x;
  return jsonb_build_object('itens', coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v) with ordinality t(e, o) where o <= v_lim), '[]'::jsonb),
                            'temMais', jsonb_array_length(v) > v_lim);
end
$function$;

CREATE OR REPLACE FUNCTION crm.contatos_metricas(p_ids uuid[])
 RETURNS TABLE(m_id uuid, m_qtd_abertos integer, m_abertos jsonb, m_lancamentos integer, m_ultima timestamp with time zone)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_ac boolean; v_sf boolean; v_rs boolean; v_un boolean;
begin
  if not coalesce(crm.eh_comercial(), false) then return; end if;
  select coalesce(c.activecampaign_ligado, false), coalesce(c.sendflow_ligado, false), coalesce(c.respondi_ligado, false),
         coalesce(c.unnichat_ligado, false)
    into v_ac, v_sf, v_rs, v_un from crm.config c;
  v_ac := coalesce(v_ac, false); v_sf := coalesce(v_sf, false); v_rs := coalesce(v_rs, false); v_un := coalesce(v_un, false);
  return query
  with ids as (select distinct x from unnest(p_ids) x where x is not null),
  g as (select gl.raiz, gl.membro from crm.grupo_lote(array(select ids.x from ids)) gl),
  neg as (select g.raiz, n.id, n.linha, n.status, n.criado_em, n.ultima_interacao_em, n.funil_id, n.etapa_id
            from g join crm.negocio n on n.pessoa_id = g.membro
            join crm.funil fv on fv.id = n.funil_id and fv.ativo
           where v_gestor or n.dono_id = v_eu or n.dono_id is null),
  ab as (select neg.raiz, count(*)::int qtd,
                jsonb_agg(jsonb_build_object('id', neg.id, 'produto', neg.linha, 'etapaNome', e.nome)
                          order by neg.criado_em desc, neg.id) j
           from neg join crm.etapa_funil e on e.id = neg.etapa_id
          where neg.status = 'aberto'
          group by neg.raiz),
  lg as (select g.raiz, l.em, f.projeto
           from g
           join crm.log l on l.pessoa_id = g.membro
           join crm.negocio n on n.id::text = l.entidade_id
           join crm.funil f on f.id = n.funil_id and f.ativo
          where l.entidade = 'negocio' and l.acao in ('moveu_etapa', 'marcou_ganho', 'marcou_perdido', 'trocou_dono')
            and (v_gestor or n.dono_id = v_eu or n.dono_id is null)),
  la as (select g.raiz, lower(pr.sigla) k
           from g join pessoas.origens o on o.pessoa_id = g.membro join mkt.projetos pr on pr.id = o.projeto_id
         union
         select g.raiz, lower(pr.sigla)
           from g join pessoas.eventos ev on ev.pessoa_id = g.membro and ev.tipo in ('mql', 'nao_mql')
           join mkt.projetos pr on pr.id = ev.projeto_id
         union
         select neg.raiz, f.projeto from neg join crm.funil f on f.id = neg.funil_id
         union
         select lg.raiz, lg.projeto from lg),
  lc as (select la.raiz, count(*)::int qtd from la where la.k is not null and la.k <> '' group by la.raiz),
  ul as (select s.raiz, max(s.em) em from (
           select g.raiz, o.quando em from g join pessoas.origens o on o.pessoa_id = g.membro
           union all
           select g.raiz, ev.quando from g join pessoas.eventos ev on ev.pessoa_id = g.membro
            where ev.tipo in ('mql', 'nao_mql', 'compra', 'checkout', 'reembolso')
           union all
           select g.raiz, ie.ocorreu_em from g join crm.evento_jornada ie on ie.pessoa_id = g.membro
            where (ie.fonte = 'activecampaign' and v_ac) or (ie.fonte = 'sendflow' and v_sf)
               or (ie.fonte = 'unnichat' and v_un) or (ie.fonte = 'respondi' and v_rs)
           union all
           select neg.raiz, neg.criado_em from neg
           union all
           select neg.raiz, neg.ultima_interacao_em from neg
           union all
           select lg.raiz, lg.em from lg
           union all
           select g.raiz, a.concluida_em from g join crm.atividade a on a.pessoa_id = g.membro
            where a.concluida_em is not null and (v_gestor or a.dono_id = v_eu)
           union all
           select g.raiz, nt.em from g join crm.nota nt on nt.pessoa_id = g.membro
         ) s group by s.raiz)
  select ids.x, coalesce(ab.qtd, 0), coalesce(ab.j, '[]'::jsonb), coalesce(lc.qtd, 0), ul.em
    from ids
    left join ab on ab.raiz = ids.x
    left join lc on lc.raiz = ids.x
    left join ul on ul.raiz = ids.x;
end
$function$;

CREATE OR REPLACE FUNCTION public.crm_sessao()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_l boolean := coalesce(crm.eh_leitor(), false); v_g boolean := coalesce(crm.eh_gestor(), false);
        v_v boolean := coalesce(crm.eh_vendedor(), false);
begin
  if not (v_g or v_v) then raise exception 'Sem acesso ao Comercial.' using errcode = '42501'; end if;
  -- 20261008lt: leitor = admin/dev fora do Comercial, só leitura
  return jsonb_build_object('vendedorId', auth.uid(),
                            'papel', case when v_l then 'leitor' when v_g then 'gestor' else 'vendedor' end);
end
$function$;


CREATE OR REPLACE FUNCTION crm.pode_ver_pessoa(p_pessoa uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_g uuid[];
begin
  if p_pessoa is null or v_eu is null then return false; end if;
  if coalesce(crm.eh_gestor(), false) then return true; end if;
  if not coalesce(crm.eh_vendedor(), false) then return false; end if;
  v_g := pessoas.grupo(pessoas.atual(p_pessoa));
  return coalesce(
       exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and (pc.dono_id = v_eu or pc.dono_id is null))
    or exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.dono_id = v_eu), false);
end
$$;

drop function crm.pessoas_funis_ve_todos();
drop function crm.funis_ve_todos();
drop table crm.vendedor_funil_aberto;
delete from supabase_migrations.schema_migrations where version = '20261017000100';
commit;
