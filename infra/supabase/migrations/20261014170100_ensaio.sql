begin;
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '1 antes', 'projeto 4 ativos ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 4 and arquivado_em is null) || ' / dos 12 no projeto 4: ' || (select count(*) from mkt_mensageria.disparos where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092) and projeto_id = 4) || ' / custo projeto 4: ' || coalesce((select sum(custo_centavos)::text from mkt_mensageria.disparos where projeto_id = 4 and arquivado_em is null), 'nulo');
-- 20261014170100: os 12 disparos de grupo da Black de 08/10 ("BF26 - Live 03/11 - Advogados/Contadores/Outros", 4 cada),
-- que chegaram antes da regra da 20261014150000, vão para o projeto 4 (BF26). Aprovado pelo Victor (via Maestro, 14/10).
-- Reversão: update mkt_mensageria.disparos set projeto_id = null where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092) and projeto_id = 4 and origem = 'api';
do $g$
begin
  if (select count(*) from mkt_mensageria.disparos where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092)
       and projeto_id is null and origem = 'api' and origem_sistema = 'sendflow' and canal = 'grupo' and arquivado_em is null
       and campanha in ('BF26 - Live 03/11 - Advogados', 'BF26 - Live 03/11 - Contadores', 'BF26 - Live 03/11 - Outros')) <> 12 then
    raise exception '20261014170100: os 12 disparos não estão no estado esperado';
  end if;
end
$g$;
update mkt_mensageria.disparos set projeto_id = 4
 where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092) and projeto_id is null and origem = 'api' and origem_sistema = 'sendflow';

insert into pg_temp._z_out(passo, linha) select '2 depois', 'projeto 4 ativos ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 4 and arquivado_em is null) || ' / dos 12 no projeto 4: ' || (select count(*) from mkt_mensageria.disparos where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092) and projeto_id = 4) || ' / custo projeto 4: ' || coalesce((select sum(custo_centavos)::text from mkt_mensageria.disparos where projeto_id = 4 and arquivado_em is null), 'nulo');
update mkt_mensageria.disparos set projeto_id = null where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092) and projeto_id = 4 and origem = 'api';
insert into pg_temp._z_out(passo, linha) select '3 depois da reversão', 'projeto 4 ativos ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 4 and arquivado_em is null) || ' / dos 12 no projeto 4: ' || (select count(*) from mkt_mensageria.disparos where id in (38978,38979,38980,38981,38982,38983,39083,39084,39087,39088,39091,39092) and projeto_id = 4) || ' / custo projeto 4: ' || coalesce((select sum(custo_centavos)::text from mkt_mensageria.disparos where projeto_id = 4 and arquivado_em is null), 'nulo');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
