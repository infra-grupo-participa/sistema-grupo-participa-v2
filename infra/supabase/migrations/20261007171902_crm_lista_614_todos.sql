-- 20261007o: Comercial, a regra da lista 614 (Clínica de Miami) cataloga TODO MUNDO que entra na lista, não só quem já é
-- contato comercial.
--
-- STATUS: NÃO APLICADA. Ensaio: 20261007o_ensaio.sql (begin … rollback, 2 passadas). Relatório: 20261007o.explain.md.
-- 07/10/2026 ~16:40 UTC: ensaio rodado de novo (0 erro, mesmo resultado) e a APLICAÇÃO FOI NEGADA pela permissão da
-- sessão do agente (classificador do Claude Code, "Production Deploy"). Nada gravado (conferido: 0 em schema_migrations,
-- sem coluna para_todos, sem gatilho). Falta quem tenha permissão aplicar (docs/captura-de-lead.md, "Como aplicar").
--
-- POR QUE
--   Pedido do Victor Hugo (07/10/2026): catalogar todo mundo que entra na lista 614 do ActiveCampaign
--   ("Clínica Internacional Diamante Dez/26 - Leads Pré-Checkout", regra 42 de crm.catalogo_regra → clinica-miami-2026-12).
--   A catalogação (20261007141044) grava em crm.pessoa_origem, que é 1:1 com crm.pessoa_comercial (FK). O FILTRO mora em
--   dois lugares deste banco, nenhum fora deste repo:
--     a) crm.anexar_integracao (corpo vivo md5 de927520…): o evento do AC só abre contato comercial (crm.garantir_pc) quando
--        CRIA a pessoa ('pessoa_criada'). Quem já existe em pessoas (aluno, comprador, lead antigo) fica 'anexado' e não
--        ganha contato comercial;
--     b) crm.origem_recatalogar_pessoa / crm.origem_catalogar (gatilho zz_origem_ac_*): só recatalogam quem tem linha em
--        crm.pessoa_origem, isto é, quem tem crm.pessoa_comercial. Sem contato, a regra 42 nunca é avaliada.
--   Medido em 07/10/2026: 1 evento de entrada na lista 614, 1 pessoa, 0 com contato comercial, 0 catalogados em
--   clinica-miami-2026-12.
--
-- O QUE FAZ
--   1. crm.catalogo_regra.para_todos boolean not null default false (todas as regras existentes ficam false: nada muda
--      para elas). CHECK: só regra tipo 'projeto' de campo do AC (ac_lista, ac_tag) pode ser para_todos, porque o gatilho só
--      olha eventos do AC. true SÓ na regra 42 (premissa conferida: ac_lista contem "Clínica Internacional Diamante Dez/26"
--      → clinica-miami-2026-12, ativa, sem janela).
--   2. crm.catalogo_para_todos(campos, quando) → id da regra para_todos que casa os campos do evento (mesma comparação do
--      crm.catalogo_resolver: crm.catalogo_casa no valor e, para lista, no nome de crm.ac_lista), ou null.
--   3. Gatilho novo zz_origem_para_todos_{ins,upd} em crm.evento_jornada (AC, entrada: subscribe ou contact_tag_added,
--      pessoa recém-ligada): se o grupo da pessoa não tem contato comercial e o evento casa uma regra para_todos, abre o
--      contato com crm.garantir_pc (dica de canal 'activecampaign', como a anexar_integracao faz). O gatilho de
--      crm.pessoa_comercial (zz_origem_ins) cria a linha de origem e cataloga pelas evidências, como para qualquer contato.
--      Nunca derruba a gravação do evento (exception → warning), como os outros zz_origem_*.
--   4. Recataloga os que já entraram: para cada pessoa com evento de entrada do AC que casa regra para_todos e sem contato
--      comercial, crm.garantir_pc (o gatilho cataloga). Hoje: 1 pessoa. Guarda: aborta acima de 1.000.
--   NÃO recria nenhuma função existente (anexar_integracao, origem_catalogar, garantir_pc e catalogo_resolver ficam como
--   estão; o md5 delas é a premissa). NÃO cria negócio, NÃO atribui dono, NÃO mexe na Ativação (crm.projeto_ativacao não
--   tem clinica-miami-2026-12; o gatilho zz_ativacao_ac continua igual).
--
-- EFEITO QUE PRECISA SER SABIDO
--   - Quem entra na 614 sem ser contato vira contato comercial (aparece em Comercial > Contatos, sem dono e sem negócio).
--     É o mesmo que já acontece com lead novo do AC ('pessoa_criada'). Não manda Slack (crm.slack_enfileirar só é chamado
--     pela Hotmart e pelas estratégias); grava 1 linha em crm.log ("Abriu o contato comercial de …"), como hoje.
--   - O PROJETO catalogado segue a regra de sempre de crm.origem_catalogar: a PRIMEIRA evidência, em ordem de data, que
--     resolve. Contato antigo (ex.: comprou outro produto antes) pode continuar no projeto antigo; a lista 614 entra nas
--     chaves vistas. Só a abertura do contato é "para todos"; a ordem da catalogação não muda.
--
-- QUEM LÊ (grep no repo e no banco, 07/10/2026): crm.catalogo_regra é lida por crm.catalogo_resolver, crm.catalogo_mql,
--   crm.projeto_conhecido e pelas RPCs public.crm_catalogo / crm_catalogo_regra_salvar (tela do Comercial, campos
--   explícitos: a coluna nova não aparece nem é apagada pela tela). Nenhum outro repo (disparos-thb, controle-de-eventos)
--   cita catalogo_regra, pessoa_comercial, evento_jornada ou anexar_integracao. crm.evento_jornada é gravada só por
--   public.crm_integracao_receber (Edge Function crm-integracao-webhook deste repo) e crm_integracao_reprocessar.
--
-- AS 5 PERGUNTAS
--   escala: o gatilho roda 1 vez por evento de ENTRADA do AC ligado a pessoa (236 de 3.514 eventos do AC até hoje); custo =
--     1 leitura indexada de pessoa_comercial pelo grupo + 1 varredura das regras para_todos (1 linha). Contato aberto: só
--     para quem entra numa lista para_todos. Com 10x: igual por evento (não depende do tamanho das tabelas).
--   índice: pessoa_comercial pela PK (pessoa_id); catalogo_regra tem dezenas de linhas (seq scan é o certo). Explain no
--     ensaio.
--   frequência: a do webhook do AC (eventos chegam em lote de até 100).
--   repetição: 1 avaliação por evento; garantir_pc é idempotente (devolve o contato existente).
--   reversão: bloco REVERSÃO no fim (desligar a flag desliga tudo em segundos; drop do gatilho e da coluna volta o banco
--     ao estado anterior; contatos abertos não são apagados, ver o bloco).
--
-- IDEMPOTENTE: coluna/CHECK/funções/gatilhos com "if not exists"/"or replace"/"drop … if exists"; a regra 42 já com
--   para_todos = true passa; outra regra com para_todos = true aborta (alguém usou a flag: reler). A recatalogação só pega
--   quem ainda não tem contato, então a 2ª passada não faz nada.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- ─── 0. Guarda de premissa ────────────────────────────────────────────────────────────────────────────────────────
do $g$
declare r record; v_regra record; v_massa int;
begin
  if to_regclass('crm.catalogo_regra') is null or to_regclass('crm.pessoa_origem') is null
     or to_regclass('crm.evento_jornada') is null or to_regclass('crm.ac_lista') is null then
    raise exception '20261007o: falta a 20261007141044 (catalogo_regra / pessoa_origem / ac_lista) ou crm.evento_jornada';
  end if;
  -- corpos VIVOS lidos em 07/10/2026 (md5 do prosrc). O desenho depende de: anexar_integracao gravar o evento com
  -- pessoa_id nulo e ligar depois por UPDATE, sem abrir contato quando 'anexado'; garantir_pc ser idempotente; o gatilho de
  -- contato catalogar; catalogo_casa/campos_do_evento compararem como o resolver.
  for r in select * from (values
      ('crm.anexar_integracao(bigint,text)',       'de92752050e026cbb5b391b26430bc23'),
      ('crm.garantir_pc(uuid)',                    '9563837f8ad7d4094c74903a75a1415c'),
      ('crm.tg_origem_pc()',                       '0840f03a5b5b3727a831b155ede1aecd'),
      ('crm.origem_catalogar(uuid)',               'fa11e935604481c1fa2a0a25294f4960'),
      ('crm.catalogo_resolver(jsonb,timestamptz)', '9390d52b3d3ddf44b867239eb07a5d9c'),
      ('crm.catalogo_casa(text,text,text)',        '249f93a9696283ccfbbfc6f0ae09d03b'),
      ('crm.campos_do_evento(text,jsonb)',         'f6412fe77edb2c8c809c3f7a6e09e353'),
      ('public.crm_catalogo_regra_salvar(jsonb)',  '8ed76517f425b41ee3ccbd5afc0c1e47')) v(sig, esperado)
  loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception '20261007o: corpo vivo de % mudou (md5 esperado %). Releia pg_get_functiondef antes de aplicar.', r.sig, r.esperado;
    end if;
  end loop;
  -- a regra 42 é a da lista 614 e aponta para a Clínica (estado da 20261007152751)
  select * into v_regra from crm.catalogo_regra x where x.id = 42;
  if not found or not v_regra.ativo or v_regra.tipo <> 'projeto' or v_regra.campo <> 'ac_lista' or v_regra.operador <> 'contem'
     or lower(btrim(v_regra.padrao)) <> lower('Clínica Internacional Diamante Dez/26')
     or v_regra.projeto is distinct from 'clinica-miami-2026-12' or v_regra.vale_de is not null or v_regra.vale_ate is not null then
    raise exception '20261007o: crm.catalogo_regra 42 não é mais "ac_lista contem Clínica Internacional Diamante Dez/26 → clinica-miami-2026-12" ativa. Conferir com o Victor.';
  end if;
  -- estado pós-migration tolerado: a flag já existe e só a 42 está ligada
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'catalogo_regra'
                and column_name = 'para_todos') then
    if exists (select 1 from crm.catalogo_regra x where x.para_todos and x.id <> 42) then
      raise exception '20261007o: há regra com para_todos = true além da 42. Alguém já usa a flag: reler antes de seguir.';
    end if;
  end if;
  if exists (select 1 from pg_trigger t where t.tgrelid = 'crm.evento_jornada'::regclass and not t.tgisinternal
                and t.tgname like 'zz_origem_para_todos%'
                and t.tgfoid <> coalesce(to_regprocedure('crm.tg_origem_para_todos()'), 0::oid)) then
    raise exception '20261007o: gatilho zz_origem_para_todos* existe apontando para outra função. Reler.';
  end if;
  -- massa da recatalogação (pessoas com entrada na 614 e sem contato comercial no grupo)
  select count(distinct pessoas.atual(e.pessoa_id)) into v_massa
    from crm.evento_jornada e
   where e.fonte = 'activecampaign' and e.pessoa_id is not null and e.tipo in ('subscribe', 'contact_tag_added')
     and btrim(coalesce(e.lista, '')) = '614'
     and not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(e.pessoa_id))));
  if v_massa > 1000 then
    raise exception '20261007o: % pessoas a recatalogar (teto 1.000). Rodar em lotes.', v_massa;
  end if;
end
$g$;

-- ─── 1. A flag por regra ──────────────────────────────────────────────────────────────────────────────────────────
alter table crm.catalogo_regra add column if not exists para_todos boolean not null default false;
comment on column crm.catalogo_regra.para_todos is
  '20261007o: true = quem entra nesta lista/tag do AC vira contato comercial (e é catalogado) mesmo sem ser contato antes. '
  'Só regra tipo projeto de ac_lista/ac_tag. Ligada só na 42 (lista 614, Clínica de Miami), pedido do Victor Hugo 07/10/2026.';
do $k$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'crm.catalogo_regra'::regclass
                    and conname = 'catalogo_regra_para_todos_ck') then
    alter table crm.catalogo_regra add constraint catalogo_regra_para_todos_ck
      check (not para_todos or (tipo = 'projeto' and campo in ('ac_lista', 'ac_tag')));
  end if;
end
$k$;

update crm.catalogo_regra x
   set para_todos = true,
       nota = left(coalesce(x.nota || ' · ', '') || 'para_todos (20261007o)', 300),
       atualizado_em = now()
 where x.id = 42 and not x.para_todos;

-- ─── 2. Qual regra para_todos o evento casa ───────────────────────────────────────────────────────────────────────
-- mesma comparação do crm.catalogo_resolver (valor e, na lista, o nome de crm.ac_lista), mesma janela de datas em BRT
create or replace function crm.catalogo_para_todos(p_campos jsonb, p_quando timestamptz default null) returns bigint
language sql stable set search_path = '' as $f$
  select x.id
    from crm.catalogo_regra x
   cross join lateral (select nullif(btrim(coalesce(p_campos ->> x.campo, '')), '') v) c
   where x.ativo and x.para_todos and x.tipo = 'projeto'
     and p_campos is not null and jsonb_typeof(p_campos) = 'object'
     and c.v is not null and not (x.campo = 'ac_lista' and c.v = '0')
     and (x.vale_de is null or (coalesce(p_quando, now()) at time zone 'America/Sao_Paulo')::date >= x.vale_de)
     and (x.vale_ate is null or (coalesce(p_quando, now()) at time zone 'America/Sao_Paulo')::date <= x.vale_ate)
     and (crm.catalogo_casa(x.operador, x.padrao, c.v)
          or (x.campo = 'ac_lista'
              and crm.catalogo_casa(x.operador, x.padrao,
                    coalesce(nullif(btrim(coalesce(p_campos ->> 'ac_lista_nome', '')), ''),
                             (select l.nome from crm.ac_lista l where l.id = c.v)))))
   order by x.prioridade, x.id
   limit 1;
$f$;
comment on function crm.catalogo_para_todos(jsonb, timestamptz) is
  '20261007o: id da regra para_todos (crm.catalogo_regra) que casa os campos do evento, ou null.';

-- ─── 3. Gatilho: entrada numa lista/tag para_todos abre o contato comercial ───────────────────────────────────────
create or replace function crm.tg_origem_para_todos() returns trigger
language plpgsql security definer set search_path = '' as $f$
declare v_atual uuid; v_campos jsonb; v_canal text;
begin
  begin
    v_atual := pessoas.atual(new.pessoa_id);
    if v_atual is null then return null; end if;
    if exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(v_atual))) then
      return null;   -- já é contato: zz_origem_ac_* recataloga como sempre
    end if;
    v_campos := crm.campos_do_evento('activecampaign', jsonb_strip_nulls(jsonb_build_object(
                  'lista', nullif(nullif(btrim(coalesce(new.lista, '')), ''), '0'),
                  'tag', nullif(btrim(coalesce(new.tag, '')), ''), 'utm', new.dados -> 'utm')));
    if crm.catalogo_para_todos(v_campos, new.ocorreu_em) is null then return null; end if;
    v_canal := current_setting('crm.canal', true);
    perform set_config('crm.canal', 'activecampaign', true);   -- dica de canal e crm.tg_log (autor integracao)
    perform crm.garantir_pc(v_atual);                          -- zz_origem_ins cria a origem e cataloga
    perform set_config('crm.canal', coalesce(v_canal, ''), true);
  exception when others then
    raise warning 'crm.tg_origem_para_todos: evento % (%: %)', new.id, sqlstate, sqlerrm;   -- nunca derruba o webhook
  end;
  return null;
end
$f$;
comment on function crm.tg_origem_para_todos() is
  '20261007o: evento de entrada do AC numa lista/tag com regra para_todos abre o contato comercial (garantir_pc) de quem não é contato.';

revoke all on function crm.catalogo_para_todos(jsonb, timestamptz) from public, anon, authenticated, service_role;
revoke all on function crm.tg_origem_para_todos() from public, anon, authenticated, service_role;

-- nome depois de zz_origem_ac_*: roda por último (o recatalogar dos contatos existentes vem antes, sem efeito para quem
-- não é contato; a ordem não muda o resultado)
drop trigger if exists zz_origem_para_todos_ins on crm.evento_jornada;
drop trigger if exists zz_origem_para_todos_upd on crm.evento_jornada;
create trigger zz_origem_para_todos_ins after insert on crm.evento_jornada for each row
  when (new.pessoa_id is not null and new.fonte = 'activecampaign' and new.tipo in ('subscribe', 'contact_tag_added'))
  execute function crm.tg_origem_para_todos();
create trigger zz_origem_para_todos_upd after update on crm.evento_jornada for each row
  when (old.pessoa_id is distinct from new.pessoa_id and new.pessoa_id is not null and new.fonte = 'activecampaign'
        and new.tipo in ('subscribe', 'contact_tag_added'))
  execute function crm.tg_origem_para_todos();

-- ─── 3b. Trava da flag (condição C2.1 do pentester, 07/10/2026) ───────────────────────────────────────────────────
-- A tela (public.crm_catalogo_regra_salvar) edita campo, operador e padrão sem mostrar para_todos: editar a regra 42
-- para um padrão largo abriria contato para toda entrada do AC. Mudou tipo, campo, operador, padrão ou projeto de uma
-- regra para_todos → a flag desliga sozinha (religar é decisão explícita, por migration).
create or replace function crm.tg_catalogo_regra_para_todos_reset() returns trigger
language plpgsql set search_path = '' as $f$
begin
  if old.para_todos and new.para_todos
     and (new.tipo, new.campo, new.operador, new.padrao, new.projeto)
         is distinct from (old.tipo, old.campo, old.operador, old.padrao, old.projeto) then
    new.para_todos := false;
    new.nota := left(coalesce(new.nota || ' · ', '') || 'para_todos desligado ao editar a regra (20261007o)', 300);
  end if;
  return new;
end
$f$;
comment on function crm.tg_catalogo_regra_para_todos_reset() is
  '20261007o: editar tipo/campo/operador/padrão/projeto de regra para_todos desliga a flag (C2.1 do pentester).';
revoke all on function crm.tg_catalogo_regra_para_todos_reset() from public, anon, authenticated, service_role;
drop trigger if exists catalogo_regra_para_todos_reset on crm.catalogo_regra;
create trigger catalogo_regra_para_todos_reset before update on crm.catalogo_regra for each row
  execute function crm.tg_catalogo_regra_para_todos_reset();

-- ─── 4. Recataloga quem já entrou ─────────────────────────────────────────────────────────────────────────────────
do $r$
declare v uuid; v_n int := 0; v_canal text := current_setting('crm.canal', true);
begin
  perform set_config('crm.canal', 'activecampaign', true);
  for v in
    select distinct pessoas.atual(e.pessoa_id)
      from crm.evento_jornada e
     where e.fonte = 'activecampaign' and e.pessoa_id is not null and e.tipo in ('subscribe', 'contact_tag_added')
       and crm.catalogo_para_todos(crm.campos_do_evento('activecampaign', jsonb_strip_nulls(jsonb_build_object(
             'lista', nullif(nullif(btrim(coalesce(e.lista, '')), ''), '0'), 'tag', nullif(btrim(coalesce(e.tag, '')), ''),
             'utm', e.dados -> 'utm'))), e.ocorreu_em) is not null
       and not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = any(pessoas.grupo(pessoas.atual(e.pessoa_id))))
  loop
    continue when v is null;
    perform crm.garantir_pc(v);
    v_n := v_n + 1;
  end loop;
  perform set_config('crm.canal', coalesce(v_canal, ''), true);
  raise notice '20261007o: % contatos abertos e catalogados pela regra para_todos', v_n;
end
$r$;

-- ─── 5. Pós-condição ──────────────────────────────────────────────────────────────────────────────────────────────
do $c$
begin
  if not (select x.para_todos from crm.catalogo_regra x where x.id = 42) then
    raise exception '20261007o: a regra 42 não ficou para_todos';
  end if;
  if exists (select 1 from crm.catalogo_regra x where x.para_todos and x.id <> 42) then
    raise exception '20261007o: outra regra ficou para_todos';
  end if;
  if (select count(*) from pg_trigger t where t.tgrelid = 'crm.evento_jornada'::regclass and not t.tgisinternal
         and t.tgname in ('zz_origem_para_todos_ins', 'zz_origem_para_todos_upd') and t.tgenabled = 'O'
         and t.tgfoid = 'crm.tg_origem_para_todos()'::regprocedure) <> 2 then
    raise exception '20261007o: os 2 gatilhos zz_origem_para_todos_* não ficaram ligados';
  end if;
  -- todo mundo com entrada na 614 tem contato comercial e linha de origem
  if exists (select 1 from crm.evento_jornada e
              where e.fonte = 'activecampaign' and e.pessoa_id is not null and e.tipo in ('subscribe', 'contact_tag_added')
                and btrim(coalesce(e.lista, '')) = '614'
                and not exists (select 1 from crm.pessoa_origem po where po.pessoa_id = any(pessoas.grupo(pessoas.atual(e.pessoa_id))))) then
    raise exception '20261007o: sobrou pessoa com entrada na lista 614 sem linha em crm.pessoa_origem';
  end if;
  if not exists (select 1 from pg_trigger t where t.tgrelid = 'crm.catalogo_regra'::regclass and not t.tgisinternal
                   and t.tgname = 'catalogo_regra_para_todos_reset' and t.tgenabled = 'O') then
    raise exception '20261007o: gatilho catalogo_regra_para_todos_reset não ficou ligado';
  end if;
  -- a lista 614 resolve para a regra 42 pelo id (nome vem de crm.ac_lista)
  if crm.catalogo_para_todos(jsonb_build_object('ac_lista', '614'), now()) is distinct from 42 then
    raise exception '20261007o: a lista 614 não casa a regra para_todos 42';
  end if;
  if exists (select 1 from pg_proc p where p.oid in ('crm.catalogo_para_todos(jsonb,timestamptz)'::regprocedure,
                                                    'crm.tg_origem_para_todos()'::regprocedure)
                and (p.proacl is null or p.proacl::text ~ '(anon|authenticated|service_role)=|[{,]=X')) then
    raise exception '20261007o: função nova executável pela API (proacl). Conferir o revoke.';
  end if;
end
$c$;

-- ─── REVERSÃO (manual, numa transação) ────────────────────────────────────────────────────────────────────────────
-- Desligar (segundos, sem DDL): update crm.catalogo_regra set para_todos = false, atualizado_em = now() where id = 42;
-- Voltar o banco ao estado anterior:
--   drop trigger if exists zz_origem_para_todos_ins on crm.evento_jornada;
--   drop trigger if exists zz_origem_para_todos_upd on crm.evento_jornada;
--   drop function if exists crm.tg_origem_para_todos();
--   drop trigger if exists catalogo_regra_para_todos_reset on crm.catalogo_regra;
--   drop function if exists crm.tg_catalogo_regra_para_todos_reset();
--   drop function if exists crm.catalogo_para_todos(jsonb, timestamptz);
--   alter table crm.catalogo_regra drop constraint if exists catalogo_regra_para_todos_ck;
--   alter table crm.catalogo_regra drop column if exists para_todos;
--   update crm.catalogo_regra set nota = nullif(regexp_replace(nota, '( · )?para_todos \(20261007o\)$', ''), '') where id = 42;
-- Contatos abertos por esta migration/gatilho NÃO são apagados na reversão (crm.pessoa_comercial tem log imutável e pode
-- já ter dono, negócio ou mensagem). Para listar: crm.log com resumo "Abriu o contato comercial de …" e autor integracao
-- depois da aplicação, cruzando com quem tem evento da lista 614. Apagar contato é decisão do Victor/Arthur.
