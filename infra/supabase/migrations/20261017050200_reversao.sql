-- Reversão da 20261017050200: devolve o corpo de dados.atm_pertence lido do banco vivo em 16/10/2026 (md5 do corpo 7945be0a410031528e24bd21a4c876ca).
-- A ACL não muda (create or replace a preserva).
create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008191000; número da foto do grupo em 20261008200000
  select case p_tipo
    when 'email' then
         exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$function$;
delete from supabase_migrations.schema_migrations where version = '20261017050200';
