-- 20260928z50 — Protocolo oficial dos relatórios do Financeiro exportados em PDF.
--
-- ESTADO: aplicada em produção (mbvybujpkwuorhtdzcde) em 28/09/2026. Conferência pós-aplicação:
--   ACL das 3 funções: só authenticated/postgres/service_role, sem PUBLIC nem anon.
--   Tabela fin.relatorios_emitidos: grants só para postgres (dono); nada para anon/authenticated.
--   explain (analyze, buffers) da verificação por protocolo: Index Scan, Execution Time 0.122 ms.
--
-- Fluxo em 2 etapas:
--   1) fn_fin_relatorio_emitir  → grava a emissão (quem, quando, tipo, nível de PII, recorte, linhas, totais)
--                                 e devolve o protocolo GP-REL-AAAA-NNNNNN para o navegador imprimir no PDF.
--   2) fn_fin_relatorio_selar   → o navegador monta o PDF, calcula o SHA-256 e sela. Só quem emitiu,
--                                 uma vez só, até 15 min depois da emissão. Passou disso = "não concluído".
--   fn_fin_relatorio_verificar  → conferência manual dentro do sistema (só quem vê o Financeiro).
--
-- Protocolo: sequência GLOBAL (não reinicia por ano). AAAA = ano da emissão em America/Sao_Paulo.
--   Ex.: GP-REL-2026-000041, GP-REL-2027-000042. Motivo: reiniciar por ano exige contador por ano com
--   lock/upsert; a sequência nativa dá unicidade sem lock. Buracos na numeração são esperados
--   (emissão que falha depois do nextval consome o número) — o protocolo é identificador, não contagem.
--   maxvalue 999999 + no cycle: estourar dá erro explícito em vez de protocolo repetido/truncado
--   (a dezenas de emissões por mês, são milênios).
--
-- Acesso: RLS ativa SEM nenhuma policy + revoke de public/anon/authenticated → ninguém lê nem grava a
--   tabela direto. Todo acesso pelas 3 funções SECURITY DEFINER, cada uma checando gp_pode_ver_financeiro().
--   Nenhuma policy consulta a tabela (não há policy) → sem risco de recursão de RLS.
--
-- Reversão (nada depende disto ainda):
--   drop function public.fn_fin_relatorio_verificar(text);
--   drop function public.fn_fin_relatorio_selar(text, text, int);
--   drop function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb);
--   drop table fin.relatorios_emitidos;            -- arquivar antes (create table ... as) se já tiver emissão real
--   drop sequence fin.relatorios_emitidos_protocolo_seq;
--   drop function fin.relatorio_recorte_valido(jsonb); drop function fin.relatorio_janela_selo();

-- ─── 0. Regras únicas (usadas pela tabela E pelas funções) ───────────────────
-- Janela para selar. Uma fonte só: selar e verificar leem daqui.
create or replace function fin.relatorio_janela_selo()
returns interval language sql immutable set search_path = ''
as $$ select interval '15 minutes' $$;

-- Recorte = filtros aplicados (família, período, canal…). Objeto JSON, ≤ 4 KB, e SEM chave de busca livre
-- ou de identificação pessoal: texto de busca é quase sempre nome de aluno e o PDF sai da empresa.
-- Só inspeciona chaves do 1º nível (ver Risco no relatório da migration).
create or replace function fin.relatorio_recorte_valido(p jsonb)
returns boolean language sql immutable set search_path = ''
as $$
  select p is not null
     and jsonb_typeof(p) = 'object'
     and octet_length(p::text) <= 4096
     and not (p ?| array['busca','q','search','texto','termo','pesquisa','nome','email','cpf','documento','telefone'])
$$;
revoke all on function fin.relatorio_janela_selo()         from public, anon, authenticated;
revoke all on function fin.relatorio_recorte_valido(jsonb) from public, anon, authenticated;

-- ─── 1. Tabela ───────────────────────────────────────────────────────────────
create sequence if not exists fin.relatorios_emitidos_protocolo_seq
  as bigint minvalue 1 maxvalue 999999 no cycle;

create table if not exists fin.relatorios_emitidos (
  id               bigserial primary key,
  protocolo        text not null,
  tipo             text not null,
  nivel            text not null,
  recorte          jsonb not null default '{}'::jsonb,
  linhas           int  not null,
  totais           jsonb not null default '{}'::jsonb,
  gerado_por       uuid references public.perfis(id) on delete set null,  -- null só se o perfil for apagado depois
  gerado_por_nome  text not null,                                         -- snapshot no momento da emissão
  emitido_em       timestamptz not null default now(),
  sha256           text,
  paginas          int,
  selado_em        timestamptz,
  constraint relatorios_emitidos_protocolo_key unique (protocolo),
  constraint relatorios_emitidos_protocolo_formato check (protocolo ~ '^GP-REL-[0-9]{4}-[0-9]{6}$'),
  constraint relatorios_emitidos_tipo_check
    check (tipo in ('board','pessoas','conciliacao','identidade','acelera','prorata')),
  constraint relatorios_emitidos_nivel_check
    check (nivel in ('completo','sem_dado_pessoal','so_numeros')),
  -- decisão do Marcio: "Mesma pessoa?" só existe no nível completo, nunca mascarado
  constraint relatorios_emitidos_identidade_so_completo
    check (tipo <> 'identidade' or nivel = 'completo'),
  constraint relatorios_emitidos_recorte_check check (fin.relatorio_recorte_valido(recorte)),
  constraint relatorios_emitidos_linhas_check check (linhas >= 0),
  constraint relatorios_emitidos_totais_check
    check (jsonb_typeof(totais) = 'object' and octet_length(totais::text) <= 8192),
  constraint relatorios_emitidos_sha256_formato check (sha256 is null or sha256 ~ '^[0-9a-f]{64}$'),
  constraint relatorios_emitidos_paginas_check check (paginas is null or paginas >= 1),
  -- selo é tudo-ou-nada: os três campos juntos, ou nenhum
  constraint relatorios_emitidos_selo_inteiro check (
    (selado_em is null and sha256 is null and paginas is null)
    or (selado_em is not null and sha256 is not null and paginas is not null))
);
-- índice único de protocolo = o da constraint relatorios_emitidos_protocolo_key (não duplicar)
create index if not exists relatorios_emitidos_emitido_em_idx on fin.relatorios_emitidos (emitido_em desc);

alter table fin.relatorios_emitidos enable row level security;
-- sem policy de propósito: RLS nega tudo a quem não é dono; o acesso é só pelas funções abaixo
revoke all on fin.relatorios_emitidos from public, anon, authenticated;
revoke all on sequence fin.relatorios_emitidos_id_seq           from public, anon, authenticated;
revoke all on sequence fin.relatorios_emitidos_protocolo_seq    from public, anon, authenticated;

-- ─── 2. Emitir ───────────────────────────────────────────────────────────────
create or replace function public.fn_fin_relatorio_emitir(
  p_tipo text, p_nivel text, p_recorte jsonb, p_linhas int, p_totais jsonb)
returns table (protocolo text, emitido_em timestamptz, gerado_por_nome text)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid  := auth.uid();
  v_recorte jsonb := coalesce(p_recorte, '{}'::jsonb);
  v_totais  jsonb := coalesce(p_totais,  '{}'::jsonb);
  v_nome    text;
  v_agora   timestamptz := now();
  v_proto   text;
begin
  if v_uid is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_tipo is null or p_tipo not in ('board','pessoas','conciliacao','identidade','acelera','prorata') then
    raise exception 'Tipo de relatório inválido.' using errcode = '22023';
  end if;
  if p_nivel is null or p_nivel not in ('completo','sem_dado_pessoal','so_numeros') then
    raise exception 'Nível de dado pessoal inválido.' using errcode = '22023';
  end if;
  if p_tipo = 'identidade' and p_nivel <> 'completo' then
    raise exception 'O relatório de identidade só existe no nível completo.' using errcode = '22023';
  end if;
  if not fin.relatorio_recorte_valido(v_recorte) then
    raise exception 'Recorte inválido: precisa ser objeto até 4 KB e sem texto de busca ou dado pessoal.'
      using errcode = '22023';
  end if;
  if p_linhas is null or p_linhas < 0 then
    raise exception 'Quantidade de linhas inválida.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_totais) <> 'object' or octet_length(v_totais::text) > 8192 then
    raise exception 'Totais inválidos: precisa ser objeto até 8 KB.' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p.nome), ''), p.email) into v_nome
    from public.perfis p where p.id = v_uid;
  if v_nome is null then
    raise exception 'Perfil sem nome.' using errcode = '42501';
  end if;

  v_proto := 'GP-REL-' || to_char(v_agora at time zone 'America/Sao_Paulo', 'YYYY') || '-'
             || lpad(nextval('fin.relatorios_emitidos_protocolo_seq')::text, 6, '0');

  return query
  insert into fin.relatorios_emitidos (protocolo, tipo, nivel, recorte, linhas, totais, gerado_por, gerado_por_nome, emitido_em)
  values (v_proto, p_tipo, p_nivel, v_recorte, p_linhas, v_totais, v_uid, v_nome, v_agora)
  returning protocolo, emitido_em, gerado_por_nome;
end $$;

-- ─── 3. Selar ────────────────────────────────────────────────────────────────
-- true = selou agora. false = não existe, não é seu, já selado ou fora da janela (não concluído).
create or replace function public.fn_fin_relatorio_selar(p_protocolo text, p_sha256 text, p_paginas int)
returns boolean
language plpgsql volatile security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_hash text := lower(btrim(p_sha256));
  v_n    int;
begin
  if v_uid is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_hash is null or v_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'SHA-256 inválido (64 caracteres hexadecimais).' using errcode = '22023';
  end if;
  if p_paginas is null or p_paginas < 1 then
    raise exception 'Quantidade de páginas inválida.' using errcode = '22023';
  end if;

  update fin.relatorios_emitidos r
     set sha256 = v_hash, paginas = p_paginas, selado_em = now()
   where r.protocolo = upper(btrim(p_protocolo))
     and r.gerado_por = v_uid
     and r.selado_em is null
     and r.emitido_em >= now() - fin.relatorio_janela_selo();
  get diagnostics v_n = row_count;
  return v_n = 1;
end $$;

-- ─── 4. Verificar ────────────────────────────────────────────────────────────
-- Devolve o sha256 inteiro: é o que permite conferir o PDF recebido (recalcular o hash e comparar).
-- Hash de PDF não é reversível e quem chama já vê o Financeiro inteiro — não há o que esconder nele.
-- situacao: 'selado' | 'aguardando_selo' (dentro da janela) | 'nao_concluido' (janela passou sem selo).
create or replace function public.fn_fin_relatorio_verificar(p_protocolo text)
returns table (protocolo text, tipo text, nivel text, recorte jsonb, linhas int, totais jsonb,
               emitido_em timestamptz, gerado_por_nome text, selado_em timestamptz, paginas int,
               sha256 text, situacao text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if auth.uid() is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select r.protocolo, r.tipo, r.nivel, r.recorte, r.linhas, r.totais, r.emitido_em, r.gerado_por_nome,
         r.selado_em, r.paginas, r.sha256,
         case when r.selado_em is not null then 'selado'
              when r.emitido_em >= now() - fin.relatorio_janela_selo() then 'aguardando_selo'
              else 'nao_concluido' end
    from fin.relatorios_emitidos r
   where r.protocolo = upper(btrim(p_protocolo));
end $$;

-- ─── 5. Grants: PUBLIC primeiro (anon herda de PUBLIC — revoke só de anon não pega) ──
revoke all on function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb) from public, anon;
revoke all on function public.fn_fin_relatorio_selar(text, text, int)                from public, anon;
revoke all on function public.fn_fin_relatorio_verificar(text)                       from public, anon;
grant execute on function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb) to authenticated;
grant execute on function public.fn_fin_relatorio_selar(text, text, int)                to authenticated;
grant execute on function public.fn_fin_relatorio_verificar(text)                       to authenticated;

-- ─── Conferência pós-aplicação (rodar e colar; não faz parte da migration) ───
-- ACL sem entrada PUBLIC ('=X/...') e sem anon:
--   select p.proname, a::text from pg_proc p, unnest(p.proacl) a
--    where p.proname like 'fn_fin_relatorio_%' order by 1, 2;
-- Tabela sem grant para anon/authenticated:
--   select grantee, string_agg(privilege_type, ', ') from information_schema.role_table_grants
--    where table_schema = 'fin' and table_name = 'relatorios_emitidos' group by 1;
-- Plano da verificação (SELECT, seguro):
--   explain (analyze, buffers) select * from fin.relatorios_emitidos where protocolo = 'GP-REL-2026-000001';
