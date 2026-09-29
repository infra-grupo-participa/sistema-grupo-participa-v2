-- 20260930z91 — Resolvedor oferta→evento por conta Hotmart (academy | escritorio).
--
-- POR QUÊ
--   fin.resolver_ofertas_eventos só lê a conta academy (z89). As ofertas da conta Soluções (Sessão de Viabilidade
--   5238525, Croqui 5243340, Holding Familiar 5301413) nunca seriam ligadas a evento — o funil do escritório (z92) só
--   teria a janela de datas. Esta migration:
--     1. ganha p_conta text default 'academy' (4º parâmetro). Troca de assinatura = drop + create (create or replace
--        com argumento novo criaria SOBRECARGA e "resolver_ofertas_eventos(true, 45)" ficaria ambíguo).
--        Nenhuma função do banco chama o resolvedor (pg_proc conferido 29/09); só o cron 63.
--     2. lê a conta pela forma canônica (select * from fin.hotmart_transacoes where conta = p_conta) — 2 citações.
--     3. eventos candidatos por conta:
--          escritorio → só fin.eventos setor = 'escritorio' e inicio >= 2025-01-01 (a conta Soluções começa em 2025);
--          academy    → todo o resto (tudo, MENOS escritório >= 2025). As regras de janela/palavras que exigiam
--                       setor 'educacao' continuam 'educacao' na academy; na conta escritorio passam a 'escritorio'.
--          sck (fin.acoes) só vale para evento candidato da conta.
--        Prova de que a academy não muda: hash de evento_ofertas / oferta_evento_fila e da saída (ver ENSAIO).
--     4. p_conta inexistente em fin.hotmart_contas → erro 22023.
--     5. cron: o job 63 (fin-oferta-evento-resolver, :25) passa a chamar p_conta 'academy' explícito — lendo o
--        command vivo por md5 e PRESERVANDO o prefixo "select fin.contratos_hf_sincronizar(); " da z93; um job irmão
--        no MESMO horário roda 'escritorio' só enquanto hotmart_contas.sincroniza. São 2 jobs de propósito: um único
--        comando com as 2 contas roda numa transação só (erro no escritório desfaria a academy toda hora) e um DO com
--        exception engoliria o erro (cron.job_run_details diria "sucesso"). Cada job falha sozinho e aparece.
--
-- ORDEM E COMO APLICAR
--   Preferida: z91 → z93 (a z93 põe o prefixo na frente do command que achar). z93 → z91 também funciona: a z91
--   reconhece o command da z93 por md5 e preserva o prefixo. Qualquer outro command no job 63 → raise, nada muda.
--   Aplicar como postgres, numa transação ÚNICA (arquivo inteiro): cron.schedule faz upsert por (jobname, username)
--   — outro usuário criaria um 2º job irmão em vez de atualizar.
--
-- Guarda: md5(prosrc) do corpo vivo lido em 29/09 = 59938014719a9bd5438e6bfd063006ba (corpo da z89).
-- Cada trecho trocado tem de aparecer exatamente n vezes (molde da z89).
-- Trava trava_conta_hotmart (z89): as 2 citações ficam na forma "where conta = p_conta" → passam sem allowlist.
--
-- REVERSÃO
--   Desligar só o escritório:  select cron.unschedule('fin-oferta-evento-resolver-escritorio');
--   Desfazer: salvar pg_get_functiondef ANTES (ou pegar do 20260930z89.backup-antes.sql + patch da z89),
--     drop function fin.resolver_ofertas_eventos(boolean,integer,text[],text); recriar o corpo anterior;
--     revoke all ... from public, anon, authenticated; grant execute ... to service_role;
--     cron: select cron.unschedule('fin-oferta-evento-resolver-escritorio'); job 63: cron.alter_job(63, command :=
--       replace(command, ', null, ''academy'')', ')')) — volta ao da z84, com o prefixo da z93 se houver.
--   Ligações gravadas pela conta escritorio: delete from fin.evento_ofertas eo using fin.eventos e
--     where e.id = eo.evento_id and e.setor = 'escritorio' and e.inicio >= date '2025-01-01' and eo.origem like 'auto:%';
--     Fila: delete from fin.oferta_evento_fila f using fin.produtos p
--     where p.produto_id = f.produto_id and p.conta = 'escritorio' and f.status = 'pendente';
--
-- AS 5 PERGUNTAS
--   escala: o resolvedor olha só ofertas com venda nos últimos 45 dias e sem ligação/decisão; a conta escritório
--     vende 3 produtos (dezenas de vendas/mês). Sem oferta candidata sai na 1ª query (return).
--   índice: nada novo. Na academy o corpo é o mesmo (só o literal virou p_conta). Plano do resolvedor NÃO medido
--     isoladamente: o ensaio inteiro (8 execuções do resolvedor + drop/create) levou 1,55 s. z84 mediu 619 ms/execução.
--     escritorio hoje: 0 candidatas → return na 1ª query.
--   frequência: 2 execuções/hora (1 por conta) em vez de 1; a do escritório é ~vazia até haver venda.
--   repetição: nenhuma tela chama o resolvedor.
--   reversão: acima.
--
-- ENSAIO (29/09 23:09 UTC, begin/rollback, mesmo banco; ver 20260930z92.explain.md seção z91)
--   Antes × depois, na mesma transação (now() igual → detalhe.calculado_em igual):
--     saída p_dias 45 (o que o cron faz)          2d5c95cd6c168dddee6a68424abafcc5 = 2d5c95cd6c168dddee6a68424abafcc5
--     gravou (p_gravar true, 45)                   38 linhas = 38 linhas
--     fin.evento_ofertas depois de gravar          2b53016c125dabca8262bb309f680890 n=24 = idem
--     fin.oferta_evento_fila depois de gravar      0325f3b1dd8b3577801d78ebdc2b4c2c n=10 = idem
--   Janela larga (p_dias 365, só leitura): 184 = 184 ofertas; 10 diferem, NENHUMA escreve pelo cron (fora dos 45 d):
--     9 só no diagnóstico detalhe.palavras (candidato/lider_sem_prazo era evento do escritório 2025+: 46, 54, 62);
--     1 muda decisão: wwzxz8v4 (Aurum, 43 vendas 15/12/2025–09/01/2026) fila:nome_contradiz → ligar auto:janela
--       evento 52 (ETHB 2025). O "contradiz" vinha da palavra "2026" casando o seminário do Márcio fev/2026 (escritório)
--       — é a correção que esta migration pretende. Não está na fila nem ligada hoje.
--   escritorio: 0 ofertas candidatas (conta sem venda ainda). p_conta 'xpto' → 22023. ACL = postgres, service_role.
--   Reensaio 23:33 (backfill já com 510 vendas escritorio): 45 d → 1 ligar (mqquvrtc → evento 70, auto:nome),
--   1 fila, 3 ignorar, 2 perene. Job irmão rodado 2×: a 2ª não muda evento_ofertas nem o conteúdo da fila
--   (ver 20260930z92.explain.md, "Ensaio da junção").

set local lock_timeout = '5s';

do $z91$
declare
  v_sig  constant text := 'fin.resolver_ofertas_eventos(boolean,integer,text[])';
  v_def  text;
  v_md5  text;
  v_n    int;
  r      record;
begin
  select md5(p.prosrc), pg_get_functiondef(p.oid) into v_md5, v_def
    from pg_proc p where p.oid = to_regprocedure(v_sig);
  if v_def is null then
    raise exception 'z91: % não existe (já aplicada?)', v_sig;
  end if;
  if v_md5 is distinct from '59938014719a9bd5438e6bfd063006ba' then
    raise exception 'z91: corpo vivo de % mudou (md5 %). Reler e refazer o patch.', v_sig, v_md5;
  end if;

  for r in
    select * from (values
      -- 1. assinatura
      (1, 'p_ofertas text[] DEFAULT NULL::text[])',
          'p_ofertas text[] DEFAULT NULL::text[], p_conta text DEFAULT ''academy''::text)', 1),
      -- 2. histórico no cabeçalho
      (2, '--      sugestão da fila: nome > janela única > ingresso > palavras > sck > janela mais curta.',
          '--      sugestão da fila: nome > janela única > ingresso > palavras > sck > janela mais curta.' || chr(10) ||
          '-- z91: p_conta. escritorio casa só com evento setor escritorio >= 2025-01-01; academy com o resto.', 1),
      -- 4. conta válida
      (3, '  if p_ofertas is not null and coalesce(p_gravar, false) then',
          '  if not exists (select 1 from fin.hotmart_contas hc where hc.conta = p_conta) then' || chr(10) ||
          '    raise exception ''conta Hotmart desconhecida: %'', p_conta using errcode = ''22023'';' || chr(10) ||
          '  end if;' || chr(10) ||
          '  if p_ofertas is not null and coalesce(p_gravar, false) then', 1),
      -- 2. leitura canônica pela conta
      (4, '(select * from fin.hotmart_transacoes where conta = ''academy'') t',
          '(select * from fin.hotmart_transacoes where conta = p_conta) t', 2),
      -- 3. eventos candidatos por conta
      (5, '      from fin.eventos e' || chr(10) || '  ), sv as (',
          '      from fin.eventos e' || chr(10) ||
          '     where coalesce(e.setor = ''escritorio'' and e.inicio >= date ''2025-01-01'', false) = (p_conta = ''escritorio'')' || chr(10) ||
          '  ), sv as (', 1),
      (6, 'e.setor = ''educacao''',
          'e.setor = case when p_conta = ''escritorio'' then ''escritorio'' else ''educacao'' end', 2),
      (7, 'join fin.acoes a on a.evento_id is not null and a.sck_regex is not null and x.sck ~* a.sck_regex',
          'join fin.acoes a on a.evento_id is not null and a.sck_regex is not null and x.sck ~* a.sck_regex' || chr(10) ||
          '                    and a.evento_id in (select e.id from ev e)', 1)
    ) v(ordem, de, para, n)
    order by ordem
  loop
    v_n := (length(v_def) - length(replace(v_def, r.de, ''))) / length(r.de);
    if v_n <> r.n then
      raise exception 'z91: trecho % aparece % vez(es) (esperado %): %', r.ordem, v_n, r.n, r.de;
    end if;
    v_def := replace(v_def, r.de, r.para);
  end loop;

  execute format('drop function %s', v_sig);
  execute v_def;
end
$z91$;

revoke all on function fin.resolver_ofertas_eventos(boolean, integer, text[], text) from public, anon, authenticated;
grant execute on function fin.resolver_ofertas_eventos(boolean, integer, text[], text) to service_role;
comment on function fin.resolver_ofertas_eventos(boolean, integer, text[], text) is
  'Liga oferta Hotmart → evento (fin.evento_ofertas) ou põe na fila (fin.oferta_evento_fila). p_conta: academy (default) ou escritorio (só eventos setor escritorio >= 2025).';

-- conferência: forma canônica pela conta, nenhuma citação presa a 'academy'
do $conf$
declare v_src text := (select p.prosrc from pg_proc p
                         where p.oid = 'fin.resolver_ofertas_eventos(boolean,integer,text[],text)'::regprocedure);
begin
  if (select count(*) from regexp_matches(v_src, 'hotmart_transacoes where conta = p_conta\)', 'g')) <> 2
     or v_src ~ 'conta = ''academy''' then
    raise exception 'z91: leitura por conta não ficou na forma esperada';
  end if;
end
$conf$;

-- 5. cron ------------------------------------------------------------------------------------------------------------
--    Job 63: lê o command VIVO (molde z93/z94: md5 do command) e troca só o sufixo da z84, preservando o prefixo
--    "select fin.contratos_hf_sincronizar(); " da z93 se ela já tiver sido aplicada. Command desconhecido → raise.
--    cron.alter_job por jobid (não cron.schedule): mantém jobid, dono e histórico. Idempotente (reaplicar = no-op).
do $cron$
declare
  c_z84  constant text := 'select count(*) from fin.resolver_ofertas_eventos(true, 45)';
  c_novo constant text := 'select count(*) from fin.resolver_ofertas_eventos(true, 45, null, ''academy'')';
  c_z93  constant text := 'select fin.contratos_hf_sincronizar(); ';
  v_id   bigint;
  v_cmd  text;
  v_md5  text;
begin
  select j.jobid, j.command into v_id, v_cmd from cron.job j where j.jobname = 'fin-oferta-evento-resolver';
  if v_id is null then
    raise exception 'z91: job fin-oferta-evento-resolver não existe';
  end if;
  v_md5 := md5(v_cmd);
  if v_md5 = 'ffb42c56f3eb43b9102f40d299ee515f' then            -- = md5(c_z84): z84 pura (lido 29/09 23:28)
    perform cron.alter_job(v_id, command := c_novo);
  elsif v_md5 = 'a29660ec49296c33885a7c5a2f1ad485' then         -- = md5(c_z93 || c_z84): z93 já aplicada
    perform cron.alter_job(v_id, command := c_z93 || c_novo);
  elsif v_cmd in (c_novo, c_z93 || c_novo) then
    null;                                                       -- z91 já aplicada
  else
    raise exception 'z91: command vivo do job % não é o da z84 nem o da z93 (md5 %): %. Reler e refazer.', v_id, v_md5, v_cmd;
  end if;
  if md5(c_z84) <> 'ffb42c56f3eb43b9102f40d299ee515f' or md5(c_z93 || c_z84) <> 'a29660ec49296c33885a7c5a2f1ad485' then
    raise exception 'z91: constantes do command divergem do md5 lido';
  end if;
end
$cron$;

--    Job irmão do escritório, mesmo horário. cron.schedule faz upsert por (jobname, username): aplicar como postgres.
select cron.schedule('fin-oferta-evento-resolver-escritorio', '25 * * * *',
  $$select count(*) from fin.hotmart_contas c
      cross join lateral fin.resolver_ofertas_eventos(true, 45, null, c.conta) r
     where c.conta = 'escritorio' and c.sincroniza$$);

do $conf_cron$
begin
  if (select command from cron.job where jobname = 'fin-oferta-evento-resolver')
       !~ '^(select fin\.contratos_hf_sincronizar\(\); )?select count\(\*\) from fin\.resolver_ofertas_eventos\(true, 45, null, ''academy''\)$'
     or (select count(*) from cron.job where jobname = 'fin-oferta-evento-resolver-escritorio' and username = 'postgres') <> 1 then
    raise exception 'z91: crons fora do esperado';
  end if;
end
$conf_cron$;
