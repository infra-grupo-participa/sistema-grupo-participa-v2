begin;
create temp table _z_out (em serial, passo text, linha text);
do $a$ declare v text; begin select m.perfil_id::text into v from acesso.master m join public.perfis p on p.id=m.perfil_id where p.status='ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1; perform set_config('request.jwt.claims', json_build_object('sub',v,'role','authenticated')::text, true); end $a$;
insert into pg_temp._z_out(passo, linha) select '1 antes', (select (to_jsonb(r) - 'atualizado_em')::text from public.dados_atm_resumo('atm-elaine-1-2026-10') r);
-- 20261014140100: desfaz só o vínculo do disparo 45721 (Unnichat, campanha "atm", canal whatsapp_api) ao projeto 75, feito
-- pela 20261014140000. Ele não tem custo em nenhuma fonte; canal pago sem custo deixa `custo_completo = false` em
-- public.dados_atm_resumo, e CPL, CAC e ROAS do ATM somem das telas. Volta quando o custo do Unnichat for conhecido.
-- Reversão: update mkt_mensageria.disparos set projeto_id = 75 where id = 45721 and projeto_id is null and origem = 'api';
do $g$
begin
  if (select count(*) from mkt_mensageria.disparos where id = 45721 and projeto_id = 75 and origem = 'api'
       and canal = 'whatsapp_api' and custo_centavos is null and arquivado_em is null) <> 1 then
    raise exception '20261014140100: o disparo 45721 não está no estado esperado';
  end if;
end
$g$;
update mkt_mensageria.disparos set projeto_id = null where id = 45721 and projeto_id = 75 and origem = 'api';
insert into pg_temp._z_out(passo, linha) select '2 depois', (select (to_jsonb(r) - 'atualizado_em')::text from public.dados_atm_resumo('atm-elaine-1-2026-10') r);
update mkt_mensageria.disparos set projeto_id = 75 where id = 45721 and projeto_id is null and origem = 'api';
insert into pg_temp._z_out(passo, linha) select '3 depois da reversão', (select (to_jsonb(r) - 'atualizado_em')::text from public.dados_atm_resumo('atm-elaine-1-2026-10') r);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
