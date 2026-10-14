-- Reversão da 20261014210100: apaga o cadastro da ação black-thb-2026-10 (planilha de mensageria, grupo, sessão, linha de
-- dados.dashboards e o projeto). Para se algum disparo ainda apontar para o projeto: arquivar antes (sem_delete).
do $g$
declare v_proj bigint := (select id from mkt.projetos where etiqueta_clickup = 'black-thb-2026-10');
begin
  if v_proj is null then raise exception 'reversão 20261014210100: projeto não existe; nada a reverter'; end if;
  if exists (select 1 from mkt_mensageria.disparos where projeto_id = v_proj) then
    raise exception 'reversão 20261014210100: há disparos no projeto; revisar antes de apagar';
  end if;
  delete from mkt_mensageria.planilhas where projeto_id = v_proj;
  delete from dados.dashboard_grupos where chave = 'black-thb-2026-10';
  delete from dados.sessoes where chave = 'black-thb-2026-10';
  delete from dados.dashboards where chave = 'black-thb-2026-10';
  delete from mkt.projetos where id = v_proj;
end
$g$;
delete from supabase_migrations.schema_migrations where version = '20261014210100';
