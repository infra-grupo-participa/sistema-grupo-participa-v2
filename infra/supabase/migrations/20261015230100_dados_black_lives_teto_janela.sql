-- 20261015230100: teto de cota na janela da coleta da aba "Lives" (achado do pentester, 15/10/2026).
--
-- POR QUE: dados.black_live_na_janela devolvia verdadeiro para QUALQUER live com situação 'ao_vivo', sem limite. Se a Edge
-- parar de conseguir atualizar a situação (cota do YouTube estourada, chave revogada, falha repetida), a live fica
-- 'ao_vivo' para sempre no banco, a janela fica aberta para sempre e o cron chama a Edge todo minuto gastando cota (chat
-- ~5 unidades por chamada, a chave é compartilhada com o dashboard-ht). Esta migration põe um teto absoluto.
--
-- O QUE FAZ (só dados.black_live_na_janela; assinatura, grants e quem chama não mudam)
--   Antes: ao_vivo (sem limite) OU de 15 min antes até 3 h depois do horário previsto.
--   Agora: ao_vivo ATÉ 6 h depois do horário previsto OU de 15 min antes até 3 h depois do horário previsto.
--   Passadas 6 h do horário previsto a live deixa de manter a janela aberta mesmo que a situação diga 'ao_vivo'. O cron continua
--   chamando a cada 10 minutos (cadastro e foto), e é essa leitura que corrige a situação quando a API voltar.
--   (A trava de concorrência da Edge está em functions/black-youtube/index.ts, não no banco.)
--
-- AS 5 PERGUNTAS
--   escala: 9 lives, uma função de 1 linha chamada 1 vez por live ativa por minuto. Não cresce com a base.
--   índice: não lê tabela (recebe os valores por argumento). Nenhuma query nova.
--   frequência: chamada por black_live_pede_chamada() a cada minuto (9 avaliações) e por black_live_alvos() a cada chamada da Edge.
--   repetição: nenhuma tela.
--   reversão: 20261015230100_reversao.sql devolve o corpo anterior (byte a byte).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('dados.black_live_na_janela(timestamptz,text)') is null then
    raise exception '20261015230100: aplique antes 20261015220000 (black_live_na_janela ausente)';
  end if;
end
$g$;

create or replace function dados.black_live_na_janela(p_prevista timestamptz, p_situacao text) returns boolean
language sql stable set search_path = '' as $$
  select (p_situacao = 'ao_vivo' and now() <= p_prevista + interval '6 hours')
      or (now() >= p_prevista - interval '15 minutes' and now() <= p_prevista + interval '3 hours')
$$;

do $conf$
begin
  if has_function_privilege('anon', 'dados.black_live_na_janela(timestamptz,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.black_live_na_janela(timestamptz,text)', 'execute')
     or has_function_privilege('service_role', 'dados.black_live_na_janela(timestamptz,text)', 'execute') then
    raise exception '20261015230100: black_live_na_janela com grant aberto';
  end if;
  if (select p.prosrc from pg_proc p where p.oid = 'dados.black_live_na_janela(timestamptz,text)'::regprocedure) !~ '6 hours' then
    raise exception '20261015230100: corpo novo não está no banco';
  end if;
end
$conf$;
