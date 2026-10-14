begin;
create temp table _z_out (em serial, passo text, linha text);
do $a$ declare v text; begin select m.perfil_id::text into v from acesso.master m join public.perfis p on p.id=m.perfil_id where p.status='ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1; perform set_config('request.jwt.claims', json_build_object('sub',v,'role','authenticated')::text, true); end $a$;
insert into pg_temp._z_out(passo, linha) select '1 antes', (select 'periodo_fim ' || periodo_fim from dados.dashboards where chave = 'atm-elaine-1-2026-10') || ' / resumo ' || (select (to_jsonb(r) - 'atualizado_em')::text from public.dados_atm_resumo('atm-elaine-1-2026-10') r);
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

insert into pg_temp._z_out(passo, linha) select '2 depois', (select 'periodo_fim ' || periodo_fim from dados.dashboards where chave = 'atm-elaine-1-2026-10') || ' / resumo ' || (select (to_jsonb(r) - 'atualizado_em')::text from public.dados_atm_resumo('atm-elaine-1-2026-10') r);
update dados.dashboards set periodo_fim = date '2026-10-14' where chave = 'atm-elaine-1-2026-10' and periodo_fim = date '2026-10-15';
insert into pg_temp._z_out(passo, linha) select '3 depois da reversão', (select 'periodo_fim ' || periodo_fim from dados.dashboards where chave = 'atm-elaine-1-2026-10') || ' / resumo ' || (select (to_jsonb(r) - 'atualizado_em')::text from public.dados_atm_resumo('atm-elaine-1-2026-10') r);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
