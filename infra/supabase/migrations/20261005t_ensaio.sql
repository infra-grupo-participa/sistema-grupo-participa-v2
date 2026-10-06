-- 20261005t: ENSAIO da F2 (não aplica nada: tudo termina em ROLLBACK). Rodado em produção (mbvybujpkwuorhtdzcde) em
-- 06/10/2026, em partes (cada chamada do MCP abaixo de ~22 s, cada uma com seu begin … rollback), com a F1 já aplicada:
--   PARTE A (até o 1º "rollback"): o corpo INTEIRO da migration + provas de cada RPC como a tela chama (authenticated +
--     request.jwt.claims de perfis REAIS: gestor = admin real "Jonathan…", vendedor A = mp, vendedor B = ro, visualizador).
--   PARTE B: massa sintética 10× + explain (analyze, buffers) 2× de crm_criar_negocio e crm_mover_etapa.
--   PARTE C: conferência separada de que nada persistiu.
-- Como rodar: cada parte inteira de uma vez (SQL editor, psql ou execute_sql), como postgres. Saída na temp _z_out;
-- esperado: NENHUMA linha começando com "ERRADO". Dados fictícios: 4 pessoas "Ensaio F2 …" (teste=true). Perfis,
-- produto e oferta reais escolhidos por SELECT: só ids em temp e booleanos/contagens na saída.
-- escrita_ligada só é ligada DENTRO da transação do ensaio (passo 2 prova que desligada tudo recusa).
--
-- ═══ PARTE A ═════════════════════════════════════════════════════════════════════════════════════════════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || p_passo || ' — ' || coalesce(p_det, ''));
$$;

-- ═══ CORPO DA MIGRATION (copiado sem mudança de 20261005t_crm_f2_escrita.sql; mudou a migration, gerar de novo) ═══
-- 20261005t: F2 do Comercial — RPCs de ESCRITA do CRM + triggers de regra + notificações por trigger
--
-- STATUS: NÃO APLICADA — aguardando ok do Arthur. Ensaio: 20261005t_ensaio.sql (begin … rollback, em partes).
-- Medidas e planos: 20261005t.explain.md. Ao aplicar: renomear o arquivo para a versão gravada em
-- supabase_migrations.schema_migrations. Desenho: docs/projetos/comercial/backend-arquitetura.md §4.1–4.5 e §6 (F2).
-- Depende da F1 (20261005s, tabelas crm.* + 20 RPCs de leitura) e da F0 (20261005r). Contrato: web/modules/comercial/
-- application/ports.ts; mensagens = web/modules/comercial/infrastructure/mock-comercial.repository.ts.
--
-- O QUE FAZ
--   1. Helpers internos (crm.*, sem grant para ninguém; só as RPCs definer chamam): envelope {ok,msg,…}, guarda comum
--      (kill-switch escrita_ligada + eh_comercial), tradução de erro de dado para mensagem, nome de pessoa/vendedor,
--      "pode escrever na pessoa", campos obrigatórios que faltam, escolha de dono (distribuição em SQL),
--      validação de funil (= validarFunil do domínio), chave de projeto (= chaveProjeto do domínio).
--   2. Triggers de regra:
--        crm.negocio  BEFORE: ganho só pela função da Hotmart (F3, set_config('crm.ganho_hotmart','on')); etapa de Ganho
--                     só com status ganho; encerrado não muda de etapa; etapa arquivada recusada; campos obrigatórios
--                     ao mudar de etapa; perdido só com motivo ATIVO.
--        crm.distribuicao / crm.funil  CONSTRAINT TRIGGER (deferrable, initially deferred): distribuição ativa soma 100
--                     (geral sempre que houver linha ativa; do funil quando distribuicao_propria).
--        crm.negocio  AFTER: notificação lead_novo (dono novo em negócio aberto) e venda_aprovada (status → ganho, F3).
--   3. crm.notificar_prazos(): prazo_estourado e atividade_vencendo (para cron de 5 min). NÃO agendada: só roda com
--      crm.config.notificacao_cron_ligado = true e o cron.schedule fica no .explain.md (o Arthur agenda ao ligar).
--   4. 22 RPCs de escrita public.crm_* (SECURITY DEFINER, search_path = ''), uma por método de escrita do port que tem
--      tabela na F1. Todas: guarda escrita_ligada (manutenção) + eh_comercial + regra de dono/gestor; mesmas mensagens
--      do mock; set_config('crm.resumo', …) antes de cada write (o crm.tg_log da F0 grava 1 linha por linha escrita, com
--      resumo e diff); erro de dado vira {ok:false, msg} (nunca 500); revoke de PUBLIC/anon, grant a authenticated.
--   5. NÃO liga escrita_ligada (continua false: todas as RPCs devolvem "CRM em manutenção").
--
-- FORA DA F2 (tabelas não existem na F1): enviarMensagem, marcarConversaLida (F4 conversa/mensagem), salvarFicha,
--   decidirFicha (F4 ficha_disparo), atualizarItemFila (fila_item), criarLink (link). Notificações lead_respondeu
--   (F4) e ficha_para_aprovar (F4) idem.
--
-- AS 5 PERGUNTAS (números em 20261005t.explain.md)
--   escala: escrita é por item (1 negócio, 1 atividade). A única leitura que cresce com a base é a escolha de dono:
--     conta negócios do funil por vendedor desde crm.config.ciclo_distribuicao_desde (negocio_dono_idx); medida com 30
--     mil negócios. Prazos (cron) percorrem só negócios ABERTOS (negocio_funil_aberto_idx).
--   índice: negócio/atividade/dashboard por PK; grupo da pessoa por pessoas.grupo (pessoas_mesclada_idx); aberto por
--     pessoa+funil pelo índice único negocio_aberto_uidx.
--   frequência: só quando alguém clica. Sem cron ligado (notificar_prazos fica desagendada).
--   repetição: cada RPC faz o write numa chamada (sem ler-modificar-escrever no cliente).
--   reversão: crm.config.escrita_ligada = false (já é o estado) desliga TODAS as RPCs em ~10 s; bloco REVERSÃO no fim.
--
-- PREMISSAS (guarda aborta se faltar): F1 aplicada (tabelas e 20 RPCs de leitura); nenhuma RPC de escrita ainda;
--   escrita_ligada = false; crm.negocio e crm.distribuicao vazias (a constraint trigger de soma nasce sem passivo).

set local lock_timeout = '3s';
set local statement_timeout = '20s';

-- ─── 0. Guarda de premissa ───────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_falta text;
begin
  select string_agg(t, ', ') into v_falta
    from unnest(array['crm.linha','crm.agrupador','crm.produto_comercial','crm.oferta_comercial','crm.campo_def',
                      'crm.modelo_funil','crm.modelo_projeto','crm.funil','crm.etapa_funil','crm.campanha','crm.motivo_perda',
                      'crm.distribuicao','crm.pessoa_comercial','crm.negocio','crm.atividade','crm.nota','crm.dashboard',
                      'crm.painel','crm.preferencias_notificacao','crm.notificacao','crm.config','crm.vendedor','crm.log']) t
   where to_regclass(t) is null;
  if v_falta is not null then raise exception '20261005t: F1 não aplicada (faltam: %)', v_falta; end if;
  if to_regprocedure('crm.tg_log()') is null or to_regprocedure('crm.pode_ver_pessoa(uuid)') is null
     or to_regprocedure('crm.eh_gestor()') is null or to_regprocedure('crm.eh_vendedor()') is null
     or to_regprocedure('pessoas.atual(uuid)') is null or to_regprocedure('pessoas.grupo(uuid)') is null
     or to_regprocedure('pessoas.dados(uuid)') is null then
    raise exception '20261005t: helpers da F0/F1 ausentes';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%') < 20 then
    raise exception '20261005t: RPCs de leitura da F1 ausentes';
  end if;
  if to_regprocedure('public.crm_mover_etapa(uuid,uuid)') is not null or to_regprocedure('crm.guarda_escrita()') is not null then
    raise exception '20261005t: RPCs de escrita já existem (migration já aplicada?)';
  end if;
  if coalesce((select c.escrita_ligada from crm.config c), true) then
    raise exception '20261005t: crm.config.escrita_ligada deveria estar false';
  end if;
  if (select count(*) from crm.negocio) <> 0 or (select count(*) from crm.distribuicao) <> 0 then
    raise exception '20261005t: crm.negocio/crm.distribuicao deveriam estar vazias (escrita só existe a partir da F2)';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
                    and column_name = 'notificacao_cron_ligado') then
    raise exception '20261005t: crm.config sem notificacao_cron_ligado';
  end if;
end
$guarda$;

-- ─── 1. Helpers internos (sem grant: só as RPCs SECURITY DEFINER, donas postgres, chamam) ──────────────────────────────
create function crm.res(p_ok boolean, p_msg text default null, p_extra jsonb default null) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('ok', p_ok)
         || case when p_msg is null then '{}'::jsonb else jsonb_build_object('msg', p_msg) end
         || coalesce(p_extra, '{}'::jsonb);
$$;

-- Kill-switch + papel. null = pode seguir. Limpa resumo que tenha sobrado de outra escrita na mesma transação.
create function crm.guarda_escrita() returns jsonb
language plpgsql security definer set search_path = '' as $$
begin
  perform set_config('crm.resumo', '', true);
  if not coalesce((select c.escrita_ligada from crm.config c), false) then
    return crm.res(false, 'CRM em manutenção: escrita desligada.');
  end if;
  if not coalesce(crm.eh_comercial(), false) then
    return crm.res(false, 'Sem acesso ao Comercial.');
  end if;
  return null;
end
$$;

-- Erro de dado (CHECK, unique, FK, cast) → mensagem para a tela. Mensagem de trigger nosso (sem constraint) passa direto.
create function crm.erro_dados(p_estado text, p_msg text, p_constraint text) returns jsonb
language sql immutable set search_path = '' as $$
  select crm.res(false, case
    when p_estado = '23505' and p_constraint = 'negocio_aberto_uidx' then 'Este contato já tem negócio aberto neste funil.'
    when p_estado = '23505' and p_constraint = 'agrupador_nome_uidx' then 'Já existe um agrupador com esse nome.'
    when p_estado = '23505' and p_constraint = 'etapa_nome_uidx' then 'Há duas etapas com o mesmo nome.'
    when p_estado = '23505' and p_constraint = 'etapa_ganho_uidx' then 'O funil precisa de exatamente uma etapa de Ganho.'
    when p_estado = '23505' then 'Registro duplicado (' || coalesce(nullif(p_constraint, ''), '?') || ').'
    when p_estado = '23514' and coalesce(p_constraint, '') = '' then p_msg
    when p_estado = '23514' then 'Dados inválidos (' || p_constraint || ').'
    when p_estado = '23503' then 'Referência inexistente (' || coalesce(nullif(p_constraint, ''), '?') || ').'
    when p_estado = '23502' then 'Campo obrigatório vazio.'
    when p_estado in ('22P02', '22007', '22008', '22003', '22001', '22023') then 'Valor inválido: ' || p_msg
    else 'Não foi possível salvar: ' || p_msg end);
$$;

create function crm.uuid_ou_null(p text) returns uuid
language sql immutable set search_path = '' as $$
  select case when p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p::uuid end;
$$;

create function crm.nome_pessoa(p uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select d.d_nome from pessoas.dados(pessoas.atual(p)) d), 'contato');
$$;

create function crm.nome_perfil(p uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case when p is null then 'sem dono' else coalesce((select x.nome from public.perfis x where x.id = p), p::text) end;
$$;

-- Vendedor que pode receber lead: mesma régua de crm.eh_vendedor(), para outro perfil.
create function crm.vendedor_ativo(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select v.ativo and pf.status = 'ativo' and 'comercial' = any(coalesce(pf.areas, '{}'))
                          and 'comercial.vender' = any(coalesce(pf.funcoes, '{}'))
                     from crm.vendedor v join public.perfis pf on pf.id = v.perfil_id where v.perfil_id = p), false);
$$;

-- Escrever na pessoa (nota, atividade sem negócio): gestor; vendedor dono do contato ou com negócio dele na pessoa.
create function crm.pode_escrever_pessoa(p uuid) returns boolean
language plpgsql stable security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_g uuid[];
begin
  if p is null or v_eu is null then return false; end if;
  if coalesce(crm.eh_gestor(), false) then return true; end if;
  if not coalesce(crm.eh_vendedor(), false) then return false; end if;
  v_g := pessoas.grupo(pessoas.atual(p));
  return coalesce(exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and pc.dono_id = v_eu)
               or exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.dono_id = v_eu), false);
end
$$;

-- Camada comercial da pessoa (1:1, sob demanda). Devolve o pessoa_id da linha (do grupo; prefere a pessoa atual).
create function crm.garantir_pc(p uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_atual uuid := pessoas.atual(p); v uuid;
begin
  select pc.pessoa_id into v from crm.pessoa_comercial pc
   where pc.pessoa_id = any(pessoas.grupo(v_atual)) order by pc.pessoa_id = v_atual desc, pc.criado_em limit 1;
  if v is not null then return v; end if;
  perform set_config('crm.resumo', 'Abriu o contato comercial de ' || crm.nome_pessoa(v_atual), true);
  insert into crm.pessoa_comercial (pessoa_id) values (v_atual) on conflict (pessoa_id) do nothing;
  perform set_config('crm.resumo', '', true);
  return v_atual;
end
$$;

-- Rótulos dos campos que faltam para ENTRAR na etapa (inclui os das etapas anteriores) = camposFaltandoNoFunil.
-- null = nada falta. Ordem: etapa, depois posição do campo na etapa (1ª ocorrência), como o Set do domínio.
create function crm.campos_faltando(p_campos jsonb, p_funil uuid, p_etapa uuid) returns text
language sql stable set search_path = '' as $$
  with alvo as (select e.ordem from crm.etapa_funil e where e.id = p_etapa and e.funil_id = p_funil),
  ex as (
    select u.c, min(e.ordem::int * 1000 + u.o) k
      from crm.etapa_funil e cross join alvo
      cross join lateral unnest(e.campos_obrigatorios) with ordinality u(c, o)
     where e.funil_id = p_funil and e.arquivada_em is null and e.ordem <= alvo.ordem
     group by u.c)
  select string_agg(coalesce(d.rotulo, ex.c), ', ' order by ex.k)
    from ex left join crm.campo_def d on d.chave = ex.c
   where nullif(btrim(coalesce(p_campos ->> ex.c, '')), '') is null;
$$;

-- Dono de negócio novo = escolherDono do domínio: contato com dono ativo mantém o dono; senão quem está mais abaixo da
-- cota (percentual) entre os ativos da distribuição do funil (se própria) ou geral, contando os negócios que cada um
-- recebeu NESTE funil desde crm.config.ciclo_distribuicao_desde. Determinístico. Chamar sob o advisory lock do funil.
create function crm.escolher_dono(p_pessoa uuid, p_funil uuid) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v_dono uuid; v_propria boolean; v_desde timestamptz; v_atual uuid := pessoas.atual(p_pessoa);
begin
  select pc.dono_id into v_dono from crm.pessoa_comercial pc
   where pc.pessoa_id = any(pessoas.grupo(v_atual)) and pc.dono_id is not null
   order by pc.pessoa_id = v_atual desc, pc.criado_em limit 1;
  if v_dono is not null and crm.vendedor_ativo(v_dono) then return v_dono; end if;
  select f.distribuicao_propria into v_propria from crm.funil f where f.id = p_funil;
  select c.ciclo_distribuicao_desde into v_desde from crm.config c;
  with el as (
    select d.vendedor_id, d.percentual from crm.distribuicao d
     where d.ativo and d.percentual > 0
       and d.funil_id is not distinct from (case when coalesce(v_propria, false) then p_funil end)
       and crm.vendedor_ativo(d.vendedor_id)),
  rec as (
    select el.vendedor_id, el.percentual,
           (select count(*) from crm.negocio n
             where n.dono_id = el.vendedor_id and n.criado_em >= v_desde and n.funil_id = p_funil) r
      from el),
  tot as (select coalesce(sum(rec.r), 0) + 1 t from rec)
  select rec.vendedor_id into v_dono from rec cross join tot
   order by (rec.percentual / 100.0) * tot.t - rec.r desc, rec.percentual desc, rec.vendedor_id
   limit 1;
  return v_dono;
end
$$;

-- Etapas / campanhas de um payload Funil (camelCase). id não-uuid (rascunho da tela) = etapa nova.
create function crm.etapas_payload(p jsonb)
returns table (id uuid, ord int, nome text, papel text, cor text, sla_a int, sla_c int, campos text[], criterio text)
language sql immutable set search_path = '' as $$
  select crm.uuid_ou_null(x.j ->> 'id'), (x.i - 1)::int, btrim(coalesce(x.j ->> 'nome', '')), x.j ->> 'papel',
         coalesce(nullif(x.j ->> 'cor', ''), 'neutral'), (x.j ->> 'slaAtencaoMin')::int, (x.j ->> 'slaCriticoMin')::int,
         array(select jsonb_array_elements_text(case when jsonb_typeof(x.j -> 'camposObrigatorios') = 'array'
                                                     then x.j -> 'camposObrigatorios' else '[]'::jsonb end)),
         coalesce(x.j ->> 'criterio', '')
    from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality x(j, i);
$$;

create function crm.campanhas_payload(p jsonb)
returns table (id uuid, nome text, canal text, regra text, ativa boolean)
language sql immutable set search_path = '' as $$
  select crm.uuid_ou_null(x.j ->> 'id'), btrim(coalesce(x.j ->> 'nome', '')), coalesce(nullif(x.j ->> 'canal', ''), 'manual'),
         coalesce(x.j ->> 'regra', ''), coalesce((x.j ->> 'ativa')::boolean, true)
    from jsonb_array_elements(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) x(j);
$$;

-- = validarFunil (domain/funis.ts): primeiro problema, ou null.
create function crm.validar_funil(p jsonb) returns text
language plpgsql stable security definer set search_path = '' as $$
declare v_et jsonb := case when jsonb_typeof(p -> 'etapas') = 'array' then p -> 'etapas' else '[]'::jsonb end;
        v_n int; r record; v_soma int;
begin
  if btrim(coalesce(p ->> 'nome', '')) = '' then return 'Dê um nome ao funil.'; end if;
  if coalesce(p ->> 'agrupadorId', '') = '' then return 'Escolha o agrupador.'; end if;
  if p ->> 'tipo' = 'hotmart' and (jsonb_typeof(p -> 'eventosHotmart') is distinct from 'array'
                                   or jsonb_array_length(p -> 'eventosHotmart') = 0) then
    return 'Funil automático precisa de ao menos um evento da Hotmart.';
  end if;
  v_n := jsonb_array_length(v_et);
  if v_n < 2 then return 'O funil precisa de pelo menos 2 etapas.'; end if;
  if exists (select 1 from crm.etapas_payload(v_et) e where e.nome = '') then return 'Toda etapa precisa de nome.'; end if;
  if (select count(distinct lower(e.nome)) from crm.etapas_payload(v_et) e) <> v_n then return 'Há duas etapas com o mesmo nome.'; end if;
  if (select count(*) from crm.etapas_payload(v_et) e where e.papel = 'fechado') <> 1 then
    return 'O funil precisa de exatamente uma etapa de Ganho.';
  end if;
  if (select e.papel from crm.etapas_payload(v_et) e order by e.ord desc limit 1) <> 'fechado' then
    return 'A etapa de Ganho precisa ser a última.';
  end if;
  for r in select * from crm.etapas_payload(v_et) e order by e.ord loop
    if (r.sla_a is null) <> (r.sla_c is null) then return format('"%s": preencha os dois alertas ou nenhum.', r.nome); end if;
    if r.sla_a is not null and r.sla_a >= r.sla_c then return format('"%s": o alerta crítico precisa vir depois do de atenção.', r.nome); end if;
  end loop;
  if jsonb_typeof(p -> 'distribuicao') = 'array' then
    select coalesce(sum((x ->> 'percentual')::int), 0) into v_soma
      from jsonb_array_elements(p -> 'distribuicao') x
     where crm.vendedor_ativo(crm.uuid_ou_null(x ->> 'vendedorId'));
    if v_soma <> 100 then return 'A distribuição própria precisa somar 100%.'; end if;
  end if;
  return null;
end
$$;

-- = chaveProjeto (domain/modelos.ts): minúsculas, sem acento, hífens.
create function crm.chave_projeto(p text) returns text
language sql immutable set search_path = '' as $$
  select btrim(regexp_replace(translate(lower(coalesce(p, '')),
                 'áàâãäåéèêëíìîïóòôõöúùûüçñý', 'aaaaaaeeeeiiiiooooouuuucny'), '[^a-z0-9]+', '-', 'g'), '-');
$$;

-- ─── 2. Triggers de regra ───────────────────────────────────────────────────────────────────────────────────────────
-- Negócio: as regras que travam escrita valem também fora das RPCs (defesa no banco).
create function crm.tg_negocio_regras() returns trigger
language plpgsql set search_path = '' as $$
declare v_papel text; v_arq timestamptz; v_falta text;
        v_msg_ganho constant text := 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.';
begin
  if tg_op = 'INSERT' or new.etapa_id is distinct from old.etapa_id or new.status is distinct from old.status then
    select e.papel, e.arquivada_em into v_papel, v_arq from crm.etapa_funil e where e.id = new.etapa_id;
  end if;
  if tg_op = 'UPDATE' and new.etapa_id is distinct from old.etapa_id then
    if old.status <> 'aberto' and new.status = old.status then
      raise exception 'Negócio encerrado não muda de etapa.' using errcode = '23514';
    end if;
    if v_arq is not null then raise exception 'Etapa não existe neste funil.' using errcode = '23514'; end if;
    if new.status = 'aberto' then
      v_falta := crm.campos_faltando(new.campos, new.funil_id, new.etapa_id);
      if v_falta is not null then raise exception 'Preencha antes: %.', v_falta using errcode = '23514'; end if;
    end if;
  end if;
  if new.status = 'ganho' and (tg_op = 'INSERT' or old.status is distinct from 'ganho')
     and coalesce(current_setting('crm.ganho_hotmart', true), '') <> 'on' then
    raise exception '%', v_msg_ganho using errcode = '23514';
  end if;
  if v_papel = 'fechado' and new.status = 'aberto' then
    raise exception '%', v_msg_ganho using errcode = '23514';
  end if;
  if new.status = 'perdido' and (tg_op = 'INSERT' or old.status is distinct from 'perdido')
     and not exists (select 1 from crm.motivo_perda m where m.chave = new.motivo_perda and m.ativo) then
    raise exception 'Motivo fora do cadastro não existe.' using errcode = '23514';
  end if;
  return new;
end
$$;
create trigger negocio_regras before insert or update on crm.negocio for each row execute function crm.tg_negocio_regras();

-- Distribuição: soma dos ativos = 100 (no fim da transação).
create function crm.confere_distribuicao(p_funil uuid) returns void
language plpgsql stable set search_path = '' as $$
declare v_soma int; v_tem boolean; v_propria boolean;
begin
  if p_funil is not null then
    select f.distribuicao_propria into v_propria from crm.funil f where f.id = p_funil;
    if not coalesce(v_propria, false) then return; end if;
  end if;
  select coalesce(sum(d.percentual) filter (where v.ativo and pf.status = 'ativo'), 0), count(*) > 0
    into v_soma, v_tem
    from crm.distribuicao d join crm.vendedor v on v.perfil_id = d.vendedor_id join public.perfis pf on pf.id = d.vendedor_id
   where d.ativo and d.funil_id is not distinct from p_funil;
  if (p_funil is null and v_tem and v_soma <> 100) or (p_funil is not null and v_soma <> 100) then
    raise exception '%', case when p_funil is null then 'A soma dos percentuais dos ativos precisa dar 100%.'
                              else 'A distribuição própria precisa somar 100%.' end using errcode = '23514';
  end if;
end
$$;

create function crm.tg_distribuicao_soma() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_table_name = 'funil' then
    perform crm.confere_distribuicao(new.id);
  else
    perform crm.confere_distribuicao(new.funil_id);
    if tg_op = 'UPDATE' and old.funil_id is distinct from new.funil_id then perform crm.confere_distribuicao(old.funil_id); end if;
  end if;
  return null;
end
$$;
create constraint trigger distribuicao_soma after insert or update on crm.distribuicao
  deferrable initially deferred for each row execute function crm.tg_distribuicao_soma();
create constraint trigger funil_distribuicao_soma after insert or update on crm.funil
  deferrable initially deferred for each row execute function crm.tg_distribuicao_soma();

-- Notificações do negócio (lead novo atribuído; venda aprovada — esta só dispara na F3). Falha aqui NÃO derruba o write.
create function crm.tg_negocio_notifica() returns trigger
language plpgsql set search_path = '' as $$
declare v_gat text; v_tit text; v_corpo text; v_nome text;
begin
  if new.dono_id is null then return null; end if;
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
$$;
create trigger negocio_notifica_ins after insert on crm.negocio for each row
  when (new.dono_id is not null and new.status = 'aberto') execute function crm.tg_negocio_notifica();
create trigger negocio_notifica_upd after update on crm.negocio for each row
  when (new.dono_id is not null and (new.dono_id is distinct from old.dono_id or new.status is distinct from old.status))
  execute function crm.tg_negocio_notifica();

-- Prazo estourado (negócio aberto além do alerta crítico da etapa) e atividade vencendo em 30 min. Para um cron de 5 min
-- (NÃO agendado aqui). Sai na 1ª linha se o kill-switch estiver desligado. Não duplica (unique perfil+gatilho+ref).
create function crm.notificar_prazos() returns int
language plpgsql security definer set search_path = '' as $$
declare v1 int := 0; v2 int := 0;
begin
  if not coalesce((select c.notificacao_cron_ligado from crm.config c), false) then return 0; end if;
  insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
  select n.dono_id, 'prazo_estourado', n.id::text || ':' || extract(epoch from n.etapa_desde)::bigint,
         left('Prazo estourado: ' || crm.nome_pessoa(n.pessoa_id), 200), left(e.nome || ' · aja agora ou escale.', 500),
         '/comercial/funil?negocio=' || n.id
    from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id
   where n.status = 'aberto' and n.dono_id is not null and e.sla_critico_min is not null
     and n.etapa_desde + make_interval(mins => e.sla_critico_min) <= now()
     and not exists (select 1 from crm.preferencias_notificacao p where p.perfil_id = n.dono_id and (p.gatilhos ->> 'prazo_estourado') = 'false')
     and not exists (select 1 from crm.notificacao x where x.perfil_id = n.dono_id and x.gatilho = 'prazo_estourado'
                        and x.ref_id = n.id::text || ':' || extract(epoch from n.etapa_desde)::bigint)
  on conflict (perfil_id, gatilho, ref_id) do nothing;
  get diagnostics v1 = row_count;
  insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
  select a.dono_id, 'atividade_vencendo', a.id::text, left('Em 30 min: ' || a.titulo, 200), left(crm.nome_pessoa(a.pessoa_id), 500),
         '/comercial/atividades'
    from crm.atividade a
   where a.concluida_em is null and not a.cancelada and a.vence_em > now() and a.vence_em <= now() + interval '30 minutes'
     and not exists (select 1 from crm.preferencias_notificacao p where p.perfil_id = a.dono_id and (p.gatilhos ->> 'atividade_vencendo') = 'false')
     and not exists (select 1 from crm.notificacao x where x.perfil_id = a.dono_id and x.gatilho = 'atividade_vencendo' and x.ref_id = a.id::text)
  on conflict (perfil_id, gatilho, ref_id) do nothing;
  get diagnostics v2 = row_count;
  return v1 + v2;
end
$$;

-- ─── 3. RPCs de escrita: NEGÓCIO ─────────────────────────────────────────────────────────────────────────────────────
-- Esqueleto: guarda (manutenção, papel) → trava a linha → dono/gestor → regra → resumo → write → {ok}.
-- Erro de dado → crm.erro_dados (o bloco inteiro desfaz).

create function public.crm_mover_etapa(p_negocio uuid, p_etapa uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; e crm.etapa_funil%rowtype; v_de text; v_falta text;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  if n.etapa_id = p_etapa then return crm.res(true); end if;
  if n.status <> 'aberto' then return crm.res(false, 'Negócio encerrado não muda de etapa.'); end if;
  select * into e from crm.etapa_funil x where x.id = p_etapa and x.funil_id = n.funil_id and x.arquivada_em is null;
  if not found then return crm.res(false, 'Etapa não existe neste funil.'); end if;
  if e.papel = 'fechado' then return crm.res(false, 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.'); end if;
  v_falta := crm.campos_faltando(n.campos, n.funil_id, p_etapa);
  if v_falta is not null then return crm.res(false, 'Preencha antes: ' || v_falta || '.'); end if;
  select x.nome into v_de from crm.etapa_funil x where x.id = n.etapa_id;
  perform set_config('crm.resumo', format('Moveu %s de %s para %s', crm.nome_pessoa(n.pessoa_id), v_de, e.nome), true);
  update crm.negocio x set etapa_id = p_etapa, etapa_desde = now(), ultima_interacao_em = now(), atualizado_em = now()
   where x.id = p_negocio;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_salvar_campos(p_negocio uuid, p_campos jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; v_novo jsonb; v_qtd int;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if jsonb_typeof(p_campos) is distinct from 'object' then return crm.res(false, 'Campos inválidos.'); end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  select count(*) into v_qtd from jsonb_each(p_campos) c
   where coalesce(n.campos ->> c.key, '') is distinct from coalesce(c.value #>> '{}', '');
  if v_qtd = 0 then return crm.res(true); end if;
  v_novo := jsonb_strip_nulls(n.campos || p_campos);
  perform set_config('crm.resumo', format('Editou %s campo(s) de %s', v_qtd, crm.nome_pessoa(n.pessoa_id)), true);
  update crm.negocio x set campos = v_novo, atualizado_em = now() where x.id = p_negocio;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_marcar_perdido(p_negocio uuid, p_motivo text, p_nota text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; m crm.motivo_perda%rowtype; v_nome text; v_pc uuid;
        a record; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Só negócio aberto pode ser perdido.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  if n.status <> 'aberto' then return crm.res(false, 'Só negócio aberto pode ser perdido.'); end if;
  select * into m from crm.motivo_perda x where x.chave = p_motivo and x.ativo;
  if not found then return crm.res(false, 'Motivo fora do cadastro não existe.'); end if;
  v_nome := crm.nome_pessoa(n.pessoa_id);
  perform set_config('crm.resumo', format('Marcou %s como perdido: %s', v_nome, m.rotulo), true);
  update crm.negocio x set status = 'perdido', motivo_perda = m.chave, nota_perda = nullif(btrim(coalesce(p_nota, '')), ''),
                           fechado_em = now(), atualizado_em = now()
   where x.id = p_negocio;
  for a in select x.id, x.titulo from crm.atividade x where x.negocio_id = p_negocio and x.concluida_em is null for update loop
    perform set_config('crm.resumo', format('Cancelou "%s" de %s: negócio perdido', a.titulo, v_nome), true);
    update crm.atividade x set concluida_em = now(), resultado = 'Cancelada: negócio perdido', cancelada = true where x.id = a.id;
  end loop;
  if m.bloqueia then
    v_pc := crm.garantir_pc(n.pessoa_id);
    perform set_config('crm.resumo', format('%s foi para a lista de bloqueio (%s)', v_nome, m.rotulo), true);
    update crm.pessoa_comercial x set opt_out = true, opt_out_em = now(), opt_out_motivo = left(m.rotulo, 200), atualizado_em = now()
     where x.pessoa_id = v_pc and not x.opt_out;
  end if;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_transferir_dono(p_negocio uuid, p_dono uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; n crm.negocio%rowtype; v_nome text; v_de text; v_para text; v_pc uuid; a record;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Troca de dono só pelo gestor do Comercial.'); end if;
  if btrim(coalesce(p_motivo, '')) = '' then return crm.res(false, 'Escreva o motivo da troca.'); end if;
  select * into n from crm.negocio x where x.id = p_negocio for update;
  if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
  if not crm.vendedor_ativo(p_dono) then return crm.res(false, 'Vendedor não encontrado ou inativo.'); end if;
  if n.dono_id = p_dono then return crm.res(true); end if;
  v_nome := crm.nome_pessoa(n.pessoa_id); v_de := crm.nome_perfil(n.dono_id); v_para := crm.nome_perfil(p_dono);
  perform set_config('crm.resumo', left(format('Trocou o dono de %s: %s → %s. Motivo: %s', v_nome, v_de, v_para, btrim(p_motivo)), 1000), true);
  update crm.negocio x set dono_id = p_dono, atualizado_em = now() where x.id = p_negocio;
  v_pc := crm.garantir_pc(n.pessoa_id);
  perform set_config('crm.resumo', format('Dono do contato %s: %s', v_nome, v_para), true);
  update crm.pessoa_comercial x set dono_id = p_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is distinct from p_dono;
  for a in select x.id, x.titulo from crm.atividade x
            where x.negocio_id = p_negocio and x.concluida_em is null and x.dono_id is distinct from p_dono for update loop
    perform set_config('crm.resumo', format('Atividade "%s" passou para %s', a.titulo, v_para), true);
    update crm.atividade x set dono_id = p_dono where x.id = a.id;
  end loop;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_atribuir_contato(p_pessoa uuid, p_dono uuid, p_motivo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_atual uuid; v_pc uuid; v_nome text; v_para text; n record;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor define dono.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if btrim(coalesce(p_motivo, '')) = '' then return crm.res(false, 'Escreva o motivo.'); end if;
  if not crm.vendedor_ativo(p_dono) then return crm.res(false, 'Vendedor não encontrado ou inativo.'); end if;
  v_nome := crm.nome_pessoa(v_atual); v_para := crm.nome_perfil(p_dono);
  v_pc := crm.garantir_pc(v_atual);
  perform set_config('crm.resumo', left(format('Definiu %s como dono de %s. Motivo: %s', v_para, v_nome, btrim(p_motivo)), 1000), true);
  update crm.pessoa_comercial x set dono_id = p_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is distinct from p_dono;
  for n in select x.id from crm.negocio x
            where x.pessoa_id = any(pessoas.grupo(v_atual)) and x.status = 'aberto' and x.dono_id is null for update loop
    perform set_config('crm.resumo', format('Negócio de %s herdou o dono %s', v_nome, v_para), true);
    update crm.negocio x set dono_id = p_dono, atualizado_em = now() where x.id = n.id;
  end loop;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- Negócio novo na 1ª etapa. Dono: contato com dono mantém; senão distribuição (sob advisory lock do funil, para dois
-- cliques simultâneos não escolherem pela mesma contagem). Valor = ticket de referência da linha (como o mock).
create function public.crm_criar_negocio(p_pessoa uuid, p_funil uuid, p_campanha uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_atual uuid; v_g uuid[]; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pc uuid; v_utm jsonb;
        v_valor numeric; v_id uuid; v_nome text; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual)
     or not (coalesce(crm.eh_gestor(), false) or coalesce(crm.pode_ver_pessoa(v_atual), false)) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  v_g := pessoas.grupo(v_atual);
  if exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and pc.opt_out) then
    return crm.res(false, 'Este contato pediu para não receber contato.');
  end if;
  select * into f from crm.funil x where x.id = p_funil and x.ativo;
  if not found then return crm.res(false, 'Funil não encontrado.'); end if;
  if p_campanha is not null and not exists (select 1 from crm.campanha c where c.id = p_campanha and c.funil_id = p_funil) then
    return crm.res(false, 'Campanha não é deste funil.');
  end if;
  perform pg_advisory_xact_lock(hashtext('crm.dist:' || p_funil::text));
  if exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.funil_id = p_funil and n.status = 'aberto') then
    return crm.res(false, 'Este contato já tem negócio aberto neste funil.');
  end if;
  select e.id into v_etapa from crm.etapa_funil e where e.funil_id = p_funil and e.arquivada_em is null order by e.ordem limit 1;
  if v_etapa is null then return crm.res(false, 'Funil sem etapas.'); end if;
  v_dono := crm.escolher_dono(v_atual, p_funil);
  v_nome := crm.nome_pessoa(v_atual);
  v_pc := crm.garantir_pc(v_atual);
  if v_dono is not null then
    perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição)', v_nome, crm.nome_perfil(v_dono)), true);
    update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is null;
  end if;
  select pc.utm_primeira into v_utm from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;
  select l.ticket_ref into v_valor from crm.linha l where l.chave = f.linha;
  perform set_config('crm.resumo', format('Criou negócio de %s em %s (dono: %s)', v_nome, f.nome, crm.nome_perfil(v_dono)), true);
  insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, campos, utm, ultima_interacao_em)
  values (v_atual, p_funil, v_etapa, p_campanha, f.linha, 'venda_ativa', v_dono, coalesce(v_valor, 0),
          jsonb_build_object('origem', coalesce(nullif(v_utm ->> 'source', ''), 'direto') || ' / ' || coalesce(nullif(v_utm ->> 'campaign', ''), '—')),
          coalesce(v_utm, '{}'::jsonb), null)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('negocioId', v_id, 'donoId', v_dono));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- ─── 4. RPCs de escrita: ATIVIDADE e NOTA ────────────────────────────────────────────────────────────────────────────
create function public.crm_criar_atividade(p_negocio uuid, p_pessoa uuid, p_tipo text, p_titulo text, p_vence_em timestamptz)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_atual uuid; n crm.negocio%rowtype; v_dono uuid; v_id uuid;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if btrim(coalesce(p_titulo, '')) = '' then return crm.res(false, 'Dê um título à atividade.'); end if;
  if p_tipo is null or p_tipo not in ('whatsapp', 'ligacao', 'email', 'tarefa', 'reuniao') then
    return crm.res(false, 'Tipo de atividade inválido.');
  end if;
  if p_vence_em is null then return crm.res(false, 'Informe quando vence.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if p_negocio is not null then
    select * into n from crm.negocio x where x.id = p_negocio and x.pessoa_id = any(pessoas.grupo(v_atual));
    if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
    if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
    v_dono := coalesce(n.dono_id, v_eu);
  else
    if not crm.pode_escrever_pessoa(v_atual) then return crm.res(false, 'Este contato não é seu.'); end if;
    v_dono := v_eu;
  end if;
  perform set_config('crm.resumo', format('Agendou "%s" para %s', btrim(p_titulo), crm.nome_pessoa(v_atual)), true);
  insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, criado_por)
  values (p_negocio, v_atual, v_dono, p_tipo, btrim(p_titulo), p_vence_em, v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('atividadeId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_concluir_atividade(p_atividade uuid, p_resultado text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; a crm.atividade%rowtype; v_res text; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into a from crm.atividade x where x.id = p_atividade for update;
  if not found or a.concluida_em is not null then return crm.res(false, 'Atividade não encontrada ou já concluída.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or a.dono_id = v_eu) then return crm.res(false, 'Esta atividade não é sua.'); end if;
  v_res := coalesce(nullif(btrim(coalesce(p_resultado, '')), ''), 'Feito');
  perform set_config('crm.resumo', left(format('Concluiu "%s" (%s) de %s', a.titulo, v_res, crm.nome_pessoa(a.pessoa_id)), 1000), true);
  update crm.atividade x set concluida_em = now(), resultado = left(v_res, 1000) where x.id = p_atividade;
  if a.negocio_id is not null then
    update crm.negocio x set ultima_interacao_em = now() where x.id = a.negocio_id;   -- coluna ignorada pelo log
  end if;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_adicionar_nota(p_pessoa uuid, p_negocio uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_atual uuid; n crm.negocio%rowtype; v_id uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if btrim(coalesce(p_texto, '')) = '' then return crm.res(false, 'Nota vazia.'); end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual) then
    return crm.res(false, 'Contato não encontrado.');
  end if;
  if p_negocio is not null then
    select * into n from crm.negocio x where x.id = p_negocio and x.pessoa_id = any(pessoas.grupo(v_atual));
    if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
    if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
  elsif not crm.pode_escrever_pessoa(v_atual) then
    return crm.res(false, 'Este contato não é seu.');
  end if;
  perform set_config('crm.resumo', format('Registrou nota em %s', crm.nome_pessoa(v_atual)), true);
  insert into crm.nota (pessoa_id, negocio_id, texto, autor_id) values (v_atual, p_negocio, btrim(p_texto), v_eu)
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('notaId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- ─── 5. RPCs de escrita: CONFIGURAÇÃO (só gestor) ────────────────────────────────────────────────────────────────────
-- Funil (id não-uuid ou inexistente = novo). Etapa removida é ARQUIVADA (FK restrict guarda o histórico); campanha
-- removida vira inativa. Reordenar/renomear em 2 passos (índices únicos de ordem/nome/ganho são checados por linha).
create function public.crm_salvar_funil(p_funil jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_prob text; v_id uuid; v_ag uuid; v_novo boolean; v_prop boolean;
        v_nome text; v_et jsonb; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor cria ou edita funis.'); end if;
  if jsonb_typeof(p_funil) is distinct from 'object' then return crm.res(false, 'Funil inválido.'); end if;
  v_prob := crm.validar_funil(p_funil);
  if v_prob is not null then return crm.res(false, v_prob); end if;
  v_ag := crm.uuid_ou_null(p_funil ->> 'agrupadorId');
  if v_ag is null or not exists (select 1 from crm.agrupador a where a.id = v_ag and a.arquivado_em is null) then
    return crm.res(false, 'Escolha o agrupador.');
  end if;
  if not exists (select 1 from crm.linha l where l.chave = p_funil ->> 'produto') then return crm.res(false, 'Produto inválido.'); end if;
  v_prop := jsonb_typeof(p_funil -> 'distribuicao') = 'array';
  if v_prop and exists (select 1 from jsonb_array_elements(p_funil -> 'distribuicao') x
                         where coalesce((x ->> 'percentual')::int, 0) > 0
                           and not exists (select 1 from crm.vendedor v where v.perfil_id = crm.uuid_ou_null(x ->> 'vendedorId'))) then
    return crm.res(false, 'Só vendedor cadastrado recebe leads.');
  end if;
  v_nome := btrim(p_funil ->> 'nome');
  v_et := p_funil -> 'etapas';
  v_id := crm.uuid_ou_null(p_funil ->> 'id');
  v_novo := v_id is null or not exists (select 1 from crm.funil f where f.id = v_id);
  if not v_novo and not exists (select 1 from crm.funil f where f.id = v_id and f.ativo) then
    return crm.res(false, 'Funil não encontrado.');
  end if;

  if v_novo then
    perform set_config('crm.resumo', format('Criou o funil %s (%s etapas)', v_nome, jsonb_array_length(v_et)), true);
    insert into crm.funil (nome, icone, projeto, agrupador_id, linha, tipo, eventos_hotmart, distribuicao_propria, criado_por)
    values (v_nome, coalesce(nullif(p_funil ->> 'icone', ''), 'kanban'), nullif(p_funil ->> 'projeto', ''), v_ag,
            p_funil ->> 'produto', coalesce(p_funil ->> 'tipo', 'manual'),
            array(select jsonb_array_elements_text(case when jsonb_typeof(p_funil -> 'eventosHotmart') = 'array' then p_funil -> 'eventosHotmart' else '[]'::jsonb end)),
            v_prop, v_eu)
    returning id into v_id;
  else
    -- etapa removida (ou que vira Ganho) com negócio aberto
    if exists (select 1 from crm.negocio n join crm.etapa_funil e on e.id = n.etapa_id
                where n.funil_id = v_id and n.status = 'aberto' and e.arquivada_em is null
                  and not exists (select 1 from crm.etapas_payload(v_et) x where x.id = e.id)) then
      return crm.res(false, 'Há negócio aberto numa etapa removida. Mova os negócios antes.');
    end if;
    if exists (select 1 from crm.negocio n join crm.etapas_payload(v_et) x on x.id = n.etapa_id
                where n.funil_id = v_id and n.status = 'aberto' and x.papel = 'fechado') then
      return crm.res(false, 'Há negócio aberto na etapa que virou Ganho. Mova os negócios antes.');
    end if;
    perform set_config('crm.resumo', format('Editou o funil %s', v_nome), true);
    update crm.funil f set nome = v_nome, icone = coalesce(nullif(p_funil ->> 'icone', ''), f.icone), projeto = nullif(p_funil ->> 'projeto', ''),
                           agrupador_id = v_ag, linha = p_funil ->> 'produto', tipo = coalesce(p_funil ->> 'tipo', f.tipo),
                           eventos_hotmart = array(select jsonb_array_elements_text(case when jsonb_typeof(p_funil -> 'eventosHotmart') = 'array' then p_funil -> 'eventosHotmart' else '[]'::jsonb end)),
                           distribuicao_propria = v_prop
     where f.id = v_id
       and (f.nome, f.icone, f.projeto, f.agrupador_id, f.linha, f.tipo, f.eventos_hotmart, f.distribuicao_propria) is distinct from
           (v_nome, coalesce(nullif(p_funil ->> 'icone', ''), f.icone), nullif(p_funil ->> 'projeto', ''), v_ag, p_funil ->> 'produto',
            coalesce(p_funil ->> 'tipo', f.tipo),
            array(select jsonb_array_elements_text(case when jsonb_typeof(p_funil -> 'eventosHotmart') = 'array' then p_funil -> 'eventosHotmart' else '[]'::jsonb end)),
            v_prop);
    -- arquiva as removidas
    update crm.etapa_funil e set arquivada_em = now()
     where e.funil_id = v_id and e.arquivada_em is null and not exists (select 1 from crm.etapas_payload(v_et) x where x.id = e.id);
    -- passo 1: tira do caminho quem muda de ordem/nome; Ganho que deixa de ser Ganho já recebe o papel novo
    update crm.etapa_funil e set ordem = e.ordem + 1000,
                                 nome = case when lower(e.nome) <> lower(x.nome) then '~' || e.id::text else e.nome end,
                                 papel = case when e.papel = 'fechado' and x.papel <> 'fechado' then x.papel else e.papel end
      from crm.etapas_payload(v_et) x
     where x.id = e.id and e.funil_id = v_id and e.arquivada_em is null
       and (e.ordem <> x.ord or lower(e.nome) <> lower(x.nome) or (e.papel = 'fechado' and x.papel <> 'fechado'));
    -- passo 2: valores finais
    update crm.etapa_funil e set ordem = x.ord, nome = x.nome, papel = x.papel, cor = x.cor, sla_atencao_min = x.sla_a,
                                 sla_critico_min = x.sla_c, campos_obrigatorios = x.campos, criterio = x.criterio
      from crm.etapas_payload(v_et) x
     where x.id = e.id and e.funil_id = v_id and e.arquivada_em is null
       and (e.ordem, e.nome, e.papel, e.cor, e.sla_atencao_min, e.sla_critico_min, e.campos_obrigatorios, e.criterio)
           is distinct from (x.ord, x.nome, x.papel, x.cor, x.sla_a, x.sla_c, x.campos, x.criterio);
  end if;
  -- etapas novas
  insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min, campos_obrigatorios, criterio)
  select v_id, x.ord, x.nome, x.papel, x.cor, x.sla_a, x.sla_c, x.campos, x.criterio
    from crm.etapas_payload(v_et) x
   where x.id is null or not exists (select 1 from crm.etapa_funil e where e.id = x.id and e.funil_id = v_id and e.arquivada_em is null)
   order by x.ord;
  -- campanhas: edita as do funil, cria as novas, inativa as removidas
  update crm.campanha c set nome = x.nome, canal = x.canal, regra = x.regra, ativa = x.ativa
    from crm.campanhas_payload(p_funil -> 'campanhas') x
   where x.id = c.id and c.funil_id = v_id and (c.nome, c.canal, c.regra, c.ativa) is distinct from (x.nome, x.canal, x.regra, x.ativa);
  insert into crm.campanha (funil_id, nome, canal, regra, ativa)
  select v_id, x.nome, x.canal, x.regra, x.ativa from crm.campanhas_payload(p_funil -> 'campanhas') x
   where x.id is null or not exists (select 1 from crm.campanha c where c.id = x.id and c.funil_id = v_id);
  update crm.campanha c set ativa = false
   where c.funil_id = v_id and c.ativa and not exists (select 1 from crm.campanhas_payload(p_funil -> 'campanhas') x where x.id = c.id);
  -- distribuição própria (a constraint trigger confere a soma no fim da transação)
  if v_prop then
    insert into crm.distribuicao (funil_id, vendedor_id, percentual, ativo)
    select v_id, crm.uuid_ou_null(x ->> 'vendedorId'), coalesce((x ->> 'percentual')::int, 0), true
      from jsonb_array_elements(p_funil -> 'distribuicao') x
     where exists (select 1 from crm.vendedor v where v.perfil_id = crm.uuid_ou_null(x ->> 'vendedorId'))
    on conflict (coalesce(funil_id, '00000000-0000-0000-0000-000000000000'::uuid), vendedor_id)
    do update set percentual = excluded.percentual, ativo = true, atualizado_em = now()
     where (crm.distribuicao.percentual, crm.distribuicao.ativo) is distinct from (excluded.percentual, true);
    update crm.distribuicao d set ativo = false, atualizado_em = now()
     where d.funil_id = v_id and d.ativo
       and not exists (select 1 from jsonb_array_elements(p_funil -> 'distribuicao') x where crm.uuid_ou_null(x ->> 'vendedorId') = d.vendedor_id);
  else
    update crm.distribuicao d set ativo = false, atualizado_em = now() where d.funil_id = v_id and d.ativo;
  end if;
  return crm.res(true, case when v_novo then 'Funil criado.' else 'Funil atualizado.' end, jsonb_build_object('funilId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_arquivar_funil(p_funil uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; f crm.funil%rowtype; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor arquiva funis.'); end if;
  select * into f from crm.funil x where x.id = p_funil and x.ativo for update;
  if not found then return crm.res(false, 'Funil não encontrado.'); end if;
  if exists (select 1 from crm.negocio n where n.funil_id = p_funil and n.status = 'aberto') then
    return crm.res(false, 'Funil com negócio aberto não pode ser arquivado.');
  end if;
  perform set_config('crm.resumo', format('Arquivou o funil %s', f.nome), true);
  update crm.funil x set ativo = false, arquivado_em = now() where x.id = p_funil;
  return crm.res(true, 'Funil arquivado.');
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_criar_agrupador(p_nome text, p_linha text default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_nome text := btrim(coalesce(p_nome, '')); v_id uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor cria agrupadores.'); end if;
  if v_nome = '' then return crm.res(false, 'Dê um nome ao agrupador.'); end if;
  if exists (select 1 from crm.agrupador a where lower(btrim(a.nome)) = lower(v_nome) and a.arquivado_em is null) then
    return crm.res(false, 'Já existe um agrupador com esse nome.');
  end if;
  if p_linha is not null and not exists (select 1 from crm.linha l where l.chave = p_linha) then
    return crm.res(false, 'Produto inválido.');
  end if;
  perform set_config('crm.resumo', format('Criou o agrupador %s', v_nome), true);
  insert into crm.agrupador (nome, linha, ordem)
  values (v_nome, p_linha, (select coalesce(max(a.ordem), 0) + 1 from crm.agrupador a))
  returning id into v_id;
  return crm.res(true, null, jsonb_build_object('agrupadorId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- "Comecei um novo projeto" = funisDoProjeto (domain/modelos.ts) a partir de crm.modelo_projeto/modelo_funil (seeds F1).
create function public.crm_criar_projeto(p_tipo text, p_nome text, p_agrupador uuid, p_linha text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_nome text := btrim(coalesce(p_nome, '')); v_chave text; pj crm.modelo_projeto%rowtype;
        m record; v_fid uuid; v_ids uuid[] := '{}'; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor cria projetos.'); end if;
  if v_nome = '' then return crm.res(false, 'Dê um nome ao projeto.'); end if;
  if p_agrupador is null or not exists (select 1 from crm.agrupador a where a.id = p_agrupador and a.arquivado_em is null) then
    return crm.res(false, 'Escolha o agrupador.');
  end if;
  select * into pj from crm.modelo_projeto x where x.tipo = p_tipo;
  if not found then return crm.res(false, 'Tipo de projeto desconhecido.'); end if;
  if not exists (select 1 from crm.linha l where l.chave = p_linha) then return crm.res(false, 'Produto inválido.'); end if;
  v_chave := btrim(left(crm.chave_projeto(v_nome), 60), '-');
  if length(v_chave) < 3 then return crm.res(false, 'Dê ao projeto um nome com pelo menos 3 letras ou números.'); end if;
  if exists (select 1 from crm.modelo_funil mf where mf.id = any(pj.funis) and length(v_nome || ' · ' || mf.nome) > 80) then
    return crm.res(false, 'Nome do projeto longo demais.');
  end if;
  if exists (select 1 from crm.funil f join crm.modelo_funil mf on f.nome = v_nome || ' · ' || mf.nome
              where f.ativo and mf.id = any(pj.funis)) then
    return crm.res(false, 'Já existe projeto com esse nome.');
  end if;
  for m in select mf.*, u.i from unnest(pj.funis) with ordinality u(mid, i) join crm.modelo_funil mf on mf.id = u.mid order by u.i loop
    perform set_config('crm.resumo', case when m.i = 1 then format('Começou o projeto %s (%s funis)', v_nome, cardinality(pj.funis))
                                          else format('Criou o funil %s', v_nome || ' · ' || m.nome) end, true);
    insert into crm.funil (nome, icone, projeto, agrupador_id, linha, tipo, eventos_hotmart, criado_por)
    values (v_nome || ' · ' || m.nome, m.icone, v_chave, p_agrupador, p_linha, m.tipo, m.eventos_hotmart, v_eu)
    returning id into v_fid;
    v_ids := v_ids || v_fid;
    insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min, campos_obrigatorios, criterio)
    select v_fid, x.ord, x.nome, x.papel, x.cor, x.sla_a, x.sla_c, x.campos, x.criterio from crm.etapas_payload(m.etapas) x order by x.ord;
    insert into crm.campanha (funil_id, nome, canal, regra, ativa)
    select v_fid, replace(x.nome, '{chave}', v_chave), x.canal, replace(x.regra, '{chave}', v_chave), x.ativa
      from crm.campanhas_payload(m.campanhas) x;
  end loop;
  return crm.res(true, format('%s funis criados para %s.', cardinality(v_ids), v_nome), jsonb_build_object('funilIds', to_jsonb(v_ids)));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- Motivo de perda: de fábrica só muda nota e ativo (o trigger da F1 também trava). p_motivo = MotivoPerdaConfig.
create function public.crm_salvar_motivo_perda(p_motivo jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_key text := p_motivo ->> 'key'; v_label text := btrim(coalesce(p_motivo ->> 'label', ''));
        m crm.motivo_perda%rowtype; v_existe boolean; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor edita motivos de perda.'); end if;
  if v_label = '' or coalesce(v_key, '') = '' then return crm.res(false, 'Dê um nome ao motivo.'); end if;
  select * into m from crm.motivo_perda x where x.chave = v_key for update;
  v_existe := found;
  if v_existe and m.sistema then
    perform set_config('crm.resumo', format('Editou o motivo de perda "%s"', m.rotulo), true);
    update crm.motivo_perda x set nota = nullif(btrim(coalesce(p_motivo ->> 'nota', '')), ''),
                                  ativo = coalesce((p_motivo ->> 'ativo')::boolean, x.ativo)
     where x.chave = v_key;
    return crm.res(true, 'Motivo atualizado.');
  end if;
  if not v_existe and exists (select 1 from crm.motivo_perda x where lower(btrim(x.rotulo)) = lower(v_label)) then
    return crm.res(false, 'Já existe um motivo com esse nome.');
  end if;
  if not v_existe and v_key !~ '^[a-z0-9_]{3,40}$' then return crm.res(false, 'Chave do motivo inválida.'); end if;
  perform set_config('crm.resumo', format('%s o motivo de perda "%s"', case when v_existe then 'Editou' else 'Criou' end, v_label), true);
  insert into crm.motivo_perda (chave, rotulo, reativa, bloqueia, alerta_gestor, nota, ativo, ordem)
  values (v_key, v_label, coalesce((p_motivo ->> 'reativa')::boolean, false), coalesce((p_motivo ->> 'bloqueia')::boolean, false),
          coalesce((p_motivo ->> 'alertaGestor')::boolean, false), nullif(btrim(coalesce(p_motivo ->> 'nota', '')), ''),
          coalesce((p_motivo ->> 'ativo')::boolean, true), (select coalesce(max(x.ordem), 0) + 1 from crm.motivo_perda x))
  on conflict (chave) do update set rotulo = excluded.rotulo, reativa = excluded.reativa, bloqueia = excluded.bloqueia,
                                    alerta_gestor = excluded.alerta_gestor, nota = excluded.nota, ativo = excluded.ativo;
  return crm.res(true, case when v_existe then 'Motivo atualizado.' else 'Motivo criado.' end);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- Distribuição GERAL. p_percentuais = { vendedorId: { percentual, ativo } } (Record do port). "ativo" = linha ativa na
-- distribuição geral (não inativa o vendedor). Soma dos ativos = 100 (validado aqui e pela constraint trigger).
create function public.crm_salvar_distribuicao(p_percentuais jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; r record; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor define a distribuição.'); end if;
  if jsonb_typeof(p_percentuais) is distinct from 'object' then return crm.res(false, 'Distribuição inválida.'); end if;
  if exists (select 1 from jsonb_each(p_percentuais) x
              where coalesce((x.value ->> 'percentual')::int, 0) > 0
                and not exists (select 1 from crm.vendedor v where v.perfil_id = crm.uuid_ou_null(x.key))) then
    return crm.res(false, 'Só vendedor cadastrado recebe leads.');
  end if;
  if exists (select 1 from jsonb_each(p_percentuais) x where (x.value ->> 'percentual')::int not between 0 and 100) then
    return crm.res(false, 'Percentual entre 0 e 100.');
  end if;
  for r in
    with x as (
      select v.perfil_id vendedor_id, coalesce(d.percentual, 0) pct_antes, coalesce(d.ativo, false) ativo_antes, d.id is not null tem,
             coalesce((p_percentuais -> v.perfil_id::text ->> 'percentual')::int, d.percentual, 0) pct,
             coalesce((p_percentuais -> v.perfil_id::text ->> 'ativo')::boolean, d.ativo, v.ativo) ativo
        from crm.vendedor v
        left join crm.distribuicao d on d.funil_id is null and d.vendedor_id = v.perfil_id)
    select x.*, sum(x.pct) filter (where x.ativo and crm.vendedor_ativo(x.vendedor_id)) over () soma from x
  loop
    if coalesce(r.soma, 0) <> 100 then return crm.res(false, 'A soma dos percentuais dos ativos precisa dar 100%.'); end if;
    continue when r.tem and (r.pct, r.ativo) is not distinct from (r.pct_antes, r.ativo_antes);
    perform set_config('crm.resumo', format('Distribuição de leads: %s %s%s%% → %s%s%%', crm.nome_perfil(r.vendedor_id),
                       case when r.ativo_antes then '' else 'inativo · ' end, r.pct_antes,
                       case when r.ativo then '' else 'inativo · ' end, r.pct), true);
    insert into crm.distribuicao (funil_id, vendedor_id, percentual, ativo) values (null, r.vendedor_id, r.pct, r.ativo)
    on conflict (coalesce(funil_id, '00000000-0000-0000-0000-000000000000'::uuid), vendedor_id)
    do update set percentual = excluded.percentual, ativo = excluded.ativo, atualizado_em = now();
  end loop;
  return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- Produto da Hotmart (fin.produtos) ↔ comercial. Desvincular tira "vigente" das ofertas dele.
create function public.crm_vincular_produto(p_produto jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_pid text := p_produto ->> 'produtoId'; v_no boolean; v_nome text; v_esc text;
        v_linha text; v_ag uuid; v_antes boolean; v_hot text; o record; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor vincula produtos.'); end if;
  select p.nome into v_hot from fin.produtos p where p.produto_id = v_pid;
  if not found then
    return crm.res(false, 'Produto não veio da Hotmart. Crie o produto na Hotmart; ele aparece aqui depois da sincronização.');
  end if;
  v_no := coalesce((p_produto ->> 'noComercial')::boolean, false);
  v_nome := nullif(btrim(coalesce(p_produto ->> 'nomeComercial', '')), '');
  v_esc := nullif(p_produto ->> 'escada', '');
  if v_no and (v_nome is null or v_esc is null) then
    return crm.res(false, 'Para vincular, dê o nome comercial e a escada (A ou B).');
  end if;
  v_linha := nullif(p_produto ->> 'produtoKey', '');
  if v_linha is not null and not exists (select 1 from crm.linha l where l.chave = v_linha) then return crm.res(false, 'Produto inválido.'); end if;
  v_ag := crm.uuid_ou_null(p_produto ->> 'agrupadorId');
  if nullif(p_produto ->> 'agrupadorId', '') is not null
     and (v_ag is null or not exists (select 1 from crm.agrupador a where a.id = v_ag and a.arquivado_em is null)) then
    return crm.res(false, 'Agrupador não encontrado.');
  end if;
  v_antes := coalesce((select pc.no_comercial from crm.produto_comercial pc where pc.produto_id = v_pid), false);
  perform set_config('crm.resumo', format('%s o produto %s', case when v_no then case when v_antes then 'Editou' else 'Vinculou ao comercial' end
                                                                 else 'Desvinculou' end, coalesce(v_hot, v_pid)), true);
  insert into crm.produto_comercial (produto_id, no_comercial, nome_comercial, linha, escada, agrupador_id, vinculado_por, vinculado_em)
  values (v_pid, v_no, v_nome, v_linha, v_esc, v_ag, case when v_no then v_eu end, case when v_no then now() end)
  on conflict (produto_id) do update
     set no_comercial = excluded.no_comercial,
         nome_comercial = coalesce(excluded.nome_comercial, crm.produto_comercial.nome_comercial),
         linha = excluded.linha, escada = coalesce(excluded.escada, crm.produto_comercial.escada), agrupador_id = excluded.agrupador_id,
         vinculado_por = case when excluded.no_comercial and not crm.produto_comercial.no_comercial then excluded.vinculado_por
                              else crm.produto_comercial.vinculado_por end,
         vinculado_em  = case when excluded.no_comercial and not crm.produto_comercial.no_comercial then excluded.vinculado_em
                              else crm.produto_comercial.vinculado_em end
   where (crm.produto_comercial.no_comercial, crm.produto_comercial.nome_comercial, crm.produto_comercial.linha,
          crm.produto_comercial.escada, crm.produto_comercial.agrupador_id)
         is distinct from (excluded.no_comercial, coalesce(excluded.nome_comercial, crm.produto_comercial.nome_comercial), excluded.linha,
                           coalesce(excluded.escada, crm.produto_comercial.escada), excluded.agrupador_id);
  if not v_no then
    for o in select oc.oferta_codigo from crm.oferta_comercial oc join fin.ofertas f on f.oferta_codigo = oc.oferta_codigo
              where f.produto_id = v_pid and oc.vigente for update of oc loop
      perform set_config('crm.resumo', format('Oferta %s deixou de ser vigente (produto desvinculado)', o.oferta_codigo), true);
      update crm.oferta_comercial x set vigente = false, atualizado_por = v_eu, atualizado_em = now() where x.oferta_codigo = o.oferta_codigo;
    end loop;
  end if;
  return crm.res(true, case when v_no then 'Produto vinculado ao comercial.' else 'Produto desvinculado.' end);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_salvar_oferta(p_oferta jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_cod text := p_oferta ->> 'codigo'; v_prod text; v_vig boolean;
        v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor define a oferta vigente.'); end if;
  select o.produto_id into v_prod from fin.ofertas o where o.oferta_codigo = v_cod;
  if not found then return crm.res(false, 'Oferta não está no catálogo da Hotmart.'); end if;
  v_vig := coalesce((p_oferta ->> 'vigente')::boolean, false);
  if v_vig and not exists (select 1 from crm.produto_comercial pc where pc.produto_id = v_prod and pc.no_comercial) then
    return crm.res(false, 'Vincule o produto ao comercial antes de marcar oferta vigente.');
  end if;
  perform set_config('crm.resumo', format('Editou a oferta %s%s', v_cod, case when v_vig then ' (vigente)' else '' end), true);
  insert into crm.oferta_comercial (oferta_codigo, vigente, condicao, valida_ate, uso, atualizado_por, atualizado_em)
  values (v_cod, v_vig, nullif(btrim(coalesce(p_oferta ->> 'condicao', '')), ''), nullif(p_oferta ->> 'validaAte', '')::date,
          nullif(btrim(coalesce(p_oferta ->> 'uso', '')), ''), v_eu, now())
  on conflict (oferta_codigo) do update
     set vigente = excluded.vigente, condicao = excluded.condicao, valida_ate = excluded.valida_ate, uso = excluded.uso,
         atualizado_por = excluded.atualizado_por, atualizado_em = excluded.atualizado_em
   where (crm.oferta_comercial.vigente, crm.oferta_comercial.condicao, crm.oferta_comercial.valida_ate, crm.oferta_comercial.uso)
         is distinct from (excluded.vigente, excluded.condicao, excluded.valida_ate, excluded.uso);
  return crm.res(true, 'Oferta salva.');
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- ─── 6. RPCs de escrita: DASHBOARD, PAINEL, PREFERÊNCIAS, NOTIFICAÇÕES (do próprio; gestor pode painel/dashboard) ─────
create function public.crm_salvar_dashboard(p_dashboard jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_id uuid := crm.uuid_ou_null(p_dashboard ->> 'id'); d crm.dashboard%rowtype;
        v_nome text := btrim(coalesce(p_dashboard ->> 'nome', '')); v_w jsonb; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if v_nome = '' then return crm.res(false, 'Dê um nome ao dashboard.'); end if;
  v_w := case when jsonb_typeof(p_dashboard -> 'widgets') = 'array' then p_dashboard -> 'widgets' else '[]'::jsonb end;
  if jsonb_array_length(v_w) > 40 then return crm.res(false, 'Dashboard com widgets demais (máximo 40).'); end if;
  if v_id is not null then
    select * into d from crm.dashboard x where x.id = v_id and x.arquivado_em is null for update;
  end if;
  if d.id is not null then
    if not (d.dono_id = v_eu or coalesce(crm.eh_gestor(), false)) then
      return crm.res(false, 'Só o dono e o gestor editam este dashboard.');
    end if;
    perform set_config('crm.resumo', format('Editou o dashboard %s', v_nome), true);
    update crm.dashboard x set nome = v_nome, descricao = nullif(btrim(coalesce(p_dashboard ->> 'descricao', '')), ''),
                               compartilhado = coalesce((p_dashboard ->> 'compartilhado')::boolean, false), widgets = v_w,
                               atualizado_em = now()
     where x.id = d.id;
    return crm.res(true, 'Dashboard salvo.', jsonb_build_object('dashboardId', d.id));
  end if;
  perform set_config('crm.resumo', format('Criou o dashboard %s', v_nome), true);
  insert into crm.dashboard (nome, descricao, dono_id, compartilhado, widgets)
  values (v_nome, nullif(btrim(coalesce(p_dashboard ->> 'descricao', '')), ''), v_eu,
          coalesce((p_dashboard ->> 'compartilhado')::boolean, false), v_w)
  returning id into v_id;
  return crm.res(true, 'Dashboard criado.', jsonb_build_object('dashboardId', v_id));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- "Excluir" na tela = arquivar (nada se apaga).
create function public.crm_arquivar_dashboard(p_dashboard uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; d crm.dashboard%rowtype; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  select * into d from crm.dashboard x where x.id = p_dashboard and x.arquivado_em is null for update;
  if not found then return crm.res(false, 'Dashboard não encontrado.'); end if;
  if not (d.dono_id = v_eu or coalesce(crm.eh_gestor(), false)) then return crm.res(false, 'Só o dono e o gestor excluem.'); end if;
  perform set_config('crm.resumo', format('Excluiu o dashboard %s', d.nome), true);
  update crm.dashboard x set arquivado_em = now(), atualizado_em = now() where x.id = p_dashboard;
  return crm.res(true, 'Dashboard excluído.');
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

create function public.crm_salvar_painel(p_perfil uuid, p_widgets jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_w jsonb; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_perfil is distinct from v_eu and not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Você só edita o seu painel.'); end if;
  if p_perfil is distinct from v_eu and not exists (select 1 from crm.vendedor v where v.perfil_id = p_perfil) then
    return crm.res(false, 'Painel só de quem é do Comercial.');
  end if;
  v_w := case when jsonb_typeof(p_widgets) = 'array' then p_widgets else '[]'::jsonb end;
  if jsonb_array_length(v_w) > 40 then return crm.res(false, 'Painel com widgets demais (máximo 40).'); end if;
  perform set_config('crm.resumo', format('Personalizou o painel de %s (%s widgets)', crm.nome_perfil(p_perfil), jsonb_array_length(v_w)), true);
  insert into crm.painel (perfil_id, widgets) values (p_perfil, v_w)
  on conflict (perfil_id) do update set widgets = excluded.widgets, atualizado_em = now()
   where crm.painel.widgets is distinct from excluded.widgets;
  return crm.res(true, 'Painel salvo.');
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- p_preferencias = PreferenciasNotificacao (vendedorId tem de ser quem está na sessão).
create function public.crm_salvar_preferencias(p_preferencias jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_g jsonb; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if crm.uuid_ou_null(p_preferencias ->> 'vendedorId') is distinct from v_eu then
    return crm.res(false, 'Você só edita as suas notificações.');
  end if;
  v_g := case when jsonb_typeof(p_preferencias -> 'gatilhos') = 'object' then p_preferencias -> 'gatilhos' else '{}'::jsonb end;
  perform set_config('crm.resumo', 'Salvou as preferências de notificação', true);
  insert into crm.preferencias_notificacao (perfil_id, desktop, gatilhos, silencio_inicio, silencio_fim)
  values (v_eu, coalesce((p_preferencias ->> 'desktop')::boolean, false), v_g,
          nullif(p_preferencias ->> 'silencioInicio', '')::time, nullif(p_preferencias ->> 'silencioFim', '')::time)
  on conflict (perfil_id) do update
     set desktop = excluded.desktop, gatilhos = excluded.gatilhos, silencio_inicio = excluded.silencio_inicio,
         silencio_fim = excluded.silencio_fim, atualizado_em = now()
   where (crm.preferencias_notificacao.desktop, crm.preferencias_notificacao.gatilhos, crm.preferencias_notificacao.silencio_inicio,
          crm.preferencias_notificacao.silencio_fim)
         is distinct from (excluded.desktop, excluded.gatilhos, excluded.silencio_inicio, excluded.silencio_fim);
  return crm.res(true, 'Preferências salvas.');
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$$;

-- Sem ids = todas as minhas não lidas. Notificação não vai para o log (é derivada).
create function public.crm_marcar_notificacoes_lidas(p_ids text[] default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_n int;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  update crm.notificacao x set lida_em = now()
   where x.perfil_id = v_eu and x.lida_em is null and (p_ids is null or x.id::text = any(p_ids));
  get diagnostics v_n = row_count;
  return crm.res(true, null, jsonb_build_object('marcadas', v_n));
end
$$;

-- ─── 7. Grants e conferência ─────────────────────────────────────────────────────────────────────────────────────────
do $grants$
declare f regprocedure;
begin
  -- helpers internos: ninguém executa direto (as RPCs são definer)
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'crm'::regnamespace
              and p.proname in ('res','guarda_escrita','erro_dados','uuid_ou_null','nome_pessoa','nome_perfil','vendedor_ativo',
                                'pode_escrever_pessoa','garantir_pc','campos_faltando','escolher_dono','etapas_payload',
                                'campanhas_payload','validar_funil','chave_projeto','tg_negocio_regras','confere_distribuicao',
                                'tg_distribuicao_soma','tg_negocio_notifica','notificar_prazos') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  for f in select p.oid::regprocedure from pg_proc p
            where p.pronamespace = 'public'::regnamespace
              and p.proname in ('crm_mover_etapa','crm_salvar_campos','crm_marcar_perdido','crm_transferir_dono',
                                'crm_atribuir_contato','crm_criar_negocio','crm_criar_atividade','crm_concluir_atividade',
                                'crm_adicionar_nota','crm_salvar_funil','crm_arquivar_funil','crm_criar_agrupador',
                                'crm_criar_projeto','crm_salvar_motivo_perda','crm_salvar_distribuicao','crm_vincular_produto',
                                'crm_salvar_oferta','crm_salvar_dashboard','crm_arquivar_dashboard','crm_salvar_painel',
                                'crm_salvar_preferencias','crm_marcar_notificacoes_lidas') loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end
$grants$;

do $confere$
declare v_aberto text; v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'crm\_%' and p.prosecdef
     and p.proname in ('crm_mover_etapa','crm_salvar_campos','crm_marcar_perdido','crm_transferir_dono','crm_atribuir_contato',
                       'crm_criar_negocio','crm_criar_atividade','crm_concluir_atividade','crm_adicionar_nota','crm_salvar_funil',
                       'crm_arquivar_funil','crm_criar_agrupador','crm_criar_projeto','crm_salvar_motivo_perda',
                       'crm_salvar_distribuicao','crm_vincular_produto','crm_salvar_oferta','crm_salvar_dashboard',
                       'crm_arquivar_dashboard','crm_salvar_painel','crm_salvar_preferencias','crm_marcar_notificacoes_lidas');
  if v_n <> 22 then raise exception '20261005t: esperava 22 RPCs de escrita definer, achou %', v_n; end if;
  select string_agg(p.oid::regprocedure::text, ', ') into v_aberto
    from pg_proc p
   where p.pronamespace in ('public'::regnamespace, 'crm'::regnamespace)
     and (p.proname like 'crm\_%' or p.pronamespace = 'crm'::regnamespace)
     and (has_function_privilege('anon', p.oid, 'execute')
          or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  if v_aberto is not null then raise exception '20261005t: função executável por anon/PUBLIC: %', v_aberto; end if;
  select string_agg(table_name || ':' || privilege_type, ', ') into v_aberto
    from information_schema.role_table_grants
   where table_schema = 'crm' and (grantee in ('anon', 'PUBLIC') or (grantee = 'authenticated' and privilege_type <> 'SELECT'));
  if v_aberto is not null then raise exception '20261005t: grant indevido em crm: %', v_aberto; end if;
  if coalesce((select c.escrita_ligada from crm.config c), true) then raise exception '20261005t: escrita_ligada não pode ser ligada aqui'; end if;
end
$confere$;

-- ═══ LIGAR (o Arthur, depois do ok, em chamada separada; desliga do mesmo jeito com false) ═══════════════════════════
-- update crm.config set escrita_ligada = true;
-- Prazos (opcional, quando quiser os avisos de prazo/atividade):
--   update crm.config set notificacao_cron_ligado = true;
--   select cron.schedule('crm-notificar-prazos', '*/5 * * * *', 'select crm.notificar_prazos()');

-- ═══ REVERSÃO (numa transação; dado escrito pela F2 fica nas tabelas da F1 e no log) ════════════════════════════════
-- update crm.config set escrita_ligada = false;          -- desliga em ~10 s, sem deploy (preferir isto)
-- select cron.unschedule('crm-notificar-prazos');        -- se tiver sido agendado
-- drop function public.crm_mover_etapa(uuid,uuid), public.crm_salvar_campos(uuid,jsonb), public.crm_marcar_perdido(uuid,text,text),
--   public.crm_transferir_dono(uuid,uuid,text), public.crm_atribuir_contato(uuid,uuid,text), public.crm_criar_negocio(uuid,uuid,uuid),
--   public.crm_criar_atividade(uuid,uuid,text,text,timestamptz), public.crm_concluir_atividade(uuid,text),
--   public.crm_adicionar_nota(uuid,uuid,text), public.crm_salvar_funil(jsonb), public.crm_arquivar_funil(uuid),
--   public.crm_criar_agrupador(text,text), public.crm_criar_projeto(text,text,uuid,text), public.crm_salvar_motivo_perda(jsonb),
--   public.crm_salvar_distribuicao(jsonb), public.crm_vincular_produto(jsonb), public.crm_salvar_oferta(jsonb),
--   public.crm_salvar_dashboard(jsonb), public.crm_arquivar_dashboard(uuid), public.crm_salvar_painel(uuid,jsonb),
--   public.crm_salvar_preferencias(jsonb), public.crm_marcar_notificacoes_lidas(text[]);
-- drop trigger negocio_regras on crm.negocio; drop trigger negocio_notifica_ins on crm.negocio;
-- drop trigger negocio_notifica_upd on crm.negocio; drop trigger distribuicao_soma on crm.distribuicao;
-- drop trigger funil_distribuicao_soma on crm.funil;
-- drop function crm.notificar_prazos(), crm.tg_negocio_notifica(), crm.tg_distribuicao_soma(), crm.confere_distribuicao(uuid),
--   crm.tg_negocio_regras(), crm.chave_projeto(text), crm.validar_funil(jsonb), crm.campanhas_payload(jsonb),
--   crm.etapas_payload(jsonb), crm.escolher_dono(uuid,uuid), crm.campos_faltando(jsonb,uuid,uuid), crm.garantir_pc(uuid),
--   crm.pode_escrever_pessoa(uuid), crm.vendedor_ativo(uuid), crm.nome_perfil(uuid), crm.nome_pessoa(uuid),
--   crm.uuid_ou_null(text), crm.erro_dados(text,text,text), crm.guarda_escrita(), crm.res(boolean,text,jsonb);

-- ═══ FIM DO CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════

-- ─── Fixtures: perfis reais (só ids em temp), pessoas fictícias (teste=true), produto/oferta reais do catálogo ─────
create temp table _v (k text primary key, u uuid, t text) on commit drop;
create function pg_temp.v(p text) returns uuid language sql as $$ select u from pg_temp._v where k = p $$;
create function pg_temp.t(p text) returns text language sql as $$ select t from pg_temp._v where k = p $$;
-- Chama SQL como authenticated + JWT do perfil (a tela). Erro vira {"erro": …} (e desfaz só aquela chamada).
create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
create function pg_temp.r(p_quem text, p_call text) returns jsonb language sql as $$
  select pg_temp.chamar(pg_temp.v(p_quem), 'select ' || p_call) $$;
create function pg_temp.m(j jsonb) returns text language sql as $$ select coalesce(j ->> 'msg', j ->> 'erro', j::text) $$;
create function pg_temp.loglast() returns bigint language sql as $$ select coalesce(max(id), 0) from crm.log $$;

insert into _v (k, u) select 'gestor', p.id from public.perfis p
 where p.cargo = 'admin' and p.status = 'ativo' and p.nome ilike 'jonathan%' order by p.criado_em limit 1;
insert into _v (k, u) select 'mp', v.perfil_id from crm.vendedor v where v.sigla = 'mp';
insert into _v (k, u) select 'ro', v.perfil_id from crm.vendedor v where v.sigla = 'ro';
insert into _v (k, u) select 'vis', p.id from public.perfis p
 where p.status = 'ativo' and p.cargo not in ('dev', 'admin', 'gestor')
   and not exists (select 1 from crm.vendedor v where v.perfil_id = p.id) order by p.criado_em limit 1;
with x as (insert into pessoas.pessoas (nome, teste) values ('Ensaio F2 Um', true), ('Ensaio F2 Dois', true),
                                                         ('Ensaio F2 Tres', true), ('Ensaio F2 Quatro', true) returning id, nome)
insert into _v (k, u) select case nome when 'Ensaio F2 Um' then 'p1' when 'Ensaio F2 Dois' then 'p2'
                                       when 'Ensaio F2 Tres' then 'p3' else 'p4' end, id from x;
insert into _v (k, t) select 'prod', p.produto_id from fin.produtos p
 where exists (select 1 from fin.ofertas o where o.produto_id = p.produto_id)
   and not exists (select 1 from crm.produto_comercial pc where pc.produto_id = p.produto_id) order by p.produto_id limit 1;
insert into _v (k, t) select 'oferta', o.oferta_codigo from fin.ofertas o where o.produto_id = pg_temp.t('prod') order by o.oferta_codigo limit 1;
insert into _v (k, u) values ('log0', null);
update _v set t = pg_temp.loglast()::text where k = 'log0';

do $p0$ begin
  perform pg_temp.ok('0.perfis', pg_temp.v('gestor') is not null and pg_temp.v('mp') is not null and pg_temp.v('ro') is not null
                     and pg_temp.v('vis') is not null and pg_temp.t('oferta') is not null, 'gestor (admin real), mp, ro, visualizador, produto+oferta reais');
  perform pg_temp.ok('0.papeis', (pg_temp.r('gestor', 'to_jsonb(crm.eh_gestor())'))::text = 'true'
                     and (pg_temp.r('mp', 'to_jsonb(crm.eh_vendedor())'))::text = 'true'
                     and (pg_temp.r('vis', 'to_jsonb(crm.eh_comercial())'))::text = 'false', 'gestor/vendedor/visualizador pelo JWT');
end $p0$;

-- ─── 1. Permissões: anon sem execute; authenticated com; helpers internos fechados ──────────────────────────────────
do $p1$
declare v_n int; v_anon int; v_auth int; v_int int;
begin
  select count(*), count(*) filter (where has_function_privilege('anon', p.oid, 'execute')),
         count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))
    into v_n, v_anon, v_auth
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
     and p.proname in ('crm_mover_etapa','crm_salvar_campos','crm_marcar_perdido','crm_transferir_dono','crm_atribuir_contato',
                       'crm_criar_negocio','crm_criar_atividade','crm_concluir_atividade','crm_adicionar_nota','crm_salvar_funil',
                       'crm_arquivar_funil','crm_criar_agrupador','crm_criar_projeto','crm_salvar_motivo_perda',
                       'crm_salvar_distribuicao','crm_vincular_produto','crm_salvar_oferta','crm_salvar_dashboard',
                       'crm_arquivar_dashboard','crm_salvar_painel','crm_salvar_preferencias','crm_marcar_notificacoes_lidas');
  perform pg_temp.ok('1.anon_sem_execute', v_n = 22 and v_anon = 0 and v_auth = 22, format('%s RPCs definer; anon %s; authenticated %s', v_n, v_anon, v_auth));
  select count(*) into v_int from pg_proc p where p.pronamespace = 'crm'::regnamespace
     and p.proname in ('guarda_escrita','garantir_pc','escolher_dono','notificar_prazos','validar_funil','pode_escrever_pessoa')
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
  perform pg_temp.ok('1.helpers_fechados', v_int = 0, format('%s helpers internos executáveis por authenticated/anon', v_int));
end $p1$;
-- anon de verdade: role anon chamando a RPC → permission denied
do $p1b$
declare v text;
begin
  begin
    execute 'set local role anon';
    perform public.crm_criar_agrupador('x', null);
    v := 'executou';
  exception when insufficient_privilege then v := 'negado';
  end;
  execute 'reset role';
  perform pg_temp.ok('1.anon_negado', v = 'negado', 'anon → ' || v);
end $p1b$;

-- ─── 2. Kill-switch: com escrita_ligada=false TODAS recusam com a mensagem de manutenção ────────────────────────────
do $p2$
declare c text; v_ok int := 0; v_tot int := 0; v_ruim text;
begin
  foreach c in array array[
    'public.crm_mover_etapa(gen_random_uuid(), gen_random_uuid())', 'public.crm_salvar_campos(gen_random_uuid(), ''{}'')',
    'public.crm_marcar_perdido(gen_random_uuid(), ''x'', '''')', 'public.crm_transferir_dono(gen_random_uuid(), gen_random_uuid(), ''m'')',
    'public.crm_atribuir_contato(gen_random_uuid(), gen_random_uuid(), ''m'')', 'public.crm_criar_negocio(gen_random_uuid(), gen_random_uuid(), null)',
    'public.crm_criar_atividade(null, gen_random_uuid(), ''tarefa'', ''t'', now())', 'public.crm_concluir_atividade(gen_random_uuid(), ''r'')',
    'public.crm_adicionar_nota(gen_random_uuid(), null, ''t'')', 'public.crm_salvar_funil(''{}'')', 'public.crm_arquivar_funil(gen_random_uuid())',
    'public.crm_criar_agrupador(''x'', null)', 'public.crm_criar_projeto(''seminario'', ''x'', gen_random_uuid(), ''ht'')',
    'public.crm_salvar_motivo_perda(''{}'')', 'public.crm_salvar_distribuicao(''{}'')', 'public.crm_vincular_produto(''{}'')',
    'public.crm_salvar_oferta(''{}'')', 'public.crm_salvar_dashboard(''{}'')', 'public.crm_arquivar_dashboard(gen_random_uuid())',
    'public.crm_salvar_painel(gen_random_uuid(), ''[]'')', 'public.crm_salvar_preferencias(''{}'')', 'public.crm_marcar_notificacoes_lidas(null)'] loop
    v_tot := v_tot + 1;
    if pg_temp.m(pg_temp.r('gestor', c)) = 'CRM em manutenção: escrita desligada.' then v_ok := v_ok + 1;
    else v_ruim := concat_ws('; ', v_ruim, c || ' → ' || pg_temp.m(pg_temp.r('gestor', c))); end if;
  end loop;
  perform pg_temp.ok('2.kill_switch', v_ok = 22 and v_tot = 22, format('%s/%s recusaram com manutenção %s', v_ok, v_tot, coalesce(v_ruim, '')));
  perform pg_temp.ok('2.kill_switch_nada_gravou', pg_temp.loglast()::text = pg_temp.t('log0'), 'nenhuma linha nova no log');
end $p2$;

-- liga a escrita SÓ dentro desta transação (rollback no fim)
update crm.config set escrita_ligada = true;

-- ─── 3. Papel: visualizador e vendedor em RPC de gestor ─────────────────────────────────────────────────────────────
do $p3$ begin
  perform pg_temp.ok('3.visualizador', pg_temp.m(pg_temp.r('vis', 'public.crm_criar_agrupador(''Ensaio F2 Ag'', ''ht'')')) = 'Sem acesso ao Comercial.', 'visualizador → Sem acesso');
  perform pg_temp.ok('3.vendedor_config', pg_temp.m(pg_temp.r('mp', 'public.crm_criar_agrupador(''Ensaio F2 Ag'', ''ht'')')) = 'Só o gestor cria agrupadores.', 'vendedor não cria agrupador');
end $p3$;

-- ─── 4. Configuração pelo gestor: agrupador, distribuição, funil, projeto ──────────────────────────────────────────
do $p4$
declare j jsonb; v_l bigint; v_funil jsonb;
begin
  j := pg_temp.r('gestor', 'public.crm_criar_agrupador(''Ensaio F2 Agrupador'', ''ht'')');
  perform pg_temp.ok('4.agrupador', (j ->> 'ok')::boolean and j ? 'agrupadorId', pg_temp.m(j));
  insert into pg_temp._v (k, u) values ('ag', (j ->> 'agrupadorId')::uuid);
  perform pg_temp.ok('4.agrupador_dup', pg_temp.m(pg_temp.r('gestor', 'public.crm_criar_agrupador('' ensaio f2 agrupador '', null)')) = 'Já existe um agrupador com esse nome.', 'nome repetido');

  j := pg_temp.r('gestor', format('public.crm_salvar_distribuicao(%L)', jsonb_build_object(pg_temp.v('mp'), jsonb_build_object('percentual', 70, 'ativo', true),
                                                                                         pg_temp.v('ro'), jsonb_build_object('percentual', 20, 'ativo', true))));
  perform pg_temp.ok('4.dist_soma_90', pg_temp.m(j) = 'A soma dos percentuais dos ativos precisa dar 100%.', pg_temp.m(j));
  v_l := pg_temp.loglast();
  j := pg_temp.r('gestor', format('public.crm_salvar_distribuicao(%L)', jsonb_build_object(pg_temp.v('mp'), jsonb_build_object('percentual', 70, 'ativo', true),
                                                                                         pg_temp.v('ro'), jsonb_build_object('percentual', 30, 'ativo', true))));
  perform pg_temp.ok('4.dist_ok', (j ->> 'ok')::boolean and (select count(*) from crm.distribuicao where funil_id is null and ativo) = 2
                     and (select count(*) from crm.log where id > v_l and entidade = 'distribuicao' and resumo like 'Distribuição de leads:%') = 2,
                     pg_temp.m(j) || ' · 2 linhas, 2 logs');
  -- soma 100 também pela constraint trigger (deferred): forçar 90 direto e checar na hora
  begin
    update crm.distribuicao set percentual = 20 where vendedor_id = pg_temp.v('ro') and funil_id is null;
    set constraints crm.distribuicao_soma immediate;
    perform pg_temp.ok('4.dist_trigger', false, 'aceitou soma 90');
  exception when check_violation then
    perform pg_temp.ok('4.dist_trigger', sqlerrm = 'A soma dos percentuais dos ativos precisa dar 100%.', 'constraint trigger: ' || sqlerrm);
  end;
  set constraints all deferred;

  v_funil := jsonb_build_object('id', '', 'nome', 'Ensaio F2 Funil', 'icone', 'kanban', 'projeto', null, 'agrupadorId', pg_temp.v('ag'),
    'produto', 'ht', 'tipo', 'manual', 'eventosHotmart', '[]'::jsonb, 'distribuicao', null, 'ativo', true, 'criadoEm', '',
    'etapas', jsonb_build_array(
      jsonb_build_object('id', 'e-1', 'nome', 'Entrada', 'papel', 'primeiro_contato', 'cor', 'info', 'slaAtencaoMin', 5, 'slaCriticoMin', 15, 'camposObrigatorios', '[]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', 'e-2', 'nome', 'Qualificar', 'papel', 'qualificar', 'cor', 'cyan', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '["perfil_profissional","atua_com_holding"]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', 'e-3', 'nome', 'Negociar', 'papel', 'negociar', 'cor', 'accent', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '[]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', 'e-4', 'nome', 'Ganho', 'papel', 'fechado', 'cor', 'green', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '[]'::jsonb, 'criterio', '')),
    'campanhas', jsonb_build_array(jsonb_build_object('id', 'c-1', 'nome', 'Captação', 'canal', 'utm', 'regra', 'utm_campaign = ensaio', 'ativa', true, 'criadoEm', '')));
  perform pg_temp.ok('4.funil_1_etapa', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_funil(%L)', jsonb_set(v_funil, '{etapas}', jsonb_build_array(v_funil -> 'etapas' -> 3)))))
                     = 'O funil precisa de pelo menos 2 etapas.', 'validarFunil no banco');
  perform pg_temp.ok('4.funil_ganho_meio', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_funil(%L)', jsonb_set(v_funil, '{etapas}',
                       jsonb_build_array(v_funil -> 'etapas' -> 0, v_funil -> 'etapas' -> 3, v_funil -> 'etapas' -> 1)))))
                     = 'A etapa de Ganho precisa ser a última.', 'ganho fora do fim');
  perform pg_temp.ok('4.funil_vendedor', pg_temp.m(pg_temp.r('mp', format('public.crm_salvar_funil(%L)', v_funil))) = 'Só o gestor cria ou edita funis.', 'vendedor');
  j := pg_temp.r('gestor', format('public.crm_salvar_funil(%L)', v_funil));
  perform pg_temp.ok('4.funil_criado', pg_temp.m(j) = 'Funil criado.' and (select count(*) from crm.etapa_funil where funil_id = (j ->> 'funilId')::uuid) = 4
                     and (select count(*) from crm.campanha where funil_id = (j ->> 'funilId')::uuid) = 1, pg_temp.m(j) || ' · 4 etapas, 1 campanha');
  insert into pg_temp._v (k, u) values ('f1', (j ->> 'funilId')::uuid);
  insert into pg_temp._v (k, u) select 'e' || (ordem + 1), id from crm.etapa_funil where funil_id = pg_temp.v('f1');

  j := pg_temp.r('gestor', format('public.crm_criar_projeto(%L, %L, %L, %L)', 'ascensao_aluno', 'Ensaio F2 Projeto', pg_temp.v('ag'), 'hm'));
  perform pg_temp.ok('4.projeto', pg_temp.m(j) = '1 funis criados para Ensaio F2 Projeto.'
                     and exists (select 1 from crm.campanha c where c.funil_id = (j -> 'funilIds' ->> 0)::uuid and c.nome = 'Ascensão ensaio-f2-projeto')
                     and (select f.projeto from crm.funil f where f.id = (j -> 'funilIds' ->> 0)::uuid) = 'ensaio-f2-projeto'
                     and (select count(*) from crm.etapa_funil where funil_id = (j -> 'funilIds' ->> 0)::uuid) = 6, pg_temp.m(j) || ' · 6 etapas do modelo, chave na campanha');
  insert into pg_temp._v (k, u) values ('f2', (j -> 'funilIds' ->> 0)::uuid);
  perform pg_temp.ok('4.projeto_dup', pg_temp.m(pg_temp.r('gestor', format('public.crm_criar_projeto(%L, %L, %L, %L)', 'ascensao_aluno', 'Ensaio F2 Projeto', pg_temp.v('ag'), 'hm')))
                     = 'Já existe projeto com esse nome.', 'mesmo nome');
  perform pg_temp.ok('4.projeto_tipo', pg_temp.m(pg_temp.r('gestor', format('public.crm_criar_projeto(%L, %L, %L, %L)', 'nao_existe', 'Outro', pg_temp.v('ag'), 'hm')))
                     = 'Tipo de projeto desconhecido.', 'tipo inválido');
end $p4$;

-- ─── 5. Criar negócio: visibilidade, distribuição por percentual, "contato com dono mantém o dono", 1 aberto/funil ──
do $p5$
declare j jsonb; v_l bigint;
begin
  perform pg_temp.ok('5.vendedor_nao_ve', pg_temp.m(pg_temp.r('mp', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p1'), pg_temp.v('f1'))))
                     = 'Contato não encontrado.', 'pessoa sem camada comercial e sem dono visível');
  v_l := pg_temp.loglast();
  j := pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p1'), pg_temp.v('f1')));
  insert into pg_temp._v (k, u) values ('n1', (j ->> 'negocioId')::uuid);
  perform pg_temp.ok('5.n1_mp', (j ->> 'ok')::boolean and (j ->> 'donoId')::uuid = pg_temp.v('mp'), 'distribuição 70/30, 1º lead → mp');
  perform pg_temp.ok('5.n1_log', (select count(*) from crm.log l where l.id > v_l and l.entidade = 'negocio' and l.entidade_id = pg_temp.v('n1')::text
                                    and l.acao = 'criou' and l.autor_id = pg_temp.v('gestor')
                                    and l.resumo = 'Criou negócio de Ensaio F2 Um em Ensaio F2 Funil (dono: ' || (select nome from public.perfis where id = pg_temp.v('mp')) || ')') = 1,
                     '1 linha de log do negócio com resumo e autor');
  perform pg_temp.ok('5.n1_valor_etapa', (select n.valor = 297 and n.etapa_id = pg_temp.v('e1') and n.campos = '{"origem":"direto / —"}'::jsonb from crm.negocio n where n.id = pg_temp.v('n1')),
                     'valor = ticket da linha, 1ª etapa, campo origem');
  j := pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p2'), pg_temp.v('f1')));
  insert into pg_temp._v (k, u) values ('n2', (j ->> 'negocioId')::uuid);
  perform pg_temp.ok('5.n2_ro', (j ->> 'donoId')::uuid = pg_temp.v('ro'), '2º lead → ro (mais abaixo da cota)');
  j := pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p3'), pg_temp.v('f1')));
  insert into pg_temp._v (k, u) values ('n3', (j ->> 'negocioId')::uuid);
  perform pg_temp.ok('5.n3_mp', (j ->> 'donoId')::uuid = pg_temp.v('mp'), '3º lead → mp');
  perform pg_temp.ok('5.dup', pg_temp.m(pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p1'), pg_temp.v('f1'))))
                     = 'Este contato já tem negócio aberto neste funil.', '1 aberto por pessoa+funil');
  j := pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p2'), pg_temp.v('f2')));
  insert into pg_temp._v (k, u) values ('n4', (j ->> 'negocioId')::uuid);
  perform pg_temp.ok('5.dono_mantido', (j ->> 'donoId')::uuid = pg_temp.v('ro'), 'p2 já é do ro: no funil novo continua ro (a distribuição daria mp)');
  perform pg_temp.ok('5.pc_dono', (select pc.dono_id from crm.pessoa_comercial pc where pc.pessoa_id = pg_temp.v('p1')) = pg_temp.v('mp'), 'contato ganhou o dono');
  perform pg_temp.ok('5.notif_lead_novo', (select count(*) from crm.notificacao where gatilho = 'lead_novo' and perfil_id = pg_temp.v('mp')) = 2
                     and (select count(*) from crm.notificacao where gatilho = 'lead_novo' and perfil_id = pg_temp.v('ro')) = 2,
                     'trigger avisou o dono de cada lead novo (mp 2, ro 2)');
  perform pg_temp.ok('5.campanha_outro_funil', pg_temp.m(pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, %L)', pg_temp.v('p4'), pg_temp.v('f1'),
                       (select id from crm.campanha where funil_id = pg_temp.v('f2') limit 1)))) = 'Campanha não é deste funil.', 'campanha de outro funil');
end $p5$;

-- ─── 6. Mover etapa e campos: dono, obrigatórios, ganho, log 1 linha com diff ─────────────────────────────────────
do $p6$
declare j jsonb; v_l bigint; v_ok boolean;
begin
  perform pg_temp.ok('6.A_nao_move_B', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n2'), pg_temp.v('e3')))) = 'Este negócio não é seu.', 'mp × negócio do ro');
  perform pg_temp.ok('6.A_nao_edita_B', pg_temp.m(pg_temp.r('mp', format('public.crm_salvar_campos(%L, %L)', pg_temp.v('n2'), '{"origem":"x"}'))) = 'Este negócio não é seu.', 'mp × campos do ro');
  perform pg_temp.ok('6.obrigatorio', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'), pg_temp.v('e2'))))
                     = 'Preencha antes: Perfil profissional, Já atua com holding.', 'mensagem do mock');
  perform pg_temp.ok('6.pular_obrigatorio', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'), pg_temp.v('e3'))))
                     = 'Preencha antes: Perfil profissional, Já atua com holding.', 'pular etapa cobra os campos das anteriores');
  perform pg_temp.ok('6.ganho', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'), pg_temp.v('e4'))))
                     = 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.', 'mover para Ganho recusado');
  perform pg_temp.ok('6.etapa_outro_funil', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'),
                       (select id from crm.etapa_funil where funil_id = pg_temp.v('f2') order by ordem offset 1 limit 1)))) = 'Etapa não existe neste funil.', 'etapa de outro funil');
  perform pg_temp.ok('6.opcao_invalida', pg_temp.m(pg_temp.r('mp', format('public.crm_salvar_campos(%L, %L)', pg_temp.v('n1'), '{"perfil_profissional":"xx"}')))
                     = 'Valor "xx" não é opção de "Perfil profissional".', 'trigger da F1 vira {ok:false,msg}');
  v_l := pg_temp.loglast();
  j := pg_temp.r('mp', format('public.crm_salvar_campos(%L, %L)', pg_temp.v('n1'), '{"perfil_profissional":"advogado","atua_com_holding":"sim"}'));
  perform pg_temp.ok('6.campos', (j ->> 'ok')::boolean
                     and (select count(*) from crm.log where id > v_l) = 1
                     and (select l.resumo = 'Editou 2 campo(s) de Ensaio F2 Um' and l.autor_id = pg_temp.v('mp')
                                 and l.mudancas @> '[{"campo":"campos"}]' from crm.log l where l.id > v_l), 'ok, 1 linha de log com resumo e diff');
  v_l := pg_temp.loglast();
  j := pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'), pg_temp.v('e2')));
  perform pg_temp.ok('6.mover', (j ->> 'ok')::boolean and (select etapa_id from crm.negocio where id = pg_temp.v('n1')) = pg_temp.v('e2')
                     and (select count(*) from crm.log where id > v_l) = 1
                     and (select l.acao = 'moveu_etapa' and l.resumo = 'Moveu Ensaio F2 Um de Entrada para Qualificar'
                                 and l.mudancas @> jsonb_build_array(jsonb_build_object('campo', 'etapa_id', 'para', pg_temp.v('e2')))
                            from crm.log l where l.id > v_l), 'ok, 1 linha de log (moveu_etapa) com resumo e diff');
  perform pg_temp.ok('6.mesma_etapa', (pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'), pg_temp.v('e2'))) ->> 'ok')::boolean
                     and (select count(*) from crm.log where id > v_l) = 1, 'mesma etapa = ok sem escrever');
  -- defesa no banco: write direto (postgres) também respeita as regras
  begin
    update crm.negocio set status = 'ganho', transacao_ganho = 'ENSAIO', fechado_em = now() where id = pg_temp.v('n1');
    v_ok := false;
  exception when check_violation then v_ok := sqlerrm = 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.';
  end;
  perform pg_temp.ok('6.trigger_ganho', v_ok, 'status ganho fora da função da Hotmart recusado pelo trigger');
  begin
    update crm.negocio set etapa_id = pg_temp.v('e4') where id = pg_temp.v('n2');
    v_ok := false;
  exception when check_violation then v_ok := true;
  end;
  perform pg_temp.ok('6.trigger_etapa_ganho', v_ok, 'etapa de Ganho com status aberto recusada pelo trigger');
  begin
    update crm.negocio set etapa_id = pg_temp.v('e3') where id = pg_temp.v('n2');
    v_ok := false;
  exception when check_violation then v_ok := sqlerrm like 'Preencha antes:%';
  end;
  perform pg_temp.ok('6.trigger_obrigatorio', v_ok, 'campos obrigatórios também no trigger');
  -- ganho pela F3 (flag de sessão que só a função da Hotmart liga): passa
  begin
    perform set_config('crm.ganho_hotmart', 'on', true);
    update crm.negocio set status = 'ganho', transacao_ganho = 'ENSAIO', fechado_em = now(), etapa_id = pg_temp.v('e4') where id = pg_temp.v('n1');
    v_ok := (select status = 'ganho' from crm.negocio where id = pg_temp.v('n1'))
            and exists (select 1 from crm.notificacao where gatilho = 'venda_aprovada' and ref_id = pg_temp.v('n1')::text);
    raise exception 'desfaz' using errcode = 'P0001';
  exception when sqlstate 'P0001' then null;
  end;
  perform set_config('crm.ganho_hotmart', '', true);
  perform pg_temp.ok('6.ganho_f3', v_ok, 'com a flag da F3 o ganho passa e avisa venda_aprovada (desfeito)');
end $p6$;

-- ─── 7. Troca de dono: só gestor, com motivo; leva contato e atividades ────────────────────────────────────────────
do $p7$
declare j jsonb; v_l bigint;
begin
  perform pg_temp.ok('7.vendedor_nao_troca', pg_temp.m(pg_temp.r('mp', format('public.crm_transferir_dono(%L, %L, %L)', pg_temp.v('n1'), pg_temp.v('ro'), 'quero')))
                     = 'Troca de dono só pelo gestor do Comercial.', 'vendedor');
  perform pg_temp.ok('7.sem_motivo', pg_temp.m(pg_temp.r('gestor', format('public.crm_transferir_dono(%L, %L, %L)', pg_temp.v('n1'), pg_temp.v('ro'), '  ')))
                     = 'Escreva o motivo da troca.', 'motivo vazio');
  perform pg_temp.ok('7.dono_invalido', pg_temp.m(pg_temp.r('gestor', format('public.crm_transferir_dono(%L, %L, %L)', pg_temp.v('n1'), pg_temp.v('vis'), 'x')))
                     = 'Vendedor não encontrado ou inativo.', 'não vendedor');
  j := pg_temp.r('mp', format('public.crm_criar_atividade(%L, %L, %L, %L, %L)', pg_temp.v('n1'), pg_temp.v('p1'), 'ligacao', 'Ligar de novo', now() + interval '1 day'));
  insert into pg_temp._v (k, u) values ('a1', (j ->> 'atividadeId')::uuid);
  v_l := pg_temp.loglast();
  j := pg_temp.r('gestor', format('public.crm_transferir_dono(%L, %L, %L)', pg_temp.v('n1'), pg_temp.v('ro'), 'Cliente pediu'));
  perform pg_temp.ok('7.gestor_troca', (j ->> 'ok')::boolean
                     and (select dono_id from crm.negocio where id = pg_temp.v('n1')) = pg_temp.v('ro')
                     and (select dono_id from crm.pessoa_comercial where pessoa_id = pg_temp.v('p1')) = pg_temp.v('ro')
                     and (select dono_id from crm.atividade where id = pg_temp.v('a1')) = pg_temp.v('ro')
                     and exists (select 1 from crm.log l where l.id > v_l and l.acao = 'trocou_dono' and l.entidade = 'negocio'
                                    and l.resumo like 'Trocou o dono de Ensaio F2 Um: % → %. Motivo: Cliente pediu')
                     and exists (select 1 from crm.notificacao where perfil_id = pg_temp.v('ro') and gatilho = 'lead_novo' and ref_id = pg_temp.v('n1')::text),
                     'negócio, contato e atividade aberta foram para o ro; log com motivo; ro avisado');
  perform pg_temp.ok('7.antigo_dono_perde', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n1'), pg_temp.v('e1')))) = 'Este negócio não é seu.', 'mp perdeu o negócio');
end $p7$;

-- ─── 8. Perdido: motivo ativo do cadastro; bloqueia → opt-out; cancela atividades ─────────────────────────────────
do $p8$
declare j jsonb;
begin
  j := pg_temp.r('mp', format('public.crm_criar_atividade(%L, %L, %L, %L, %L)', pg_temp.v('n3'), pg_temp.v('p3'), 'whatsapp', 'Mandar proposta', now() + interval '2 hours'));
  insert into pg_temp._v (k, u) values ('a3', (j ->> 'atividadeId')::uuid);
  perform pg_temp.ok('8.motivo_fora', pg_temp.m(pg_temp.r('mp', format('public.crm_marcar_perdido(%L, %L, %L)', pg_temp.v('n3'), 'nao_existe', '')))
                     = 'Motivo fora do cadastro não existe.', 'motivo inexistente');
  j := pg_temp.r('gestor', format('public.crm_salvar_motivo_perda(%L)', '{"key":"sem_interesse","label":"Sem interesse","reativa":false,"bloqueia":false,"alertaGestor":false,"nota":null,"sistema":true,"ativo":false}'));
  perform pg_temp.ok('8.motivo_desativado', pg_temp.m(j) = 'Motivo atualizado.' and not (select ativo from crm.motivo_perda where chave = 'sem_interesse'), pg_temp.m(j));
  perform pg_temp.ok('8.motivo_inativo', pg_temp.m(pg_temp.r('mp', format('public.crm_marcar_perdido(%L, %L, %L)', pg_temp.v('n3'), 'sem_interesse', '')))
                     = 'Motivo fora do cadastro não existe.', 'motivo inativo recusado');
  perform pg_temp.ok('8.B_nao_perde_A', pg_temp.m(pg_temp.r('ro', format('public.crm_marcar_perdido(%L, %L, %L)', pg_temp.v('n3'), 'fora_do_perfil', '')))
                     = 'Este negócio não é seu.', 'ro × negócio do mp');
  j := pg_temp.r('mp', format('public.crm_marcar_perdido(%L, %L, %L)', pg_temp.v('n3'), 'pediu_sem_contato', 'Pediu por WhatsApp'));
  perform pg_temp.ok('8.perdido_bloqueia', (j ->> 'ok')::boolean
                     and (select status = 'perdido' and motivo_perda = 'pediu_sem_contato' and fechado_em is not null from crm.negocio where id = pg_temp.v('n3'))
                     and (select opt_out and opt_out_motivo = 'Pediu para não receber contato' from crm.pessoa_comercial where pessoa_id = pg_temp.v('p3'))
                     and (select cancelada and concluida_em is not null from crm.atividade where id = pg_temp.v('a3')),
                     'perdido; contato foi para opt-out (supressão); atividade aberta cancelada');
  perform pg_temp.ok('8.optout_bloqueia_negocio', pg_temp.m(pg_temp.r('gestor', format('public.crm_criar_negocio(%L, %L, null)', pg_temp.v('p3'), pg_temp.v('f2'))))
                     = 'Este contato pediu para não receber contato.', 'opt-out impede negócio novo');
  perform pg_temp.ok('8.ja_perdido', pg_temp.m(pg_temp.r('mp', format('public.crm_marcar_perdido(%L, %L, %L)', pg_temp.v('n3'), 'fora_do_perfil', '')))
                     = 'Só negócio aberto pode ser perdido.', 'encerrado');
  perform pg_temp.ok('8.encerrado_nao_move', pg_temp.m(pg_temp.r('mp', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n3'), pg_temp.v('e2'))))
                     = 'Negócio encerrado não muda de etapa.', 'encerrado');
  j := pg_temp.r('gestor', format('public.crm_salvar_motivo_perda(%L)', '{"key":"ensaio_motivo","label":"Ensaio motivo","reativa":true,"bloqueia":false,"alertaGestor":false,"nota":"x","sistema":false,"ativo":true}'));
  perform pg_temp.ok('8.motivo_novo', pg_temp.m(j) = 'Motivo criado.', pg_temp.m(j));
  perform pg_temp.ok('8.motivo_dup', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_motivo_perda(%L)', '{"key":"ensaio_outro","label":"ensaio MOTIVO","reativa":false,"bloqueia":false,"alertaGestor":false,"nota":null,"sistema":false,"ativo":true}')))
                     = 'Já existe um motivo com esse nome.', 'rótulo repetido');
  perform pg_temp.ok('8.motivo_fabrica', (select rotulo = 'Sem interesse' and not bloqueia from crm.motivo_perda where chave = 'sem_interesse'), 'de fábrica só mudou ativo/nota');
end $p8$;

-- ─── 9. Atividade e nota ────────────────────────────────────────────────────────────────────────────────────────────
do $p9$
declare j jsonb;
begin
  j := pg_temp.r('ro', format('public.crm_criar_atividade(%L, %L, %L, %L, %L)', pg_temp.v('n2'), pg_temp.v('p2'), 'ligacao', 'Ligar', now() + interval '1 hour'));
  insert into pg_temp._v (k, u) values ('a2', (j ->> 'atividadeId')::uuid);
  perform pg_temp.ok('9.atividade', (j ->> 'ok')::boolean and exists (select 1 from crm.log l where l.entidade = 'atividade' and l.entidade_id = pg_temp.v('a2')::text
                                                                         and l.resumo = 'Agendou "Ligar" para Ensaio F2 Dois'), 'ok + log');
  perform pg_temp.ok('9.A_nao_agenda_B', pg_temp.m(pg_temp.r('mp', format('public.crm_criar_atividade(%L, %L, %L, %L, %L)', pg_temp.v('n2'), pg_temp.v('p2'), 'ligacao', 'x', now())))
                     = 'Este negócio não é seu.', 'mp × negócio do ro');
  perform pg_temp.ok('9.A_contato_B', pg_temp.m(pg_temp.r('mp', format('public.crm_criar_atividade(null, %L, %L, %L, %L)', pg_temp.v('p2'), 'tarefa', 'x', now())))
                     = 'Este contato não é seu.', 'mp × contato do ro');
  perform pg_temp.ok('9.A_nao_conclui_B', pg_temp.m(pg_temp.r('mp', format('public.crm_concluir_atividade(%L, %L)', pg_temp.v('a2'), 'feito')))
                     = 'Esta atividade não é sua.', 'mp × atividade do ro');
  j := pg_temp.r('ro', format('public.crm_concluir_atividade(%L, %L)', pg_temp.v('a2'), 'Atendeu'));
  perform pg_temp.ok('9.concluir', (j ->> 'ok')::boolean and (select resultado = 'Atendeu' from crm.atividade where id = pg_temp.v('a2'))
                     and exists (select 1 from crm.log l where l.acao = 'concluiu' and l.entidade_id = pg_temp.v('a2')::text), 'ok + log concluiu');
  perform pg_temp.ok('9.concluir_2x', pg_temp.m(pg_temp.r('ro', format('public.crm_concluir_atividade(%L, %L)', pg_temp.v('a2'), 'x')))
                     = 'Atividade não encontrada ou já concluída.', 'mensagem do mock');
  perform pg_temp.ok('9.nota_vazia', pg_temp.m(pg_temp.r('ro', format('public.crm_adicionar_nota(%L, null, %L)', pg_temp.v('p2'), '   '))) = 'Nota vazia.', 'vazia');
  perform pg_temp.ok('9.A_nota_B', pg_temp.m(pg_temp.r('mp', format('public.crm_adicionar_nota(%L, null, %L)', pg_temp.v('p2'), 'oi'))) = 'Este contato não é seu.', 'mp × contato do ro');
  j := pg_temp.r('ro', format('public.crm_adicionar_nota(%L, %L, %L)', pg_temp.v('p2'), pg_temp.v('n2'), 'Pediu proposta'));
  perform pg_temp.ok('9.nota', (j ->> 'ok')::boolean and exists (select 1 from crm.nota where id = (j ->> 'notaId')::uuid and autor_id = pg_temp.v('ro')), 'ok');
end $p9$;

-- ─── 10. Atribuir contato, funil (editar/arquivar), produto/oferta ─────────────────────────────────────────────────
do $p10$
declare j jsonb; v_f jsonb;
begin
  perform pg_temp.ok('10.vendedor_atribui', pg_temp.m(pg_temp.r('mp', format('public.crm_atribuir_contato(%L, %L, %L)', pg_temp.v('p4'), pg_temp.v('mp'), 'x')))
                     = 'Só o gestor define dono.', 'vendedor');
  perform pg_temp.ok('10.atribui_sem_motivo', pg_temp.m(pg_temp.r('gestor', format('public.crm_atribuir_contato(%L, %L, %L)', pg_temp.v('p4'), pg_temp.v('mp'), '')))
                     = 'Escreva o motivo.', 'motivo');
  j := pg_temp.r('gestor', format('public.crm_atribuir_contato(%L, %L, %L)', pg_temp.v('p4'), pg_temp.v('mp'), 'Indicação'));
  perform pg_temp.ok('10.atribui', (j ->> 'ok')::boolean and (select dono_id from crm.pessoa_comercial where pessoa_id = pg_temp.v('p4')) = pg_temp.v('mp'), 'contato sem dono → mp');

  perform pg_temp.ok('10.arquivar_aberto', pg_temp.m(pg_temp.r('gestor', format('public.crm_arquivar_funil(%L)', pg_temp.v('f1'))))
                     = 'Funil com negócio aberto não pode ser arquivado.', 'aberto');
  perform pg_temp.ok('10.arquivar_vendedor', pg_temp.m(pg_temp.r('mp', format('public.crm_arquivar_funil(%L)', pg_temp.v('f1')))) = 'Só o gestor arquiva funis.', 'vendedor');
  -- n2 está na Entrada (e1): remover e1 recusa
  v_f := jsonb_build_object('id', pg_temp.v('f1'), 'nome', 'Ensaio F2 Funil', 'icone', 'kanban', 'projeto', null, 'agrupadorId', pg_temp.v('ag'),
    'produto', 'ht', 'tipo', 'manual', 'eventosHotmart', '[]'::jsonb, 'distribuicao', null, 'campanhas', '[]'::jsonb,
    'etapas', jsonb_build_array(
      jsonb_build_object('id', pg_temp.v('e2'), 'nome', 'Qualificar', 'papel', 'qualificar', 'cor', 'cyan', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '[]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', pg_temp.v('e4'), 'nome', 'Ganho', 'papel', 'fechado', 'cor', 'green', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '[]'::jsonb, 'criterio', '')));
  perform pg_temp.ok('10.remover_etapa_aberta', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_funil(%L)', v_f)))
                     = 'Há negócio aberto numa etapa removida. Mova os negócios antes.', 'etapa com negócio aberto');
  -- tira Negociar (vazia), troca a ordem de Entrada/Qualificar, renomeia Entrada, distribuição própria 50/50
  v_f := jsonb_set(v_f, '{etapas}', jsonb_build_array(
      jsonb_build_object('id', pg_temp.v('e2'), 'nome', 'Qualificar', 'papel', 'qualificar', 'cor', 'cyan', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '[]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', pg_temp.v('e1'), 'nome', 'Primeiro contato', 'papel', 'primeiro_contato', 'cor', 'info', 'slaAtencaoMin', 5, 'slaCriticoMin', 15, 'camposObrigatorios', '[]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', 'nova', 'nome', 'Aguardar pagamento', 'papel', 'aguardar_pagamento', 'cor', 'yellow', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '["forma_pagamento"]'::jsonb, 'criterio', ''),
      jsonb_build_object('id', pg_temp.v('e4'), 'nome', 'Ganho', 'papel', 'fechado', 'cor', 'green', 'slaAtencaoMin', null, 'slaCriticoMin', null, 'camposObrigatorios', '[]'::jsonb, 'criterio', '')));
  v_f := jsonb_set(v_f, '{distribuicao}', jsonb_build_array(jsonb_build_object('vendedorId', pg_temp.v('mp'), 'percentual', 50), jsonb_build_object('vendedorId', pg_temp.v('ro'), 'percentual', 40)));
  perform pg_temp.ok('10.funil_dist_90', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_funil(%L)', v_f))) = 'A distribuição própria precisa somar 100%.', 'soma 90');
  v_f := jsonb_set(v_f, '{distribuicao,1,percentual}', '50');
  j := pg_temp.r('gestor', format('public.crm_salvar_funil(%L)', v_f));
  perform pg_temp.ok('10.funil_editado', pg_temp.m(j) = 'Funil atualizado.'
                     and (select ordem = 1 and nome = 'Primeiro contato' from crm.etapa_funil where id = pg_temp.v('e1'))
                     and (select ordem = 0 from crm.etapa_funil where id = pg_temp.v('e2'))
                     and (select arquivada_em is not null from crm.etapa_funil where id = pg_temp.v('e3'))
                     and (select count(*) from crm.etapa_funil where funil_id = pg_temp.v('f1') and arquivada_em is null) = 4
                     and (select distribuicao_propria from crm.funil where id = pg_temp.v('f1'))
                     and (select count(*) from crm.distribuicao where funil_id = pg_temp.v('f1') and ativo) = 2
                     and not (select ativa from crm.campanha where funil_id = pg_temp.v('f1') limit 1),
                     pg_temp.m(j) || ' · reordenou, renomeou, arquivou a removida, criou a nova, distribuição própria, campanha removida inativa');

  perform pg_temp.ok('10.produto_vendedor', pg_temp.m(pg_temp.r('mp', format('public.crm_vincular_produto(%L)', jsonb_build_object('produtoId', pg_temp.t('prod'), 'noComercial', true)))) = 'Só o gestor vincula produtos.', 'vendedor');
  perform pg_temp.ok('10.oferta_sem_vinculo', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_oferta(%L)', jsonb_build_object('codigo', pg_temp.t('oferta'), 'vigente', true))))
                     = 'Vincule o produto ao comercial antes de marcar oferta vigente.', 'vigente sem produto vinculado');
  perform pg_temp.ok('10.produto_inexistente', pg_temp.m(pg_temp.r('gestor', format('public.crm_vincular_produto(%L)', '{"produtoId":"nao-existe-ensaio","noComercial":true}')))
                     = 'Produto não veio da Hotmart. Crie o produto na Hotmart; ele aparece aqui depois da sincronização.', 'fora de fin.produtos');
  perform pg_temp.ok('10.produto_sem_nome', pg_temp.m(pg_temp.r('gestor', format('public.crm_vincular_produto(%L)', jsonb_build_object('produtoId', pg_temp.t('prod'), 'noComercial', true, 'nomeComercial', ' ', 'escada', 'B'))))
                     = 'Para vincular, dê o nome comercial e a escada (A ou B).', 'nome vazio');
  j := pg_temp.r('gestor', format('public.crm_vincular_produto(%L)', jsonb_build_object('produtoId', pg_temp.t('prod'), 'noComercial', true, 'nomeComercial', 'Ensaio F2 Produto',
                                                                                       'produtoKey', 'ht', 'agrupadorId', pg_temp.v('ag'), 'escada', 'B')));
  perform pg_temp.ok('10.produto_vinculado', pg_temp.m(j) = 'Produto vinculado ao comercial.', pg_temp.m(j));
  j := pg_temp.r('gestor', format('public.crm_salvar_oferta(%L)', jsonb_build_object('codigo', pg_temp.t('oferta'), 'vigente', true, 'condicao', '12x', 'validaAte', '2026-12-31', 'uso', 'ensaio')));
  perform pg_temp.ok('10.oferta', pg_temp.m(j) = 'Oferta salva.' and (select vigente and valida_ate = '2026-12-31' from crm.oferta_comercial where oferta_codigo = pg_temp.t('oferta')), pg_temp.m(j));
  j := pg_temp.r('gestor', format('public.crm_vincular_produto(%L)', jsonb_build_object('produtoId', pg_temp.t('prod'), 'noComercial', false)));
  perform pg_temp.ok('10.desvincular', pg_temp.m(j) = 'Produto desvinculado.' and not (select vigente from crm.oferta_comercial where oferta_codigo = pg_temp.t('oferta')),
                     'desvinculou e a oferta deixou de ser vigente');
  perform pg_temp.ok('10.oferta_inexistente', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_oferta(%L)', '{"codigo":"nao-existe-ensaio","vigente":false}')))
                     = 'Oferta não está no catálogo da Hotmart.', 'fora de fin.ofertas');
end $p10$;

-- ─── 11. Dashboard, painel, preferências, notificações, prazos ─────────────────────────────────────────────────────
do $p11$
declare j jsonb; v_d uuid; v_n int;
begin
  j := pg_temp.r('mp', format('public.crm_salvar_dashboard(%L)', '{"id":"dash-novo-1","nome":"Meu painel","descricao":null,"compartilhado":true,"widgets":[]}'));
  v_d := (j ->> 'dashboardId')::uuid;
  perform pg_temp.ok('11.dash_criado', pg_temp.m(j) = 'Dashboard criado.' and (select dono_id from crm.dashboard where id = v_d) = pg_temp.v('mp'), pg_temp.m(j));
  perform pg_temp.ok('11.dash_vazio', pg_temp.m(pg_temp.r('mp', format('public.crm_salvar_dashboard(%L)', '{"nome":"  "}'))) = 'Dê um nome ao dashboard.', 'nome');
  perform pg_temp.ok('11.dash_B_edita_A', pg_temp.m(pg_temp.r('ro', format('public.crm_salvar_dashboard(%L)', jsonb_build_object('id', v_d, 'nome', 'Hack', 'widgets', '[]'::jsonb))))
                     = 'Só o dono e o gestor editam este dashboard.', 'ro × dashboard do mp');
  perform pg_temp.ok('11.dash_B_exclui_A', pg_temp.m(pg_temp.r('ro', format('public.crm_arquivar_dashboard(%L)', v_d))) = 'Só o dono e o gestor excluem.', 'ro × dashboard do mp');
  perform pg_temp.ok('11.dash_gestor', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_dashboard(%L)', jsonb_build_object('id', v_d, 'nome', 'Meu painel 2', 'compartilhado', true, 'widgets', '[]'::jsonb)))) = 'Dashboard salvo.', 'gestor edita');
  j := pg_temp.r('mp', format('public.crm_arquivar_dashboard(%L)', v_d));   -- chamar ANTES de conferir (AND não garante ordem)
  perform pg_temp.ok('11.dash_excluir', pg_temp.m(j) = 'Dashboard excluído.'
                     and (select arquivado_em is not null from crm.dashboard where id = v_d), 'arquivado, não apagado');
  perform pg_temp.ok('11.painel_outro', pg_temp.m(pg_temp.r('mp', format('public.crm_salvar_painel(%L, %L)', pg_temp.v('ro'), '[]'))) = 'Você só edita o seu painel.', 'mp × painel do ro');
  perform pg_temp.ok('11.painel_gestor', pg_temp.m(pg_temp.r('gestor', format('public.crm_salvar_painel(%L, %L)', pg_temp.v('mp'), '[{"id":"w1"}]'))) = 'Painel salvo.', 'gestor monta o do mp');
  perform pg_temp.ok('11.pref_outro', pg_temp.m(pg_temp.r('mp', format('public.crm_salvar_preferencias(%L)', jsonb_build_object('vendedorId', pg_temp.v('ro'), 'desktop', true, 'gatilhos', '{}'::jsonb))))
                     = 'Você só edita as suas notificações.', 'mp × preferências do ro');
  j := pg_temp.r('mp', format('public.crm_salvar_preferencias(%L)', jsonb_build_object('vendedorId', pg_temp.v('mp'), 'desktop', true,
                 'gatilhos', '{"lead_novo":true,"prazo_estourado":true,"lead_respondeu":true,"venda_aprovada":true,"ficha_para_aprovar":true,"atividade_vencendo":false}'::jsonb,
                 'silencioInicio', '20:00', 'silencioFim', '08:00')));
  perform pg_temp.ok('11.pref', pg_temp.m(j) = 'Preferências salvas.' and (select silencio_inicio = '20:00' from crm.preferencias_notificacao where perfil_id = pg_temp.v('mp')), pg_temp.m(j));
  select count(*) into v_n from crm.notificacao where perfil_id = pg_temp.v('mp') and lida_em is null;
  j := pg_temp.r('mp', 'public.crm_marcar_notificacoes_lidas(null)');
  perform pg_temp.ok('11.lidas', (j ->> 'marcadas')::int = v_n and v_n > 0
                     and exists (select 1 from crm.notificacao where perfil_id = pg_temp.v('ro') and lida_em is null), format('mp marcou %s; as do ro continuam não lidas', v_n));
  -- prazos: kill-switch desligado → 0; ligado → avisa quem estourou o crítico
  perform pg_temp.ok('11.prazos_desligado', crm.notificar_prazos() = 0, 'notificacao_cron_ligado=false');
  update crm.config set notificacao_cron_ligado = true;
  update crm.negocio set etapa_desde = now() - interval '1 hour' where id = pg_temp.v('n2');     -- Entrada: crítico 15 min
  update crm.atividade set vence_em = now() + interval '10 minutes' where id = pg_temp.v('a1');  -- do ro
  v_n := crm.notificar_prazos();
  perform pg_temp.ok('11.prazos', v_n >= 2 and exists (select 1 from crm.notificacao where perfil_id = pg_temp.v('ro') and gatilho = 'prazo_estourado')
                     and exists (select 1 from crm.notificacao where perfil_id = pg_temp.v('ro') and gatilho = 'atividade_vencendo' and ref_id = pg_temp.v('a1')::text)
                     and crm.notificar_prazos() = 0, format('%s avisos; 2ª rodada não duplica', v_n));
  update crm.config set notificacao_cron_ligado = false;
end $p11$;

-- ─── 12. Log: toda escrita do ensaio gravou resumo; leitura (F1) respeita o dono depois das escritas ───────────────
do $p12$
declare v_sem int; v_aut int; j jsonb;
begin
  select count(*) filter (where coalesce(resumo, '') = '' or resumo like initcap(acao) || ' ' || entidade || ' %'),
         count(*) filter (where autor_id is null)
    into v_sem, v_aut
    from crm.log where id > pg_temp.t('log0')::bigint and canal <> 'sistema' and entidade not in ('etapa', 'campanha', 'distribuicao');
  perform pg_temp.ok('12.log_resumo', v_sem = 0, format('%s linhas de log (fora etapa/campanha/distribuição do funil) sem resumo próprio', v_sem));
  perform pg_temp.ok('12.log_autor', v_aut = 0, format('%s linhas feitas pela tela sem autor', v_aut));
  j := pg_temp.r('mp', 'public.crm_negocios()');
  perform pg_temp.ok('12.rls_A', not exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::uuid in (pg_temp.v('n1'), pg_temp.v('n2'), pg_temp.v('n4')))
                     and exists (select 1 from jsonb_array_elements(j) x where (x ->> 'id')::uuid = pg_temp.v('n3')), 'mp lê só o dele (n3), não os do ro');
end $p12$;

-- ─── 13. Desliga de novo: volta a recusar ───────────────────────────────────────────────────────────────────────────
update crm.config set escrita_ligada = false;
do $p13$ begin
  perform pg_temp.ok('13.desligado_de_novo', pg_temp.m(pg_temp.r('gestor', format('public.crm_mover_etapa(%L, %L)', pg_temp.v('n2'), pg_temp.v('e2'))))
                     = 'CRM em manutenção: escrita desligada.', 'kill-switch em ~0 s');
end $p13$;

select linha from _z_out order by n;
rollback;

-- ═══ PARTE B: massa 10× + medição (1 chamada, begin … rollback) ════════════════════════════════════════════════════
-- Recria SÓ o que a medição precisa, com o MESMO corpo da migration (helpers, triggers do negócio, crm_criar_negocio,
-- crm_mover_etapa, crm_salvar_dashboard/crm_arquivar_dashboard; o bloco de exceção reduzido às 4 classes que estas
-- RPCs disparam). B0 refaz o passo 11.dash_excluir da Parte A chamando a RPC antes de conferir (a 1ª versão do teste
-- avaliava a subconsulta antes da chamada: AND não garante ordem). Massa: 20 mil pessoas (teste=true), 19.998 camadas
-- comerciais, 29.998 negócios NUM funil só (pior caso da contagem da distribuição), carregados com os triggers de
-- usuário desligados SÓ dentro da transação (para não gravar 50 mil linhas de log), religados antes de medir.
-- Medição = RPC inteira como a tela chama (authenticated + JWT real), 2×. Números colados em 20261005t.explain.md.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _z_out (n serial, passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void language sql as $$
insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'OK ' else 'ERRADO ' end || p_passo || ' — ' || coalesce(p_det, '')); $$;
create function crm.res(p_ok boolean, p_msg text default null, p_extra jsonb default null) returns jsonb language sql immutable set search_path = '' as $$
select jsonb_build_object('ok', p_ok) || case when p_msg is null then '{}'::jsonb else jsonb_build_object('msg', p_msg) end || coalesce(p_extra, '{}'::jsonb); $$;
create function crm.guarda_escrita() returns jsonb language plpgsql security definer set search_path = '' as $$
begin
perform set_config('crm.resumo', '', true);
if not coalesce((select c.escrita_ligada from crm.config c), false) then return crm.res(false, 'CRM em manutenção: escrita desligada.'); end if;
if not coalesce(crm.eh_comercial(), false) then return crm.res(false, 'Sem acesso ao Comercial.'); end if;
return null;
end $$;
create function crm.erro_dados(p_estado text, p_msg text, p_constraint text) returns jsonb language sql immutable set search_path = '' as $$
select crm.res(false, case when p_estado = '23505' and p_constraint = 'negocio_aberto_uidx' then 'Este contato já tem negócio aberto neste funil.'
when p_estado = '23514' and coalesce(p_constraint, '') = '' then p_msg else 'Não foi possível salvar: ' || p_msg end); $$;
create function crm.uuid_ou_null(p text) returns uuid language sql immutable set search_path = '' as $$
select case when p ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then p::uuid end; $$;
create function crm.nome_pessoa(p uuid) returns text language sql stable security definer set search_path = '' as $$
select coalesce((select d.d_nome from pessoas.dados(pessoas.atual(p)) d), 'contato'); $$;
create function crm.nome_perfil(p uuid) returns text language sql stable security definer set search_path = '' as $$
select case when p is null then 'sem dono' else coalesce((select x.nome from public.perfis x where x.id = p), p::text) end; $$;
create function crm.vendedor_ativo(p uuid) returns boolean language sql stable security definer set search_path = '' as $$
select coalesce((select v.ativo and pf.status = 'ativo' and 'comercial' = any(coalesce(pf.areas, '{}')) and 'comercial.vender' = any(coalesce(pf.funcoes, '{}'))
from crm.vendedor v join public.perfis pf on pf.id = v.perfil_id where v.perfil_id = p), false); $$;
create function crm.garantir_pc(p uuid) returns uuid language plpgsql security definer set search_path = '' as $$
declare v_atual uuid := pessoas.atual(p); v uuid;
begin
select pc.pessoa_id into v from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(v_atual)) order by pc.pessoa_id = v_atual desc, pc.criado_em limit 1;
if v is not null then return v; end if;
perform set_config('crm.resumo', 'Abriu o contato comercial de ' || crm.nome_pessoa(v_atual), true);
insert into crm.pessoa_comercial (pessoa_id) values (v_atual) on conflict (pessoa_id) do nothing;
perform set_config('crm.resumo', '', true);
return v_atual;
end $$;
create function crm.campos_faltando(p_campos jsonb, p_funil uuid, p_etapa uuid) returns text language sql stable set search_path = '' as $$
with alvo as (select e.ordem from crm.etapa_funil e where e.id = p_etapa and e.funil_id = p_funil),
ex as (select u.c, min(e.ordem::int * 1000 + u.o) k from crm.etapa_funil e cross join alvo cross join lateral unnest(e.campos_obrigatorios) with ordinality u(c, o)
where e.funil_id = p_funil and e.arquivada_em is null and e.ordem <= alvo.ordem group by u.c)
select string_agg(coalesce(d.rotulo, ex.c), ', ' order by ex.k) from ex left join crm.campo_def d on d.chave = ex.c
where nullif(btrim(coalesce(p_campos ->> ex.c, '')), '') is null; $$;
create function crm.escolher_dono(p_pessoa uuid, p_funil uuid) returns uuid language plpgsql stable security definer set search_path = '' as $$
declare v_dono uuid; v_propria boolean; v_desde timestamptz; v_atual uuid := pessoas.atual(p_pessoa);
begin
select pc.dono_id into v_dono from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(v_atual)) and pc.dono_id is not null
order by pc.pessoa_id = v_atual desc, pc.criado_em limit 1;
if v_dono is not null and crm.vendedor_ativo(v_dono) then return v_dono; end if;
select f.distribuicao_propria into v_propria from crm.funil f where f.id = p_funil;
select c.ciclo_distribuicao_desde into v_desde from crm.config c;
with el as (select d.vendedor_id, d.percentual from crm.distribuicao d where d.ativo and d.percentual > 0
and d.funil_id is not distinct from (case when coalesce(v_propria, false) then p_funil end) and crm.vendedor_ativo(d.vendedor_id)),
rec as (select el.vendedor_id, el.percentual, (select count(*) from crm.negocio n where n.dono_id = el.vendedor_id and n.criado_em >= v_desde and n.funil_id = p_funil) r from el),
tot as (select coalesce(sum(rec.r), 0) + 1 t from rec)
select rec.vendedor_id into v_dono from rec cross join tot order by (rec.percentual / 100.0) * tot.t - rec.r desc, rec.percentual desc, rec.vendedor_id limit 1;
return v_dono;
end $$;
create function crm.tg_negocio_regras() returns trigger language plpgsql set search_path = '' as $$
declare v_papel text; v_arq timestamptz; v_falta text; v_msg_ganho constant text := 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.';
begin
if tg_op = 'INSERT' or new.etapa_id is distinct from old.etapa_id or new.status is distinct from old.status then
select e.papel, e.arquivada_em into v_papel, v_arq from crm.etapa_funil e where e.id = new.etapa_id; end if;
if tg_op = 'UPDATE' and new.etapa_id is distinct from old.etapa_id then
if old.status <> 'aberto' and new.status = old.status then raise exception 'Negócio encerrado não muda de etapa.' using errcode = '23514'; end if;
if v_arq is not null then raise exception 'Etapa não existe neste funil.' using errcode = '23514'; end if;
if new.status = 'aberto' then v_falta := crm.campos_faltando(new.campos, new.funil_id, new.etapa_id);
if v_falta is not null then raise exception 'Preencha antes: %.', v_falta using errcode = '23514'; end if; end if;
end if;
if new.status = 'ganho' and (tg_op = 'INSERT' or old.status is distinct from 'ganho') and coalesce(current_setting('crm.ganho_hotmart', true), '') <> 'on' then
raise exception '%', v_msg_ganho using errcode = '23514'; end if;
if v_papel = 'fechado' and new.status = 'aberto' then raise exception '%', v_msg_ganho using errcode = '23514'; end if;
if new.status = 'perdido' and (tg_op = 'INSERT' or old.status is distinct from 'perdido')
and not exists (select 1 from crm.motivo_perda m where m.chave = new.motivo_perda and m.ativo) then
raise exception 'Motivo fora do cadastro não existe.' using errcode = '23514'; end if;
return new;
end $$;
create trigger negocio_regras before insert or update on crm.negocio for each row execute function crm.tg_negocio_regras();
create function crm.tg_negocio_notifica() returns trigger language plpgsql set search_path = '' as $$
declare v_gat text; v_tit text; v_corpo text; v_nome text;
begin
if new.dono_id is null then return null; end if;
if new.status = 'aberto' and (tg_op = 'INSERT' or old.dono_id is distinct from new.dono_id) and new.dono_id is distinct from auth.uid() then v_gat := 'lead_novo';
elsif tg_op = 'UPDATE' and new.status = 'ganho' and old.status is distinct from 'ganho' then v_gat := 'venda_aprovada';
else return null; end if;
begin
if exists (select 1 from crm.preferencias_notificacao p where p.perfil_id = new.dono_id and (p.gatilhos ->> v_gat) = 'false') then return null; end if;
v_nome := crm.nome_pessoa(new.pessoa_id);
if v_gat = 'lead_novo' then v_tit := 'Lead novo: ' || v_nome;
v_corpo := coalesce((select e.nome from crm.etapa_funil e where e.id = new.etapa_id), 'Entrada') || ' · primeiro contato em até 5 minutos.';
else v_tit := 'Venda aprovada: ' || v_nome;
v_corpo := coalesce((select l.nome from crm.linha l where l.chave = new.linha), new.linha) || ' · pagamento aprovado na Hotmart.'; end if;
insert into crm.notificacao (perfil_id, gatilho, ref_id, titulo, corpo, href)
values (new.dono_id, v_gat, new.id::text, left(v_tit, 200), left(v_corpo, 500), '/comercial/funil?negocio=' || new.id) on conflict (perfil_id, gatilho, ref_id) do nothing;
exception when others then raise warning 'crm.tg_negocio_notifica: % (%)', sqlerrm, sqlstate;
end;
return null;
end $$;
create trigger negocio_notifica_ins after insert on crm.negocio for each row when (new.dono_id is not null and new.status = 'aberto') execute function crm.tg_negocio_notifica();
create trigger negocio_notifica_upd after update on crm.negocio for each row
when (new.dono_id is not null and (new.dono_id is distinct from old.dono_id or new.status is distinct from old.status)) execute function crm.tg_negocio_notifica();
create function public.crm_mover_etapa(p_negocio uuid, p_etapa uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; n crm.negocio%rowtype; e crm.etapa_funil%rowtype; v_de text; v_falta text; v_s text; v_c text; v_m text;
begin
v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
select * into n from crm.negocio x where x.id = p_negocio for update;
if not found then return crm.res(false, 'Negócio não encontrado.'); end if;
if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then return crm.res(false, 'Este negócio não é seu.'); end if;
if n.etapa_id = p_etapa then return crm.res(true); end if;
if n.status <> 'aberto' then return crm.res(false, 'Negócio encerrado não muda de etapa.'); end if;
select * into e from crm.etapa_funil x where x.id = p_etapa and x.funil_id = n.funil_id and x.arquivada_em is null;
if not found then return crm.res(false, 'Etapa não existe neste funil.'); end if;
if e.papel = 'fechado' then return crm.res(false, 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.'); end if;
v_falta := crm.campos_faltando(n.campos, n.funil_id, p_etapa);
if v_falta is not null then return crm.res(false, 'Preencha antes: ' || v_falta || '.'); end if;
select x.nome into v_de from crm.etapa_funil x where x.id = n.etapa_id;
perform set_config('crm.resumo', format('Moveu %s de %s para %s', crm.nome_pessoa(n.pessoa_id), v_de, e.nome), true);
update crm.negocio x set etapa_id = p_etapa, etapa_desde = now(), ultima_interacao_em = now(), atualizado_em = now() where x.id = p_negocio;
return crm.res(true);
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation then
get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text; return crm.erro_dados(v_s, v_m, v_c);
end $$;
create function public.crm_criar_negocio(p_pessoa uuid, p_funil uuid, p_campanha uuid default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_r jsonb; v_atual uuid; v_g uuid[]; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pc uuid; v_utm jsonb; v_valor numeric; v_id uuid; v_nome text; v_s text; v_c text; v_m text;
begin
v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
v_atual := pessoas.atual(p_pessoa);
if v_atual is null or not exists (select 1 from pessoas.pessoas p where p.id = v_atual)
or not (coalesce(crm.eh_gestor(), false) or coalesce(crm.pode_ver_pessoa(v_atual), false)) then return crm.res(false, 'Contato não encontrado.'); end if;
v_g := pessoas.grupo(v_atual);
if exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and pc.opt_out) then return crm.res(false, 'Este contato pediu para não receber contato.'); end if;
select * into f from crm.funil x where x.id = p_funil and x.ativo;
if not found then return crm.res(false, 'Funil não encontrado.'); end if;
if p_campanha is not null and not exists (select 1 from crm.campanha c where c.id = p_campanha and c.funil_id = p_funil) then return crm.res(false, 'Campanha não é deste funil.'); end if;
perform pg_advisory_xact_lock(hashtext('crm.dist:' || p_funil::text));
if exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.funil_id = p_funil and n.status = 'aberto') then return crm.res(false, 'Este contato já tem negócio aberto neste funil.'); end if;
select e.id into v_etapa from crm.etapa_funil e where e.funil_id = p_funil and e.arquivada_em is null order by e.ordem limit 1;
if v_etapa is null then return crm.res(false, 'Funil sem etapas.'); end if;
v_dono := crm.escolher_dono(v_atual, p_funil);
v_nome := crm.nome_pessoa(v_atual);
v_pc := crm.garantir_pc(v_atual);
if v_dono is not null then
perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição)', v_nome, crm.nome_perfil(v_dono)), true);
update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is null; end if;
select pc.utm_primeira into v_utm from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;
select l.ticket_ref into v_valor from crm.linha l where l.chave = f.linha;
perform set_config('crm.resumo', format('Criou negócio de %s em %s (dono: %s)', v_nome, f.nome, crm.nome_perfil(v_dono)), true);
insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, campos, utm, ultima_interacao_em)
values (v_atual, p_funil, v_etapa, p_campanha, f.linha, 'venda_ativa', v_dono, coalesce(v_valor, 0),
jsonb_build_object('origem', coalesce(nullif(v_utm ->> 'source', ''), 'direto') || ' / ' || coalesce(nullif(v_utm ->> 'campaign', ''), '—')), coalesce(v_utm, '{}'::jsonb), null)
returning id into v_id;
return crm.res(true, null, jsonb_build_object('negocioId', v_id, 'donoId', v_dono));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation then
get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text; return crm.erro_dados(v_s, v_m, v_c);
end $$;
create function public.crm_salvar_dashboard(p_dashboard jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; v_id uuid := crm.uuid_ou_null(p_dashboard ->> 'id'); d crm.dashboard%rowtype; v_nome text := btrim(coalesce(p_dashboard ->> 'nome', '')); v_w jsonb;
begin
v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
if v_nome = '' then return crm.res(false, 'Dê um nome ao dashboard.'); end if;
v_w := case when jsonb_typeof(p_dashboard -> 'widgets') = 'array' then p_dashboard -> 'widgets' else '[]'::jsonb end;
if v_id is not null then select * into d from crm.dashboard x where x.id = v_id and x.arquivado_em is null for update; end if;
if d.id is not null then
if not (d.dono_id = v_eu or coalesce(crm.eh_gestor(), false)) then return crm.res(false, 'Só o dono e o gestor editam este dashboard.'); end if;
perform set_config('crm.resumo', format('Editou o dashboard %s', v_nome), true);
update crm.dashboard x set nome = v_nome, compartilhado = coalesce((p_dashboard ->> 'compartilhado')::boolean, false), widgets = v_w, atualizado_em = now() where x.id = d.id;
return crm.res(true, 'Dashboard salvo.', jsonb_build_object('dashboardId', d.id)); end if;
perform set_config('crm.resumo', format('Criou o dashboard %s', v_nome), true);
insert into crm.dashboard (nome, dono_id, compartilhado, widgets) values (v_nome, v_eu, coalesce((p_dashboard ->> 'compartilhado')::boolean, false), v_w) returning id into v_id;
return crm.res(true, 'Dashboard criado.', jsonb_build_object('dashboardId', v_id));
end $$;
create function public.crm_arquivar_dashboard(p_dashboard uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); v_r jsonb; d crm.dashboard%rowtype; v_s text; v_c text; v_m text;
begin
v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
select * into d from crm.dashboard x where x.id = p_dashboard and x.arquivado_em is null for update;
if not found then return crm.res(false, 'Dashboard não encontrado.'); end if;
if not (d.dono_id = v_eu or coalesce(crm.eh_gestor(), false)) then return crm.res(false, 'Só o dono e o gestor excluem.'); end if;
perform set_config('crm.resumo', format('Excluiu o dashboard %s', d.nome), true);
update crm.dashboard x set arquivado_em = now(), atualizado_em = now() where x.id = p_dashboard;
return crm.res(true, 'Dashboard excluído.');
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation then
get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text; return crm.erro_dados(v_s, v_m, v_c);
end $$;
revoke all on function public.crm_mover_etapa(uuid,uuid), public.crm_criar_negocio(uuid,uuid,uuid), public.crm_salvar_dashboard(jsonb), public.crm_arquivar_dashboard(uuid) from public, anon;
grant execute on function public.crm_mover_etapa(uuid,uuid), public.crm_criar_negocio(uuid,uuid,uuid), public.crm_salvar_dashboard(jsonb), public.crm_arquivar_dashboard(uuid) to authenticated;
create temp table _v (k text primary key, u uuid, t text) on commit drop;
create function pg_temp.v(p text) returns uuid language sql as $$ select u from pg_temp._v where k = p $$;
create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
execute 'set local role authenticated'; execute p_sql into v; execute 'reset role';
return v;
exception when others then return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;
create function pg_temp.explica(p_perfil uuid, p_sql text) returns setof text language plpgsql as $$
declare r record;
begin
perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
execute 'set local role authenticated';
for r in execute 'explain (analyze, buffers, costs off, timing on) ' || p_sql loop return next r."QUERY PLAN"; end loop;
execute 'reset role';
end $$;
insert into _v (k, u) select 'gestor', p.id from public.perfis p where p.cargo = 'admin' and p.status = 'ativo' and p.nome ilike 'jonathan%' order by p.criado_em limit 1;
insert into _v (k, u) select 'mp', v.perfil_id from crm.vendedor v where v.sigla = 'mp';
insert into _v (k, u) select 'ro', v.perfil_id from crm.vendedor v where v.sigla = 'ro';
update crm.config set escrita_ligada = true;
-- B0: dashboard (refaz o passo 11.dash_excluir chamando a RPC ANTES de conferir)
do $b0$
declare j jsonb; v_d uuid;
begin
j := pg_temp.chamar(pg_temp.v('mp'), 'select public.crm_salvar_dashboard(''{"id":"novo","nome":"Ensaio","widgets":[]}'')');
v_d := (j ->> 'dashboardId')::uuid;
j := pg_temp.chamar(pg_temp.v('ro'), format('select public.crm_arquivar_dashboard(%L)', v_d));
perform pg_temp.ok('B0.dash_B_exclui_A', j ->> 'msg' = 'Só o dono e o gestor excluem.', j::text);
j := pg_temp.chamar(pg_temp.v('mp'), format('select public.crm_arquivar_dashboard(%L)', v_d));
perform pg_temp.ok('B0.dash_excluir', j ->> 'msg' = 'Dashboard excluído.' and (select arquivado_em is not null from crm.dashboard where id = v_d), j::text || ' · arquivado, não apagado');
j := pg_temp.chamar(pg_temp.v('mp'), format('select public.crm_arquivar_dashboard(%L)', v_d));
perform pg_temp.ok('B0.dash_excluir_2x', j ->> 'msg' = 'Dashboard não encontrado.', j::text);
end $b0$;
-- B1: massa 10× (20 mil pessoas teste, 20 mil camadas comerciais, 30 mil negócios num funil só = pior caso da contagem)
alter table crm.negocio disable trigger user;
alter table crm.pessoa_comercial disable trigger user;
alter table crm.funil disable trigger user;
alter table crm.etapa_funil disable trigger user;
alter table crm.distribuicao disable trigger user;
insert into crm.funil (nome, agrupador_id, linha, tipo) select 'Ensaio massa', a.id, 'ht', 'manual' from crm.agrupador a order by a.ordem limit 1;
insert into _v (k, u) select 'f', id from crm.funil where nome = 'Ensaio massa';
insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, campos_obrigatorios)
select pg_temp.v('f'), o, 'Etapa ' || o, case o when 5 then 'fechado' when 0 then 'primeiro_contato' else 'qualificar' end, 'info',
case when o = 2 then array['perfil_profissional'] else '{}' end from generate_series(0, 5) o;
insert into crm.distribuicao (funil_id, vendedor_id, percentual) values (null, pg_temp.v('mp'), 70), (null, pg_temp.v('ro'), 30);
create temp table _p on commit drop as
with x as (insert into pessoas.pessoas (nome, teste) select 'Ensaio Massa ' || g, true from generate_series(1, 20000) g returning id)
select id, row_number() over () rn from x;
insert into crm.pessoa_comercial (pessoa_id, dono_id, criado_em)
select id, case when rn % 10 < 7 then pg_temp.v('mp') when rn % 10 < 9 then pg_temp.v('ro') end, now() - (rn % 60) * interval '1 day' from _p where rn > 2;
insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, status, dono_id, campos, criado_em, etapa_desde)
select p.id, pg_temp.v('f'), (select id from crm.etapa_funil where funil_id = pg_temp.v('f') and ordem = 1), 'ht', 'venda_ativa', 'aberto',
case when p.rn % 10 < 7 then pg_temp.v('mp') else pg_temp.v('ro') end, '{"perfil_profissional":"advogado"}', now() - (p.rn % 60) * interval '1 day', now()
from _p p where p.rn > 2;
insert into crm.negocio (pessoa_id, funil_id, etapa_id, linha, origem, status, dono_id, motivo_perda, fechado_em, criado_em, etapa_desde)
select p.id, pg_temp.v('f'), (select id from crm.etapa_funil where funil_id = pg_temp.v('f') and ordem = 1), 'ht', 'venda_ativa', 'perdido',
case when p.rn % 10 < 7 then pg_temp.v('mp') else pg_temp.v('ro') end, 'fora_do_perfil', now(), now() - (p.rn % 60) * interval '1 day', now()
from _p p where p.rn between 3 and 10002;
alter table crm.negocio enable trigger user;
alter table crm.pessoa_comercial enable trigger user;
alter table crm.funil enable trigger user;
alter table crm.etapa_funil enable trigger user;
alter table crm.distribuicao enable trigger user;
analyze crm.negocio; analyze crm.pessoa_comercial; analyze pessoas.pessoas;
insert into _v (k, u) select 'pa', id from _p where rn = 1;
insert into _v (k, u) select 'pb', id from _p where rn = 2;
insert into _v (k, u) select 'nm', n.id from crm.negocio n join _p p on p.id = n.pessoa_id where p.rn = 13 and n.status = 'aberto';
insert into _v (k, u) select 'nm2', n.id from crm.negocio n join _p p on p.id = n.pessoa_id where p.rn = 23 and n.status = 'aberto';
insert into _v (k, u) select 'e3', id from crm.etapa_funil where funil_id = pg_temp.v('f') and ordem = 3;
insert into _z_out (passo, linha) select 'B1.massa', format('massa: %s negócios no funil (%s abertos), %s camadas comerciais, %s pessoas teste',
(select count(*) from crm.negocio where funil_id = pg_temp.v('f')), (select count(*) from crm.negocio where funil_id = pg_temp.v('f') and status = 'aberto'),
(select count(*) from crm.pessoa_comercial), (select count(*) from _p));
-- B2: crm_criar_negocio (gestor, pessoa sem dono → distribuição conta 30 mil negócios do funil) 2×
insert into _z_out (passo, linha) select 'B2.criar_negocio_1', l from pg_temp.explica(pg_temp.v('gestor'), format('select public.crm_criar_negocio(%L, %L)', pg_temp.v('pa'), pg_temp.v('f'))) l;
insert into _z_out (passo, linha) select 'B2.criar_negocio_2', l from pg_temp.explica(pg_temp.v('gestor'), format('select public.crm_criar_negocio(%L, %L)', pg_temp.v('pb'), pg_temp.v('f'))) l;
do $b2$ begin
perform pg_temp.ok('B2.criados', (select count(*) from crm.negocio where pessoa_id in (pg_temp.v('pa'), pg_temp.v('pb'))) = 2, 'os 2 negócios foram criados');
end $b2$;
-- B2b: a consulta interna da distribuição (contagem por vendedor) 2×
insert into _z_out (passo, linha) select 'B2b.contagem', l from pg_temp.explica(pg_temp.v('gestor'),
format('select count(*) from crm.negocio n where n.dono_id = %L and n.criado_em >= (select ciclo_distribuicao_desde from crm.config) and n.funil_id = %L', pg_temp.v('mp'), pg_temp.v('f'))) l;
-- B3: crm_mover_etapa (vendedor dono, etapa 1 → 3 com campo obrigatório preenchido) 2×
insert into _z_out (passo, linha) select 'B3.mover_1', l from pg_temp.explica(pg_temp.v('mp'), format('select public.crm_mover_etapa(%L, %L)', pg_temp.v('nm'), pg_temp.v('e3'))) l;
insert into _z_out (passo, linha) select 'B3.mover_2', l from pg_temp.explica(pg_temp.v('mp'), format('select public.crm_mover_etapa(%L, %L)', pg_temp.v('nm2'), pg_temp.v('e3'))) l;
do $b3$ begin
perform pg_temp.ok('B3.movidos', (select count(*) from crm.negocio where id in (pg_temp.v('nm'), pg_temp.v('nm2')) and etapa_id = pg_temp.v('e3')) = 2, 'os 2 negócios mudaram de etapa');
end $b3$;
select passo, linha from _z_out order by n;
rollback;

-- ═══ PARTE C: nada persistiu (chamada separada, só leitura) ════════════════════════════════════════════════════════
select (select escrita_ligada from crm.config) escrita_ligada, (select notificacao_cron_ligado from crm.config) cron_ligado,
       (select count(*) from crm.negocio) negocios, (select count(*) from crm.distribuicao) distribuicao, (select count(*) from crm.funil) funis,
       (select count(*) from crm.agrupador where nome ilike 'ensaio%') agrup_ensaio, (select count(*) from crm.pessoa_comercial) pc,
       (select count(*) from crm.notificacao) notif, (select count(*) from crm.dashboard) dash, (select count(*) from crm.motivo_perda) motivos,
       (select bool_and(ativo) from crm.motivo_perda) motivos_ativos, (select count(*) from crm.produto_comercial) prod,
       (select count(*) from crm.oferta_comercial) ofertas, (select count(*) from pessoas.pessoas where nome like 'Ensaio%') pessoas_ensaio,
       to_regprocedure('public.crm_mover_etapa(uuid,uuid)') rpc_escrita, to_regprocedure('crm.guarda_escrita()') helper,
       (select count(*) from pg_trigger where tgname in ('negocio_regras','negocio_notifica_ins','distribuicao_soma')) triggers_f2;
-- Resultado em 06/10/2026: escrita_ligada=false, cron_ligado=false, negocios=0, distribuicao=0, funis=0, agrup_ensaio=0,
-- pc=0, notif=0, dash=0, motivos=9 (todos ativos), prod=0, ofertas=0, pessoas_ensaio=0, rpc_escrita=null, helper=null,
-- triggers_f2=0. (As 2 únicas linhas de crm.log fora de 'migracao' são o cadastro de mp/ro da F0.)
