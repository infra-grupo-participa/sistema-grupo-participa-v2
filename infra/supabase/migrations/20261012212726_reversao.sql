-- Reversão de 20261012212726. Numa transação.
-- ANTES, nesta ordem:
--   1. Desligar a flag: update mkt_trafego.coleta_config set valor = null where chave = 'meta_anuncio_contas';
--      (com a flag nula a Edge trafego-meta não chama nenhuma função daqui; a coleta por campanha segue igual).
--   2. Se a Edge com anuncios.ts estiver publicada, publicar a versão anterior da trafego-meta (ou deixar a flag nula:
--      a versão nova com a flag nula não toca nada desta migration).
--   3. Esvaziar o bucket trafego-miniaturas pela Storage API ou pelo painel do Supabase (Storage > trafego-miniaturas >
--      selecionar tudo > Delete). NÃO VERIFICADO se o Supabase deste projeto bloqueia delete direto em storage.objects
--      e storage.buckets (há projetos com o gatilho storage.protect_delete). Se o último comando abaixo falhar por isso,
--      apagar o bucket pela Storage API (DELETE /storage/v1/bucket/trafego-miniaturas, com o bucket vazio).
-- O QUE SE PERDE: o cadastro de conjuntos e anúncios e o desempenho por anúncio (o por campanha, em desempenho_dia, fica).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists mkt_trafego.etapa_black(text);
drop function if exists public.trafego_anuncio_miniatura_receber(jsonb);
drop function if exists public.trafego_desempenho_anuncio_receber(jsonb);
drop function if exists public.trafego_anuncios_receber(jsonb);
drop function if exists public.trafego_conjuntos_receber(jsonb);
drop table if exists mkt_trafego.desempenho_anuncio_dia;
drop table if exists mkt_trafego.anuncios;
drop table if exists mkt_trafego.conjuntos;
delete from mkt_trafego.coleta_config where chave = 'meta_anuncio_contas';

-- por último: só com o bucket vazio (passo 3 acima)
delete from storage.buckets where id = 'trafego-miniaturas';
