-- 20260930z95 — Oferta→evento do escritório: palavras presas à janela do evento, fila com proposta completa e
--               evento criado pela fila no setor certo.
--
-- POR QUÊ
--   O job irmão da z91 (fin-oferta-evento-resolver-escritorio, :25) ligou a oferta mqquvrtc "Seminário ATM -
--   Setembro/2026" (9 Sessões pagas em 09–10/09/2026) ao evento 70 "Seminário de Estruturação Patrimonial (Elaine,
--   jul/2026)", que terminou em 30/07 com vendas até 02/08. Regra usada: palavras ("2026" + "seminario", 2 comuns).
--   O CTE kws aceitava evento cuja janela ia de ref_de - 60 até venda_ate + 60 — 38 dias depois do fim da venda
--   ainda casava. As outras regras já são presas à janela (nome/janela: primeira venda entre ja_de e ja_ate;
--   ingresso: ing_de..ja_ate; sck: só evento com ação).
--   Reprovação do João (1ª versão): confirmar a fila pela tela criaria o evento com setor 'educacao' fixo
--   (fn_fin_decidir_oferta, z85) e o funil do escritório (z92) só lê setor 'escritorio' → as 9 Sessões ficariam em
--   perene; e a proposta da fila não trazia a data do evento (o front abre com inicio '' → digitação à mão).
--
-- O QUE MUDA
--   1. fin.resolver_ofertas_eventos (md5 8e6890ab776ffad24d9c2bf34e0c69ea, corpo da z91):
--      a. kws, só com p_conta = 'escritorio': a 1ª venda da oferta tem de cair entre coalesce(carrinho_inicio,
--         inicio) - 60 e venda_ate + 7 (venda_ate é NOT NULL). Academy continua com + 60.
--      b. proposta_evento ganha a chave 'inicio' = 1ª venda da oferta (as duas contas). Já trazia nome, categoria,
--         carrinho_inicio (1ª venda) e venda_ate (p90 das vendas). Com isso a proposta passa inteira no p_criar.
--   2. public.fn_fin_decidir_oferta (md5 ffc9897fb03f5e9fb8b408db06d4e4a2, corpo da z85): a conta da oferta vem do
--      produto (fin.produtos.conta = 'escritorio' → escritório; senão academy).
--      a. p_criar: evento nasce com setor 'escritorio' (conta escritório) ou 'educacao' (como antes); conta
--         escritório com inicio < 2025-01-01 → recusa 22023 (o evento cairia fora da conta pela regra da z89/z91).
--      b. p_evento_id: recusa 22023 quando a conta do evento (setor 'escritorio' e inicio >= 2025-01-01 → escritório)
--         não bate com a conta da oferta.
--      Permissão, demais validações e ACL não mudam.
--   3. Fila pendente já gravada: proposta_evento sem 'inicio' recebe sinais.primeira_venda (mesmo valor que o
--      resolvedor passa a gravar). Só proposta objeto (JSON null = fila com evento sugerido, sem proposta).
--      Hoje 5 linhas (4 academy, 1 escritório) de 11 pendentes.
--   4. Apaga as ligações AUTOMÁTICAS (origem 'auto:%' e sinais.regra = 'palavras') a evento do escritório 2025+
--      cuja 1ª venda gravada nos sinais viola a janela nova. Ligação manual/confirmada não é tocada.
--      Cada linha apagada sai inteira (oferta, evento, origem, observação, sinais, criado_em) em raise notice.
--      Não há tabela de arquivo em fin; a linha de hoje (mqquvrtc → 70) está transcrita em 20260930z95.explain.md.
--   5. Roda o resolvedor da conta escritório uma vez (o mesmo comando do cron).
--
-- EVENTOS QUE FALTAM (fonte: mapeamento histórico do Drive, 103 eventos, 20 seminario_familias)
--   Os 16 do banco são exatamente os 16 seminários "Realizado" da fonte. Os 4 que faltam NÃO entram aqui:
--     - Seminário de Estruturação Patrimonial (Elaine) 24/08/2026 — "Não confirmado", pasta vazia, sem data de fim;
--       0 Sessão vendida entre 20/08 e 08/09.
--     - Seminário do THB "Patrimônio Brasil" 03–08/11/2026 (carrinho 05–08/11) — "Programado (concepção)"; a fonte
--       não diz quem apresenta → categoria seminario_marcio × seminario_elaine seria inventada. Decisão do dono.
--     - Elaine 4º ciclo 2025 e 4ª edição 2022 — "Não confirmado", sem data nenhuma (inicio é NOT NULL).
--   O "Seminário ATM - Setembro/2026" NÃO está na fonte (o levantamento corta em jul/2026). A fila propõe o evento
--   a partir das vendas; um clique em "criar evento" com a proposta cria o evento no setor escritório.
--
-- Guardas: md5(prosrc) de cada função; cada trecho trocado tem de aparecer exatamente n vezes (molde z89/z91).
-- Mesmas assinaturas → create or replace (ACL e comentário ficam).
-- Trava trava_conta_hotmart: as 2 leituras seguem "where conta = p_conta" (não são tocadas).
-- Aplicar como postgres, arquivo inteiro numa transação.
--
-- REVERSÃO
--   Resolvedor: create or replace com o corpo da z91 (desfazer trechos 1 e 3). A ligação apagada volta sozinha na
--     próxima rodada do job escritório se o corpo antigo voltar (mqquvrtc está nos 45 dias até 24/10/2026) — ou
--     insert com a linha transcrita no explain.
--   Decidir: create or replace com o corpo da z85 (v_setor → 'educacao').
--   Fila: a chave 'inicio' extra é ignorada por quem não a lê; update ... set proposta_evento = proposta_evento - 'inicio'.
--
-- AS 5 PERGUNTAS
--   escala: kws só perde pares; a fila tem 11 pendentes; decidir é 1 oferta por clique.
--   índice: nada novo. DELETE e kws medidos com explain (analyze, buffers) — ver explain.md.
--   frequência: igual (cron :25, 1×/h por conta; decidir = clique humano).
--   repetição: nenhuma tela chama o resolvedor; a fila já lia proposta_evento inteira.
--   reversão: acima; desligar o escritório inteiro = cron.unschedule('fin-oferta-evento-resolver-escritorio').
--
-- PENDENTE (outro agente): web/modules/financeiro/domain/fila-ofertas.ts formDaProposta passar a ler
--   proposta_evento.inicio (hoje fixa inicio ''); lerProposta/tipo PropostaEvento ganhar 'inicio'.
--
-- ENSAIO: ver 20260930z95.explain.md.

set local lock_timeout = '5s';

-- 1. resolvedor ------------------------------------------------------------------------------------------------------
do $z95$
declare
  v_sig  constant text := 'fin.resolver_ofertas_eventos(boolean,integer,text[],text)';
  v_def  text;
  v_md5  text;
  v_n    int;
  r      record;
begin
  select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
    from pg_proc p where p.oid = to_regprocedure(v_sig);
  if v_def is null then
    raise exception 'z95: % não existe (z91 aplicada?)', v_sig;
  end if;
  if v_md5 is distinct from '8e6890ab776ffad24d9c2bf34e0c69ea' then
    raise exception 'z95: corpo vivo de % mudou (md5 %). Reler e refazer o patch.', v_sig, v_md5;
  end if;

  for r in
    select * from (values
      (1, 'join ev e on o.primeira between e.ref_de - 60 and e.ja_ate + 60',
          'join ev e on o.primeira between e.ref_de - 60' ||
          ' and e.ja_ate + case when p_conta = ''escritorio'' then 7 else 60 end', 1),
      (2, '-- z91: p_conta. escritorio casa só com evento setor escritorio >= 2025-01-01; academy com o resto.',
          '-- z91: p_conta. escritorio casa só com evento setor escritorio >= 2025-01-01; academy com o resto.' || chr(10) ||
          '-- z95: escritorio — palavras só casa se a 1ª venda cair entre ref_de - 60 e venda_ate + 7 (academy: + 60);' || chr(10) ||
          '--      proposta_evento traz inicio (1ª venda).', 1),
      (3, '                  ''carrinho_inicio'', r.primeira,',
          '                  ''inicio'', r.primeira,' || chr(10) ||
          '                  ''carrinho_inicio'', r.primeira,', 1)
    ) v(ordem, de, para, n)
    order by ordem
  loop
    v_n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if v_n <> r.n then
      raise exception 'z95: resolvedor, trecho % aparece % vez(es) (esperado %): %', r.ordem, v_n, r.n, r.de;
    end if;
    v_def := replace(v_def, r.de, r.para);
  end loop;

  execute v_def;   -- CREATE OR REPLACE, mesma assinatura
end
$z95$;

do $conf$
declare v_src text := (select p.prosrc from pg_proc p
                         where p.oid = 'fin.resolver_ofertas_eventos(boolean,integer,text[],text)'::regprocedure);
begin
  if (select count(*) from regexp_matches(v_src, 'hotmart_transacoes where conta = p_conta\)', 'g')) <> 2
     or v_src !~ 'e\.ja_ate \+ case when p_conta = ''escritorio'' then 7 else 60 end'
     or v_src ~ 'e\.ja_ate \+ 60'
     or v_src !~ '''inicio'', r\.primeira,' then
    raise exception 'z95: corpo do resolvedor não ficou na forma esperada';
  end if;
end
$conf$;

-- 2. decidir: setor do evento criado vem do produto da oferta ------------------------------------------------------
do $z95d$
declare
  v_sig  constant text := 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)';
  v_def  text;
  v_md5  text;
  v_n    int;
  r      record;
begin
  select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
    from pg_proc p where p.oid = to_regprocedure(v_sig);
  if v_def is null then
    raise exception 'z95: % não existe', v_sig;
  end if;
  if v_md5 is distinct from 'ffc9897fb03f5e9fb8b408db06d4e4a2' then
    raise exception 'z95: corpo vivo de % mudou (md5 %). Reler e refazer o patch.', v_sig, v_md5;
  end if;

  for r in
    select * from (values
      (1, '-- z85: datas finitas, janela <= 120 dias, datas a <= 2 anos de hoje, categoria já existente (pentest).',
          '-- z85: datas finitas, janela <= 120 dias, datas a <= 2 anos de hoje, categoria já existente (pentest).' || chr(10) ||
          '-- z95: conta da oferta = escritorio se o produto é da conta escritorio. Evento criado herda o setor;' || chr(10) ||
          '--      conta escritorio exige inicio >= 2025-01-01; evento existente só liga se for da mesma conta' || chr(10) ||
          '--      (escritorio = setor escritorio e inicio >= 2025-01-01, regra da z89/z91).', 1),
      (2, '  v_car  date;' || chr(10) || 'begin',
          '  v_car  date;' || chr(10) || '  v_setor text;' || chr(10) || '  v_esc  boolean;' || chr(10) ||
          '  v_ev_esc boolean;' || chr(10) || 'begin', 1),
      (3, '    raise exception ''A oferta % já está ligada ao evento %.'', v_of, v_lig using errcode = ''23505'';' || chr(10) ||
          '  end if;' || chr(10),
          '    raise exception ''A oferta % já está ligada ao evento %.'', v_of, v_lig using errcode = ''23505'';' || chr(10) ||
          '  end if;' || chr(10) ||
          '  v_esc := exists (select 1 from fin.produtos p where p.produto_id = v_f.produto_id and p.conta = ''escritorio'');' || chr(10) ||
          '  v_setor := case when v_esc then ''escritorio'' else ''educacao'' end;' || chr(10), 1),
      (4, '    insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, fonte, observacao, automatico)' || chr(10) ||
          '    values (v_nome, v_cat, ''educacao'', v_ini,',
          '    if v_esc and v_ini < date ''2025-01-01'' then' || chr(10) ||
          '      raise exception ''Oferta da conta escritório: o evento tem de começar a partir de 01/01/2025 (informado %).'', v_ini' || chr(10) ||
          '        using errcode = ''22023'';' || chr(10) ||
          '    end if;' || chr(10) ||
          '    insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, fonte, observacao, automatico)' || chr(10) ||
          '    values (v_nome, v_cat, v_setor, v_ini,', 1),
      (5, '    select e.id into v_ev from fin.eventos e where e.id = p_evento_id;' || chr(10) ||
          '    if v_ev is null then' || chr(10) ||
          '      raise exception ''Evento % não existe.'', p_evento_id using errcode = ''P0002'';' || chr(10) ||
          '    end if;' || chr(10),
          '    select e.id, coalesce(e.setor = ''escritorio'' and e.inicio >= date ''2025-01-01'', false)' || chr(10) ||
          '      into v_ev, v_ev_esc from fin.eventos e where e.id = p_evento_id;' || chr(10) ||
          '    if v_ev is null then' || chr(10) ||
          '      raise exception ''Evento % não existe.'', p_evento_id using errcode = ''P0002'';' || chr(10) ||
          '    end if;' || chr(10) ||
          '    if v_ev_esc <> v_esc then' || chr(10) ||
          '      raise exception ''A oferta % é da conta % e o evento % é da conta %: escolha um evento da mesma conta.'',' || chr(10) ||
          '        v_of, case when v_esc then ''escritório'' else ''academy'' end, v_ev,' || chr(10) ||
          '        case when v_ev_esc then ''escritório'' else ''academy'' end using errcode = ''22023'';' || chr(10) ||
          '    end if;' || chr(10), 1)
    ) v(ordem, de, para, n)
    order by ordem
  loop
    v_n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if v_n <> r.n then
      raise exception 'z95: decidir, trecho % aparece % vez(es) (esperado %): %', r.ordem, v_n, r.n, r.de;
    end if;
    v_def := replace(v_def, r.de, r.para);
  end loop;

  execute v_def;   -- CREATE OR REPLACE, mesma assinatura (ACL authenticated/service_role fica)
end
$z95d$;

do $conf_d$
declare v_src text := (select p.prosrc from pg_proc p
                         where p.oid = 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)'::regprocedure);
begin
  if v_src ~ 'v_cat, ''educacao'', v_ini' or v_src !~ 'values \(v_nome, v_cat, v_setor, v_ini,'
     or v_src !~ 'gp_pode_ver_financeiro\(\), false\) or v_uid is null'
     or v_src !~ 'if v_esc and v_ini < date ''2025-01-01'' then'
     or v_src !~ 'if v_ev_esc <> v_esc then' then
    raise exception 'z95: corpo de fn_fin_decidir_oferta não ficou na forma esperada';
  end if;
  if (select p.prosecdef from pg_proc p where p.oid = 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)'::regprocedure) is not true
     or has_function_privilege('anon', 'public.fn_fin_decidir_oferta(text,bigint,jsonb,boolean)', 'execute') then
    raise exception 'z95: fn_fin_decidir_oferta perdeu security definer ou ficou aberta a anon';
  end if;
end
$conf_d$;

-- 3. fila pendente já gravada: proposta ganha inicio = 1ª venda -----------------------------------------------------
do $fila$
declare v_n int;
begin
  update fin.oferta_evento_fila f
     set proposta_evento = f.proposta_evento || jsonb_build_object('inicio', f.sinais ->> 'primeira_venda')
   where f.status = 'pendente'
     and jsonb_typeof(f.proposta_evento) = 'object'
     and not (f.proposta_evento ? 'inicio')
     and (f.sinais ->> 'primeira_venda') ~ '^\d{4}-\d{2}-\d{2}$';
  get diagnostics v_n = row_count;
  raise notice 'z95: % proposta(s) pendente(s) ganharam inicio', v_n;
end
$fila$;

-- 4. ligações automáticas por palavras que violam a janela nova (só escritório 2025+, nunca manual/confirmado) ------
do $limpa$
declare
  v_n    int;
  v_rows jsonb;
begin
  with apagar as (
    delete from fin.evento_ofertas eo
     using fin.eventos e
     where e.id = eo.evento_id
       and e.setor = 'escritorio' and e.inicio >= date '2025-01-01'
       and eo.origem like 'auto:%'
       and eo.sinais ->> 'regra' = 'palavras'
       and (eo.sinais ->> 'primeira_venda')::date
           not between coalesce(e.carrinho_inicio, e.inicio) - 60 and e.venda_ate + 7
    returning eo.oferta_codigo, eo.evento_id, eo.origem, eo.observacao, eo.sinais, eo.criado_em
  )
  select count(*), jsonb_agg(to_jsonb(a) order by a.oferta_codigo) into v_n, v_rows from apagar a;
  if v_n > 5 then
    raise exception 'z95: % ligações apagadas (esperado <= 5, medido 1 em 29/09). Conferir antes.', v_n;
  end if;
  raise notice 'z95: % ligação(ões) automática(s) por palavras fora da janela apagada(s): %', v_n, coalesce(v_rows, '[]'::jsonb);
end
$limpa$;

-- 5. religa pela regra nova (mesmo comando do job irmão da z91) ----------------------------------------------------
select count(*) from fin.hotmart_contas c
  cross join lateral fin.resolver_ofertas_eventos(true, 45, null, c.conta) r
 where c.conta = 'escritorio' and c.sincroniza;

do $conf_dado$
begin
  if exists (select 1 from fin.evento_ofertas eo join fin.eventos e on e.id = eo.evento_id
              where e.setor = 'escritorio' and e.inicio >= date '2025-01-01'
                and eo.origem like 'auto:%' and eo.sinais ->> 'regra' = 'palavras'
                and (eo.sinais ->> 'primeira_venda')::date
                    not between coalesce(e.carrinho_inicio, e.inicio) - 60 and e.venda_ate + 7) then
    raise exception 'z95: ainda há ligação por palavras fora da janela';
  end if;
  if exists (select 1 from fin.oferta_evento_fila f
              where f.status = 'pendente' and jsonb_typeof(f.proposta_evento) = 'object'
                and not (f.proposta_evento ? 'inicio')) then
    raise exception 'z95: proposta pendente sem inicio';
  end if;
end
$conf_dado$;
