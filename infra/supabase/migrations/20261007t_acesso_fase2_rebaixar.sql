-- 20261007t: níveis de acesso, fase 2 (rebaixar). Quem não é master deixa de ser admin/dev e passa a valer só pelos
-- vínculos e capacidades de acesso.*. Perfis pendentes com vínculo (Tráfego, Mensageria, Audiovisual) são ativados.
--
-- STATUS: NÃO APLICADA. SÓ APLICAR COM O OK DO VICTOR HUGO sobre o relatório "quem perde o quê"
--   (.maestri/entregas/niveis-de-acesso/ensaio-fase2.md no cérebro; resumo em 20261007t.explain.md). Regra dele:
--   "sobe na minha branch, depois que eu validar a gente sobe". Ensaio: 20261007t_ensaio.sql (rollback).
--
-- POR QUE
--   É a fase que de fato impede o líder de Web de criar projeto no Tráfego: com a fase 1, a guarda é "velho OU novo",
--   e o "velho" (cargo admin) ainda abre tudo para 19 pessoas que não são master.
--
-- O QUE FAZ
--   1. Foto acesso.perfis_antes_20261007 (id, nome, status, cargo, areas, funcoes, pode_ver_cpf_completo) de TODOS os
--      perfis, antes de mexer. Nada é apagado.
--   2. Perfis ativos com cargo admin ou dev que não estão em acesso.master → cargo visualizador. areas e funcoes ficam
--      como estão (o operador/gestor com função fina continua valendo onde já valia; visualizador não usa areas).
--   3. Perfis pendentes com vínculo vigente em acesso.vinculo → status ativo (renan, emmanuel, jessica, guilherme,
--      matheusvasconcellos, todos casados por e-mail com o Painel de KPIs). Continuam visualizador.
--
-- AS 5 PERGUNTAS
--   escala: 19 updates de cargo e 5 de status. índice: PK. frequência: uma vez. repetição: nenhuma.
--   reversão: update a partir da foto (bloco REVERSÃO no fim).
--
-- IDEMPOTENTE: a foto só é tirada uma vez (on conflict do nothing); rodar de novo não muda nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('acesso.master') is null or to_regclass('acesso.corpo_antes') is null then
    raise exception '20261007t: faltam as fases 0 e 1 (20261007180503, 20261007181138)';
  end if;
  if (select count(*) from acesso.master m join public.perfis p on p.id = m.perfil_id
       where p.status = 'ativo' and p.cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007t: os 3 masters não estão ativos com cargo admin/dev. Conferir antes de rebaixar.';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.provolatile = 'v' and p.prosrc ~ 'mkt\.pode_ver\(') then
    raise exception '20261007t: a fase 1 não está completa (escrita do Marketing ainda em mkt.pode_ver)';
  end if;
end
$g$;

-- 1. Foto
create table if not exists acesso.perfis_antes_20261007 (
  id uuid primary key, nome text, status text, cargo text, areas text[], funcoes text[],
  pode_ver_cpf_completo boolean, foto_em timestamptz not null default now()
);
alter table acesso.perfis_antes_20261007 enable row level security;
revoke all on acesso.perfis_antes_20261007 from public, anon, authenticated;
insert into acesso.perfis_antes_20261007 (id, nome, status, cargo, areas, funcoes, pode_ver_cpf_completo)
select p.id, p.nome, p.status, p.cargo, p.areas, p.funcoes, p.pode_ver_cpf_completo from public.perfis p
on conflict (id) do nothing;

-- 2. Rebaixar quem não é master
update public.perfis p set cargo = 'visualizador', atualizado_em = now()
 where p.status = 'ativo' and p.cargo in ('admin', 'dev')
   and not exists (select 1 from acesso.master m where m.perfil_id = p.id);

-- 3. Ativar pendentes com vínculo
update public.perfis p set status = 'ativo', atualizado_em = now()
 where p.status = 'pendente'
   and exists (select 1 from acesso.vinculo v where v.perfil_id = p.id and v.vigente_ate is null);

-- 4. Pós-condição
do $c$
begin
  if (select count(*) from public.perfis where status = 'ativo' and cargo in ('admin', 'dev')) <> 3 then
    raise exception '20261007t: esperava só os 3 masters com admin/dev';
  end if;
  if exists (select 1 from acesso.vinculo v join public.perfis p on p.id = v.perfil_id
              where v.vigente_ate is null and p.status <> 'ativo') then
    raise exception '20261007t: sobrou perfil com vínculo sem estar ativo';
  end if;
end
$c$;

-- REVERSÃO (numa transação):
-- update public.perfis p set cargo = f.cargo, status = f.status, atualizado_em = now()
--   from acesso.perfis_antes_20261007 f where f.id = p.id and (p.cargo, p.status) is distinct from (f.cargo, f.status);
