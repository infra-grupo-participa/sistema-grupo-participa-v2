-- 20260927f — Revisão humana da identidade: pares "talvez mesma pessoa" (telefone/nome igual)
-- e documentos bloqueados (compartilhados/escritório). Só leitura; nada é juntado daqui.
create or replace function public.fn_fin_hotmart_identidade()
returns table (tipo text, motivo text, evidencia text, pessoa_a text, emails_a text[], nomes_a text[],
               pessoa_b text, emails_b text[], nomes_b text[], pago_a numeric, pago_b numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with emails as (
    select i.pessoa_chave p, array_agg(distinct substr(i.no, 3)) em from fin.identidade i where i.no like 'e:%' group by 1
  ), nomes as (
    select i.pessoa_chave p, array_agg(distinct t.comprador_nome) nm,
           coalesce(sum(coalesce(t.valor_base, t.valor_cobrado)) filter (where t.status in ('APPROVED','COMPLETE')), 0) pago
      from fin.identidade i join fin.hotmart_transacoes t on 'e:' || lower(trim(t.comprador_email)) = i.no
     group by 1
  )
  select 'sugestao', s.motivo,
         case when s.motivo in ('mesmo_telefone', 'mesmo_documento_tentativa') and not coalesce(public.gp_pode_ver_cpf(), false)
              then '···' || right(s.evidencia, 4) else s.evidencia end,
         fin.chave_opaca(s.pessoa_a), ea.em, na.nm, fin.chave_opaca(s.pessoa_b), eb.em, nb.nm, coalesce(na.pago, 0), coalesce(nb.pago, 0)
    from fin.identidade_sugestao s
    left join emails ea on ea.p = s.pessoa_a left join nomes na on na.p = s.pessoa_a
    left join emails eb on eb.p = s.pessoa_b left join nomes nb on nb.p = s.pessoa_b
  union all
  select 'revisao', r.motivo, case when r.no like 'd:%' then '···' || right(r.no, 4) else r.no end,
         fin.chave_opaca(r.no), null, null, null, null, null, null, null
    from fin.identidade_revisao r
   order by 1, 2;
end $$;
revoke all on function public.fn_fin_hotmart_identidade() from public, anon;
grant execute on function public.fn_fin_hotmart_identidade() to authenticated;
