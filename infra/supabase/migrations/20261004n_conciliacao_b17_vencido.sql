-- 20261004n — b17de93b: expirou 24/09/2026 sem renovação. A guarda da 20261004m (pagamento depois de
-- expiração - 11 meses) pegou as parcelas HM do próprio ciclo (out e dez/2025), não renovação; último HM é 13/12/2025.
do $$
declare k int;
begin
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, f.campo, f.antes, f.novo, 'conc_vencimento:certo'
    from public.thb_alunos a
   cross join lateral (values ('situacao_acesso', a.situacao_acesso, 'vencido', a.situacao_acesso in ('a_vencer', 'em_dia')),
                              ('status_acesso', a.status_acesso, 'vencido', a.status_acesso in ('vigente', 'renovado')),
                              ('status_acesso_central', a.status_acesso_central, 'Vencido', a.status_acesso_central = 'Ativo')) f(campo, antes, novo, troca)
   where a.id::text like 'b17de93b%' and a.cancelado_em is null and a.data_expiracao = date '2026-09-24' and f.troca;
  update public.thb_alunos a
     set situacao_acesso = 'vencido',
         status_acesso = case when a.status_acesso in ('vigente', 'renovado') then 'vencido' else a.status_acesso end,
         status_acesso_central = case when a.status_acesso_central = 'Ativo' then 'Vencido' else a.status_acesso_central end,
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:vencimento] expirou 24/09/2026; último pagamento HM 13/12/2025 (parcela do ciclo), sem renovação: vencido (decisão do João)')
   where a.id::text like 'b17de93b%' and a.cancelado_em is null and a.data_expiracao = date '2026-09-24'
     and a.situacao_acesso in ('a_vencer', 'em_dia');
  get diagnostics k = row_count;
  if k <> 1 then raise exception 'b17de93b: esperado 1, veio %', k; end if;
end $$;
