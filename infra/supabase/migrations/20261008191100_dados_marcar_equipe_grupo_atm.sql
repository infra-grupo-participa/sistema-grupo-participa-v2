-- 20261008191100: marca como "equipe" os números que entraram no grupo do ATM 1 da Elaine em 06/10/2026
--
-- STATUS: ver 20261008191000.explain.md. Depende de 20261008191000.
-- POR QUE: pedido do Victor (08/10/2026): em 06/10 (horário de Brasília) entraram no grupo 'ATM 10/26' 11 eventos de
--   7 números únicos, entre 17:42 e 18:39, todos da equipe (antes de a captação começar em 07/10). Marcar, não apagar:
--   os eventos ficam em crm.evento_jornada e saem das contas do dashboard pela marcação.
-- Quem marcou: não há usuário logado numa migration; marcado_por fica nulo e marcado_por_email registra a origem.
-- PARA VOLTAR: update dados.marcacoes_teste set desmarcado_em = now(), desmarcado_por_email = 'reversão 20261008191100'
--              where chave = 'atm-elaine-1-2026-10' and marcado_por_email = 'migration 20261008191100' and desmarcado_em is null;
-- IDEMPOTENTE: on conflict do nothing (uma marcação ativa por número).

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('dados.marcacoes_teste') is null then
    raise exception 'premissa: 20261008191000 não aplicada';
  end if;
  if (select count(distinct right(j.fone_key, 8)) from crm.evento_jornada j
       where j.fonte = 'sendflow' and j.tag = 'ATM 10/26' and j.tipo = 'entrada' and j.fone_key is not null
         and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06') <> 7 then
    raise exception 'premissa: esperava 7 números em 06/10; conferir antes de marcar';
  end if;
end
$g$;

insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
select distinct 'atm-elaine-1-2026-10', 'fone', right(j.fone_key, 8), 'equipe', null::uuid, 'migration 20261008191100'
  from crm.evento_jornada j
 where j.fonte = 'sendflow' and j.tag = 'ATM 10/26' and j.tipo = 'entrada' and j.fone_key is not null
   and (j.ocorreu_em at time zone 'America/Sao_Paulo')::date = date '2026-10-06'
on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
