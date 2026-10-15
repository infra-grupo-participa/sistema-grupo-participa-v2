-- Reversão da 20261015180000: volta dados_black_leads ao corpo de 15/10 (sem contato.ver).

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
