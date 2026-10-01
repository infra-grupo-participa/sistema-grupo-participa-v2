-- Placar de veracidade da base de alunos ativos (12 checagens). Só leitura; rodar após cada rodada de conciliação.
with a as (
  select * from thb_alunos where cancelado_em is null
),
resp as (
  -- maior nível declarado (nunca rebaixar); formulários que não são de nível ficam fora
  select aluno_id, max(array_position(array['iniciante','pessoal','em_formacao','profissional','ouro','platina','diamante','diamante_vermelho'], dados->>'nivel_codigo')) pos
  from respondi.respostas
  where aluno_id is not null and form_slug not in ('E7k0fEnj','bRkxySli','NVcTd1wZ')
    and dados->>'nivel_codigo' in ('iniciante','pessoal','em_formacao','profissional','ouro','platina','diamante','diamante_vermelho')
  group by aluno_id
),
placa as (
  select distinct on (lower(trim(email))) lower(trim(email)) em, nivel
  from thb_placas_solicitacoes where status='concluido' and nivel is not null
  order by lower(trim(email)), coalesce(updated_at, created_at) desc
),
cpf as (
  select id, d from (select id, regexp_replace(coalesce(documento,''),'\D','','g') d from a where tipo_documento='CPF') x
),
cpfok as (
  select id, (length(d)=11 and d !~ '^(\d)\1{10}$' and
    ((select (sum(substr(d,i,1)::int*(11-i))*10)%11%10 from generate_series(1,9) i) = substr(d,10,1)::int) and
    ((select (sum(substr(d,i,1)::int*(12-i))*10)%11%10 from generate_series(1,10) i) = substr(d,11,1)::int)) ok
  from cpf
),
dupdoc as (
  select regexp_replace(documento,'\D','','g') d from a where documento is not null and length(regexp_replace(documento,'\D','','g'))>=11
  group by 1 having count(*)>1
),
nsoc as (select socio_de_aluno_id t, count(*) n from a where socio_de_aluno_id is not null group by 1),
chk as (
  select a.id,
    -- nivel: placa é piso; senão a ficha tem de estar no maior nível declarado ou acima (planilha acima = manter)
    case when p.nivel is not null then coalesce(array_position(array['iniciante','pessoal','em_formacao','profissional','ouro','platina','diamante','diamante_vermelho'], a.nivel_resultado),0)
                                      >= array_position(array['iniciante','pessoal','em_formacao','profissional','ouro','platina','diamante','diamante_vermelho'], p.nivel)
         when r.pos is not null then coalesce(array_position(array['iniciante','pessoal','em_formacao','profissional','ouro','platina','diamante','diamante_vermelho'], a.nivel_resultado),0) >= r.pos
         else null end                                              as c_nivel,
    case when a.tipo_documento='CPF' then c.ok else null end          as c_cpf,
    case when a.documento is null then false
         else regexp_replace(a.documento,'\D','','g') not in (select d from dupdoc) end as c_doc_unico,
    a.telefone_e164 is not null                                       as c_telefone,
    case when a.cep is not null then a.estado is not null else null end as c_uf,
    a.turma_id is not null or a.turma_aurum_id is not null            as c_turma,
    case when a.eh_socio then a.socio_de_aluno_id is not null else null end as c_socio_vinculo,
    case when a.eh_socio and a.socio_de_aluno_id is not null then
      not exists (select 1 from a t where t.id=a.socio_de_aluno_id and t.socio_de_aluno_id=a.id) else null end as c_socio_mutuo,
    case when not a.eh_socio then coalesce(a.num_socios,0) = coalesce(n.n,0) else null end as c_num_socios,
    case when a.valor_pago is not null and a.valor_total is not null then a.valor_pago <= a.valor_total else null end as c_valor,
    case when a.acessos_revogados_em is not null then a.situacao_acesso not in ('em_dia','a_vencer') else null end as c_revogado,
    case when a.situacao_acesso='vencido' then a.data_expiracao < current_date
         when a.situacao_acesso in ('em_dia','a_vencer') and a.data_expiracao is not null then a.data_expiracao >= current_date
         else null end                                                as c_vencimento
  from a
  left join resp r on r.aluno_id=a.id
  left join placa p on p.em=lower(trim(a.email))
  left join cpfok c on c.id=a.id
  left join nsoc n on n.t=a.id
),
u as (
  select chk.id, k, v from chk, lateral (values
   ('nivel',c_nivel),('cpf_valido',c_cpf),('documento_unico',c_doc_unico),('telefone',c_telefone),('uf',c_uf),
   ('turma',c_turma),('socio_vinculo',c_socio_vinculo),('socio_mutuo',c_socio_mutuo),('num_socios',c_num_socios),
   ('valor',c_valor),('revogado',c_revogado),('vencimento',c_vencimento)) t(k,v)
),
-- falha explicada: a ficha tem observação da conciliação para aquela checagem ([conc:<checagem>];
-- acesso×dinheiro explica revogado/vencimento; nível também aceita o texto das rodadas de nível)
ux as (
  select u.k, u.v, a.obs_central ~ ('\[conc:' || u.k || '\]')
      or (u.k in ('revogado','vencimento') and a.obs_central ~ '\[conc:acesso\]')
      or (u.k = 'nivel' and a.obs_central ~ '\[2026-\d\d-\d\d\] (Nível|Sem fonte)[^|]*a confirmar') explicada
  from u join a using (id) where not u.v
)
select json_build_object(
  'ativos',(select count(*) from a),
  'score_pct',(select round(100.0*count(*) filter (where v)/nullif(count(*) filter (where v is not null),0),2) from u),
  'por_check',(select json_object_agg(k, json_build_object('ok',ok,'falha',f,'sem_fonte',s,'pct',round(100.0*ok/nullif(ok+f,0),1))) from
     (select k, count(*) filter (where v) ok, count(*) filter (where not v) f, count(*) filter (where v is null) s from u group by k) z),
  'falhas',(select count(*) from ux),
  'falhas_explicadas',(select count(*) filter (where explicada) from ux),
  'score_com_explicadas_pct',(select round(100.0*(count(*) filter (where v) + (select count(*) filter (where explicada) from ux))/nullif(count(*) filter (where v is not null),0),2) from u),
  'sem_explicacao_por_check',(select json_object_agg(k, n) from (select k, count(*) n from ux where not coalesce(explicada,false) group by k) z),
  'nivel_falha_explicada',(select count(*) from chk join a using(id) where not c_nivel and a.obs_central ~ '\[2026-\d\d-\d\d\] (Nível|Sem fonte)[^|]*a confirmar'),
  'nivel_falha_sem_obs',(select json_agg(chk.id) from chk join a using(id) where not c_nivel and coalesce(a.obs_central,'') !~ '\[2026-\d\d-\d\d\] (Nível|Sem fonte)[^|]*a confirmar'),
  'alunos_100',(select count(*) from chk where coalesce(c_nivel,true) and coalesce(c_cpf,true) and coalesce(c_doc_unico,true) and coalesce(c_telefone,true) and coalesce(c_uf,true) and coalesce(c_turma,true) and coalesce(c_socio_vinculo,true) and coalesce(c_socio_mutuo,true) and coalesce(c_num_socios,true) and coalesce(c_valor,true) and coalesce(c_revogado,true) and coalesce(c_vencimento,true))
);
