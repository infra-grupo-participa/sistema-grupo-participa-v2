-- 20261015180000: dados_black_leads passa a exigir a capacidade contato.ver (pedido do Maestro/Victor, 15/10).
-- Por quê: a RPC devolve nome, e-mail e telefone e só exigia ser da equipe (@advmais ativo). As outras que devolvem
-- contato (dados_black_lista, dados_atm_leads, dados_atm_pre_checkout, dados_atm_sv_vendas) já exigem contato.ver.
-- Efeito: equipe sem contato.ver recebe 42501 ao abrir a tabela de leads da Black; master e quem tem contato.ver seguem iguais.
-- Reversão: 20261015180000_reversao.sql (recria o corpo de antes, md5 do prosrc 1eadf321...).
-- Guarda: aborta se o corpo vivo não for o lido em 15/10.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_leads(text,text[])'::regprocedure) is distinct from '1eadf32102cc43026c67e6143b68113e' then
    raise exception '20261015180000: corpo vivo de dados_black_leads mudou; revisar antes de aplicar';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.dados_black_leads(p_chave text, p_lead_ids text[])
 RETURNS TABLE(lead_id text, nome text, email text, telefone text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.black_evento(p_chave);
begin
  -- 20261015180000: devolve nome, e-mail e telefone; exige contato.ver, como dados_black_lista e dados_atm_leads
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if p_lead_ids is null or cardinality(p_lead_ids) = 0 then return; end if;
  if cardinality(p_lead_ids) > 500 then
    raise exception 'no máximo 500 leads por chamada' using errcode = '22023';
  end if;
  return query
  select l.lead_id, l.nome, l.email, l.whatsapp
    from dados.black_leads l
   where l.lead_id = any (p_lead_ids)
   order by l.criado_em, l.lead_id;
end
$function$;

revoke all on function public.dados_black_leads(text,text[]) from public, anon;
grant execute on function public.dados_black_leads(text,text[]) to authenticated;
