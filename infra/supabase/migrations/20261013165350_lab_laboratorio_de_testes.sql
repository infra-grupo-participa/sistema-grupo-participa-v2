-- Laboratório de decisões e testes (Infra › Laboratório). Pedido do Arthur, 13/10/2026.
-- Especificação: docs/projetos/laboratorio/playbook-de-decisoes-e-testes.md (dono: Renan Schwarz).
-- Schema `lab` fechado (fora da API). A tela fala só com as RPCs public.lab_* (SECURITY DEFINER, guard próprio).
-- Acesso: toda a equipe (gp_eh_equipe) vê e cria; edita quem criou, os responsáveis e admin/dev (gp_is_admin).
-- Travas do playbook (6.1, regra 6): depois de sair do rascunho, régua, métrica de decisão, tipo de métrica,
-- variável e forma de sortear só mudam com motivo; a mudança reinicia o relógio (início = hoje) e fica registrada.

create schema if not exists lab;
revoke all on schema lab from public, anon, authenticated;

create table lab.experimento (
  id uuid primary key default gen_random_uuid(),
  area text not null check (area in ('trafego','comercial','atendimento','conteudo','crm','rh','operacoes','financeiro','produto','outro')),
  nivel smallint not null check (nivel between 1 and 3),
  titulo text not null check (length(btrim(titulo)) between 3 and 140),
  status text not null default 'rascunho' check (status in ('rascunho','no_ar','em_leitura','concluido','cancelado')),
  -- ficha (seções 4, 5 e 6.2)
  decisao text,               -- nível 1: o que vamos fazer
  hipotese text,              -- com número
  previsao text,              -- nível 1: o que esperamos ver, e até quando
  variavel text,              -- a única coisa que muda
  nao_muda text,              -- lista do que não muda
  sorteio text,               -- como cada caso cai em A ou B
  metrica_tipo text check (metrica_tipo in ('taxa','custo')),
  metrica_decisao text,
  metricas_diagnostico text,
  taxa_base numeric check (taxa_base is null or (taxa_base > 0 and taxa_base < 1)),
  regua numeric check (regua is null or (regua > 0 and regua <= 5)),   -- menor diferença que importa, fração (0,30 = 30%)
  perguntas_regua jsonb not null default '{}'::jsonb,                  -- as 4 perguntas da 6A
  amostra_minima integer check (amostra_minima is null or amostra_minima > 0),
  grupo_piloto text,
  grupo_comparacao text,
  medicao_antes text,
  confundidores text,
  alarme text,
  decisao_combinada jsonb not null default '{}'::jsonb,                -- vencedor / provavel / empate / inconclusivo
  controle_a text,            -- pergunta de controle (seção 10): se der A, fazemos o quê?
  controle_b text,            -- e se der B?
  inicio date,
  leitura_em date,
  revisao_em date,            -- nível 1
  clickup text,
  monta_id uuid references public.perfis(id),
  confere_id uuid references public.perfis(id),
  le_id uuid references public.perfis(id),
  -- fechamento
  revisao_bateu text check (revisao_bateu in ('sim','nao','nao_sabe')),
  resultado text check (resultado in ('vencedor','provavel','empate','inconclusivo')),
  confianca numeric check (confianca is null or (confianca >= 0 and confianca <= 1)),
  o_que_fizemos text,
  aprendizado text,
  concluido_em timestamptz,
  mudancas jsonb not null default '[]'::jsonb,
  criado_por uuid references public.perfis(id),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index experimento_status_idx on lab.experimento (status, leitura_em);
create index experimento_area_idx on lab.experimento (area, criado_em desc);

create table lab.leitura (
  id uuid primary key default gen_random_uuid(),
  experimento_id uuid not null references lab.experimento(id) on delete cascade,
  em date not null default (now() at time zone 'America/Sao_Paulo')::date,
  a_n numeric check (a_n is null or a_n >= 0),   -- taxa: casos do controle (A); custo: gasto do controle
  a_x numeric check (a_x is null or a_x >= 0),   -- taxa: sucessos de A; custo: resultados de A
  b_n numeric check (b_n is null or b_n >= 0),
  b_x numeric check (b_x is null or b_x >= 0),
  medicao_ok boolean not null default true,
  nota text,
  calculo jsonb not null default '{}'::jsonb,    -- resultado calculado na tela (domain/estatistica.ts), guardado como foi lido
  classificacao text check (classificacao in ('vencedor','provavel','empate','inconclusivo')),
  lido_por uuid references public.perfis(id),
  criado_em timestamptz not null default now()
);
create index leitura_experimento_idx on lab.leitura (experimento_id, em desc);

alter table lab.experimento enable row level security;
alter table lab.leitura enable row level security;
revoke all on lab.experimento, lab.leitura from public, anon, authenticated;

-- ── helpers ──
create or replace function lab.pode_editar(e lab.experimento) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_is_admin(), false)
      or auth.uid() in (e.criado_por, e.monta_id, e.confere_id, e.le_id)
$$;
revoke all on function lab.pode_editar(lab.experimento) from public, anon, authenticated;

create or replace function lab.res(p_ok boolean, p_msg text, p_extra jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = '' as $$ select jsonb_build_object('ok', p_ok, 'msg', p_msg) || coalesce(p_extra, '{}'::jsonb) $$;
revoke all on function lab.res(boolean, text, jsonb) from public, anon, authenticated;

create or replace function lab.json(e lab.experimento) returns jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(e) || jsonb_build_object(
    'criado_por_nome', (select p.nome from public.perfis p where p.id = e.criado_por),
    'monta_nome', (select p.nome from public.perfis p where p.id = e.monta_id),
    'confere_nome', (select p.nome from public.perfis p where p.id = e.confere_id),
    'le_nome', (select p.nome from public.perfis p where p.id = e.le_id),
    'pode_editar', lab.pode_editar(e),
    'leituras', coalesce((select jsonb_agg(to_jsonb(l) || jsonb_build_object('lido_por_nome', (select p.nome from public.perfis p where p.id = l.lido_por))
                                          order by l.em desc, l.criado_em desc)
                            from lab.leitura l where l.experimento_id = e.id), '[]'::jsonb))
$$;
revoke all on function lab.json(lab.experimento) from public, anon, authenticated;

-- Ficha mínima para ir ao ar, por nível (seções 4, 5 e 6.2).
create or replace function lab.faltando(e lab.experimento) returns text[]
language sql immutable set search_path = '' as $$
  select array_remove(array[
    case when nullif(btrim(coalesce(e.hipotese, '')), '') is null then 'hipótese' end,
    case when e.nivel = 1 and nullif(btrim(coalesce(e.decisao, '')), '') is null then 'decisão' end,
    case when e.nivel = 1 and nullif(btrim(coalesce(e.previsao, '')), '') is null then 'previsão com número' end,
    case when e.nivel = 1 and e.revisao_em is null then 'data de revisão' end,
    case when e.nivel = 2 and nullif(btrim(coalesce(e.grupo_piloto, '')), '') is null then 'grupo piloto' end,
    case when e.nivel = 2 and nullif(btrim(coalesce(e.grupo_comparacao, '')), '') is null then 'grupo de comparação' end,
    case when e.nivel = 2 and nullif(btrim(coalesce(e.confundidores, '')), '') is null then 'confundidores' end,
    case when e.nivel >= 2 and nullif(btrim(coalesce(e.metrica_decisao, '')), '') is null then 'métrica de decisão' end,
    case when e.nivel >= 2 and e.leitura_em is null then 'data de leitura' end,
    case when e.nivel = 3 and nullif(btrim(coalesce(e.variavel, '')), '') is null then 'variável única' end,
    case when e.nivel = 3 and nullif(btrim(coalesce(e.sorteio, '')), '') is null then 'como sortear' end,
    case when e.nivel = 3 and e.metrica_tipo is null then 'tipo de métrica' end,
    case when e.nivel = 3 and e.regua is null then 'menor diferença que importa' end,
    case when e.nivel = 3 and e.amostra_minima is null then 'amostra mínima' end,
    case when e.nivel = 3 and e.inicio is null then 'início' end
  ], null)
$$;
revoke all on function lab.faltando(lab.experimento) from public, anon, authenticated;

-- ── RPCs ──
create or replace function public.lab_listar() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.gp_eh_equipe(), false) then raise exception 'Sem acesso ao Laboratório.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(lab.json(e) - 'leituras' || jsonb_build_object('n_leituras', (select count(*) from lab.leitura l where l.experimento_id = e.id))
                                    order by e.criado_em desc) from lab.experimento e), '[]'::jsonb);
end $$;

create or replace function public.lab_obter(p_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare e lab.experimento;
begin
  if not coalesce(public.gp_eh_equipe(), false) then raise exception 'Sem acesso ao Laboratório.' using errcode = '42501'; end if;
  select * into e from lab.experimento x where x.id = p_id;
  if not found then return null; end if;
  return lab.json(e);
end $$;

create or replace function public.lab_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e lab.experimento; v_id uuid; v_novo boolean; v_mudou text[] := '{}'; v_motivo text;
begin
  if not coalesce(public.gp_eh_equipe(), false) then return lab.res(false, 'Sem acesso ao Laboratório.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return lab.res(false, 'Dados inválidos.'); end if;
  v_id := nullif(p ->> 'id', '')::uuid;
  v_novo := v_id is null;
  if not v_novo then
    select * into e from lab.experimento x where x.id = v_id for update;
    if not found then return lab.res(false, 'Experimento não encontrado.'); end if;
    if not lab.pode_editar(e) then return lab.res(false, 'Só quem criou, os responsáveis ou um admin editam.'); end if;
    if e.status in ('concluido', 'cancelado') then return lab.res(false, 'Experimento encerrado não muda. Abra um novo.'); end if;
    if e.nivel::text is distinct from coalesce(p ->> 'nivel', e.nivel::text) and e.status <> 'rascunho' then
      return lab.res(false, 'O nível não muda depois que o teste foi ao ar.');
    end if;
    -- regra 6 da seção 6.1: o que define o teste não muda no meio sem motivo; mudar reinicia o relógio
    if e.status <> 'rascunho' then
      if p ? 'regua' and (p ->> 'regua')::numeric is distinct from e.regua then v_mudou := v_mudou || 'régua'; end if;
      if p ? 'metrica_decisao' and nullif(p ->> 'metrica_decisao', '') is distinct from e.metrica_decisao then v_mudou := v_mudou || 'métrica de decisão'; end if;
      if p ? 'metrica_tipo' and nullif(p ->> 'metrica_tipo', '') is distinct from e.metrica_tipo then v_mudou := v_mudou || 'tipo de métrica'; end if;
      if p ? 'variavel' and nullif(p ->> 'variavel', '') is distinct from e.variavel then v_mudou := v_mudou || 'variável'; end if;
      if p ? 'sorteio' and nullif(p ->> 'sorteio', '') is distinct from e.sorteio then v_mudou := v_mudou || 'sorteio'; end if;
      if cardinality(v_mudou) > 0 then
        v_motivo := nullif(btrim(coalesce(p ->> 'motivo_mudanca', '')), '');
        if v_motivo is null or length(v_motivo) < 10 then
          return lab.res(false, 'Mudar ' || array_to_string(v_mudou, ', ') || ' com o teste no ar reinicia o relógio. Escreva o motivo (pelo menos 10 letras).',
                         jsonb_build_object('exige_motivo', true, 'mudou', to_jsonb(v_mudou)));
        end if;
      end if;
    end if;
  end if;

  if v_novo then
    insert into lab.experimento (area, nivel, titulo, criado_por)
    values (coalesce(p ->> 'area', 'outro'), coalesce((p ->> 'nivel')::smallint, 1), coalesce(nullif(btrim(p ->> 'titulo'), ''), 'Sem título'), auth.uid())
    returning * into e;
  end if;

  update lab.experimento x set
    area = coalesce(p ->> 'area', x.area),
    nivel = case when x.status = 'rascunho' then coalesce((p ->> 'nivel')::smallint, x.nivel) else x.nivel end,
    titulo = coalesce(nullif(btrim(p ->> 'titulo'), ''), x.titulo),
    decisao = case when p ? 'decisao' then nullif(btrim(p ->> 'decisao'), '') else x.decisao end,
    hipotese = case when p ? 'hipotese' then nullif(btrim(p ->> 'hipotese'), '') else x.hipotese end,
    previsao = case when p ? 'previsao' then nullif(btrim(p ->> 'previsao'), '') else x.previsao end,
    variavel = case when p ? 'variavel' then nullif(btrim(p ->> 'variavel'), '') else x.variavel end,
    nao_muda = case when p ? 'nao_muda' then nullif(btrim(p ->> 'nao_muda'), '') else x.nao_muda end,
    sorteio = case when p ? 'sorteio' then nullif(btrim(p ->> 'sorteio'), '') else x.sorteio end,
    metrica_tipo = case when p ? 'metrica_tipo' then nullif(p ->> 'metrica_tipo', '') else x.metrica_tipo end,
    metrica_decisao = case when p ? 'metrica_decisao' then nullif(btrim(p ->> 'metrica_decisao'), '') else x.metrica_decisao end,
    metricas_diagnostico = case when p ? 'metricas_diagnostico' then nullif(btrim(p ->> 'metricas_diagnostico'), '') else x.metricas_diagnostico end,
    taxa_base = case when p ? 'taxa_base' then nullif(p ->> 'taxa_base', '')::numeric else x.taxa_base end,
    regua = case when p ? 'regua' then nullif(p ->> 'regua', '')::numeric else x.regua end,
    perguntas_regua = case when p ? 'perguntas_regua' then coalesce(p -> 'perguntas_regua', '{}'::jsonb) else x.perguntas_regua end,
    amostra_minima = case when p ? 'amostra_minima' then nullif(p ->> 'amostra_minima', '')::integer else x.amostra_minima end,
    grupo_piloto = case when p ? 'grupo_piloto' then nullif(btrim(p ->> 'grupo_piloto'), '') else x.grupo_piloto end,
    grupo_comparacao = case when p ? 'grupo_comparacao' then nullif(btrim(p ->> 'grupo_comparacao'), '') else x.grupo_comparacao end,
    medicao_antes = case when p ? 'medicao_antes' then nullif(btrim(p ->> 'medicao_antes'), '') else x.medicao_antes end,
    confundidores = case when p ? 'confundidores' then nullif(btrim(p ->> 'confundidores'), '') else x.confundidores end,
    alarme = case when p ? 'alarme' then nullif(btrim(p ->> 'alarme'), '') else x.alarme end,
    decisao_combinada = case when p ? 'decisao_combinada' then coalesce(p -> 'decisao_combinada', '{}'::jsonb) else x.decisao_combinada end,
    controle_a = case when p ? 'controle_a' then nullif(btrim(p ->> 'controle_a'), '') else x.controle_a end,
    controle_b = case when p ? 'controle_b' then nullif(btrim(p ->> 'controle_b'), '') else x.controle_b end,
    inicio = case when cardinality(v_mudou) > 0 then (now() at time zone 'America/Sao_Paulo')::date
                  when p ? 'inicio' then nullif(p ->> 'inicio', '')::date else x.inicio end,
    leitura_em = case when p ? 'leitura_em' then nullif(p ->> 'leitura_em', '')::date else x.leitura_em end,
    revisao_em = case when p ? 'revisao_em' then nullif(p ->> 'revisao_em', '')::date else x.revisao_em end,
    clickup = case when p ? 'clickup' then nullif(btrim(p ->> 'clickup'), '') else x.clickup end,
    monta_id = case when p ? 'monta_id' then nullif(p ->> 'monta_id', '')::uuid else x.monta_id end,
    confere_id = case when p ? 'confere_id' then nullif(p ->> 'confere_id', '')::uuid else x.confere_id end,
    le_id = case when p ? 'le_id' then nullif(p ->> 'le_id', '')::uuid else x.le_id end,
    mudancas = case when cardinality(v_mudou) > 0
                    then x.mudancas || jsonb_build_array(jsonb_build_object('em', now(), 'por', auth.uid(), 'campos', to_jsonb(v_mudou), 'motivo', v_motivo))
                    else x.mudancas end,
    atualizado_em = now()
   where x.id = e.id
   returning * into e;
  return lab.res(true, case when v_novo then 'Experimento criado.' when cardinality(v_mudou) > 0 then 'Salvo. O relógio do teste recomeçou hoje.' else 'Salvo.' end,
                 jsonb_build_object('id', e.id, 'faltando', to_jsonb(lab.faltando(e))));
exception when check_violation or invalid_text_representation or invalid_datetime_format or numeric_value_out_of_range or foreign_key_violation then
  return lab.res(false, 'Dado inválido: ' || sqlerrm);
end $$;

create or replace function public.lab_status(p_id uuid, p_status text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e lab.experimento; v_falta text[];
begin
  if not coalesce(public.gp_eh_equipe(), false) then return lab.res(false, 'Sem acesso ao Laboratório.'); end if;
  select * into e from lab.experimento x where x.id = p_id for update;
  if not found then return lab.res(false, 'Experimento não encontrado.'); end if;
  if not lab.pode_editar(e) then return lab.res(false, 'Só quem criou, os responsáveis ou um admin mudam o status.'); end if;
  if p_status not in ('rascunho','no_ar','cancelado') then return lab.res(false, 'Status inválido.'); end if;
  if e.status in ('concluido','cancelado') then return lab.res(false, 'Experimento encerrado não muda.'); end if;
  if p_status = 'no_ar' then
    v_falta := lab.faltando(e);
    if cardinality(v_falta) > 0 then
      return lab.res(false, 'Sem ficha, não é teste: é mudança. Falta: ' || array_to_string(v_falta, ', ') || '.', jsonb_build_object('faltando', to_jsonb(v_falta)));
    end if;
    update lab.experimento x set status = 'no_ar', inicio = coalesce(x.inicio, (now() at time zone 'America/Sao_Paulo')::date), atualizado_em = now() where x.id = e.id;
    return lab.res(true, case when e.nivel = 1 then 'Decisão registrada. Confira na data de revisão.' else 'No ar. Olhe todo dia, mas decida só na data de leitura.' end);
  elsif p_status = 'rascunho' then
    if e.status <> 'no_ar' or exists (select 1 from lab.leitura l where l.experimento_id = e.id) then
      return lab.res(false, 'Só volta para rascunho o que está no ar e ainda não teve leitura.');
    end if;
    update lab.experimento x set status = 'rascunho', atualizado_em = now() where x.id = e.id;
    return lab.res(true, 'Voltou para rascunho.');
  else
    if nullif(btrim(coalesce(p_motivo, '')), '') is null then return lab.res(false, 'Diga por que o experimento foi cancelado.'); end if;
    update lab.experimento x set status = 'cancelado', aprendizado = coalesce(x.aprendizado, '') || case when x.aprendizado is null then '' else E'\n' end || 'Cancelado: ' || btrim(p_motivo),
           concluido_em = now(), atualizado_em = now() where x.id = e.id;
    return lab.res(true, 'Cancelado e registrado no log.');
  end if;
end $$;

create or replace function public.lab_registrar_leitura(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e lab.experimento; v_cls text;
begin
  if not coalesce(public.gp_eh_equipe(), false) then return lab.res(false, 'Sem acesso ao Laboratório.'); end if;
  select * into e from lab.experimento x where x.id = nullif(p ->> 'experimento_id', '')::uuid for update;
  if not found then return lab.res(false, 'Experimento não encontrado.'); end if;
  if not lab.pode_editar(e) then return lab.res(false, 'Só quem criou, os responsáveis ou um admin registram leitura.'); end if;
  if e.nivel = 1 then return lab.res(false, 'Nível 1 se fecha com a revisão, não com leitura.'); end if;
  if e.status not in ('no_ar','em_leitura') then return lab.res(false, 'Ponha o experimento no ar antes de registrar leitura.'); end if;
  v_cls := nullif(p ->> 'classificacao', '');
  insert into lab.leitura (experimento_id, em, a_n, a_x, b_n, b_x, medicao_ok, nota, calculo, classificacao, lido_por)
  values (e.id, coalesce(nullif(p ->> 'em', '')::date, (now() at time zone 'America/Sao_Paulo')::date),
          nullif(p ->> 'a_n', '')::numeric, nullif(p ->> 'a_x', '')::numeric, nullif(p ->> 'b_n', '')::numeric, nullif(p ->> 'b_x', '')::numeric,
          coalesce((p ->> 'medicao_ok')::boolean, true), nullif(btrim(p ->> 'nota'), ''), coalesce(p -> 'calculo', '{}'::jsonb), v_cls, auth.uid());
  if coalesce((p ->> 'concluir')::boolean, false) then
    if v_cls is null then return lab.res(false, 'Para concluir, a leitura precisa do resultado.'); end if;
    if nullif(btrim(coalesce(p ->> 'o_que_fizemos', '')), '') is null then return lab.res(false, 'Para concluir, diga o que fizemos com o resultado.'); end if;
    update lab.experimento x set status = 'concluido', resultado = v_cls, confianca = nullif(p -> 'calculo' ->> 'confianca', '')::numeric,
           o_que_fizemos = btrim(p ->> 'o_que_fizemos'), aprendizado = nullif(btrim(p ->> 'aprendizado'), ''), concluido_em = now(), atualizado_em = now()
     where x.id = e.id;
    return lab.res(true, 'Leitura registrada e experimento concluído no log.');
  end if;
  update lab.experimento x set status = 'em_leitura', atualizado_em = now() where x.id = e.id;
  return lab.res(true, 'Leitura registrada.');
exception when check_violation or invalid_text_representation or invalid_datetime_format or numeric_value_out_of_range then
  return lab.res(false, 'Dado inválido: ' || sqlerrm);
end $$;

create or replace function public.lab_revisar(p_id uuid, p_bateu text, p_aprendizado text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e lab.experimento;
begin
  if not coalesce(public.gp_eh_equipe(), false) then return lab.res(false, 'Sem acesso ao Laboratório.'); end if;
  select * into e from lab.experimento x where x.id = p_id for update;
  if not found then return lab.res(false, 'Experimento não encontrado.'); end if;
  if not lab.pode_editar(e) then return lab.res(false, 'Só quem criou, os responsáveis ou um admin revisam.'); end if;
  if e.nivel <> 1 then return lab.res(false, 'Revisão é do nível 1. Nos níveis 2 e 3, registre a leitura.'); end if;
  if e.status <> 'no_ar' then return lab.res(false, 'Registre a decisão (no ar) antes de revisar.'); end if;
  if p_bateu not in ('sim','nao','nao_sabe') then return lab.res(false, 'Responda se a previsão bateu: sim, não ou não dá para saber.'); end if;
  update lab.experimento x set status = 'concluido', revisao_bateu = p_bateu, aprendizado = nullif(btrim(p_aprendizado), ''), concluido_em = now(), atualizado_em = now()
   where x.id = e.id;
  return lab.res(true, 'Revisão registrada.');
end $$;

create or replace function public.lab_excluir(p_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare e lab.experimento;
begin
  if not coalesce(public.gp_eh_equipe(), false) then return lab.res(false, 'Sem acesso ao Laboratório.'); end if;
  select * into e from lab.experimento x where x.id = p_id for update;
  if not found then return lab.res(false, 'Experimento não encontrado.'); end if;
  if not lab.pode_editar(e) then return lab.res(false, 'Só quem criou, os responsáveis ou um admin excluem.'); end if;
  if e.status <> 'rascunho' then return lab.res(false, 'Só rascunho se exclui. O que foi ao ar fica no log (cancele, se for o caso).'); end if;
  delete from lab.experimento x where x.id = e.id;
  return lab.res(true, 'Rascunho excluído.');
end $$;

create or replace function public.lab_equipe() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not coalesce(public.gp_eh_equipe(), false) then raise exception 'Sem acesso ao Laboratório.' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'nome', p.nome) order by p.nome)
                     from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com' and p.nome is not null), '[]'::jsonb);
end $$;

revoke all on function public.lab_listar(), public.lab_obter(uuid), public.lab_salvar(jsonb), public.lab_status(uuid, text, text),
  public.lab_registrar_leitura(jsonb), public.lab_revisar(uuid, text, text), public.lab_excluir(uuid), public.lab_equipe() from public, anon;
grant execute on function public.lab_listar(), public.lab_obter(uuid), public.lab_salvar(jsonb), public.lab_status(uuid, text, text),
  public.lab_registrar_leitura(jsonb), public.lab_revisar(uuid, text, text), public.lab_excluir(uuid), public.lab_equipe() to authenticated;

-- ── semente: as duas linhas do log da seção 11 do playbook (autor Renan Schwarz) ──
insert into lab.experimento (area, nivel, titulo, status, hipotese, variavel, sorteio, metrica_tipo, metrica_decisao, taxa_base, regua,
                             amostra_minima, inicio, leitura_em, criado_por)
select 'trafego', 3, 'Página BL2 atual x uma dobra', 'no_ar',
       'A página de uma dobra aumenta o MQL por visita em 30% ou mais.', 'A página (atual x uma dobra)',
       'Visitantes divididos ao acaso entre as duas versões', 'taxa', 'MQL por visita', 0.119, 0.30, 1450,
       date '2026-10-13', date '2026-10-20', p.id
  from public.perfis p where p.email ilike 'renan@advmais.com'
union all
select 'trafego', 2, 'Migrar a captação da AK1 para a BL2', 'no_ar',
       'O custo por lead qualificado cai na BL2.', null, null, 'custo', 'Custo por lead qualificado', null, null,
       null, date '2026-10-05', date '2026-10-16', p.id
  from public.perfis p where p.email ilike 'renan@advmais.com';
update lab.experimento set grupo_piloto = 'Captação na BL2', grupo_comparacao = 'Captação na AK1',
       confundidores = 'Feriado prolongado de 10 a 12/10; mudança de verba e de CBO no mesmo período',
       medicao_antes = 'Leituras em 07, 12 e 16/10'
 where titulo = 'Migrar a captação da AK1 para a BL2';
