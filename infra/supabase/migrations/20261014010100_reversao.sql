-- Reversão de 20261014010100: corpo anterior e EXECUTE de volta para anon.
set local lock_timeout = '5s';
set local statement_timeout = '30s';
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure) <> '6f9187d4584427df3e9743008bb39e26' then
    raise exception 'reversão de 20261014010100: corpo vivo não é o desta migration. Reler.';
  end if;
end
$g$;
CREATE OR REPLACE FUNCTION public.black_lista_disparo(p_chave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 20261013172751: chamada pelo Apps Script (projeto do Victor) da planilha "[BLACK FRIDAY/26] LISTA DISPARO LIVE
-- CONSULTORIA 13/10", de hora em hora, com a anon key + p_chave. Sem a chave certa: 42501 e nada sai.
declare
  v_hash text;
  r jsonb;
begin
  select c.chave_sha256 into v_hash from dados.black_lista_config c where c.id;
  if v_hash is null or p_chave is null or length(p_chave) < 32
     or encode(extensions.digest(p_chave, 'sha256'), 'hex') <> v_hash then
    raise exception 'não autorizado' using errcode = '42501';
  end if;
  if exists (select 1 from dados.black_lista_leituras l where l.em > now() - interval '5 minutes') then
    raise exception 'leitura recente: tente de novo em 5 min' using errcode = '54000';
  end if;
  r := dados.black_lista_disparo_montar();
  insert into dados.black_lista_leituras (pessoas, lista, fora_do_padrao)
  values ((r->'resumo'->>'pessoas')::int, (r->'resumo'->>'lista')::int, (r->'resumo'->>'fora_do_padrao')::int);
  return r;
end
$function$;
revoke execute on function public.black_lista_disparo(text) from public, authenticated, service_role;
grant execute on function public.black_lista_disparo(text) to anon;
