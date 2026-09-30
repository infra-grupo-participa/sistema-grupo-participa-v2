-- 20261003j — Fecha 2 vazamentos achados na reauditoria da 20261003i (30/09/2026)
--
-- POR QUÊ
--   1) central.auth_bkp_joao_20260803: cópia de auth.users (1 linha, COM hash de senha e tokens de recuperação),
--      sem RLS, SELECT para authenticated = qualquer login dos 7 sistemas (aluno do GPS inclusive). A varredura da i
--      mediu só anon; esta pega authenticated.
--   2) public.kpi_* (10 views, security_invoker=false, dono postgres): anon e authenticated com SELECT/INSERT/UPDATE/
--      DELETE/TRUNCATE. Como a view roda com o dono, anon lia nome/e-mail da equipe (kpi_pessoa) e podia ESCREVER no
--      schema kpi passando por cima do RLS.
--
-- QUEM USA (edge_logs, 24 h até 30/09 21:14): 100% das chamadas às kpi_* com role service_role (GET/POST/PATCH).
--   Zero anon, zero authenticated. service_role não perde nada. Nenhum arquivo local cita kpi_pessoa.
--
-- AS 5 PERGUNTAS
--   escala/índice/frequência/repetição: só grant e set schema, sem query nova. reversão: ver fim do arquivo.

begin;

-- 1) cópia de auth.users → arquivo (mesmo padrão da 20261003i)
do $$
begin
  if to_regclass('central.auth_bkp_joao_20260803') is null then
    raise exception '20261003j: central.auth_bkp_joao_20260803 não existe';
  end if;
  if exists (select 1 from pg_depend where refobjid = 'central.auth_bkp_joao_20260803'::regclass and deptype = 'n') then
    raise exception '20261003j: central.auth_bkp_joao_20260803 tem dependente';
  end if;
end $$;

alter table central.auth_bkp_joao_20260803 set schema arquivo;
revoke all on arquivo.auth_bkp_joao_20260803 from public, anon, authenticated;
comment on table arquivo.auth_bkp_joao_20260803 is '20261003j: movida de central (cópia de auth.users legível por authenticated).';

-- 2) views kpi_*: só service_role (e o dono) continuam
revoke all on public.kpi_acesso, public.kpi_area, public.kpi_fechamento_trafego, public.kpi_kpi_periodo,
              public.kpi_medicao_tarefa, public.kpi_periodo, public.kpi_pessoa, public.kpi_pessoa_area,
              public.kpi_regra, public.kpi_retrato
  from public, anon, authenticated;

commit;

-- REVERSÃO
--   alter table arquivo.auth_bkp_joao_20260803 set schema central;  (não devolver grant: era vazamento)
--   grant select on public.kpi_<view> to authenticated;  -- só se aparecer consumidor logado legítimo
