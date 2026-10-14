-- 20261014010100: public.black_lista_disparo deixa de ser executável por anon; comentário velho corrigido
--
-- POR QUE (auditoria pelo guia do JP, itens 5, 6 e 14):
--  5. DEFINER executável por anon que devolve nome, e-mail e telefone com uma chave. A chave nunca foi configurada
--     (dados.black_lista_config.chave_sha256 nulo) e dados.black_lista_leituras tem 0 linhas: o Apps Script da planilha
--     nunca foi ligado. Guia 6.6: "em função nova, o padrão é fechar".
--  6. dados.black_lista_disparo_montar repete a regra de dados.black_base_pessoas. O único chamador é esta função; com o anon
--     fechado, ela fica desligada (não apagada), como manda o guia (10: desligar, não apagar). As listas da Mensageria usam
--     dados.black_base_pessoas e não mudam.
--  14. O comentário citava 20261013172751 (o número antes de renomear para 20261013174100).
-- O QUE FAZ: recria a função a partir do corpo vivo mudando só os comentários; revoke de anon (e de public e
--   authenticated, que já não tinham). Nenhuma lógica muda.
-- AS 5 PERGUNTAS: escala = nenhuma; índice = não se aplica; frequência = 0 chamadas hoje; repetição = nenhuma;
--   reversão = 20261014010100_reversao.sql (corpo e grant a anon de volta).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure) <> '0af314f38997fd59db0646313dc653fb' then
    raise exception '20261014010100: corpo vivo de black_lista_disparo mudou. Reler.';
  end if;
  if (select count(*) from dados.black_lista_leituras) <> 0 then
    raise exception '20261014010100: a lista já foi lida pelo Apps Script; não fechar sem falar com o Victor.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.black_lista_disparo(p_chave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 20261013174100 (o arquivo saiu com 20261013172751 no comentário antes de renomear): chamada pelo Apps Script da planilha "[BLACK FRIDAY/26] LISTA DISPARO LIVE
-- CONSULTORIA 13/10", de hora em hora, com a anon key + p_chave. Sem a chave certa: 42501 e nada sai.
-- 20261014010100: DESLIGADA para anon (auditoria pelo guia do JP, item 5). O Apps Script nunca foi ligado (chave nunca
-- configurada, 0 leituras). Para religar: grant execute a anon numa migration nova, com o ok do Victor e do pentester.
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

revoke execute on function public.black_lista_disparo(text) from public, anon, authenticated, service_role;
