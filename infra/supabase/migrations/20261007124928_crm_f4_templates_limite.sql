-- F4 do CRM — sincronização de templates do WhatsApp: teto de 500 → 2.000 por chamada (07/10/2026).
-- Medido no 1º GET (só leitura) de /whatsapp/2/senders/5521987545211/templates: 567 templates (565 APPROVED, 2 REJECTED),
-- 1 WABA, sem paginação. Com o teto de 500 da F4, 67 ficariam de fora — e, nas sincronizações seguintes, seriam
-- marcados ativo=false. Única mudança: `o <= 500` → `o <= 2000`. Corpo partiu do vigente (pg_get_functiondef);
-- mesma assinatura (create or replace preserva o ACL: sem grant para anon/authenticated/service_role).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $guarda$
begin
  if position('where o <= 500 loop' in pg_get_functiondef('crm.whatsapp_templates_sincronizar(text,jsonb)'::regprocedure)) = 0 then
    raise exception 'crm.whatsapp_templates_sincronizar mudou desde a F4: reler o corpo vivo';
  end if;
end
$guarda$;

CREATE OR REPLACE FUNCTION crm.whatsapp_templates_sincronizar(p_numero text, p_lista jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n crm.numero_whatsapp%rowtype; t jsonb; v_ini timestamptz := clock_timestamp(); v_texto text; v_cat text; k int := 0; v_inat int;
begin
  select * into n from crm.numero_whatsapp x where x.numero = pessoas.so_digitos(p_numero);
  if not found then return jsonb_build_object('ok', false, 'msg', 'Número não cadastrado.'); end if;
  if jsonb_typeof(p_lista) is distinct from 'array' then return jsonb_build_object('ok', false, 'msg', 'Lista inválida.'); end if;
  for t in select x from jsonb_array_elements(p_lista) with ordinality y(x, o) where o <= 2000 loop
    v_texto := left(coalesce(t -> 'structure' -> 'body' ->> 'text', t -> 'body' ->> 'text', t ->> 'body'), 4096);
    v_cat := lower(t ->> 'category');
    continue when coalesce(t ->> 'name', '') = '' or coalesce(v_texto, '') = '' or coalesce(v_cat, '') not in ('marketing', 'utility', 'authentication');
    insert into crm.template (numero_id, nome_provedor, idioma, categoria, texto, variaveis, aprovado, status_provedor, ativo, sincronizado_em)
    values (n.id, left(t ->> 'name', 512), coalesce(nullif(t ->> 'language', ''), 'pt_BR'), v_cat, v_texto,
            coalesce((select max((mm[1])::int) from regexp_matches(v_texto, '\{\{([0-9]+)\}\}', 'g') mm), 0),
            upper(coalesce(t ->> 'status', '')) = 'APPROVED', left(upper(t ->> 'status'), 40), true, clock_timestamp())
    on conflict (numero_id, nome_provedor, idioma) do update
       set categoria = excluded.categoria, texto = excluded.texto, variaveis = excluded.variaveis, aprovado = excluded.aprovado,
           status_provedor = excluded.status_provedor, ativo = true, sincronizado_em = excluded.sincronizado_em;
    k := k + 1;
  end loop;
  update crm.template x set ativo = false where x.numero_id = n.id and x.ativo and x.sincronizado_em < v_ini;
  get diagnostics v_inat = row_count;
  return jsonb_build_object('ok', true, 'sincronizados', k, 'inativados', v_inat);
end
$function$;
