-- 20261005k: Pedidos de alteração, troca de sócio com PESSOA NOVA em cadastro completo (endereço e documento)
--
-- O QUE FAZ
--   Pedido do Victor (05/10/2026). Na troca de sócio com "Pessoa nova", a 20261005j só pedia nome, e-mail, telefone e
--   documento (opcional). Agora o sócio novo entra com o cadastro completo:
--     nome, e-mail, telefone, CPF/CNPJ (todos obrigatórios), profissão (opcional) e endereço
--     (cep, endereco_logradouro, endereco_numero, endereco_complemento, bairro, cidade, estado, pais).
--   "Mesmo endereço do sócio que sai": o pedido guarda a FOTO do endereço de quem sai no momento do pedido
--     (socio_entra_novo.endereco, com endereco_mantido = true). Ao aprovar, grava essa foto: o aprovador vê
--     exatamente o que vai para thb_alunos. O endereço vindo da tela é ignorado nesse caso (o banco lê o de quem sai).
--   Validação no banco (espelho da tela, web/modules/alunos/domain/pedidos-alteracao.ts):
--     CPF/CNPJ com dígito verificador; e-mail; telefone (Brasil: 55 + DDD + número, 12 ou 13 dígitos; exterior:
--     8 a 15 dígitos com o código do país); Brasil: CEP com 8 dígitos e UF entre as 27; exterior: estado/província e
--     CEP em texto livre. Duplicata: e-mail OU documento já na base = recusa, com a sugestão de escolher a pessoa
--     existente (a tela avisa antes por pa_duplicata_pessoa).
--   "Alterar dado" de endereço: estado tem de ser uma das 27 UFs quando o país é Brasil (antes bastava 2 letras);
--     exterior aceita estado/província livre. Documento (alterar dado) passa a exigir dígito verificador.
--
--   Funções novas: pa_ufs, pa_doc_valido, pa_eh_brasil, pa_endereco, pa_telefone_pessoa (internas, sem grant) e
--     pa_duplicata_pessoa (tela, authenticated). Substituídas (mesma assinatura, grants mantidos): pa_normalizar,
--     pa_criar, pa_decidir. Nenhuma tabela muda: socio_entra_novo já é jsonb.
--   Pedidos antigos (socio_entra_novo sem endereço) continuam aprovando: endereço nulo, país 'Brasil' (default da coluna).
--
-- AS 5 PERGUNTAS
--   escala: dezenas de pedidos por mês. A checagem de duplicata por documento varre thb_alunos (~2 mil linhas,
--     regexp nos dígitos), uma vez por pedido e por digitação completa de documento na tela (debounce): poucos ms.
--   índice: nenhum novo (o e-mail já tem índice em lower(trim(email)); documento não, e não compensa para 2 mil linhas).
--   frequência: pa_duplicata_pessoa só roda com e-mail válido ou documento válido digitado (debounce de 400 ms).
--   repetição: nenhuma query por linha.
--   reversão: bloco REVERSÃO no fim.
--
-- ENSAIO: infra/supabase/migrations/20261005k_ensaio.sql (begin … rollback).

set local lock_timeout = '3s';

-- ─── 0. Guardas ─────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_falta text;
begin
  select string_agg(x.t || '.' || x.c, ', ') into v_falta
    from (values
      ('thb_alunos','tipo_documento'), ('thb_alunos','profissao'), ('thb_alunos','cep'),
      ('thb_alunos','endereco_logradouro'), ('thb_alunos','endereco_numero'), ('thb_alunos','endereco_complemento'),
      ('thb_alunos','bairro'), ('thb_alunos','cidade'), ('thb_alunos','estado'), ('thb_alunos','pais'),
      ('pa_pedidos','socio_entra_novo')
    ) x(t, c)
   where not exists (select 1 from information_schema.columns ic
                      where ic.table_schema = 'public' and ic.table_name = x.t and ic.column_name = x.c);
  if v_falta is not null then
    raise exception '20261005k: colunas ausentes: %', v_falta;
  end if;
  if to_regprocedure('public.pa_criar(jsonb)') is null
     or to_regprocedure('public.pa_decidir(bigint, text, text, jsonb, boolean)') is null
     or to_regprocedure('public.pa_normalizar(text, jsonb)') is null then
    raise exception '20261005k: a 20261005j (pedidos de alteração) não está aplicada';
  end if;
  if to_regprocedure('public.pa_doc_valido(text)') is not null then
    raise exception '20261005k: pa_doc_valido já existe (migration já aplicada?)';
  end if;
end
$guarda$;

-- ─── 1. Regras puras novas ──────────────────────────────────────────────────────────────────────────────────────────
-- As 27 UFs. Espelho: UFS em web/modules/alunos/domain/pedidos-alteracao.ts.
create function public.pa_ufs()
returns text[] language sql immutable set search_path = '' as $$
  select array['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE',
               'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO']::text[];
$$;

-- CPF (11) ou CNPJ (14) com dígito verificador. Repetidos (111.111.111-11) são inválidos. Espelho: documentoValido().
create function public.pa_doc_valido(p text)
returns boolean language plpgsql immutable set search_path = '' as $$
declare
  d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
  s int;
  r int;
  i int;
  w int[];
begin
  if length(d) = 11 then
    if d = repeat(left(d, 1), 11) then return false; end if;
    s := 0;
    for i in 1..9 loop s := s + substr(d, i, 1)::int * (11 - i); end loop;
    r := (s * 10) % 11; if r = 10 then r := 0; end if;
    if r <> substr(d, 10, 1)::int then return false; end if;
    s := 0;
    for i in 1..10 loop s := s + substr(d, i, 1)::int * (12 - i); end loop;
    r := (s * 10) % 11; if r = 10 then r := 0; end if;
    return r = substr(d, 11, 1)::int;
  elsif length(d) = 14 then
    if d = repeat(left(d, 1), 14) then return false; end if;
    w := array[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    s := 0;
    for i in 1..12 loop s := s + substr(d, i, 1)::int * w[i]; end loop;
    r := s % 11; r := case when r < 2 then 0 else 11 - r end;
    if r <> substr(d, 13, 1)::int then return false; end if;
    w := array[6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    s := 0;
    for i in 1..13 loop s := s + substr(d, i, 1)::int * w[i]; end loop;
    r := s % 11; r := case when r < 2 then 0 else 11 - r end;
    return r = substr(d, 14, 1)::int;
  end if;
  return false;
end
$$;

-- País vazio conta como Brasil (default da coluna thb_alunos.pais). Espelho: ehBrasil().
create function public.pa_eh_brasil(p text)
returns boolean language sql immutable set search_path = '' as $$
  select coalesce(public.pa_chave_nome(p), 'brasil') in ('brasil', 'brazil', 'br');
$$;

-- Valida e normaliza um endereço (as 8 colunas de pa_colunas_endereco). p_completo = cadastro de pessoa nova
-- (obrigatórios); sem p_completo = "alterar dado" (pode vir parcial, como na 20261005j). Espelho: validarEndereco().
--   Brasil: CEP só dígitos (8), estado = UF da lista, país gravado como 'Brasil'.
--   Exterior: CEP (até 20) e estado/província (até 100) em texto livre.
create function public.pa_endereco(p jsonb, p_completo boolean)
returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  v_pais text;
  v_br boolean;
  k text;
  v text;
  v_out jsonb := '{}'::jsonb;
  v_falta text[] := '{}';
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Endereço inválido.' using errcode = '22023';
  end if;
  v_pais := left(public.pa_txt(p -> 'pais'), 100);
  v_br := public.pa_eh_brasil(v_pais);
  if v_br and (v_pais is not null or p_completo) then v_pais := 'Brasil'; end if;

  foreach k in array public.pa_colunas_endereco() loop
    v := nullif(btrim(regexp_replace(coalesce(public.pa_txt(p -> k), ''), '\s+', ' ', 'g')), '');
    v := left(v, 200);
    if k = 'pais' then
      v := v_pais;
    elsif k = 'cep' and v is not null then
      if v_br then
        v := regexp_replace(v, '\D', '', 'g');
        if length(v) <> 8 then raise exception 'CEP deve ter 8 dígitos.' using errcode = '22023'; end if;
      else
        v := left(v, 20);
      end if;
    elsif k = 'estado' and v is not null then
      if v_br then
        v := upper(v);
        if not (v = any(public.pa_ufs())) then
          raise exception 'Estado inválido: escolha uma das 27 UFs (ex.: SP).' using errcode = '22023';
        end if;
      else
        v := left(v, 100);
      end if;
    end if;
    v_out := v_out || jsonb_build_object(k, v);
  end loop;

  -- thb_alunos.estado é character(2) em produção: fora do Brasil a província vai junto da cidade, "Cidade (Província)",
  -- e o estado fica vazio. Nada se perde e o aprovador vê exatamente o que vai gravar (05/10/2026).
  if not v_br and v_out ->> 'estado' is not null then
    v_out := v_out || jsonb_build_object('cidade',
               case when v_out ->> 'cidade' is null then v_out ->> 'estado'
                    when lower(v_out ->> 'cidade') = lower(v_out ->> 'estado') then (v_out ->> 'cidade')
                    else (v_out ->> 'cidade') || ' (' || (v_out ->> 'estado') || ')' end,
               'estado', null);
  end if;

  if p_completo then
    if v_br then
      if v_out ->> 'cep' is null then v_falta := v_falta || 'CEP'::text; end if;
      if v_out ->> 'endereco_logradouro' is null then v_falta := v_falta || 'logradouro'::text; end if;
      if v_out ->> 'endereco_numero' is null then v_falta := v_falta || 'número'::text; end if;
      if v_out ->> 'bairro' is null then v_falta := v_falta || 'bairro'::text; end if;
      if v_out ->> 'cidade' is null then v_falta := v_falta || 'cidade'::text; end if;
      if v_out ->> 'estado' is null then v_falta := v_falta || 'estado'::text; end if;
    else
      if v_out ->> 'endereco_logradouro' is null then v_falta := v_falta || 'endereço'::text; end if;
      if v_out ->> 'cidade' is null then v_falta := v_falta || 'cidade'::text; end if;
    end if;
    if cardinality(v_falta) > 0 then
      raise exception 'Endereço incompleto: falta %.', array_to_string(v_falta, ', ') using errcode = '22023';
    end if;
  end if;
  return v_out;
end
$$;

-- Telefone de pessoa nova (obrigatório). Brasil: 55 + DDD + número (12 ou 13 dígitos). Exterior: código do país +
-- número, 8 a 15 dígitos (E.164). Grava só dígitos, como a Central. Espelho: normalizarTelefonePessoa().
create function public.pa_telefone_pessoa(p text, p_brasil boolean)
returns text language plpgsql immutable set search_path = '' as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if d = '' then raise exception 'Informe o telefone.' using errcode = '22023'; end if;
  if coalesce(p_brasil, true) then
    if length(d) in (10, 11) then d := '55' || d; end if;
    if d !~ '^55[1-9][0-9]{9,10}$' then
      raise exception 'Telefone inválido: use DDD + número (ex.: 21 99999-9999).' using errcode = '22023';
    end if;
  elsif length(d) < 8 or length(d) > 15 then
    raise exception 'Telefone internacional inválido: código do país + número, de 8 a 15 dígitos.' using errcode = '22023';
  end if;
  return d;
end
$$;

-- ─── 2. Tela: aviso de duplicata antes de enviar ────────────────────────────────────────────────────────────────────
-- Já existe aluno com este e-mail ou documento? Devolve o mesmo resumo da busca (e-mail mascarado, final do documento),
-- nunca o documento inteiro. Só checa documento com dígito verificador válido (não serve de oráculo de CPF parcial).
create function public.pa_duplicata_pessoa(p_email text, p_documento text)
returns json language plpgsql stable security definer set search_path = '' as $$
declare
  v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
  v_doc text := regexp_replace(coalesce(p_documento, ''), '\D', '', 'g');
  v_id_email uuid;
  v_id_doc uuid;
begin
  if not public.pa_pode_pedir() then return null; end if;
  if v_email is not null and v_email ~ '^[^\s@]+@[^\s@]+\.[^\s@]{2,}$' then
    select a.id into v_id_email from public.thb_alunos a
     where lower(btrim(a.email)) = v_email order by (a.cancelado_em is null) desc limit 1;
  end if;
  if public.pa_doc_valido(v_doc) then
    select a.id into v_id_doc from public.thb_alunos a
     where regexp_replace(coalesce(a.documento, ''), '\D', '', 'g') = v_doc order by (a.cancelado_em is null) desc limit 1;
  end if;
  return json_build_object(
    'email', case when v_id_email is not null then public.pa_resumo_aluno(v_id_email)::jsonb
                    || jsonb_build_object('cancelado', exists (select 1 from public.thb_alunos a where a.id = v_id_email and a.cancelado_em is not null)) end,
    'documento', case when v_id_doc is not null then public.pa_resumo_aluno(v_id_doc)::jsonb
                    || jsonb_build_object('cancelado', exists (select 1 from public.thb_alunos a where a.id = v_id_doc and a.cancelado_em is not null)) end);
end
$$;

-- ─── 3. Substituições (mesma assinatura da 20261005j; o grant existente continua valendo) ──────────────────────────

-- Valida e normaliza o valor pedido para um campo. Erro de validação = errcode 22023 com a mensagem para a tela.
create or replace function public.pa_normalizar(p_campo text, p_valor jsonb)
returns jsonb language plpgsql stable set search_path = '' as $$
declare
  v text := public.pa_txt(p_valor);
  d text;
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
    if not public.pa_doc_valido(d) then
      raise exception 'CPF ou CNPJ inválido: confira os dígitos.' using errcode = '22023';
    end if;
    return to_jsonb(d);
  elsif p_campo = 'endereco' then
    -- 20261005k: Brasil exige UF da lista; exterior aceita estado/província e CEP livres (pa_endereco).
    return public.pa_endereco(p_valor, false);
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

-- ─── 7. Criar pedido ────────────────────────────────────────────────────────────────────────────────────────────────
-- p: tipo, aluno_id, campo, valor_novo, socio_sai_id, socio_entra_id,
--    socio_entra_novo{nome,email,telefone,documento,profissao,endereco_mantido,endereco{8 colunas}},
--    descricao, motivo, evidencia
create or replace function public.pa_criar(p jsonb)
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
  v_sn jsonb;
  v_mantido boolean;
  v_end jsonb;
  v_doc text;
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
      -- 20261005k: pessoa nova com cadastro completo. Endereço "mantido" = foto do endereço de quem sai, lida aqui
      -- (o que a tela mandar em endereco é ignorado nesse caso).
      v_sn := p -> 'socio_entra_novo';
      v_txt := regexp_replace(coalesce(public.pa_txt(v_sn -> 'nome'), ''), '\s+', ' ', 'g');
      if length(v_txt) < 3 or length(v_txt) > 200 then
        return json_build_object('ok', false, 'msg', 'Informe o nome completo do sócio novo.');
      end if;
      v_mantido := lower(coalesce(v_sn ->> 'endereco_mantido', 'false')) = 'true';
      if v_mantido then
        v_end := public.pa_valor_campo(v_sai.id, 'endereco');
        if not exists (select 1 from jsonb_each_text(v_end) e
                        where e.key <> 'pais' and nullif(btrim(e.value), '') is not null) then
          return json_build_object('ok', false, 'msg',
            'O sócio que sai não tem endereço cadastrado: preencha o endereço do sócio novo.');
        end if;
      end if;
      begin
        if not v_mantido then
          v_end := public.pa_endereco(v_sn -> 'endereco', true);
        end if;
        v_doc := regexp_replace(coalesce(public.pa_txt(v_sn -> 'documento'), ''), '\D', '', 'g');
        if v_doc = '' then
          raise exception 'Informe o CPF ou CNPJ.' using errcode = '22023';
        end if;
        v_doc := public.pa_txt(public.pa_normalizar('documento', to_jsonb(v_doc)));
        v_entra_novo := jsonb_build_object(
          'nome', v_txt,
          'email', public.pa_txt(public.pa_normalizar('email', v_sn -> 'email')),
          'telefone', public.pa_telefone_pessoa(public.pa_txt(v_sn -> 'telefone'), public.pa_eh_brasil(v_end ->> 'pais')),
          'documento', v_doc,
          'tipo_documento', case length(v_doc) when 11 then 'CPF' else 'CNPJ' end,
          'profissao', public.pa_txt(public.pa_normalizar('profissao', coalesce(v_sn -> 'profissao', 'null'::jsonb))),
          'endereco_mantido', v_mantido,
          'endereco', v_end);
      exception when sqlstate '22023' then
        return json_build_object('ok', false, 'msg', 'Sócio novo: ' || sqlerrm);
      end;
      if exists (select 1 from public.thb_alunos o where lower(btrim(o.email)) = lower(v_entra_novo ->> 'email')) then
        return json_build_object('ok', false, 'msg', 'Esse e-mail já está na base: escolha a pessoa como sócio existente.');
      end if;
      if exists (select 1 from public.thb_alunos o where regexp_replace(coalesce(o.documento, ''), '\D', '', 'g') = v_doc) then
        return json_build_object('ok', false, 'msg', 'Esse CPF/CNPJ já está na base: escolha a pessoa como sócio existente.');
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

-- Decide um pedido. Aprovar aplica na hora (numa subtransação: erro não deixa meia alteração).
--   p_valor_ajustado: o aprovador corrige o valor antes de aplicar (alterar_dado).
--   p_confirmar_conflito: o valor mudou desde o pedido; sem esta confirmação, não aplica.
create or replace function public.pa_decidir(p_pedido bigint, p_decisao text, p_motivo_recusa text default null,
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
  v_sn jsonb;
  v_end jsonb;
  v_doc text;
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
        -- 20261005k: cadastro completo. Endereço = o do pedido (foto; "mantido" já é a cópia de quem saiu na hora do
        -- pedido). Pedido antigo sem endereço: colunas nulas e país 'Brasil' (default da coluna).
        v_sn := r.socio_entra_novo;
        v_end := case when jsonb_typeof(v_sn -> 'endereco') = 'object' then v_sn -> 'endereco' else '{}'::jsonb end;
        v_doc := nullif(regexp_replace(coalesce(v_sn ->> 'documento', ''), '\D', '', 'g'), '');
        if v_doc is not null and exists (select 1 from public.thb_alunos o
                                          where regexp_replace(coalesce(o.documento, ''), '\D', '', 'g') = v_doc) then
          raise exception 'O CPF/CNPJ do sócio novo já entrou na base depois do pedido: recuse e peça com o sócio existente.' using errcode = '22023';
        end if;
        insert into public.thb_alunos (nome, email, telefone, documento, tipo_documento, profissao,
                                       cep, endereco_logradouro, endereco_numero, endereco_complemento, bairro, cidade,
                                       estado, pais, fonte, atualizado_em, atualizado_por)
        values (v_sn ->> 'nome', v_sn ->> 'email', v_sn ->> 'telefone', v_doc,
                coalesce(v_sn ->> 'tipo_documento', case length(v_doc) when 11 then 'CPF' when 14 then 'CNPJ' end),
                public.pa_txt(v_sn -> 'profissao'),
                public.pa_txt(v_end -> 'cep'), public.pa_txt(v_end -> 'endereco_logradouro'),
                public.pa_txt(v_end -> 'endereco_numero'), public.pa_txt(v_end -> 'endereco_complemento'),
                public.pa_txt(v_end -> 'bairro'), public.pa_txt(v_end -> 'cidade'), public.pa_txt(v_end -> 'estado'),
                coalesce(public.pa_txt(v_end -> 'pais'), 'Brasil'),
                'pedido_alteracao', now(), v_por)
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
                                                 'instrucao', v_nivel || ' - SÓCIO', 'num_socios', v_num,
                                                 'socio_novo', r.socio_entra_id is null,
                                                 'endereco_mantido', coalesce((r.socio_entra_novo ->> 'endereco_mantido')::boolean, false)),
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

-- ─── 4. Quem executa o quê ──────────────────────────────────────────────────────────────────────────────────────────
-- Funções novas nascem com EXECUTE para PUBLIC: fecha todas e abre só a da tela. As substituídas mantêm o grant da j.
revoke all on function public.pa_ufs(), public.pa_doc_valido(text), public.pa_eh_brasil(text),
  public.pa_endereco(jsonb, boolean), public.pa_telefone_pessoa(text, boolean), public.pa_duplicata_pessoa(text, text)
  from public, anon, authenticated;
grant execute on function public.pa_duplicata_pessoa(text, text) to authenticated;

-- ─── 5. Conferência (aborta se algo nasceu aberto ou fora do padrão) ───────────────────────────────────────────────
do $confere$
declare
  f record;
  v_publicas text[] := array['pa_meu_papel', 'pa_buscar_alunos', 'pa_socios_do_titular', 'pa_valor_atual', 'pa_turmas', 'pa_criar',
                             'pa_meus_pedidos', 'pa_fila', 'pa_decidir', 'pa_marcar_aplicado', 'pa_duplicata_pessoa'];
begin
  for f in select p.oid::regprocedure as sig, p.proname, p.prosecdef, p.proconfig, p.proacl
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'pa\_%' loop
    if not (f.proconfig @> array['search_path=""']) then
      raise exception '20261005k: % sem search_path vazio', f.sig;
    end if;
    if has_function_privilege('anon', f.sig, 'execute') then
      raise exception '20261005k: anon executa %', f.sig;
    end if;
    if f.proacl is null or exists (select 1 from aclexplode(f.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE') then
      raise exception '20261005k: PUBLIC executa %', f.sig;
    end if;
    if (f.proname = any(v_publicas)) <> has_function_privilege('authenticated', f.sig, 'execute') then
      raise exception '20261005k: grant de authenticated errado em %', f.sig;
    end if;
    if f.proname = any(v_publicas) and not f.prosecdef then
      raise exception '20261005k: % deveria ser SECURITY DEFINER', f.sig;
    end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = any(v_publicas)) <> 11 then
    raise exception '20261005k: esperava 11 funções públicas pa_*';
  end if;
  -- Regras puras: dígito verificador e UF.
  if not public.pa_doc_valido('529.982.247-25') or public.pa_doc_valido('529.982.247-24') or public.pa_doc_valido('11111111111')
     or not public.pa_doc_valido('11.222.333/0001-81') or public.pa_doc_valido('11.222.333/0001-80') then
    raise exception '20261005k: pa_doc_valido com resultado errado';
  end if;
  if cardinality(public.pa_ufs()) <> 27 then
    raise exception '20261005k: pa_ufs sem 27 UFs';
  end if;
end
$confere$;


-- ═══ REVERSÃO (numa transação) ══════════════════════════════════════════════════════════════════════════════════════
-- Pedidos criados depois desta migration continuam legíveis (socio_entra_novo é jsonb); os campos a mais são ignorados
-- pela pa_decidir da j (o sócio novo entraria sem endereço). Por isso: aprovar ou recusar os pendentes antes de reverter.
-- begin;
-- -- 1) Recriar pa_normalizar, pa_criar e pa_decidir com o corpo da 20261005j_pedidos_alteracao.sql (seções 3, 7 e 9),
-- --    trocando "create function" por "create or replace function". O grant de authenticated continua.
-- -- 2) Apagar as funções novas:
-- drop function public.pa_duplicata_pessoa(text, text);
-- drop function public.pa_telefone_pessoa(text, boolean);
-- drop function public.pa_endereco(jsonb, boolean);
-- drop function public.pa_eh_brasil(text);
-- drop function public.pa_doc_valido(text);
-- drop function public.pa_ufs();
-- commit;
-- (os passos 1 e 2 na mesma transação: a pa_normalizar/pa_criar/pa_decidir desta migration dependem das funções novas.)
