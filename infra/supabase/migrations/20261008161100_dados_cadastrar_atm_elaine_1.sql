-- 20261008161100: cadastro do ATM 1 da Dra. Elaine (atm-elaine-1-2026-10) no modelo seminario-atm
--
-- STATUS: ESCRITA, NÃO APLICADA. Depende da 20261008161000. TRAVADA DE PROPÓSITO até alguém preencher a SIGLA (v_sigla
-- abaixo): a guarda aborta enquanto ela for nula. A sigla é decisão do Victor (dono do padrão de nomenclatura) e tem de
-- casar com '^[A-Z]{2,10}[0-9]{2,4}$' (check de mkt.projetos). Ela é o que liga os disparos da Mensageria ao projeto
-- ([SIGLA] no nome da campanha). Observado em 08/10: o disparo de e-mail "SEMATMOUT - BYTHEWAY" (sem colchete e sem
-- número, então não casa com o check; não usei).
-- Ensaio: dentro de 20261008161000_ensaio.sql (com sigla fictícia só na transação).
--
-- PARA VOLTAR: rodar o bloco REVERSÃO de 20261008161000_reversao.sql (parte "cadastro da edição"): apaga sessões, grupos
--   e listas da chave, a linha de dados.dashboards e o projeto (só se nenhum disparo, página ou lead apontar para ele).
--
-- O QUE CADASTRA (cada valor com a fonte)
--   mkt.projetos ......... etiqueta atm-elaine-1-2026-10 (briefing e CONTEXT.md do projeto no gp-operacoes); nome
--                          "ATM 1 da Dra. Elaine, outubro de 2026" (título da concepção); linha 'Seminário' (a mesma do
--                          SEMSET26); tipo interno, unidade escritorio (iguais ao SEMSET26); especialista 2 = Elaine
--                          Montenegro (mkt.especialistas); evento 13/10 a 15/10/2026 (live, replay, triplay: concepção).
--   dados.dashboards ..... modelo seminario-atm; conta escritorio (a oferta é a de 3.000 da Sessão de Viabilidade, produto
--                          5238525, conta escritorio em fin.hotmart_transacoes); oferta_codigo NULO (tarefa 86aktf1c3 do
--                          Arthur, "Configurar o checkout da oferta de 3.000", prazo 09/10: código ainda não existe);
--                          lista_ac_leads 615 ("Seminário ATM Outubro 2026 - Leads", criada 07/10, página ak1);
--                          lista_ac (pré-checkout) NULA (lista do gateway Guardiões do Legado não identificada);
--                          vendas_desde 07/10/2026 00:00 de São Paulo (início da reativação, concepção);
--                          ciclo_fecha_em NULO (hora do triplay em aberto na concepção, seção 7).
--   dados.sessoes ........ live 13/10/2026 19:30 de São Paulo (concepção). Replay e triplay: sem hora definida, não
--                          cadastrados.
--   dados.dashboard_grupos  nada: o nome da campanha do SendFlow do ATM não está no banco nem no CONTEXT.md
--                          (whatsapp_grupos: nao-encontrado).
--
-- Para preencher depois (cada um é um update/insert de 1 linha; exemplos em docs/dashboard-atm/MODELO-DE-DADOS.md §4):
--   oferta_codigo, lista_ac, ciclo_fecha_em, campanha do SendFlow, replay e triplay, pico e equipe de cada sessão.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $c$
declare
  v_sigla   text := null;   -- <<< PREENCHER (decisão do Victor). Ex. de formato: 'XXXX26'
  v_chave   text := 'atm-elaine-1-2026-10';
  v_proj    bigint;
begin
  if v_sigla is null then
    raise exception '20261008161100: sigla do projeto não definida. Preencher v_sigla com a sigla aprovada pelo Victor.';
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    raise exception '20261008161100: sigla % fora do padrão de mkt.projetos', v_sigla;
  end if;
  if to_regclass('dados.sessoes') is null then
    raise exception '20261008161100: aplicar antes a 20261008161000';
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup is distinct from v_chave) then
    raise exception '20261008161100: a sigla % já existe com outra etiqueta', v_sigla;
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave and sigla <> v_sigla) then
    raise exception '20261008161100: % já cadastrada com outra sigla', v_chave;
  end if;
  if (select nome from mkt.especialistas where id = 2) is distinct from 'Elaine Montenegro' then
    raise exception '20261008161100: especialista 2 não é mais Elaine Montenegro';
  end if;

  insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, tipo, unidade, especialista_id,
                            evento_inicio, evento_fim, obs)
  select v_sigla, 'ATM 1 da Dra. Elaine, outubro de 2026', 'Seminário', 2026, v_chave, 'interno', 'escritorio', 2,
         date '2026-10-13', date '2026-10-15', 'Seminário ATM, live 13/10 19h30. Card 86aktf11y. 20261008161100.'
   where not exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave);
  select id into v_proj from mkt.projetos where etiqueta_clickup = v_chave;

  insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, lista_ac_leads,
                                vendas_desde, ciclo_fecha_em)
  values (v_chave, 'seminario-atm', v_proj, 'escritorio', null, null, '615',
          timestamptz '2026-10-07 00:00:00-03', null)
  on conflict (chave) do nothing;

  insert into dados.sessoes (chave, tipo, inicio)
  values (v_chave, 'live', timestamptz '2026-10-13 19:30:00-03')
  on conflict (chave, tipo, inicio) do nothing;
end
$c$;
