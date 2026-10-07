-- 20261007150701_ensaio.sql — ensaio da migration 20261007150701_crm_estrategias (escrita como 20261007w) em transação DESFEITA (termina em ROLLBACK).
-- Roda a migration inteira e depois cada regra com JWT real (request.jwt.claims + role authenticated):
--   Elaine (dev, com a função)   → acesso {solicitar:true, gestor:false}; cria 3 pedidos; prévia só com contagem (amostra vazia);
--                                   não muda situação nem transforma; RLS: vê só os dela.
--   Marcos (vendedor, operador)  → acesso {false,false}; lista/detalhe 42501; salvar/prévia/situação recusados; RLS 0.
--   Visualizador ativo            → acesso {false,false}; lista/opções 42501; salvar/prévia/transformar recusados; RLS 0.
--   Jonathan (admin + comercial) → acesso {solicitar:false, gestor:true}; vê todos; prévia com amostra mascarada;
--                                   em_analise ok, volta inválida recusada; transforma p1 em fila (2ª vez recusada);
--                                   prévia de novo = quase todos "outraAcao"; p2 vira funil próprio; recusa exige motivo.
--   Efeitos: notificação "nova" para Jonathan e Arthur (não para a Elaine); solicitante notificada a cada mudança;
--   1 aviso no Slack por pedido sem "@"; fila e funil divididos Jonathan/Marcos; 0 "lead_novo" do lote; resumo por vendedor.
-- Depois do ROLLBACK: to_regclass('crm.estrategia') is null e nenhum perfil com a função (prova de que nada persistiu).
begin;
set local lock_timeout = '5s';
set local statement_timeout = '90s';
-- 20261007w_crm_estrategias.sql
-- Estratégias do Comercial (antiga "Recuperação"): solicitação de estratégia/ação, modelo de público,
-- "Transformar em ação" (fila de recuperação ou funil próprio) e placar da ação.
--
-- Quem faz o quê (pedido do Arthur, 07/10/2026):
--   * Solicita: quem tem a função `comercial.solicitar_estrategia` em perfis.funcoes (vale pela FUNÇÃO, não pelo cargo:
--     dev/admin sem a função não solicita). Concedida aqui a Elaine, Marcio e Arthur.
--   * Executa: o gestor comercial = status ativo, cargo dev/admin/gestor E área `comercial` (crm.estrategia_eh_gestor:
--     hoje Jonathan e Arthur). Mais estreito que crm.eh_gestor() de propósito (este libera todo dev/admin).
--   * O solicitante vê só os pedidos dele e o andamento/placar, sem acesso ao resto do CRM.
--
-- Mudanças em objeto existente (definição VIVA lida em 07/10/2026 antes de reescrever):
--   * CHECK crm.notificacao.gatilho, crm.slack_fila.tipo e crm.log.entidade ganham 'estrategia' (valores antigos mantidos).
--   * crm.tg_negocio_notifica: + 1 linha (lote de estratégia não avisa negócio a negócio; vai um resumo por vendedor).
--
-- Contas Hotmart: a estratégia lê as DUAS contas de propósito (escada B vende na Academy; Sessão de Viabilidade, Croqui e
-- Holding do escritório vendem na conta Escritório). Toda citação de fin.hotmart_transacoes está na forma da trava
-- (fin.trava_conta_hotmart): uma subconsulta por conta, juntas com union all.
--
-- Kill-switch: crm.config.escrita_ligada (as RPCs de escrita passam por crm.guarda_escrita no caminho do gestor e
-- checam a flag no caminho do solicitante). Nada se apaga: pedido recusado/concluído fica no histórico.

-- 0. Guarda de premissa ------------------------------------------------------------------------------------------
do $$
begin
  if to_regclass('crm.estrategia') is not null then raise exception 'premissa: crm.estrategia já existe'; end if;
  if to_regprocedure('public.crm_criar_negocio(uuid,uuid,uuid)') is null
     or to_regprocedure('crm.slack_enfileirar(text,text,text)') is null
     or to_regprocedure('pessoas.mascara_email(text)') is null
     or to_regprocedure('pessoas.pessoa_do_aluno(uuid)') is null
     or to_regprocedure('pessoas.pessoa_do_comprador(uuid)') is null
     or to_regprocedure('crm.pessoa_por_email(text)') is null
     or to_regprocedure('crm.garantir_pc(uuid)') is null
     or to_regprocedure('crm.vendedor_ativo(uuid)') is null then
    raise exception 'premissa: funções do CRM/pessoas ausentes';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'notificacao_gatilho_check' and c.conrelid = 'crm.notificacao'::regclass)
     <> 'CHECK ((gatilho = ANY (ARRAY[''lead_novo''::text, ''lead_respondeu''::text, ''prazo_estourado''::text, ''venda_aprovada''::text, ''ficha_para_aprovar''::text, ''atividade_vencendo''::text])))' then
    raise exception 'premissa: notificacao_gatilho_check mudou';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'slack_fila_tipo_check' and c.conrelid = 'crm.slack_fila'::regclass)
     <> 'CHECK ((tipo = ANY (ARRAY[''reembolso''::text, ''chargeback''::text, ''disputa''::text, ''oferta_orfa''::text, ''erro_hotmart''::text])))' then
    raise exception 'premissa: slack_fila_tipo_check mudou';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'log_entidade_check' and c.conrelid = 'crm.log'::regclass)
     not like '%''config''::text])))' or (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conname = 'log_entidade_check' and c.conrelid = 'crm.log'::regclass) like '%estrategia%' then
    raise exception 'premissa: log_entidade_check mudou';
  end if;
  if (select count(*) from public.perfis p where p.email in ('elaine@advmais.com', 'marcio@advmais.com', 'arthur@advmais.com') and p.status = 'ativo') <> 3 then
    raise exception 'premissa: os 3 perfis solicitantes não estão ativos';
  end if;
  if position('crm.lote_estrategia' in pg_get_functiondef('crm.tg_negocio_notifica()'::regprocedure)) > 0 then
    raise exception 'premissa: tg_negocio_notifica já tem a trava de lote';
  end if;
end $$;

-- 1. CHECKs: acrescenta 'estrategia' sem tirar valor nenhum -------------------------------------------------------
alter table crm.notificacao drop constraint notificacao_gatilho_check;
alter table crm.notificacao add constraint notificacao_gatilho_check check (gatilho = any (array['lead_novo', 'lead_respondeu',
  'prazo_estourado', 'venda_aprovada', 'ficha_para_aprovar', 'atividade_vencendo', 'estrategia']));

alter table crm.slack_fila drop constraint slack_fila_tipo_check;
alter table crm.slack_fila add constraint slack_fila_tipo_check check (tipo = any (array['reembolso', 'chargeback', 'disputa',
  'oferta_orfa', 'erro_hotmart', 'estrategia']));

alter table crm.log drop constraint log_entidade_check;
alter table crm.log add constraint log_entidade_check check (entidade = any (array['negocio', 'contato', 'atividade', 'mensagem',
  'nota', 'funil', 'etapa', 'campanha', 'agrupador', 'projeto', 'motivo', 'ficha', 'fila', 'produto', 'oferta', 'distribuicao',
  'link', 'dashboard', 'painel', 'preferencias', 'vendedor', 'config', 'estrategia']));

-- 2. Tabelas ----------------------------------------------------------------------------------------------------
create table crm.estrategia_modelo (
  chave      text primary key check (chave ~ '^[a-z0-9_]{3,60}$'),
  nome       text not null check (length(btrim(nome)) between 3 and 80),
  descricao  text not null default '' check (length(descricao) <= 1000),
  filtros    jsonb not null check (jsonb_typeof(filtros) = 'object'),
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

create table crm.estrategia (
  id              uuid primary key default gen_random_uuid(),
  titulo          text not null check (length(btrim(titulo)) between 3 and 120),
  objetivo        text not null check (length(btrim(objetivo)) between 3 and 2000),
  publico         text not null default '' check (length(publico) <= 2000),
  filtros         jsonb not null default '{}' check (jsonb_typeof(filtros) = 'object'),
  modelo          text references crm.estrategia_modelo(chave) on delete restrict,
  linha           text references crm.linha(chave) on delete restrict,
  oferta          text check (oferta is null or length(oferta) <= 200),
  prazo           date,
  prioridade      text not null default 'media' check (prioridade in ('baixa', 'media', 'alta', 'urgente')),
  observacoes     text not null default '' check (length(observacoes) <= 2000),
  solicitante_id  uuid not null references public.perfis(id) on delete restrict,
  situacao        text not null default 'solicitada'
                  check (situacao in ('solicitada', 'em_analise', 'em_execucao', 'concluida', 'recusada')),
  motivo_recusa   text check (motivo_recusa is null or length(btrim(motivo_recusa)) between 3 and 500),
  responsavel_id  uuid references public.perfis(id) on delete restrict,
  acao_tipo       text check (acao_tipo in ('fila', 'funil')),
  fila_id         uuid references crm.fila(id) on delete restrict,
  funil_id        uuid references crm.funil(id) on delete restrict,
  acao_criada_em  timestamptz,
  acao_pessoas    integer check (acao_pessoas is null or acao_pessoas >= 0),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  constraint estrategia_recusa_check check ((situacao = 'recusada') = (motivo_recusa is not null)),
  constraint estrategia_acao_check check (
    (acao_tipo is null and fila_id is null and funil_id is null and acao_criada_em is null)
    or (acao_tipo = 'fila' and fila_id is not null and funil_id is null and acao_criada_em is not null)
    or (acao_tipo = 'funil' and funil_id is not null and fila_id is null and acao_criada_em is not null))
);
create index estrategia_solicitante_idx on crm.estrategia (solicitante_id, criado_em desc);
create index estrategia_situacao_idx on crm.estrategia (situacao, criado_em desc);

create table crm.estrategia_historico (
  id             bigint generated always as identity primary key,
  estrategia_id  uuid not null references crm.estrategia(id) on delete restrict,
  de             text,
  para           text not null,
  por            uuid references public.perfis(id) on delete restrict,
  nota           text check (nota is null or length(nota) <= 500),
  em             timestamptz not null default now()
);
create index estrategia_historico_idx on crm.estrategia_historico (estrategia_id, em);

-- 3. Helpers de papel (SECURITY DEFINER, coalesce: falha FECHADA com NULL) ---------------------------------------
create function crm.estrategia_eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.status = 'ativo' and p.cargo in ('dev', 'admin', 'gestor') and 'comercial' = any(coalesce(p.areas, '{}'))
      from public.perfis p where p.id = (select auth.uid())
  ), false);
$$;

create function crm.pode_solicitar_estrategia()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.status = 'ativo' and 'comercial.solicitar_estrategia' = any(coalesce(p.funcoes, '{}'))
      from public.perfis p where p.id = (select auth.uid())
  ), false);
$$;

revoke execute on function crm.estrategia_eh_gestor(), crm.pode_solicitar_estrategia() from public, anon;
grant execute on function crm.estrategia_eh_gestor(), crm.pode_solicitar_estrategia() to authenticated;

-- 4. RLS (leitura direta, se o schema crm um dia for exposto; escrita só por RPC) --------------------------------
alter table crm.estrategia enable row level security;
alter table crm.estrategia_historico enable row level security;
alter table crm.estrategia_modelo enable row level security;

create policy estrategia_ver on crm.estrategia for select to authenticated
  using (coalesce(crm.estrategia_eh_gestor(), false)
         or (solicitante_id = (select auth.uid()) and coalesce(crm.pode_solicitar_estrategia(), false)));
create policy estrategia_historico_ver on crm.estrategia_historico for select to authenticated
  using (exists (select 1 from crm.estrategia e where e.id = estrategia_id
                  and (coalesce(crm.estrategia_eh_gestor(), false)
                       or (e.solicitante_id = (select auth.uid()) and coalesce(crm.pode_solicitar_estrategia(), false)))));
create policy estrategia_modelo_ver on crm.estrategia_modelo for select to authenticated
  using (coalesce(crm.estrategia_eh_gestor(), false) or coalesce(crm.pode_solicitar_estrategia(), false));

revoke all on crm.estrategia, crm.estrategia_historico, crm.estrategia_modelo from public, anon, authenticated;
grant select on crm.estrategia, crm.estrategia_historico, crm.estrategia_modelo to authenticated;

-- 5. Lote de estratégia não avisa negócio a negócio (vai 1 resumo por vendedor) ---------------------------------
-- Corpo VIVO de 07/10/2026 + a linha marcada.
create or replace function crm.tg_negocio_notifica()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
declare v_gat text; v_tit text; v_corpo text; v_nome text;
begin
  if new.dono_id is null then return null; end if;
  if coalesce(current_setting('crm.canal', true), '') = 'clint_import' then return null; end if;   -- 20261006d: carga da Clint não avisa
  if coalesce(current_setting('crm.lote_estrategia', true), '') = '1' then return null; end if;   -- 20261007w: lote da estratégia avisa por resumo
  if new.status = 'aberto' and (tg_op = 'INSERT' or old.dono_id is distinct from new.dono_id)
     and new.dono_id is distinct from auth.uid() then
    v_gat := 'lead_novo';
  elsif tg_op = 'UPDATE' and new.status = 'ganho' and old.status is distinct from 'ganho' then
    v_gat := 'venda_aprovada';
  else
    return null;
  end if;
  begin
    if exists (select 1 from crm.preferencias_notificacao p
                where p.perfil_id = new.dono_id and (p.gatilhos ->> v_gat) = 'false') then
      return null;
    end if;
    v_nome := crm.nome_pessoa(new.pessoa_id);
    if v_gat = 'lead_novo' then
      v_tit := 'Lead novo: ' || v_nome;
      v_corpo := coalesce((select e.nome from crm.etapa_funil e where e.id = new.etapa_id), 'Entrada') || ' · primeiro contato em até 5 minutos.';
    else
      v_tit := 'Venda aprovada: ' || v_nome;
      v_corpo := coalesce((select l.nome from crm.linha l where l.chave = new.linha), new.linha) || ' · pagamento aprovado na Hotmart.';
    end if;
    insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
    values (new.dono_id, v_gat, new.id::text, left(v_tit, 200), left(v_corpo, 500), '/comercial/funil?negocio=' || new.id)
    on conflict (perfil_id, gatilho, ref_id) do nothing;
  exception when others then
    raise warning 'crm.tg_negocio_notifica: % (%)', sqlerrm, sqlstate;
  end;
  return null;
end
$function$;

-- 6. Funções internas (não chamáveis pela API) ------------------------------------------------------------------
-- Texto[] de um jsonb array de strings (lixo vira vazio).
create function crm.estr_txt(p jsonb)
returns text[] language sql immutable set search_path = '' as $$
  select coalesce(array(select btrim(x) from jsonb_array_elements_text(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) x
                         where btrim(x) <> ''), '{}');
$$;

-- Produtos Hotmart de um bloco {produtos:[ids], linhas:[chaves]} (linha → produtos vinculados ao comercial).
create function crm.estr_produtos(p jsonb)
returns text[] language sql stable set search_path = '' as $$
  select coalesce(array(
    select x from unnest(crm.estr_txt(p -> 'produtos')) x
    union
    select pc.produto_id from crm.produto_comercial pc where pc.linha = any(crm.estr_txt(p -> 'linhas'))), '{}');
$$;

-- Valida o formato dos filtros. null = ok; texto = o que está errado.
create function crm.estrategia_validar_filtros(p jsonb)
returns text language plpgsql immutable set search_path = '' as $$
declare r jsonb; k text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return 'Filtros inválidos.'; end if;
  if length(p::text) > 20000 then return 'Filtros grandes demais.'; end if;
  for k in select jsonb_object_keys(p) loop
    if k not in ('base', 'alunos', 'comprou', 'naoComprou', 'respondi', 'catalogacao', 'excluir') then
      return format('Filtro desconhecido: %s.', k);
    end if;
  end loop;
  if coalesce(p ->> 'base', 'alunos') not in ('alunos', 'contatos', 'compradores') then return 'Base inválida.'; end if;
  if jsonb_typeof(p -> 'respondi' -> 'regras') = 'array' then
    if jsonb_array_length(p -> 'respondi' -> 'regras') > 20 then return 'No máximo 20 regras de pesquisa.'; end if;
    for r in select * from jsonb_array_elements(p -> 'respondi' -> 'regras') loop
      if cardinality(crm.estr_txt(r -> 'perguntas')) = 0 or cardinality(crm.estr_txt(r -> 'contem')) = 0 then
        return 'Cada regra de pesquisa precisa de pergunta e resposta.';
      end if;
      if exists (select 1 from unnest(crm.estr_txt(r -> 'contem')) c where length(c) < 3) then
        return 'Resposta da regra de pesquisa com menos de 3 letras.';
      end if;
    end loop;
  end if;
  return null;
end
$$;

-- O público: cada pessoa candidata e o motivo de ficar de fora (null = elegível). Sem guarda própria: só é
-- chamada pelas RPCs abaixo, que guardam. Opt-out sai SEMPRE.
create function crm.estrategia_candidatos(p jsonb)
returns table(pessoa_id uuid, aluno_id uuid, comprador_id uuid, email text, nome text, nivel text, turma text, motivo text)
language plpgsql stable set search_path = '' as $$
#variable_conflict use_column
declare
  v_base text := coalesce(p ->> 'base', 'alunos');
  v_niveis text[] := crm.estr_txt(p -> 'alunos' -> 'niveis');
  v_turmas text[] := crm.estr_txt(p -> 'alunos' -> 'turmas');
  v_tipos text[] := crm.estr_txt(p -> 'alunos' -> 'tiposTurma');
  v_planos text[] := crm.estr_txt(p -> 'alunos' -> 'planos');
  v_status text[] := crm.estr_txt(p -> 'alunos' -> 'statusAcesso');
  v_comprou text[] := crm.estr_produtos(p -> 'comprou');
  v_nao text[] := crm.estr_produtos(p -> 'naoComprou');
  v_projetos text[] := crm.estr_txt(p -> 'catalogacao' -> 'projetos');
  v_canais text[] := crm.estr_txt(p -> 'catalogacao' -> 'canais');
  v_regras jsonb := case when jsonb_typeof(p -> 'respondi' -> 'regras') = 'array' then p -> 'respondi' -> 'regras' else '[]'::jsonb end;
  v_tem_al boolean; v_tem_resp boolean; v_tem_cat boolean;
  v_ex_neg boolean := coalesce((p -> 'excluir' ->> 'emNegociacao')::boolean, true);
  v_ex_acao boolean := coalesce((p -> 'excluir' ->> 'outraAcao')::boolean, true);
begin
  v_tem_al := cardinality(v_niveis) + cardinality(v_turmas) + cardinality(v_tipos) + cardinality(v_planos) + cardinality(v_status) > 0;
  v_tem_resp := jsonb_array_length(v_regras) > 0;
  v_tem_cat := cardinality(v_projetos) + cardinality(v_canais) > 0;
  if v_base = 'compradores' and cardinality(v_comprou) = 0 then
    raise exception 'Base de compradores precisa do filtro "comprou".' using errcode = '22023';
  end if;

  return query
  with
  regras as (
    select array(select jsonb_array_elements_text(r -> 'perguntas')) per,
           array(select '%' || replace(replace(replace(lower(btrim(x)), '\', '\\'), '%', '\%'), '_', '\_') || '%'
                   from jsonb_array_elements_text(r -> 'contem') x where btrim(x) <> '') pads,
           crm.estr_txt(r -> 'forms') forms
      from jsonb_array_elements(v_regras) r),
  forms_alvo as (
    select f.slug from respondi.formularios f
     where v_tem_resp and exists (
       select 1 from jsonb_array_elements(case jsonb_typeof(f.campos) when 'array' then f.campos else '[]'::jsonb end) c, regras g
        where (c ->> 'pergunta') = any(g.per) and (cardinality(g.forms) = 0 or f.slug = any(g.forms)))),
  resp as materialized (
    select distinct r.aluno_id ra, lower(btrim(r.email)) re
      from respondi.respostas r
      cross join lateral jsonb_array_elements(case jsonb_typeof(r.respostas) when 'array' then r.respostas else '[]'::jsonb end) e
      join regras g on (e ->> 'p') = any(g.per) and (cardinality(g.forms) = 0 or r.form_slug = any(g.forms))
     where v_tem_resp and r.form_slug in (select fa.slug from forms_alvo fa)
       and lower(e ->> 'v') like any(g.pads)),
  resp_al as (select distinct ra from resp where ra is not null),
  resp_em as (select distinct re from resp where re is not null and re <> ''),
  compr as materialized (
    select distinct lower(trim(both from t.comprador_email)) em from (select * from fin.hotmart_transacoes where conta = 'academy' union all select * from fin.hotmart_transacoes where conta = 'escritorio') t
     where cardinality(v_comprou) > 0 and t.produto_id = any(v_comprou) and t.status in ('APPROVED', 'COMPLETE')),
  nao as materialized (
    select distinct lower(trim(both from t.comprador_email)) em from (select * from fin.hotmart_transacoes where conta = 'academy' union all select * from fin.hotmart_transacoes where conta = 'escritorio') t
     where cardinality(v_nao) > 0 and t.produto_id = any(v_nao) and t.status in ('APPROVED', 'COMPLETE')),
  base_al as (
    select a.id a_id, a.comprador_id c_id, lower(trim(both from a.email)) em, a.nome nm, a.nivel_resultado nv, t.codigo tc,
           t.tipo tt, a.plano pl, a.status_acesso sa, pp.id pid
      from public.thb_alunos a
      left join public.thb_turmas t on t.id = a.turma_id
      left join pessoas.pessoas pp on pp.aluno_id = a.id
     where v_base = 'alunos'),
  base_ct as (
    select a.id a_id, coalesce(pp.comprador_id, a.comprador_id) c_id,
           coalesce(nullif(lower(trim(both from a.email)), ''), nullif(lower(btrim(c.email::text)), ''),
                    (select i.chave from pessoas.identificadores i where i.pessoa_id = pp.id and i.tipo = 'email' limit 1)) em,
           coalesce(pp.nome, a.nome, c.nome::text) nm, a.nivel_resultado nv, t.codigo tc, t.tipo tt, a.plano pl, a.status_acesso sa, pp.id pid
      from crm.pessoa_comercial pc
      join pessoas.pessoas pp on pp.id = pc.pessoa_id and pp.mesclada_em is null and not coalesce(pp.teste, false)
      left join public.thb_alunos a on a.id = pp.aluno_id
      left join public.thb_turmas t on t.id = a.turma_id
      left join public.compradores c on c.id = pp.comprador_id
     where v_base = 'contatos'),
  base_co as (
    select a.id a_id, coalesce(c.id, a.comprador_id) c_id, x.em, coalesce(a.nome, c.nome::text) nm, a.nivel_resultado nv, t.codigo tc,
           t.tipo tt, a.plano pl, a.status_acesso sa,
           coalesce((select pp.id from pessoas.pessoas pp where pp.aluno_id = a.id),
                    (select pp.id from pessoas.pessoas pp where pp.comprador_id = c.id)) pid
      from compr x
      left join lateral (select c0.* from public.compradores c0 where lower(btrim(c0.email::text)) = x.em limit 1) c on true
      left join public.thb_alunos a on lower(trim(both from a.email)) = x.em and a.email is not null and a.email <> ''
      left join public.thb_turmas t on t.id = a.turma_id
     where v_base = 'compradores' and x.em is not null and x.em <> ''),
  cand as (
    select b.*, pessoas.atual(b.pid) atual
      from (select * from base_al union all select * from base_ct union all select * from base_co) b
     where (b.pid is not null or b.a_id is not null or b.c_id is not null)
       and (not v_tem_al or (b.a_id is not null
            and (cardinality(v_niveis) = 0 or b.nv = any(v_niveis))
            and (cardinality(v_turmas) = 0 or b.tc = any(v_turmas))
            and (cardinality(v_tipos) = 0 or b.tt = any(v_tipos))
            and (cardinality(v_planos) = 0 or b.pl = any(v_planos))
            and (cardinality(v_status) = 0 or b.sa = any(v_status))))
       and (v_base = 'compradores' or cardinality(v_comprou) = 0 or b.em in (select compr.em from compr))
       and (not v_tem_resp or b.a_id in (select resp_al.ra from resp_al) or b.em in (select resp_em.re from resp_em))),
  cand_cat as (
    select c.* from cand c
     where not v_tem_cat or exists (
       select 1 from crm.pessoa_origem po
        where po.pessoa_id = any(pessoas.grupo(c.atual))
          and (cardinality(v_projetos) = 0 or po.projeto = any(v_projetos))
          and (cardinality(v_canais) = 0 or po.canal_entrada = any(v_canais)))),
  optout as materialized (
    select distinct pessoas.atual(pc.pessoa_id) id from crm.pessoa_comercial pc where pc.opt_out),
  supr as materialized (
    select distinct s.valor em from crm.supressao s where s.tipo = 'e' and s.canal = 'todos'),
  negoc as materialized (
    select distinct pessoas.atual(n.pessoa_id) id from crm.negocio n where v_ex_neg and n.status = 'aberto'),
  acao as materialized (
    select distinct pessoas.atual(fi.pessoa_id) id from crm.fila_item fi join crm.fila f on f.id = fi.fila_id and f.encerrada_em is null
     where v_ex_acao and fi.status in ('a_abordar', 'tentando_contato', 'em_conversa', 'vai_comprar')),
  final as (
    select distinct on (coalesce(c.atual::text, 'a:' || c.a_id::text, 'e:' || c.em))
           c.atual, c.a_id, c.c_id, c.em, c.nm, c.nv, c.tc,
           case when c.atual in (select o.id from optout o) or c.em in (select s.em from supr s) then 'opt_out'
                when c.em in (select n.em from nao n) then 'ja_comprou'
                when c.atual in (select g.id from negoc g) then 'em_negociacao'
                when c.atual in (select x.id from acao x) then 'outra_acao' end mot
      from cand_cat c
     order by coalesce(c.atual::text, 'a:' || c.a_id::text, 'e:' || c.em), c.a_id nulls last)
  select f.atual, f.a_id, f.c_id, f.em::text, f.nm::text, f.nv::text, f.tc::text, f.mot::text from final f;
end
$$;

-- Placar de uma estratégia (null sem ação). Vendas e receita: negócios GANHOS de pessoas da lista, na linha da
-- ação, fechados depois que a ação nasceu (pega também a venda que caiu no funil de checkout da Hotmart).
create function crm.estrategia_placar(p_id uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
declare e crm.estrategia%rowtype; v_linha text; v_lista int := 0; v_abord int := 0; v_conv int := 0; v_vendas int := 0; v_receita numeric := 0;
begin
  select * into e from crm.estrategia x where x.id = p_id;
  if not found or e.acao_tipo is null then return null; end if;
  if e.acao_tipo = 'fila' then
    select f.linha into v_linha from crm.fila f where f.id = e.fila_id;
    select count(*), count(*) filter (where i.status <> 'a_abordar'),
           count(*) filter (where i.status in ('em_conversa', 'vai_comprar', 'ganho'))
      into v_lista, v_abord, v_conv
      from crm.fila_item i where i.fila_id = e.fila_id;
  else
    select f.linha into v_linha from crm.funil f where f.id = e.funil_id;
    select count(*),
           count(*) filter (where n.status <> 'aberto' or n.ultima_interacao_em is not null
                            or et.ordem > (select min(e2.ordem) from crm.etapa_funil e2 where e2.funil_id = e.funil_id and e2.arquivada_em is null)),
           count(*) filter (where n.status = 'ganho' or (n.status = 'aberto' and et.papel in ('qualificar', 'apresentar_oferta', 'negociar', 'aguardar_pagamento')))
      into v_lista, v_abord, v_conv
      from crm.negocio n join crm.etapa_funil et on et.id = n.etapa_id
     where n.funil_id = e.funil_id;
  end if;
  with lista as (
    select distinct pessoas.atual(i.pessoa_id) id from crm.fila_item i where e.acao_tipo = 'fila' and i.fila_id = e.fila_id
    union
    select distinct pessoas.atual(n.pessoa_id) from crm.negocio n where e.acao_tipo = 'funil' and n.funil_id = e.funil_id),
  ganhos as (
    select n.id, pessoas.atual(n.pessoa_id) pid, coalesce(t.valor_cobrado, n.valor) valor
      from crm.negocio n left join (select * from fin.hotmart_transacoes where conta = 'academy' union all select * from fin.hotmart_transacoes where conta = 'escritorio') t on t.transacao = n.transacao_ganho
     where n.status = 'ganho' and n.linha = v_linha and n.fechado_em >= e.acao_criada_em)
  select count(distinct g.pid), coalesce(sum(g.valor), 0) into v_vendas, v_receita
    from ganhos g where g.pid in (select l.id from lista l);
  return jsonb_build_object('naLista', v_lista, 'abordadas', v_abord, 'emConversa', v_conv, 'vendas', v_vendas,
                            'receita', round(v_receita, 2));
end
$$;

-- Notificação do CRM respeitando a preferência (gatilho 'estrategia' = false desliga).
create function crm.estrategia_notificar(p_perfil uuid, p_ref text, p_titulo text, p_corpo text, p_href text)
returns void language plpgsql set search_path = '' as $$
begin
  if p_perfil is null then return; end if;
  if exists (select 1 from crm.preferencias_notificacao pn where pn.perfil_id = p_perfil and (pn.gatilhos ->> 'estrategia') = 'false') then
    return;
  end if;
  insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
  values (p_perfil, 'estrategia', left(p_ref, 80), left(p_titulo, 200), left(coalesce(p_corpo, ''), 500), p_href)
  on conflict (perfil_id, gatilho, ref_id) do nothing;
end
$$;

-- Pedido em JSON (camelCase), com o placar.
create function crm.estrategia_json(e crm.estrategia)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', e.id, 'titulo', e.titulo, 'objetivo', e.objetivo, 'publico', e.publico, 'filtros', e.filtros, 'modelo', e.modelo,
    'linha', e.linha, 'oferta', e.oferta, 'prazo', e.prazo, 'prioridade', e.prioridade, 'observacoes', e.observacoes,
    'solicitanteId', e.solicitante_id, 'solicitanteNome', crm.nome_perfil(e.solicitante_id),
    'situacao', e.situacao, 'motivoRecusa', e.motivo_recusa,
    'responsavelId', e.responsavel_id, 'responsavelNome', case when e.responsavel_id is not null then crm.nome_perfil(e.responsavel_id) end,
    'acaoTipo', e.acao_tipo, 'filaId', e.fila_id, 'funilId', e.funil_id, 'acaoCriadaEm', e.acao_criada_em,
    'acaoPessoas', e.acao_pessoas, 'criadoEm', e.criado_em, 'atualizadoEm', e.atualizado_em,
    'placar', crm.estrategia_placar(e.id));
$$;

revoke execute on function crm.estr_txt(jsonb), crm.estr_produtos(jsonb), crm.estrategia_validar_filtros(jsonb),
  crm.estrategia_candidatos(jsonb), crm.estrategia_placar(uuid), crm.estrategia_notificar(uuid, text, text, text, text),
  crm.estrategia_json(crm.estrategia) from public, anon, authenticated;

-- 7. RPCs (public, SECURITY DEFINER, guarda interna, {ok,msg}) ----------------------------------------------------
create function public.crm_estrategia_acesso()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('solicitar', coalesce(crm.pode_solicitar_estrategia(), false),
                            'gestor', coalesce(crm.estrategia_eh_gestor(), false));
$$;

create function public.crm_estrategias()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_gestor boolean := coalesce(crm.estrategia_eh_gestor(), false); v_sol boolean := coalesce(crm.pode_solicitar_estrategia(), false); v jsonb;
begin
  if not (v_gestor or v_sol) then raise exception 'Sem acesso às Estratégias.' using errcode = '42501'; end if;
  select coalesce(jsonb_agg(crm.estrategia_json(x.r) order by x.c desc), '[]'::jsonb) into v
    from (select e as r, e.criado_em c from crm.estrategia e
           where v_gestor or e.solicitante_id = auth.uid()
           order by e.criado_em desc limit 200) x;
  return v;
end
$$;

create function public.crm_estrategia_detalhe(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare e crm.estrategia%rowtype;
begin
  if not (coalesce(crm.estrategia_eh_gestor(), false) or coalesce(crm.pode_solicitar_estrategia(), false)) then
    raise exception 'Sem acesso às Estratégias.' using errcode = '42501';
  end if;
  select * into e from crm.estrategia x where x.id = p_id
     and (coalesce(crm.estrategia_eh_gestor(), false) or x.solicitante_id = auth.uid());
  if not found then return null; end if;
  return crm.estrategia_json(e) || jsonb_build_object('historico', coalesce((
    select jsonb_agg(jsonb_build_object('de', h.de, 'para', h.para, 'porNome', case when h.por is not null then crm.nome_perfil(h.por) end,
                                        'nota', h.nota, 'em', h.em) order by h.em, h.id)
      from crm.estrategia_historico h where h.estrategia_id = e.id), '[]'::jsonb));
end
$$;

create function public.crm_estrategia_modelos()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (coalesce(crm.estrategia_eh_gestor(), false) or coalesce(crm.pode_solicitar_estrategia(), false)) then
    raise exception 'Sem acesso às Estratégias.' using errcode = '42501';
  end if;
  return coalesce((select jsonb_agg(jsonb_build_object('chave', m.chave, 'nome', m.nome, 'descricao', m.descricao, 'filtros', m.filtros)
                                    order by m.nome)
                     from crm.estrategia_modelo m where m.ativo), '[]'::jsonb);
end
$$;

-- Opções dos filtros estruturados (sem dado pessoal: só valores de cadastro e textos de pergunta).
create function public.crm_estrategia_opcoes()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not (coalesce(crm.estrategia_eh_gestor(), false) or coalesce(crm.pode_solicitar_estrategia(), false)) then
    raise exception 'Sem acesso às Estratégias.' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'niveis', coalesce((select jsonb_agg(x order by x) from (select distinct a.nivel_resultado x from public.thb_alunos a where a.nivel_resultado is not null) s), '[]'),
    'turmas', coalesce((select jsonb_agg(jsonb_build_object('codigo', t.codigo, 'tipo', t.tipo) order by t.tipo, t.codigo) from public.thb_turmas t), '[]'),
    'planos', coalesce((select jsonb_agg(x order by x) from (select distinct a.plano x from public.thb_alunos a where a.plano is not null and a.plano <> '') s), '[]'),
    'statusAcesso', coalesce((select jsonb_agg(x order by x) from (select distinct a.status_acesso x from public.thb_alunos a where a.status_acesso is not null) s), '[]'),
    'linhas', coalesce((select jsonb_agg(jsonb_build_object('chave', l.chave, 'nome', l.nome, 'escada', l.escada) order by l.ordem) from crm.linha l where l.ativo), '[]'),
    'produtos', coalesce((select jsonb_agg(jsonb_build_object('id', s.produto_id, 'nome', s.nome) order by s.nome) from (
        select distinct on (t.produto_id) t.produto_id, coalesce(pc.nome_comercial, t.produto_nome) nome
          from (select * from fin.hotmart_transacoes where conta = 'academy' union all select * from fin.hotmart_transacoes where conta = 'escritorio') t left join crm.produto_comercial pc on pc.produto_id = t.produto_id
         where t.status in ('APPROVED', 'COMPLETE') and t.produto_nome is not null
         order by t.produto_id, t.aprovado_em desc nulls last) s), '[]'),
    'projetos', coalesce((select jsonb_agg(x order by x) from (select distinct po.projeto x from crm.pessoa_origem po where po.projeto is not null) s), '[]'),
    'canais', coalesce((select jsonb_agg(x order by x) from (select distinct po.canal_entrada x from crm.pessoa_origem po where po.canal_entrada is not null) s), '[]'),
    'perguntas', coalesce((select jsonb_agg(jsonb_build_object('pergunta', s.p, 'formularios', s.n) order by s.n desc, s.p) from (
        select c ->> 'pergunta' p, count(distinct f.slug) n
          from respondi.formularios f, jsonb_array_elements(case jsonb_typeof(f.campos) when 'array' then f.campos else '[]'::jsonb end) c
         where c ->> 'tipo' in ('radio', 'select', 'checkbox', 'text', 'textarea') and length(c ->> 'pergunta') between 5 and 300
         group by 1 order by 2 desc limit 300) s), '[]'));
end
$$;

-- Prévia do público: contagem e motivos de exclusão. Amostra (máscara) só para o gestor.
create function public.crm_estrategia_previa(p_filtros jsonb)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_gestor boolean := coalesce(crm.estrategia_eh_gestor(), false); v_msg text; v jsonb;
begin
  if not (v_gestor or coalesce(crm.pode_solicitar_estrategia(), false)) then
    return crm.res(false, 'Sem acesso às Estratégias.');
  end if;
  v_msg := crm.estrategia_validar_filtros(p_filtros);
  if v_msg is not null then return crm.res(false, v_msg); end if;
  with c as materialized (select * from crm.estrategia_candidatos(p_filtros))
  select jsonb_build_object(
    'ok', true,
    'total', count(*) filter (where c.motivo is null),
    'excluidos', jsonb_build_object(
       'optOut', count(*) filter (where c.motivo = 'opt_out'),
       'jaComprou', count(*) filter (where c.motivo = 'ja_comprou'),
       'emNegociacao', count(*) filter (where c.motivo = 'em_negociacao'),
       'outraAcao', count(*) filter (where c.motivo = 'outra_acao')),
    'amostra', case when v_gestor then coalesce((
       select jsonb_agg(jsonb_build_object(
                'nome', coalesce(nullif(split_part(btrim(a.nome), ' ', 1), ''), 'Sem nome')
                        || case when btrim(a.nome) like '% %' then ' ' || left(regexp_replace(btrim(a.nome), '^.* ', ''), 1) || '.' else '' end,
                'email', pessoas.mascara_email(a.email), 'nivel', a.nivel, 'turma', a.turma))
         from (select * from c where c.motivo is null order by c.nome nulls last limit 8) a), '[]'::jsonb) else '[]'::jsonb end)
  into v from c;
  return v;
exception when invalid_parameter_value then
  return crm.res(false, sqlerrm);
end
$$;

-- Cria (sem id) ou edita (com id, só o próprio pedido ainda "solicitada").
create function public.crm_estrategia_salvar(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_id uuid; v_msg text; v_filtros jsonb; v_modelo text; v_linha text; v_prazo date; v_prio text;
        v_titulo text; e crm.estrategia%rowtype; g record; v_s text; v_c text; v_m text;
begin
  if not coalesce((select c.escrita_ligada from crm.config c), false) then return crm.res(false, 'CRM em manutenção: escrita desligada.'); end if;
  if not coalesce(crm.pode_solicitar_estrategia(), false) then return crm.res(false, 'Sem permissão para solicitar estratégia.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;
  v_titulo := btrim(coalesce(p ->> 'titulo', ''));
  if length(v_titulo) < 3 then return crm.res(false, 'Dê um título ao pedido.'); end if;
  if length(btrim(coalesce(p ->> 'objetivo', ''))) < 3 then return crm.res(false, 'Descreva o objetivo.'); end if;
  v_filtros := coalesce(case when jsonb_typeof(p -> 'filtros') = 'object' then p -> 'filtros' end, '{}'::jsonb);
  if v_filtros <> '{}'::jsonb then
    v_msg := crm.estrategia_validar_filtros(v_filtros);
    if v_msg is not null then return crm.res(false, v_msg); end if;
  end if;
  v_modelo := nullif(btrim(coalesce(p ->> 'modelo', '')), '');
  if v_modelo is not null and not exists (select 1 from crm.estrategia_modelo m where m.chave = v_modelo and m.ativo) then
    return crm.res(false, 'Modelo de público não encontrado.');
  end if;
  v_linha := nullif(btrim(coalesce(p ->> 'linha', '')), '');
  if v_linha is not null and not exists (select 1 from crm.linha l where l.chave = v_linha and l.ativo) then
    return crm.res(false, 'Produto inválido.');
  end if;
  v_prazo := nullif(p ->> 'prazo', '')::date;
  if v_prazo is not null and v_prazo < (now() at time zone 'America/Sao_Paulo')::date then return crm.res(false, 'Prazo no passado.'); end if;
  v_prio := coalesce(nullif(p ->> 'prioridade', ''), 'media');

  if nullif(p ->> 'id', '') is not null then
    select * into e from crm.estrategia x where x.id = crm.uuid_ou_null(p ->> 'id') for update;
    if not found or e.solicitante_id <> v_eu then return crm.res(false, 'Pedido não encontrado.'); end if;
    if e.situacao <> 'solicitada' then return crm.res(false, 'O Comercial já começou a analisar: o pedido não muda mais.'); end if;
    update crm.estrategia x set titulo = v_titulo, objetivo = btrim(p ->> 'objetivo'), publico = coalesce(p ->> 'publico', ''),
           filtros = v_filtros, modelo = v_modelo, linha = v_linha, oferta = nullif(btrim(coalesce(p ->> 'oferta', '')), ''),
           prazo = v_prazo, prioridade = v_prio, observacoes = coalesce(p ->> 'observacoes', ''), atualizado_em = now()
     where x.id = e.id;
    perform crm.log_registrar('editou', 'estrategia', e.id::text, null, format('Editou o pedido de estratégia "%s"', v_titulo));
    return crm.res(true, 'Pedido atualizado.', jsonb_build_object('id', e.id));
  end if;

  insert into crm.estrategia (titulo, objetivo, publico, filtros, modelo, linha, oferta, prazo, prioridade, observacoes, solicitante_id)
  values (v_titulo, btrim(p ->> 'objetivo'), coalesce(p ->> 'publico', ''), v_filtros, v_modelo, v_linha,
          nullif(btrim(coalesce(p ->> 'oferta', '')), ''), v_prazo, v_prio, coalesce(p ->> 'observacoes', ''), v_eu)
  returning id into v_id;
  insert into crm.estrategia_historico (estrategia_id, de, para, por) values (v_id, null, 'solicitada', v_eu);
  perform crm.log_registrar('criou', 'estrategia', v_id::text, null, format('Solicitou a estratégia "%s"', v_titulo));
  -- Gestores do Comercial (mesma regra de crm.estrategia_eh_gestor), menos quem pediu.
  for g in select p2.id from public.perfis p2
            where p2.status = 'ativo' and p2.cargo in ('dev', 'admin', 'gestor') and 'comercial' = any(coalesce(p2.areas, '{}'))
              and p2.id <> v_eu loop
    perform crm.estrategia_notificar(g.id, 'nova:' || v_id, 'Nova solicitação de estratégia: ' || v_titulo,
      'Prioridade ' || v_prio || coalesce(' · prazo ' || to_char(v_prazo, 'DD/MM'), '') || '. Analise e transforme em ação.',
      '/comercial/estrategias?pedido=' || v_id);
  end loop;
  -- Slack #comercial: sem dado pessoal (título, prioridade, prazo e link).
  perform crm.slack_enfileirar('estrategia', v_id::text,
    format(':compass: *Nova solicitação de estratégia* · %s · prioridade %s%s · <https://grupoparticipa.app.br/comercial/estrategias?pedido=%s|Abrir pedido>',
           crm.slack_esc(v_titulo), v_prio, coalesce(' · prazo ' || to_char(v_prazo, 'DD/MM/YYYY'), ''), v_id));
  return crm.res(true, 'Pedido enviado ao Comercial.', jsonb_build_object('id', v_id));
exception when check_violation or foreign_key_violation or not_null_violation or invalid_text_representation
             or invalid_datetime_format or datetime_field_overflow or string_data_right_truncation then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- Gestor muda a situação. Caminho: solicitada → em_analise → em_execucao → concluida; recusada (com motivo) até
-- antes da execução. em_execucao também nasce de crm_estrategia_transformar.
create function public.crm_estrategia_situacao(p_id uuid, p_situacao text, p_nota text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; e crm.estrategia%rowtype; v_nota text := nullif(btrim(coalesce(p_nota, '')), ''); v_ok boolean;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.estrategia_eh_gestor(), false) then return crm.res(false, 'Só o gestor comercial muda a situação.'); end if;
  select * into e from crm.estrategia x where x.id = p_id for update;
  if not found then return crm.res(false, 'Pedido não encontrado.'); end if;
  v_ok := (e.situacao, p_situacao) in (('solicitada', 'em_analise'), ('solicitada', 'recusada'), ('em_analise', 'recusada'),
                                       ('em_analise', 'em_execucao'), ('em_execucao', 'concluida'));
  if not v_ok then return crm.res(false, 'Mudança de situação não permitida.'); end if;
  if p_situacao = 'recusada' and (v_nota is null or length(v_nota) < 3) then return crm.res(false, 'Diga o motivo da recusa.'); end if;
  update crm.estrategia x set situacao = p_situacao, atualizado_em = now(),
         motivo_recusa = case when p_situacao = 'recusada' then left(v_nota, 500) end,
         responsavel_id = coalesce(x.responsavel_id, auth.uid())
   where x.id = e.id;
  insert into crm.estrategia_historico (estrategia_id, de, para, por, nota) values (e.id, e.situacao, p_situacao, auth.uid(), left(v_nota, 500));
  perform crm.log_registrar(case when p_situacao = 'recusada' then 'reprovou' else 'editou' end, 'estrategia', e.id::text, null,
                            format('Estratégia "%s": %s → %s', e.titulo, e.situacao, p_situacao));
  perform crm.estrategia_notificar(e.solicitante_id, e.id || ':' || p_situacao,
    'Sua estratégia "' || left(e.titulo, 80) || '": ' || case p_situacao when 'em_analise' then 'em análise' when 'em_execucao' then 'em execução'
                                                              when 'concluida' then 'concluída' else 'recusada' end,
    coalesce(case when p_situacao = 'recusada' then 'Motivo: ' || v_nota else v_nota end, ''), '/comercial/estrategias?pedido=' || e.id);
  return crm.res(true, 'Situação atualizada.');
end
$$;

-- "Transformar em ação": monta a lista a partir dos filtros e cria a fila de recuperação ou o funil próprio,
-- com as pessoas distribuídas (dono atual da pessoa se ativo; senão distribuição geral). Liga a ação ao pedido.
create function public.crm_estrategia_transformar(p_id uuid, p_tipo text, p_linha text default null, p_filtros jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; e crm.estrategia%rowtype; v_filtros jsonb; v_msg text; v_linha text; v_pids uuid[]; v_n int; v_lim int;
        v_fila uuid; v_funil uuid; v_nome text; v_tem_pesq boolean; v_res jsonb; v_criados int := 0; v_falhas int := 0;
        v_dono uuid; v_pc uuid; c record; d record; v_pid uuid;
        v_vend uuid[]; v_perc numeric[]; v_cnt int[]; v_tot int; v_k int; k int; v_agr uuid;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.estrategia_eh_gestor(), false) then return crm.res(false, 'Só o gestor comercial transforma em ação.'); end if;
  if p_tipo not in ('fila', 'funil') then return crm.res(false, 'Tipo de ação inválido.'); end if;
  select * into e from crm.estrategia x where x.id = p_id for update;
  if not found then return crm.res(false, 'Pedido não encontrado.'); end if;
  if e.acao_tipo is not null then return crm.res(false, 'Este pedido já virou ação.'); end if;
  if e.situacao not in ('solicitada', 'em_analise') then return crm.res(false, 'Pedido recusado ou encerrado não vira ação.'); end if;
  v_filtros := coalesce(p_filtros, e.filtros);
  if v_filtros is null or v_filtros = '{}'::jsonb then return crm.res(false, 'Defina o público (filtros) antes de criar a ação.'); end if;
  v_msg := crm.estrategia_validar_filtros(v_filtros);
  if v_msg is not null then return crm.res(false, v_msg); end if;
  v_linha := coalesce(nullif(btrim(coalesce(p_linha, '')), ''), e.linha);
  if v_linha is null or not exists (select 1 from crm.linha l where l.chave = v_linha and l.ativo) then
    return crm.res(false, 'Escolha o produto (linha) da ação.');
  end if;
  if p_tipo = 'funil' then
    select a.id into v_agr from crm.agrupador a where a.linha = v_linha and a.arquivado_em is null order by a.ordem, a.criado_em limit 1;
    if v_agr is null then return crm.res(false, 'Este produto não tem pasta de funis: crie uma em Funil antes.'); end if;
  end if;
  v_tem_pesq := jsonb_typeof(v_filtros -> 'respondi' -> 'regras') = 'array' and jsonb_array_length(v_filtros -> 'respondi' -> 'regras') > 0;
  v_lim := case when p_tipo = 'fila' then 5000 else 300 end;

  -- Lista: elegíveis; quem ainda não é pessoa no CRM vira pessoa (aluno → comprador → e-mail).
  v_pids := '{}';
  for c in select * from crm.estrategia_candidatos(v_filtros) x where x.motivo is null loop
    v_pid := coalesce(c.pessoa_id,
                      case when c.aluno_id is not null then pessoas.pessoa_do_aluno(c.aluno_id) end,
                      case when c.comprador_id is not null then pessoas.pessoa_do_comprador(c.comprador_id) end,
                      case when c.email is not null then crm.pessoa_por_email(c.email) end);
    if v_pid is not null and not (v_pid = any(v_pids)) then v_pids := v_pids || v_pid; end if;
    if cardinality(v_pids) > v_lim then
      return crm.res(false, case when p_tipo = 'funil'
        then format('Mais de %s pessoas: para funil, refine o público ou crie uma fila de recuperação.', v_lim)
        else format('Mais de %s pessoas: refine o público.', v_lim) end);
    end if;
  end loop;
  v_n := cardinality(v_pids);
  if v_n = 0 then return crm.res(false, 'O público não tem ninguém elegível.'); end if;

  v_nome := 'Estratégia · ' || left(e.titulo, case when p_tipo = 'fila' then 105 else 66 end);
  if p_tipo = 'fila' then
    perform set_config('crm.resumo', format('Montou a fila "%s" (%s) a partir de uma estratégia', v_nome, v_linha), true);
    insert into crm.fila (nome, linha, projeto, criada_por) values (v_nome, v_linha, null, auth.uid()) returning id into v_fila;
    -- Dono único por pessoa: o dono atual (se vendedor ativo); senão, distribuição geral (percentual, saldo do lote).
    select coalesce(array_agg(dd.vendedor_id order by dd.vendedor_id), '{}'), coalesce(array_agg(dd.percentual::numeric order by dd.vendedor_id), '{}')
      into v_vend, v_perc
      from crm.distribuicao dd
     where dd.ativo and dd.percentual > 0 and dd.funil_id is null and crm.vendedor_ativo(dd.vendedor_id);
    v_cnt := array_fill(0, array[greatest(cardinality(v_vend), 1)]);
    foreach v_pid in array v_pids loop
      v_pc := crm.garantir_pc(v_pid);
      v_dono := null;
      select pc.dono_id into v_dono from crm.pessoa_comercial pc
       where pc.pessoa_id = any(pessoas.grupo(v_pid)) and pc.dono_id is not null and crm.vendedor_ativo(pc.dono_id)
       order by pc.pessoa_id = v_pid desc, pc.criado_em limit 1;
      if v_dono is null and cardinality(v_vend) > 0 then
        v_tot := 0;
        for k in 1 .. cardinality(v_vend) loop v_tot := v_tot + v_cnt[k]; end loop;
        v_k := 1;
        for k in 1 .. cardinality(v_vend) loop
          if (v_perc[k] / 100.0) * (v_tot + 1) - v_cnt[k] > (v_perc[v_k] / 100.0) * (v_tot + 1) - v_cnt[v_k] then v_k := k; end if;
        end loop;
        v_dono := v_vend[v_k];
        update crm.pessoa_comercial pc set dono_id = v_dono, atualizado_em = now() where pc.pessoa_id = v_pc and pc.dono_id is null;
      end if;
      if v_dono is not null then
        for k in 1 .. cardinality(v_vend) loop
          if v_vend[k] = v_dono then v_cnt[k] := v_cnt[k] + 1; end if;
        end loop;
      end if;
      insert into crm.fila_item (fila_id, pessoa_id, score, sinais, responsavel_id)
      values (v_fila, v_pid, crm.score_recuperacao(case when v_tem_pesq then array['pesquisa'] else '{}'::text[] end),
              case when v_tem_pesq then array['pesquisa'] else '{}'::text[] end, v_dono)
      on conflict (fila_id, pessoa_id) do nothing;
    end loop;
    select count(*) into v_criados from crm.fila_item i where i.fila_id = v_fila;
    for d in select i.responsavel_id rid, count(*) n from crm.fila_item i where i.fila_id = v_fila and i.responsavel_id is not null group by 1 loop
      perform crm.estrategia_notificar(d.rid, 'acao:' || e.id, 'Estratégia nova na sua carteira: ' || left(e.titulo, 80),
        d.n || ' contato(s) na fila "' || left(v_nome, 120) || '".', '/comercial/estrategias');
    end loop;
  else
    perform set_config('crm.resumo', format('Criou o funil "%s" a partir de uma estratégia', v_nome), true);
    insert into crm.funil (nome, icone, agrupador_id, linha, tipo, criado_por) values (v_nome, 'target', v_agr, v_linha, 'manual', auth.uid()) returning id into v_funil;
    insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor) values
      (v_funil, 0, 'Abordar', 'primeiro_contato', 'neutral'),
      (v_funil, 1, 'Em conversa', 'qualificar', 'cyan'),
      (v_funil, 2, 'Oferta apresentada', 'apresentar_oferta', 'purple'),
      (v_funil, 3, 'Aguardando pagamento', 'aguardar_pagamento', 'yellow'),
      (v_funil, 4, 'Fechado', 'fechado', 'green');
    perform set_config('crm.lote_estrategia', '1', true);
    foreach v_pid in array v_pids loop
      v_res := public.crm_criar_negocio(v_pid, v_funil, null);
      if coalesce((v_res ->> 'ok')::boolean, false) then v_criados := v_criados + 1; else v_falhas := v_falhas + 1; end if;
    end loop;
    perform set_config('crm.lote_estrategia', '', true);
    for d in select n.dono_id rid, count(*) n from crm.negocio n where n.funil_id = v_funil and n.dono_id is not null group by 1 loop
      perform crm.estrategia_notificar(d.rid, 'acao:' || e.id, 'Estratégia nova na sua carteira: ' || left(e.titulo, 80),
        d.n || ' negócio(s) no funil "' || v_nome || '". Primeiro contato hoje.', '/comercial/funil?funil=' || v_funil);
    end loop;
  end if;
  if v_criados = 0 then
    raise exception 'Nenhuma pessoa entrou na ação.' using errcode = 'P0001';
  end if;

  update crm.estrategia x set acao_tipo = p_tipo, fila_id = v_fila, funil_id = v_funil, acao_criada_em = now(), acao_pessoas = v_criados,
         filtros = v_filtros, linha = v_linha, situacao = 'em_execucao', responsavel_id = coalesce(x.responsavel_id, auth.uid()),
         atualizado_em = now()
   where x.id = e.id;
  insert into crm.estrategia_historico (estrategia_id, de, para, por, nota)
  values (e.id, e.situacao, 'em_execucao', auth.uid(),
          format('Virou %s com %s pessoa(s)%s.', case when p_tipo = 'fila' then 'fila de recuperação' else 'funil próprio' end, v_criados,
                 case when v_falhas > 0 then format(' (%s ficaram de fora na criação)', v_falhas) else '' end));
  perform crm.log_registrar('vinculou', 'estrategia', e.id::text, null,
                            format('Estratégia "%s" virou %s com %s pessoa(s)', e.titulo, p_tipo, v_criados));
  perform crm.estrategia_notificar(e.solicitante_id, e.id || ':em_execucao', 'Sua estratégia "' || left(e.titulo, 80) || '": em execução',
    format('%s pessoa(s) na ação. Acompanhe o placar.', v_criados), '/comercial/estrategias?pedido=' || e.id);
  return crm.res(true, format('Ação criada com %s pessoa(s).', v_criados),
                 jsonb_build_object('filaId', v_fila, 'funilId', v_funil, 'pessoas', v_criados, 'falhas', v_falhas));
exception when sqlstate 'P0001' then
  return crm.res(false, sqlerrm);
end
$$;

revoke execute on function public.crm_estrategia_acesso(), public.crm_estrategias(), public.crm_estrategia_detalhe(uuid),
  public.crm_estrategia_modelos(), public.crm_estrategia_opcoes(), public.crm_estrategia_previa(jsonb),
  public.crm_estrategia_salvar(jsonb), public.crm_estrategia_situacao(uuid, text, text),
  public.crm_estrategia_transformar(uuid, text, text, jsonb) from public, anon;
grant execute on function public.crm_estrategia_acesso(), public.crm_estrategias(), public.crm_estrategia_detalhe(uuid),
  public.crm_estrategia_modelos(), public.crm_estrategia_opcoes(), public.crm_estrategia_previa(jsonb),
  public.crm_estrategia_salvar(jsonb), public.crm_estrategia_situacao(uuid, text, text),
  public.crm_estrategia_transformar(uuid, text, text, jsonb) to authenticated;

-- 8. Modelo pronto: "Alunos que querem a própria holding" (caso da Dra. Elaine) ----------------------------------
-- Pesquisas lidas no respondi em 07/10/2026 (perguntas exatas). Escada A já comprada sai (Sessão de Viabilidade,
-- Croqui Estrutural e Holding Familiar do escritório, nas duas contas Hotmart).
insert into crm.estrategia_modelo (chave, nome, descricao, filtros) values (
  'alunos_querem_propria_holding',
  'Alunos que querem a própria holding',
  'Alunos do Time Holding Brasil que, nas pesquisas (Níveis Atingidos 2024–2026, Sessão Estratégica, coleta de opiniões '
  || 'das turmas e cadastros de evento), disseram que querem fazer a própria holding e ainda não compraram Sessão de '
  || 'Viabilidade, Croqui ou a Holding do escritório. Potenciais clientes da escada A.',
  jsonb_build_object(
    'base', 'alunos',
    'alunos', jsonb_build_object('tiposTurma', jsonb_build_array('thb')),
    'respondi', jsonb_build_object('regras', jsonb_build_array(
      jsonb_build_object('perguntas', jsonb_build_array('O seu interesse hoje é:'),
                         'contem', jsonb_build_array('fazer a minha holding')),
      jsonb_build_object('perguntas', jsonb_build_array('Em qual Nível você está hoje?', 'Seu Nível no trabalho com Holding Familiar',
                                                        'Selecione o seu nível atual no trabalho com Holding Familiar',
                                                        'Selecione o seu nível atual com o trabalho com Holding Familiar'),
                         'contem', jsonb_build_array('nível pessoal')),
      jsonb_build_object('perguntas', jsonb_build_array('Qual seu objetivo com Holding Familiar?'),
                         'contem', jsonb_build_array('fazer a minha')),
      jsonb_build_object('perguntas', jsonb_build_array('Qual é o seu interesse em Holding Familiar?'),
                         'contem', jsonb_build_array('minha própria holding')),
      jsonb_build_object('perguntas', jsonb_build_array('1. Por que você ingressou no Treinamento Holding Masters? Qual é o seu objetivo?',
                                                        'Por que você ingressou no Treinamento Holding Masters? Qual era o seu objetivo ao entrar no curso?'),
                         'contem', jsonb_build_array('fazer a minha', 'fazer minha própria', 'fazer minha propria', 'montar minha',
                                                     'montar a minha', 'minha própria holding', 'minha propria holding', 'a própria holding',
                                                     'a propria holding', 'holding da minha família', 'holding da minha familia',
                                                     'nossa holding', 'nossa própria', 'nossa propria')))),
    'naoComprou', jsonb_build_object('produtos', jsonb_build_array('1663254', '1664749', '5238525', '1542521', '5243340', '3595938', '5301413')),
    'excluir', jsonb_build_object('emNegociacao', true, 'outraAcao', true)));

-- 9. Função nova para os 3 solicitantes (soma ao que já têm; não tira nada) ---------------------------------------
update public.perfis p
   set funcoes = array(select distinct x from unnest(coalesce(p.funcoes, '{}') || array['comercial.solicitar_estrategia']) x order by 1)
 where p.email in ('elaine@advmais.com', 'marcio@advmais.com', 'arthur@advmais.com')
   and not ('comercial.solicitar_estrategia' = any(coalesce(p.funcoes, '{}')));

-- ════════════════════════ TESTES (rodam como as pessoas reais, JWT pelo request.jwt.claims) ════════════════════════
create temp table _r (t timestamptz default clock_timestamp(), k text, v jsonb);
create temp table _ids (k text, id uuid);
grant all on _r, _ids to authenticated;

-- A. Estrutura (postgres)
insert into _r (k, v) select 'A_perfis_com_funcao', jsonb_agg(p.email order by p.email) from public.perfis p where 'comercial.solicitar_estrategia' = any(p.funcoes);
insert into _r (k, v) select 'A_rpcs_exec_anon', coalesce(jsonb_agg(p.proname), '[]') from pg_proc p where p.proname like 'crm_estrategia%' and has_function_privilege('anon', p.oid, 'execute');
insert into _r (k, v) select 'A_internas_exec_authenticated', coalesce(jsonb_agg(p.proname), '[]') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'crm' and p.proname in ('estrategia_candidatos', 'estrategia_placar', 'estrategia_notificar', 'estrategia_json', 'estr_txt', 'estr_produtos', 'estrategia_validar_filtros')
    and has_function_privilege('authenticated', p.oid, 'execute');
insert into _r (k, v) select 'A_tabelas_escrita_authenticated', to_jsonb(has_table_privilege('authenticated', 'crm.estrategia', 'insert') or has_table_privilege('authenticated', 'crm.estrategia', 'update'));

-- B. Elaine (dev, sem área comercial, COM a função): solicita
select set_config('request.jwt.claims', '{"sub":"6ed2bfc4-1d69-458d-9954-77a03902c56a","role":"authenticated"}', true);
set local role authenticated;
insert into _r (k, v) select 'B_E_acesso', public.crm_estrategia_acesso();
insert into _r (k, v) select 'B_E_previa_modelo', public.crm_estrategia_previa((select m.filtros from crm.estrategia_modelo m where m.chave = 'alunos_querem_propria_holding'));
insert into _ids select 'p1', (public.crm_estrategia_salvar(jsonb_build_object('titulo', 'Própria holding: alunos THB', 'objetivo', 'Vender Sessão de Viabilidade a alunos que querem a própria holding',
  'publico', 'Alunos do THB que disseram querer fazer a própria holding', 'modelo', 'alunos_querem_propria_holding',
  'filtros', (select m.filtros from crm.estrategia_modelo m where m.chave = 'alunos_querem_propria_holding'),
  'linha', 'sv', 'oferta', 'Sessão de Viabilidade', 'prazo', ((now() at time zone 'America/Sao_Paulo')::date + 14)::text, 'prioridade', 'alta')) ->> 'id')::uuid;
insert into _ids select 'p2', (public.crm_estrategia_salvar(jsonb_build_object('titulo', 'Nível pessoal: SV', 'objetivo', 'Teste de funil próprio',
  'filtros', jsonb_build_object('base', 'alunos', 'alunos', jsonb_build_object('tiposTurma', jsonb_build_array('thb')),
     'respondi', jsonb_build_object('regras', jsonb_build_array(jsonb_build_object('perguntas', jsonb_build_array('Em qual Nível você está hoje?'), 'contem', jsonb_build_array('nível pessoal')))),
     'excluir', jsonb_build_object('outraAcao', false)), 'linha', 'sv', 'prioridade', 'media')) ->> 'id')::uuid;
insert into _ids select 'p3', (public.crm_estrategia_salvar('{"titulo":"Pedido para recusar","objetivo":"Testar a recusa com motivo"}'::jsonb) ->> 'id')::uuid;
insert into _r (k, v) select 'B_E_salvou_3', to_jsonb((select count(*) from _ids where id is not null));
insert into _r (k, v) select 'B_E_salvar_prazo_passado', public.crm_estrategia_salvar('{"titulo":"abc","objetivo":"abc","prazo":"2020-01-01"}');
insert into _r (k, v) select 'B_E_lista_n', to_jsonb(jsonb_array_length(public.crm_estrategias()));
insert into _r (k, v) select 'B_E_situacao_recusada', public.crm_estrategia_situacao((select id from _ids where k = 'p1'), 'em_analise', null);
insert into _r (k, v) select 'B_E_transformar_recusado', public.crm_estrategia_transformar((select id from _ids where k = 'p1'), 'fila', null, null);
insert into _r (k, v) select 'B_E_rls_select', jsonb_build_object('estrategia', (select count(*) from crm.estrategia), 'historico', (select count(*) from crm.estrategia_historico), 'modelo', (select count(*) from crm.estrategia_modelo));
reset role;

-- C. Marcos (vendedor, operador, sem a função): não vê nem pede
select set_config('request.jwt.claims', '{"sub":"9d347183-5395-434e-9e96-2a65dde1a3cd","role":"authenticated"}', true);
set local role authenticated;
insert into _r (k, v) select 'C_M_acesso', public.crm_estrategia_acesso();
do $t$ begin perform public.crm_estrategias(); insert into _r (k, v) values ('C_M_lista', '"VAZOU"');
  exception when insufficient_privilege then insert into _r (k, v) values ('C_M_lista', to_jsonb('42501: ' || sqlerrm)); end $t$;
do $t$ begin perform public.crm_estrategia_detalhe((select id from _ids where k = 'p1')); insert into _r (k, v) values ('C_M_detalhe', '"VAZOU"');
  exception when insufficient_privilege then insert into _r (k, v) values ('C_M_detalhe', to_jsonb('42501: ' || sqlerrm)); end $t$;
insert into _r (k, v) select 'C_M_salvar', public.crm_estrategia_salvar('{"titulo":"xxx","objetivo":"yyy"}');
insert into _r (k, v) select 'C_M_previa', public.crm_estrategia_previa('{"base":"alunos"}');
insert into _r (k, v) select 'C_M_situacao', public.crm_estrategia_situacao((select id from _ids where k = 'p1'), 'em_analise', null);
insert into _r (k, v) select 'C_M_rls_select', jsonb_build_object('estrategia', (select count(*) from crm.estrategia), 'modelo', (select count(*) from crm.estrategia_modelo));
reset role;

-- D. Visualizador ativo (fora do Comercial): recusado em tudo
select set_config('request.jwt.claims', '{"sub":"9d5fb8e7-f61e-459d-be04-d103ec783c08","role":"authenticated"}', true);
set local role authenticated;
insert into _r (k, v) select 'D_V_acesso', public.crm_estrategia_acesso();
do $t$ begin perform public.crm_estrategias(); insert into _r (k, v) values ('D_V_lista', '"VAZOU"');
  exception when insufficient_privilege then insert into _r (k, v) values ('D_V_lista', to_jsonb('42501: ' || sqlerrm)); end $t$;
do $t$ begin perform public.crm_estrategia_opcoes(); insert into _r (k, v) values ('D_V_opcoes', '"VAZOU"');
  exception when insufficient_privilege then insert into _r (k, v) values ('D_V_opcoes', to_jsonb('42501: ' || sqlerrm)); end $t$;
insert into _r (k, v) select 'D_V_salvar', public.crm_estrategia_salvar('{"titulo":"xxx","objetivo":"yyy"}');
insert into _r (k, v) select 'D_V_previa', public.crm_estrategia_previa('{"base":"alunos"}');
insert into _r (k, v) select 'D_V_transformar', public.crm_estrategia_transformar((select id from _ids where k = 'p1'), 'fila', null, null);
insert into _r (k, v) select 'D_V_rls_select', jsonb_build_object('estrategia', (select count(*) from crm.estrategia), 'historico', (select count(*) from crm.estrategia_historico), 'modelo', (select count(*) from crm.estrategia_modelo));
reset role;

-- E. Jonathan (admin + área comercial = gestor comercial): analisa, transforma, recusa
select set_config('request.jwt.claims', '{"sub":"bd5361bc-3c3f-4f85-8b5a-f21433d040e3","role":"authenticated"}', true);
set local role authenticated;
insert into _r (k, v) select 'E_J_acesso', public.crm_estrategia_acesso();
insert into _r (k, v) select 'E_J_lista_n', to_jsonb(jsonb_array_length(public.crm_estrategias()));
insert into _r (k, v) select 'E_J_previa', (select jsonb_build_object('ok', x -> 'ok', 'total', x -> 'total', 'excluidos', x -> 'excluidos', 'amostra_n', jsonb_array_length(x -> 'amostra'),
    'emails_mascarados', (select bool_and(a ->> 'email' like '%*%' or a ->> 'email' is null) from jsonb_array_elements(x -> 'amostra') a),
    'nomes_curtos', (select bool_and(a ->> 'nome' ~ '^\S+( \S\.)?$') from jsonb_array_elements(x -> 'amostra') a))
  from (select public.crm_estrategia_previa((select e.filtros from crm.estrategia e where e.id = (select id from _ids where k = 'p1'))) x) s);
insert into _r (k, v) select 'E_J_em_analise', public.crm_estrategia_situacao((select id from _ids where k = 'p1'), 'em_analise', 'Vamos montar a fila.');
insert into _r (k, v) select 'E_J_volta_invalida', public.crm_estrategia_situacao((select id from _ids where k = 'p1'), 'solicitada', null);
insert into _r (k, v) select 'E_J_transformar_fila', public.crm_estrategia_transformar((select id from _ids where k = 'p1'), 'fila', null, null);
insert into _r (k, v) select 'E_J_transformar_de_novo', public.crm_estrategia_transformar((select id from _ids where k = 'p1'), 'fila', null, null);
insert into _r (k, v) select 'E_J_placar_p1', public.crm_estrategia_detalhe((select id from _ids where k = 'p1')) -> 'placar';
insert into _r (k, v) select 'E_J_previa_depois_da_fila', (select jsonb_build_object('total', x -> 'total', 'excluidos', x -> 'excluidos'))
  from (select public.crm_estrategia_previa((select e.filtros from crm.estrategia e where e.id = (select id from _ids where k = 'p1'))) x) s;
insert into _r (k, v) select 'E_J_transformar_funil', public.crm_estrategia_transformar((select id from _ids where k = 'p2'), 'funil', null, null);
insert into _r (k, v) select 'E_J_placar_p2', public.crm_estrategia_detalhe((select id from _ids where k = 'p2')) -> 'placar';
insert into _r (k, v) select 'E_J_recusa_sem_motivo', public.crm_estrategia_situacao((select id from _ids where k = 'p3'), 'recusada', null);
insert into _r (k, v) select 'E_J_recusa', public.crm_estrategia_situacao((select id from _ids where k = 'p3'), 'recusada', 'Fora do foco deste trimestre');
insert into _r (k, v) select 'E_J_concluir_p1', public.crm_estrategia_situacao((select id from _ids where k = 'p1'), 'concluida', null);
insert into _r (k, v) select 'E_J_rls_select', jsonb_build_object('estrategia', (select count(*) from crm.estrategia));
reset role;
set constraints all immediate;   -- dispara os gatilhos adiados (soma da distribuição do funil novo)

-- F. Elaine de novo: acompanha o andamento, não edita depois da análise
select set_config('request.jwt.claims', '{"sub":"6ed2bfc4-1d69-458d-9954-77a03902c56a","role":"authenticated"}', true);
set local role authenticated;
insert into _r (k, v) select 'F_E_situacoes', (select jsonb_object_agg(x ->> 'titulo', x ->> 'situacao') from jsonb_array_elements(public.crm_estrategias()) x);
insert into _r (k, v) select 'F_E_historico_p1', (select jsonb_agg(h ->> 'para') from jsonb_array_elements(public.crm_estrategia_detalhe((select id from _ids where k = 'p1')) -> 'historico') h);
insert into _r (k, v) select 'F_E_placar_p1', public.crm_estrategia_detalhe((select id from _ids where k = 'p1')) -> 'placar';
insert into _r (k, v) select 'F_E_editar_p1', public.crm_estrategia_salvar(jsonb_build_object('id', (select id from _ids where k = 'p1'), 'titulo', 'mudar', 'objetivo', 'mudar'));
insert into _r (k, v) select 'F_E_previa_sem_amostra', to_jsonb(jsonb_array_length(public.crm_estrategia_previa((select m.filtros from crm.estrategia_modelo m where m.chave = 'alunos_querem_propria_holding')) -> 'amostra'));
reset role;

-- G. Efeitos no dado (postgres)
insert into _r (k, v) select 'G_notif_nova_para', (select jsonb_agg(distinct crm.nome_perfil(n.perfil_id)) from crm.notificacao n where n.gatilho = 'estrategia' and n.ref_id = 'nova:' || (select id from _ids where k = 'p1'));
insert into _r (k, v) select 'G_notif_solicitante', (select jsonb_agg(n.titulo order by n.id) from crm.notificacao n where n.gatilho = 'estrategia' and n.perfil_id = '6ed2bfc4-1d69-458d-9954-77a03902c56a');
insert into _r (k, v) select 'G_slack', (select jsonb_build_object('n', count(*), 'tem_arroba', bool_or(s.texto like '%@%'), 'ex', min(regexp_replace(s.texto, 'pedido=[0-9a-f-]+', 'pedido=…'))) from crm.slack_fila s where s.tipo = 'estrategia');
insert into _r (k, v) select 'G_fila_por_responsavel', (select jsonb_object_agg(coalesce(crm.nome_perfil(i.responsavel_id), 'sem'), i.n) from (select i.responsavel_id, count(*) n from crm.fila_item i join crm.estrategia e on e.fila_id = i.fila_id where e.id = (select id from _ids where k = 'p1') group by 1) i);
insert into _r (k, v) select 'G_funil_por_dono', (select jsonb_object_agg(coalesce(crm.nome_perfil(n.dono_id), 'sem'), n.q) from (select n.dono_id, count(*) q from crm.negocio n join crm.estrategia e on e.funil_id = n.funil_id where e.id = (select id from _ids where k = 'p2') group by 1) n);
insert into _r (k, v) select 'G_lead_novo_do_lote', to_jsonb((select count(*) from crm.notificacao x where x.gatilho = 'lead_novo' and x.ref_id in (select n.id::text from crm.negocio n join crm.estrategia e on e.funil_id = n.funil_id where e.id = (select id from _ids where k = 'p2'))));
insert into _r (k, v) select 'G_resumo_vendedores', (select jsonb_agg(crm.nome_perfil(n.perfil_id) || ': ' || n.corpo) from crm.notificacao n where n.gatilho = 'estrategia' and n.ref_id like 'acao:%');
insert into _r (k, v) select 'G_dono_unico', to_jsonb((select count(*) from crm.fila_item i join crm.estrategia e on e.fila_id = i.fila_id
   join crm.pessoa_comercial pc on pc.pessoa_id = i.pessoa_id where e.id = (select id from _ids where k = 'p1') and pc.dono_id is distinct from i.responsavel_id));
insert into _r (k, v) select 'G_log', (select jsonb_agg(l.acao || ': ' || l.resumo order by l.id) from crm.log l where l.entidade = 'estrategia');
select set_config('request.jwt.claims', '{"sub":"bd5361bc-3c3f-4f85-8b5a-f21433d040e3","role":"authenticated"}', true);
set local role authenticated;
insert into _r (k, v) select 'H_J_opcoes', (select jsonb_object_agg(k, jsonb_array_length(o -> k)) from (select public.crm_estrategia_opcoes() o) s, jsonb_object_keys(s.o) k);
insert into _r (k, v) select 'H_J_modelos', (select jsonb_agg(m ->> 'nome') from jsonb_array_elements(public.crm_estrategia_modelos()) m);
reset role;
select k, v from _r order by t;
rollback;
