-- Ensaio de 20261014010000, 010100, 010200 e 010300 em sequência (transação desfeita), com o estado antes, depois e
-- depois das reversões (a reversão de 010100 é ensaiada à parte, porque a guarda dela precisa do md5 do corpo novo).
begin;
set local statement_timeout = '60s';
create temp table _z_out (em serial, passo text, linha text);
create temp table _zlog as select count(*) n from acesso.capacidade;
insert into pg_temp._z_out(passo, linha) select '1 antes capacidade contato.ver / log de capacidade', (select count(*) from acesso.capacidade where chave = 'contato.ver')::text;
insert into pg_temp._z_out(passo, linha) select '1 antes black_lista_disparo: md5 / anon executa / acl', (select md5(prosrc) || ' / ' || has_function_privilege('anon', oid, 'execute') || ' / ' || coalesce(proacl::text,'NULL') from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure);
insert into pg_temp._z_out(passo, linha) select '1 antes índice planilhas_projeto_id_idx', coalesce(to_regclass('mkt_mensageria.planilhas_projeto_id_idx')::text, 'não existe');
insert into pg_temp._z_out(passo, linha) select '1 antes crons', (select string_agg(jobname || ' ' || schedule || ' ativo=' || active, ' | ' order by jobname) from cron.job where jobname in ('mensageria-planilha-sync','dados-hotmart-ao-vivo-limpar'));
-- 20261014010000: registra em migration a permissão contato.ver dada a 4 perfis da equipe em 13/10/2026 18:36 UTC
--
-- POR QUE: em 13/10 as 4 linhas de contato.ver (listas da Mensageria da Black) entraram em acesso.capacidade por SQL direto,
-- sem migration (auditoria pelo guia do JP, item 4; guia 6.3 e 10.4). Permissão também é migration.
-- O QUE FAZ: insert idempotente das 4 linhas, por perfil_id (nunca por e-mail: o repo é público). No banco de produção as 4
-- já existem, então não muda nada (on conflict do nothing; o gatilho de log só dispara em insert real). Serve para quem
-- recriar o banco a partir das migrations (ex.: homologação). Quem são: decisão do Victor de 13/10, lista nominal no cérebro.
-- AS 5 PERGUNTAS: escala = 4 linhas; índice = PK (perfil_id, chave); frequência = única; repetição = nenhuma;
--   reversão = 20261014010000_reversao.sql (só registra; apagar a permissão é decisão do Victor, não reversão desta migration).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select count(*) from public.perfis p where p.id in ('81d2eaee-cce1-4058-8714-439b0fc6f970', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '843d43db-73b3-44a9-b449-1731e362dbc3', '012bbcd3-cade-4889-a6ff-4804ed15c36d') and p.status = 'ativo') <> 4 then
    raise exception '20261014010000: os 4 perfis não estão todos ativos. Reler.';
  end if;
end
$g$;

insert into acesso.capacidade (perfil_id, chave, criado_por)
select x.perfil_id, 'contato.ver', '81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid
  from (values
    ('81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid),
    ('3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid),
    ('843d43db-73b3-44a9-b449-1731e362dbc3'::uuid),
    ('012bbcd3-cade-4889-a6ff-4804ed15c36d'::uuid)
  ) as x(perfil_id)
on conflict (perfil_id, chave) do nothing;

-- 20261014010100: public.black_lista_disparo deixa de ser executável por anon; comentário velho corrigido
--
-- POR QUE (auditoria pelo guia do JP, itens 5, 6 e 14):
--  5. DEFINER executável por anon que devolve nome, e-mail e telefone com uma chave. A chave nunca foi configurada
--     (dados.black_lista_config.chave_sha256 nulo) e dados.black_lista_leituras tem 0 linhas: o Apps Script da planilha
--     nunca foi ligado. Guia 6.6: "em função nova, o padrão é fechar".
--  6. dados.black_lista_disparo_montar repete a regra de dados.black_base_pessoas. O único chamador é esta função; com o anon
--     fechado, ela fica desligada (não apagada), como manda o guia (10: desligar, não apagar). As listas da Mensageria usam
--     dados.black_base_pessoas e não mudam.
--  14. O comentário citava 20261013172751 (o número antes de renomear para 20261013174100).
-- O QUE FAZ: recria a função a partir do corpo vivo mudando só os comentários; revoke de anon (e de public e
--   authenticated, que já não tinham). Nenhuma lógica muda.
-- AS 5 PERGUNTAS: escala = nenhuma; índice = não se aplica; frequência = 0 chamadas hoje; repetição = nenhuma;
--   reversão = 20261014010100_reversao.sql (corpo e grant a anon de volta).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure) <> '0af314f38997fd59db0646313dc653fb' then
    raise exception '20261014010100: corpo vivo de black_lista_disparo mudou. Reler.';
  end if;
  if (select count(*) from dados.black_lista_leituras) <> 0 then
    raise exception '20261014010100: a lista já foi lida pelo Apps Script; não fechar sem falar com o Victor.';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION public.black_lista_disparo(p_chave text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- 20261013174100 (o arquivo saiu com 20261013172751 no comentário antes de renomear): chamada pelo Apps Script da planilha "[BLACK FRIDAY/26] LISTA DISPARO LIVE
-- CONSULTORIA 13/10", de hora em hora, com a anon key + p_chave. Sem a chave certa: 42501 e nada sai.
-- 20261014010100: DESLIGADA para anon (auditoria pelo guia do JP, item 5). O Apps Script nunca foi ligado (chave nunca
-- configurada, 0 leituras). Para religar: grant execute a anon numa migration nova, com o ok do Victor e do pentester.
declare
  v_hash text;
  r jsonb;
begin
  select c.chave_sha256 into v_hash from dados.black_lista_config c where c.id;
  if v_hash is null or p_chave is null or length(p_chave) < 32
     or encode(extensions.digest(p_chave, 'sha256'), 'hex') <> v_hash then
    raise exception 'não autorizado' using errcode = '42501';
  end if;
  if exists (select 1 from dados.black_lista_leituras l where l.em > now() - interval '5 minutes') then
    raise exception 'leitura recente: tente de novo em 5 min' using errcode = '54000';
  end if;
  r := dados.black_lista_disparo_montar();
  insert into dados.black_lista_leituras (pessoas, lista, fora_do_padrao)
  values ((r->'resumo'->>'pessoas')::int, (r->'resumo'->>'lista')::int, (r->'resumo'->>'fora_do_padrao')::int);
  return r;
end
$function$;

revoke execute on function public.black_lista_disparo(text) from public, anon, authenticated, service_role;

-- 20261014010200: índice na FK mkt_mensageria.planilhas.projeto_id (auditoria pelo guia do JP, item 11, parte nossa)
--
-- POR QUE: toda FK tem índice (padrão). A FK planilhas.projeto_id -> mkt.projetos(id) ON DELETE RESTRICT não tinha.
-- O QUE FAZ: create index if not exists. A tabela tem 1 linha: o índice não muda nenhum plano hoje (o guia lembra que em
--   tabela pequena o seq scan vence); serve para a checagem da FK quando um projeto for apagado e para o futuro. Sem
--   CONCURRENTLY porque o runner embrulha em transação e a tabela tem 1 linha (lock instantâneo).
-- AS 5 PERGUNTAS: escala = 1 linha; índice = este; frequência = única; repetição = nenhuma; reversão = 20261014010200_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create index if not exists planilhas_projeto_id_idx on mkt_mensageria.planilhas (projeto_id);

-- 20261014010300: dois crons nossos saem de minutos cheios (auditoria pelo guia do JP, item 10, parte nossa)
--
-- POR QUE: guia 6.5 e 8 ("cron novo = minuto vazio"). mensageria-planilha-sync (2-59/10) rodava junto com ops-vigia-10min em
--   TODA rodada; dados-hotmart-ao-vivo-limpar (05:37) junto com crm-whatsapp-reprocessar e os de cada minuto.
-- O QUE FAZ (cron.alter_job, só a agenda; comando, frequência e ativo não mudam):
--   mensageria-planilha-sync: 2-59/10 -> 6-59/10 (6/hora; coincide só com mensageria-fonte-sendflow 2x/hora e rotinas
--     diárias/semanais, não há minuto livre para um job de 10 em 10);
--   dados-hotmart-ao-vivo-limpar: 37 5 * * * -> 34 5 * * * (sem job de até 11/h nesse minuto).
-- FICA PARA O VICTOR (não mexido): data de fim de trafego-meta-hoje e de mensageria-planilha-sync depois do ATM 1 e da Black;
--   trafego-meta-hoje continua em :15/:45 (a validade de 75 min de dados_black_trafego conta com esse ritmo).
-- AS 5 PERGUNTAS: escala/índice não se aplicam; frequência igual; repetição nenhuma; reversão = 20261014010300_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
declare v_m bigint; v_h bigint;
begin
  select jobid into v_m from cron.job where jobname = 'mensageria-planilha-sync' and schedule = '2-59/10 * * * *';
  select jobid into v_h from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar' and schedule = '37 5 * * *';
  if v_m is null or v_h is null then
    raise exception '20261014010300: agenda viva diferente da esperada. Reler cron.job.';
  end if;
  perform cron.alter_job(job_id := v_m, schedule := '6-59/10 * * * *');
  perform cron.alter_job(job_id := v_h, schedule := '34 5 * * *');
end
$g$;

insert into pg_temp._z_out(passo, linha) select '2 depois capacidade contato.ver / log de capacidade', (select count(*) from acesso.capacidade where chave = 'contato.ver')::text;
insert into pg_temp._z_out(passo, linha) select '2 depois black_lista_disparo: md5 / anon executa / acl', (select md5(prosrc) || ' / ' || has_function_privilege('anon', oid, 'execute') || ' / ' || coalesce(proacl::text,'NULL') from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure);
insert into pg_temp._z_out(passo, linha) select '2 depois índice planilhas_projeto_id_idx', coalesce(to_regclass('mkt_mensageria.planilhas_projeto_id_idx')::text, 'não existe');
insert into pg_temp._z_out(passo, linha) select '2 depois crons', (select string_agg(jobname || ' ' || schedule || ' ativo=' || active, ' | ' order by jobname) from cron.job where jobname in ('mensageria-planilha-sync','dados-hotmart-ao-vivo-limpar'));
insert into pg_temp._z_out(passo, linha) select '2 linhas em acesso.capacidade iguais a antes', ((select count(*) from acesso.capacidade) = (select n from _zlog))::text;
-- Reversão de 20261014010300: agendas de antes.
set local lock_timeout = '5s';
do $g$
begin
  perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'mensageria-planilha-sync'), schedule := '2-59/10 * * * *');
  perform cron.alter_job(job_id := (select jobid from cron.job where jobname = 'dados-hotmart-ao-vivo-limpar'), schedule := '37 5 * * *');
end
$g$;

-- Reversão de 20261014010200
set local lock_timeout = '5s';
drop index if exists mkt_mensageria.planilhas_projeto_id_idx;

-- Reversão de 20261014010000: nada a desfazer. A migration só registra 4 linhas que já existiam em produção (on conflict do nothing).
-- Tirar contato.ver de alguém é decisão do Victor, numa migration própria.
select 1;

insert into pg_temp._z_out(passo, linha) select '3 depois das reversões de 010300, 010200 e 010000 capacidade contato.ver / log de capacidade', (select count(*) from acesso.capacidade where chave = 'contato.ver')::text;
insert into pg_temp._z_out(passo, linha) select '3 depois das reversões de 010300, 010200 e 010000 black_lista_disparo: md5 / anon executa / acl', (select md5(prosrc) || ' / ' || has_function_privilege('anon', oid, 'execute') || ' / ' || coalesce(proacl::text,'NULL') from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure);
insert into pg_temp._z_out(passo, linha) select '3 depois das reversões de 010300, 010200 e 010000 índice planilhas_projeto_id_idx', coalesce(to_regclass('mkt_mensageria.planilhas_projeto_id_idx')::text, 'não existe');
insert into pg_temp._z_out(passo, linha) select '3 depois das reversões de 010300, 010200 e 010000 crons', (select string_agg(jobname || ' ' || schedule || ' ativo=' || active, ' | ' order by jobname) from cron.job where jobname in ('mensageria-planilha-sync','dados-hotmart-ao-vivo-limpar'));
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
