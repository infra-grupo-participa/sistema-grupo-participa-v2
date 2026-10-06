-- 20261006160403: Pedidos de alteração (etapa 2), o n8n leva o pedido aplicado para a planilha da Central
--
-- STATUS: NÃO APLICADA. Ensaio: 20261006160403_ensaio.sql (begin … rollback). Notas: 20261006160403.explain.md.
-- Depende da 20261006160402 (pa_config, pa_n8n_valido). Independente da 160401 e da 160404.
--
-- O banco NÃO escreve na planilha. Ele entrega ao n8n, com segredo, o que escrever e onde achar a linha; o n8n escreve
-- (credencial Google do Victor) e devolve o resultado. Primeiro numa CÓPIA da planilha: pa_config.planilha_id nasce
-- NULO e, enquanto for nulo, a reserva não devolve nenhum pedido.
--
-- DECISÕES DO VICTOR (06/10/2026, noite) que esta migration traduz
--   • Casar a linha só por e-mail (as duas partes de "novo / antigo") ou documento; nunca por nome. 0 ou mais de 1
--     linha, ou célula diferente do esperado = erro, não escreve (regra aplicada pelo n8n com as chaves daqui).
--   • Alterar dado: nome→Nome (A), email→Email (C) no formato "novo / antigo", telefone→Telefone (D),
--     documento→Documento (B), endereço→CEP..Complemento (E..L), profissao→Profissão (M), turma→Turma (P, código),
--     instrucao→Instrução (O), obs_central→Obs (AM). telefone_profissional e espaco_instrucao não têm coluna: nada a
--     escrever, o n8n confirma ok com o detalhe.
--   • Troca de sócio: a linha de quem sai vai para "Removidos — Histórico" (J Motivo, K Transação de origem,
--     M Tinha acesso antigo?, N Quem determinou com os textos decididos). Se quem entra NÃO tem linha: a linha de
--     quem sai é sobrescrita (A..M do cadastro, O instrução, P/AI/W do titular, N/Q/R copiados da linha do titular,
--     S/T/U/Y/AE/BM/BN/BO com os padrões de sócio, AF nome do titular, demais colunas vazias). Se quem entra JÁ tem
--     linha: a linha de quem sai é APAGADA e na de quem entra só O, U, W, Y, AF. Titular: AG = sócios atuais
--     separados por "; " e AH = num_socios.
--   • Sem coluna nova de trilha na planilha.
--   Os nomes de aba e de cabeçalho abaixo são as strings EXATAS lidas da planilha 15ugo5… em 06/10/2026 (linha 1).
--
-- O QUE FAZ
--   1. pa_planilha_reservas (pedido_id, reservado_em): reserva de 10 minutos, fechada. Tabela própria em vez de
--      coluna nova em pa_pedidos: nada que a tela lê muda.
--   2. pa_planilha_reservar(p_segredo): até 5 pedidos `aplicado` com planilha_status = 'pendente' (alterar_dado e
--      trocar_socio), em ordem de nº, sem reserva viva; reserva e devolve, por pedido, as chaves e os valores por NOME
--      de cabeçalho (datas dd/mm/aaaa, turma pelo código, nulo vira ""). Sem segredo válido: {"ok": false} e nada mais.
--   3. pa_planilha_confirmar(p_segredo, p_pedido, p_ok, p_erro, p_detalhe): só para pedido reservado e pendente;
--      grava planilha_status ok/erro, planilha_em, planilha_erro e uma linha em pa_historico ('planilha_ok' ou
--      'planilha_erro', por = nulo, detalhe limitado a 8000 caracteres). Tira a reserva.
--   Funções com segredo: execute para anon e authenticated (o n8n chama pelo PostgREST), como ra_slack_*.
--
-- AS 5 PERGUNTAS
--   escala: dezenas de pedidos por mês; a reserva lê só os aplicados com planilha pendente (hoje 0) e no máximo 5.
--   índice: já existem pa_pedidos_planilha_idx (id) where planilha_status = 'pendente' e pa_pedidos_status_idx
--     (status, id); reservas pela pk. Nenhum índice novo (com a tabela pequena o planejador lê a tabela inteira, ver
--     o explain no .explain.md).
--   frequência: rodada de 15 min do n8n (desligado até o Victor ligar).
--   repetição: "for update skip locked" + reserva de 10 min + "on conflict … where reserva vencida": duas rodadas ao
--     mesmo tempo não pegam o mesmo pedido; confirmar exige reserva e planilha pendente (não confirma duas vezes).
--   reversão: bloco REVERSÃO no fim (drop das funções e da tabela nova). Nada existente é alterado.
--
-- Quem lê fora do v2: ninguém (objetos novos; pa_pedidos só é lido pelo v2).

set local lock_timeout = '5s';

-- ═══ 0. Guarda ═══
do $guarda$
begin
  if to_regclass('public.pa_config') is null or to_regprocedure('public.pa_n8n_valido(text)') is null then
    raise exception '20261006160403: aplicar antes a 20261006160402 (pa_config, pa_n8n_valido)';
  end if;
  if to_regclass('public.pa_planilha_reservas') is not null then
    raise exception '20261006160403: pa_planilha_reservas já existe (migration já aplicada?)';
  end if;
  if to_regprocedure('public.pa_contar_socios(uuid)') is null or to_regprocedure('public.pa_chave_nome(text)') is null
     or to_regprocedure('public.pa_txt(jsonb)') is null then
    raise exception '20261006160403: pa_contar_socios, pa_chave_nome ou pa_txt ausente';
  end if;
end
$guarda$;

-- ═══ 1. Reserva (fechada) ═══
create table public.pa_planilha_reservas (
  pedido_id    bigint primary key references public.pa_pedidos(id) on delete cascade,
  reservado_em timestamptz not null default now()
);
alter table public.pa_planilha_reservas enable row level security;
revoke all on table public.pa_planilha_reservas from public, anon, authenticated;

-- ═══ 2. Auxiliares internas ═══
-- Texto para a célula: nulo vira "" (escrever "" limpa a célula).
create function public.pa_planilha_cel(p text)
returns text language sql immutable set search_path = '' as $$
  select coalesce(btrim(p), '');
$$;

-- Chaves para achar a linha: e-mails (minúsculo, sem espaço) e documentos (só dígitos, 11 ou mais) do aluno no banco
-- mais os extras (valor antigo de uma alteração). Aluno apagado (nulo): listas vazias, o n8n acha 0 linhas = erro.
create function public.pa_planilha_chaves(p_aluno uuid, p_emails text[] default '{}', p_docs text[] default '{}')
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'emails', coalesce((select jsonb_agg(distinct e order by e) from (
                 select lower(btrim(x)) e from unnest(array[(select a.email from public.thb_alunos a where a.id = p_aluno)]
                                                      || coalesce(p_emails, '{}')) x) s
                where e is not null and e <> ''), '[]'::jsonb),
    'documentos', coalesce((select jsonb_agg(distinct d order by d) from (
                 select regexp_replace(coalesce(x, ''), '\D', '', 'g') d
                   from unnest(array[(select a.documento from public.thb_alunos a where a.id = p_aluno)]
                               || coalesce(p_docs, '{}')) x) s
                where length(d) >= 11), '[]'::jsonb));
$$;

-- Os cabeçalhos usados, com a coluna em que estavam em 06/10/2026: o n8n confere a linha 1 antes de escrever.
create function public.pa_planilha_cabecalhos()
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'Central de Acessos 2026', jsonb_build_object(
      'Nome', 'A', 'Documento', 'B', 'Email', 'C', 'Telefone', 'D', 'CEP', 'E', 'Cidade', 'F', 'Estado', 'G',
      'Bairro', 'H', 'País', 'I', 'Endereço', 'J', 'Número', 'K', 'Complemento', 'L', 'Profissão', 'M',
      'Produto', 'N', 'Instrução', 'O', 'Turma', 'P', 'Turma Aurum', 'Q', 'Nível', 'R', 'Oferta', 'S',
      'Tipo de oferta', 'T', 'Regra de acesso', 'U', 'Data de expiração', 'W', 'Status do acesso', 'Y',
      'Origem do acesso', 'AE', 'Sócio de (titular)', 'AF', 'Sócio', 'AG', 'Nº de sócios', 'AH',
      'Data de entrada no THB', 'AI', 'Obs', 'AM', 'Canal de aquisição', 'BM', 'Tipo de entrada', 'BN',
      'Origem do canal (como foi atribuído)', 'BO'),
    'Removidos — Histórico', jsonb_build_object(
      'Data da saída', 'A', 'Nome', 'B', 'Documento', 'C', 'E-mail', 'D', 'Telefone', 'E', 'Linha na Central', 'F',
      'Instrução que tinha', 'G', 'Turma que tinha', 'H', 'Expiração que tinha', 'I', 'Motivo', 'J',
      'Transação de origem', 'K', 'Valor', 'L', 'Tinha acesso antigo?', 'M', 'Quem determinou', 'N'));
$$;

-- O que o n8n faz com UM pedido. Interna (chamada só por pa_planilha_reservar).
create function public.pa_planilha_pedido(p_id bigint)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r public.pa_pedidos%rowtype;
  t public.thb_alunos%rowtype;
  e public.thb_alunos%rowtype;
  v_entra uuid;
  v_aprov text;
  v_dia text;
  v_turma text;
  v_ant jsonb;
  v_nov jsonb;
  v_esc jsonb := '{}'::jsonb;
  v_antes jsonb := '{}'::jsonb;
  v_socios text;
  v_copiar text[];
  v_end_cols constant jsonb := jsonb_build_object(
    'cep', 'CEP', 'cidade', 'Cidade', 'estado', 'Estado', 'bairro', 'Bairro', 'pais', 'País',
    'endereco_logradouro', 'Endereço', 'endereco_numero', 'Número', 'endereco_complemento', 'Complemento');
  v_cab text;
  v_k text;
begin
  select * into r from public.pa_pedidos where id = p_id;
  v_aprov := coalesce((select p.nome from public.perfis p where p.id = r.decidido_por), '(aprovador não encontrado)');
  v_dia := to_char(r.decidido_em at time zone 'America/Sao_Paulo', 'DD/MM/YYYY');

  if r.tipo = 'alterar_dado' then
    v_ant := r.valor_atual;
    v_nov := coalesce(r.valor_aplicado, r.valor_novo);
    if r.campo in ('telefone_profissional', 'espaco_instrucao') then
      return jsonb_build_object('pedido', r.id, 'tipo', r.tipo, 'campo', r.campo,
        'aluno', jsonb_build_object('nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
                                    'chaves', public.pa_planilha_chaves(r.aluno_id)),
        'escrever', '{}'::jsonb, 'esperado_antes', '{}'::jsonb, 'sem_coluna', true,
        'detalhe', case r.campo when 'telefone_profissional' then 'Telefone profissional' else 'Espaço de instrução' end
                   || ' não tem coluna na Central: nada a escrever.');
    end if;
    if r.campo = 'endereco' then
      for v_k, v_cab in select key, value from jsonb_each_text(v_end_cols) loop
        v_esc := v_esc || jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_nov -> v_k)));
        v_antes := v_antes || jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_ant -> v_k)));
      end loop;
    elsif r.campo = 'turma_id' then
      v_esc := jsonb_build_object('Turma', public.pa_planilha_cel(
                 (select tu.codigo from public.thb_turmas tu where tu.id = (public.pa_txt(v_nov))::int)));
      v_antes := jsonb_build_object('Turma', public.pa_planilha_cel(
                 (select tu.codigo from public.thb_turmas tu where tu.id = (public.pa_txt(v_ant))::int)));
    elsif r.campo = 'email' then
      v_esc := jsonb_build_object('Email', public.pa_txt(v_nov) || coalesce(' / ' || public.pa_txt(v_ant), ''));
      v_antes := jsonb_build_object('Email', public.pa_planilha_cel(public.pa_txt(v_ant)));
    else
      v_cab := case r.campo when 'nome' then 'Nome' when 'telefone' then 'Telefone' when 'documento' then 'Documento'
                            when 'profissao' then 'Profissão' when 'instrucao' then 'Instrução' when 'obs_central' then 'Obs' end;
      if v_cab is null then
        -- Campo novo sem mapeamento: não derruba a rodada; o n8n confirma como erro com esta mensagem.
        return jsonb_build_object('pedido', r.id, 'tipo', r.tipo, 'campo', r.campo,
          'erro', 'Campo ' || coalesce(r.campo, '(nulo)') || ' sem coluna mapeada no banco: confirmar como erro.');
      end if;
      v_esc := jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_nov)));
      v_antes := jsonb_build_object(v_cab, public.pa_planilha_cel(public.pa_txt(v_ant)));
    end if;
    return jsonb_build_object('pedido', r.id, 'tipo', r.tipo, 'campo', r.campo,
      'aluno', jsonb_build_object(
         'nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.aluno_id), r.aluno_nome),
         'chaves', public.pa_planilha_chaves(r.aluno_id,
                     case when r.campo = 'email' then array[public.pa_txt(v_ant), public.pa_txt(v_nov)] else '{}'::text[] end,
                     case when r.campo = 'documento' then array[public.pa_txt(v_ant), public.pa_txt(v_nov)] else '{}'::text[] end)),
      'escrever', v_esc, 'esperado_antes', v_antes, 'sem_coluna', false, 'detalhe', null);
  end if;

  -- trocar_socio
  select * into t from public.thb_alunos where id = r.aluno_id;
  v_entra := coalesce(r.socio_entra_id, (r.valor_aplicado ->> 'socio_entra_id')::uuid);
  select * into e from public.thb_alunos where id = v_entra;
  v_turma := (select tu.codigo from public.thb_turmas tu where tu.id = t.turma_id);
  -- Sócios atuais do titular, pela mesma regra de pa_contar_socios.
  select string_agg(s.nome, '; ' order by s.nome) into v_socios
    from public.thb_alunos s
   where t.id is not null and s.id <> t.id and s.cancelado_em is null
     and (s.socio_de_aluno_id = t.id
          or (s.socio_de_aluno_id is null and coalesce(s.eh_socio, false)
              and public.pa_chave_nome(s.socio_de_nome) = public.pa_chave_nome(t.nome)));
  -- O que não está no banco do titular sai da linha dele na planilha.
  v_copiar := array['Produto', 'Turma Aurum', 'Nível']
              || case when v_turma is null then array['Turma'] else '{}'::text[] end
              || case when t.data_entrada_thb is null then array['Data de entrada no THB'] else '{}'::text[] end
              || case when t.data_expiracao is null then array['Data de expiração'] else '{}'::text[] end;

  return jsonb_build_object('pedido', r.id, 'tipo', r.tipo,
    'titular', jsonb_build_object(
       'nome', coalesce(t.nome, r.aluno_nome),
       'chaves', public.pa_planilha_chaves(r.aluno_id),
       'escrever', jsonb_build_object('Sócio', coalesce(v_socios, ''), 'Nº de sócios', coalesce(t.num_socios::text, ''))),
    'sai', jsonb_build_object(
       'nome', coalesce((select a.nome from public.thb_alunos a where a.id = r.socio_sai_id), r.socio_sai_nome),
       'chaves', public.pa_planilha_chaves(r.socio_sai_id)),
    'entra', jsonb_build_object(
       'nome', coalesce(e.nome, r.socio_entra_nome, r.socio_entra_novo ->> 'nome'),
       'chaves', public.pa_planilha_chaves(v_entra),
       'socio_novo', coalesce((r.valor_aplicado ->> 'socio_novo')::boolean, r.socio_entra_id is null)),
    -- Linha nova em "Removidos — Histórico": estes valores fixos + os copiados da linha de quem sai + "Linha na Central"
    -- (número da linha de quem sai, achado pelo n8n).
    'removidos', jsonb_build_object(
       'Data da saída', coalesce(v_dia, ''),
       'Motivo', 'Troca de sócio: saiu como sócio de ' || coalesce(t.nome, r.aluno_nome) || ' (pedido nº ' || r.id || ')',
       'Transação de origem', 'PEDIDO-ALTERACAO-' || r.id,
       'Valor', '',
       'Tinha acesso antigo?', 'ver caso de Remoção de Acessos',
       'Quem determinou', 'Pedido nº ' || r.id || ', aprovado por ' || v_aprov || ', ' || coalesce(v_dia, '')),
    'copiar_para_removidos', jsonb_build_object(
       'Nome', 'Nome', 'Documento', 'Documento', 'E-mail', 'Email', 'Telefone', 'Telefone',
       'Instrução que tinha', 'Instrução', 'Turma que tinha', 'Turma', 'Expiração que tinha', 'Data de expiração'),
    -- Quem entra NÃO tem linha: sobrescreve a linha de quem sai (depois de copiá-la para Removidos).
    'se_entra_sem_linha', jsonb_build_object(
       'acao', 'sobrescrever a linha de quem sai',
       'escrever', jsonb_strip_nulls(jsonb_build_object(
          'Nome', public.pa_planilha_cel(e.nome), 'Documento', public.pa_planilha_cel(e.documento),
          'Email', public.pa_planilha_cel(e.email), 'Telefone', public.pa_planilha_cel(e.telefone),
          'CEP', public.pa_planilha_cel(e.cep), 'Cidade', public.pa_planilha_cel(e.cidade),
          'Estado', public.pa_planilha_cel(e.estado), 'Bairro', public.pa_planilha_cel(e.bairro),
          'País', public.pa_planilha_cel(e.pais), 'Endereço', public.pa_planilha_cel(e.endereco_logradouro),
          'Número', public.pa_planilha_cel(e.endereco_numero), 'Complemento', public.pa_planilha_cel(e.endereco_complemento),
          'Profissão', public.pa_planilha_cel(e.profissao),
          'Instrução', public.pa_planilha_cel(coalesce(r.valor_aplicado ->> 'instrucao', e.instrucao)),
          'Turma', v_turma,
          'Data de entrada no THB', to_char(t.data_entrada_thb, 'DD/MM/YYYY'),
          'Data de expiração', to_char(t.data_expiracao, 'DD/MM/YYYY'),
          'Oferta', '(convite/cadastro manual)', 'Tipo de oferta', 'Sócio', 'Regra de acesso', 'Acompanha titular',
          'Status do acesso', 'Acompanha titular', 'Origem do acesso', 'Sócio/Convite',
          'Canal de aquisição', 'Sócio', 'Tipo de entrada', 'Sócio',
          'Origem do canal (como foi atribuído)', 'É sócio — acompanha o titular',
          'Sócio de (titular)', public.pa_planilha_cel(t.nome))),
       'copiar_do_titular', to_jsonb(v_copiar),
       'limpar_demais', true),
    -- Quem entra JÁ tem linha: apaga a linha de quem sai (depois de copiá-la) e escreve só estas 5 na de quem entra.
    'se_entra_com_linha', jsonb_build_object(
       'acao', 'apagar a linha de quem sai',
       'escrever', jsonb_strip_nulls(jsonb_build_object(
          'Instrução', public.pa_planilha_cel(coalesce(r.valor_aplicado ->> 'instrucao', e.instrucao)),
          'Regra de acesso', 'Acompanha titular',
          'Data de expiração', to_char(t.data_expiracao, 'DD/MM/YYYY'),
          'Status do acesso', 'Acompanha titular',
          'Sócio de (titular)', public.pa_planilha_cel(t.nome))),
       'copiar_do_titular', case when t.data_expiracao is null then '["Data de expiração"]'::jsonb else '[]'::jsonb end));
end
$$;

-- ═══ 3. Reserva para o n8n ═══
create function public.pa_planilha_reservar(p_segredo text)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_planilha text;
  v_ids bigint[];
begin
  if not public.pa_n8n_valido(p_segredo) then return json_build_object('ok', false); end if;
  select c.planilha_id into v_planilha from public.pa_config c;
  if v_planilha is null then return json_build_object('ok', true, 'planilha_id', null, 'pedidos', '[]'::json); end if;

  with alvo as (
    select x.id from public.pa_pedidos x
     where x.status = 'aplicado' and x.planilha_status = 'pendente' and x.tipo in ('alterar_dado', 'trocar_socio')
       and not exists (select 1 from public.pa_planilha_reservas pr
                        where pr.pedido_id = x.id and pr.reservado_em >= now() - interval '10 minutes')
     order by x.id
     limit 5
     for update of x skip locked
  ), res as (
    insert into public.pa_planilha_reservas as pr (pedido_id, reservado_em)
    select id, now() from alvo
    on conflict (pedido_id) do update set reservado_em = excluded.reservado_em
      where pr.reservado_em < now() - interval '10 minutes'
    returning pr.pedido_id
  )
  select array_agg(pedido_id order by pedido_id) into v_ids from res;

  return json_build_object('ok', true, 'planilha_id', v_planilha,
    'abas', json_build_object('central', 'Central de Acessos 2026', 'removidos', 'Removidos — Histórico'),
    'cabecalhos', public.pa_planilha_cabecalhos(),
    'reserva_minutos', 10,
    'pedidos', coalesce((select json_agg(public.pa_planilha_pedido(i) order by i) from unnest(v_ids) i), '[]'::json));
end
$$;

-- ═══ 4. Resultado do n8n ═══
create function public.pa_planilha_confirmar(p_segredo text, p_pedido bigint, p_ok boolean, p_erro text default null,
                                             p_detalhe jsonb default null)
returns json language plpgsql volatile security definer set search_path = '' as $$
declare
  v_det jsonb := coalesce(p_detalhe, '{}'::jsonb);
  v_erro text;
begin
  if not public.pa_n8n_valido(p_segredo) then return json_build_object('ok', false); end if;
  if p_ok is null then return json_build_object('ok', false, 'msg', 'p_ok é obrigatório.'); end if;
  if length(v_det::text) > 8000 then
    v_det := jsonb_build_object('truncado', true, 'inicio', left(v_det::text, 8000));
  end if;
  v_erro := case when p_ok then null else left(coalesce(nullif(btrim(p_erro), ''), 'erro sem mensagem do n8n'), 500) end;

  update public.pa_pedidos x
     set planilha_status = case when p_ok then 'ok' else 'erro' end, planilha_em = now(), planilha_erro = v_erro
   where x.id = p_pedido and x.status = 'aplicado' and x.planilha_status = 'pendente'
     and exists (select 1 from public.pa_planilha_reservas pr where pr.pedido_id = x.id);
  if not found then
    return json_build_object('ok', false, 'msg', 'Pedido sem reserva ou com a planilha já resolvida.');
  end if;
  delete from public.pa_planilha_reservas where pedido_id = p_pedido;
  insert into public.pa_historico (pedido_id, acao, por, detalhe)
  values (p_pedido, case when p_ok then 'planilha_ok' else 'planilha_erro' end, null,
          v_det || case when p_ok then '{}'::jsonb else jsonb_build_object('erro', v_erro) end);
  return json_build_object('ok', true);
end
$$;

-- ═══ 5. Permissões ═══
revoke all on function public.pa_planilha_cel(text) from public, anon, authenticated;
revoke all on function public.pa_planilha_chaves(uuid, text[], text[]) from public, anon, authenticated;
revoke all on function public.pa_planilha_cabecalhos() from public, anon, authenticated;
revoke all on function public.pa_planilha_pedido(bigint) from public, anon, authenticated;
revoke all on function public.pa_planilha_reservar(text) from public;
revoke all on function public.pa_planilha_confirmar(text, bigint, boolean, text, jsonb) from public;
grant execute on function public.pa_planilha_reservar(text) to anon, authenticated;
grant execute on function public.pa_planilha_confirmar(text, bigint, boolean, text, jsonb) to anon, authenticated;

-- ═══ 6. Conferência ═══
do $confere$
begin
  if has_table_privilege('anon', 'public.pa_planilha_reservas', 'select')
     or has_table_privilege('authenticated', 'public.pa_planilha_reservas', 'select') then
    raise exception '20261006160403: pa_planilha_reservas legível por anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.pa_planilha_pedido(bigint)', 'execute')
     or has_function_privilege('authenticated', 'public.pa_planilha_pedido(bigint)', 'execute')
     or has_function_privilege('anon', 'public.pa_planilha_chaves(uuid,text[],text[])', 'execute') then
    raise exception '20261006160403: função interna exposta';
  end if;
  if not has_function_privilege('anon', 'public.pa_planilha_reservar(text)', 'execute') then
    raise exception '20261006160403: pa_planilha_reservar sem execute para anon';
  end if;
end
$confere$;

-- ═══ REVERSÃO (não rodar junto com a migration) ═══
-- Tira as funções e a tabela de reservas. Nada existente foi alterado; pedidos já marcados ok/erro e as linhas
-- 'planilha_ok'/'planilha_erro' de pa_historico ficam (são registro do que aconteceu). Desligar antes o workflow do n8n.
-- Para reverter: tirar o "-- " das linhas abaixo e rodar.
--
-- drop function if exists public.pa_planilha_confirmar(text, bigint, boolean, text, jsonb);
-- drop function if exists public.pa_planilha_reservar(text);
-- drop function if exists public.pa_planilha_pedido(bigint);
-- drop function if exists public.pa_planilha_cabecalhos();
-- drop function if exists public.pa_planilha_chaves(uuid, text[], text[]);
-- drop function if exists public.pa_planilha_cel(text);
-- drop table if exists public.pa_planilha_reservas;
