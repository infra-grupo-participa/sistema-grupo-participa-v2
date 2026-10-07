-- 20261007e: Comercial — funil de ATIVAÇÃO padrão em todo projeto (a primeira jornada do lead na empresa).
--
-- STATUS: APLICADA em 07/10/2026 (uma apply_migration; versão gravada no nome do arquivo). Ensaio: <versão>_ensaio.sql
-- (begin … rollback, 37/37 ok). Decisões do Arthur: <versão>.explain.md.
-- Depende da 20261007123627_crm_projeto_atm (APLICADA). Corpo das funções recriadas lido VIVO em 07/10/2026
-- (md5 do prosrc conferido na guarda).
--
-- Processo: gp-operacoes, comercial/areas/prospeccao/processos/acompanhar-mql-ate-o-evento.md (três toques, o mesmo
-- vendedor do começo ao fim e na recuperação, só pelo número oficial, desapegar 24 h, nunca mencionar replay), com a
-- correção do Arthur (07/10/2026): o toque 1 sai NA HORA da entrada, com o prazo de primeiro contato do playbook
-- (5 min / 15 min em horário comercial); fora do horário, vence na abertura do próximo expediente.
--
-- DECISÕES DO ARTHUR (07/10/2026, ver explain): horário seg–sex 8h–20h, sáb 9h–13h, domingo e feriado fechados
-- (crm.config.expediente + crm.feriado); fim da Ativação = dia seguinte ao FECHAMENTO DO CARRINHO (sem ele, o fim do
-- evento); datas lidas de mkt.projetos (etiqueta_clickup = chave) com o CRM como fallback; MQL pela catalogação
-- (crm.mql_do_evento, versão mínima false); Respondi cria contato novo; teto 50 conversas novas/número/dia.
--
-- O QUE ENTRA
--   1. crm.modelo_funil 'ativacao' (6 etapas; a única de Ganho é "Comprou", que só a Hotmart fecha) e
--      'captacao_mql' sai de lancamento_classico/seminario (a Ativação faz o mesmo acompanhamento; o modelo fica).
--   2. crm.projeto_ativacao: por projeto (chave = funil.projeto): data e hora do evento, produtos da OFERTA da Hotmart
--      (saída "Comprou") e a fila de recuperação. NÃO guarda lista/tag/produto de entrada: isso é a catalogação de origem.
--      crm.ativacao_entrada: cada entrada recebida (fonte + ref únicos por projeto), com o resultado.
--   3. crm_criar_projeto: todo projeto nasce com o funil "<Projeto> · Ativação" (primeiro) e o cadastro.
--      crm_ativacao_garantir(projeto): acrescenta a projeto criado antes.
--   4. Entrada automática: a qual projeto o evento pertence quem diz é crm.projeto_do_evento(fonte, dados) → chave,
--      CONTRATO com a catalogação de origem (outro agente). Aqui nasce a versão mínima, que devolve null.
--      - AC: subscribe/contact_tag_added (trigger em crm.evento_jornada, quando o evento ganha pessoa — webhook e reprocessar);
--      - Hotmart: compra aprovada (trigger em crm.hotmart_processado, quando ganha pessoa), fora a oferta do próprio projeto;
--      - Respondi: resposta de pesquisa (trigger em respondi.respostas); quem não existe vira contato. MQL: crm.mql_do_evento.
--      Cria o negócio com dono pela distribuição (crm.escolher_dono: quem já é dono do contato continua), uma vez por
--      pessoa por projeto (aberto OU fechado), e o toque 1 (whatsapp) vencendo agora/na abertura do expediente.
--   5. Atividades: trigger em crm.negocio (insert no funil de ativação, troca de dono, fechamento) cria/reagenda toque 1,
--      toque 2 (ligação na sexta anterior ao evento, 10h) e toque 3 (cada dia do evento, 1 h antes; sem hora, 9h).
--      Troca de dono leva as atividades abertas junto (o mesmo dono do começo ao fim).
--   6. Saída: compra aprovada de produto da OFERTA do projeto fecha o negócio de ativação como ganho (hotmart_processar
--      prefere o negócio de ativação e tira os funis de ativação da regra geral por linha: o ingresso não vira ganho).
--      Carrinho fechou (dia seguinte ao fechamento; sem ele, ao fim do evento; cron diário) ou o gestor encerrou: quem está aberto vira perdido
--      "Evento encerrado sem compra" (motivo novo, reativa) e entra na fila de recuperação do projeto com o MESMO dono.
--   7. Leitura: crm_ativacao_painel() (D6: vendedor só conta os dele; carga do dia vs teto 50; disparos da
--      Mensageria no projeto hoje). Escrita: crm_ativacao_salvar, crm_ativacao_garantir, crm_ativacao_encerrar (gestor).
--   8. Kill-switch: crm.config.ativacao_ligada (NASCE false). Desligado: nenhuma entrada automática e o cron não encerra.
--
-- AS 5 PERGUNTAS (números no explain)
--   escala: por evento de webhook, 1 chamada a crm.projeto_do_evento + 1 entrada (só quando há projeto); atividades por
--     negócio ≤ 1 + 1 + 7. Painel: agregados por projeto com índices (funil_id/status, projeto/em, vence_em).
--   índice: negocio_aberto_uidx/negocio_pessoa_idx (dedupe), ativacao_entrada (projeto, fonte, ref) e (projeto, em),
--     atividade_negocio_idx, atividade_dono_aberta_idx; projeto_ativacao.funil_id unique.
--   frequência: webhook em tempo real (sem cron novo para entrada); 1 cron diário (encerrar), barato quando não há.
--   repetição: o mesmo evento reprocessado não duplica (unique em ativacao_entrada + 1 negócio por pessoa e projeto).
--   reversão: update crm.config set ativacao_ligada = false (~10 s); bloco REVERSÃO no fim.

-- ─── 0. Guardas de premissa ───────────────────────────────────────────────────────────────────────────────────────
do $g$
begin
  if to_regclass('crm.projeto_ativacao') is not null then raise exception '20261007e: já aplicada'; end if;
  if not exists (select 1 from crm.modelo_projeto where tipo = 'atm') then
    raise exception '20261007e: falta a 20261007123627_crm_projeto_atm';
  end if;
  if exists (select 1 from crm.modelo_funil where id = 'ativacao') then raise exception '20261007e: modelo ativacao já existe'; end if;
  if (select count(*) from crm.modelo_projeto) <> 7 then raise exception '20261007e: esperava 7 tipos de projeto'; end if;
  if (select count(*) from crm.modelo_projeto where tipo in ('lancamento_classico', 'seminario') and 'captacao_mql' = any(funis)) <> 2 then
    raise exception '20261007e: lancamento_classico/seminario sem captacao_mql (base mudou)';
  end if;
  if md5((select prosrc from pg_proc where oid = 'public.crm_criar_projeto(text,text,uuid,text)'::regprocedure)) <> '4528661f7ca9eb6d4d2a969ae63e4a10' then
    raise exception '20261007e: crm_criar_projeto mudou desde a leitura';
  end if;
  if md5((select prosrc from pg_proc where oid = 'crm.hotmart_processar(jsonb)'::regprocedure)) <> '26c950bf7304ca5e08cc9169c20d58a3' then
    raise exception '20261007e: crm.hotmart_processar mudou desde a leitura';
  end if;
  if exists (select 1 from crm.motivo_perda where chave = 'evento_sem_compra') then raise exception '20261007e: motivo já existe'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'ativacao_ligada') then
    raise exception '20261007e: crm.config.ativacao_ligada já existe';
  end if;
  if to_regclass('respondi.respostas') is null then raise exception '20261007e: falta respondi.respostas'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config' and column_name = 'expediente')
     or to_regclass('crm.feriado') is not null or to_regprocedure('crm.projeto_do_evento(text,jsonb)') is not null
     or to_regprocedure('crm.mql_do_evento(text,jsonb)') is not null then
    raise exception '20261007e: expediente/feriado/projeto_do_evento/mql_do_evento já existem';
  end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'mkt' and table_name = 'projetos'
                  and column_name in ('etiqueta_clickup', 'evento_inicio', 'evento_fim') group by table_name having count(*) = 3) then
    raise exception '20261007e: mkt.projetos sem etiqueta_clickup/evento_inicio/evento_fim';
  end if;
end
$g$;

-- ─── 1. Kill-switch, motivo, modelo ──────────────────────────────────────────────────────────────────────────────
alter table crm.config add column ativacao_ligada boolean not null default false;
comment on column crm.config.ativacao_ligada is
  '20261007e: false = nenhuma entrada automática no funil de Ativação e o cron não encerra eventos. Nasce false.';

-- Horário comercial (decisão 1): dia ISO (1 = segunda … 7 = domingo) → [abre, fecha] em HH:MM de Brasília; dia ausente = fechado.
alter table crm.config add column expediente jsonb not null
  default '{"1":["08:00","20:00"],"2":["08:00","20:00"],"3":["08:00","20:00"],"4":["08:00","20:00"],"5":["08:00","20:00"],"6":["09:00","13:00"]}'::jsonb
  check (jsonb_typeof(expediente) = 'object');
comment on column crm.config.expediente is
  '20261007e: horário comercial por dia ISO (1=seg…7=dom) → ["HH:MM","HH:MM"] em Brasília. Ausente = fechado. Feriados: crm.feriado.';

create table crm.feriado (
  dia  date primary key,
  nome text not null check (length(btrim(nome)) between 1 and 80)
);
comment on table crm.feriado is '20261007e: dias fechados do Comercial (feriados nacionais; acrescentar os da casa).';
insert into crm.feriado (dia, nome) values
  ('2026-10-12', 'Nossa Senhora Aparecida'), ('2026-11-02', 'Finados'), ('2026-11-15', 'Proclamação da República'),
  ('2026-11-20', 'Consciência Negra'), ('2026-12-25', 'Natal'),
  ('2027-01-01', 'Confraternização Universal'), ('2027-03-26', 'Sexta-feira Santa'), ('2027-04-21', 'Tiradentes'),
  ('2027-05-01', 'Dia do Trabalho'), ('2027-09-07', 'Independência'), ('2027-10-12', 'Nossa Senhora Aparecida'),
  ('2027-11-02', 'Finados'), ('2027-11-15', 'Proclamação da República'), ('2027-11-20', 'Consciência Negra'),
  ('2027-12-25', 'Natal');
alter table crm.feriado enable row level security;
revoke all on crm.feriado from public, anon, authenticated, service_role;

insert into crm.motivo_perda (chave, rotulo, reativa, bloqueia, alerta_gestor, nota, sistema, ativo, ordem)
values ('evento_sem_compra', 'Evento encerrado sem compra', true, false, false,
        'Ativação: o carrinho fechou e a pessoa não comprou. Vai para a fila de recuperação com o mesmo dono e para a reativação.', false, true, 11);

insert into crm.modelo_funil (id, nome, descricao, icone, tipo, eventos_hotmart, etapas, campanhas, ordem) values
('ativacao', 'Ativação', 'Primeira jornada do lead: quem se inscreveu, comprou o ingresso ou virou MQL recebe os três toques do mesmo vendedor até o evento. Toque 1 na hora da entrada.', 'user-check', 'manual', '{}'::text[], '[{"nome":"Toque 1: falar agora","papel":"primeiro_contato","cor":"red","slaAtencaoMin":5,"slaCriticoMin":15,"criterio":"Mensagem do toque 1 enviada: pediu para salvar o número","camposObrigatorios":[]},{"nome":"Salvou o número","papel":"qualificar","cor":"cyan","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Ligação da sexta anterior ao evento feita (5 blocos)","camposObrigatorios":[]},{"nome":"Ligação feita","papel":"qualificar","cor":"info","slaAtencaoMin":1440,"slaCriticoMin":2880,"criterio":"Confirmou presença. Sem resposta em 24 h: desapegar","camposObrigatorios":[]},{"nome":"Presença confirmada","papel":"apresentar_oferta","cor":"purple","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Esteve ao vivo no evento","camposObrigatorios":[]},{"nome":"Compareceu","papel":"negociar","cor":"accent","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"Comprou a oferta do evento (Hotmart aprova)","camposObrigatorios":[]},{"nome":"Comprou","papel":"fechado","cor":"green","slaAtencaoMin":null,"slaCriticoMin":null,"criterio":"","camposObrigatorios":[]}]'::jsonb, '[{"nome":"Inscrição {chave}","canal":"webhook","regra":"Inscrição no ActiveCampaign que a catalogação de origem liga a {chave}","ativa":true},{"nome":"Ingresso {chave}","canal":"hotmart","regra":"Compra aprovada do ingresso que a catalogação de origem liga a {chave}","ativa":true},{"nome":"Pesquisa MQL {chave}","canal":"formulario","regra":"Pesquisa de MQL que a catalogação de origem liga a {chave}","ativa":true}]'::jsonb, 0);

-- A Ativação (padrão de todo projeto) substitui "Captação e MQL" nos tipos que o tinham. O modelo antigo fica.
update crm.modelo_projeto set funis = array_remove(funis, 'captacao_mql') where tipo in ('lancamento_classico', 'seminario');

-- ─── 2. Tabelas ──────────────────────────────────────────────────────────────────────────────────────────────────
create table crm.projeto_ativacao (
  projeto           text primary key check (projeto ~ '^[a-z0-9-]{3,60}$'),
  nome              text not null check (length(btrim(nome)) between 1 and 80),
  funil_id          uuid not null unique references crm.funil(id) on delete restrict,
  linha             text not null references crm.linha(chave) on delete restrict,
  evento_inicio     date,
  evento_fim        date,
  evento_hora       time,
  carrinho_fim      date,   -- fechamento do carrinho (decisão 4); vazio = fim do evento
  hotmart_oferta    text[] not null default '{}' check (cardinality(hotmart_oferta) <= 20),   -- produtos da oferta: compra = "Comprou"
  ligado            boolean not null default true,
  fila_id           uuid references crm.fila(id) on delete restrict,
  encerrado_em      timestamptz,
  encerrado_por     uuid references public.perfis(id) on delete restrict,
  criado_em         timestamptz not null default now(),
  atualizado_em     timestamptz not null default now(),
  atualizado_por    uuid references public.perfis(id) on delete restrict,
  check ((evento_inicio is null) = (evento_fim is null)),
  check (evento_fim is null or (evento_fim >= evento_inicio and evento_fim - evento_inicio <= 6)),
  check (carrinho_fim is null or evento_inicio is null or carrinho_fim >= evento_inicio));
comment on table crm.projeto_ativacao is
  '20261007e: Ativação de cada projeto (chave = crm.funil.projeto): data/hora do evento e fechamento do carrinho (FALLBACK: '
  'vale mkt.projetos quando etiqueta_clickup = chave) e produtos da OFERTA (saída "Comprou"). '
  'A qual projeto um evento pertence NÃO mora aqui: crm.projeto_do_evento (catalogação de origem).';

create table crm.ativacao_entrada (
  id          bigint generated always as identity primary key,
  projeto     text not null references crm.projeto_ativacao(projeto) on delete restrict,
  pessoa_id   uuid not null references pessoas.pessoas(id) on delete restrict,
  fonte       text not null check (fonte in ('activecampaign', 'hotmart', 'respondi', 'manual')),
  ref         text not null check (length(ref) between 1 and 200),
  mql         boolean not null default false,
  resultado   text not null default 'pendente'
              check (resultado in ('pendente', 'negocio_criado', 'sem_dono', 'ja_tinha', 'opt_out')),
  negocio_id  uuid references crm.negocio(id) on delete restrict,
  em          timestamptz not null default now(),
  unique (projeto, fonte, ref)
);
create index ativacao_entrada_projeto_em_idx on crm.ativacao_entrada (projeto, em desc);
create index ativacao_entrada_pessoa_idx on crm.ativacao_entrada (pessoa_id);

-- Fechadas: só as funções abaixo leem/escrevem (o schema crm não é exposto à API).
alter table crm.projeto_ativacao enable row level security;
alter table crm.ativacao_entrada enable row level security;
revoke all on crm.projeto_ativacao, crm.ativacao_entrada from public, anon, authenticated, service_role;

-- ─── 3. Regras de tempo ──────────────────────────────────────────────────────────────────────────────────────────
-- Horário comercial (decisão 1): crm.config.expediente por dia da semana + crm.feriado. Agora, se aberto; senão a
-- abertura do próximo expediente (procura até 14 dias).
create function crm.ativacao_expediente(p timestamptz) returns timestamptz
language plpgsql stable set search_path = '' as $f$
declare v_l timestamp := p at time zone 'America/Sao_Paulo'; v_d date := (p at time zone 'America/Sao_Paulo')::date;
        v_hora time := (p at time zone 'America/Sao_Paulo')::time; v_exp jsonb; v_j jsonb; i int; v_ini time; v_fim time;
begin
  select c.expediente into v_exp from crm.config c;
  for i in 0..14 loop
    v_j := v_exp -> extract(isodow from v_d + i)::int::text;
    continue when v_j is null or jsonb_typeof(v_j) <> 'array' or exists (select 1 from crm.feriado f where f.dia = v_d + i);
    v_ini := (v_j ->> 0)::time; v_fim := (v_j ->> 1)::time;
    if i = 0 then
      if v_hora < v_ini then return (v_d + v_ini) at time zone 'America/Sao_Paulo'; end if;
      if v_hora < v_fim then return p; end if;
      continue;
    end if;
    return ((v_d + i) + v_ini) at time zone 'America/Sao_Paulo';
  end loop;
  return p;
end
$f$;

-- Datas efetivas do projeto (decisão 12): mkt.projetos (etiqueta_clickup = chave, evento válido) vence; o CRM é fallback.
-- Hora e fechamento do carrinho só existem no CRM (mkt.projetos não tem essas colunas). fim_ativacao = carrinho ou evento.
create function crm.ativacao_datas(p_projeto text)
returns table (inicio date, fim date, hora time, carrinho_fim date, fim_ativacao date, do_marketing boolean)
language sql stable set search_path = '' as $f$
  with mk as (
    select mp.evento_inicio, mp.evento_fim from mkt.projetos mp
     where mp.etiqueta_clickup = p_projeto and mp.ativo and mp.evento_inicio is not null and mp.evento_fim is not null
       and mp.evento_fim >= mp.evento_inicio and mp.evento_fim - mp.evento_inicio <= 6
     order by mp.id desc limit 1)
  select coalesce(mk.evento_inicio, pa.evento_inicio), coalesce(mk.evento_fim, pa.evento_fim), pa.evento_hora, pa.carrinho_fim,
         coalesce(pa.carrinho_fim, mk.evento_fim, pa.evento_fim), mk.evento_inicio is not null
    from crm.projeto_ativacao pa left join mk on true
   where pa.projeto = p_projeto;
$f$;

-- Uma atividade de toque: abre se não existe; se está aberta, acompanha o novo vencimento e o dono; feita, fica.
create function crm.ativacao_toque(p_negocio uuid, p_pessoa uuid, p_dono uuid, p_tipo text, p_titulo text, p_vence timestamptz)
returns int language plpgsql set search_path = '' as $f$
declare v_id uuid; v_feita boolean;
begin
  select a.id, a.concluida_em is not null into v_id, v_feita from crm.atividade a
   where a.negocio_id = p_negocio and a.titulo = p_titulo order by a.concluida_em is null desc, a.criado_em desc limit 1;
  if v_id is null then
    insert into crm.atividade (negocio_id, pessoa_id, dono_id, tipo, titulo, vence_em, criado_por)
    values (p_negocio, p_pessoa, p_dono, p_tipo, p_titulo, p_vence, null);
    return 1;
  end if;
  if not v_feita then
    update crm.atividade a set vence_em = p_vence, dono_id = p_dono
     where a.id = v_id and (a.vence_em, a.dono_id) is distinct from (p_vence, p_dono);
  end if;
  return 0;
end
$f$;

-- Os três toques de um negócio de ativação aberto e com dono. Idempotente: chamar de novo só acerta datas e dono.
create function crm.ativacao_agendar(p_negocio uuid) returns int
language plpgsql set search_path = '' as $f$
declare n crm.negocio%rowtype; pa crm.projeto_ativacao%rowtype; v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
        v_sexta date; v_volta int; v_venc timestamptz; v_d date; v_i int; v_min int; v_tit text; v_n int := 0;
        v_validos text[] := '{}'; dt record;
begin
  select * into n from crm.negocio x where x.id = p_negocio;
  if not found or n.status <> 'aberto' or n.dono_id is null then return 0; end if;
  select * into pa from crm.projeto_ativacao x where x.funil_id = n.funil_id;
  if not found then return 0; end if;
  select * into dt from crm.ativacao_datas(pa.projeto);
  perform set_config('crm.resumo', format('Ativação de %s: toques agendados para %s', pa.nome, crm.nome_perfil(n.dono_id)), true);

  -- toque 1: na hora (ou na abertura do expediente); um só por negócio
  if not exists (select 1 from crm.atividade a where a.negocio_id = n.id and a.titulo like 'Toque 1:%') then
    v_n := v_n + crm.ativacao_toque(n.id, n.pessoa_id, n.dono_id, 'whatsapp', 'Toque 1: mensagem agora (salvar o número)',
                                    crm.ativacao_expediente(now()));
  else
    update crm.atividade a set dono_id = n.dono_id where a.negocio_id = n.id and a.titulo like 'Toque 1:%'
       and a.concluida_em is null and a.dono_id is distinct from n.dono_id;
  end if;

  if dt.inicio is not null then
    -- toque 2: sexta ANTERIOR ao início, 10h; quem entra depois dela (e antes do evento), no próximo expediente
    if dt.inicio > v_hoje then
      v_volta := (extract(isodow from dt.inicio)::int - 5 + 7) % 7;
      v_sexta := dt.inicio - case when v_volta = 0 then 7 else v_volta end;
      v_venc := case when v_sexta > v_hoje then (v_sexta + time '10:00') at time zone 'America/Sao_Paulo'
                     else crm.ativacao_expediente(now()) end;
      v_tit := 'Toque 2: ligar (5 blocos)';
      v_n := v_n + crm.ativacao_toque(n.id, n.pessoa_id, n.dono_id, 'ligacao', v_tit, v_venc);
      v_validos := v_validos || v_tit;
    end if;
    -- toque 3: cada dia do evento, 1 h antes do início (sem hora: 9h). Dia que passou não entra.
    v_min := greatest(0, coalesce(extract(hour from dt.hora)::int * 60 + extract(minute from dt.hora)::int, 600) - 60);
    for v_i in 0 .. (dt.fim - dt.inicio) loop
      v_d := dt.inicio + v_i;
      continue when v_d < v_hoje;
      v_venc := greatest((v_d + make_interval(mins => v_min)) at time zone 'America/Sao_Paulo', now());
      v_tit := format('Toque 3 · dia %s: link no privado antes do grupo', v_i + 1);
      v_n := v_n + crm.ativacao_toque(n.id, n.pessoa_id, n.dono_id, 'whatsapp', v_tit, v_venc);
      v_validos := v_validos || v_tit;
    end loop;
  end if;

  -- toque 2/3 aberto que não vale mais (evento remarcado ou encurtado): encerrado, nunca apagado
  update crm.atividade a set concluida_em = now(), resultado = 'Encerrada: evento remarcado', cancelada = true
   where a.negocio_id = n.id and a.concluida_em is null
     and (a.titulo like 'Toque 2:%' or a.titulo like 'Toque 3 ·%') and not (a.titulo = any(v_validos));
  return v_n;
end
$f$;

-- ─── 4. Entrada ──────────────────────────────────────────────────────────────────────────────────────────────────
-- Uma pessoa = um negócio de ativação por projeto (aberto ou já fechado). Devolve o resultado gravado na entrada.
create function crm.ativacao_entrar(p_projeto text, p_pessoa uuid, p_fonte text, p_ref text, p_mql boolean, p_origem text)
returns text language plpgsql set search_path = '' as $f$
declare pa crm.projeto_ativacao%rowtype; v_atual uuid; v_g uuid[]; v_etapa uuid; v_dono uuid; v_pc uuid; v_utm jsonb;
        v_neg uuid; v_ins int; v_res text; v_camp uuid; v_canal text := current_setting('crm.canal', true);
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return 'desligada'; end if;
  select * into pa from crm.projeto_ativacao x where x.projeto = p_projeto;
  if not found or not pa.ligado or pa.encerrado_em is not null then return 'projeto_fechado'; end if;
  if (select d.fim_ativacao from crm.ativacao_datas(pa.projeto) d) < (now() at time zone 'America/Sao_Paulo')::date then
    return 'carrinho_fechou';
  end if;
  if not exists (select 1 from crm.funil f where f.id = pa.funil_id and f.ativo) then return 'funil_arquivado'; end if;
  v_atual := pessoas.atual(p_pessoa);
  if v_atual is null then return 'sem_pessoa'; end if;

  insert into crm.ativacao_entrada (projeto, pessoa_id, fonte, ref, mql) values (pa.projeto, v_atual, p_fonte, left(p_ref, 200), coalesce(p_mql, false))
  on conflict (projeto, fonte, ref) do nothing;
  get diagnostics v_ins = row_count;
  if v_ins = 0 then return 'duplicado'; end if;

  v_g := pessoas.grupo(v_atual);
  perform pg_advisory_xact_lock(hashtext('crm.dist:' || pa.funil_id::text));   -- o mesmo lock de crm_criar_negocio
  if exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(v_g) and pc.opt_out) then
    v_res := 'opt_out';
  elsif exists (select 1 from crm.negocio n where n.pessoa_id = any(v_g) and n.funil_id = pa.funil_id) then
    v_res := 'ja_tinha';
  else
    select e.id into v_etapa from crm.etapa_funil e where e.funil_id = pa.funil_id and e.arquivada_em is null order by e.ordem limit 1;
    if v_etapa is null then return 'funil_sem_etapa'; end if;
    perform set_config('crm.canal', p_fonte, true);   -- crm.tg_log: autor_tipo integracao
    v_dono := crm.escolher_dono(v_atual, pa.funil_id);
    v_pc := crm.garantir_pc(v_atual);
    if v_dono is not null then
      perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição, Ativação)', crm.nome_pessoa(v_atual), crm.nome_perfil(v_dono)), true);
      update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is null;
    end if;
    select pc.utm_primeira into v_utm from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;
    select c.id into v_camp from crm.campanha c where c.funil_id = pa.funil_id and c.ativa
       and c.canal = case p_fonte when 'activecampaign' then 'webhook' when 'hotmart' then 'hotmart' else 'formulario' end
     order by c.criado_em limit 1;
    perform set_config('crm.resumo', format('Ativação de %s: %s entrou (%s, dono: %s)', pa.nome, crm.nome_pessoa(v_atual), p_origem,
                                            coalesce(crm.nome_perfil(v_dono), 'sem dono')), true);
    insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, campos, utm, ultima_interacao_em)
    values (v_atual, pa.funil_id, v_etapa, v_camp, pa.linha, 'venda_ativa', v_dono, 0,
            jsonb_build_object('origem', left('Ativação · ' || p_origem, 200)), coalesce(v_utm, '{}'::jsonb), null)
    returning id into v_neg;   -- trigger zz_ativacao_ins cria o toque 1 (e 2/3 com data do evento)
    v_res := case when v_dono is null then 'sem_dono' else 'negocio_criado' end;
    perform set_config('crm.canal', coalesce(v_canal, ''), true);
  end if;
  update crm.ativacao_entrada x set resultado = v_res, negocio_id = v_neg
   where x.projeto = pa.projeto and x.fonte = p_fonte and x.ref = left(p_ref, 200);
  return v_res;
end
$f$;

-- A QUAL PROJETO o evento pertence. Contrato com a CATALOGAÇÃO DE ORIGEM (outro agente, migration própria), que vai
-- SUBSTITUIR este corpo (create or replace, mesma assinatura) com as regras lista/tag do AC, produto da Hotmart,
-- funil da Clint e UTM → projeto. Versão MÍNIMA: devolve null (nenhum evento entra sozinho até a catalogação existir).
--   p_fonte: 'activecampaign' | 'hotmart' | 'respondi'
--   p_dados: AC {tipo, lista, tag, utm{source,medium,campaign,content}, eventoId}
--            Hotmart {classe, produtoId, ofertaCodigo, transacao, sck, chave}
--            Respondi {formSlug, respostaId}
--   devolve: a chave do projeto (crm.funil.projeto / crm.projeto_ativacao.projeto) ou null.
create function crm.projeto_do_evento(p_fonte text, p_dados jsonb) returns text
language sql stable set search_path = '' as $f$
  select null::text;
$f$;
comment on function crm.projeto_do_evento(text, jsonb) is
  '20261007e: versão mínima (null). Será substituída pela catalogação de origem (mesma assinatura).';

-- MQL (decisão 7): quais tags/listas valem como MQL em cada projeto é regra da catalogação de origem (controlada pelo
-- Victor Hugo). Contrato com a 20261007g, que SUBSTITUI este corpo (mesma assinatura). Versão mínima: false.
create function crm.mql_do_evento(p_fonte text, p_dados jsonb) returns boolean
language sql stable set search_path = '' as $f$
  select false;
$f$;
comment on function crm.mql_do_evento(text, jsonb) is
  '20261007e: versão mínima (false). Será substituída pela catalogação de origem (mesma assinatura).';

-- AC: inscrição (subscribe) ou tag. Dispara quando o evento ganha pessoa (webhook ou reprocessar).
create function crm.tg_ativacao_ac() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_dados jsonb; v_proj text;
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return null; end if;
  begin
    v_dados := jsonb_strip_nulls(jsonb_build_object('tipo', new.tipo, 'lista', nullif(nullif(btrim(coalesce(new.lista, '')), ''), '0'),
                                                    'tag', nullif(btrim(coalesce(new.tag, '')), ''), 'utm', new.dados -> 'utm',
                                                    'eventoId', new.id));
    v_proj := crm.projeto_do_evento('activecampaign', v_dados);
    if v_proj is not null then
      perform crm.ativacao_entrar(v_proj, new.pessoa_id, 'activecampaign', 'ej-' || new.id, crm.mql_do_evento('activecampaign', v_dados),
                                  case when new.tipo = 'subscribe' then 'inscrição na lista ' || coalesce(new.lista, '?')
                                       else 'tag ' || coalesce(new.tag, '?') end);
    end if;
  exception when others then
    raise warning 'crm.tg_ativacao_ac: evento % (%: %)', new.id, sqlstate, sqlerrm;   -- nunca derruba o webhook
  end;
  return null;
end
$f$;

create trigger zz_ativacao_ac after update on crm.evento_jornada for each row
  when (old.pessoa_id is null and new.pessoa_id is not null and new.fonte = 'activecampaign'
        and new.tipo in ('subscribe', 'contact_tag_added'))
  execute function crm.tg_ativacao_ac();

-- Hotmart: compra aprovada (venda nova; recorrência não) de produto que a catalogação liga a um projeto (o ingresso).
create function crm.tg_ativacao_hotmart() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_dados jsonb; v_proj text;
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return null; end if;
  if coalesce(new.resultado, '') like 'jornada: recorrência%' then return null; end if;
  begin
    v_dados := jsonb_strip_nulls(jsonb_build_object('classe', new.classe, 'produtoId', new.produto_id, 'ofertaCodigo', new.oferta_codigo,
                                                    'transacao', new.transacao, 'chave', new.chave));
    v_proj := crm.projeto_do_evento('hotmart', v_dados);
    -- compra da OFERTA do próprio projeto é saída ("Comprou", em hotmart_processar), não entrada
    if v_proj is not null and not exists (select 1 from crm.projeto_ativacao pa where pa.projeto = v_proj
                                                                                and new.produto_id = any(pa.hotmart_oferta)) then
      perform crm.ativacao_entrar(v_proj, new.pessoa_id, 'hotmart', 'hm-' || new.chave, crm.mql_do_evento('hotmart', v_dados),
                                  'ingresso comprado na Hotmart');
    end if;
  exception when others then
    raise warning 'crm.tg_ativacao_hotmart: % (%: %)', new.chave, sqlstate, sqlerrm;
  end;
  return null;
end
$f$;

create trigger zz_ativacao_hotmart after update on crm.hotmart_processado for each row
  when (old.pessoa_id is null and new.pessoa_id is not null and new.classe = 'aprovada')
  execute function crm.tg_ativacao_hotmart();

-- Respondi (decisão 8): quem responde a pesquisa e ainda não existe VIRA CONTATO (pessoas.registrar, fonte 'formulario':
-- o CHECK de pessoas.identificadores/eventos não tem 'respondi') e entra na Ativação do projeto. Só com projeto e e-mail.
create function crm.tg_ativacao_respondi() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_dados jsonb; v_proj text; v_pessoa uuid; v_email text; v_reg jsonb; v_canal text;
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return null; end if;
  begin
    v_email := pessoas.norm_email(new.email);
    if v_email is null then return null; end if;
    v_dados := jsonb_build_object('formSlug', new.form_slug, 'respostaId', new.uuid);
    v_proj := crm.projeto_do_evento('respondi', v_dados);
    if v_proj is null then return null; end if;
    perform pg_advisory_xact_lock(hashtext('pessoas.resolver:' || v_email));   -- a mesma trava de pessoas.resolver
    v_pessoa := crm.pessoa_por_email(v_email);
    if v_pessoa is null then
      v_reg := pessoas.registrar(jsonb_build_object('email', v_email, 'telefone', pessoas.norm_telefone(new.telefone),
                                                    'nome', coalesce(new.dados ->> 'nome', null), 'evento', 'lead'), 'formulario', null);
      if not coalesce((v_reg ->> 'ok')::boolean, false) or (v_reg ->> 'pessoa_id') is null then return null; end if;
      v_pessoa := (v_reg ->> 'pessoa_id')::uuid;
      v_canal := current_setting('crm.canal', true);
      perform set_config('crm.canal', 'respondi', true);   -- crm.tg_log: autor_tipo integracao
      perform crm.garantir_pc(v_pessoa);
      perform set_config('crm.canal', coalesce(v_canal, ''), true);
    end if;
    perform crm.ativacao_entrar(v_proj, v_pessoa, 'respondi', 'rs-' || new.uuid, crm.mql_do_evento('respondi', v_dados),
                                'pesquisa ' || coalesce(new.form_slug, ''));
  exception when others then
    raise warning 'crm.tg_ativacao_respondi: % (%: %)', new.uuid, sqlstate, sqlerrm;   -- nunca derruba a importação
  end;
  return null;
end
$f$;

create trigger zz_ativacao_respondi after insert on respondi.respostas for each row
  execute function crm.tg_ativacao_respondi();

-- Negócio novo no funil de ativação (automático ou à mão) ganha os toques; troca de dono leva os toques junto.
create function crm.tg_ativacao_negocio() returns trigger
language plpgsql security definer set search_path = '' as $f$
begin
  if not exists (select 1 from crm.projeto_ativacao pa where pa.funil_id = new.funil_id) then return null; end if;
  begin
    -- negócio fechou (comprou, perdeu, encerrou): os toques abertos saem da agenda do dono (encerrados, nunca apagados)
    if tg_op = 'UPDATE' and new.status <> 'aberto' then
      update crm.atividade a set concluida_em = now(), cancelada = true,
             resultado = case when new.status = 'ganho' then 'Encerrada: comprou' else 'Encerrada: negócio encerrado' end
       where a.negocio_id = new.id and a.concluida_em is null and a.titulo like 'Toque %';
      return null;
    end if;
    if tg_op = 'UPDATE' then
      update crm.atividade a set dono_id = new.dono_id
       where a.negocio_id = new.id and a.concluida_em is null and a.titulo like 'Toque %' and new.dono_id is not null;
    end if;
    perform crm.ativacao_agendar(new.id);
  exception when others then
    raise warning 'crm.tg_ativacao_negocio: % (%: %)', new.id, sqlstate, sqlerrm;   -- preserva a gravação do negócio
  end;
  return null;
end
$f$;

create trigger zz_ativacao_ins after insert on crm.negocio for each row
  when (new.status = 'aberto') execute function crm.tg_ativacao_negocio();
create trigger zz_ativacao_dono after update on crm.negocio for each row
  when (old.dono_id is distinct from new.dono_id and new.status = 'aberto') execute function crm.tg_ativacao_negocio();
create trigger zz_ativacao_fim after update on crm.negocio for each row
  when (old.status = 'aberto' and new.status <> 'aberto') execute function crm.tg_ativacao_negocio();

-- ─── 5. Saída ────────────────────────────────────────────────────────────────────────────────────────────────────
-- 5a. "Comprou": hotmart_processar prefere o negócio de ativação do projeto cuja OFERTA tem o produto, e tira os funis
--     de ativação da regra geral por linha. Recriado a partir do corpo VIVO (md5 conferido), trocando só este trecho.
do $h$
declare v_def text := pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure); v_novo text;
        v_de constant text := $de$      select * into n from crm.negocio x
       where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
       order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
       limit 1 for update;
      if found then$de$;
        v_para constant text := $para$      -- 20261007e: compra de produto da OFERTA de um projeto fecha o negócio de ATIVAÇÃO dele (mesmo dono);
      -- funil de ativação fica fora da regra geral por linha (o ingresso tem a linha do projeto e não é ganho)
      select x.* into n from crm.negocio x join crm.projeto_ativacao pa on pa.funil_id = x.funil_id
       where x.pessoa_id = any(v_g) and x.status = 'aberto' and (p ->> 'produto_id') = any(pa.hotmart_oferta)
       order by x.criado_em, x.id
       limit 1 for update of x;
      if not found then
        select * into n from crm.negocio x
         where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
           and not exists (select 1 from crm.projeto_ativacao pa where pa.funil_id = x.funil_id)
         order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
         limit 1 for update;
      end if;
      if found then$para$;
begin
  if (length(v_def) - length(replace(v_def, v_de, ''))) / length(v_de) <> 1 then
    raise exception '20261007e: trecho de hotmart_processar não encontrado exatamente 1 vez';
  end if;
  v_novo := replace(v_def, v_de, v_para);
  execute v_novo;
end
$h$;

-- 5b. Carrinho fechou (ou o gestor encerrou): abertos viram perdidos e vão para a fila de recuperação com o MESMO dono.
create function crm.ativacao_encerrar_projeto(p_projeto text, p_quem uuid) returns jsonb
language plpgsql set search_path = '' as $f$
declare pa crm.projeto_ativacao%rowtype; n crm.negocio%rowtype; v_fila uuid; v_perd int := 0; v_fila_n int := 0; v_k int;
        v_sinais text[];
begin
  select * into pa from crm.projeto_ativacao x where x.projeto = p_projeto for update;
  if not found then return null; end if;
  if pa.encerrado_em is not null then return jsonb_build_object('jaEncerrado', true); end if;
  v_fila := pa.fila_id;
  if v_fila is null then
    perform set_config('crm.resumo', format('Fila de recuperação da Ativação de %s', pa.nome), true);
    insert into crm.fila (nome, linha, projeto, criada_por) values (left('Recuperação · ' || pa.nome, 120), pa.linha, pa.projeto, p_quem)
    returning id into v_fila;
  end if;
  for n in select x.* from crm.negocio x where x.funil_id = pa.funil_id and x.status = 'aberto' order by x.criado_em for update loop
    perform set_config('crm.resumo', format('Evento de %s encerrado sem compra: %s vai para a recuperação com o mesmo dono',
                                            pa.nome, crm.nome_pessoa(n.pessoa_id)), true);
    update crm.negocio x set status = 'perdido', motivo_perda = 'evento_sem_compra', fechado_em = now(), atualizado_em = now(),
                             nota_perda = format('Ativação de %s encerrada em %s sem compra (carrinho fechado).', pa.nome, to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY'))
     where x.id = n.id;
    update crm.atividade a set concluida_em = now(), resultado = 'Encerrada: carrinho fechou', cancelada = true
     where a.negocio_id = n.id and a.concluida_em is null;
    v_perd := v_perd + 1;
    if not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(n.pessoa_id)) and pc.opt_out) then
      v_sinais := case when exists (select 1 from crm.ativacao_entrada e where e.projeto = pa.projeto and e.negocio_id = n.id and e.mql)
                         or exists (select 1 from crm.ativacao_entrada e where e.projeto = pa.projeto and e.pessoa_id = n.pessoa_id and e.mql)
                       then array['pesquisa'] else '{}'::text[] end;
      insert into crm.fila_item (fila_id, pessoa_id, score, sinais, responsavel_id)
      values (v_fila, n.pessoa_id, crm.score_recuperacao(v_sinais), v_sinais, n.dono_id)
      on conflict (fila_id, pessoa_id) do nothing;
      get diagnostics v_k = row_count;
      v_fila_n := v_fila_n + v_k;
    end if;
  end loop;
  update crm.projeto_ativacao x set encerrado_em = now(), encerrado_por = p_quem, fila_id = v_fila, atualizado_em = now()
   where x.projeto = pa.projeto;
  return jsonb_build_object('perdidos', v_perd, 'naFila', v_fila_n, 'filaId', v_fila);
end
$f$;

-- Cron diário: encerra a Ativação cujo carrinho fechou ontem (ou antes). Desligado com ativacao_ligada = false.
create function crm.ativacao_encerrar_vencidos() returns int
language plpgsql security definer set search_path = '' as $f$
declare r record; v int := 0;
begin
  if not coalesce((select c.ativacao_ligada from crm.config c), false) then return 0; end if;
  perform set_config('crm.canal', 'sistema', true);
  -- decisão 4: o dia seguinte ao FECHAMENTO DO CARRINHO (sem ele, ao fim do evento)
  for r in select pa.projeto from crm.projeto_ativacao pa cross join lateral crm.ativacao_datas(pa.projeto) d
            where pa.encerrado_em is null and d.fim_ativacao < (now() at time zone 'America/Sao_Paulo')::date loop
    perform crm.ativacao_encerrar_projeto(r.projeto, null);
    v := v + 1;
  end loop;
  return v;
end
$f$;

-- ─── 6. Funil de ativação de um projeto (usado por criar_projeto e por garantir) ─────────────────────────────────
create function crm.ativacao_criar_funil(p_projeto text, p_nome text, p_agrupador uuid, p_linha text, p_eu uuid) returns uuid
language plpgsql set search_path = '' as $f$
declare m crm.modelo_funil%rowtype; v_fid uuid;
begin
  select * into m from crm.modelo_funil x where x.id = 'ativacao';
  if not found then raise exception 'Modelo de ativação ausente.' using errcode = '23514'; end if;
  insert into crm.funil (nome, icone, projeto, agrupador_id, linha, tipo, eventos_hotmart, criado_por)
  values (p_nome || ' · ' || m.nome, m.icone, p_projeto, p_agrupador, p_linha, m.tipo, m.eventos_hotmart, p_eu)
  returning id into v_fid;
  insert into crm.etapa_funil (funil_id, ordem, nome, papel, cor, sla_atencao_min, sla_critico_min, campos_obrigatorios, criterio)
  select v_fid, x.ord, x.nome, x.papel, x.cor, x.sla_a, x.sla_c, x.campos, x.criterio from crm.etapas_payload(m.etapas) x order by x.ord;
  insert into crm.campanha (funil_id, nome, canal, regra, ativa)
  select v_fid, replace(x.nome, '{chave}', p_projeto), x.canal, replace(x.regra, '{chave}', p_projeto), x.ativa
    from crm.campanhas_payload(m.campanhas) x;
  -- datas: lidas ao vivo de mkt.projetos por crm.ativacao_datas; as do CRM são fallback (crm_ativacao_salvar)
  insert into crm.projeto_ativacao (projeto, nome, funil_id, linha, atualizado_por)
  values (p_projeto, p_nome, v_fid, p_linha, p_eu);
  return v_fid;
end
$f$;

-- ─── 7. crm_criar_projeto: todo projeto nasce com a Ativação (primeiro funil) ────────────────────────────────────
create or replace function public.crm_criar_projeto(p_tipo text, p_nome text, p_agrupador uuid, p_linha text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_eu uuid := auth.uid(); v_r jsonb; v_nome text := btrim(coalesce(p_nome, '')); v_chave text; pj crm.modelo_projeto%rowtype;
        m record; v_fid uuid; v_ids uuid[] := '{}'; v_funis text[]; v_s text; v_c text; v_m text;
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
  -- 20261007e: a Ativação é o primeiro funil de todo projeto, qualquer que seja o tipo
  v_funis := array['ativacao'] || array_remove(pj.funis, 'ativacao');
  if exists (select 1 from crm.modelo_funil mf where mf.id = any(v_funis) and length(v_nome || ' · ' || mf.nome) > 80) then
    return crm.res(false, 'Nome do projeto longo demais.');
  end if;
  if exists (select 1 from crm.funil f join crm.modelo_funil mf on f.nome = v_nome || ' · ' || mf.nome
              where f.ativo and mf.id = any(v_funis))
     or exists (select 1 from crm.projeto_ativacao pa where pa.projeto = v_chave) then
    return crm.res(false, 'Já existe projeto com esse nome.');
  end if;
  for m in select mf.*, u.i from unnest(v_funis) with ordinality u(mid, i) join crm.modelo_funil mf on mf.id = u.mid order by u.i loop
    perform set_config('crm.resumo', case when m.i = 1 then format('Começou o projeto %s (%s funis)', v_nome, cardinality(v_funis))
                                          else format('Criou o funil %s', v_nome || ' · ' || m.nome) end, true);
    if m.id = 'ativacao' then
      v_fid := crm.ativacao_criar_funil(v_chave, v_nome, p_agrupador, p_linha, v_eu);
      v_ids := v_ids || v_fid;
      continue;
    end if;
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
$function$;

-- ─── 8. RPCs da tela ─────────────────────────────────────────────────────────────────────────────────────────────
-- Lista de texto do payload: sem espaços nas pontas, sem vazios, sem repetidos, na ordem; tags em minúsculas.
create function crm.ativacao_lista(p jsonb, p_minusc boolean) returns text[]
language sql immutable set search_path = '' as $f$
  select coalesce(array_agg(v order by o), '{}') from (
    select distinct on (v) v, o from (
      select case when p_minusc then lower(btrim(x)) else btrim(x) end v, o
        from jsonb_array_elements_text(case when jsonb_typeof(p) = 'array' then p else '[]'::jsonb end) with ordinality t(x, o)) a
     where v <> '' order by v, o) b;
$f$;

create function public.crm_ativacao_painel() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_gestor boolean := coalesce(crm.eh_gestor(), false); v_eu uuid := auth.uid();
        v_ini timestamptz := ((now() at time zone 'America/Sao_Paulo')::date)::timestamp at time zone 'America/Sao_Paulo';
        v_fim timestamptz; v_proj jsonb; v_carga jsonb; v_total int; v_sem jsonb;
begin
  perform crm.exige_comercial();
  v_fim := v_ini + interval '1 day';
  select coalesce(jsonb_agg(jsonb_build_object(
           'projeto', pa.projeto, 'nome', pa.nome, 'funilId', pa.funil_id, 'produto', pa.linha,
           'eventoInicio', d.inicio, 'eventoFim', d.fim, 'eventoHora', to_char(d.hora, 'HH24:MI'), 'carrinhoFim', pa.carrinho_fim,
           'fimAtivacao', d.fim_ativacao, 'datasDoMarketing', d.do_marketing,
           'crmEventoInicio', pa.evento_inicio, 'crmEventoFim', pa.evento_fim,
           'hotmartOferta', to_jsonb(pa.hotmart_oferta), 'ligado', pa.ligado, 'encerradoEm', pa.encerrado_em, 'filaId', pa.fila_id,
           'porEtapa', coalesce((select jsonb_object_agg(q.etapa_id, q.c) from (
                          select n.etapa_id, count(*) c from crm.negocio n
                           where n.funil_id = pa.funil_id and n.status = 'aberto' and (v_gestor or n.dono_id = v_eu)
                           group by n.etapa_id) q), '{}'::jsonb),
           'entradasHoje', (select count(*) from crm.ativacao_entrada e left join crm.negocio n on n.id = e.negocio_id
                             where e.projeto = pa.projeto and e.em >= v_ini and e.resultado in ('negocio_criado', 'sem_dono')
                               and (v_gestor or n.dono_id = v_eu)),
           'mqls', (select count(distinct e.pessoa_id) from crm.ativacao_entrada e
                     where e.projeto = pa.projeto and e.mql
                       and (v_gestor or exists (select 1 from crm.negocio n where n.funil_id = pa.funil_id
                                                   and n.pessoa_id = e.pessoa_id and n.dono_id = v_eu))),
           'mensageriaHoje', (select count(*) from mkt_mensageria.disparos d join mkt.projetos mp on mp.id = d.projeto_id
                               where mp.etiqueta_clickup = pa.projeto and d.arquivado_em is null
                                 and d.enviado_em >= v_ini and d.enviado_em < v_fim))
         order by pa.encerrado_em is not null, d.inicio nulls last, pa.nome), '[]'::jsonb)
    into v_proj
    from crm.projeto_ativacao pa cross join lateral crm.ativacao_datas(pa.projeto) d;
  -- carga do dia: conversa nova = toque 1 que vence hoje (aberto ou feito hoje). Vendedor: só a dele.
  select coalesce(jsonb_agg(jsonb_build_object('vendedorId', q.dono_id, 'novasHoje', q.novas, 'toquesHoje', q.toques)), '[]'::jsonb)
    into v_carga
    from (select a.dono_id, count(*) filter (where a.titulo like 'Toque 1:%') novas, count(*) toques
            from crm.atividade a join crm.negocio n on n.id = a.negocio_id
            join crm.projeto_ativacao pa on pa.funil_id = n.funil_id
           where a.vence_em >= v_ini and a.vence_em < v_fim and not a.cancelada and (v_gestor or a.dono_id = v_eu)
           group by a.dono_id) q;
  -- teto é por NÚMERO: o total do dia sai para todos (número, sem dado de pessoa)
  select count(*) into v_total from crm.atividade a join crm.negocio n on n.id = a.negocio_id
    join crm.projeto_ativacao pa on pa.funil_id = n.funil_id
   where a.vence_em >= v_ini and a.vence_em < v_fim and not a.cancelada and a.titulo like 'Toque 1:%';
  select case when v_gestor then coalesce(jsonb_agg(distinct f.projeto), '[]'::jsonb) else '[]'::jsonb end into v_sem
    from crm.funil f where f.ativo and f.projeto is not null
     and not exists (select 1 from crm.projeto_ativacao pa where pa.projeto = f.projeto);
  return jsonb_build_object('projetos', v_proj, 'carga', v_carga, 'totalNovasHoje', v_total, 'semAtivacao', v_sem,
                            'ligada', coalesce((select c.ativacao_ligada from crm.config c), false));
end
$f$;

create function public.crm_ativacao_salvar(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r jsonb; v_eu uuid := auth.uid(); pa crm.projeto_ativacao%rowtype; v_proj text; v_ini date; v_fim date; v_hora time;
        v_ofe text[]; v_ligado boolean; v_n int := 0; r record; v_s text; v_c text; v_m text; v_carr date; dt record;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor configura a ativação.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;
  v_proj := lower(btrim(coalesce(p ->> 'projeto', '')));
  select * into pa from crm.projeto_ativacao x where x.projeto = v_proj for update;
  if not found then return crm.res(false, 'Projeto sem ativação.'); end if;
  if pa.encerrado_em is not null then return crm.res(false, 'Ativação encerrada não muda.'); end if;
  v_ini := nullif(p ->> 'eventoInicio', '')::date;
  v_fim := nullif(p ->> 'eventoFim', '')::date;
  v_hora := nullif(p ->> 'eventoHora', '')::time;
  v_carr := nullif(p ->> 'carrinhoFim', '')::date;
  v_ofe := crm.ativacao_lista(p -> 'hotmartOferta', false);
  v_ligado := coalesce((p ->> 'ligado')::boolean, true);
  -- as mesmas mensagens de validarAtivacao (domain/ativacao.ts)
  if (v_ini is null) <> (v_fim is null) then return crm.res(false, 'Preencha o início e o fim do evento, ou nenhum.'); end if;
  if v_fim < v_ini then return crm.res(false, 'O fim do evento vem antes do início.'); end if;
  if v_fim - v_ini > 6 then return crm.res(false, 'Evento de até 7 dias.'); end if;
  if exists (select 1 from unnest(v_ofe) x where x !~ '^[0-9]{1,20}$') then
    return crm.res(false, 'Produto da Hotmart é o número do produto.');
  end if;
  select * into dt from crm.ativacao_datas(pa.projeto);
  if v_ligado and coalesce(v_ini, case when dt.do_marketing then dt.inicio end) is null then
    return crm.res(false, 'Ativação ligada precisa da data do evento.');
  end if;
  if v_carr is not null and v_carr < coalesce(case when dt.do_marketing then dt.inicio end, v_ini, v_carr) then
    return crm.res(false, 'O carrinho não fecha antes do início do evento.');
  end if;
  perform set_config('crm.resumo', format('Configurou a ativação de %s', pa.nome), true);
  update crm.projeto_ativacao x set evento_inicio = v_ini, evento_fim = v_fim, evento_hora = v_hora, carrinho_fim = v_carr, hotmart_oferta = v_ofe,
         ligado = v_ligado, atualizado_em = now(), atualizado_por = v_eu
   where x.projeto = pa.projeto;
  for r in select n.id from crm.negocio n where n.funil_id = pa.funil_id and n.status = 'aberto' and n.dono_id is not null loop
    perform crm.ativacao_agendar(r.id);
    v_n := v_n + 1;
  end loop;
  return crm.res(true, format('Ativação de %s salva.%s', pa.nome,
                              case when v_n > 0 then format(' Toques de %s negócio(s) reagendados.', v_n) else '' end));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$f$;

create function public.crm_ativacao_garantir(p_projeto text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r jsonb; v_eu uuid := auth.uid(); v_proj text := lower(btrim(coalesce(p_projeto, ''))); f crm.funil%rowtype;
        v_nome text; v_fid uuid; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor acrescenta a ativação.'); end if;
  select x.funil_id into v_fid from crm.projeto_ativacao x where x.projeto = v_proj;
  if v_fid is not null then return crm.res(true, 'Este projeto já tem a Ativação.', jsonb_build_object('funilId', v_fid)); end if;
  select * into f from crm.funil x where x.projeto = v_proj and x.ativo order by x.criado_em, x.id limit 1;
  if not found then return crm.res(false, 'Projeto não encontrado.'); end if;
  v_nome := btrim(split_part(f.nome, ' · ', 1));
  if v_nome = '' or length(v_nome || ' · Ativação') > 80 then return crm.res(false, 'Nome do projeto longo demais.'); end if;
  if exists (select 1 from crm.funil x where x.ativo and x.nome = v_nome || ' · Ativação') then
    return crm.res(false, 'Já existe um funil com o nome da Ativação deste projeto.');
  end if;
  perform set_config('crm.resumo', format('Acrescentou a Ativação ao projeto %s', v_nome), true);
  v_fid := crm.ativacao_criar_funil(v_proj, v_nome, f.agrupador_id, f.linha, v_eu);
  return crm.res(true, format('Funil de Ativação criado para %s.', v_nome), jsonb_build_object('funilId', v_fid));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$f$;

create function public.crm_ativacao_encerrar(p_projeto text) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_r jsonb; v jsonb; v_s text; v_c text; v_m text;
begin
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if not coalesce(crm.eh_gestor(), false) then return crm.res(false, 'Só o gestor encerra a ativação.'); end if;
  v := crm.ativacao_encerrar_projeto(lower(btrim(coalesce(p_projeto, ''))), auth.uid());
  if v is null then return crm.res(false, 'Projeto sem ativação.'); end if;
  if v ? 'jaEncerrado' then return crm.res(false, 'Esta ativação já foi encerrada.'); end if;
  return crm.res(true, format('Ativação encerrada: %s sem compra, %s na fila de recuperação com o mesmo dono.',
                              v ->> 'perdidos', v ->> 'naFila'), jsonb_build_object('filaId', v ->> 'filaId'));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$f$;

-- ─── 9. Permissões ───────────────────────────────────────────────────────────────────────────────────────────────
revoke all on function crm.ativacao_expediente(timestamptz), crm.ativacao_toque(uuid, uuid, uuid, text, text, timestamptz),
  crm.ativacao_agendar(uuid), crm.ativacao_entrar(text, uuid, text, text, boolean, text), crm.tg_ativacao_ac(),
  crm.projeto_do_evento(text, jsonb), crm.mql_do_evento(text, jsonb), crm.ativacao_datas(text),
  crm.tg_ativacao_hotmart(), crm.tg_ativacao_respondi(), crm.tg_ativacao_negocio(), crm.ativacao_encerrar_projeto(text, uuid),
  crm.ativacao_encerrar_vencidos(), crm.ativacao_criar_funil(text, text, uuid, text, uuid), crm.ativacao_lista(jsonb, boolean)
  from public, anon, authenticated, service_role;
revoke all on function public.crm_ativacao_painel(), public.crm_ativacao_salvar(jsonb), public.crm_ativacao_garantir(text),
  public.crm_ativacao_encerrar(text) from public, anon;
grant execute on function public.crm_ativacao_painel(), public.crm_ativacao_salvar(jsonb), public.crm_ativacao_garantir(text),
  public.crm_ativacao_encerrar(text) to authenticated, service_role;

-- ─── 10. Cron (SQL, não HTTP: ops.cron_post não se aplica; o vigia registra pela agenda) ──────────────────────────
select cron.schedule('crm-ativacao-encerrar', '0 9 * * *', 'select crm.ativacao_encerrar_vencidos()');

-- ─── 11. Conferência ─────────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare v text;
begin
  if not exists (select 1 from crm.modelo_funil where id = 'ativacao' and jsonb_array_length(etapas) = 6) then
    raise exception '20261007e: modelo ativacao incompleto';
  end if;
  if exists (select 1 from crm.modelo_projeto where 'captacao_mql' = any(funis)) then raise exception '20261007e: captacao_mql ficou'; end if;
  if position('projeto_ativacao' in (select prosrc from pg_proc where oid = 'crm.hotmart_processar(jsonb)'::regprocedure)) = 0 then
    raise exception '20261007e: hotmart_processar sem a regra da ativação';
  end if;
  select proacl::text into v from pg_proc where oid = 'crm.hotmart_processar(jsonb)'::regprocedure;
  if v <> '{postgres=X/postgres}' then raise exception '20261007e: acl de hotmart_processar mudou: %', v; end if;
  select proacl::text into v from pg_proc where oid = 'public.crm_criar_projeto(text,text,uuid,text)'::regprocedure;
  if v <> '{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}' then
    raise exception '20261007e: acl de crm_criar_projeto mudou: %', v;
  end if;
  if exists (select 1 from pg_proc p join pg_namespace s on s.oid = p.pronamespace
              where (s.nspname = 'crm' and (p.proname like 'ativacao%' or p.proname like 'tg_ativacao%' or p.proname in ('projeto_do_evento', 'mql_do_evento')))
                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '20261007e: função interna executável por anon/authenticated';
  end if;
  if exists (select 1 from pg_proc p where p.proname like 'crm_ativacao%' and has_function_privilege('anon', p.oid, 'execute')) then
    raise exception '20261007e: RPC executável por anon';
  end if;
  if (select count(*) from pg_proc where proname = 'crm_criar_projeto') <> 1 then raise exception '20261007e: sobrecarga de crm_criar_projeto'; end if;
end
$c$;

-- ─── REVERSÃO (manual, nesta ordem; nada de dado de pessoa se perde: negócios/atividades criados ficam) ───────────
-- update crm.config set ativacao_ligada = false;                           -- 1º, sempre: desliga em ~10 s
-- select cron.unschedule('crm-ativacao-encerrar');
-- drop trigger zz_ativacao_ac on crm.evento_jornada; drop trigger zz_ativacao_hotmart on crm.hotmart_processado;
-- drop trigger zz_ativacao_respondi on respondi.respostas;
-- drop trigger zz_ativacao_ins on crm.negocio; drop trigger zz_ativacao_dono on crm.negocio; drop trigger zz_ativacao_fim on crm.negocio;
-- hotmart_processar: recriar o corpo de 20261007123321 (trecho "select * into n … for update; if found then" sem a ativação).
-- crm_criar_projeto: recriar o corpo de 20261005t/20261007123627 (md5 4528661f7ca9eb6d4d2a969ae63e4a10).
-- update crm.modelo_projeto set funis = array['captacao_mql'] || funis where tipo in ('lancamento_classico', 'seminario');
-- Tabelas e funis criados: NÃO apagar (há FK de negócio). Arquivar os funis de ativação pela tela, se for o caso.
