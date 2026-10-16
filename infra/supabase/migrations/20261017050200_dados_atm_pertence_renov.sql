-- 20261017050200: dados.atm_pertence reconhece o e-mail e o telefone das aplicações do /renov (metodo.renov_aplicacoes) da chave.
--
-- STATUS: NÃO APLICADA. Escrita em 16/10/2026 (branch victor-renov-padrao). Só foi rodado o ENSAIO (begin ... rollback).
--   Ensaio: 20261017050200_ensaio.sql. Reversão: 20261017050200_reversao.sql. Detalhe: 20261017050200.explain.md.
--
-- POR QUE: public.dados_marcar_teste só aceita marcar um e-mail ou telefone que "apareça neste evento" (dados.atm_pertence; senão P0002).
--   Quem aplicou no /renov e ainda não virou lead, venda nem presença não aparece em nenhuma das fontes de hoje, então não dava para
--   marcá-lo como teste pelo mesmo mecanismo do resto do dashboard. A aplicação do /renov passa a ser uma fonte do evento.
-- O QUE MUDA (uma função; mesma assinatura, mesmo retorno, mesma ACL):
--   dados.atm_pertence(p_chave, p_tipo, p_valor): corpo vivo (md5 7945be0a410031528e24bd21a4c876ca) + um EXISTS a mais em cada ramo.
--     'email': aplicação em metodo.renov_aplicacoes cuja origem aponta, em metodo.origem_etiqueta, para p_chave e lower(btrim(email)) = p_valor.
--     'fone' : o mesmo, com right(controle.fone_key(telefone), 8) = p_valor (mesma regra dos 8 últimos dígitos do resto da função).
--   O EXISTS novo vai primeiro em cada ramo: a tabela é minúscula e, quando casa, os outros não precisam rodar.
-- QUEM CHAMA (grep em 16/10/2026, banco e repositórios): só public.dados_marcar_teste, que é security definer e só master. A função segue
--   sem EXECUTE para public, anon e authenticated.
-- COMO VOLTAR: 20261017050200_reversao.sql (corpo vivo de antes, a partir de pg_get_functiondef de 16/10/2026).
-- AS 5 PERGUNTAS: escala = a checagem roda a cada clique de marcar teste de um master (dezenas por dia, no máximo); a tabela nova da checagem
--   tem 11 linhas e cresce com as aplicações (milhares no pior caso); com 10x continua leitura de milissegundo. índice = o EXISTS lê
--   metodo.origem_etiqueta pela PK e renov_aplicacoes por varredura (11 linhas); lower(btrim(email)) não usa o índice lower(email), e não
--   precisa: ver .explain.md. frequência = por clique, nunca job. repetição = nenhuma. reversão = arquivo.
-- DADO PESSOAL: a função só compara; não devolve nada além de true/false.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('dados.atm_pertence(text,text,text)') is null then
    raise exception '20261017050200: dados.atm_pertence(text,text,text) não existe';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure) <> '7945be0a410031528e24bd21a4c876ca' then
    raise exception '20261017050200: o corpo vivo de dados.atm_pertence mudou desde a leitura de 16/10/2026; reler e refazer a partir dele';
  end if;
  if to_regclass('metodo.renov_aplicacoes') is null or to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261017050200: faltam metodo.renov_aplicacoes (20261016163924, Arthur) ou metodo.origem_etiqueta';
  end if;
  if not exists (select 1 from metodo.origem_etiqueta where origem = 'renov-thb' and etiqueta = 'black-thb-2026-10') then
    raise exception '20261017050200: falta o de-para renov-thb -> black-thb-2026-10 (20261017050100); sem ele o ramo novo nunca casa';
  end if;
end
$g$;

create or replace function dados.atm_pertence(p_chave text, p_tipo text, p_valor text)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261008191000; número da foto do grupo em 20261008200000; aplicações do /renov em 20261017050200
  select case p_tipo
    when 'email' then
         exists (select 1 from metodo.renov_aplicacoes a join metodo.origem_etiqueta o on o.origem = a.origem
                  where o.etiqueta = p_chave and lower(btrim(a.email)) = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where l.email = p_valor)
      or exists (select 1 from dados.dashboards d cross join lateral dados.pre_checkout(d.chave, d.projeto_id, d.lista_ac) y
                  where d.chave = p_chave and lower(btrim(y.email)) = p_valor)
      or exists (select 1 from dados.atm_vendas_todas(p_chave) v where lower(btrim(v.email)) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and pr.email_norm = p_valor)
    when 'fone' then
         exists (select 1 from metodo.renov_aplicacoes a join metodo.origem_etiqueta o on o.origem = a.origem
                  where o.etiqueta = p_chave and right(controle.fone_key(a.telefone), 8) = p_valor)
      or exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
      or exists (select 1 from dados.atm_leads(p_chave) l where right(controle.fone_key(l.telefone), 8) = p_valor)
      or exists (select 1 from dados.sessao_presencas pr join dados.sessoes s on s.id = pr.sessao_id
                  where s.chave = p_chave and right(pr.fone_key, 8) = p_valor)
    else false end
$function$;

-- a ACL não pode ter mudado (create or replace a preserva; conferido aqui)
do $a$
begin
  if has_function_privilege('anon', 'dados.atm_pertence(text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.atm_pertence(text,text,text)', 'execute')
     or has_function_privilege('service_role', 'dados.atm_pertence(text,text,text)', 'execute') then
    raise exception '20261017050200: dados.atm_pertence ficou executável por anon, authenticated ou service_role';
  end if;
end
$a$;
