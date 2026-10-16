-- Reversão de 20261016240000 (cópia da aba Relatório da planilha Dados [MIAMI 2026]): tira a função da tela, as funções
-- internas, a tabela da cópia e o segredo do Vault. A planilha NÃO é tocada. Se o cron 20261016240100 está aplicado, rodar antes
-- 20261016240100_reversao.sql (senão o cron chama uma Edge que não encontra mais as funções e o vigia abre incidente).
-- A cópia (conteúdo da aba) se perde, mas é refeita da planilha em 5 minutos se a migration voltar.
-- Desligar sem reverter (kill-switch): update dados.relatorio_planilha set ativa = false;
set local lock_timeout = '5s';
set local statement_timeout = '60s';

drop function if exists public.dados_miami_relatorio(text, text);
drop function if exists dados.relatorio_planilha_gravar(text, jsonb, text);
drop function if exists dados.relatorio_planilha_config();
drop function if exists dados.relatorio_planilha_chave();
drop table if exists dados.relatorio_planilha;
delete from vault.secrets where name = 'dados_relatorio_planilha_chave';

do $c$
begin
  if to_regclass('dados.relatorio_planilha') is not null
     or to_regprocedure('public.dados_miami_relatorio(text,text)') is not null
     or to_regprocedure('dados.relatorio_planilha_gravar(text,jsonb,text)') is not null
     or to_regprocedure('dados.relatorio_planilha_config()') is not null
     or to_regprocedure('dados.relatorio_planilha_chave()') is not null
     or exists (select 1 from vault.secrets where name = 'dados_relatorio_planilha_chave') then
    raise exception 'reversão de 20261016240000 incompleta';
  end if;
end
$c$;
