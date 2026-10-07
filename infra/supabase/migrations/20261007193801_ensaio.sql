-- Ensaio de 20261007w_acesso_log_jusy_vendedora.sql: 2 passadas num só begin … rollback. Gerado a partir dos .sql
-- como estão. Rodar com aplica_sql.py ensaio (o fim vira raise com a saída). Nada persiste.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to service_role, authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to service_role, authenticated, anon;


insert into pg_temp._z_out (passo, linha) select '1 antes', (select jsonb_build_object('log_jusy', (select jsonb_agg(tabela || ':' || acao) from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df'), 'cargo', (select cargo from public.perfis where id = '412d7d8d-7699-4dbf-977c-3b3cc82223df')))::text;

-- ===== PASSADA 1: 20261007w_acesso_log_jusy_vendedora.sql =====
-- 20261007w: níveis de acesso, registro em acesso.log da conta da Jusy como vendedora do Comercial (exceção nominal
-- pedida pelo Victor Hugo em 07/10/2026: "garanta que a jusy tenha acesso ao grupoparticipa app como vendedora la no
-- comercial, sem ser admin").
--
-- STATUS: NÃO APLICADA. Relatório: 20261007w.explain.md.
--
-- POR QUE
--   Conferido em 07/10/2026 (só leitura): a conta da Jusy (#412d) já está como vendedora e sem admin: perfil ativo, cargo
--   operador, área comercial, função comercial.vender, linha ativa em crm.vendedor (sigla js, criada 18:08:53 UTC) e
--   vínculo acesso membro do comercial (fase 2). A fase 2 (20261007182928) a deixou visualizador às 18:29:30 UTC; depois
--   disso o cargo passou a operador SEM linha em acesso.log e sem atualizar perfis.atualizado_em (autor não identificado:
--   o gatilho de log de perfis só nasce na fase 3). Nada precisou mudar no banco. A senha foi definida pela API admin do
--   Supabase Auth a pedido do Victor (a senha não é registrada em lugar nenhum).
--   Esta migration só REGISTRA, para a trilha de auditoria. Não muda perfis, vínculos nem capacidades.
--
-- AS 5 PERGUNTAS
--   escala: 2 linhas em acesso.log. índice: PK. frequência: uma vez. repetição: nenhuma. reversão: nenhuma (só acréscimo).
--
-- IDEMPOTENTE: só insere o que ainda não foi registrado com estes motivos.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '412d7d8d-7699-4dbf-977c-3b3cc82223df' and p.nome = 'Jusy' and p.status = 'ativo'
                    and p.cargo = 'operador' and 'comercial' = any(p.areas) and 'comercial.vender' = any(p.funcoes))
     or not exists (select 1 from crm.vendedor v where v.perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df' and v.ativo)
     or exists (select 1 from acesso.master m where m.perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df') then
    raise exception '20261007w: a conta da Jusy não está mais como vendedora sem admin. Reler antes de registrar.';
  end if;
end
$g$;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select null, 'perfis', 'update', '412d7d8d-7699-4dbf-977c-3b3cc82223df',
       jsonb_build_object('cargo', 'visualizador', 'nota', 'estado depois da fase 2 (20261007182928, 18:29:30 UTC)'),
       jsonb_build_object('cargo', 'operador', 'status', 'ativo', 'areas', '{comercial}'::text[], 'funcoes', '{comercial.vender}'::text[],
                          'motivo', 'cargo de vendedora (operador) depois da fase 2, sem log na hora; autor não identificado',
                          'registrado_por', 'migration 20261007w', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df'
                     and depois ->> 'motivo' = 'cargo de vendedora (operador) depois da fase 2, sem log na hora; autor não identificado');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select null, 'auth', 'senha', '412d7d8d-7699-4dbf-977c-3b3cc82223df', null,
       jsonb_build_object('motivo', 'senha padrão definida pela API admin do Auth a pedido do Victor 07/10 (vendedora do Comercial, sem admin)',
                          'login_testado', true, 'registrado_por', 'migration 20261007w', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df' and tabela = 'auth');

insert into pg_temp._z_out (passo, linha) select '2 depois1', (select jsonb_build_object('log_jusy', (select jsonb_agg(tabela || ':' || acao) from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df'), 'cargo', (select cargo from public.perfis where id = '412d7d8d-7699-4dbf-977c-3b3cc82223df')))::text;

-- ===== PASSADA 2: 20261007w_acesso_log_jusy_vendedora.sql =====
-- 20261007w: níveis de acesso, registro em acesso.log da conta da Jusy como vendedora do Comercial (exceção nominal
-- pedida pelo Victor Hugo em 07/10/2026: "garanta que a jusy tenha acesso ao grupoparticipa app como vendedora la no
-- comercial, sem ser admin").
--
-- STATUS: NÃO APLICADA. Relatório: 20261007w.explain.md.
--
-- POR QUE
--   Conferido em 07/10/2026 (só leitura): a conta da Jusy (#412d) já está como vendedora e sem admin: perfil ativo, cargo
--   operador, área comercial, função comercial.vender, linha ativa em crm.vendedor (sigla js, criada 18:08:53 UTC) e
--   vínculo acesso membro do comercial (fase 2). A fase 2 (20261007182928) a deixou visualizador às 18:29:30 UTC; depois
--   disso o cargo passou a operador SEM linha em acesso.log e sem atualizar perfis.atualizado_em (autor não identificado:
--   o gatilho de log de perfis só nasce na fase 3). Nada precisou mudar no banco. A senha foi definida pela API admin do
--   Supabase Auth a pedido do Victor (a senha não é registrada em lugar nenhum).
--   Esta migration só REGISTRA, para a trilha de auditoria. Não muda perfis, vínculos nem capacidades.
--
-- AS 5 PERGUNTAS
--   escala: 2 linhas em acesso.log. índice: PK. frequência: uma vez. repetição: nenhuma. reversão: nenhuma (só acréscimo).
--
-- IDEMPOTENTE: só insere o que ainda não foi registrado com estes motivos.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '412d7d8d-7699-4dbf-977c-3b3cc82223df' and p.nome = 'Jusy' and p.status = 'ativo'
                    and p.cargo = 'operador' and 'comercial' = any(p.areas) and 'comercial.vender' = any(p.funcoes))
     or not exists (select 1 from crm.vendedor v where v.perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df' and v.ativo)
     or exists (select 1 from acesso.master m where m.perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df') then
    raise exception '20261007w: a conta da Jusy não está mais como vendedora sem admin. Reler antes de registrar.';
  end if;
end
$g$;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select null, 'perfis', 'update', '412d7d8d-7699-4dbf-977c-3b3cc82223df',
       jsonb_build_object('cargo', 'visualizador', 'nota', 'estado depois da fase 2 (20261007182928, 18:29:30 UTC)'),
       jsonb_build_object('cargo', 'operador', 'status', 'ativo', 'areas', '{comercial}'::text[], 'funcoes', '{comercial.vender}'::text[],
                          'motivo', 'cargo de vendedora (operador) depois da fase 2, sem log na hora; autor não identificado',
                          'registrado_por', 'migration 20261007w', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df'
                     and depois ->> 'motivo' = 'cargo de vendedora (operador) depois da fase 2, sem log na hora; autor não identificado');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select null, 'auth', 'senha', '412d7d8d-7699-4dbf-977c-3b3cc82223df', null,
       jsonb_build_object('motivo', 'senha padrão definida pela API admin do Auth a pedido do Victor 07/10 (vendedora do Comercial, sem admin)',
                          'login_testado', true, 'registrado_por', 'migration 20261007w', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df' and tabela = 'auth');

insert into pg_temp._z_out (passo, linha) select '3 depois2', (select jsonb_build_object('log_jusy', (select jsonb_agg(tabela || ':' || acao) from acesso.log where perfil_id = '412d7d8d-7699-4dbf-977c-3b3cc82223df'), 'cargo', (select cargo from public.perfis where id = '412d7d8d-7699-4dbf-977c-3b3cc82223df')))::text;


set local statement_timeout = '60s';
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
