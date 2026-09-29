-- 20260929z84 — Resolvedor oferta→evento roda sozinho (de hora em hora, às :25)
--
-- Por quê (Marcio, 29/09): o sistema tem que ficar independente de ação humana. A z83 passou na conferência
-- (7/7 acertos nas ligações conhecidas, 0 erro; 12 ligações novas conferidas uma a uma) e o backfill de 120 dias
-- foi gravado com trava (nenhum card por link ou manual mudou; funil ETHB +R$ 2.982 por ingressos agora atribuídos).
-- Horário: :25, depois do sync da Hotmart (:07) e da fila de janelas; o erro que importa acontece no dia do evento.
-- Custo medido: 619 ms por execução (45 dias) -> ~15 s/dia. Sem oferta candidata, sai na hora.
-- Reversão: select cron.unschedule('fin-oferta-evento-resolver');
--           desfazer ligações: delete from fin.evento_ofertas where origem like 'auto:%';

select cron.unschedule(jobid) from cron.job where jobname = 'fin-oferta-evento-resolver';
select cron.schedule('fin-oferta-evento-resolver', '25 * * * *',
  $$select count(*) from fin.resolver_ofertas_eventos(true, 45)$$);
