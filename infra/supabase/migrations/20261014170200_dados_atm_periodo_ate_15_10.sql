-- 20261014170200: dashboard do ATM 1 (atm-elaine-1-2026-10) passa a ir até 15/10/2026 (quinta), ordem do Victor de 14/10
-- ("estende o periodo do dash ate quinta"). As RPCs do ATM leem periodo_fim de dados.dashboards a cada chamada.
-- Reversão: update dados.dashboards set periodo_fim = date '2026-10-14' where chave = 'atm-elaine-1-2026-10' and periodo_fim = date '2026-10-15';
do $g$
begin
  if (select count(*) from dados.dashboards where chave = 'atm-elaine-1-2026-10' and periodo_fim = date '2026-10-14') <> 1 then
    raise exception '20261014170200: periodo_fim do ATM não é 14/10; revisar';
  end if;
end
$g$;
update dados.dashboards set periodo_fim = date '2026-10-15'
 where chave = 'atm-elaine-1-2026-10' and periodo_fim = date '2026-10-14';
