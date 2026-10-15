-- Reversão de 20261015220000 (aba Lives da Black): tira as 5 RPCs, as 7 funções internas e as 5 tabelas.
-- ATENÇÃO: apaga o que foi coletado (minuto, foto, chat, comentário) e o cadastro das lives. Antes, se quiser guardar:
--   copy (select * from dados.black_live_chat) to stdout;  (e as outras tabelas). Nada fora da aba Lives lê estes objetos.
-- Ordem: desligar antes o cron (20261015220100_reversao.sql), senão a Edge chama funções que não existem mais.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists public.dados_black_lives(text);
drop function if exists public.dados_black_live_detalhe(text, text);
drop function if exists public.dados_black_live_importar(text, text, jsonb, boolean);
drop function if exists public.dados_black_live_cadastrar(text, text, text, timestamptz);
drop function if exists public.dados_black_live_remover(text, text);

drop function if exists dados.black_live_gravar_comentarios(text, jsonb);
drop function if exists dados.black_live_gravar_amostra(text, integer, integer, jsonb, text, text);
drop function if exists dados.black_live_atualizar(jsonb);
drop function if exists dados.black_live_alvos();
drop function if exists dados.black_live_pede_chamada();
drop function if exists dados.black_live_na_janela(timestamptz, text);
drop function if exists dados.black_youtube_credenciais();

drop table if exists dados.black_live_comentario;
drop table if exists dados.black_live_chat;
drop table if exists dados.black_live_foto;
drop table if exists dados.black_live_minuto;
drop table if exists dados.black_lives;

do $c$
begin
  if to_regclass('dados.black_lives') is not null
     or exists (select 1 from pg_proc p where p.proname like 'dados_black_live%' or p.proname like 'black_live%') then
    raise exception '20261015220000_reversao: sobrou objeto da aba Lives';
  end if;
end
$c$;
