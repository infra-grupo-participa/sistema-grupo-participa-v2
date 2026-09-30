-- 20261002a — Trajetória do aluno (fase 1, back-end): public.fn_aluno_trajetoria(p_aluno_id uuid)
--
-- POR QUÊ (Marcio, 30/09): a Base de alunos precisa mostrar a trajetória do aluno no Time Holding Brasil,
-- com tudo o que vem de fonte VIVA e CONFIÁVEL. Ficam fora: backup (ativacoes_bak_*), foto de planilha
-- (controle.aluno_historico), log técnico e casamento ambíguo.
--
-- O QUE FAZ
--   1. fin.trajetoria_nucleo(p_emails text[]) — o miolo compra→evento que estava em public.fn_fin_trajetoria
--      (corpo vivo = z79 SEM a linha de comentário "-- z79: oferta cadastrada...", md5(prosrc)
--      0c08041295469d56a0276e5fb33c3a8a, 5.299 caracteres; conferido: o corpo da z79 sem essa linha dá o mesmo md5).
--      SEM guarda, SECURITY INVOKER, revoke de public/anon/authenticated: só é chamado de dentro de funções
--      SECURITY DEFINER. Mesmas CTEs e laterais do corpo vivo; muda só:
--        a) alvo = unnest(p_emails) (antes: 1 e-mail); expandir por fin.identidade de novo é idempotente;
--        b) 5 colunas a mais no FIM: transacao, pedido_em, momento, email, grupo.
--      Lê SÓ fin.vw_transacoes (já filtrada conta = 'academy' na z89): passa pela trava trava_conta_hotmart (z89),
--      que só inspeciona corpos que citam hotmart_transacoes/vw_transacoes_contas.
--   2. public.fn_fin_trajetoria(text): mesma assinatura, guarda (gp_pode_ver_financeiro), saída e ordem
--      (dia, pedido_em); o corpo passa a chamar o núcleo.
--   3. public.fn_aluno_trajetoria(uuid): STABLE, SECURITY DEFINER, search_path ''; guarda da z57
--      (gp_eh_equipe → não devolve nada). Sem e-mail/telefone na saída. valor só com gp_pode_ver_financeiro().
--
-- FONTES INCLUÍDAS (dimensao)
--   compras      núcleo (recorrencia = 1; recusado/expirado já ficam fora no núcleo). Recorrência > 1 não vira linha:
--                resumo "7/12 pagas · 2 em atraso" no detalhe da compra de origem — só se a (email, oferta) tiver
--                UMA compra de origem (duas = casamento ambíguo → sem resumo). estornado → tipo 'estorno'.
--   vinculo      entrada_thb (thb_alunos.data_entrada_thb); cancelamento (thb_alunos.cancelado_em);
--                saida = estorno/chargeback da compra principal (HM/AURUM/THB, papel <> ingresso)
--                      | parcela OVERDUE/CANCELLED sem pagamento no mesmo (email, oferta) em 30 dias
--                      | cs.contatos_hm.cancelamento_efetivado_em ('cancelamento do card HM');
--                volta = 1ª compra paga HM/AURUM/THB depois de uma saída/cancelamento (renovação incluída);
--                        parcela paga (recorrência > 1) só conta como volta depois da saída do MESMO contrato.
--                troca_plano / tipo_entrada (thb_alunos_audit_log).
--   turma        turma de origem (núcleo: fin.acoes da 1ª compra HM/AURUM); turma atual e Aurum (thb_turmas);
--                troca de turma (audit_log campo turma_id, com o código da turma).
--   socios       titular: cada sócio (socio_de_aluno_id) em importado_em; convites gps.socio_convites e
--                central.convites_socio (enviado/aceito, SEM o e-mail do convidado); eh_socio (audit_log).
--                sócio: o vínculo com o titular.
--   eventos      gps.aluno_eventos: marcos (conta_criada, primeiro_acesso, entrou_no_programa, onboarding_*,
--                etapa_liberada_pela_equipe) e resultados do parceiro (honorários, contrato, adesão, croqui, minuta,
--                estudo de caso) viram linha; rotina vira 1 linha-resumo por mês; excluído/removido/reaberto/
--                desfavoritado/email_confirmado não entram. central.alunos (boas-vindas, Raio-X, debriefing),
--                central.participacoes (trilha iniciada/encerrada), gps.plantao_inscricoes (presença; inscrição
--                não cancelada sem presença; cancelada não entra).
--   grupos       controle.grupo_evento_unificado por fone_key = controle.fone_key() (DDD + 8 últimos dígitos, 10 no total), só se a chave não casar com
--                NENHUM OUTRO aluno ativo (medido pela sessão principal: 12 chaves colididas em 1.833).
--   atendimento  cs.contatos_hm (entrada no card, reunião, entrevista, pagamento, quitação, pedido de cancelamento,
--                cancelado na Hotmart, acessos revogados); audit_log nivel_resultado, status_acesso_central,
--                placa_solicitacao_id ("solicitou placa").
-- FONTES EXCLUÍDAS
--   thb_system_events: "Sync comprador→aluno" (técnico) e "Espaço de instrução corrigido" (técnico) fora;
--     "Nível atualizado via placa aprovada" (17) também fora: é o mesmo fato do audit_log nivel_resultado (17),
--     que já entra — e thb_system_events não tem índice por aluno_id conhecido.
--   public.ativacoes_bak_*, controle.aluno_historico, e-mails do mailer, logs de erro: regra do Marcio.
--   thb_alunos.acessos_revogados_em / retornou_em: duplicaria o card / 0 preenchidos.
--
-- ÍNDICES: 1 novo, ix_thb_alunos_fone_key_ativo (checagem de colisão do telefone: 36,8 → 1,3 ms). Filtros: thb_alunos (PK), fin.identidade (no), fin.vw_transacoes email = any(...)
--   (hotmart_transacoes_email_idx / hotmart_transacoes_contrato_rec_idx, mesma expressão lower(TRIM(BOTH FROM ...))),
--   gps.aluno_eventos idx_aluno_eventos_timeline, thb_alunos_audit_log (aluno_id, criado_em desc),
--   central.participacoes (aluno_id, status), gps.plantao_inscricoes (aluno_plantao_id, inscrito_em desc),
--   controle.grupo_evento_unificado ix_geu_fone. SEM índice conhecido (tabelas pequenas, a medir no ensaio):
--   cs.contatos_hm(aluno_id), central.alunos(email), gps.plantao_alunos(email), gps.socio_convites,
--   central.convites_socio, thb_alunos(socio_de_aluno_id) e a varredura de thb_alunos para a colisão de fone_key.
--
-- AS 5 PERGUNTAS
--   escala: 1 aluno por chamada; o maior custo é o núcleo (mesmo de fn_fin_trajetoria) + transações recorrentes
--     da pessoa (index scan por e-mail) + seq scan de thb_alunos (~2 mil linhas) para a colisão de fone_key.
--   índice: acima. frequência: 1 chamada por abertura da aba Trajetória. repetição: nenhuma query por linha fora
--     das CTEs materializadas. reversão: bloco REVERSÃO no fim.
--
-- ENSAIO e MEDIÇÃO: bloco no fim do arquivo (begin … rollback), para a sessão principal.

set local lock_timeout = '5s';

-- ─── 0. Guardas (falham ANTES de gravar) ───────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_src  text;
  v_falta text;
  v_n    bigint;
  v_fk   text;
begin
  -- 0.1 corpo vivo de fn_fin_trajetoria = o medido em 30/09 (ou já é esta versão)
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.fn_fin_trajetoria(text)'::regprocedure;
  if md5(v_src) <> '0c08041295469d56a0276e5fb33c3a8a' and position('trajetoria_nucleo' in v_src) = 0 then
    raise exception '20261002a: corpo vivo de public.fn_fin_trajetoria mudou (md5 %, esperado 0c08041295469d56a0276e5fb33c3a8a)', md5(v_src);
  end if;

  -- 0.2 colunas usadas existem; as de data são timestamptz (date convertido com at time zone mudaria o dia)
  select string_agg(format('%s.%s.%s (%s)', x.s, x.t, x.c, coalesce(c.data_type, 'AUSENTE')), ', ')
    into v_falta
    from (values
      ('public','thb_alunos','email',null), ('public','thb_alunos','nome',null), ('public','thb_alunos','telefone',null),
      ('public','thb_alunos','telefone_e164',null), ('public','thb_alunos','data_entrada_thb','date'),
      ('public','thb_alunos','tipo_entrada',null), ('public','thb_alunos','canal_aquisicao',null),
      ('public','thb_alunos','cancelado_em','timestamp with time zone'), ('public','thb_alunos','cancelado_motivo',null),
      ('public','thb_alunos','importado_em','timestamp with time zone'), ('public','thb_alunos','socio_de_aluno_id','uuid'),
      ('public','thb_alunos','turma_id',null), ('public','thb_alunos','turma_aurum_id',null),
      ('public','thb_turmas','codigo',null), ('public','thb_turmas','tipo',null),
      ('public','thb_alunos_audit_log','id',null), ('public','thb_alunos_audit_log','aluno_id','uuid'),
      ('public','thb_alunos_audit_log','campo',null), ('public','thb_alunos_audit_log','valor_anterior',null),
      ('public','thb_alunos_audit_log','valor_novo',null), ('public','thb_alunos_audit_log','origem',null),
      ('public','thb_alunos_audit_log','criado_em','timestamp with time zone'),
      ('gps','aluno_eventos','id',null), ('gps','aluno_eventos','aluno_id','uuid'), ('gps','aluno_eventos','tipo',null),
      ('gps','aluno_eventos','rotulo',null), ('gps','aluno_eventos','ocorrido_em','timestamp with time zone'),
      ('central','alunos','id',null), ('central','alunos','email',null),
      ('central','alunos','boas_vindas_em','timestamp with time zone'), ('central','alunos','raiox_at','timestamp with time zone'),
      ('central','alunos','debriefing_liberado_em','timestamp with time zone'),
      ('central','participacoes','id',null), ('central','participacoes','aluno_id',null),
      ('central','participacoes','trilha_slug',null), ('central','participacoes','numero',null),
      ('central','participacoes','faixa',null), ('central','participacoes','status',null),
      ('central','participacoes','iniciada_em','timestamp with time zone'),
      ('central','participacoes','encerrada_em','timestamp with time zone'),
      ('central','participacoes','itens_feitos',null), ('central','participacoes','itens_total',null),
      ('central','participacoes','pct',null), ('central','participacoes','motivo',null),
      ('central','convites_socio','id',null), ('central','convites_socio','titular_id',null),
      ('central','convites_socio','created_at','timestamp with time zone'),
      ('central','convites_socio','aceito_em','timestamp with time zone'),
      ('gps','socio_convites','id',null), ('gps','socio_convites','ambiente_aluno_id',null),
      ('gps','socio_convites','status',null), ('gps','socio_convites','criado_em','timestamp with time zone'),
      ('gps','socio_convites','aceito_em','timestamp with time zone'),
      ('gps','plantao_alunos','id',null), ('gps','plantao_alunos','email',null),
      ('gps','plantao_inscricoes','id',null), ('gps','plantao_inscricoes','aluno_plantao_id',null),
      ('gps','plantao_inscricoes','semana',null), ('gps','plantao_inscricoes','nps_nota',null),
      ('gps','plantao_inscricoes','inscrito_em','timestamp with time zone'),
      ('gps','plantao_inscricoes','cancelado_em','timestamp with time zone'),
      ('gps','plantao_inscricoes','presenca_em','timestamp with time zone'),
      ('controle','grupo_evento_unificado','fone_key',null), ('controle','grupo_evento_unificado','group_name',null),
      ('controle','grupo_evento_unificado','tipo',null), ('controle','grupo_evento_unificado','fonte',null),
      ('controle','grupo_evento_unificado','ocorreu_em','timestamp with time zone'),
      ('cs','contatos_hm','id',null), ('cs','contatos_hm','aluno_id','uuid'), ('cs','contatos_hm','produto',null),
      ('cs','contatos_hm','turma',null), ('cs','contatos_hm','plano',null),
      ('cs','contatos_hm','entrevista_resultado',null), ('cs','contatos_hm','cancelamento_motivo_tipo',null),
      ('cs','contatos_hm','entrada_em','timestamp with time zone'), ('cs','contatos_hm','criado_em','timestamp with time zone'),
      ('cs','contatos_hm','reuniao_em','timestamp with time zone'), ('cs','contatos_hm','entrevista_em','timestamp with time zone'),
      ('cs','contatos_hm','pagamento_em','timestamp with time zone'), ('cs','contatos_hm','quitado_em','timestamp with time zone'),
      ('cs','contatos_hm','cancelamento_em','timestamp with time zone'),
      ('cs','contatos_hm','cancelamento_efetivado_em','timestamp with time zone'),
      ('cs','contatos_hm','hotmart_cancelado_em','timestamp with time zone'),
      ('cs','contatos_hm','acessos_revogados_em','timestamp with time zone')
    ) x(s, t, c, tipo)
    left join information_schema.columns c
      on c.table_schema = x.s and c.table_name = x.t and c.column_name = x.c
   where c.column_name is null or (x.tipo is not null and c.data_type <> x.tipo);
  if v_falta is not null then
    raise exception '20261002a: coluna ausente ou de tipo diferente do previsto: %', v_falta;
  end if;

  -- 0.3 premissas de ligação (pedidas pela sessão principal): FK declarada, ou dado 100% casando
  --     central.participacoes.aluno_id  → central.alunos.id   (NÃO thb_alunos.id)
  --     central.convites_socio.titular_id → central.alunos.id
  --     gps.socio_convites.ambiente_aluno_id → public.thb_alunos.id
  --     gps.plantao_inscricoes.aluno_plantao_id → gps.plantao_alunos.id
  for v_fk in
    select * from (values
      ('central.participacoes|aluno_id|central.alunos'),
      ('central.convites_socio|titular_id|central.alunos'),
      ('gps.socio_convites|ambiente_aluno_id|public.thb_alunos'),
      ('gps.plantao_inscricoes|aluno_plantao_id|gps.plantao_alunos')
    ) v(x)
  loop
    select count(*) into v_n
      from pg_constraint k
      join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
     where k.contype = 'f' and k.conrelid = split_part(v_fk, '|', 1)::regclass
       and a.attname = split_part(v_fk, '|', 2)
       and k.confrelid <> split_part(v_fk, '|', 3)::regclass;
    if v_n > 0 then
      raise exception '20261002a: % tem FK para outra tabela que não %', split_part(v_fk, '|', 1) || '.' || split_part(v_fk, '|', 2), split_part(v_fk, '|', 3);
    end if;
    execute format('select count(*) from %s x where x.%I is not null and not exists (select 1 from %s y where y.id = x.%I)',
                   split_part(v_fk, '|', 1), split_part(v_fk, '|', 2), split_part(v_fk, '|', 3), split_part(v_fk, '|', 2))
      into v_n;
    if v_n > 0 then
      raise exception '20261002a: % linha(s) de %.% não casam com %.id — premissa de ligação falsa',
        v_n, split_part(v_fk, '|', 1), split_part(v_fk, '|', 2), split_part(v_fk, '|', 3);
    end if;
  end loop;

  -- 0.4 fone_key da tabela = controle.fone_key() = DDD + 8 últimos dígitos (10); a chave do aluno usa a MESMA função
  select count(*) into v_n
    from (select g.fone_key from controle.grupo_evento_unificado g where g.fone_key is not null limit 20000) s
   where s.fone_key !~ '^[0-9]{10}$';
  if v_n > 0 then
    raise exception '20261002a: % fone_key fora do formato de 10 dígitos (controle.fone_key) em controle.grupo_evento_unificado', v_n;
  end if;
end $guarda$;


-- ─── 1. Núcleo compra→evento (corpo vivo de fn_fin_trajetoria, sem guarda) ─────────────────────────────────────────
create or replace function fin.trajetoria_nucleo(p_emails text[])
returns table (dia date, familia text, produto text, oferta text, situacao text, valor numeric, parcelas int,
               papel text, evento_id bigint, evento text, evento_categoria text, turma text, regra_evento text,
               transacao text, pedido_em timestamptz, momento timestamptz, email text, grupo text)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
begin
  return query
  with alvo as (
    select distinct lower(trim(u.e)) email from unnest(p_emails) u(e)
  ), emails as (
    select distinct coalesce(substr(i2.no, 3), a.email) email
      from alvo a
      left join fin.identidade i on i.no = 'e:' || a.email
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
  ), evs as (
    select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
      from fin.eventos e
  ), tx as (
    select t.*, coalesce(t.dia_aprovado, t.dia_pedido) d, cat.categoria cat
      from emails e
      join fin.vw_transacoes t on t.email = e.email
      left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
     where t.grupo in ('pago','estornado','atrasado','em_aberto') and coalesce(t.recorrencia, 1) = 1
  )
  select x.d, x.familia, x.produto_nome, x.oferta_codigo,
         case x.grupo when 'pago' then 'pago' when 'estornado' then 'estornado' when 'atrasado' then 'em atraso' else 'em aberto' end,
         round(x.valor_oferta * case when x.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(x.parcelas, 1) else 1 end, 2),
         x.parcelas,
         case when ev.regra = 'ingresso do evento' then 'ingresso'
              when x.produto_id = '5064314' and x.d >= date '2026-06-25' and coalesce(x.cat, '') not in ('renovacao','reserva') then 'programa'
              else 'compra' end,
         ev.id, ev.nome, ev.categoria,
         tor.turma,
         ev.regra,
         x.transacao::text, x.pedido_em::timestamptz, coalesce(x.aprovado_em, x.pedido_em)::timestamptz,
         x.email::text, x.grupo::text
    from tx x
    left join lateral (
      select e.id, e.nome, e.categoria,
             case when exists (select 1 from fin.evento_produtos ep
                                where ep.categoria = e.categoria and ep.produto_id = x.produto_id and ep.papel = 'ingresso')
                  then 'ingresso do evento' else 'oferta do evento' end regra
        from fin.evento_ofertas eo
        join fin.eventos e on e.id = eo.evento_id
       where eo.oferta_codigo = x.oferta_codigo
       limit 1
    ) evo on true
    left join lateral (
      select e.id, e.nome, e.categoria, case when ep.papel = 'ingresso' then 'ingresso do evento' else 'oferta do evento' end regra
        from evs e
        join fin.evento_produtos ep on ep.categoria = e.categoria and ep.produto_id = x.produto_id
       where evo.id is null
         and ((ep.papel = 'ingresso' and x.d between e.ing_de and e.venda_ate)
           or (ep.papel = 'oferta' and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate))
       order by (ep.papel = 'oferta') desc, e.venda_ate, e.inicio limit 1
    ) ev0 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'dia do evento'::text regra
        from fin.eventos e
       where evo.id is null and ev0.id is null and e.setor = 'educacao'
         and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
         and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1
    ) ev1 on true
    left join lateral (
      select e.id, e.nome, e.categoria, 'depois do evento'::text regra
        from fin.eventos e
       where evo.id is null and ev0.id is null and ev1.id is null and e.setor = 'educacao'
         and e.venda_ate < x.d and e.venda_ate >= x.d - 30
         and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
       order by e.venda_ate desc limit 1
    ) ev2 on true
    left join lateral (
      select null::bigint id, a.nome, 'aurum_turma'::text categoria, 'lançamento da turma Aurum'::text regra
        from fin.acoes a
       where evo.id is null and ev0.id is null and ev1.id is null and ev2.id is null and x.familia = 'AURUM'
         and a.produto = 'AURUM' and a.prioridade = 50
         and (x.d::timestamp at time zone 'America/Sao_Paulo') >= a.inicio and (x.d::timestamp at time zone 'America/Sao_Paulo') < a.fim
       limit 1
    ) ev3 on true
    cross join lateral (select coalesce(evo.id, ev0.id, ev1.id, ev2.id) id,
                               coalesce(evo.nome, ev0.nome, ev1.nome, ev2.nome, ev3.nome) nome,
                               coalesce(evo.categoria, ev0.categoria, ev1.categoria, ev2.categoria, ev3.categoria) categoria,
                               coalesce(evo.regra, ev0.regra, ev1.regra, ev2.regra, ev3.regra) regra) ev
    left join lateral (select a.turma from fin.acoes a
                        where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) >= a.inicio
                          and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
                                where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) < a.fim
                        order by a.prioridade desc, a.inicio desc limit 1) tor on true
   order by x.d, x.pedido_em;
end
$$;
comment on function fin.trajetoria_nucleo(text[]) is
  'Miolo compra→evento (regra da fn_fin_trajetoria, z79). SEM guarda: só para funções SECURITY DEFINER que já guardam o acesso. 20261002a.';
revoke all on function fin.trajetoria_nucleo(text[]) from public, anon, authenticated;


-- ─── 2. fn_fin_trajetoria: mesma assinatura, guarda e saída; corpo chama o núcleo ─────────────────────────────────
create or replace function public.fn_fin_trajetoria(p_email text)
returns table (dia date, familia text, produto text, oferta text, situacao text, valor numeric, parcelas int,
               papel text, evento_id bigint, evento text, evento_categoria text, turma text, regra_evento text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  select n.dia, n.familia, n.produto, n.oferta, n.situacao, n.valor, n.parcelas, n.papel,
         n.evento_id, n.evento, n.evento_categoria, n.turma, n.regra_evento
    from fin.trajetoria_nucleo(array[lower(trim(p_email))]) n
   order by n.dia, n.pedido_em;
end
$$;
revoke all on function public.fn_fin_trajetoria(text) from public, anon;
grant execute on function public.fn_fin_trajetoria(text) to authenticated;


-- Índice da checagem de colisão do telefone (roda a cada ficha aberta). Medido 30/09 em 1.884 linhas:
-- Seq Scan 36,8 ms → Index Scan 1,3 ms; 80 kB. Parcial: só aluno ativo entra na comparação.
create index if not exists ix_thb_alunos_fone_key_ativo
  on public.thb_alunos (controle.fone_key(coalesce(telefone_e164, telefone))) where cancelado_em is null;

-- ─── 3. fn_aluno_trajetoria ─────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_aluno_trajetoria(p_aluno_id uuid)
returns table (dia date, momento timestamptz, dimensao text, tipo text, titulo text, detalhe text, valor numeric,
               situacao text, fonte text, regra text, ref text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_al     public.thb_alunos%rowtype;
  v_emails text[];
  v_fin    boolean;
  v_key    text;
  v_key_ok boolean := false;
begin
  if not coalesce(public.gp_eh_equipe(), false) then return; end if;

  select a.* into v_al from public.thb_alunos a where a.id = p_aluno_id;
  if not found then return; end if;

  v_fin := coalesce(public.gp_pode_ver_financeiro(), false);

  -- e-mails da pessoa: lower(trim(both from email)) (expressão do índice de e-mail do espelho), expandida por fin.identidade
  select coalesce(array_agg(distinct coalesce(substr(i2.no, 3), b.email)), '{}'::text[])
    into v_emails
    from (select lower(trim(both from v_al.email)) email) b
    left join fin.identidade i on i.no = 'e:' || b.email
    left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
   where coalesce(b.email, '') <> '';

  -- chave de telefone: controle.fone_key (a mesma que grava a tabela); só vale se nenhum OUTRO aluno ativo tiver a mesma chave
  v_key := controle.fone_key(coalesce(v_al.telefone_e164, v_al.telefone));
  if v_key is not null then
    v_key_ok := not exists (
      select 1 from public.thb_alunos o
       where o.id <> v_al.id and o.cancelado_em is null
         and controle.fone_key(coalesce(o.telefone_e164, o.telefone)) = v_key);
  end if;

  return query
  with n as (
    select * from fin.trajetoria_nucleo(v_emails)
  ), rec as (          -- parcelas de contrato (recorrência) da pessoa
    select t.email, t.oferta_codigo, t.recorrencia, t.grupo, t.status, t.familia, t.transacao::text transacao,
           t.produto_nome, coalesce(t.aprovado_em, t.pedido_em) momento
      from fin.vw_transacoes t
     where t.email = any (v_emails) and t.recorrencia is not null
  ), rr as (
    select r.email, r.oferta_codigo, r.recorrencia, bool_or(r.grupo = 'pago') pg, bool_or(r.grupo = 'atrasado') atr
      from rec r group by 1, 2, 3
  ), rs as (
    select r.email, r.oferta_codigo, max(r.recorrencia) mx,
           count(*) filter (where r.pg) pagas, count(*) filter (where r.atr and not r.pg) atraso
      from rr r group by 1, 2
  ), orig as (
    select n.email, n.oferta, count(*) q from n group by 1, 2
  ), sai as (          -- saídas e cancelamentos (base para 'volta')
    select n.dia, n.momento, 'saida'::text tipo, 'estorno/chargeback da compra principal'::text regra,
           'Hotmart'::text fonte, n.transacao ref, null::text email, null::text oferta,
           coalesce(n.produto, n.oferta) titulo
      from n
     where n.grupo = 'estornado' and n.familia in ('HM','AURUM','THB') and n.papel <> 'ingresso'
    union all
    select (q.momento at time zone 'America/Sao_Paulo')::date, q.momento, 'saida',
           'parcela ' || q.status || ' sem pagamento no contrato em 30 dias', 'Hotmart', q.transacao,
           q.email, q.oferta_codigo, q.produto_nome
      from rec q
     where q.status in ('OVERDUE','CANCELLED') and q.familia in ('HM','AURUM','THB')
       and q.momento <= now() - interval '30 days'
       and not exists (select 1 from rec p
                        where p.email = q.email and p.oferta_codigo = q.oferta_codigo and p.grupo = 'pago'
                          and p.momento > q.momento and p.momento <= q.momento + interval '30 days')
       and not exists (select 1 from rec q2   -- mesma saída já aberta por parcela anterior, sem pagamento entre elas
                        where q2.email = q.email and q2.oferta_codigo = q.oferta_codigo
                          and q2.status in ('OVERDUE','CANCELLED') and q2.momento < q.momento
                          and not exists (select 1 from rec p2
                                           where p2.email = q.email and p2.oferta_codigo = q.oferta_codigo
                                             and p2.grupo = 'pago' and p2.momento > q2.momento and p2.momento < q.momento))
    union all
    select (c.cancelamento_efetivado_em at time zone 'America/Sao_Paulo')::date, c.cancelamento_efetivado_em, 'saida',
           'cancelamento do card HM', 'Card HM', c.id::text, null, null, 'Card ' || coalesce(c.produto::text, 'HM')
      from cs.contatos_hm c
     where c.aluno_id = v_al.id and c.cancelamento_efetivado_em is not null
    union all
    select (v_al.cancelado_em at time zone 'America/Sao_Paulo')::date, v_al.cancelado_em, 'cancelamento',
           'thb_alunos.cancelado_em', 'Base de alunos', v_al.id::text, null, null, v_al.cancelado_motivo::text
     where v_al.cancelado_em is not null
  ), vc as (           -- candidatas a 'volta'
    select n.momento, n.dia, n.transacao ref, coalesce(n.produto, n.oferta) titulo, n.familia,
           n.email, n.oferta, false recur
      from n where n.grupo = 'pago' and n.familia in ('HM','AURUM','THB') and n.papel <> 'ingresso'
    union all
    select r.momento, (r.momento at time zone 'America/Sao_Paulo')::date, r.transacao, r.produto_nome, r.familia,
           r.email, r.oferta_codigo, true
      from rec r where r.grupo = 'pago' and r.familia in ('HM','AURUM','THB') and r.recorrencia > 1
  ), volta as (
    select distinct on (p.ref) p.*, s.regra regra_saida
      from vc p
      join sai s on s.momento < p.momento and (not p.recur or (s.email = p.email and s.oferta = p.oferta))
     where not exists (select 1 from vc p2
                        where p2.momento > s.momento and p2.momento < p.momento
                          and (not p2.recur or (s.email = p2.email and s.oferta = p2.oferta)))
     order by p.ref, s.momento desc
  ), ev_rot as (       -- rotina do GPS: 1 linha por mês
    select date_trunc('month', e.ocorrido_em at time zone 'America/Sao_Paulo') mes, max(e.ocorrido_em) ult,
           count(*) filter (where e.tipo = 'cliente_cadastrado') cad,
           count(*) filter (where e.tipo = 'tarefa_concluida') tar,
           count(*) filter (where e.tipo in ('cliente_favoritado','favorito_confirmado_pela_equipe')) fav,
           count(*) filter (where e.tipo = 'cliente_mensagem_padrao') msg,
           count(*) filter (where e.tipo = 'cliente_ligacao') lig,
           count(*) filter (where e.tipo = 'cliente_reuniao_agendada') reu,
           count(*) filter (where e.tipo = 'cliente_fase_mudou') fas,
           count(*) filter (where e.tipo = 'cliente_selecionado_entrevista') ent,
           count(*) filter (where e.tipo = 'cliente_documento_lido') doc
      from gps.aluno_eventos e
     where e.aluno_id = v_al.id
       and e.tipo in ('cliente_cadastrado','tarefa_concluida','cliente_favoritado','favorito_confirmado_pela_equipe',
                      'cliente_mensagem_padrao','cliente_ligacao','cliente_reuniao_agendada','cliente_fase_mudou',
                      'cliente_selecionado_entrevista','cliente_documento_lido')
     group by 1
  ), ca as (
    select a.* from central.alunos a where lower(trim(both from a.email)) = any (v_emails)
  ), u (dia, momento, dimensao, tipo, titulo, detalhe, valor, situacao, fonte, regra, ref) as (
    -- compras
    select n.dia::date, n.momento::timestamptz, 'compras'::text,
           (case when n.grupo = 'estornado' then 'estorno' else n.papel end)::text,
           coalesce(n.produto, n.oferta)::text,
           nullif(concat_ws(' · ',
             n.evento,
             case when n.papel = 'programa' and n.turma is not null then 'turma ' || n.turma end,
             case when v_fin and rs.mx > 1 and o.q = 1 then
                    rs.pagas || '/' || greatest(coalesce(n.parcelas, 0), rs.mx) || ' pagas'
                    || case when rs.atraso > 0 then ' · ' || rs.atraso || ' em atraso' else '' end end), '')::text,
           (case when v_fin then n.valor end)::numeric,
           (case when v_fin then n.situacao end)::text, 'Hotmart'::text, n.regra_evento::text, n.transacao::text
      from n
      left join orig o on o.email = n.email and o.oferta is not distinct from n.oferta
      left join rs on rs.email = n.email and rs.oferta_codigo = n.oferta
    -- vínculo
    union all
    select v_al.data_entrada_thb, null, 'vinculo', 'entrada_thb', 'Entrada no Time Holding Brasil',
           nullif(concat_ws(' · ', v_al.tipo_entrada::text, v_al.canal_aquisicao::text), ''), null, null,
           'Base de alunos', 'thb_alunos.data_entrada_thb', v_al.id::text
     where v_al.data_entrada_thb is not null
    union all
    select s.dia, s.momento, 'vinculo', s.tipo,
           case s.tipo when 'saida' then 'Saída do THB' else 'Cancelamento na base de alunos' end,
           s.titulo, null, null, s.fonte, s.regra, s.ref
      from sai s
    union all
    select v.dia, v.momento, 'vinculo', 'volta', 'Volta ao THB', v.titulo, null, 'pago', 'Hotmart',
           'compra paga ' || v.familia || ' depois de: ' || v.regra_saida, v.ref
      from volta v
    -- turma
    union all
    select min(n.dia), min(n.momento), 'turma', 'turma_origem', 'Turma de origem ' || n.turma, null, null, null,
           'fin.acoes', 'turma da 1ª compra HM/AURUM', null
      from n
     where n.turma is not null and n.familia in ('HM','AURUM') and n.grupo in ('pago','estornado')
     group by n.turma
    union all
    select coalesce((ult.criado_em at time zone 'America/Sao_Paulo')::date, v_al.data_entrada_thb,
                    (v_al.importado_em at time zone 'America/Sao_Paulo')::date),
           ult.criado_em, 'turma', x.tipo, x.rotulo || ' ' || coalesce(tt.codigo::text, '?'), tt.tipo::text, null, null,
           'Base de alunos', 'thb_alunos.' || x.campo, tt.id::text
      from (values ('turma_atual', 'Turma atual', 'turma_id', v_al.turma_id::text),
                   ('turma_aurum', 'Turma Aurum', 'turma_aurum_id', v_al.turma_aurum_id::text)) x(tipo, rotulo, campo, tid)
      join public.thb_turmas tt on tt.id::text = x.tid
      left join lateral (select l.criado_em from public.thb_alunos_audit_log l
                          where l.aluno_id = v_al.id and l.campo = x.campo
                          order by l.criado_em desc limit 1) ult on true
    -- audit_log (campos relevantes; telefone/nome/endereço/instrução ficam fora)
    union all
    select (l.criado_em at time zone 'America/Sao_Paulo')::date, l.criado_em,
           case l.campo when 'turma_id' then 'turma' when 'eh_socio' then 'socios'
                        when 'plano' then 'vinculo' when 'tipo_entrada' then 'vinculo' else 'atendimento' end,
           case l.campo when 'turma_id' then 'troca_turma' when 'eh_socio' then 'marcado_socio'
                        when 'nivel_resultado' then 'nivel' when 'plano' then 'troca_plano'
                        when 'status_acesso_central' then 'acesso_central' when 'placa_solicitacao_id' then 'solicitou_placa'
                        else 'tipo_entrada' end,
           case l.campo when 'turma_id' then 'Troca de turma' when 'eh_socio' then 'Marcação de sócio'
                        when 'nivel_resultado' then 'Nível de resultado' when 'plano' then 'Troca de plano'
                        when 'status_acesso_central' then 'Acesso à Central' when 'placa_solicitacao_id' then 'Solicitou placa'
                        else 'Tipo de entrada' end,
           case l.campo when 'placa_solicitacao_id' then null
                        when 'turma_id' then coalesce(ta.codigo::text, l.valor_anterior::text, '—') || ' → ' || coalesce(tn.codigo::text, l.valor_novo::text, '—')
                        else coalesce(l.valor_anterior::text, '—') || ' → ' || coalesce(l.valor_novo::text, '—') end,
           null, null, 'Base de alunos (' || coalesce(l.origem::text, '?') || ')', 'thb_alunos_audit_log.' || l.campo, l.id::text
      from public.thb_alunos_audit_log l
      left join public.thb_turmas ta on l.campo = 'turma_id' and ta.id::text = l.valor_anterior::text
      left join public.thb_turmas tn on l.campo = 'turma_id' and tn.id::text = l.valor_novo::text
     where l.aluno_id = v_al.id
       and l.campo in ('turma_id','eh_socio','nivel_resultado','plano','status_acesso_central','placa_solicitacao_id','tipo_entrada')
       and not (l.campo = 'placa_solicitacao_id' and l.valor_novo is null)
    -- sócios
    union all
    select (s.importado_em at time zone 'America/Sao_Paulo')::date, s.importado_em, 'socios', 'socio_vinculado',
           'Sócio vinculado: ' || coalesce(s.nome::text, '?'), null, null,
           case when s.cancelado_em is null then 'ativo' else 'cancelado' end,
           'Base de alunos', 'thb_alunos.socio_de_aluno_id', s.id::text
      from public.thb_alunos s where s.socio_de_aluno_id = v_al.id
    union all
    select (v_al.importado_em at time zone 'America/Sao_Paulo')::date, v_al.importado_em, 'socios', 'socio_de',
           'Sócio de ' || coalesce(t.nome::text, '?'), null, null,
           case when t.cancelado_em is null then 'ativo' else 'cancelado' end,
           'Base de alunos', 'thb_alunos.socio_de_aluno_id', t.id::text
      from public.thb_alunos t where t.id = v_al.socio_de_aluno_id
    union all
    select (m.em at time zone 'America/Sao_Paulo')::date, m.em, 'socios', m.tipo, m.titulo, null, null,
           c.status::text, 'GPS', 'gps.socio_convites', c.id::text
      from gps.socio_convites c
      cross join lateral (values ('convite_socio', 'Convite de sócio enviado (GPS)', c.criado_em),
                                 ('convite_socio_aceito', 'Convite de sócio aceito (GPS)', c.aceito_em)) m(tipo, titulo, em)
     where c.ambiente_aluno_id = v_al.id and m.em is not null
    union all
    select (m.em at time zone 'America/Sao_Paulo')::date, m.em, 'socios', m.tipo, m.titulo, null, null, null,
           'Central', 'central.convites_socio', c.id::text
      from ca join central.convites_socio c on c.titular_id = ca.id
      cross join lateral (values ('convite_socio', 'Convite de sócio enviado (Central)', c.created_at),
                                 ('convite_socio_aceito', 'Convite de sócio aceito (Central)', c.aceito_em)) m(tipo, titulo, em)
     where m.em is not null
    -- eventos: GPS (marcos e resultados)
    union all
    select (e.ocorrido_em at time zone 'America/Sao_Paulo')::date, e.ocorrido_em, 'eventos', e.tipo::text,
           case e.tipo when 'conta_criada' then 'Conta criada no GPS' when 'primeiro_acesso' then 'Primeiro acesso ao GPS'
                       when 'entrou_no_programa' then 'Entrou no programa' when 'onboarding_iniciado' then 'Onboarding iniciado'
                       when 'onboarding_concluido' then 'Onboarding concluído' when 'etapa_liberada_pela_equipe' then 'Etapa liberada pela equipe'
                       when 'cliente_honorarios_definidos' then 'Honorários definidos com cliente'
                       when 'cliente_contrato_anexado' then 'Contrato de cliente anexado'
                       when 'cliente_aderiu_reuniao' then 'Cliente aderiu na reunião'
                       when 'cliente_croqui_anexado' then 'Croqui anexado' when 'cliente_minuta_anexada' then 'Minuta anexada'
                       else 'Estudo de caso' end,
           e.rotulo::text, null, null, 'GPS',
           case when e.tipo like 'cliente\_%' then 'resultado do parceiro' else 'marco do GPS' end, e.id::text
      from gps.aluno_eventos e
     where e.aluno_id = v_al.id
       and e.tipo in ('conta_criada','primeiro_acesso','entrou_no_programa','onboarding_iniciado','onboarding_concluido',
                      'etapa_liberada_pela_equipe','cliente_honorarios_definidos','cliente_contrato_anexado',
                      'cliente_aderiu_reuniao','cliente_croqui_anexado','cliente_minuta_anexada','cliente_estudo_caso')
    union all
    select (r.ult at time zone 'America/Sao_Paulo')::date, r.ult, 'eventos', 'atividade_mes',
           'Atividade no GPS em ' || (array['jan','fev','mar','abr','mai','jun','jul','ago','set','out','nov','dez'])[extract(month from r.mes)::int]
             || '/' || extract(year from r.mes)::int,
           nullif(concat_ws(' · ',
             case when r.cad > 0 then r.cad || case when r.cad = 1 then ' cliente cadastrado' else ' clientes cadastrados' end end,
             case when r.tar > 0 then r.tar || case when r.tar = 1 then ' tarefa concluída' else ' tarefas concluídas' end end,
             case when r.reu > 0 then r.reu || case when r.reu = 1 then ' reunião agendada' else ' reuniões agendadas' end end,
             case when r.ent > 0 then r.ent || case when r.ent = 1 then ' selecionado para entrevista' else ' selecionados para entrevista' end end,
             case when r.fas > 0 then r.fas || case when r.fas = 1 then ' mudança de fase' else ' mudanças de fase' end end,
             case when r.lig > 0 then r.lig || case when r.lig = 1 then ' ligação' else ' ligações' end end,
             case when r.msg > 0 then r.msg || case when r.msg = 1 then ' mensagem' else ' mensagens' end end,
             case when r.fav > 0 then r.fav || case when r.fav = 1 then ' favorito' else ' favoritos' end end,
             case when r.doc > 0 then r.doc || case when r.doc = 1 then ' documento lido' else ' documentos lidos' end end), ''),
           null, null, 'GPS', 'resumo mensal da atividade de rotina', to_char(r.mes, 'YYYY-MM')
      from ev_rot r
    -- eventos: Central
    union all
    select (m.em at time zone 'America/Sao_Paulo')::date, m.em, 'eventos', m.tipo, m.titulo, null, null, null,
           'Central', 'central.alunos.' || m.col, ca.id::text
      from ca
      cross join lateral (values ('boas_vindas', 'Boas-vindas da Central', ca.boas_vindas_em, 'boas_vindas_em'),
                                 ('raio_x', 'Raio-X respondido', ca.raiox_at, 'raiox_at'),
                                 ('debriefing', 'Debriefing liberado', ca.debriefing_liberado_em, 'debriefing_liberado_em')) m(tipo, titulo, em, col)
     where m.em is not null
    union all
    select (m.em at time zone 'America/Sao_Paulo')::date, m.em, 'eventos', m.tipo,
           'Trilha ' || coalesce(p.trilha_slug::text, '?') || coalesce(' nº ' || p.numero::text, ''),
           m.det, null, m.sit, 'Central', 'central.participacoes', p.id::text
      from ca
      join central.participacoes p on p.aluno_id = ca.id
      cross join lateral (values
        ('trilha_iniciada', p.iniciada_em, p.faixa::text, null::text),
        ('trilha_encerrada', p.encerrada_em,
         nullif(concat_ws(' · ',
           case when p.itens_total is not null then coalesce(p.itens_feitos::text, '0') || '/' || p.itens_total::text || ' itens' end,
           case when p.pct is not null then p.pct::text || '%' end,
           p.motivo::text), ''),
         p.status::text)) m(tipo, em, det, sit)
     where m.em is not null
    -- eventos: plantão (presença; inscrição não cancelada sem presença)
    union all
    select (coalesce(i.presenca_em, i.inscrito_em) at time zone 'America/Sao_Paulo')::date,
           coalesce(i.presenca_em, i.inscrito_em), 'eventos',
           case when i.presenca_em is not null then 'plantao_presenca' else 'plantao_inscricao' end,
           'Plantão' || coalesce(' ' || i.semana::text, ''),
           case when i.nps_nota is not null then 'NPS ' || i.nps_nota::text end, null,
           case when i.presenca_em is not null then 'presente' else 'sem presença registrada' end,
           'GPS Plantão', 'gps.plantao_inscricoes', i.id::text
      from gps.plantao_alunos pa
      join gps.plantao_inscricoes i on i.aluno_plantao_id = pa.id
     where lower(trim(both from pa.email)) = any (v_emails) and i.cancelado_em is null
    -- grupos de WhatsApp
    union all
    select (g.ocorreu_em at time zone 'America/Sao_Paulo')::date, g.ocorreu_em, 'grupos',
           case g.tipo when 'entrada' then 'entrou_grupo' else 'saiu_grupo' end,
           case g.tipo when 'entrada' then 'Entrou no grupo ' else 'Saiu do grupo ' end || coalesce(g.group_name::text, '?'),
           null, null, null, 'WhatsApp (' || coalesce(g.fonte::text, '?') || ')',
           'fone_key único entre alunos ativos', null
      from controle.grupo_evento_unificado g
     where v_key_ok and g.fone_key = v_key and g.tipo in ('entrada','saida')
    -- atendimento: card HM (cancelamento efetivado já saiu como 'saida' em vinculo)
    union all
    select (m.em at time zone 'America/Sao_Paulo')::date, m.em, 'atendimento', m.tipo, m.titulo, m.det, null, m.sit,
           'Card HM', 'cs.contatos_hm.' || m.col, c.id::text
      from cs.contatos_hm c
      cross join lateral (values
        ('entrada_card', 'Entrada no card ' || coalesce(c.produto::text, 'HM'), coalesce(c.entrada_em, c.criado_em),
           nullif(concat_ws(' · ', case when v_fin then c.plano::text end, 'turma ' || c.turma::text), ''), null::text, 'entrada_em'),
        ('reuniao', 'Reunião', c.reuniao_em, null, null, 'reuniao_em'),
        ('entrevista', 'Entrevista', c.entrevista_em, null, c.entrevista_resultado::text, 'entrevista_em'),
        ('pagamento', 'Pagamento registrado no card', c.pagamento_em, null, null, 'pagamento_em'),
        ('quitado', 'Quitado', c.quitado_em, null, null, 'quitado_em'),
        ('pedido_cancelamento', 'Pedido de cancelamento', c.cancelamento_em, c.cancelamento_motivo_tipo::text, null, 'cancelamento_em'),
        ('cancelado_hotmart', 'Cancelado na Hotmart', c.hotmart_cancelado_em, null, null, 'hotmart_cancelado_em'),
        ('acessos_revogados', 'Acessos revogados', c.acessos_revogados_em, null, null, 'acessos_revogados_em')
      ) m(tipo, titulo, em, det, sit, col)
     where c.aluno_id = v_al.id and m.em is not null
       and (v_fin or m.tipo not in ('pagamento','quitado'))
  )
  select u.dia::date, u.momento::timestamptz, u.dimensao::text, u.tipo::text, u.titulo::text, u.detalhe::text,
         u.valor::numeric, u.situacao::text, u.fonte::text, u.regra::text, u.ref::text
    from u
   order by coalesce(u.momento, u.dia::timestamp at time zone 'America/Sao_Paulo') nulls last, u.dimensao, u.tipo;
end
$$;
comment on function public.fn_aluno_trajetoria(uuid) is
  'Trajetória do aluno no THB (fase 1, 20261002a). Só equipe (gp_eh_equipe); valor só com gp_pode_ver_financeiro. Sem e-mail/telefone.';
revoke all on function public.fn_aluno_trajetoria(uuid) from public, anon;
grant execute on function public.fn_aluno_trajetoria(uuid) to authenticated;


-- ─── 4. Conferência de grants (aborta se a função nasceu aberta) ────────────────────────────────────────────────────
do $confere$
begin
  if has_function_privilege('anon', 'fin.trajetoria_nucleo(text[])', 'execute')
     or has_function_privilege('authenticated', 'fin.trajetoria_nucleo(text[])', 'execute') then
    raise exception '20261002a: fin.trajetoria_nucleo executável por anon/authenticated';
  end if;
  if has_function_privilege('anon', 'public.fn_aluno_trajetoria(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_aluno_trajetoria(uuid)', 'execute') then
    raise exception '20261002a: grants de public.fn_aluno_trajetoria errados';
  end if;
  if has_function_privilege('anon', 'public.fn_fin_trajetoria(text)', 'execute') then
    raise exception '20261002a: public.fn_fin_trajetoria executável por anon';
  end if;
end $confere$;


-- ═══ REVERSÃO (numa transação; restaura o corpo vivo de 30/09, md5 0c08041295469d56a0276e5fb33c3a8a) ═══════════════
-- drop function if exists public.fn_aluno_trajetoria(uuid);
-- drop index if exists public.ix_thb_alunos_fone_key_ativo;
-- (1) recriar public.fn_fin_trajetoria com o corpo antigo ABAIXO (tirar o "-- " do início de cada linha);
-- (2) só depois: drop function if exists fin.trajetoria_nucleo(text[]);
--
-- create or replace function public.fn_fin_trajetoria(p_email text)
-- returns table (dia date, familia text, produto text, oferta text, situacao text, valor numeric, parcelas int,
--                papel text, evento_id bigint, evento text, evento_categoria text, turma text, regra_evento text)
-- language plpgsql stable security definer set search_path = ''
-- as $$
-- #variable_conflict use_column
-- begin
--   if not coalesce(public.gp_pode_ver_financeiro(), false) then
--     raise exception 'Sem permissão.' using errcode = '42501';
--   end if;
--   return query
--   with alvo as (
--     select lower(trim(p_email)) email
--   ), emails as (
--     select distinct coalesce(substr(i2.no, 3), a.email) email
--       from alvo a
--       left join fin.identidade i on i.no = 'e:' || a.email
--       left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
--   ), evs as (
--     select e.*, coalesce(lag(e.venda_ate) over (partition by e.categoria order by e.inicio) + 1, e.inicio - 60) ing_de
--       from fin.eventos e
--   ), tx as (
--     select t.*, coalesce(t.dia_aprovado, t.dia_pedido) d, cat.categoria cat
--       from emails e
--       join fin.vw_transacoes t on t.email = e.email
--       left join public.hm_product_catalog cat on cat.offer_code = t.oferta_codigo
--      where t.grupo in ('pago','estornado','atrasado','em_aberto') and coalesce(t.recorrencia, 1) = 1
--   )
--   select x.d, x.familia, x.produto_nome, x.oferta_codigo,
--          case x.grupo when 'pago' then 'pago' when 'estornado' then 'estornado' when 'atrasado' then 'em atraso' else 'em aberto' end,
--          round(x.valor_oferta * case when x.oferta_modo like 'HOTMART_INSTALLMENTS%' then coalesce(x.parcelas, 1) else 1 end, 2),
--          x.parcelas,
--          case when ev.regra = 'ingresso do evento' then 'ingresso'
--               when x.produto_id = '5064314' and x.d >= date '2026-06-25' and coalesce(x.cat, '') not in ('renovacao','reserva') then 'programa'
--               else 'compra' end,
--          ev.id, ev.nome, ev.categoria,
--          tor.turma,
--          ev.regra
--     from tx x
--     left join lateral (
--       select e.id, e.nome, e.categoria,
--              case when exists (select 1 from fin.evento_produtos ep
--                                 where ep.categoria = e.categoria and ep.produto_id = x.produto_id and ep.papel = 'ingresso')
--                   then 'ingresso do evento' else 'oferta do evento' end regra
--         from fin.evento_ofertas eo
--         join fin.eventos e on e.id = eo.evento_id
--        where eo.oferta_codigo = x.oferta_codigo
--        limit 1
--     ) evo on true
--     left join lateral (
--       select e.id, e.nome, e.categoria, case when ep.papel = 'ingresso' then 'ingresso do evento' else 'oferta do evento' end regra
--         from evs e
--         join fin.evento_produtos ep on ep.categoria = e.categoria and ep.produto_id = x.produto_id
--        where evo.id is null
--          and ((ep.papel = 'ingresso' and x.d between e.ing_de and e.venda_ate)
--            or (ep.papel = 'oferta' and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate))
--        order by (ep.papel = 'oferta') desc, e.venda_ate, e.inicio limit 1
--     ) ev0 on true
--     left join lateral (
--       select e.id, e.nome, e.categoria, 'dia do evento'::text regra
--         from fin.eventos e
--        where evo.id is null and ev0.id is null and e.setor = 'educacao'
--          and x.d between coalesce(e.carrinho_inicio, e.inicio) and e.venda_ate
--          and (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)) <= 10
--          and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
--        order by (e.venda_ate - coalesce(e.carrinho_inicio, e.inicio)), e.inicio desc limit 1
--     ) ev1 on true
--     left join lateral (
--       select e.id, e.nome, e.categoria, 'depois do evento'::text regra
--         from fin.eventos e
--        where evo.id is null and ev0.id is null and ev1.id is null and e.setor = 'educacao'
--          and e.venda_ate < x.d and e.venda_ate >= x.d - 30
--          and not (x.familia = 'HM' and e.categoria in ('aurum_plus','diamantes'))
--        order by e.venda_ate desc limit 1
--     ) ev2 on true
--     left join lateral (
--       select null::bigint id, a.nome, 'aurum_turma'::text categoria, 'lançamento da turma Aurum'::text regra
--         from fin.acoes a
--        where evo.id is null and ev0.id is null and ev1.id is null and ev2.id is null and x.familia = 'AURUM'
--          and a.produto = 'AURUM' and a.prioridade = 50
--          and (x.d::timestamp at time zone 'America/Sao_Paulo') >= a.inicio and (x.d::timestamp at time zone 'America/Sao_Paulo') < a.fim
--        limit 1
--     ) ev3 on true
--     cross join lateral (select coalesce(evo.id, ev0.id, ev1.id, ev2.id) id,
--                                coalesce(evo.nome, ev0.nome, ev1.nome, ev2.nome, ev3.nome) nome,
--                                coalesce(evo.categoria, ev0.categoria, ev1.categoria, ev2.categoria, ev3.categoria) categoria,
--                                coalesce(evo.regra, ev0.regra, ev1.regra, ev2.regra, ev3.regra) regra) ev
--     left join lateral (select a.turma from fin.acoes a
--                         where a.produto = 'HM' and a.turma is not null and a.inicio is not null and a.fim is not null
--                           and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
--                                 where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) >= a.inicio
--                           and (select min(coalesce(y.aprovado_em, y.pedido_em)) from tx y
--                                 where y.familia in ('HM','AURUM') and y.grupo in ('pago','estornado')) < a.fim
--                         order by a.prioridade desc, a.inicio desc limit 1) tor on true
--    order by x.d, x.pedido_em;
-- end
-- $$;
-- revoke all on function public.fn_fin_trajetoria(text) from public, anon;
-- grant execute on function public.fn_fin_trajetoria(text) to authenticated;


-- ═══ ENSAIO (sessão principal; tudo numa transação desfeita) ════════════════════════════════════════════════════════
-- begin;
-- set local statement_timeout = '20s';
-- -- usuário da equipe com financeiro (gp_eh_equipe e gp_pode_ver_financeiro leem auth.uid() = claims.sub)
-- select set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub',
--          (select p.id from public.perfis p where p.status = 'ativo' and p.email ilike '%@advmais.com'
--             and p.cargo in ('dev','admin') order by p.id limit 1))::text, true);
-- select public.gp_eh_equipe() equipe, public.gp_pode_ver_financeiro() fin;          -- esperado: t | t
--
-- -- A. IGUALDADE da fn_fin_trajetoria (5 e-mails: 3 com mais transações, 1 com estorno, 1 sócio)
-- create temp table _z_emails on commit drop as
--   select * from ((select t.email from fin.vw_transacoes t where t.email is not null group by 1 order by count(*) desc, 1 limit 3)
--   union (select min(t.email) from fin.vw_transacoes t where t.grupo = 'estornado')
--   union (select lower(trim(both from a.email)) from public.thb_alunos a
--           where a.socio_de_aluno_id is not null and a.email is not null order by 1 limit 1)) x(email);
-- create temp table _z_antes on commit drop as
--   select e.email q, t.* from _z_emails e cross join lateral public.fn_fin_trajetoria(e.email) with ordinality t;
-- select md5(prosrc) from pg_proc where oid = 'public.fn_fin_trajetoria(text)'::regprocedure;   -- 0c08041295469d56a0276e5fb33c3a8a
--
-- <<< colar aqui o arquivo inteiro, do "set local lock_timeout" até o bloco $confere$ >>>
--
-- create temp table _z_depois on commit drop as
--   select e.email q, t.* from _z_emails e cross join lateral public.fn_fin_trajetoria(e.email) with ordinality t;
-- select (select count(*) from _z_antes) antes, (select count(*) from _z_depois) depois,
--        (select count(*) from (select q, dia, familia, produto, oferta, situacao, valor, parcelas, papel, evento_id, evento, evento_categoria, turma, regra_evento from _z_antes
--                               except all
--                               select q, dia, familia, produto, oferta, situacao, valor, parcelas, papel, evento_id, evento, evento_categoria, turma, regra_evento from _z_depois) x) so_antes,
--        (select count(*) from (select q, dia, familia, produto, oferta, situacao, valor, parcelas, papel, evento_id, evento, evento_categoria, turma, regra_evento from _z_depois
--                               except all
--                               select q, dia, familia, produto, oferta, situacao, valor, parcelas, papel, evento_id, evento, evento_categoria, turma, regra_evento from _z_antes) x) so_depois,
--        (select count(*) from _z_antes a join _z_depois d using (q, ordinality)
--          where (a.dia, a.oferta, a.situacao) is distinct from (d.dia, d.oferta, d.situacao)) ordem_diferente;
-- -- esperado: antes = depois, so_antes = 0, so_depois = 0; ordem_diferente = 0 (≠ 0 só pode ser empate em (dia, pedido_em))
--
-- -- B. Alunos de ensaio: p50 e o de 317 eventos (gps.aluno_eventos; troque se o "317" for outra contagem)
-- select e.aluno_id, count(*) from gps.aluno_eventos e group by 1 having count(*) = 317;
-- with c as (select a.id, (select count(*) from gps.aluno_eventos e where e.aluno_id = a.id) n
--              from public.thb_alunos a where a.cancelado_em is null)
-- select id, n from c order by n, id offset (select count(*) / 2 from c) limit 1;
--
-- -- C. Peças (Index Scan esperado: hotmart_transacoes_email_idx ou _contrato_rec_idx; nada de Seq Scan em hotmart_transacoes)
-- explain (analyze, buffers) select * from fin.trajetoria_nucleo(array['<email do aluno 317>']);
-- explain (analyze, buffers) select t.* from fin.vw_transacoes t
--   where t.email = any (array['<email do aluno 317>']) and t.recorrencia is not null;
-- explain (analyze, buffers) select * from cs.contatos_hm c where c.aluno_id = '<uuid 317>';
-- explain (analyze, buffers) select * from central.alunos a where lower(trim(both from a.email)) = any (array['<email 317>']);
-- explain (analyze, buffers) select * from gps.plantao_alunos a where lower(trim(both from a.email)) = any (array['<email 317>']);
-- explain (analyze, buffers) select 1 from public.thb_alunos o where o.cancelado_em is null
--   and controle.fone_key(coalesce(o.telefone_e164, o.telefone)) = '1112345678';
--
-- -- D. Função inteira (2x cada; a 1ª paga o cache frio do plpgsql)
-- explain (analyze, buffers) select * from public.fn_aluno_trajetoria('<uuid p50>');
-- explain (analyze, buffers) select * from public.fn_aluno_trajetoria('<uuid p50>');
-- explain (analyze, buffers) select * from public.fn_aluno_trajetoria('<uuid 317>');
-- explain (analyze, buffers) select * from public.fn_aluno_trajetoria('<uuid 317>');
-- select dimensao, tipo, count(*) from public.fn_aluno_trajetoria('<uuid 317>') group by 1, 2 order by 1, 2;
--
-- -- E. MEDIÇÃO saída/volta nos ativos (8 lotes; cada insert é 1 comando sob o timeout de 20 s)
-- create temp table _z_lote on commit drop as
--   select a.id, ntile(8) over (order by a.id) nb from public.thb_alunos a where a.cancelado_em is null;
-- create temp table _z_med (aluno_id uuid, tipo text, regra text) on commit drop;
-- insert into _z_med select l.id, t.tipo, t.regra from _z_lote l cross join lateral public.fn_aluno_trajetoria(l.id) t
--   where l.nb = 1 and t.dimensao = 'vinculo' and t.tipo in ('saida','volta');      -- repetir com nb = 2 … 8
-- select (select count(*) from _z_lote) ativos,
--        count(distinct aluno_id) filter (where tipo = 'saida') com_saida,
--        count(distinct aluno_id) filter (where tipo = 'volta') com_volta from _z_med;
-- select tipo, split_part(regra, ' depois de: ', 1) regra, count(distinct aluno_id) alunos, count(*) linhas
--   from _z_med group by 1, 2 order by 1, 3 desc;
--
-- -- F. Grants de verdade (cada um num savepoint; esperado: erro 42501 nos dois primeiros, linhas no terceiro)
-- savepoint s1; set local role anon;          select count(*) from public.fn_aluno_trajetoria('<uuid p50>'); rollback to s1;
-- savepoint s2; set local role authenticated; select count(*) from fin.trajetoria_nucleo(array['x@x']);    rollback to s2;
-- savepoint s3; set local role authenticated; select count(*) from public.fn_aluno_trajetoria('<uuid p50>'); rollback to s3;
-- rollback;
