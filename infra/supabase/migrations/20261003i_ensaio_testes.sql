-- testes do ensaio da 20261003i (rodar após o corpo da migration, dentro do mesmo begin … ZOUT)
create temp table _zi (k text, v text) on commit drop;
grant all on _zi to authenticated;
insert into _zi select 'arquivados', count(*)::text from pg_class c where c.relnamespace = 'arquivo'::regnamespace and obj_description(c.oid,'pg_class') like '20261003i:%';
insert into _zi select 'anon_le_algum', bool_or(has_table_privilege('anon', c.oid, 'select'))::text from pg_class c where c.relnamespace = 'arquivo'::regnamespace;
insert into _zi select 'autor_default', column_default from information_schema.columns where table_name='thb_alunos_audit_log' and column_name='autor';
insert into _zi select 'titular_tem_equipe', (prosrc like '%gp_eh_equipe()%')::text from pg_proc where oid='public.fn_aluno_definir_titular(uuid,uuid)'::regprocedure;
select set_config('z.adm', (select p.id::text from public.perfis p where p.status='ativo' and p.cargo='admin' and p.email ilike '%@advmais.com' order by p.id limit 1), true);
-- nenhum visualizador ativo @advmais hoje: rebaixa outro perfil só dentro do ensaio (rollback)
select set_config('z.vis', (select p.id::text from public.perfis p where p.status='ativo' and p.email ilike '%@advmais.com' and p.id::text <> current_setting('z.adm') order by p.id limit 1), true);
update public.perfis set cargo='visualizador', areas='{}', funcoes='{}' where id = current_setting('z.vis')::uuid;
insert into _zi values ('tem_visualizador', (current_setting('z.vis') <> '')::text);
create temp table _zitem on commit drop as select item, tipo from public.fn_aluno_conciliacao(null,false) where false;
grant all on _zitem to authenticated;
set local role authenticated;
select set_config('request.jwt.claims', json_build_object('sub', current_setting('z.adm'), 'role','authenticated')::text, true);
insert into _zitem select item, tipo from public.fn_aluno_conciliacao(null,false) where tipo in ('comprou_fora_da_base','sip_sem_aluno','revogado_com_vigencia','cadastro_incompleto') ;
insert into _zi select 'adm_ref_'||z.tipo, (select count(*) from public.fn_aluno_conciliacao_ref(z.item))::text from (select distinct on (tipo) item, tipo from _zitem where tipo in ('comprou_fora_da_base','sip_sem_aluno') order by tipo, item) z;
do $m$ declare v_i text; v_id bigint; begin
  select item into v_i from _zitem where tipo not in ('comprou_fora_da_base','sip_sem_aluno','revogado_com_vigencia') limit 1;
  if v_i is null then select item into v_i from _zitem limit 1; end if;
  v_id := public.fn_aluno_conciliacao_marcar(v_i, 'conferido', repeat('x', 600));
  perform set_config('z.did', v_id::text, true);
exception when others then insert into _zi values ('obs_len_erro', sqlstate||' '||sqlerrm); end $m$;
select set_config('request.jwt.claims', json_build_object('sub', nullif(current_setting('z.vis'),''), 'role','authenticated')::text, true);
do $v$ begin
  perform * from public.fn_aluno_conciliacao_ref((select item from _zitem where tipo='comprou_fora_da_base' limit 1));
  insert into _zi values ('vis_ref', 'PASSOU');
exception when others then insert into _zi values ('vis_ref', sqlstate); end $v$;
reset role;
insert into _zi select 'obs_len', length(observacao)::text from public.thb_aluno_conciliacao_decisao where id = nullif(current_setting('z.did', true),'')::bigint;
do $z$ begin raise exception 'ZOUT %', (select json_object_agg(k, v) from _zi); end $z$;
