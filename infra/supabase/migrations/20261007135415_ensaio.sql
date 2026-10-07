-- Ensaio da 20261007135415_crm_ativacao_padrao (ex-20261007e, funil de Ativação padrão). Transação DESFEITA: nada persiste.
-- Como rodar: este arquivo inteiro numa chamada (MCP execute_sql). Para ver o relatório pelo MCP, troque o
-- "select … from _r; rollback;" do fim pelo bloco "raise exception" comentado logo abaixo dele (aborta = desfaz tudo).
--
-- ESPERADO: toda linha de _r com ok = true. Cenário (decisões do Arthur de 07/10 incluídas):
--   0. horário de crm.config.expediente + crm.feriado (sábado tarde e feriado 12/10 → terça 8h; domingo; sex 21h → sáb 9h).
--   1. contratos mínimos: projeto_do_evento = null, mql_do_evento = false.
--   2. gestor cria projeto: Ativação 1º funil; salva datas (fallback do CRM) e fechamento do carrinho; carrinho antes do
--      evento é recusado; fim da Ativação = carrinho; vendedor não configura. 2b. mkt.projetos (mesma chave) vence o CRM.
--   3. catalogação simulada só aqui (tag AC, produto de ingresso, formulário; MQL pela tag de MQL).
--   4. inscrição AC pelo caminho real: pessoa criada, dono pela distribuição VIVA, toque 1 no expediente, toque 2 sexta 10h,
--      3 toques 3, notificação lead novo, MQL só pela regra. 5. não duplica. 6. ingresso Hotmart não vira ganho.
--   6b. Respondi: quem não existe vira contato e entra. 7. troca de dono leva os toques. 8. D6 no painel.
--   9. compra da oferta = Comprou, mesmo dono, toques encerrados. 10. cron só encerra depois do fechamento do carrinho:
--      perdidos evento_sem_compra, fila com o mesmo dono, ganho intacto; entrada depois do fechamento recusada.
--  11. permissões.
-- RESULTADO FINAL (07/10/2026 13:50 UTC, produção, arquivo final da migration + este cenário, transação abortada no fim):
--   37/37 ok. Depois: crm.projeto_ativacao e crm.feriado não existiam, crm.config sem ativacao_ligada/expediente,
--   0 pessoas 'ensaio.ativacao%', 0 respostas do Respondi de ensaio, 0 mkt.projetos ENSATV99, 0 job do cron,
--   md5 de hotmart_processar igual (26c950bf…). Em seguida: uma apply_migration (versão 20261007135415).
--   Rodadas anteriores (desenho de 07/10 manhã): 28/30 → corrigido o toque aberto depois do ganho (zz_ativacao_fim).
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';

-- >>> MIGRATION (colada aqui na execução; o arquivo é o 20261007135415_crm_ativacao_padrao.sql) <<<

create temp table _r (n serial, k text, ok boolean, info text) on commit drop;

-- prep (postgres): ligar a ativação (a distribuição geral é a viva)
update crm.config set ativacao_ligada = true, escrita_ligada = true;

-- 0. horário (decisão 1): 2026-10-10 é sábado; 2026-10-12 é feriado (segunda)
insert into _r (k, ok, info) select '0 sáb 14h → ter 8h (seg 12/10 é feriado)', crm.ativacao_expediente('2026-10-10 14:00-03') = '2026-10-13 08:00-03', crm.ativacao_expediente('2026-10-10 14:00-03')::text;
insert into _r (k, ok, info) select '0 feriado 10h → ter 8h', crm.ativacao_expediente('2026-10-12 10:00-03') = '2026-10-13 08:00-03', null;
insert into _r (k, ok, info) select '0 dom 18/10 → seg 8h', crm.ativacao_expediente('2026-10-18 10:00-03') = '2026-10-19 08:00-03', null;
insert into _r (k, ok, info) select '0 ter 7h → ter 8h', crm.ativacao_expediente('2026-10-13 07:00-03') = '2026-10-13 08:00-03', null;
insert into _r (k, ok, info) select '0 qua 10h = agora', crm.ativacao_expediente('2026-10-14 10:00-03') = '2026-10-14 10:00-03', null;
insert into _r (k, ok, info) select '0 sex 21h → sáb 9h', crm.ativacao_expediente('2026-10-16 21:00-03') = '2026-10-17 09:00-03', null;

-- 1. contratos mínimos
insert into _r (k, ok, info) select '1 projeto_do_evento = null e mql_do_evento = false',
  crm.projeto_do_evento('activecampaign', '{"tag":"x"}') is null and crm.mql_do_evento('activecampaign', '{"tag":"PB MQL"}') = false, null;

-- 2. gestor cria o projeto; datas no CRM (fallback); carrinho fecha 2 dias depois do fim
select set_config('ens.ini', (date_trunc('week', now() at time zone 'America/Sao_Paulo')::date + 14)::text, true);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
select set_config('ens.proj', public.crm_criar_projeto('lancamento_classico', 'Ensaio Ativacao 07out', 'b6c39c9f-01d3-4092-8c1a-ce04da73e2d0', 'ht')::text, true);
select set_config('ens.salvar', public.crm_ativacao_salvar(jsonb_build_object('projeto', 'ensaio-ativacao-07out', 'eventoInicio', current_setting('ens.ini'),
  'eventoFim', (current_setting('ens.ini')::date + 2)::text, 'eventoHora', '19:00', 'carrinhoFim', (current_setting('ens.ini')::date + 4)::text,
  'hotmartOferta', jsonb_build_array('5064314'), 'ligado', true))::text, true);
select set_config('ens.carr_ruim', public.crm_ativacao_salvar(jsonb_build_object('projeto', 'ensaio-ativacao-07out', 'eventoInicio', current_setting('ens.ini'),
  'eventoFim', current_setting('ens.ini'), 'carrinhoFim', (current_setting('ens.ini')::date - 1)::text, 'ligado', true))::text, true);
select set_config('request.jwt.claims', '{"sub":"9d347183-5395-434e-9e96-2a65dde1a3cd","role":"authenticated"}', true);
select set_config('ens.vend_salvar', public.crm_ativacao_salvar('{"projeto":"ensaio-ativacao-07out"}')::text, true);
reset role;
select set_config('request.jwt.claims', '', true);
insert into _r (k, ok, info) select '2 projeto criado (4 funis, Ativação 1º)', (current_setting('ens.proj')::jsonb ->> 'ok')::boolean
  and jsonb_array_length(current_setting('ens.proj')::jsonb -> 'funilIds') = 4
  and (select pa.funil_id = (current_setting('ens.proj')::jsonb -> 'funilIds' ->> 0)::uuid from crm.projeto_ativacao pa where pa.projeto = 'ensaio-ativacao-07out'),
  (select string_agg(f.nome, ' | ' order by f.nome) from crm.funil f where f.projeto = 'ensaio-ativacao-07out');
insert into _r (k, ok, info) select '2 etapas (6, SLA 5/15, ganho último)', (select count(*) = 6 and bool_and(case when e.ordem = 0 then e.sla_atencao_min = 5 and e.sla_critico_min = 15 and e.papel = 'primeiro_contato' when e.ordem = 5 then e.papel = 'fechado' else true end)
  from crm.etapa_funil e join crm.projeto_ativacao pa on pa.funil_id = e.funil_id where pa.projeto = 'ensaio-ativacao-07out'), null;
insert into _r (k, ok, info) select '2 salvar data/carrinho/oferta', (current_setting('ens.salvar')::jsonb ->> 'ok')::boolean, current_setting('ens.salvar');
insert into _r (k, ok, info) select '2 carrinho antes do evento recusado', not (current_setting('ens.carr_ruim')::jsonb ->> 'ok')::boolean, current_setting('ens.carr_ruim')::jsonb ->> 'msg';
insert into _r (k, ok, info) select '2 fim da ativação = carrinho', (select d.fim_ativacao = current_setting('ens.ini')::date + 4 and not d.do_marketing from crm.ativacao_datas('ensaio-ativacao-07out') d), null;
insert into _r (k, ok, info) select '11 vendedor não configura', not (current_setting('ens.vend_salvar')::jsonb ->> 'ok')::boolean, current_setting('ens.vend_salvar')::jsonb ->> 'msg';

-- 2b. mkt.projetos vence o CRM (decisão 12): projeto do Marketing com a mesma chave e evento 1 semana depois
insert into mkt.projetos (sigla, nome, linha, etiqueta_clickup, ativo, evento_inicio, evento_fim)
values ('ENSATV99', 'Ensaio Ativacao', 'Holding Total', 'ensaio-ativacao-07out', true, current_setting('ens.ini')::date + 7, current_setting('ens.ini')::date + 8);
insert into _r (k, ok, info) select '2b datas do Marketing vencem o CRM (carrinho do CRM fica)',
  (select d.do_marketing and d.inicio = current_setting('ens.ini')::date + 7 and d.fim_ativacao = current_setting('ens.ini')::date + 4
     from crm.ativacao_datas('ensaio-ativacao-07out') d), (select row_to_json(d)::text from crm.ativacao_datas('ensaio-ativacao-07out') d);
delete from mkt.projetos where sigla = 'ENSATV99' and etiqueta_clickup = 'ensaio-ativacao-07out';

-- 3. catalogação simulada (só no ensaio): tag do AC, produto de ingresso, formulário do Respondi; MQL pela tag
create or replace function crm.projeto_do_evento(p_fonte text, p_dados jsonb) returns text
language sql stable set search_path = '' as $f$
  select case when p_fonte = 'activecampaign' and p_dados ->> 'tag' in ('ENSAIO ATIVACAO', 'ENSAIO MQL') then 'ensaio-ativacao-07out'
              when p_fonte = 'hotmart' and p_dados ->> 'produtoId' = '1560865' then 'ensaio-ativacao-07out'
              when p_fonte = 'respondi' and p_dados ->> 'formSlug' = 'HFaSnLRf' then 'ensaio-ativacao-07out' end;
$f$;
create or replace function crm.mql_do_evento(p_fonte text, p_dados jsonb) returns boolean
language sql stable set search_path = '' as $f$ select p_fonte = 'activecampaign' and p_dados ->> 'tag' = 'ENSAIO MQL'; $f$;

-- 4. inscrição pelo caminho real do webhook do AC
with e as (insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, nome, tag)
           values ('activecampaign', 'ens-ativ-1', 'contact_tag_added', now(), 'ensaio.ativacao.1@exemplo.invalid', 'Ensaio Ativacao Um', 'ENSAIO ATIVACAO') returning id)
select set_config('ens.ev1', crm.anexar_integracao(e.id, '+55 11 98888-0001'), true) from e;
with e as (insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, nome, tag)
           values ('activecampaign', 'ens-ativ-2', 'contact_tag_added', now(), 'ensaio.ativacao.2@exemplo.invalid', 'Ensaio Ativacao Dois', 'ENSAIO MQL') returning id)
select set_config('ens.ev2', crm.anexar_integracao(e.id, '+55 11 98888-0002'), true) from e;
create temp view _neg as
  select n.*, x.email from (values ('ensaio.ativacao.1@exemplo.invalid'), ('ensaio.ativacao.2@exemplo.invalid'), ('ensaio.ativacao.3@exemplo.invalid'), ('ensaio.ativacao.4@exemplo.invalid')) x(email)
    join crm.negocio n on n.pessoa_id = any(pessoas.grupo(crm.pessoa_por_email(x.email)))
    join crm.projeto_ativacao pa on pa.funil_id = n.funil_id and pa.projeto = 'ensaio-ativacao-07out';
insert into _r (k, ok, info) select '4 AC: pessoa criada, negócio com dono (Marcos: único vendedor ativo da distribuição)',
  current_setting('ens.ev1') = 'pessoa_criada' and (select count(*) = 2 and bool_and(dono_id = '9d347183-5395-434e-9e96-2a65dde1a3cd' and status = 'aberto') from _neg),
  (select string_agg(email || ':' || crm.nome_perfil(dono_id) || '/' || (select e.nome from crm.etapa_funil e where e.id = etapa_id), ', ') from _neg);
insert into _r (k, ok, info) select '4 toque 1 = crm.ativacao_expediente(now()) para o dono', (select count(*) = 1 and bool_and(a.tipo = 'whatsapp' and a.dono_id = n.dono_id and a.vence_em = crm.ativacao_expediente(now()))
  from _neg n join crm.atividade a on a.negocio_id = n.id and a.titulo like 'Toque 1:%' where n.email like '%.1@%'),
  (select a.vence_em::text || ' agora=' || now()::text from _neg n join crm.atividade a on a.negocio_id = n.id and a.titulo like 'Toque 1:%' where n.email like '%.1@%');
insert into _r (k, ok, info) select '4 toque 2 sexta anterior 10h', (select a.vence_em = ((current_setting('ens.ini')::date - 3) + time '10:00') at time zone 'America/Sao_Paulo' and a.tipo = 'ligacao'
  from _neg n join crm.atividade a on a.negocio_id = n.id and a.titulo like 'Toque 2:%' where n.email like '%.1@%'), null;
insert into _r (k, ok, info) select '4 toque 3 x3, 18h', (select count(*) = 3 and bool_and(extract(hour from a.vence_em at time zone 'America/Sao_Paulo') = 18)
  from _neg n join crm.atividade a on a.negocio_id = n.id and a.titulo like 'Toque 3 ·%' where n.email like '%.1@%'), null;
insert into _r (k, ok, info) select '4 notificação lead novo na hora', exists (select 1 from _neg n join crm.notificacao x on x.ref_id = n.id::text and x.gatilho = 'lead_novo' and x.perfil_id = n.dono_id where n.email like '%.1@%'), null;
insert into _r (k, ok, info) select '4 MQL pela regra da catalogação (só a tag de MQL)',
  (select bool_and(e.mql = (e.ref = 'ej-' || (select id from crm.evento_jornada where fonte_evento_id = 'ens-ativ-2'))) from crm.ativacao_entrada e where e.projeto = 'ensaio-ativacao-07out'), null;

-- 5. não duplica
with e as (insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, nome, tag)
           values ('activecampaign', 'ens-ativ-1b', 'contact_tag_added', now(), 'ensaio.ativacao.1@exemplo.invalid', 'Ensaio Ativacao Um', 'ENSAIO ATIVACAO') returning id)
select set_config('ens.ev1b', crm.anexar_integracao(e.id, null), true) from e;
insert into _r (k, ok, info) select '5 2º evento ja_tinha, 1 negócio', (select count(*) = 1 from _neg where email like '%.1@%')
  and (select e.resultado = 'ja_tinha' from crm.ativacao_entrada e where e.projeto = 'ensaio-ativacao-07out' order by e.id desc limit 1), null;
insert into _r (k, ok, info) select '5 mesmo ref = duplicado', crm.ativacao_entrar('ensaio-ativacao-07out', crm.pessoa_por_email('ensaio.ativacao.1@exemplo.invalid'), 'activecampaign',
  (select e.ref from crm.ativacao_entrada e where e.projeto = 'ensaio-ativacao-07out' order by e.id limit 1), false, 'x') = 'duplicado', null;

-- 6. ingresso pela Hotmart (pessoa 3)
select set_config('ens.hm3', crm.hotmart_processar(jsonb_build_object('chave', 'ens-ativ-hm-3', 'ref', 'ens-ativ-hm-3', 'fonte', 'sync', 'conta', 'academy', 'classe', 'aprovada', 'transacao', 'HPENSAIOATIV3',
  'quando', now(), 'email', 'ensaio.ativacao.3@exemplo.invalid', 'nome', 'Ensaio Ativacao Tres', 'produto_id', '1560865', 'valor', 297, 'recorrencia', 1)), true);
insert into _r (k, ok, info) select '6 ingresso → ativação aberta, não ganho', (select count(*) = 1 and bool_and(status = 'aberto' and transacao_ganho is null) from _neg where email like '%.3@%'), current_setting('ens.hm3');

-- 6b. Respondi (decisão 8): quem não existe vira contato e entra
insert into respondi.respostas (uuid, form_slug, respondido_em, email, telefone, dados, respostas, importado_em)
values (gen_random_uuid(), 'HFaSnLRf', now(), 'ensaio.ativacao.4@exemplo.invalid', '5511988880004', '{"nome":"Ensaio Ativacao Quatro"}', '[]', now());
insert into _r (k, ok, info) select '6b Respondi: contato novo + ativação com toque 1',
  crm.pessoa_por_email('ensaio.ativacao.4@exemplo.invalid') is not null
  and exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = crm.pessoa_por_email('ensaio.ativacao.4@exemplo.invalid'))
  and (select count(*) = 1 from _neg n join crm.atividade a on a.negocio_id = n.id and a.titulo like 'Toque 1:%' where n.email like '%.4@%'),
  (select string_agg(email || ':' || status, ', ') from _neg where email like '%.4@%');

-- 7. troca de dono leva os toques (pessoa 3 → Ronan, só para provar o trigger)
update crm.negocio n set dono_id = 'db6e59ea-bb47-4d92-a169-a08ee4c30260' where n.id = (select id from _neg where email like '%.3@%');
insert into _r (k, ok, info) select '7 toques seguem o novo dono', (select bool_and(a.dono_id = n.dono_id) and count(*) = 5
  from _neg n join crm.atividade a on a.negocio_id = n.id and a.concluida_em is null where n.email like '%.3@%' group by n.dono_id), null;

-- 8. D6: painel do vendedor Marcos × gestor
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"9d347183-5395-434e-9e96-2a65dde1a3cd","role":"authenticated"}', true);
select set_config('ens.painel_v', public.crm_ativacao_painel()::text, true);
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
select set_config('ens.painel_g', public.crm_ativacao_painel()::text, true);
reset role;
select set_config('request.jwt.claims', '', true);
insert into _r (k, ok, info) select '8 D6 vendedor só os dele',
  (select sum(v::text::int) from jsonb_path_query(current_setting('ens.painel_v')::jsonb, '$.projetos[*] ? (@.projeto == "ensaio-ativacao-07out").porEtapa.*') v)
    = (select count(*) from _neg where dono_id = '9d347183-5395-434e-9e96-2a65dde1a3cd' and status = 'aberto')
  and (select bool_and(x ->> 'vendedorId' = '9d347183-5395-434e-9e96-2a65dde1a3cd') from jsonb_array_elements(current_setting('ens.painel_v')::jsonb -> 'carga') x),
  (current_setting('ens.painel_v')::jsonb -> 'carga')::text;
insert into _r (k, ok, info) select '8 gestor vê os 4, com carrinho e fim', (select sum(v::text::int) from jsonb_path_query(current_setting('ens.painel_g')::jsonb, '$.projetos[*] ? (@.projeto == "ensaio-ativacao-07out").porEtapa.*') v) = 4
  and (select (x ->> 'fimAtivacao')::date = current_setting('ens.ini')::date + 4 from jsonb_array_elements(current_setting('ens.painel_g')::jsonb -> 'projetos') x where x ->> 'projeto' = 'ensaio-ativacao-07out'),
  'total=' || (current_setting('ens.painel_g')::jsonb ->> 'totalNovasHoje');

-- 9. "Comprou": pessoa 1 compra a oferta (HM 5064314)
select set_config('ens.dono1', (select dono_id::text from _neg where email like '%.1@%'), true);
select set_config('ens.hm1', crm.hotmart_processar(jsonb_build_object('chave', 'ens-ativ-hm-1', 'ref', 'ens-ativ-hm-1', 'fonte', 'sync', 'conta', 'academy', 'classe', 'aprovada', 'transacao', 'HPENSAIOATIV1',
  'quando', now(), 'email', 'ensaio.ativacao.1@exemplo.invalid', 'nome', 'Ensaio Ativacao Um', 'produto_id', '5064314', 'valor', 30000, 'recorrencia', 1)), true);
insert into _r (k, ok, info) select '9 oferta = ganho na ativação, mesmo dono, toques encerrados', (select status = 'ganho' and transacao_ganho = 'HPENSAIOATIV1' and dono_id::text = current_setting('ens.dono1')
  and (select e.nome = 'Comprou' from crm.etapa_funil e where e.id = etapa_id)
  and not exists (select 1 from crm.atividade a where a.negocio_id = _neg.id and a.concluida_em is null) from _neg where email like '%.1@%'), current_setting('ens.hm1');

-- 10. saída: cron antes do carrinho fechar não encerra; com o carrinho fechado ontem, encerra
insert into _r (k, ok, info) select '10 cron antes do fechamento não encerra', crm.ativacao_encerrar_vencidos() = 0, null;
update crm.projeto_ativacao set evento_inicio = current_date - 5, evento_fim = current_date - 3, carrinho_fim = current_date - 1 where projeto = 'ensaio-ativacao-07out';
insert into _r (k, ok, info) select '10 carrinho fechado: entrada nova recusada',
  crm.ativacao_entrar('ensaio-ativacao-07out', crm.pessoa_por_email('ensaio.ativacao.1@exemplo.invalid'), 'manual', 'x-tarde', false, 'x') = 'carrinho_fechou', null;
insert into _r (k, ok, info) select '10 cron encerra 1 projeto', crm.ativacao_encerrar_vencidos() >= 1, null;
insert into _r (k, ok, info) select '10 perdido evento_sem_compra', (select count(*) = 3 and bool_and(status = 'perdido' and motivo_perda = 'evento_sem_compra') from _neg where email not like '%.1@%'), null;
insert into _r (k, ok, info) select '10 fila de recuperação com o MESMO dono', (select count(*) = 3 and bool_and(fi.responsavel_id = n.dono_id and fi.status = 'a_abordar')
  from _neg n join crm.projeto_ativacao pa on pa.projeto = 'ensaio-ativacao-07out' join crm.fila_item fi on fi.fila_id = pa.fila_id and fi.pessoa_id = n.pessoa_id where n.email not like '%.1@%'),
  (select f.nome from crm.fila f join crm.projeto_ativacao pa on pa.fila_id = f.id where pa.projeto = 'ensaio-ativacao-07out');
insert into _r (k, ok, info) select '10 ganho intacto, nenhum toque aberto', (select status = 'ganho' from _neg where email like '%.1@%')
  and not exists (select 1 from _neg n join crm.atividade a on a.negocio_id = n.id where a.concluida_em is null), null;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
select set_config('ens.enc2', public.crm_ativacao_encerrar('ensaio-ativacao-07out')::text, true);
reset role;
select set_config('request.jwt.claims', '', true);
insert into _r (k, ok, info) select '10 encerrar de novo recusa', not (current_setting('ens.enc2')::jsonb ->> 'ok')::boolean, current_setting('ens.enc2')::jsonb ->> 'msg';

-- 11. permissões
insert into _r (k, ok, info) select '11 anon sem execute; internas fechadas',
  not has_function_privilege('anon', 'public.crm_ativacao_painel()', 'execute') and not has_function_privilege('anon', 'public.crm_ativacao_salvar(jsonb)', 'execute')
  and not has_function_privilege('authenticated', 'crm.ativacao_entrar(text,uuid,text,text,boolean,text)', 'execute')
  and not has_function_privilege('authenticated', 'crm.mql_do_evento(text,jsonb)', 'execute')
  and not has_table_privilege('authenticated', 'crm.feriado', 'select'), null;

select n, k, ok, info from _r order by n;
-- (MCP) em vez do select acima:
-- do $x$ begin raise exception E'RELATORIO\n%', (select string_agg(format('%s %s | %s', case when ok then 'ok' else 'ERRADO' end, k, coalesce(info, '')), E'\n' order by n) from _r); end $x$;
rollback;
-- Depois: crm.projeto_ativacao não existe; 0 pessoas 'ensaio.ativacao%'; 0 job 'crm-ativacao-encerrar'.
