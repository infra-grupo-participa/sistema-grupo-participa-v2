-- 20260930z90 — Ativação da 2ª conta Hotmart (escritorio / Soluções): separar "sincroniza" de "aparece nos funis".
--
-- POR QUÊ (achado do revisor sobre a z89, bloqueia a ativação)
--   fin.hotmart_contas.ativa fazia DUAS coisas: (1) liberava credencial + fila (sem ela o catálogo e o backfill da conta
--   são impossíveis) e (2) desligava conta_ausente nos funis NA HORA. Ligar para sincronizar = funil mostrando número
--   parcial do backfill como se fosse completo. Esta migration separa:
--     sincroniza     → credencial (fin.hotmart_credenciais_conta), fila (fin.hotmart_sync_enfileirar, crons '*').
--     visivel_funis  → os 3 funis (fn_fin_funis, fn_fin_funil_compradores, fn_fin_hotmart_funis). Conta com
--                      visivel_funis = false: evento/família dela lê a conta '(oculta)' (nenhuma transação casa → 0,
--                      exatamente o que a tela mostra hoje) e fn_fin_funis continua marcando conta_ausente.
--   Academy: as duas true. Escritório: as duas false. Ligar = UPDATE separado (RUNBOOK abaixo).
--
--   1. hotmart_contas: ativa → renomeada para sincroniza; visivel_funis nova (default false; academy = true).
--      "ativa" CONTINUA existindo como coluna gerada (= sincroniza): a edge hotmart-sync v9 (no ar) lê
--      "where ativa" em contasProntas e no ramo body.rotina. Sem isto o sync da Academy pararia. Somente leitura.
--      Remover "ativa" só depois de uma edge que leia sincroniza (fora desta migration: edge intocada, sem deploy).
--   2. Trava (fin.trava_conta_hotmart_violacao): v_aprovados recebe os md5 NOVOS dos 3 funis ANTES do patch deles.
--      Patch pelo corpo vivo com guarda md5 (molde da z89). O bloco $trava$ é repetido no fim (regra da z89).
--   3. Patches pelo corpo vivo, guarda md5 + "trecho aparece exatamente n vezes":
--        fin.hotmart_credenciais_conta(text) e fin.hotmart_sync_enfileirar(integer): ativa → sincroniza.
--        fn_fin_funis, fn_fin_funil_compradores, fn_fin_hotmart_funis: conta escritorio só se visivel_funis.
--   4. Crons que inserem em fin.hotmart_sync_fila (cron.job lido em 29/09):
--        57 fin-hotmart-rotina-todos        (7 * * * *)   insert '*' SEM conta → caía em 'academy'. Passa a 1 linha por
--        61 fin-hotmart-rotina-todos-45dias (43 3 * * *)  conta com sincroniza. Guarda md5 do command vivo.
--        48 fin-hotmart-sync-60dias / 52 fin-hotmart-sync-historia chamam fin.hotmart_sync_enfileirar → coberto em 3.
--        45 fin-hotmart-sync-rotina / 51 fin-hotmart-sync-fila chamam fin.hotmart_sync_disparar → edge (body.rotina
--        já insere por conta "ativa" = sincroniza). 56 fin-hotmart-catalogo: edge, todas as contas "ativa". Intocados.
--
-- ANTES × DEPOIS DO command (jobs 57 e 61)
--   57 ANTES  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo, status, tentativas)
--             select '*', hoje - 3, hoje, 'rotina', 'pendente', 0
--              where not exists (select 1 from fin.hotmart_sync_fila where produto_id = '*' and tipo = 'rotina'
--                                   and status in ('pendente','processando'))
--   57 DEPOIS insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo, status, tentativas)
--             select c.conta, '*', hoje - 3, hoje, 'rotina', 'pendente', 0 from fin.hotmart_contas c
--              where c.sincroniza and not exists (... f.conta = c.conta and f.produto_id = '*' and f.tipo = 'rotina'
--                                                  and f.status in ('pendente','processando'))
--             on conflict do nothing
--   61 ANTES  igual ao 57 com hoje - 45 e guarda também por inicio = hoje - 45 and fim = hoje
--   61 DEPOIS idem, por conta com sincroniza (guarda por conta + inicio + fim), on conflict do nothing
--   (hoje = (now() at time zone 'America/Sao_Paulo')::date; texto literal nos blocos abaixo)
--
-- REVERSÃO
--   ⚠️ A reversão da z89 ("set ativa = false") DEIXA DE VALER: ativa agora é coluna GERADA (= sincroniza) e o
--   update dá "column ativa can only be updated to DEFAULT". Use as linhas abaixo.
--   ⚠️ REAPLICAR a z89 depois da z90 FALHA: o "insert into fin.hotmart_contas (conta, empresa, vault_nome, ativa)"
--   (l.92 da z89) grava valor em ativa, que agora é coluna GERADA ("cannot insert a non-DEFAULT value into column
--   ativa"). A z89 não é idempotente sobre a z90; repor a z89 exige desfazer a z90 antes (linha "Desfazer" abaixo).
--   ⚠️ Quem REMOVER a coluna ativa (depois de uma edge que leia sincroniza) tem de conferir também a forma sem
--   prefixo ("from fin.hotmart_contas where ativa"): a checagem do bloco 3 só pega "x.ativa".
--   Desligar o escritório sem desfazer: update fin.hotmart_contas set sincroniza = false, visivel_funis = false
--     where conta = 'escritorio';   → credencial NULL, fila ignora a conta, funis voltam a conta_ausente.
--   Só esconder dos funis (sync segue): update fin.hotmart_contas set visivel_funis = false where conta = 'escritorio';
--   Desfazer de verdade: repor os corpos anteriores (md5 nas guardas; SALVAR pg_get_functiondef das 6 funções e
--   cron.job 57/61 antes do apply),
--   alter table fin.hotmart_contas drop column ativa, drop column visivel_funis, rename column sincroniza to ativa;
--   trava: repor v_aprovados antigos (b72ed7dd…, f354c46d…, a36eed87…) ANTES de repor os funis.
--
-- AS 5 PERGUNTAS
--   escala: hotmart_contas tem 2 linhas; o teste de visibilidade é 1 subquery NÃO correlacionada (InitPlan, 1×
--     por chamada) — não cresce com o volume do espelho.
--   índice: nenhum novo. Planos antes/depois em 20260930z90.explain.md.
--   frequência: funis = tela do Financeiro (dezenas/dia); crons: os mesmos horários.
--   repetição: nenhuma query nova por tela.
--   reversão: acima.
--
-- ======================================================================================================================
-- RUNBOOK DA ATIVAÇÃO (em ordem; cada passo só depois de conferido o anterior)
--   Evitar :05–:10 e :23–:32 (crons do sync). Toda chamada < 25 s.
--
--   (a) Aplicar esta migration (z90). Conferir: select * from fin.hotmart_contas;
--         academy  sincroniza t visivel_funis t ativa t
--         escritorio sincroniza f visivel_funis f ativa f
--       PROVA DA JUNÇÃO com a edge v9 (lê "where ativa", agora coluna gerada): depois do commit, aguardar a próxima
--       execução do cron 51 (≤ 2 min, só dispara se houver janela pendente) ou do 45 (:07) e conferir:
--         select id, status_code, left(content, 300) from net._http_response order by id desc limit 1;
--           → 200, "feitos" com conta academy, contas_puladas [] e nenhum erro de coluna ("column ... ativa").
--       ou:  select max(atualizado_em) from (select * from fin.hotmart_transacoes where conta = 'academy') t;
--           → avança depois da execução.  Falhou → alter table fin.hotmart_contas drop column ativa NÃO resolve;
--           a correção é a edge ler sincroniza (ou reverter a z90).
--
--   (b) Ligar SÓ o sync do escritório:
--         update fin.hotmart_contas set sincroniza = true where conta = 'escritorio';
--       Conferir: select basic is not null from fin.hotmart_credenciais_conta('escritorio');   → true
--                 fn_fin_funis(): eventos setor escritorio desde 2025 continuam conta_ausente = true, valores 0.
--       A partir daqui os crons 57/61 (e o body.rotina da edge) já enfileiram '*' da conta escritorio: a rotina
--       de 3 dias começa a trazer venda recente antes do backfill — é esperado (não aparece nos funis).
--
--   (c) Catálogo da conta escritório (edge hotmart-sync, body.catalogo + body.conta; header x-sync-chave = Vault
--       fin_hotmart_sync_chave, a mesma das 2 contas — igual ao cron 56):
--         select net.http_post(
--           url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/hotmart-sync',
--           headers := jsonb_build_object('Content-Type','application/json','x-sync-chave',
--             (select decrypted_secret from vault.decrypted_secrets where name = 'fin_hotmart_sync_chave')),
--           body := '{"catalogo": true, "conta": "escritorio"}'::jsonb, timeout_milliseconds := 150000);
--       Resposta (assíncrono): select status_code, content from net._http_response where id = <id devolvido>;
--         esperado: por_conta.escritorio > 0, contas_puladas [], catalogo_erro [].
--       Conferir: select produto_id, nome from fin.hotmart_catalogo where conta = 'escritorio';
--                 select produto_id, familia from fin.produtos where conta = 'escritorio';  → todos A_CLASSIFICAR
--       ⚠️ produto_id que já exista na Academy NÃO é gravado (on conflict … where conta = excluded.conta).
--          Conferir que 5238525, 5243340 e 5301413 aparecem com conta = 'escritorio'.
--
--   (d) Classificar os 3 produtos:
--         update fin.produtos set familia = 'ESCRITORIO_SOLUCOES', sincroniza = true,
--                nota = 'Conta escritorio (Soluções). Classificado na ativação z90.'
--          where conta = 'escritorio' and produto_id in ('5238525','5243340','5301413');   → 3 linhas
--         insert into fin.evento_produtos (categoria, produto_id, papel) values
--           ('seminario_marcio', '5238525', 'oferta'), ('seminario_elaine', '5238525', 'oferta')
--         on conflict do nothing;
--       POR QUE família NOVA 'ESCRITORIO_SOLUCOES' (e não 'ESCRITORIO'/'OUTROS' dos legados):
--         fn_fin_hotmart_funis escolhe a conta pela família: só lê 'escritorio' se TODOS os produtos da família forem
--         dessa conta; família mista fica na academy. Os legados são da Academy: ESCRITORIO = {1542521 Croqui,
--         1663254 e 1664749 Sessão}; OUTROS contém 3595938 "Holding Familiar" e mais 30 produtos academy.
--           - Pôr Sessão/Croqui em ESCRITORIO → família mista → continua lendo academy: o funil do legado não muda,
--             mas o novo fica INVISÍVEL para sempre nesse funil.
--           - Pôr HF em OUTROS → idem (OUTROS vira mista, HF da Soluções some).
--           - Família nova só com produtos escritorio → lê a conta escritorio; ESCRITORIO e OUTROS continuam 100%
--             academy (resultado idêntico). Nenhum dos dois quebra.
--         HF entra na mesma família nova (é produto da Soluções; em OUTROS ficaria invisível). A tela hoje não lista
--         nem ESCRITORIO nem a nova (FAMILIAS_EM_ORDEM em web/modules/financeiro/domain/hotmart.ts) — a escolha
--         importa para fn_fin_hotmart_funis e para quem a incluir depois.
--         fn_fin_funis NÃO usa família: casa venda com evento por fin.evento_produtos (categoria). Os seminários
--         seminario_marcio/seminario_elaine só conhecem 1663254/1664749 (Academy); sem o insert acima, os eventos de
--         2025+ (que leem a conta escritorio) continuariam com 0 venda mesmo depois de visíveis. Para os eventos
--         antigos (conta academy) o produto 5238525 não casa nada (nenhuma venda academy tem esse produto_id).
--         Croqui e HF não entram em evento_produtos (os legados também não estão).
--       ⚠️ Com fin.produtos.sincroniza = true nos 3, o cron 48 (fin-hotmart-sync-60dias, 03:23 UTC diário) passa a
--       enfileirar janelas de 60 dias POR PRODUTO do escritório, por cima do backfill '*'. É duplicata inofensiva
--       (upsert por transação), mas são chamadas extras à API Hotmart — esperado. O 52 (domingo) faz o mesmo desde 2019.
--       Depois: repetir o passo (c) para trazer as OFERTAS dos 3 (só produto com sincroniza = true busca oferta).
--
--   (e) Backfill desde 2025-03-01, janelas de 7 dias, todos os produtos da conta ('*'):
--         insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo, status, tentativas)
--         select 'escritorio', '*', g::date, least(g::date + 6, (now() at time zone 'America/Sao_Paulo')::date),
--                'backfill', 'pendente', 0
--           from generate_series(date '2025-03-01', (now() at time zone 'America/Sao_Paulo')::date, interval '7 days') g
--         on conflict do nothing;                                                  → ~83 janelas
--       O cron 51 (a cada 2 min, até 3 em paralelo) processa; a edge dá prioridade à rotina e vai de trás para frente.
--       Acompanhar: select status, count(*), max(erro) from fin.hotmart_sync_fila where conta = 'escritorio'
--                    and tipo = 'backfill' group by 1;
--       Erro com tentativas = 3 → corrigir a causa e: update fin.hotmart_sync_fila set status = 'pendente',
--         tentativas = 0 where conta = 'escritorio' and status = 'erro';
--       Colisões: select count(*) from fin.hotmart_transacoes_colisao where conta = 'escritorio';  → esperado 0.
--
--   (f) Conferência contra a Hotmart (APPROVED/COMPLETE, 03/2025 → 29/09/2026):
--         select t.produto_id, count(*) vendas, count(distinct lower(trim(t.comprador_email))) pessoas
--           from (select * from fin.hotmart_transacoes where conta = 'escritorio') t
--          where t.produto_id in ('5238525','5243340','5301413') and t.status in ('APPROVED','COMPLETE')
--            and t.aprovado_em >= timestamptz '2025-03-01 00:00-03' and t.aprovado_em < timestamptz '2026-09-30 00:00-03'
--          group by 1 order by 1;
--       Esperado: 5238525 Sessão 174 / 173 · 5243340 Croqui 85 / 74 · 5301413 HF 33 / 25.
--       Origem: levantamento pela API Hotmart (sales/history), conta escritório, 29/09 ~18:17 BRT (ver
--       20260930z90.explain.md §0). A janela termina em 29/09: REFAZER o levantamento pela API no dia da conferência.
--       Divergiu → NÃO seguir. Ver janelas com erro, colisões e se o produto veio com outro produto_id.
--
--   (g) Só então:  update fin.hotmart_contas set visivel_funis = true where conta = 'escritorio';
--       Conferir fn_fin_funis(): eventos escritorio 2025+ com conta_ausente = false e vendas > 0 nos seminários;
--       resto da Academy idêntico (hash antes/depois — ver 20260930z90.explain.md).
--       Pendência conhecida: fin.resolver_ofertas_eventos é só academy (z89) — oferta do escritório não é ligada a
--       evento por fin.evento_ofertas; fn_fin_funis cai na janela de datas do evento (carrinho_inicio..venda_ate).
-- ======================================================================================================================

set local lock_timeout = '5s';

-- 1. Duas flags --------------------------------------------------------------------------------------------------------
do $flags$
begin
  if exists (select 1 from pg_attribute where attrelid = 'fin.hotmart_contas'::regclass and attname = 'ativa'
               and not attisdropped and attgenerated = '')
     and not exists (select 1 from pg_attribute where attrelid = 'fin.hotmart_contas'::regclass and attname = 'sincroniza'
                       and not attisdropped) then
    alter table fin.hotmart_contas rename column ativa to sincroniza;
  end if;
end
$flags$;
alter table fin.hotmart_contas add column if not exists visivel_funis boolean not null default false;
update fin.hotmart_contas set visivel_funis = true where conta = 'academy' and not visivel_funis;
update fin.hotmart_contas set visivel_funis = false, sincroniza = false where conta = 'escritorio' and (visivel_funis or sincroniza);
-- Compatibilidade com a edge hotmart-sync v9 ("where ativa"). Somente leitura; some quando a edge ler sincroniza.
alter table fin.hotmart_contas add column if not exists ativa boolean generated always as (sincroniza) stored;

comment on table fin.hotmart_contas is
  'Contas Hotmart espelhadas no Financeiro. vault_nome = segredo (Basic) em vault.secrets. sincroniza = credencial + fila '
  '(catálogo, backfill, rotina). visivel_funis = os funis leem a conta (false: conta_ausente, valores 0). '
  'ativa = cópia gerada de sincroniza, só para a edge v9.';
comment on column fin.hotmart_contas.ativa is 'LEGADO (edge hotmart-sync v9). Gerada = sincroniza. Não usar em código novo.';

-- 2. Trava: md5 novos dos 3 funis em v_aprovados (ANTES do patch deles) ------------------------------------------------
do $trava_lista$
declare
  v_def text;
  v_md5 text;
  r     record;
begin
  select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
    from pg_proc p where p.oid = 'fin.trava_conta_hotmart_violacao(oid,oid)'::regprocedure;
  if v_md5 is distinct from 'be13743875a7cbbacc5092a7cda4f0bf' then
    raise exception 'z90: corpo vivo de fin.trava_conta_hotmart_violacao mudou (md5 %). Reler e refazer.', v_md5;
  end if;
  for r in select * from (values
      ('''public.fn_fin_funis()|b72ed7dda46ecc1c6ff0c0ebf835e2a0''',
       '''public.fn_fin_funis()|ffdfe84fdc11e4fae4ac7c06bec35a6c'''),
      ('''public.fn_fin_funil_compradores(bigint)|f354c46da0d29c173d46daf52d7c1421''',
       '''public.fn_fin_funil_compradores(bigint)|52e86030a8fcc448fc3201bc403f21b8'''),
      ('''public.fn_fin_hotmart_funis(text,date,date)|a36eed87268bb5ca192b3857d9e8476c''',
       '''public.fn_fin_hotmart_funis(text,date,date)|2019d65bbf3c3d7f345906b98b3e810b''')
    ) v(de, para) loop
    if (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de) <> 1 then
      raise exception 'z90: trecho não aparece 1 vez na trava: %', r.de;
    end if;
    v_def := replace(v_def, r.de, r.para);
  end loop;
  execute v_def;
end
$trava_lista$;

-- 3. Patches pelo corpo vivo ---------------------------------------------------------------------------------------------
do $patch$
declare
  r      record;
  v_def  text;
  v_md5  text;
  v_n    int;
  i      int;
  v_vis  constant text := '(case when exists (select 1 from fin.hotmart_contas hc where hc.conta = ''escritorio'' and hc.visivel_funis) then ''escritorio'' else ''(oculta)'' end)';
begin
  -- Todos os trechos de uma função são trocados e a função é recriada UMA vez: um estado intermediário do
  -- fn_fin_funis (só o 1º trecho) tem md5 fora de v_aprovados e a trava aborta (visto no ensaio).
  for r in
    select * from (values
      (1, 'fin.hotmart_credenciais_conta(text)',          '5f7516a3336de1fce85c5a2463839e12',
          array['where c.conta = p_conta and c.ativa)'], array['where c.conta = p_conta and c.sincroniza)']),
      (2, 'fin.hotmart_sync_enfileirar(integer)',         'f06f1b29e896a805d9a1332aefc0ae4d',
          array['where c.conta = p.conta and c.ativa)'], array['where c.conta = p.conta and c.sincroniza)']),
      (3, 'public.fn_fin_funis()',                        'b72ed7dda46ecc1c6ff0c0ebf835e2a0',
          array['then ''escritorio'' else ''academy'' end conta_ev', 'hc.conta = ''escritorio'' and hc.ativa)'],
          array['then ' || v_vis || ' else ''academy'' end conta_ev', 'hc.conta = ''escritorio'' and hc.visivel_funis)']),
      (4, 'public.fn_fin_funil_compradores(bigint)',      'f354c46da0d29c173d46daf52d7c1421',
          array['then ''escritorio'' else ''academy'' end conta_ev'],
          array['then ' || v_vis || ' else ''academy'' end conta_ev']),
      (5, 'public.fn_fin_hotmart_funis(text,date,date)',  'a36eed87268bb5ca192b3857d9e8476c',
          array['p.conta <> ''escritorio'') then ''escritorio'' else ''academy'' end;'],
          array['p.conta <> ''escritorio'') then ' || v_vis || ' else ''academy'' end;'])
    ) v(ordem, sig, md5_esperado, de, para)
    order by ordem
  loop
    select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
      from pg_proc p where p.oid = r.sig::regprocedure;
    if v_md5 is distinct from r.md5_esperado then
      raise exception 'z90: corpo vivo de % mudou (md5 % <> %). Reler a função e refazer o patch.', r.sig, v_md5, r.md5_esperado;
    end if;
    for i in 1 .. array_length(r.de, 1) loop
      v_n := (length(v_def) - length(replace(v_def, r.de[i], ''))) / length(r.de[i]);
      if v_n <> 1 then
        raise exception 'z90: trecho aparece % vez(es) em % (esperado 1): %', v_n, r.sig, r.de[i];
      end if;
      v_def := replace(v_def, r.de[i], r.para[i]);
    end loop;
    execute v_def;   -- create or replace: mantém dono, ACL, security definer e proconfig
  end loop;

  -- Nenhum corpo do banco pode continuar lendo hotmart_contas.ativa.
  select string_agg(p.oid::regprocedure::text, ', ') into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('fin', 'public') and p.prosrc ~ 'hotmart_contas' and p.prosrc ~ '\m[a-z]+\.ativa\M';
  if v_def is not null then
    raise exception 'z90: ainda lê hotmart_contas.ativa: %', v_def;
  end if;
  -- Os 3 funis têm que sair com o md5 que a trava aprovou no bloco 2 (a trava já barraria; aqui a mensagem é clara).
  select string_agg(x.sig || ' ' || x.m, ', ') into v_def
    from (select p.oid::regprocedure::text sig, md5(p.prosrc) m from pg_proc p
           where p.oid in ('public.fn_fin_funis()'::regprocedure, 'public.fn_fin_funil_compradores(bigint)'::regprocedure,
                           'public.fn_fin_hotmart_funis(text,date,date)'::regprocedure)) x
   where x.m not in ('ffdfe84fdc11e4fae4ac7c06bec35a6c', '52e86030a8fcc448fc3201bc403f21b8', '2019d65bbf3c3d7f345906b98b3e810b');
  if v_def is not null then
    raise exception 'z90: md5 de funil fora do aprovado: %', v_def;
  end if;
end
$patch$;

-- 4. Crons que inserem '*' na fila: 1 linha por conta com sincroniza --------------------------------------------------
do $cron$
declare
  r     record;
  v_id  bigint;
  v_md5 text;
begin
  for r in select * from (values
      ('fin-hotmart-rotina-todos', 'd59c72ba787e1a9a674af9290400ffd6', $cmd$
  insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo, status, tentativas)
  select c.conta, '*', (now() at time zone 'America/Sao_Paulo')::date - 3, (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
    from fin.hotmart_contas c
   where c.sincroniza
     and not exists (select 1 from fin.hotmart_sync_fila f
                      where f.conta = c.conta and f.produto_id = '*' and f.tipo = 'rotina' and f.status in ('pendente','processando'))
  on conflict do nothing
$cmd$),
      ('fin-hotmart-rotina-todos-45dias', 'fe0f14187f22a6d80ed4693467bba0a2', $cmd$
  insert into fin.hotmart_sync_fila (conta, produto_id, inicio, fim, tipo, status, tentativas)
  select c.conta, '*', (now() at time zone 'America/Sao_Paulo')::date - 45, (now() at time zone 'America/Sao_Paulo')::date, 'rotina', 'pendente', 0
    from fin.hotmart_contas c
   where c.sincroniza
     and not exists (
       select 1 from fin.hotmart_sync_fila f
        where f.conta = c.conta and f.produto_id = '*' and f.tipo = 'rotina' and f.status in ('pendente','processando')
          and f.inicio = (now() at time zone 'America/Sao_Paulo')::date - 45
          and f.fim    = (now() at time zone 'America/Sao_Paulo')::date
     )
  on conflict do nothing
$cmd$)
    ) v(nome, md5_esperado, cmd)
  loop
    select j.jobid, md5(j.command) into v_id, v_md5 from cron.job j where j.jobname = r.nome;
    if v_id is null then
      raise exception 'z90: cron % não existe', r.nome;
    end if;
    if v_md5 = md5(r.cmd) then
      continue;  -- já aplicado
    end if;
    if v_md5 is distinct from r.md5_esperado then
      raise exception 'z90: command do cron % mudou (md5 % <> %). Reler e refazer.', r.nome, v_md5, r.md5_esperado;
    end if;
    perform cron.alter_job(job_id := v_id, command := r.cmd);
  end loop;
end
$cron$;

-- 5. Trava: a mesma regra sobre TODO o banco (repetição obrigatória — a z90 recriou fin.trava_conta_hotmart_violacao) --
do $trava$
declare
  v_fora text;
begin
  select string_agg(x.erro, E'\n' order by x.erro) into v_fora
    from (select fin.trava_conta_hotmart_violacao('pg_catalog.pg_proc'::regclass, p.oid) erro
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname not in ('pg_catalog', 'information_schema') and n.nspname !~ '^pg_toast'
             and p.prokind in ('f', 'p')
          union all
          select fin.trava_conta_hotmart_violacao('pg_catalog.pg_class'::regclass, c.oid)
            from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where c.relkind in ('v', 'm') and n.nspname not in ('pg_catalog', 'information_schema')) x
   where x.erro is not null;
  if v_fora is not null then
    raise exception E'z90 trava:\n%', v_fora;
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'trava_conta_hotmart' and evtenabled <> 'D') then
    raise exception 'z90: event trigger trava_conta_hotmart ausente ou desligado';
  end if;
end
$trava$;
