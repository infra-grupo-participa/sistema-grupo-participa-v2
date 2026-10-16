-- 20261017020600: liga ao projeto 68 (CNFMIAMI26, Clínica Internacional de Holding Familiar) os 7 disparos da Clínica que a
--   integração gravou sem projeto (campanha sem [SIGLA] no nome => projeto nulo, origem 'api').
-- STATUS: ver 20261017020600.explain.md.
-- O QUE FAZ: update de projeto_id (null -> 68) em 7 ids, conferidos um a um (canal, campanha, origem, sistema, projeto nulo, não
--   arquivado). 5 e-mails do ActiveCampaign ("[Clínica] Carrinho aberto", "(2)", "(3)", "[Clínica] Último dia", "[Clínica] Faltam 3 horas")
--   e 2 WhatsApp API do Unichat (clinica_carrinhoaberto, clinica_miami_inscricao_pendente_util; os mesmos 2 da aba API da planilha da
--   Clínica, com o mesmo tamanho de base 1478 e 1467).
-- O QUE NÃO FAZ: não apaga (o banco bloqueia), não mexe em custo, copy, origem nem nos outros 2 disparos com "clinica" no nome
--   ("[CLINICA-INT] Compra Aprovada - v2" 50162 e clinica_compraaprovada_v2 50132: pós-compra, fora do pedido; decisão do Victor).
--   Não toca nos grupos "ALUNOS ATIVOS" do SendFlow (nome reaproveitado por outros eventos; entram pela planilha).
-- AVISO (ver explain): quando a planilha da Clínica for ativada com a aba API, desligar o vínculo dos ids 39925 e 40560
--   (projeto_id = null), senão a mesma mensagem conta duas vezes (a planilha insere linha nova de origem 'planilha').
-- AS 5 PERGUNTAS: escala 7 linhas; índice = a PK (id); frequência = uma vez; repetição = idempotente (where projeto_id is null);
--   reversão = 20261017020600_reversao.sql.
-- Sem grant, RLS ou auth.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select count(*) from mkt_mensageria.disparos
       where origem = 'api' and projeto_id is null and arquivado_em is null and (id, canal, campanha, origem_sistema) in (
         (39935, 'email', '[Clínica] Carrinho aberto', 'activecampaign'),
         (41099, 'email', '[Clínica] Carrinho aberto (2)', 'activecampaign'),
         (42695, 'email', '[Clínica] Carrinho aberto (3)', 'activecampaign'),
         (44024, 'email', '[Clínica] Último dia', 'activecampaign'),
         (44512, 'email', '[Clínica] Faltam 3 horas', 'activecampaign'),
         (39925, 'whatsapp_api', 'clinica_carrinhoaberto', 'unichat'),
         (40560, 'whatsapp_api', 'clinica_miami_inscricao_pendente_util', 'unichat'))) <> 7 then
    raise exception '20261017020600: os 7 disparos da Clínica não estão no estado esperado (sem projeto, ativos, mesmo nome)';
  end if;
  if not exists (select 1 from mkt.projetos where id = 68 and sigla = 'CNFMIAMI26') then
    raise exception '20261017020600: projeto 68 (CNFMIAMI26) não existe';
  end if;
end
$g$;

update mkt_mensageria.disparos set projeto_id = 68
 where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id is null and origem = 'api';

do $c$
begin
  if (select count(*) from mkt_mensageria.disparos where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id = 68) <> 7 then
    raise exception '20261017020600: nem todos os 7 foram ligados ao projeto 68';
  end if;
end
$c$;
