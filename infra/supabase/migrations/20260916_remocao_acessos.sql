-- =====================================================================
-- 20260916_remocao_acessos
-- Módulo "Remoção de Acessos": quem pede reembolso ou dá chargeback no
-- Holding Masters vira um CASO, e a remoção dos acessos passa a ter dono,
-- prazo e registro.
--
-- Pedido do Victor (16/09/2026). O ciclo:
--   1. A compra de HM muda para REFUNDED ou CHARGEBACK (o webhook da Hotmart
--      já grava isso em public.compras) → nasce um caso "aguardando triagem",
--      com prazo de 1 dia útil (sexta 12h → segunda 12h; fora do horário útil
--      9h-18h, conta a partir da próxima abertura; feriado não conta).
--      PROTESTED/DISPUTE (disputa) vira só ALERTA, sem checklist.
--   2. TRIAGEM, só o triador (Victor): "mantém acesso antigo" fecha o caso;
--      "remover acessos" gera o checklist.
--   3. CHECKLIST por pessoa (titular e cada sócio): cada item tem UM
--      responsável, e só ele marca. O triador pode corrigir, e fica registrado.
--   4. Último item marcado → caso concluído.
--
-- Padrão do sistema: tabelas fechadas (RLS ligado, sem política) e todo
-- acesso por função SECURITY DEFINER com a trava dentro (igual ao financeiro).
-- O n8n lê a fila por duas funções liberadas ao anon que exigem um segredo
-- guardado em ra_config (tabela que ninguém lê pelo PostgREST).
--
-- Só HM por decisão do Victor (Diamante e Aurum ficam fora).
-- Começa do zero: o gatilho só age em mudanças daqui para frente.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Tabelas
-- ---------------------------------------------------------------------
create table if not exists public.ra_feriados (
  data date primary key,
  nome text not null
);

-- Feriados nacionais, mais Carnaval (segunda e terça) e Corpus Christi,
-- que o Victor decidiu contar como feriado (16/09/2026).
insert into public.ra_feriados (data, nome) values
  ('2026-01-01', 'Confraternização Universal'), ('2026-04-03', 'Sexta-feira Santa'),
  ('2026-04-21', 'Tiradentes'), ('2026-05-01', 'Dia do Trabalho'),
  ('2026-09-07', 'Independência'), ('2026-10-12', 'Nossa Senhora Aparecida'),
  ('2026-11-02', 'Finados'), ('2026-11-15', 'Proclamação da República'),
  ('2026-11-20', 'Dia Nacional de Zumbi e da Consciência Negra'), ('2026-12-25', 'Natal'),
  ('2027-01-01', 'Confraternização Universal'), ('2027-03-26', 'Sexta-feira Santa'),
  ('2027-04-21', 'Tiradentes'), ('2027-05-01', 'Dia do Trabalho'),
  ('2027-09-07', 'Independência'), ('2027-10-12', 'Nossa Senhora Aparecida'),
  ('2027-11-02', 'Finados'), ('2027-11-15', 'Proclamação da República'),
  ('2027-11-20', 'Dia Nacional de Zumbi e da Consciência Negra'), ('2027-12-25', 'Natal'),
  ('2026-02-16', 'Carnaval (segunda)'), ('2026-02-17', 'Carnaval (terça)'), ('2026-06-04', 'Corpus Christi'),
  ('2027-02-08', 'Carnaval (segunda)'), ('2027-02-09', 'Carnaval (terça)'), ('2027-05-27', 'Corpus Christi')
on conflict (data) do nothing;

-- Configuração privada: segredo do n8n, triador e endereço do sistema.
create table if not exists public.ra_config (
  chave text primary key,
  valor text not null,
  atualizado_em timestamptz not null default now()
);
insert into public.ra_config (chave, valor) values
  ('slack_segredo', replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  ('triador_id', '81d2eaee-cce1-4058-8714-439b0fc6f970'),           -- Victor Hugo
  ('app_url', 'https://grupoparticipa.app.br')
on conflict (chave) do nothing;

-- Quem é quem no Slack (para marcar nas mensagens).
create table if not exists public.ra_slack (
  perfil_id uuid primary key references public.perfis(id) on delete cascade,
  slack_id text not null
);
insert into public.ra_slack (perfil_id, slack_id) values
  ('81d2eaee-cce1-4058-8714-439b0fc6f970', 'U0AQ4H2GZ0T')          -- Victor Hugo
on conflict (perfil_id) do nothing;

-- Catálogo do checklist: cada item tem UM responsável.
create table if not exists public.ra_itens_catalogo (
  item text primary key,
  rotulo text not null,
  responsavel_id uuid references public.perfis(id),
  ordem int not null,
  so_programa boolean not null default false,   -- só se o aluno é do Programa de Implementação
  ativo boolean not null default true
);
insert into public.ra_itens_catalogo (item, rotulo, responsavel_id, ordem, so_programa) values
  ('searchie',            'Searchie',                              '998e69ce-0c71-409f-b267-b8409889b640', 10, false), -- Thomas
  ('obvio',               'Obvio',                                 '998e69ce-0c71-409f-b267-b8409889b640', 20, false), -- Thomas
  ('grupo_informes',      'Grupo de informes',                     'e303b8d1-e31a-4539-a450-259a8cb1d71a', 30, false), -- Ana Camila
  ('comunidade_facebook', 'Comunidade no Facebook',                'e303b8d1-e31a-4539-a450-259a8cb1d71a', 40, false), -- Ana Camila
  ('sistema_programa',    'Sistema do Programa de Implementação',  '843d43db-73b3-44a9-b449-1731e362dbc3', 50, true),  -- João
  ('central_planilha',    'Central de Alunos (planilha)', '81d2eaee-cce1-4058-8714-439b0fc6f970', 60, false), -- Victor
  ('central_sistema',     'Base de Alunos (sistema)',              '81d2eaee-cce1-4058-8714-439b0fc6f970', 70, false)  -- Victor
on conflict (item) do nothing;

create table if not exists public.ra_casos (
  id uuid primary key default gen_random_uuid(),
  compra_id uuid not null references public.compras(id),
  hotmart_transaction text not null,
  tipo text not null check (tipo in ('reembolso', 'chargeback', 'disputa')),
  status text not null check (status in ('alerta', 'aguardando_triagem', 'mantem_acesso', 'em_remocao', 'concluido')),
  produto_nome text,
  oferta_codigo text,
  valor numeric,
  comprador_id uuid,
  aluno_id uuid references public.thb_alunos(id),
  nome text,
  email text,
  telefone text,
  documento text,
  ocorrido_em timestamptz not null,
  prazo_em timestamptz,
  eh_programa boolean not null default false,
  sugestao jsonb not null default '{}'::jsonb,
  decisao_obs text,
  triado_por uuid references public.perfis(id),
  triado_em timestamptz,
  concluido_em timestamptz,
  slack_ts text,
  slack_avisos jsonb not null default '{}'::jsonb,
  criado_em timestamptz not null default now(),
  unique (hotmart_transaction, tipo)
);
create index if not exists idx_ra_casos_status on public.ra_casos (status, prazo_em);

create table if not exists public.ra_pessoas (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references public.ra_casos(id) on delete cascade,
  aluno_id uuid references public.thb_alunos(id),
  nome text,
  email text,
  papel text not null check (papel in ('titular', 'socio')),
  ordem int not null default 0
);
create index if not exists idx_ra_pessoas_caso on public.ra_pessoas (caso_id);

create table if not exists public.ra_itens (
  id uuid primary key default gen_random_uuid(),
  caso_id uuid not null references public.ra_casos(id) on delete cascade,
  pessoa_id uuid not null references public.ra_pessoas(id) on delete cascade,
  item text not null references public.ra_itens_catalogo(item),
  responsavel_id uuid references public.perfis(id),
  situacao text not null default 'pendente' check (situacao in ('pendente', 'feito', 'nao_se_aplica')),
  marcado_por uuid references public.perfis(id),
  marcado_em timestamptz,
  corrigido boolean not null default false,
  obs text,
  unique (pessoa_id, item)
);
create index if not exists idx_ra_itens_caso on public.ra_itens (caso_id);
create index if not exists idx_ra_itens_resp on public.ra_itens (responsavel_id, situacao);

create table if not exists public.ra_historico (
  id bigserial primary key,
  caso_id uuid not null references public.ra_casos(id) on delete cascade,
  acao text not null,
  por uuid references public.perfis(id),
  em timestamptz not null default now(),
  detalhe jsonb not null default '{}'::jsonb
);
create index if not exists idx_ra_historico_caso on public.ra_historico (caso_id, em);

-- Tabelas fechadas: só as funções abaixo leem e escrevem.
do $$
declare t text;
begin
  foreach t in array array['ra_feriados','ra_config','ra_slack','ra_itens_catalogo','ra_casos','ra_pessoas','ra_itens','ra_historico'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2) Permissões
-- ---------------------------------------------------------------------
create or replace function public.ra_pode_ver()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.perfis p
    where p.id = (select auth.uid()) and p.status = 'ativo'
      and (p.cargo in ('dev', 'admin')
           or (p.cargo in ('gestor', 'operador') and 'remocao_acessos' = any(coalesce(p.areas, '{}'))))
  );
$$;

create or replace function public.ra_eh_triador()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.ra_config c
    join public.perfis p on p.id = c.valor::uuid and p.status = 'ativo'
    where c.chave = 'triador_id' and c.valor::uuid = (select auth.uid())
  );
$$;

-- ---------------------------------------------------------------------
-- 3) Prazo em dia útil
-- ---------------------------------------------------------------------
create or replace function public.ra_dia_util(p_dia date)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select extract(isodow from p_dia) < 6
     and not exists (select 1 from public.ra_feriados f where f.data = p_dia);
$$;

-- Regra do Victor: 24h contadas só em dia útil. Reembolso na sexta 12h vence
-- na segunda 12h. Fora do horário útil (9h-18h) ou em dia não útil, a contagem
-- começa na próxima abertura (9h do próximo dia útil).
create or replace function public.ra_calcular_prazo(p_quando timestamptz)
returns timestamptz language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_local timestamp := p_quando at time zone 'America/Sao_Paulo';
  v_dia date := v_local::date;
  v_hora time := v_local::time;
  v_inicio timestamp;
  v_alvo date;
begin
  if public.ra_dia_util(v_dia) and v_hora >= time '09:00' and v_hora < time '18:00' then
    v_inicio := v_local;
  else
    if not public.ra_dia_util(v_dia) or v_hora >= time '18:00' then
      v_dia := v_dia + 1;
      while not public.ra_dia_util(v_dia) loop v_dia := v_dia + 1; end loop;
    end if;
    v_inicio := v_dia + time '09:00';
  end if;
  v_alvo := v_inicio::date + 1;
  while not public.ra_dia_util(v_alvo) loop v_alvo := v_alvo + 1; end loop;
  return (v_alvo + v_inicio::time) at time zone 'America/Sao_Paulo';
end $$;

-- ---------------------------------------------------------------------
-- 4) Sugestão da triagem
-- ---------------------------------------------------------------------
-- O sistema NÃO decide: mostra a evidência. A decisão é do triador.
create or replace function public.ra_montar_sugestao(p_compra_id uuid, p_aluno_id uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_compra public.compras%rowtype;
  v_comprador public.compradores%rowtype;
  v_aluno public.thb_alunos%rowtype;
  v_turma text;
  v_anteriores jsonb;
  v_historico jsonb := '[]'::jsonb;
  v_aluno_json jsonb;
  v_recomendacao text;
  v_motivo text;
begin
  select * into v_compra from public.compras where id = p_compra_id;
  select * into v_comprador from public.compradores where id = v_compra.comprador_id;

  -- Outras compras que dão acesso ao THB (HM e Aurum; ingresso de HT não conta).
  select coalesce(jsonb_agg(jsonb_build_object(
           'transacao', c.hotmart_transaction, 'produto', c.produto_nome, 'oferta', c.oferta_codigo,
           'valor', c.preco, 'status', c.status, 'data', c.data_compra) order by c.data_compra), '[]'::jsonb)
    into v_anteriores
    from public.compras c
    join public.compradores cp on cp.id = c.comprador_id
   where c.id <> v_compra.id
     and c.status in ('APPROVED', 'COMPLETED', 'COMPLETE')
     and c.produto_id in ('5064314', '3507214', '3094405')
     and (c.comprador_id = v_compra.comprador_id
          or (coalesce(v_comprador.email, '') <> '' and lower(trim(cp.email)) = lower(trim(v_comprador.email)))
          or (length(regexp_replace(coalesce(v_comprador.documento, ''), '\D', '', 'g')) >= 11
              and regexp_replace(coalesce(cp.documento, ''), '\D', '', 'g') = regexp_replace(v_comprador.documento, '\D', '', 'g')));

  if p_aluno_id is not null then
    select * into v_aluno from public.thb_alunos where id = p_aluno_id;
    select t.codigo into v_turma from public.thb_turmas t where t.id = v_aluno.turma_id;
    v_aluno_json := jsonb_build_object(
      'instrucao', v_aluno.instrucao, 'espaco', v_aluno.espaco_instrucao, 'turma', v_turma,
      'data_expiracao', v_aluno.data_expiracao, 'data_entrada_thb', v_aluno.data_entrada_thb,
      'status_central', v_aluno.status_acesso_central, 'eh_socio', v_aluno.eh_socio);
    select coalesce(jsonb_agg(jsonb_build_object('de', l.valor_anterior, 'para', l.valor_novo,
             'origem', l.origem, 'em', l.criado_em) order by l.criado_em desc), '[]'::jsonb)
      into v_historico
      from (select * from public.thb_alunos_audit_log
             where aluno_id = p_aluno_id and campo = 'data_expiracao'
             order by criado_em desc limit 5) l;
  end if;

  if jsonb_array_length(v_anteriores) > 0
     or (v_aluno.data_entrada_thb is not null
         and v_aluno.data_entrada_thb < (v_compra.data_compra at time zone 'America/Sao_Paulo')::date) then
    v_recomendacao := 'verificar';
    v_motivo := 'Já era aluno antes desta compra: conferir se o acesso antigo ainda vale hoje.';
  elsif p_aluno_id is null then
    v_recomendacao := 'remover';
    v_motivo := 'Não há aluno na base nem outra compra de HM ou Aurum no sistema.';
  else
    v_recomendacao := 'remover';
    v_motivo := 'Entrou por esta compra e não há outra compra de HM ou Aurum no sistema.';
  end if;

  return jsonb_build_object(
    'recomendacao', v_recomendacao,
    'motivo', v_motivo,
    'compras_anteriores', v_anteriores,
    'aluno', v_aluno_json,
    'historico_expiracao', v_historico,
    'aviso', 'O histórico de compras do sistema começa em 13/03/2026. Compras anteriores estão na Central (planilha).'
  );
end $$;

-- Valor em reais no padrão brasileiro (R$ 8.997,00).
create or replace function public.ra_brl(p_valor numeric)
returns text language sql immutable set search_path to 'public' as $$
  select case when p_valor is null then 'sem valor'
              else 'R$ ' || translate(to_char(p_valor, 'FM999,999,990.00'), ',.', '.,') end;
$$;

-- ---------------------------------------------------------------------
-- 5) Abrir o caso
-- ---------------------------------------------------------------------
create or replace function public.ra_abrir_caso(p_compra_id uuid, p_tipo text)
returns uuid language plpgsql security definer set search_path to 'public' as $$
declare
  v_compra public.compras%rowtype;
  v_comprador public.compradores%rowtype;
  v_titular public.thb_alunos%rowtype;
  v_caso uuid;
  v_quando timestamptz;
  v_programa boolean;
  v_ordem int := 1;
  r record;
begin
  select * into v_compra from public.compras where id = p_compra_id;
  if not found then return null; end if;
  select * into v_comprador from public.compradores where id = v_compra.comprador_id;

  -- Titular: pelo comprador, depois e-mail, depois documento. Quem está fora da Central fica por último.
  select a.* into v_titular
    from public.thb_alunos a
   where a.comprador_id = v_compra.comprador_id
      or (coalesce(v_comprador.email, '') <> '' and lower(trim(a.email)) = lower(trim(v_comprador.email)))
      or (length(regexp_replace(coalesce(v_comprador.documento, ''), '\D', '', 'g')) >= 11
          and regexp_replace(coalesce(a.documento, ''), '\D', '', 'g') = regexp_replace(v_comprador.documento, '\D', '', 'g'))
   order by (a.comprador_id = v_compra.comprador_id) desc nulls last,
            (coalesce(a.status_acesso_central, '') in ('Ativo','Ativo (cortesia)','A vencer','Vencido','Acompanha titular','Verificar')) desc,
            a.eh_socio asc nulls first
   limit 1;

  v_quando := coalesce(v_compra.atualizado_em, now());
  -- Programa de Implementação = espaço do titular na base. O cadastro de ofertas não
  -- é confiável para isso (mistura código e descrição), então o triador pode ajustar.
  v_programa := coalesce(v_titular.espaco_instrucao = 'holding_masters_implementacao', false);

  insert into public.ra_casos (
    compra_id, hotmart_transaction, tipo, status, produto_nome, oferta_codigo, valor,
    comprador_id, aluno_id, nome, email, telefone, documento, ocorrido_em, prazo_em, eh_programa, sugestao)
  values (
    v_compra.id, v_compra.hotmart_transaction, p_tipo,
    case when p_tipo = 'disputa' then 'alerta' else 'aguardando_triagem' end,
    v_compra.produto_nome, v_compra.oferta_codigo, v_compra.preco,
    v_compra.comprador_id, v_titular.id,
    coalesce(v_titular.nome, v_comprador.nome), coalesce(v_comprador.email, v_titular.email),
    coalesce(v_comprador.telefone, v_titular.telefone), coalesce(v_comprador.documento, v_titular.documento),
    v_quando,
    case when p_tipo = 'disputa' then null else public.ra_calcular_prazo(v_quando) end,
    v_programa,
    public.ra_montar_sugestao(v_compra.id, v_titular.id))
  on conflict (hotmart_transaction, tipo) do nothing
  returning id into v_caso;

  if v_caso is null then return null; end if;

  insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
  values (v_caso, v_titular.id, coalesce(v_titular.nome, v_comprador.nome),
          coalesce(v_titular.email, v_comprador.email), 'titular', 0);

  if v_titular.id is not null then
    for r in
      select s.id, s.nome, s.email
        from public.thb_alunos s
       where s.id <> v_titular.id
         and coalesce(s.status_acesso_central, '') in ('Ativo','Ativo (cortesia)','A vencer','Vencido','Acompanha titular','Verificar')
         and (s.socio_de_aluno_id = v_titular.id
              or (s.eh_socio and s.socio_de_aluno_id is null
                  and lower(trim(coalesce(s.socio_de_nome, ''))) = lower(trim(v_titular.nome))))
       order by s.nome
    loop
      insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
      values (v_caso, r.id, r.nome, r.email, 'socio', v_ordem);
      v_ordem := v_ordem + 1;
    end loop;
  end if;

  insert into public.ra_historico (caso_id, acao, detalhe)
  values (v_caso, 'aberto', jsonb_build_object('tipo', p_tipo, 'status_compra', v_compra.status,
                                               'evento', v_compra.hotmart_event));
  return v_caso;
end $$;

-- Gatilho: roda depois dos 8 gatilhos que já existem (ordem alfabética) e
-- NUNCA derruba a gravação da compra: se falhar, só registra o aviso.
create or replace function public.ra_fn_compra_status()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare v_tipo text;
begin
  if tg_op = 'UPDATE' and new.status is not distinct from old.status then return new; end if;
  v_tipo := case upper(coalesce(new.status, ''))
              when 'REFUNDED' then 'reembolso'
              when 'CHARGEBACK' then 'chargeback'
              when 'PROTESTED' then 'disputa'
              when 'DISPUTE' then 'disputa'
              else null end;
  if v_tipo is null then return new; end if;
  if not (coalesce(new.produto_id, '') in ('5064314', '3507214')
          or coalesce(new.produto_nome, '') ilike '%holding masters%') then
    return new;
  end if;
  begin
    perform public.ra_abrir_caso(new.id, v_tipo);
  exception when others then
    raise warning 'ra_abrir_caso falhou para % (%): %', new.hotmart_transaction, v_tipo, sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists trg_zzzz_ra_caso on public.compras;
create trigger trg_zzzz_ra_caso
  after insert or update of status on public.compras
  for each row execute function public.ra_fn_compra_status();

-- ---------------------------------------------------------------------
-- 6) Ações da tela
-- ---------------------------------------------------------------------
create or replace function public.ra_triar(p_caso uuid, p_decisao text, p_obs text default null,
                                           p_programa boolean default null)
returns json language plpgsql security definer set search_path to 'public' as $$
declare
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem decide este passo.');
  end if;
  select * into v_caso from public.ra_casos where id = p_caso for update;
  if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
  if v_caso.status <> 'aguardando_triagem' then
    return json_build_object('ok', false, 'msg', 'Este caso já foi triado.');
  end if;
  if p_programa is not null and p_programa is distinct from v_caso.eh_programa then
    update public.ra_casos set eh_programa = p_programa where id = p_caso;
    v_caso.eh_programa := p_programa;
  end if;

  if p_decisao = 'manter' then
    update public.ra_casos
       set status = 'mantem_acesso', triado_por = v_uid, triado_em = now(),
           decisao_obs = nullif(trim(coalesce(p_obs, '')), ''), concluido_em = now()
     where id = p_caso;
  elsif p_decisao = 'remover' then
    update public.ra_casos
       set status = 'em_remocao', triado_por = v_uid, triado_em = now(),
           decisao_obs = nullif(trim(coalesce(p_obs, '')), '')
     where id = p_caso;
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select p_caso, p.id, c.item, c.responsavel_id
      from public.ra_pessoas p
      cross join public.ra_itens_catalogo c
     where p.caso_id = p_caso and c.ativo and (not c.so_programa or v_caso.eh_programa)
    on conflict (pessoa_id, item) do nothing;
  else
    return json_build_object('ok', false, 'msg', 'Decisão inválida.');
  end if;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (p_caso, 'triagem', v_uid, jsonb_build_object('decisao', p_decisao, 'obs', p_obs, 'programa', v_caso.eh_programa));
  return json_build_object('ok', true, 'msg', case when p_decisao = 'manter'
    then 'Caso encerrado: a pessoa mantém o acesso antigo.'
    else 'Remoção liberada para os responsáveis.' end);
end $$;

create or replace function public.ra_marcar_item(p_item uuid, p_situacao text, p_obs text default null)
returns json language plpgsql security definer set search_path to 'public' as $$
declare
  v_item public.ra_itens%rowtype;
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
  v_triador boolean := public.ra_eh_triador();
  v_pendentes int;
begin
  if not public.ra_pode_ver() then
    return json_build_object('ok', false, 'msg', 'Sem acesso ao módulo Remoção de Acessos.');
  end if;
  if p_situacao not in ('pendente', 'feito', 'nao_se_aplica') then
    return json_build_object('ok', false, 'msg', 'Situação inválida.');
  end if;
  select * into v_item from public.ra_itens where id = p_item for update;
  if not found then return json_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
  if not (v_item.responsavel_id = v_uid or v_triador) then
    return json_build_object('ok', false, 'msg', 'Este item é de outro responsável.');
  end if;
  select * into v_caso from public.ra_casos where id = v_item.caso_id for update;
  if v_caso.status not in ('em_remocao', 'concluido') then
    return json_build_object('ok', false, 'msg', 'A remoção deste caso ainda não foi liberada.');
  end if;

  update public.ra_itens
     set situacao = p_situacao,
         marcado_por = case when p_situacao = 'pendente' then null else v_uid end,
         marcado_em = case when p_situacao = 'pendente' then null else now() end,
         corrigido = (v_item.responsavel_id is distinct from v_uid),
         obs = nullif(trim(coalesce(p_obs, '')), '')
   where id = p_item;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (v_item.caso_id, 'item', v_uid, jsonb_build_object(
    'item', v_item.item, 'pessoa_id', v_item.pessoa_id, 'situacao', p_situacao,
    'correcao', v_item.responsavel_id is distinct from v_uid, 'obs', p_obs));

  select count(*) into v_pendentes from public.ra_itens where caso_id = v_item.caso_id and situacao = 'pendente';
  if v_pendentes = 0 and v_caso.status = 'em_remocao' then
    update public.ra_casos set status = 'concluido', concluido_em = now() where id = v_item.caso_id;
    insert into public.ra_historico (caso_id, acao, por) values (v_item.caso_id, 'concluido', v_uid);
  elsif v_pendentes > 0 and v_caso.status = 'concluido' then
    update public.ra_casos set status = 'em_remocao', concluido_em = null where id = v_item.caso_id;
    insert into public.ra_historico (caso_id, acao, por) values (v_item.caso_id, 'reaberto', v_uid);
  end if;
  return json_build_object('ok', true, 'msg', 'Registrado.');
end $$;

-- ---------------------------------------------------------------------
-- 7) Leitura da tela
-- ---------------------------------------------------------------------
create or replace function public.ra_meu_papel()
returns json language sql stable security definer set search_path to 'public' as $$
  select json_build_object(
    'pode_ver', public.ra_pode_ver(),
    'pode_triar', public.ra_eh_triador(),
    'pode_configurar', public.gp_is_admin(),
    'meus_itens', coalesce((select json_agg(c.rotulo order by c.ordem) from public.ra_itens_catalogo c
                             where c.ativo and c.responsavel_id = (select auth.uid())), '[]'::json));
$$;

create or replace function public.ra_fila()
returns setof json language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := (select auth.uid()); v_doc boolean;
begin
  if not public.ra_pode_ver() then return; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  return query
    select to_json(x) from (
      select c.id, c.tipo, c.status, c.nome, c.email, c.produto_nome, c.oferta_codigo, c.valor,
             c.hotmart_transaction, c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa,
             public.mask_sensivel(c.documento, v_doc) as documento,
             c.sugestao->>'recomendacao' as recomendacao,
             (select count(*) from public.ra_pessoas p where p.caso_id = c.id) as pessoas,
             (select count(*) from public.ra_itens i where i.caso_id = c.id) as itens_total,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao <> 'pendente') as itens_feitos,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao = 'pendente'
                and i.responsavel_id = v_uid) as meus_pendentes
        from public.ra_casos c
       order by case c.status when 'aguardando_triagem' then 0 when 'em_remocao' then 1 when 'alerta' then 2 else 3 end,
                c.prazo_em nulls last, c.ocorrido_em desc
    ) x;
end $$;

create or replace function public.ra_caso(p_caso uuid)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare v_uid uuid := (select auth.uid()); v_doc boolean; v_triador boolean;
begin
  if not public.ra_pode_ver() then return null; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  v_triador := public.ra_eh_triador();
  return (
    select json_build_object(
      'caso', (select to_json(y) from (
                 select c.id, c.tipo, c.status, c.nome, c.email, c.telefone,
                        public.mask_sensivel(c.documento, v_doc) as documento,
                        c.produto_nome, c.oferta_codigo, c.valor, c.hotmart_transaction,
                        c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.sugestao,
                        c.decisao_obs, c.triado_em, tp.nome as triado_por_nome, c.aluno_id
                   from public.ra_casos c left join public.perfis tp on tp.id = c.triado_por
                  where c.id = p_caso) y),
      'pessoas', coalesce((select json_agg(json_build_object(
                    'id', p.id, 'nome', p.nome, 'email', p.email, 'papel', p.papel, 'aluno_id', p.aluno_id,
                    'itens', coalesce((select json_agg(json_build_object(
                                'id', i.id, 'item', i.item, 'rotulo', k.rotulo, 'situacao', i.situacao,
                                'responsavel', rp.nome, 'marcado_por', mp.nome, 'marcado_em', i.marcado_em,
                                'corrigido', i.corrigido, 'obs', i.obs,
                                'pode_marcar', (i.responsavel_id = v_uid or v_triador)) order by k.ordem)
                              from public.ra_itens i
                              join public.ra_itens_catalogo k on k.item = i.item
                              left join public.perfis rp on rp.id = i.responsavel_id
                              left join public.perfis mp on mp.id = i.marcado_por
                             where i.pessoa_id = p.id), '[]'::json)) order by p.ordem)
                  from public.ra_pessoas p where p.caso_id = p_caso), '[]'::json),
      'historico', coalesce((select json_agg(json_build_object(
                      'acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em)
                    from public.ra_historico h left join public.perfis hp on hp.id = h.por
                   where h.caso_id = p_caso), '[]'::json),
      'pode_triar', v_triador
    )
  );
end $$;

create or replace function public.ra_responsaveis()
returns setof json language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.ra_pode_ver() then return; end if;
  return query
    select to_json(x) from (
      select c.item, c.rotulo, c.ordem, c.so_programa, c.ativo, c.responsavel_id, p.nome as responsavel, p.email
        from public.ra_itens_catalogo c left join public.perfis p on p.id = c.responsavel_id
       order by c.ordem) x;
end $$;

-- Troca o responsável de um item. Vale para os casos que ainda serão liberados;
-- itens já criados mantêm quem estava (o histórico não muda de dono).
create or replace function public.ra_definir_responsavel(p_item text, p_perfil uuid)
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.gp_is_admin() then
    return json_build_object('ok', false, 'msg', 'Só admin troca responsáveis.');
  end if;
  if not exists (select 1 from public.perfis where id = p_perfil and status = 'ativo') then
    return json_build_object('ok', false, 'msg', 'Usuário inativo ou inexistente.');
  end if;
  update public.ra_itens_catalogo set responsavel_id = p_perfil where item = p_item;
  if not found then return json_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
  return json_build_object('ok', true, 'msg', 'Responsável atualizado.');
end $$;

-- ---------------------------------------------------------------------
-- 8) Slack via n8n (anon + segredo)
-- ---------------------------------------------------------------------
create or replace function public.ra_slack_valido(p_segredo text)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select coalesce(p_segredo, '') <> ''
     and exists (select 1 from public.ra_config where chave = 'slack_segredo' and valor = p_segredo);
$$;

create or replace function public.ra_slack_marca(p_perfil uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select coalesce((select '<@' || s.slack_id || '>' from public.ra_slack s where s.perfil_id = p_perfil),
                  (select p.nome from public.perfis p where p.id = p_perfil), 'responsável não definido');
$$;

-- Mensagens que ainda não foram para o Slack. O texto sai pronto daqui, para a
-- regra morar num lugar só; o n8n só posta e confirma.
create or replace function public.ra_slack_pendentes(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_out json;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;

  with base as (
    select c.*, to_char(c.ocorrido_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando,
           to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as prazo,
           v_url || '/relatorios/remocoes?caso=' || c.id as link,
           (select string_agg(p.nome, ', ' order by p.ordem) from public.ra_pessoas p
             where p.caso_id = c.id and p.papel = 'socio') as socios
      from public.ra_casos c
  ),
  msgs as (
    -- Disputa: só alerta, marca o triador.
    select b.id as caso_id, 'alerta' as aviso, null::text as thread_ts,
           ':warning: *Disputa aberta no HM* ' || public.ra_slack_marca(v_triador) || E'\n'
           || '*' || coalesce(b.nome, 'sem dado') || '* · ' || coalesce(b.email, 'sem dado') || E'\n'
           || coalesce(b.produto_nome, '') || ' · oferta ' || coalesce(b.oferta_codigo, 'sem dado')
           || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n'
           || 'Fique de olho: ainda não é reembolso nem chargeback. ' || '<' || b.link || '|Abrir no sistema>' as texto
      from base b where b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
    union all
    -- Caso novo: marca só o triador.
    select b.id, 'novo', null,
           ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente* ' || public.ra_slack_marca(v_triador) || E'\n'
           || '*' || coalesce(b.nome, 'sem dado') || '* · ' || coalesce(b.email, 'sem dado') || E'\n'
           || coalesce(b.produto_nome, '') || ' · oferta ' || coalesce(b.oferta_codigo, 'sem dado')
           || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
           || case when b.eh_programa then ' · Programa de Implementação' else '' end || E'\n'
           || 'Sócios: ' || coalesce(b.socios, 'nenhum') || E'\n'
           || 'Sugestão: *' || coalesce(b.sugestao->>'recomendacao', 'sem dado') || '* · ' || coalesce(b.sugestao->>'motivo', '') || E'\n'
           || 'Prazo: ' || coalesce(b.prazo, 'sem dado') || ' · <' || b.link || '|Abrir no sistema>'
      from base b where b.tipo <> 'disputa' and not (b.slack_avisos ? 'novo')
    union all
    -- Triagem: manter acesso.
    select b.id, 'fechado', b.slack_ts,
           ':white_check_mark: Mantém o acesso antigo. Nada a remover.'
           || coalesce(E'\n' || b.decisao_obs, '')
      from base b where b.status = 'mantem_acesso' and b.slack_ts is not null and not (b.slack_avisos ? 'fechado')
    union all
    -- Triagem: remoção liberada, marca cada responsável com a lista dele.
    select b.id, 'liberado', b.slack_ts,
           ':scissors: *Remoção liberada.* Prazo: ' || coalesce(b.prazo, 'sem dado') || E'\n'
           || (select string_agg(linha, E'\n') from (
                 select public.ra_slack_marca(i.responsavel_id) || ': '
                        || string_agg(distinct k.rotulo, ', ') as linha
                   from public.ra_itens i join public.ra_itens_catalogo k on k.item = i.item
                  where i.caso_id = b.id
                  group by i.responsavel_id) z)
           || E'\n' || 'Vale para ' || (select count(*) from public.ra_pessoas p where p.caso_id = b.id)
           || ' pessoa(s): titular' || case when b.socios is not null then ' e sócios (' || b.socios || ')' else '' end
           || '. <' || b.link || '|Abrir no sistema>'
      from base b where b.status in ('em_remocao', 'concluido') and b.slack_ts is not null
                    and not (b.slack_avisos ? 'liberado')
    union all
    -- Concluído.
    select b.id, 'concluido', b.slack_ts,
           ':white_check_mark: *Acessos removidos.* '
           || (select string_agg(linha, ' · ') from (
                 select coalesce(mp.nome, 'sem dado') || ' ' || to_char(max(i.marcado_em) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as linha
                   from public.ra_itens i left join public.perfis mp on mp.id = i.marcado_por
                  where i.caso_id = b.id
                  group by mp.nome) z)
      from base b where b.status = 'concluido' and b.slack_ts is not null
                    and (b.slack_avisos ? 'liberado') and not (b.slack_avisos ? 'concluido')
  )
  select json_build_object('ok', true, 'mensagens', coalesce(json_agg(m), '[]'::json)) into v_out from msgs m;
  return v_out;
end $$;

create or replace function public.ra_slack_confirmar(p_segredo text, p_caso uuid, p_aviso text, p_ts text default null)
returns json language plpgsql security definer set search_path to 'public' as $$
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  update public.ra_casos
     set slack_avisos = slack_avisos || jsonb_build_object(p_aviso, now()),
         slack_ts = case when p_aviso in ('novo', 'alerta') and slack_ts is null then p_ts else slack_ts end
   where id = p_caso;
  return json_build_object('ok', found);
end $$;

-- Lembrete de dia útil: o que vence hoje ou já venceu, marcando quem deve.
create or replace function public.ra_slack_lembrete(p_segredo text)
returns json language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_linhas text;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  if not public.ra_dia_util(v_hoje) then return json_build_object('ok', true, 'texto', null); end if;

  select string_agg(linha, E'\n' order by prazo_em) into v_linhas from (
    select c.prazo_em,
           case when c.prazo_em < now() then ':red_circle: ' else ':large_yellow_circle: ' end
           || '*' || coalesce(c.nome, 'sem dado') || '* · prazo '
           || to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') || ' · '
           || case when c.status = 'aguardando_triagem' then 'triagem: ' || public.ra_slack_marca(v_triador)
                   else 'faltam: ' || coalesce((select string_agg(distinct public.ra_slack_marca(i.responsavel_id), ' ')
                                                  from public.ra_itens i
                                                 where i.caso_id = c.id and i.situacao = 'pendente'), 'sem dado') end
           || ' · <' || v_url || '/relatorios/remocoes?caso=' || c.id || '|abrir>' as linha
      from public.ra_casos c
     where c.status in ('aguardando_triagem', 'em_remocao')
       and (c.prazo_em at time zone 'America/Sao_Paulo')::date <= v_hoje
  ) z;

  return json_build_object('ok', true, 'texto',
    case when v_linhas is null then null
         else ':alarm_clock: *Remoção de acessos: vencendo hoje ou atrasado*' || E'\n' || v_linhas end);
end $$;

-- ---------------------------------------------------------------------
-- 9) Quem executa o quê
-- ---------------------------------------------------------------------
revoke all on function public.ra_abrir_caso(uuid, text) from public, anon, authenticated;
revoke all on function public.ra_montar_sugestao(uuid, uuid) from public, anon, authenticated;
revoke all on function public.ra_fn_compra_status() from public, anon, authenticated;
revoke all on function public.ra_slack_marca(uuid) from public, anon, authenticated;
revoke all on function public.ra_brl(numeric) from public, anon;
revoke all on function public.ra_slack_valido(text) from public, anon, authenticated;
revoke all on function public.ra_calcular_prazo(timestamptz) from public, anon;
revoke all on function public.ra_dia_util(date) from public, anon;

revoke all on function public.ra_pode_ver() from public, anon;
revoke all on function public.ra_eh_triador() from public, anon;
revoke all on function public.ra_meu_papel() from public, anon;
revoke all on function public.ra_fila() from public, anon;
revoke all on function public.ra_caso(uuid) from public, anon;
revoke all on function public.ra_responsaveis() from public, anon;
revoke all on function public.ra_triar(uuid, text, text, boolean) from public, anon;
revoke all on function public.ra_marcar_item(uuid, text, text) from public, anon;
revoke all on function public.ra_definir_responsavel(text, uuid) from public, anon;
grant execute on function public.ra_pode_ver(), public.ra_eh_triador(), public.ra_meu_papel(),
  public.ra_fila(), public.ra_caso(uuid), public.ra_responsaveis(),
  public.ra_triar(uuid, text, text, boolean), public.ra_marcar_item(uuid, text, text),
  public.ra_definir_responsavel(text, uuid), public.ra_calcular_prazo(timestamptz),
  public.ra_dia_util(date) to authenticated;

revoke all on function public.ra_slack_pendentes(text) from public;
revoke all on function public.ra_slack_confirmar(text, uuid, text, text) from public;
revoke all on function public.ra_slack_lembrete(text) from public;
grant execute on function public.ra_slack_pendentes(text), public.ra_slack_confirmar(text, uuid, text, text),
  public.ra_slack_lembrete(text) to anon, authenticated;
