-- Reversão da 20261016001200: tira o objetivo CAPTAÇÃO, as fases distribuicao e pre_captacao e os 2 mapeamentos.
-- Se alguém já usou uma fase nova (fase_manual, projeto_fases, modelo_fases, campanhas esperadas), a FK RESTRICT barra e nada é apagado.
-- Depois: delete from supabase_migrations.schema_migrations where version = '20261016001200';
set local lock_timeout = '5s';
set local statement_timeout = '30s';

delete from mkt_trafego.objetivo_fase where (objetivo, fase) in (('CAPTAÇÃO', 'captacao'), ('DISTRIBUIÇÃO', 'distribuicao'));
delete from mkt_trafego.fases where codigo in ('distribuicao', 'pre_captacao');
delete from mkt.campanha_objetivos where codigo = 'CAPTAÇÃO';
