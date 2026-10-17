-- Reversão das 3 migrations do meta x realizado da Black, na ordem inversa. Não toca em nada que existia antes.
drop function if exists public.dados_black_plano_diario(text);
drop function if exists mkt_trafego.segmento_plano(text, text);
drop table if exists mkt_trafego.plano_diario;   -- apaga também as 161 linhas da carga (o CSV continua no gp-operacoes)
