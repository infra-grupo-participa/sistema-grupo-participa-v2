-- Reversão de 20261017040000: apaga as funções, as views e a tabela de atributos.
-- Nada fora destes objetos depende deles (conferido em 16/10/2026: nenhuma view, função ou job referencia pessoas.atributos, vw_compra ou vw_oferta_a_conferir).
-- A tabela é só cálculo: refazer é rodar a migration e os lotes de novo. Nenhum dado de origem é perdido.
set local lock_timeout = '5s';
set local statement_timeout = '60s';
drop function if exists pessoas.atributos_lote(uuid, integer);
drop function if exists pessoas.atributos_calcular(uuid[]);
drop view if exists pessoas.vw_oferta_a_conferir;
drop view if exists pessoas.vw_compra;
drop table if exists pessoas.atributos;
