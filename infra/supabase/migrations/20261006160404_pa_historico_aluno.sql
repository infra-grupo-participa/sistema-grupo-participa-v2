-- 20261006160404: Pedidos de alteração (etapa 2), histórico de pedidos no card do aluno
--
-- STATUS: APLICADA em 06/10/2026 (pentester aprovou). Ensaio: 20261006160404_ensaio.sql (begin … rollback). Notas: 20261006160404.explain.md.
-- Independente das 20261006160401/02/03.
--
-- DECISÃO DO VICTOR (06/10/2026, noite): o histórico no card é lido de pa_pedidos aplicados (sem tabela nova, sem
-- backfill). Uma troca de sócio gera 3 textos, um para cada pessoa:
--   titular: "<titular> trocou o sócio <X> pelo sócio <Y> (pedido nº N, aprovado por <Fulano> em dd/mm/aaaa)"
--   sai:     "<X> saiu como sócio de <titular> (...)"
--   entra:   "<Y> entrou como sócio de <titular> (...)" + " (cadastro novo)" se a pessoa foi criada pelo pedido
--   alterar dado: "<Rótulo> alterado de <antes> para <depois> (...)", com pa_exibir (documento mascarado por
--   pa_pode_ver_doc(), turma pelo código, endereço numa linha).
--
-- CONTRATO COM A TELA (fixo):
--   pa_historico_aluno(p_aluno uuid) returns table(em timestamptz, pedido_id bigint, papel text, texto text)
--   papel ∈ 'titular' | 'sai' | 'entra' | 'aluno'; SECURITY DEFINER; só para gp_eh_equipe() (fora disso, 0 linhas);
--   ordem em desc.
--
-- ESCOLHAS DESTA MIGRATION (não estavam no plano; ficam registradas)
--   • Só pedidos `aplicado` dos tipos trocar_socio e alterar_dado. "outro" fica de fora: não tem texto estruturado.
--   • em = aplicado_em (cai para decidido_em se nulo). A data do texto é decidido_em, no fuso America/Sao_Paulo.
--   • Nomes vêm da foto do pedido (aluno_nome, socio_sai_nome, socio_entra_nome): é o nome na hora da troca.
--   • Rótulos = os da tela (CAMPOS_EDITAVEIS em web/modules/alunos/domain/pedidos-alteracao.ts), com concordância
--     ("Profissão alterada", "Turma alterada", "Instrução alterada", "Observação da Central alterada"). Valor vazio
--     aparece como "(vazio)", igual à tela.
--   • Aprovador sem perfil: "(aprovador não encontrado)".
--
-- AS 5 PERGUNTAS
--   escala: pa_pedidos tem dezenas de linhas e cresce dezenas por mês; cada chamada devolve os pedidos de 1 aluno.
--   índice: 3 novos, pa_pedidos(aluno_id), (socio_sai_id), (socio_entra_id), para não varrer a tabela quando ela
--     crescer (a ficha abre a cada clique num aluno). Parciais (where coluna is not null).
--   frequência: a cada abertura da aba de histórico na ficha (a tela guarda em cache por aluno).
--   repetição: leitura pura.
--   reversão: bloco REVERSÃO no fim (drop da função e dos 3 índices).
--
-- Quem lê fora do v2: ninguém (função nova; índices não mudam resultado de ninguém).

set local lock_timeout = '5s';

-- ═══ 0. Guarda ═══
do $guarda$
begin
  if to_regprocedure('public.pa_historico_aluno(uuid)') is not null then
    raise exception '20261006160404: pa_historico_aluno já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('public.pa_exibir(text,jsonb,boolean)') is null or to_regprocedure('public.pa_pode_ver_doc()') is null
     or to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception '20261006160404: pa_exibir, pa_pode_ver_doc ou gp_eh_equipe ausente';
  end if;
end
$guarda$;

-- ═══ 1. Índices (pa_pedidos é pequena: o create index trava a tabela por milissegundos) ═══
create index if not exists pa_pedidos_aluno_idx on public.pa_pedidos (aluno_id) where aluno_id is not null;
create index if not exists pa_pedidos_socio_sai_idx on public.pa_pedidos (socio_sai_id) where socio_sai_id is not null;
create index if not exists pa_pedidos_socio_entra_idx on public.pa_pedidos (socio_entra_id) where socio_entra_id is not null;

-- ═══ 2. Histórico do aluno ═══
create function public.pa_historico_aluno(p_aluno uuid)
returns table (em timestamptz, pedido_id bigint, papel text, texto text)
language sql stable security definer set search_path = '' as $$
  with ped as (
    select x.id, x.tipo, x.campo, x.valor_atual, x.valor_aplicado, x.aluno_id, x.socio_sai_id, x.socio_entra_id,
           x.aluno_nome, x.socio_sai_nome,
           coalesce(x.socio_entra_nome, x.socio_entra_novo ->> 'nome') as entra_nome,
           coalesce((x.valor_aplicado ->> 'socio_novo')::boolean, false) as socio_novo,
           coalesce(x.aplicado_em, x.decidido_em) as quando,
           ' (pedido nº ' || x.id || ', aprovado por ' || coalesce(p.nome, '(aprovador não encontrado)') || ' em '
             || coalesce(to_char(x.decidido_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'), '?') || ')' as suf
      from public.pa_pedidos x
      left join public.perfis p on p.id = x.decidido_por
     where p_aluno is not null and public.gp_eh_equipe()
       and x.status = 'aplicado' and x.tipo in ('trocar_socio', 'alterar_dado')
       and (x.aluno_id = p_aluno or x.socio_sai_id = p_aluno or x.socio_entra_id = p_aluno)
  ), doc as (select public.pa_pode_ver_doc() as ver)
  select h.em, h.pedido_id, h.papel, h.texto from (
    select q.quando as em, q.id as pedido_id, 'titular'::text as papel,
           q.aluno_nome || ' trocou o sócio ' || coalesce(q.socio_sai_nome, '?') || ' pelo sócio '
             || coalesce(q.entra_nome, '?') || q.suf as texto
      from ped q where q.tipo = 'trocar_socio' and q.aluno_id = p_aluno
    union all
    select q.quando, q.id, 'sai', coalesce(q.socio_sai_nome, '?') || ' saiu como sócio de ' || q.aluno_nome || q.suf
      from ped q where q.tipo = 'trocar_socio' and q.socio_sai_id = p_aluno
    union all
    select q.quando, q.id, 'entra', coalesce(q.entra_nome, '?') || ' entrou como sócio de ' || q.aluno_nome || q.suf
             || case when q.socio_novo then ' (cadastro novo)' else '' end
      from ped q where q.tipo = 'trocar_socio' and q.socio_entra_id = p_aluno
    union all
    select q.quando, q.id, 'aluno',
           case q.campo when 'nome' then 'Nome alterado' when 'email' then 'E-mail alterado'
                        when 'telefone' then 'Telefone alterado' when 'telefone_profissional' then 'Telefone profissional alterado'
                        when 'documento' then 'Documento (CPF ou CNPJ) alterado' when 'endereco' then 'Endereço alterado'
                        when 'profissao' then 'Profissão alterada' when 'turma_id' then 'Turma alterada'
                        when 'instrucao' then 'Instrução alterada' when 'espaco_instrucao' then 'Espaço de instrução alterado'
                        when 'obs_central' then 'Observação da Central alterada'
                        else coalesce(q.campo, 'Campo') || ' alterado' end
           || ' de ' || coalesce(public.pa_exibir(q.campo, q.valor_atual, d.ver), '(vazio)')
           || ' para ' || coalesce(public.pa_exibir(q.campo, q.valor_aplicado, d.ver), '(vazio)') || q.suf
      from ped q cross join doc d where q.tipo = 'alterar_dado' and q.aluno_id = p_aluno
  ) h
  order by h.em desc, h.pedido_id desc;
$$;

revoke all on function public.pa_historico_aluno(uuid) from public, anon;
grant execute on function public.pa_historico_aluno(uuid) to authenticated;

-- ═══ 3. Conferência ═══
do $confere$
begin
  if has_function_privilege('anon', 'public.pa_historico_aluno(uuid)', 'execute') then
    raise exception '20261006160404: pa_historico_aluno exposta para anon';
  end if;
  if (select count(*) from pg_indexes where schemaname = 'public' and tablename = 'pa_pedidos'
        and indexname in ('pa_pedidos_aluno_idx', 'pa_pedidos_socio_sai_idx', 'pa_pedidos_socio_entra_idx')) <> 3 then
    raise exception '20261006160404: índices não criados';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- A aba de histórico da ficha passa a dar erro ao chamar a função: reverter junto com a tela.
-- Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- drop function if exists public.pa_historico_aluno(uuid);
-- drop index if exists public.pa_pedidos_socio_entra_idx;
-- drop index if exists public.pa_pedidos_socio_sai_idx;
-- drop index if exists public.pa_pedidos_aluno_idx;
