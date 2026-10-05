-- 20261005j: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql).
--   Todo resultado vai para a tabela temporária _z_out; o penúltimo comando mostra tudo.
--   Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out" (inclusive), leia, e rode
--   o "rollback;" em seguida. NÃO deixe a transação aberta: ela segura lock em ra_casos e thb_alunos até o rollback.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261005j_pedidos_alteracao.sql; se a migration
-- mudar, gerar de novo). Depois dele, os testes chamam as funções como a tela chamaria (JWT simulado, role authenticated)
-- com 3 alunos de TESTE (fonte 'ensaio_20261005j', e-mail @exemplo.invalid), que somem no rollback.
--
-- Esperados (conferir no _z_out):
--   1.alunos_teste            = 3
--   2.sem_permissao_criar     = {"ok" : false, "msg" : "Sem permissão para pedir alteração de cadastro."}
--   2.sem_permissao_busca     = 0
--   2.grants                  = tabela=false nas 6 linhas
--   2.grants_funcoes          = anon=false em todas; auth=true só nas 10 públicas (pa_meu_papel, pa_buscar_alunos,
--                               pa_socios_do_titular, pa_valor_atual, pa_turmas, pa_criar, pa_meus_pedidos, pa_fila, pa_decidir,
--                               pa_marcar_aplicado)
--   3.papel                   = pode_pedir true, pode_aprovar true, pendentes 0
--   3.busca                   = os 3 alunos ZZ Ensaio, e-mail mascarado ("zz***@exemplo.invalid")
--   3.socios                  = só "ZZ Ensaio Socio Sai"
--   4.criar_email             = ok true, "Pedido nº N enviado"; 4.criar_campo_proibido = ok false (lista fechada)
--   4.aprovar_email           = ok true; 4.aluno_email = zz.ensaio.novo@… por=81d2eaee…
--   4.audit                   = 1 linha campo email, valor_anterior zz.ensaio.titular@…, origem pedido_alteracao:N,
--                               autor 81d2eaee… (se a coluna autor existir)
--   5.aprovar_sem_confirmar   = ok false, conflito true, agora 5521977770000
--   5.aprovar_confirmando     = ok true
--   6.recusar                 = ok true
--   7.aprovar_troca           = ok true, ra_caso_id preenchido
--   7.alunos_depois           = Sai: socio_de_aluno_id null e socio_de_nome null (instrução continua AURUM - SÓCIO);
--                               Entra: eh_socio true, socio_de_aluno_id = titular, instrucao "AURUM - SÓCIO",
--                               espaco aurum, data_expiracao 2027-03-31, regra "Acompanha titular";
--                               Titular: num_socios 1
--   7.caso_remocao            = tipo troca_socio, aguardando_triagem, "ZZ Ensaio Socio Sai", PEDIDO-ALTERACAO-N,
--                               prazo preenchido, origem pedido_alteracao, pessoas 1
--   8.select_direto           = 42501 ok
--   Qualquer ERRO no meio = a migration não serve como está: não aplicar.

begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas (aborta se o banco não for o que esta migration espera) ─────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
  v_def text;
begin
  select string_agg(x.t || '.' || x.c, ', ') into v_falta
    from (values
      ('perfis','id'), ('perfis','nome'), ('perfis','email'), ('perfis','cargo'), ('perfis','status'), ('perfis','areas'),
      ('perfis','pode_ver_cpf_completo'),
      ('thb_alunos','id'), ('thb_alunos','nome'), ('thb_alunos','email'), ('thb_alunos','telefone'),
      ('thb_alunos','telefone_profissional'), ('thb_alunos','documento'), ('thb_alunos','cep'),
      ('thb_alunos','endereco_logradouro'), ('thb_alunos','endereco_numero'), ('thb_alunos','endereco_complemento'),
      ('thb_alunos','bairro'), ('thb_alunos','cidade'), ('thb_alunos','estado'), ('thb_alunos','pais'),
      ('thb_alunos','profissao'), ('thb_alunos','turma_id'), ('thb_alunos','instrucao'), ('thb_alunos','espaco_instrucao'),
      ('thb_alunos','obs_central'), ('thb_alunos','eh_socio'), ('thb_alunos','socio_de_aluno_id'),
      ('thb_alunos','socio_de_nome'), ('thb_alunos','num_socios'), ('thb_alunos','data_expiracao'),
      ('thb_alunos','mes_expiracao'), ('thb_alunos','ano_expiracao'), ('thb_alunos','regra_acesso'),
      ('thb_alunos','status_acesso_central'), ('thb_alunos','fonte'), ('thb_alunos','atualizado_em'),
      ('thb_alunos','atualizado_por'), ('thb_alunos','cancelado_em'), ('thb_alunos','data_entrada_thb'),
      ('thb_turmas','id'), ('thb_turmas','codigo'),
      ('thb_alunos_audit_log','aluno_id'), ('thb_alunos_audit_log','campo'), ('thb_alunos_audit_log','valor_anterior'),
      ('thb_alunos_audit_log','valor_novo'), ('thb_alunos_audit_log','origem'),
      ('ra_casos','id'), ('ra_casos','compra_id'), ('ra_casos','hotmart_transaction'), ('ra_casos','tipo'),
      ('ra_casos','status'), ('ra_casos','produto_nome'), ('ra_casos','aluno_id'), ('ra_casos','nome'),
      ('ra_casos','email'), ('ra_casos','telefone'), ('ra_casos','documento'), ('ra_casos','ocorrido_em'),
      ('ra_casos','prazo_em'), ('ra_casos','eh_programa'), ('ra_casos','sugestao'), ('ra_casos','teste'),
      ('ra_casos','origem'),
      ('ra_pessoas','caso_id'), ('ra_pessoas','aluno_id'), ('ra_pessoas','nome'), ('ra_pessoas','email'),
      ('ra_pessoas','papel'), ('ra_pessoas','ordem'),
      ('ra_historico','caso_id'), ('ra_historico','acao'), ('ra_historico','por'), ('ra_historico','detalhe')
    ) x(t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'public' and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then
    raise exception '20261005j: colunas ausentes: %', v_falta;
  end if;

  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'ra_casos' and column_name = 'compra_id' and is_nullable = 'NO') then
    raise exception '20261005j: ra_casos.compra_id ainda é NOT NULL (a 20260916_remocao_acessos_webhook não foi aplicada?)';
  end if;
  if to_regprocedure('public.gp_eh_equipe()') is null or to_regprocedure('public.ra_calcular_prazo(timestamptz)') is null then
    raise exception '20261005j: gp_eh_equipe() ou ra_calcular_prazo(timestamptz) ausente';
  end if;
  if to_regclass('public.pa_pedidos') is not null then
    raise exception '20261005j: public.pa_pedidos já existe (migration já aplicada?)';
  end if;

  -- O check de tipo de ra_casos tem de ser o conhecido (reembolso/chargeback/disputa) para ser trocado com segurança.
  select pg_get_constraintdef(k.oid) into v_def
    from pg_constraint k
   where k.conrelid = 'public.ra_casos'::regclass and k.conname = 'ra_casos_tipo_check';
  if v_def is null or v_def not like '%reembolso%' or v_def not like '%chargeback%' or v_def not like '%disputa%' then
    raise exception '20261005j: ra_casos_tipo_check diferente do esperado: %', coalesce(v_def, '(ausente)');
  end if;
end
$guarda$;

-- ─── 1. Remoção de Acessos aceita o tipo 'troca_socio' ──────────────────────────────────────────────────────────────
alter table public.ra_casos drop constraint ra_casos_tipo_check;
alter table public.ra_casos add constraint ra_casos_tipo_check
  check (tipo in ('reembolso', 'chargeback', 'disputa', 'troca_socio'));

-- ─── 2. Tabelas ─────────────────────────────────────────────────────────────────────────────────────────────────────
create table public.pa_aprovadores (
  perfil_id uuid primary key references public.perfis(id) on delete cascade,
  criado_em timestamptz not null default now()
);
insert into public.pa_aprovadores (perfil_id)
select p.id from public.perfis p where p.id = '81d2eaee-cce1-4058-8714-439b0fc6f970';   -- Victor Hugo

create table public.pa_pedidos (
  id bigint generated always as identity primary key,              -- = número do pedido
  tipo text not null check (tipo in ('alterar_dado', 'trocar_socio', 'outro')),
  aluno_id uuid references public.thb_alunos(id) on delete set null,  -- aluno alvo; na troca de sócio, o titular
  aluno_nome text not null,                                        -- nome no momento do pedido (a lista não depende do aluno existir)
  campo text,                                                      -- alterar_dado
  valor_atual jsonb,                                               -- foto do valor quando pediu (detecta conflito)
  valor_novo jsonb,                                                -- o que foi pedido, já normalizado
  valor_aplicado jsonb,                                            -- o que foi gravado (pode ser o ajuste do aprovador)
  socio_sai_id uuid references public.thb_alunos(id) on delete set null,
  socio_sai_nome text,
  socio_entra_id uuid references public.thb_alunos(id) on delete set null,
  socio_entra_nome text,
  socio_entra_novo jsonb,                                          -- dados do sócio novo (nome, email, telefone, documento)
  descricao text,                                                  -- outro
  motivo text not null check (length(btrim(motivo)) between 5 and 2000),
  evidencia text check (evidencia is null or (evidencia ~ '^https?://\S+$' and length(evidencia) <= 1000)),
  status text not null default 'pendente' check (status in ('pendente', 'aprovado', 'recusado', 'aplicado', 'erro')),
  solicitado_por uuid not null references public.perfis(id),
  solicitado_em timestamptz not null default now(),
  decidido_por uuid references public.perfis(id),
  decidido_em timestamptz,
  motivo_recusa text,
  conflito_confirmado boolean not null default false,
  aplicado_em timestamptz,
  erro_msg text,
  planilha_status text check (planilha_status in ('pendente', 'ok', 'erro')),
  planilha_em timestamptz,
  planilha_erro text,
  ra_caso_id uuid references public.ra_casos(id) on delete set null,
  check (tipo <> 'alterar_dado' or (campo is not null and valor_novo is not null)),
  check (tipo <> 'trocar_socio' or (socio_sai_id is not null and (socio_entra_id is not null or socio_entra_novo is not null))),
  check (tipo <> 'outro' or length(btrim(coalesce(descricao, ''))) >= 5),
  check (status <> 'recusado' or length(btrim(coalesce(motivo_recusa, ''))) >= 3)
);
create index pa_pedidos_status_idx on public.pa_pedidos (status, id);
create index pa_pedidos_solicitante_idx on public.pa_pedidos (solicitado_por, id desc);
create index pa_pedidos_planilha_idx on public.pa_pedidos (id) where planilha_status = 'pendente';
-- Um pedido pendente por aluno e campo: o segundo pedido igual vira aviso, não fila duplicada.
create unique index pa_pedidos_pendente_campo_uidx on public.pa_pedidos (aluno_id, campo)
  where status = 'pendente' and tipo = 'alterar_dado';

create table public.pa_historico (
  id bigint generated always as identity primary key,
  pedido_id bigint not null references public.pa_pedidos(id) on delete cascade,
  acao text not null,
  por uuid references public.perfis(id),
  em timestamptz not null default now(),
  detalhe jsonb not null default '{}'::jsonb
);
create index pa_historico_pedido_idx on public.pa_historico (pedido_id, em);

alter table public.pa_aprovadores enable row level security;
alter table public.pa_pedidos enable row level security;
alter table public.pa_historico enable row level security;
revoke all on table public.pa_aprovadores, public.pa_pedidos, public.pa_historico from public, anon, authenticated;

comment on table public.pa_pedidos is
  '20261005j: pedidos de alteração de cadastro. Fechada; só pelas funções pa_*. planilha_status = fila da etapa 2 (n8n).';

-- ─── 3. Regras puras (catálogo e normalização) ──────────────────────────────────────────────────────────────────────
-- Lista FECHADA de campos editáveis por "alterar dado". Espelho: web/modules/pedidos-alteracao/domain/campos.ts.
create function public.pa_campos()
returns text[] language sql immutable set search_path = '' as $$
  select array['nome', 'email', 'telefone', 'telefone_profissional', 'documento', 'endereco',
               'profissao', 'turma_id', 'instrucao', 'espaco_instrucao', 'obs_central']::text[];
$$;

create function public.pa_colunas_endereco()
returns text[] language sql immutable set search_path = '' as $$
  select array['cep', 'endereco_logradouro', 'endereco_numero', 'endereco_complemento',
               'bairro', 'cidade', 'estado', 'pais']::text[];
$$;

create function public.pa_sem_acento(p text)
returns text language sql immutable set search_path = '' as $$
  select translate(p, 'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇáàâãäéèêëíìîïóòôõöúùûüç',
                      'AAAAAEEEEIIIIOOOOOUUUUCaaaaaeeeeiiiiooooouuuuc');
$$;

-- Chave de nome (mesma ideia do chaveNome da tela): sem acento, minúsculo, espaços simples.
create function public.pa_chave_nome(p text)
returns text language sql immutable set search_path = '' as $$
  select nullif(btrim(regexp_replace(lower(public.pa_sem_acento(coalesce(p, ''))), '\s+', ' ', 'g')), '');
$$;

-- Instrução canônica (espelho de instrucaoCanonica em aluno-360.ts): "<NÍVEL>" ou "<NÍVEL> - SÓCIO".
create function public.pa_instrucao_canonica(p_instrucao text, p_espaco text, p_eh_socio boolean)
returns text language plpgsql immutable set search_path = '' as $$
declare
  v_bruto text := upper(btrim(coalesce(p_instrucao, '')));
  v_sem text;
  v_socio boolean := false;
  v_nivel text;
begin
  if v_bruto <> '' then
    v_sem := btrim(regexp_replace(v_bruto, '\s*[-–—]\s*S[ÓO]CIOS?\s*$', ''));
    v_socio := v_sem <> v_bruto;
    select n into v_nivel
      from unnest(array['THB', 'THB IMPLEMENTAÇÃO', 'PLATINA', 'AURUM', 'DIAMANTE', 'DIAMANTE VERMELHO']) n
     where public.pa_sem_acento(n) = public.pa_sem_acento(v_sem);
  end if;
  if v_nivel is null then
    v_nivel := case p_espaco
                 when 'holding_masters' then 'THB'
                 when 'holding_masters_implementacao' then 'THB IMPLEMENTAÇÃO'
                 when 'platina' then 'PLATINA'
                 when 'aurum' then 'AURUM'
                 when 'mastermind_diamante' then 'DIAMANTE'
                 when 'diamante_vermelho' then 'DIAMANTE VERMELHO'
               end;
    if v_nivel is null then return null; end if;
    v_socio := coalesce(p_eh_socio, false);
  end if;
  if coalesce(p_eh_socio, false) then v_socio := true; end if;
  return v_nivel || case when v_socio then ' - SÓCIO' else '' end;
end
$$;

create function public.pa_mascara_email(p text)
returns text language sql immutable set search_path = '' as $$
  select case when p is null or position('@' in p) = 0 then null
              else left(split_part(btrim(p), '@', 1), 2) || '***@' || split_part(btrim(p), '@', 2) end;
$$;

create function public.pa_final(p text)
returns text language sql immutable set search_path = '' as $$
  select nullif(right(regexp_replace(coalesce(p, ''), '\D', '', 'g'), 4), '');
$$;

create function public.pa_mascara_doc(p text, p_ver boolean)
returns text language sql immutable set search_path = '' as $$
  select case when p is null or p_ver then p
              when length(regexp_replace(p, '\D', '', 'g')) >= 4
                then repeat('*', greatest(length(p) - 4, 0)) || right(regexp_replace(p, '\D', '', 'g'), 4)
              else repeat('*', length(p)) end;
$$;

-- Texto de um valor jsonb (string → texto; null/"" → null).
create function public.pa_txt(p jsonb)
returns text language sql immutable set search_path = '' as $$
  select case when p is null or jsonb_typeof(p) = 'null' then null
              when jsonb_typeof(p) = 'string' then nullif(btrim(p #>> '{}'), '')
              else nullif(btrim(p::text), '') end;
$$;

create function public.pa_telefone(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if d = '' then return null; end if;
  if length(d) in (10, 11) then d := '55' || d; end if;   -- padrão da Central: 55 + DDD + número
  if length(d) < 10 or length(d) > 15 then
    raise exception 'Telefone inválido: use DDD + número (ex.: 21 99999-9999).' using errcode = '22023';
  end if;
  return d;
end
$$;

-- Valida e normaliza o valor pedido para um campo. Erro de validação = errcode 22023 com a mensagem para a tela.
create function public.pa_normalizar(p_campo text, p_valor jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v text := public.pa_txt(p_valor);
  d text;
  k text;
  v_end jsonb := '{}'::jsonb;
begin
  if p_campo is null or not (p_campo = any(public.pa_campos())) then
    raise exception 'Campo fora da lista de campos editáveis.' using errcode = '22023';
  end if;

  if p_campo = 'nome' then
    v := regexp_replace(coalesce(v, ''), '\s+', ' ', 'g');
    if length(v) < 3 or length(v) > 200 then
      raise exception 'Nome deve ter entre 3 e 200 caracteres.' using errcode = '22023';
    end if;
    return to_jsonb(v);
  elsif p_campo = 'email' then
    if v is null or v !~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' or length(v) > 200 then
      raise exception 'E-mail inválido.' using errcode = '22023';
    end if;
    return to_jsonb(v);
  elsif p_campo in ('telefone', 'telefone_profissional') then
    return coalesce(to_jsonb(public.pa_telefone(v)), 'null'::jsonb);
  elsif p_campo = 'documento' then
    d := regexp_replace(coalesce(v, ''), '\D', '', 'g');
    if length(d) not in (11, 14) then
      raise exception 'Documento inválido: CPF com 11 dígitos ou CNPJ com 14.' using errcode = '22023';
    end if;
    return to_jsonb(d);
  elsif p_campo = 'endereco' then
    if p_valor is null or jsonb_typeof(p_valor) <> 'object' then
      raise exception 'Endereço inválido.' using errcode = '22023';
    end if;
    foreach k in array public.pa_colunas_endereco() loop
      v := left(public.pa_txt(p_valor -> k), 200);
      if k = 'cep' and v is not null then
        v := regexp_replace(v, '\D', '', 'g');
        if length(v) <> 8 then raise exception 'CEP deve ter 8 dígitos.' using errcode = '22023'; end if;
      elsif k = 'estado' and v is not null then
        v := upper(v);
        if v !~ '^[A-Z]{2}$' then raise exception 'Estado deve ser a sigla de 2 letras (ex.: SP).' using errcode = '22023'; end if;
      end if;
      v_end := v_end || jsonb_build_object(k, v);
    end loop;
    return v_end;
  elsif p_campo = 'turma_id' then
    if v is null or v !~ '^\d{1,6}$' or not exists (select 1 from public.thb_turmas t where t.id = v::int) then
      raise exception 'Turma inexistente.' using errcode = '22023';
    end if;
    return to_jsonb(v::int);
  elsif p_campo = 'instrucao' then
    v := upper(coalesce(v, ''));
    if not (v = any(array['THB', 'THB - SÓCIO', 'THB IMPLEMENTAÇÃO', 'THB IMPLEMENTAÇÃO - SÓCIO', 'PLATINA',
                          'PLATINA - SÓCIO', 'AURUM', 'AURUM - SÓCIO', 'DIAMANTE', 'DIAMANTE - SÓCIO',
                          'DIAMANTE VERMELHO', 'DIAMANTE VERMELHO - SÓCIO'])) then
      raise exception 'Instrução fora das 12 da Central.' using errcode = '22023';
    end if;
    return to_jsonb(v);
  elsif p_campo = 'espaco_instrucao' then
    if not (coalesce(v, '') = any(array['holding_masters', 'holding_masters_implementacao', 'aurum', 'platina',
                                        'mastermind_diamante', 'diamante_vermelho'])) then
      raise exception 'Espaço de instrução inválido.' using errcode = '22023';
    end if;
    return to_jsonb(v);
  elsif p_campo = 'profissao' then
    if length(coalesce(v, '')) > 200 then raise exception 'Profissão com mais de 200 caracteres.' using errcode = '22023'; end if;
    return coalesce(to_jsonb(v), 'null'::jsonb);
  elsif p_campo = 'obs_central' then
    if length(coalesce(v, '')) > 2000 then raise exception 'Observação com mais de 2000 caracteres.' using errcode = '22023'; end if;
    return coalesce(to_jsonb(v), 'null'::jsonb);
  end if;
  raise exception 'Campo sem regra de validação.' using errcode = '22023';
end
$$;

-- ─── 4. Leitura do aluno ────────────────────────────────────────────────────────────────────────────────────────────
-- Valor atual de um campo editável, no mesmo formato do valor_novo.
create function public.pa_valor_campo(p_aluno uuid, p_campo text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v jsonb;
  v_txt text;
begin
  if p_campo = 'endereco' then
    select jsonb_build_object('cep', a.cep, 'endereco_logradouro', a.endereco_logradouro,
             'endereco_numero', a.endereco_numero, 'endereco_complemento', a.endereco_complemento,
             'bairro', a.bairro, 'cidade', a.cidade, 'estado', a.estado, 'pais', a.pais)
      into v from public.thb_alunos a where a.id = p_aluno;
    return v;
  elsif p_campo = 'turma_id' then
    select to_jsonb(a.turma_id::int) into v from public.thb_alunos a where a.id = p_aluno;
    return coalesce(v, 'null'::jsonb);
  elsif p_campo = any(public.pa_campos()) then
    execute format('select (a.%I)::text from public.thb_alunos a where a.id = $1', p_campo) into v_txt using p_aluno;
    return coalesce(to_jsonb(v_txt), 'null'::jsonb);
  end if;
  return null;
end
$$;

-- Texto de tela para um valor (turma pelo código, endereço numa linha, documento mascarado sem permissão).
create function public.pa_exibir(p_campo text, p_valor jsonb, p_ver_doc boolean)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v text;
begin
  if p_valor is null or jsonb_typeof(p_valor) = 'null' then return null; end if;
  if p_campo = 'turma_id' then
    select t.codigo into v from public.thb_turmas t where t.id = (p_valor #>> '{}')::int;
    return coalesce(v, 'turma ' || (p_valor #>> '{}'));
  elsif p_campo = 'endereco' then
    return nullif(concat_ws(', ',
      public.pa_txt(p_valor -> 'endereco_logradouro'), public.pa_txt(p_valor -> 'endereco_numero'),
      public.pa_txt(p_valor -> 'endereco_complemento'), public.pa_txt(p_valor -> 'bairro'),
      nullif(concat_ws('/', public.pa_txt(p_valor -> 'cidade'), public.pa_txt(p_valor -> 'estado')), ''),
      'CEP ' || public.pa_txt(p_valor -> 'cep'), public.pa_txt(p_valor -> 'pais')), '');
  elsif p_campo = 'documento' then
    return public.pa_mascara_doc(public.pa_txt(p_valor), p_ver_doc);
  end if;
  return public.pa_txt(p_valor);
end
$$;

-- Sócio de um titular: pelo vínculo forte (FK) ou, sem FK, pelo nome do titular (mesma regra do ra_abrir_caso).
create function public.pa_eh_socio_de(p_socio uuid, p_titular uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.thb_alunos s join public.thb_alunos t on t.id = p_titular
     where s.id = p_socio and s.id <> t.id
       and (s.socio_de_aluno_id = t.id
            or (s.socio_de_aluno_id is null and coalesce(s.eh_socio, false)
                and public.pa_chave_nome(s.socio_de_nome) = public.pa_chave_nome(t.nome))));
$$;

create function public.pa_contar_socios(p_titular uuid)
returns int language sql stable security definer set search_path = '' as $$
  select count(*)::int
    from public.thb_alunos s join public.thb_alunos t on t.id = p_titular
   where s.id <> t.id and s.cancelado_em is null
     and (s.socio_de_aluno_id = t.id
          or (s.socio_de_aluno_id is null and coalesce(s.eh_socio, false)
              and public.pa_chave_nome(s.socio_de_nome) = public.pa_chave_nome(t.nome)));
$$;

-- ─── 5. Permissões ──────────────────────────────────────────────────────────────────────────────────────────────────
-- Espelho: podePedirAlteracao() em web/modules/pedidos-alteracao/domain/acesso.ts.
create function public.pa_pode_pedir()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_eh_equipe(), false) and exists (
    select 1 from public.perfis p
     where p.id = (select auth.uid()) and p.status = 'ativo'
       and (p.cargo in ('dev', 'admin')
            or (p.cargo in ('gestor', 'operador') and 'pedidos_alteracao' = any(coalesce(p.areas, '{}')))));
$$;

create function public.pa_eh_aprovador()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_eh_equipe(), false) and exists (
    select 1 from public.pa_aprovadores a join public.perfis p on p.id = a.perfil_id and p.status = 'ativo'
     where a.perfil_id = (select auth.uid()));
$$;

-- Espelho de podeVerCpf() (shared/domain/auth/permissions.ts).
create function public.pa_pode_ver_doc()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfis p
                  where p.id = (select auth.uid()) and p.status = 'ativo'
                    and (p.cargo in ('dev', 'admin') or coalesce(p.pode_ver_cpf_completo, false)));
$$;

create function public.pa_meu_papel()
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'pode_pedir', public.pa_pode_pedir(),
    'pode_aprovar', public.pa_eh_aprovador(),
    'pode_ver_doc', public.pa_pode_ver_doc(),
    'pendentes', case when public.pa_eh_aprovador()
                      then (select count(*) from public.pa_pedidos where status in ('pendente', 'erro')) end);
$$;

-- ─── 6. Busca de aluno para o formulário (só o mínimo para distinguir homônimos) ────────────────────────────────────
create function public.pa_resumo_aluno(p_aluno uuid)
returns json language sql stable security definer set search_path = '' as $$
  select json_build_object(
    'id', a.id, 'nome', a.nome,
    'instrucao', public.pa_instrucao_canonica(a.instrucao, a.espaco_instrucao, a.eh_socio),
    'espaco', a.espaco_instrucao,
    'eh_socio', (a.socio_de_aluno_id is not null or coalesce(a.eh_socio, false)),
    'titular_nome', case when a.socio_de_aluno_id is not null or coalesce(a.eh_socio, false)
                         then coalesce(t.nome, a.socio_de_nome) end,
    'titular_id', a.socio_de_aluno_id,
    'turma', tu.codigo,
    'email', public.pa_mascara_email(a.email),
    'telefone_final', public.pa_final(a.telefone),
    'doc_final', public.pa_final(a.documento),
    'num_socios', a.num_socios)
    from public.thb_alunos a
    left join public.thb_alunos t on t.id = a.socio_de_aluno_id
    left join public.thb_turmas tu on tu.id = a.turma_id
   where a.id = p_aluno;
$$;

create function public.pa_buscar_alunos(p_termo text, p_instrucoes text[] default null, p_espacos text[] default null,
                                        p_papel text default null, p_limite int default 15)
returns setof json language plpgsql stable security definer set search_path = '' as $$
declare
  v_termo text := public.pa_chave_nome(p_termo);
  v_tokens text[];
begin
  if not public.pa_pode_pedir() then return; end if;
  if v_termo is null or length(v_termo) < 3 then return; end if;
  v_tokens := regexp_split_to_array(v_termo, ' ');
  return query
    select public.pa_resumo_aluno(x.id)
      from (
        select a.id, a.nome,
               (public.pa_chave_nome(a.nome) like v_termo || '%') as prefixo
          from public.thb_alunos a
         where a.cancelado_em is null
           and (select bool_and((public.pa_chave_nome(a.nome) || ' ' || lower(coalesce(a.email, ''))) like '%' || tk || '%')
                  from unnest(v_tokens) tk)
           and (p_instrucoes is null or cardinality(p_instrucoes) = 0
                or public.pa_instrucao_canonica(a.instrucao, a.espaco_instrucao, a.eh_socio) = any(p_instrucoes))
           and (p_espacos is null or cardinality(p_espacos) = 0 or a.espaco_instrucao = any(p_espacos))
           and (p_papel is null
                or (p_papel = 'socio' and (a.socio_de_aluno_id is not null or coalesce(a.eh_socio, false)))
                or (p_papel = 'titular' and a.socio_de_aluno_id is null and not coalesce(a.eh_socio, false)))
         order by prefixo desc, a.nome
         limit least(greatest(coalesce(p_limite, 15), 1), 30)
      ) x
     order by x.prefixo desc, x.nome;
end
$$;

-- Sócios de um titular (troca de sócio guiada).
create function public.pa_socios_do_titular(p_titular uuid)
returns setof json language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.pa_pode_pedir() then return; end if;
  return query
    select public.pa_resumo_aluno(s.id)
      from public.thb_alunos s
     where s.cancelado_em is null and public.pa_eh_socio_de(s.id, p_titular)
     order by s.nome;
end
$$;

-- Valor atual de um campo para mostrar no formulário (documento mascarado sem permissão).
create function public.pa_valor_atual(p_aluno uuid, p_campo text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare v jsonb;
begin
  if not public.pa_pode_pedir() then return null; end if;
  if not (p_campo = any(public.pa_campos())) then return null; end if;
  if not exists (select 1 from public.thb_alunos a where a.id = p_aluno and a.cancelado_em is null) then return null; end if;
  v := public.pa_valor_campo(p_aluno, p_campo);
  return json_build_object(
    'valor', case when p_campo = 'documento' and not public.pa_pode_ver_doc() then null else v end,
    'exibicao', public.pa_exibir(p_campo, v, public.pa_pode_ver_doc()));
end
$$;

-- Turmas para o campo "turma" do formulário (quem pede pode não ter leitura de thb_turmas).
create function public.pa_turmas()
returns setof json language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.pa_pode_pedir() then return; end if;
  return query select json_build_object('id', t.id, 'codigo', t.codigo) from public.thb_turmas t order by t.id;
end
$$;

-- ─── 7. Criar pedido ────────────────────────────────────────────────────────────────────────────────────────────────
-- p: tipo, aluno_id, campo, valor_novo, socio_sai_id, socio_entra_id, socio_entra_novo{nome,email,telefone,documento},
--    descricao, motivo, evidencia
create function public.pa_criar(p jsonb)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_tipo text := p ->> 'tipo';
  v_aluno public.thb_alunos%rowtype;
  v_sai public.thb_alunos%rowtype;
  v_entra public.thb_alunos%rowtype;
  v_campo text;
  v_atual jsonb;
  v_novo jsonb;
  v_entra_novo jsonb;
  v_motivo text := btrim(coalesce(p ->> 'motivo', ''));
  v_evid text := nullif(btrim(coalesce(p ->> 'evidencia', '')), '');
  v_desc text := nullif(btrim(coalesce(p ->> 'descricao', '')), '');
  v_id bigint;
  v_dup bigint;
  v_txt text;
begin
  if not public.pa_pode_pedir() then
    return json_build_object('ok', false, 'msg', 'Sem permissão para pedir alteração de cadastro.');
  end if;
  if v_tipo is null or v_tipo not in ('alterar_dado', 'trocar_socio', 'outro') then
    return json_build_object('ok', false, 'msg', 'Tipo de pedido inválido.');
  end if;
  if length(v_motivo) < 5 then
    return json_build_object('ok', false, 'msg', 'Explique o motivo (mínimo 5 caracteres).');
  end if;
  if length(v_motivo) > 2000 then
    return json_build_object('ok', false, 'msg', 'Motivo com mais de 2000 caracteres.');
  end if;
  if v_evid is not null and (v_evid !~ '^https?://\S+$' or length(v_evid) > 1000) then
    return json_build_object('ok', false, 'msg', 'Evidência deve ser um link (http ou https).');
  end if;

  begin
    select * into strict v_aluno from public.thb_alunos a
     where a.id = nullif(p ->> 'aluno_id', '')::uuid and a.cancelado_em is null;
  exception when no_data_found or invalid_text_representation then
    return json_build_object('ok', false, 'msg', 'Aluno não encontrado.');
  end;

  if v_tipo = 'alterar_dado' then
    v_campo := p ->> 'campo';
    if v_campo is null or not (v_campo = any(public.pa_campos())) then
      return json_build_object('ok', false, 'msg', 'Campo fora da lista de campos editáveis.');
    end if;
    v_atual := public.pa_valor_campo(v_aluno.id, v_campo);
    begin
      -- Endereço: o que não veio no pedido continua como está.
      v_novo := public.pa_normalizar(v_campo,
                  case when v_campo = 'endereco' and jsonb_typeof(p -> 'valor_novo') = 'object'
                       then v_atual || (p -> 'valor_novo') else p -> 'valor_novo' end);
    exception when sqlstate '22023' then
      return json_build_object('ok', false, 'msg', sqlerrm);
    end;
    if v_novo = v_atual then
      return json_build_object('ok', false, 'msg', 'O valor novo é igual ao atual.');
    end if;
    if v_campo = 'email' and exists (select 1 from public.thb_alunos o
                                      where o.id <> v_aluno.id and lower(btrim(o.email)) = lower(public.pa_txt(v_novo))) then
      return json_build_object('ok', false, 'msg', 'Esse e-mail já é de outro aluno na base.');
    end if;
    select id into v_dup from public.pa_pedidos
     where aluno_id = v_aluno.id and campo = v_campo and status = 'pendente' and tipo = 'alterar_dado';
    if v_dup is not null then
      return json_build_object('ok', false, 'msg', 'Já existe o pedido nº ' || v_dup || ' pendente para esse campo deste aluno.');
    end if;

  elsif v_tipo = 'trocar_socio' then
    if v_aluno.socio_de_aluno_id is not null or coalesce(v_aluno.eh_socio, false) then
      return json_build_object('ok', false, 'msg', 'O aluno escolhido é sócio. Escolha o titular.');
    end if;
    begin
      select * into strict v_sai from public.thb_alunos a
       where a.id = nullif(p ->> 'socio_sai_id', '')::uuid and a.cancelado_em is null;
    exception when no_data_found or invalid_text_representation then
      return json_build_object('ok', false, 'msg', 'Escolha o sócio que sai.');
    end;
    if not public.pa_eh_socio_de(v_sai.id, v_aluno.id) then
      return json_build_object('ok', false, 'msg', v_sai.nome || ' não é sócio de ' || v_aluno.nome || '.');
    end if;

    if nullif(p ->> 'socio_entra_id', '') is not null then
      begin
        select * into strict v_entra from public.thb_alunos a
         where a.id = (p ->> 'socio_entra_id')::uuid and a.cancelado_em is null;
      exception when no_data_found or invalid_text_representation then
        return json_build_object('ok', false, 'msg', 'Sócio que entra não encontrado.');
      end;
      if v_entra.id in (v_aluno.id, v_sai.id) then
        return json_build_object('ok', false, 'msg', 'O sócio que entra tem de ser outra pessoa.');
      end if;
      if public.pa_eh_socio_de(v_entra.id, v_aluno.id) then
        return json_build_object('ok', false, 'msg', v_entra.nome || ' já é sócio deste titular.');
      end if;
      if v_entra.socio_de_aluno_id is not null then
        return json_build_object('ok', false, 'msg', v_entra.nome || ' já é sócio de outro titular.');
      end if;
      if exists (select 1 from public.thb_alunos o where o.socio_de_aluno_id = v_entra.id and o.cancelado_em is null) then
        return json_build_object('ok', false, 'msg', v_entra.nome || ' é titular de outros sócios e não pode virar sócio.');
      end if;
    elsif jsonb_typeof(p -> 'socio_entra_novo') = 'object' then
      v_txt := regexp_replace(coalesce(public.pa_txt(p -> 'socio_entra_novo' -> 'nome'), ''), '\s+', ' ', 'g');
      if length(v_txt) < 3 then
        return json_build_object('ok', false, 'msg', 'Informe o nome completo do sócio novo.');
      end if;
      begin
        v_entra_novo := jsonb_build_object(
          'nome', v_txt,
          'email', public.pa_txt(public.pa_normalizar('email', p -> 'socio_entra_novo' -> 'email')),
          'telefone', public.pa_telefone(public.pa_txt(p -> 'socio_entra_novo' -> 'telefone')),
          'documento', case when public.pa_txt(p -> 'socio_entra_novo' -> 'documento') is null then null
                            else public.pa_txt(public.pa_normalizar('documento', p -> 'socio_entra_novo' -> 'documento')) end);
      exception when sqlstate '22023' then
        return json_build_object('ok', false, 'msg', 'Sócio novo: ' || sqlerrm);
      end;
      if exists (select 1 from public.thb_alunos o where lower(btrim(o.email)) = lower(v_entra_novo ->> 'email')) then
        return json_build_object('ok', false, 'msg', 'Esse e-mail já está na base: escolha a pessoa como sócio existente.');
      end if;
    else
      return json_build_object('ok', false, 'msg', 'Escolha o sócio que entra (existente ou novo).');
    end if;
    v_atual := jsonb_build_object('socio_sai_vinculado', true, 'num_socios', v_aluno.num_socios);

  else -- outro
    if v_desc is null or length(v_desc) < 5 then
      return json_build_object('ok', false, 'msg', 'Descreva a alteração (mínimo 5 caracteres).');
    end if;
    if length(v_desc) > 2000 then
      return json_build_object('ok', false, 'msg', 'Descrição com mais de 2000 caracteres.');
    end if;
  end if;

  begin
    insert into public.pa_pedidos (tipo, aluno_id, aluno_nome, campo, valor_atual, valor_novo,
                                   socio_sai_id, socio_sai_nome, socio_entra_id, socio_entra_nome, socio_entra_novo,
                                   descricao, motivo, evidencia, solicitado_por)
    values (v_tipo, v_aluno.id, coalesce(v_aluno.nome, '(sem nome)'), v_campo, v_atual, v_novo,
            v_sai.id, v_sai.nome, v_entra.id, coalesce(v_entra.nome, v_entra_novo ->> 'nome'), v_entra_novo,
            case when v_tipo = 'outro' then v_desc end, v_motivo, v_evid, v_uid)
    returning id into v_id;
  exception when unique_violation then
    return json_build_object('ok', false, 'msg', 'Já existe um pedido pendente para esse campo deste aluno.');
  end;

  insert into public.pa_historico (pedido_id, acao, por, detalhe)
  values (v_id, 'criado', v_uid, jsonb_build_object('tipo', v_tipo, 'campo', v_campo));
  return json_build_object('ok', true, 'msg', 'Pedido nº ' || v_id || ' enviado para aprovação.', 'numero', v_id);
end
$$;

-- ─── 8. Listas ──────────────────────────────────────────────────────────────────────────────────────────────────────
-- Linha de tela de um pedido. p_aprovador = mostra o valor de hoje e o conflito.
create function public.pa_linha(p_id bigint, p_aprovador boolean)
returns json language plpgsql stable security definer set search_path = '' as $$
declare
  r public.pa_pedidos%rowtype;
  v_doc boolean := public.pa_pode_ver_doc();
  v_agora jsonb;
  v_conflito boolean := false;
  v_sai_vinculado boolean;
begin
  select * into r from public.pa_pedidos where id = p_id;
  if not found then return null; end if;
  if p_aprovador and r.status in ('pendente', 'erro') then
    if r.tipo = 'alterar_dado' and r.aluno_id is not null then
      v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
      v_conflito := v_agora is distinct from r.valor_atual;
    elsif r.tipo = 'trocar_socio' then
      v_sai_vinculado := r.aluno_id is not null and r.socio_sai_id is not null
                         and public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id);
      v_conflito := not v_sai_vinculado;
    end if;
  end if;
  return json_build_object(
    'id', r.id, 'tipo', r.tipo, 'status', r.status,
    'aluno_id', r.aluno_id, 'aluno_nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
    'aluno', case when p_aprovador and r.aluno_id is not null then public.pa_resumo_aluno(r.aluno_id) end,
    'campo', r.campo,
    'de', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, r.valor_atual, v_doc) end,
    'para', case when r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, coalesce(r.valor_aplicado, r.valor_novo), v_doc) end,
    'agora', case when p_aprovador and r.tipo = 'alterar_dado' then public.pa_exibir(r.campo, v_agora, v_doc) end,
    'valor_novo', case when p_aprovador and (r.campo <> 'documento' or v_doc) then r.valor_novo end,
    'conflito', v_conflito,
    'socio_sai_id', r.socio_sai_id, 'socio_sai_nome', r.socio_sai_nome,
    'socio_sai_vinculado', v_sai_vinculado,
    'socio_entra_id', r.socio_entra_id, 'socio_entra_nome', r.socio_entra_nome,
    'socio_entra_novo', case when r.socio_entra_novo is null then null
                             else r.socio_entra_novo || jsonb_build_object('documento',
                                    public.pa_mascara_doc(r.socio_entra_novo ->> 'documento', v_doc)) end,
    'descricao', r.descricao, 'motivo', r.motivo, 'evidencia', r.evidencia,
    'solicitado_em', r.solicitado_em,
    'solicitado_por_nome', (select p.nome from public.perfis p where p.id = r.solicitado_por),
    'decidido_em', r.decidido_em,
    'decidido_por_nome', (select p.nome from public.perfis p where p.id = r.decidido_por),
    'motivo_recusa', r.motivo_recusa, 'conflito_confirmado', r.conflito_confirmado,
    'aplicado_em', r.aplicado_em, 'erro_msg', r.erro_msg,
    'planilha_status', r.planilha_status, 'planilha_em', r.planilha_em, 'planilha_erro', r.planilha_erro,
    'ra_caso_id', r.ra_caso_id,
    'historico', case when p_aprovador then coalesce((
       select json_agg(json_build_object('acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em, h.id)
         from public.pa_historico h left join public.perfis hp on hp.id = h.por
        where h.pedido_id = r.id), '[]'::json) end);
end
$$;

create function public.pa_meus_pedidos()
returns setof json language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.pa_pode_pedir() then return; end if;
  return query
    select public.pa_linha(x.id, false)
      from public.pa_pedidos x
     where x.solicitado_por = (select auth.uid())
     order by x.id desc
     limit 300;
end
$$;

-- Fila do aprovador: pendentes e com erro; com p_todos, também os decididos dos últimos 90 dias.
create function public.pa_fila(p_todos boolean default false)
returns setof json language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.pa_eh_aprovador() then return; end if;
  return query
    select public.pa_linha(x.id, true)
      from public.pa_pedidos x
     where x.status in ('pendente', 'erro', 'aprovado')
        or (coalesce(p_todos, false) and x.solicitado_em >= now() - interval '90 days')
     order by case x.status when 'pendente' then 0 when 'erro' then 1 when 'aprovado' then 2 else 3 end, x.id desc
     limit 500;
end
$$;

-- ─── 9. Aplicar ─────────────────────────────────────────────────────────────────────────────────────────────────────
-- Grava UMA coluna de thb_alunos e a linha do audit, se o valor mudou. Uso interno (sem grant).
create function public.pa_set_coluna(p_aluno uuid, p_col text, p_novo text, p_origem text, p_por uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_tipo text;
  v_ant text;
begin
  select format_type(a.atttypid, a.atttypmod) into v_tipo
    from pg_catalog.pg_attribute a
   where a.attrelid = 'public.thb_alunos'::regclass and a.attname = p_col and a.attnum > 0 and not a.attisdropped;
  if v_tipo is null then raise exception 'pa_set_coluna: coluna % inexistente', p_col; end if;
  execute format('select (a.%I)::text from public.thb_alunos a where a.id = $1', p_col) into v_ant using p_aluno;
  if v_ant is not distinct from p_novo then return false; end if;
  execute format('update public.thb_alunos set %I = $1::%s, atualizado_em = now(), atualizado_por = $2 where id = $3',
                 p_col, v_tipo)
    using p_novo, p_por, p_aluno;
  insert into public.thb_alunos_audit_log (aluno_id, campo, valor_anterior, valor_novo, origem)
  values (p_aluno, p_col, v_ant, p_novo, p_origem);
  return true;
end
$$;

-- Caso de Remoção de Acessos para o sócio que saiu. Mesmo formato dos casos da Hotmart, sem compra:
-- nasce aguardando triagem, com prazo de 1 dia útil; a triagem e o checklist seguem o fluxo do módulo.
create function public.pa_abrir_caso_remocao(p_pedido bigint, p_socio uuid, p_titular_nome text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_s public.thb_alunos%rowtype;
  v_turma text;
  v_caso uuid;
  v_transacao text := 'PEDIDO-ALTERACAO-' || p_pedido;
begin
  select * into v_s from public.thb_alunos where id = p_socio;
  select t.codigo into v_turma from public.thb_turmas t where t.id = v_s.turma_id;
  insert into public.ra_casos (
    compra_id, hotmart_transaction, tipo, status, produto_nome, aluno_id, nome, email, telefone, documento,
    ocorrido_em, prazo_em, eh_programa, sugestao, teste, origem)
  values (
    null, v_transacao, 'troca_socio', 'aguardando_triagem', 'Troca de sócio (pedido nº ' || p_pedido || ')',
    v_s.id, v_s.nome, v_s.email, v_s.telefone, v_s.documento,
    now(), public.ra_calcular_prazo(now()), coalesce(v_s.espaco_instrucao = 'holding_masters_implementacao', false),
    jsonb_build_object(
      'recomendacao', 'remover',
      'motivo', 'Troca de sócio, pedido nº ' || p_pedido || ': saiu do vínculo com ' || coalesce(p_titular_nome, 'o titular') || '.',
      'compras_anteriores', '[]'::jsonb,
      'aluno', jsonb_build_object('instrucao', v_s.instrucao, 'espaco', v_s.espaco_instrucao, 'turma', v_turma,
                                  'data_expiracao', v_s.data_expiracao, 'data_entrada_thb', v_s.data_entrada_thb,
                                  'status_central', v_s.status_acesso_central, 'eh_socio', v_s.eh_socio),
      'historico_expiracao', '[]'::jsonb,
      'aviso', 'Caso aberto pela aprovação de um pedido de alteração de cadastro, não pela Hotmart.'),
    false, 'pedido_alteracao')
  on conflict (hotmart_transaction, tipo) do nothing
  returning id into v_caso;

  if v_caso is null then
    select id into v_caso from public.ra_casos where hotmart_transaction = v_transacao and tipo = 'troca_socio';
    return v_caso;
  end if;
  insert into public.ra_pessoas (caso_id, aluno_id, nome, email, papel, ordem)
  values (v_caso, v_s.id, v_s.nome, v_s.email, 'socio', 0);
  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (v_caso, 'aberto', (select p.id from public.perfis p where p.id = (select auth.uid())),
          jsonb_build_object('tipo', 'troca_socio', 'origem', 'pedido_alteracao', 'pedido', p_pedido,
                             'titular', p_titular_nome));
  return v_caso;
end
$$;

-- Decide um pedido. Aprovar aplica na hora (numa subtransação: erro não deixa meia alteração).
--   p_valor_ajustado: o aprovador corrige o valor antes de aplicar (alterar_dado).
--   p_confirmar_conflito: o valor mudou desde o pedido; sem esta confirmação, não aplica.
create function public.pa_decidir(p_pedido bigint, p_decisao text, p_motivo_recusa text default null,
                                  p_valor_ajustado jsonb default null, p_confirmar_conflito boolean default false)
returns json language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := (select auth.uid());
  v_por uuid;
  r public.pa_pedidos%rowtype;
  v_origem text;
  v_agora jsonb;
  v_novo jsonb;
  v_t public.thb_alunos%rowtype;
  v_s2 uuid;
  v_nivel text;
  v_num int;
  v_caso uuid;
  v_k text;
  v_n int := 0;
  v_status_final text;
begin
  if not public.pa_eh_aprovador() then
    return json_build_object('ok', false, 'msg', 'Só o aprovador decide pedidos de alteração.');
  end if;
  v_por := (select p.id from public.perfis p where p.id = v_uid);
  select * into r from public.pa_pedidos where id = p_pedido for update;
  if not found then return json_build_object('ok', false, 'msg', 'Pedido não encontrado.'); end if;
  if r.status not in ('pendente', 'erro') then
    return json_build_object('ok', false, 'msg', 'Este pedido já foi decidido.');
  end if;
  v_origem := 'pedido_alteracao:' || r.id;

  if p_decisao = 'recusar' then
    if length(btrim(coalesce(p_motivo_recusa, ''))) < 3 then
      return json_build_object('ok', false, 'msg', 'Informe o motivo da recusa.');
    end if;
    update public.pa_pedidos
       set status = 'recusado', decidido_por = v_uid, decidido_em = now(),
           motivo_recusa = left(btrim(p_motivo_recusa), 2000), erro_msg = null
     where id = r.id;
    insert into public.pa_historico (pedido_id, acao, por, detalhe)
    values (r.id, 'recusado', v_uid, jsonb_build_object('motivo', btrim(p_motivo_recusa)));
    return json_build_object('ok', true, 'msg', 'Pedido nº ' || r.id || ' recusado.');
  elsif p_decisao <> 'aprovar' then
    return json_build_object('ok', false, 'msg', 'Decisão inválida.');
  end if;

  -- outro: não há o que aplicar automaticamente.
  if r.tipo = 'outro' then
    update public.pa_pedidos set status = 'aprovado', decidido_por = v_uid, decidido_em = now(), erro_msg = null where id = r.id;
    insert into public.pa_historico (pedido_id, acao, por) values (r.id, 'aprovado', v_uid);
    return json_build_object('ok', true, 'msg', 'Pedido nº ' || r.id || ' aprovado. Faça a alteração e marque como aplicado.');
  end if;

  if r.aluno_id is null then
    return json_build_object('ok', false, 'msg', 'O aluno deste pedido não existe mais na base.');
  end if;

  begin
    if r.tipo = 'alterar_dado' then
      perform 1 from public.thb_alunos a where a.id = r.aluno_id and a.cancelado_em is null for update;
      if not found then raise exception 'O aluno deste pedido foi cancelado ou removido.' using errcode = '22023'; end if;
      v_agora := public.pa_valor_campo(r.aluno_id, r.campo);
      if v_agora is distinct from r.valor_atual and not coalesce(p_confirmar_conflito, false) then
        return json_build_object('ok', false, 'conflito', true,
          'agora', public.pa_exibir(r.campo, v_agora, public.pa_pode_ver_doc()),
          'msg', 'O valor mudou desde o pedido. Confira e confirme para aplicar mesmo assim.');
      end if;
      v_novo := public.pa_normalizar(r.campo,
                  case when p_valor_ajustado is null then r.valor_novo
                       when r.campo = 'endereco' and jsonb_typeof(p_valor_ajustado) = 'object' then r.valor_novo || p_valor_ajustado
                       else p_valor_ajustado end);
      if r.campo = 'email' and exists (select 1 from public.thb_alunos o
                                        where o.id <> r.aluno_id and lower(btrim(o.email)) = lower(public.pa_txt(v_novo))) then
        raise exception 'Esse e-mail já é de outro aluno na base.' using errcode = '22023';
      end if;
      if r.campo = 'endereco' then
        foreach v_k in array public.pa_colunas_endereco() loop
          if public.pa_set_coluna(r.aluno_id, v_k, v_novo ->> v_k, v_origem, v_por) then v_n := v_n + 1; end if;
        end loop;
      else
        -- O e-mail antigo fica no audit (valor_anterior) e no próprio pedido (valor_atual), para achar a compra antiga.
        if public.pa_set_coluna(r.aluno_id, r.campo, public.pa_txt(v_novo), v_origem, v_por) then v_n := v_n + 1; end if;
      end if;
      update public.pa_pedidos
         set status = 'aplicado', decidido_por = v_uid, decidido_em = now(), aplicado_em = now(),
             valor_aplicado = v_novo, conflito_confirmado = (v_agora is distinct from r.valor_atual),
             planilha_status = 'pendente', erro_msg = null
       where id = r.id;

    else -- trocar_socio
      -- Trava as linhas envolvidas em ordem de id (dois aprovadores ao mesmo tempo não se travam).
      perform 1 from public.thb_alunos a
       where a.id in (r.aluno_id, r.socio_sai_id, coalesce(r.socio_entra_id, r.aluno_id))
       order by a.id for update;
      select * into v_t from public.thb_alunos where id = r.aluno_id and cancelado_em is null;
      if not found then raise exception 'O titular foi cancelado ou removido.' using errcode = '22023'; end if;
      if v_t.socio_de_aluno_id is not null or coalesce(v_t.eh_socio, false) then
        raise exception 'O titular virou sócio de alguém depois do pedido. Recuse e peça de novo.' using errcode = '22023';
      end if;
      if r.socio_sai_id is null or not exists (select 1 from public.thb_alunos where id = r.socio_sai_id) then
        raise exception 'O sócio que sai não existe mais na base.' using errcode = '22023';
      end if;
      v_agora := jsonb_build_object('socio_sai_vinculado', public.pa_eh_socio_de(r.socio_sai_id, r.aluno_id));
      if not (v_agora ->> 'socio_sai_vinculado')::boolean and not coalesce(p_confirmar_conflito, false) then
        return json_build_object('ok', false, 'conflito', true, 'agora', 'O sócio que sai já não está vinculado a este titular.',
          'msg', 'O vínculo mudou desde o pedido. Confira e confirme para aplicar mesmo assim.');
      end if;

      v_nivel := public.pa_instrucao_canonica(v_t.instrucao, v_t.espaco_instrucao, false);
      if v_nivel is null then
        raise exception 'O titular está sem instrução e sem espaço: não dá para definir a instrução do sócio.' using errcode = '22023';
      end if;

      -- 1) Sai: só perde o vínculo. O acesso é tirado pelo caso de Remoção.
      perform public.pa_set_coluna(r.socio_sai_id, 'socio_de_aluno_id', null, v_origem, v_por);
      perform public.pa_set_coluna(r.socio_sai_id, 'socio_de_nome', null, v_origem, v_por);

      -- 2) Entra: existente ou novo.
      if r.socio_entra_id is not null then
        v_s2 := r.socio_entra_id;
        if not exists (select 1 from public.thb_alunos where id = v_s2 and cancelado_em is null) then
          raise exception 'O sócio que entra foi cancelado ou removido.' using errcode = '22023';
        end if;
        if exists (select 1 from public.thb_alunos where id = v_s2 and socio_de_aluno_id is not null and socio_de_aluno_id <> v_t.id) then
          raise exception 'O sócio que entra virou sócio de outro titular depois do pedido.' using errcode = '22023';
        end if;
        if exists (select 1 from public.thb_alunos o where o.socio_de_aluno_id = v_s2 and o.cancelado_em is null) then
          raise exception 'O sócio que entra é titular de outros sócios.' using errcode = '22023';
        end if;
      else
        if exists (select 1 from public.thb_alunos o where lower(btrim(o.email)) = lower(r.socio_entra_novo ->> 'email')) then
          raise exception 'O e-mail do sócio novo já entrou na base depois do pedido: recuse e peça com o sócio existente.' using errcode = '22023';
        end if;
        insert into public.thb_alunos (nome, email, telefone, documento, fonte, atualizado_em, atualizado_por)
        values (r.socio_entra_novo ->> 'nome', r.socio_entra_novo ->> 'email', r.socio_entra_novo ->> 'telefone',
                r.socio_entra_novo ->> 'documento', 'pedido_alteracao', now(), v_por)
        returning id into v_s2;
        update public.pa_pedidos set socio_entra_id = v_s2 where id = r.id;
      end if;
      perform public.pa_set_coluna(v_s2, 'eh_socio', 'true', v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'socio_de_aluno_id', v_t.id::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'socio_de_nome', v_t.nome, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'instrucao', v_nivel || ' - SÓCIO', v_origem, v_por);
      if v_t.espaco_instrucao is not null then
        perform public.pa_set_coluna(v_s2, 'espaco_instrucao', v_t.espaco_instrucao, v_origem, v_por);
      end if;
      perform public.pa_set_coluna(v_s2, 'data_expiracao', v_t.data_expiracao::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'mes_expiracao', v_t.mes_expiracao::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'ano_expiracao', v_t.ano_expiracao::text, v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'regra_acesso', 'Acompanha titular', v_origem, v_por);
      perform public.pa_set_coluna(v_s2, 'status_acesso_central', 'Acompanha titular', v_origem, v_por);

      -- 3) Titular: recontagem de sócios.
      v_num := public.pa_contar_socios(v_t.id);
      perform public.pa_set_coluna(v_t.id, 'num_socios', v_num::text, v_origem, v_por);

      -- 4) Caso de Remoção para quem saiu.
      v_caso := public.pa_abrir_caso_remocao(r.id, r.socio_sai_id, v_t.nome);

      update public.pa_pedidos
         set status = 'aplicado', decidido_por = v_uid, decidido_em = now(), aplicado_em = now(),
             valor_aplicado = jsonb_build_object('socio_sai_id', r.socio_sai_id, 'socio_entra_id', v_s2,
                                                 'instrucao', v_nivel || ' - SÓCIO', 'num_socios', v_num),
             conflito_confirmado = not (v_agora ->> 'socio_sai_vinculado')::boolean,
             ra_caso_id = v_caso, planilha_status = 'pendente', erro_msg = null
       where id = r.id;
      insert into public.pa_historico (pedido_id, acao, por, detalhe)
      values (r.id, 'caso_remocao_aberto', v_uid, jsonb_build_object('caso', v_caso, 'socio', r.socio_sai_id));
    end if;

    insert into public.pa_historico (pedido_id, acao, por, detalhe)
    values (r.id, 'aplicado', v_uid, jsonb_build_object('ajustado', p_valor_ajustado is not null,
                                                        'conflito_confirmado', coalesce(p_confirmar_conflito, false),
                                                        'colunas', v_n));
  exception
    when sqlstate '22023' then
      -- Validação: nada foi gravado, o pedido segue como estava para o aprovador ajustar ou recusar.
      return json_build_object('ok', false, 'msg', sqlerrm);
    when others then
      update public.pa_pedidos set status = 'erro', erro_msg = left(sqlerrm, 500) where id = r.id;
      insert into public.pa_historico (pedido_id, acao, por, detalhe)
      values (r.id, 'erro', v_uid, jsonb_build_object('sqlstate', sqlstate, 'msg', sqlerrm));
      return json_build_object('ok', false, 'msg', 'Erro ao aplicar (nada foi gravado no aluno): ' || sqlerrm);
  end;

  select status into v_status_final from public.pa_pedidos where id = r.id;
  return json_build_object('ok', true, 'msg', 'Pedido nº ' || r.id || ' aplicado.'
    || case when v_caso is not null then ' Caso de Remoção de Acessos aberto para o sócio que saiu.' else '' end,
    'status', v_status_final, 'ra_caso_id', v_caso);
end
$$;

-- Pedido "outro" aprovado: o aprovador fez à mão e marca como aplicado.
create function public.pa_marcar_aplicado(p_pedido bigint, p_obs text default null)
returns json language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := (select auth.uid());
begin
  if not public.pa_eh_aprovador() then
    return json_build_object('ok', false, 'msg', 'Só o aprovador marca pedidos como aplicados.');
  end if;
  update public.pa_pedidos set status = 'aplicado', aplicado_em = now()
   where id = p_pedido and tipo = 'outro' and status = 'aprovado';
  if not found then return json_build_object('ok', false, 'msg', 'Só pedido "outro" aprovado pode ser marcado.'); end if;
  insert into public.pa_historico (pedido_id, acao, por, detalhe)
  values (p_pedido, 'marcado_aplicado', v_uid, jsonb_build_object('obs', nullif(btrim(coalesce(p_obs, '')), '')));
  return json_build_object('ok', true, 'msg', 'Pedido nº ' || p_pedido || ' marcado como aplicado.');
end
$$;

-- ─── 10. Quem executa o quê ─────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.proname like 'pa\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
end
$grants$;
grant execute on function
  public.pa_meu_papel(), public.pa_buscar_alunos(text, text[], text[], text, int), public.pa_socios_do_titular(uuid),
  public.pa_valor_atual(uuid, text), public.pa_turmas(), public.pa_criar(jsonb), public.pa_meus_pedidos(), public.pa_fila(boolean),
  public.pa_decidir(bigint, text, text, jsonb, boolean), public.pa_marcar_aplicado(bigint, text)
  to authenticated;

-- ─── 11. Conferência (aborta se algo nasceu aberto ou fora do padrão) ───────────────────────────────────────────────
do $confere$
declare
  r text;
  t text;
  f record;
  v_publicas text[] := array['pa_meu_papel', 'pa_buscar_alunos', 'pa_socios_do_titular', 'pa_valor_atual', 'pa_turmas', 'pa_criar',
                             'pa_meus_pedidos', 'pa_fila', 'pa_decidir', 'pa_marcar_aplicado'];
begin
  foreach t in array array['public.pa_aprovadores', 'public.pa_pedidos', 'public.pa_historico'] loop
    foreach r in array array['anon', 'authenticated'] loop
      if has_table_privilege(r, t, 'select, insert, update, delete, truncate, references, trigger') then
        raise exception '20261005j: % tem privilégio em %', r, t;
      end if;
    end loop;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception '20261005j: RLS desligada em %', t;
    end if;
  end loop;

  for f in select p.oid::regprocedure as sig, p.proname, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pa\_%' loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005j: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005j: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005j: PUBLIC executa %', f.sig;
    end if;
    if (f.proname = any(v_publicas)) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005j: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_publicas) and not f.prosecdef then
      raise exception '20261005j: % deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;

  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_publicas)) <> 10 then
    raise exception '20261005j: esperava 10 funções públicas pa_*';
  end if;
  if pg_get_constraintdef((select k.oid from pg_constraint k
                            where k.conrelid = 'public.ra_casos'::regclass and k.conname = 'ra_casos_tipo_check'))
     not like '%troca_socio%' then
    raise exception '20261005j: ra_casos_tipo_check sem troca_socio';
  end if;
end
$confere$;

-- ═══ ENSAIO: testes (como a tela chamaria, com JWT simulado) ════════════════════════════════════════════════════════
-- Alunos de TESTE (somem no rollback). Victor = quem pede E quem aprova (admin + pa_aprovadores).
insert into public.thb_alunos (id, nome, email, telefone, documento, instrucao, espaco_instrucao, data_expiracao,
                               mes_expiracao, ano_expiracao, num_socios, fonte)
values ('e0000000-0000-4000-8000-000000000001', 'ZZ Ensaio Titular', 'zz.ensaio.titular@exemplo.invalid', '5521900000001',
        '00000000191', 'AURUM', 'aurum', '2027-03-31', 3, 2027, 1, 'ensaio_20261005j'),
       ('e0000000-0000-4000-8000-000000000002', 'ZZ Ensaio Socio Sai', 'zz.ensaio.sai@exemplo.invalid', null, null,
        'AURUM - SÓCIO', 'aurum', '2027-03-31', 3, 2027, null, 'ensaio_20261005j'),
       ('e0000000-0000-4000-8000-000000000003', 'ZZ Ensaio Socio Entra', 'zz.ensaio.entra@exemplo.invalid', null, null,
        'THB', 'holding_masters', '2026-06-30', 6, 2026, null, 'ensaio_20261005j');
update public.thb_alunos set eh_socio = true, socio_de_aluno_id = 'e0000000-0000-4000-8000-000000000001',
       socio_de_nome = 'ZZ Ensaio Titular' where id = 'e0000000-0000-4000-8000-000000000002';
insert into pg_temp._z_out (passo, linha) values ('1.alunos_teste', (select count(*)::text from public.thb_alunos where fonte = 'ensaio_20261005j'));

-- 2. Sem permissão (uid aleatório) e grants
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000ff","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('2.sem_permissao_criar',
  public.pa_criar('{"tipo":"outro","aluno_id":"e0000000-0000-4000-8000-000000000001","descricao":"teste x","motivo":"teste de permissão"}')::text);
insert into pg_temp._z_out (passo, linha) values ('2.sem_permissao_busca', (select count(*)::text from public.pa_buscar_alunos('zz ensaio')));
reset role;
insert into pg_temp._z_out (passo, linha)
select '2.grants', r || ' ' || t || ' tabela=' || has_table_privilege(r, t, 'select,insert,update,delete')
  from unnest(array['anon','authenticated']) r, unnest(array['public.pa_pedidos','public.pa_historico','public.pa_aprovadores']) t;
insert into pg_temp._z_out (passo, linha)
select '2.grants_funcoes', p.proname || ' anon=' || has_function_privilege('anon', p.oid, 'execute')
       || ' auth=' || has_function_privilege('authenticated', p.oid, 'execute') || ' definer=' || p.prosecdef
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pa\_%' order by p.proname;

-- 3. Como o Victor
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('3.papel', public.pa_meu_papel()::text);
insert into pg_temp._z_out (passo, linha) select '3.busca', b::text from public.pa_buscar_alunos('zz ensaio') b;
insert into pg_temp._z_out (passo, linha) select '3.socios', b::text from public.pa_socios_do_titular('e0000000-0000-4000-8000-000000000001') b;
insert into pg_temp._z_out (passo, linha) values ('3.valor_atual', public.pa_valor_atual('e0000000-0000-4000-8000-000000000001', 'email')::text);
-- alterar_dado + aprovar
insert into pg_temp._z_out (passo, linha) values ('4.criar_email', public.pa_criar(
  '{"tipo":"alterar_dado","aluno_id":"e0000000-0000-4000-8000-000000000001","campo":"email","valor_novo":"zz.ensaio.novo@exemplo.invalid","motivo":"ensaio da migration"}')::text);
insert into pg_temp._z_out (passo, linha) values ('4.criar_campo_proibido', public.pa_criar(
  '{"tipo":"alterar_dado","aluno_id":"e0000000-0000-4000-8000-000000000001","campo":"valor_pago","valor_novo":"1","motivo":"ensaio da migration"}')::text);
insert into pg_temp._z_out (passo, linha) values ('4.aprovar_email', public.pa_decidir(
  (select (linha::json->>'numero')::bigint from pg_temp._z_out where passo = '4.criar_email'), 'aprovar')::text);
reset role;
insert into pg_temp._z_out (passo, linha) select '4.aluno_email', email || ' por=' || coalesce(atualizado_por::text, '?')
  from public.thb_alunos where id = 'e0000000-0000-4000-8000-000000000001';
insert into pg_temp._z_out (passo, linha) select '4.audit', row_to_json(l)::text
  from public.thb_alunos_audit_log l where l.aluno_id = 'e0000000-0000-4000-8000-000000000001' and l.origem like 'pedido_alteracao:%';
-- conflito: pede telefone, o valor muda por fora, aprovar não aplica sem confirmar
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('5.criar_tel', public.pa_criar(
  '{"tipo":"alterar_dado","aluno_id":"e0000000-0000-4000-8000-000000000001","campo":"telefone","valor_novo":"21 98888-0001","motivo":"ensaio da migration"}')::text);
reset role;
update public.thb_alunos set telefone = '5521977770000' where id = 'e0000000-0000-4000-8000-000000000001';
set local role authenticated;
insert into pg_temp._z_out (passo, linha) values ('5.aprovar_sem_confirmar', public.pa_decidir((select (linha::json->>'numero')::bigint from pg_temp._z_out where passo = '5.criar_tel'), 'aprovar')::text);
insert into pg_temp._z_out (passo, linha) values ('5.aprovar_confirmando', public.pa_decidir((select (linha::json->>'numero')::bigint from pg_temp._z_out where passo = '5.criar_tel'), 'aprovar', null, null, true)::text);
-- recusa
insert into pg_temp._z_out (passo, linha) values ('6.criar_nome', public.pa_criar(
  '{"tipo":"alterar_dado","aluno_id":"e0000000-0000-4000-8000-000000000001","campo":"nome","valor_novo":"ZZ Ensaio Outro Nome","motivo":"ensaio da migration"}')::text);
insert into pg_temp._z_out (passo, linha) values ('6.recusar', public.pa_decidir((select (linha::json->>'numero')::bigint from pg_temp._z_out where passo = '6.criar_nome'), 'recusar', 'ensaio: recusa')::text);
-- troca de sócio
insert into pg_temp._z_out (passo, linha) values ('7.criar_troca', public.pa_criar(
  '{"tipo":"trocar_socio","aluno_id":"e0000000-0000-4000-8000-000000000001","socio_sai_id":"e0000000-0000-4000-8000-000000000002","socio_entra_id":"e0000000-0000-4000-8000-000000000003","motivo":"ensaio da migration"}')::text);
insert into pg_temp._z_out (passo, linha) values ('7.aprovar_troca', public.pa_decidir((select (linha::json->>'numero')::bigint from pg_temp._z_out where passo = '7.criar_troca'), 'aprovar')::text);
insert into pg_temp._z_out (passo, linha) select '7.meus_pedidos', x::text from public.pa_meus_pedidos() x;
reset role;
insert into pg_temp._z_out (passo, linha)
select '7.alunos_depois', row_to_json(a)::text
  from (select nome, eh_socio, socio_de_aluno_id, socio_de_nome, instrucao, espaco_instrucao, data_expiracao, regra_acesso,
               status_acesso_central, num_socios from public.thb_alunos where fonte = 'ensaio_20261005j' order by nome) a;
insert into pg_temp._z_out (passo, linha)
select '7.caso_remocao', row_to_json(c)::text
  from (select c.tipo, c.status, c.nome, c.hotmart_transaction, c.prazo_em, c.origem,
               (select count(*) from public.ra_pessoas p where p.caso_id = c.id) as pessoas
          from public.ra_casos c where c.hotmart_transaction like 'PEDIDO-ALTERACAO-%') c;
-- leitura direta da tabela como authenticated tem de falhar (42501)
do $t$
begin
  set local role authenticated;
  begin
    perform 1 from public.pa_pedidos limit 1;
    insert into pg_temp._z_out (passo, linha) values ('8.select_direto', 'LEU (ERRADO)');
  exception when insufficient_privilege then
    insert into pg_temp._z_out (passo, linha) values ('8.select_direto', '42501 ok');
  end;
  reset role;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
