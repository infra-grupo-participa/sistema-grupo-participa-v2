-- 20261005t: F2 do Comercial — RPCs de ESCRITA do CRM + triggers de regra + notificações por trigger
--
-- STATUS: APLICADA em 06/10/2026 — versão 20261006041654 (name crm_f2_escrita), md5 do statement gravado =
-- f75c175162c97e2f4187964800178502 (= este arquivo antes desta linha de STATUS). escrita_ligada continua false.
-- Ensaio: 20261005t_ensaio.sql (begin … rollback, em partes).
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
