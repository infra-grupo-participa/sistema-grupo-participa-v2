-- Reversão de 20261014160400: a view volta à definição da 20261014160200; a tabela sai (com as conferências humanas
-- que tiver: exportar antes se já houver linhas com regra 'conferencia_humana').
set local lock_timeout = '5s';
drop view pessoas.vw_oferta;  -- create or replace não remove a coluna regra_tipo (42P16, pego no ensaio)
create view pessoas.vw_oferta with (security_invoker = true) as
select o.oferta_codigo, o.nome as oferta_nome, o.produto_id, p.nome as produto_nome, p.familia, p.conta,
       hm.categoria as categoria_hm, hm.papel as papel_hm,
       case hm.categoria when 'sinal' then 'sinal' when 'diferenca' then 'saldo' when 'compra_cheia' then 'integral' end as tipo
  from fin.ofertas o
  left join fin.produtos p on p.produto_id = o.produto_id
  left join public.hm_product_catalog hm on hm.offer_code = o.oferta_codigo;
revoke all on pessoas.vw_oferta from public, anon, authenticated, service_role;
drop table if exists pessoas.oferta_tipo;
