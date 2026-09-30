-- 20261002b — Trajetória do aluno (fase 3, back-end): histórico de estado de thb_alunos
--
-- MARCO: fonte única = public.fn_thb_alunos_historico_marco() (seção 0.0; IMMUTABLE, SQL, sem SET: o planner
--   inlina e dobra em constante). Instante em que este arquivo foi escrito, relógio da máquina em UTC.
--   Linhas de thb_alunos_audit_log com campo turma_id/plano valem na trajetória SÓ antes do marco;
--   depois dele, a fonte dessas mudanças é public.thb_alunos_historico (trigger abaixo). A guarda 0.4 aborta
--   se existir audit turma_id/plano >= marco (buraco entre marco e aplicação) ou se now() < marco.
--
-- POR QUÊ: a F1 só enxerga troca de turma/plano quando o escritor do audit_log grava (18 turma_id + 1 plano em 90 dias).
--   Mudanças feitas pela tela (updateAluno), pelo provisionamento HM, pela conciliação de turma e pelo cron diário
--   de situação de acesso (06h10) não deixam rastro. A F3 grava o rastro no próprio UPDATE.
--
-- O QUE FAZ
--   1. public.thb_alunos_historico: 1 linha por campo mudado (plano, turma_id, turma_aurum_id, status_acesso,
--      situacao_acesso).
--      aluno_id SEM FK (import antigo apaga aluno; a trilha fica). RLS ligada sem policy; revoke all de
--      public/anon/authenticated; service_role perde insert/update/delete/truncate (trilha só de acréscimo pela API).
--   2. public.fn_thb_alunos_historico(): trigger AFTER UPDATE (sem lista de colunas) FOR EACH ROW WHEN (alguma das 5 mudou).
--      SECURITY DEFINER, search_path ''. Um único insert…select from (values …) where anterior is distinct from novo.
--      Sem exception: se o insert falhar, o UPDATE do aluno falha junto (trilha não fica para trás em silêncio).
--      alterado_por = auth.uid() (nulo em cron/service_role); origem = coalesce(auth.role(), session_user).
--   3. public.fn_aluno_trajetoria(uuid): mesma assinatura, guarda (gp_eh_equipe), grants e saída da 20261002a;
--      passa a ler o histórico (turma: troca_turma / troca_turma_aurum; vinculo: troca_plano / status_acesso /
--      situacao_acesso); audit turma_id/plano só < marco; data da turma atual/Aurum = greatest(último audit < marco,
--      último histórico). O cron muda situacao_acesso e status_acesso no MESMO UPDATE: são 2 linhas no histórico
--      (trilha fiel) e 1 linha na trajetória (situação no título, status no detalhe) — colapso por aluno + alterado_em.
--      Autor no detalhe (plano, turma e acesso): "por <nome>" (usuário), "sem usuário (integração)" (origem service_role:
--      edge function/integração), "sem usuário (rotina ou banco)" (mudança sem JWT: cron ou SQL direto).
--
-- INTERAÇÃO COM OS TRIGGERS VIVOS DE thb_alunos
--   a_trg_thb_alunos_skip_noop (BEFORE): se devolver NULL no UPDATE sem mudança, a linha não é gravada e o AFTER
--     não dispara. O WHEN do AFTER cobre o caso que o skip não pega (updateAluno sempre muda atualizado_em).
--   O AFTER não tem lista de colunas: o WHEN compara old com o new FINAL (depois dos BEFORE), então um valor trocado
--     por trigger BEFORE também é gravado, com o autor do UPDATE que o provocou. A guarda 0.3 fica como defesa: aborta
--     se algum trigger BEFORE UPDATE de thb_alunos escrever num campo rastreado (new.x := / new.x = / into new.x),
--     trocar a linha inteira (new := / into new) ou devolver outra coisa que não new/old/null — para alguém ler o
--     corpo antes de aplicar (troca derivada atribuída ao usuário; ou skip_noop devolvendo NULL antes dela).
--
-- AS 5 PERGUNTAS
--   escala: 1 insert de 1 a 5 linhas por aluno mudado; o cron 06h10 é o maior escritor (delta medido no ensaio, passo 7).
--   índice: ix_thb_alunos_historico_aluno (aluno_id, alterado_em desc) — a leitura é por aluno (e por aluno+instante
--     no colapso do acesso).
--   frequência: leitura 1x por abertura da aba Trajetória; escrita só em mudança real dos 5 campos.
--   repetição: nenhuma query por linha; o trigger é 1 insert por linha de thb_alunos alterada.
--   reversão: bloco REVERSÃO no fim (desliga o trigger, devolve a função da F1; a tabela fica, arquivada).
--
-- ENSAIO: infra/supabase/migrations/20261002b_ensaio.sql (begin … rollback).

set local lock_timeout = '3s';

-- ─── 0.0 Marco (FONTE ÚNICA; todo uso do marco chama esta função) ─────────────────────────────────────────────────────
-- IMMUTABLE + language sql + sem SET/SECURITY DEFINER = inlinável: vira constante no plano (não mata índice).
-- Criada antes das guardas porque a 0.4 a usa; se uma guarda abortar, a transação da migration desfaz a criação.
create function public.fn_thb_alunos_historico_marco()
returns timestamptz
language sql immutable parallel safe
as $$ select timestamptz '2026-09-30 18:06:36+00' $$;
comment on function public.fn_thb_alunos_historico_marco() is
  'Marco de corte da 20261002b: audit_log turma_id/plano vale na trajetória só antes dele; depois, thb_alunos_historico.';
revoke all on function public.fn_thb_alunos_historico_marco() from public, anon, authenticated;

-- ─── 0. Guardas (falham ANTES de gravar) ───────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_src   text;
  v_falta text;
  v_n     bigint;
  v_trg   text;
begin
  -- 0.1 corpo vivo de fn_aluno_trajetoria = o da 20261002a (md5 do prosrc do arquivo) ou já é esta versão
  select p.prosrc into v_src from pg_proc p where p.oid = 'public.fn_aluno_trajetoria(uuid)'::regprocedure;
  if md5(v_src) <> '47cd1c325a59e26f4bc7c302b4b8bd42' and position('thb_alunos_historico' in v_src) = 0 then
    raise exception '20261002b: corpo vivo de public.fn_aluno_trajetoria mudou (md5 %, esperado 47cd1c325a59e26f4bc7c302b4b8bd42)', md5(v_src);
  end if;

  -- 0.2 colunas usadas existem; funções de auth existem
  select string_agg(format('%s.%s.%s', x.s, x.t, x.c), ', ')
    into v_falta
    from (values ('public','thb_alunos','plano'), ('public','thb_alunos','turma_id'),
                 ('public','thb_alunos','turma_aurum_id'), ('public','thb_alunos','status_acesso'),
                 ('public','thb_alunos','situacao_acesso'),
                 ('public','perfis','id'), ('public','perfis','nome'),
                 ('public','thb_turmas','id'), ('public','thb_turmas','codigo')) x(s, t, c)
    left join information_schema.columns c
      on c.table_schema = x.s and c.table_name = x.t and c.column_name = x.c
   where c.column_name is null;
  if v_falta is not null then
    raise exception '20261002b: coluna ausente: %', v_falta;
  end if;
  if to_regprocedure('auth.uid()') is null or to_regprocedure('auth.role()') is null then
    raise exception '20261002b: auth.uid() ou auth.role() ausente';
  end if;
  if to_regclass('public.thb_alunos_historico') is not null then
    raise exception '20261002b: public.thb_alunos_historico já existe';
  end if;

  -- 0.3 nenhum trigger BEFORE UPDATE de thb_alunos troca um dos 5 campos (a troca seria gravada com o autor do UPDATE
  --     que a provocou, ou sumiria se o skip_noop devolver NULL antes dela: ler o corpo antes de aplicar).
  --   Case-insensitive (~*), espaço/quebra livres, identificador com ou sem aspas. Padrões:
  --   a) new.col :=            b) new.col = … no início de comando (após ; then else loop begin, comentário -- no meio)
  --   c) select|execute|fetch … into [strict] x, new.col       d) linha inteira: new := / new = / into new
  --   e) return de outra coisa que não new/old/null (ex.: r := new; r.plano := …; return r)
  --   Falso positivo aborta (seguro): ler o corpo do trigger apontado e decidir.
  select string_agg(distinct t.tgname, ', ') into v_trg
    from pg_trigger t
    join pg_proc p on p.oid = t.tgfoid
   where t.tgrelid = 'public.thb_alunos'::regclass and not t.tgisinternal
     and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16
     and p.prosrc ~* any (array[
       'new\s*\.\s*"?(plano|turma_id|turma_aurum_id|status_acesso|situacao_acesso)\M"?\s*:=',
       '(;|\m(then|else|loop|begin))(\s|--[^\n]*)*new\s*\.\s*"?(plano|turma_id|turma_aurum_id|status_acesso|situacao_acesso)\M"?\s*=',
       '\minto\s+(strict\s+)?([a-z0-9_."]+\s*,\s*)*new\s*\.\s*"?(plano|turma_id|turma_aurum_id|status_acesso|situacao_acesso)\M',
       '(;|\m(then|else|loop|begin))(\s|--[^\n]*)*new\s*:?=',
       '\minto\s+(strict\s+)?([a-z0-9_."]+\s*,\s*)*new\M(?!\s*\.)',
       '\mreturn\s+(?!(new|old|null)\M)\S'
     ]);
  if v_trg is not null then
    raise exception '20261002b: trigger BEFORE UPDATE pode escrever campo rastreado (%): ler o corpo antes de aplicar (a troca seria atribuída ao autor do UPDATE)', v_trg;
  end if;

  -- 0.4 marco: já passou, e nenhum audit turma_id/plano caiu entre o marco e a aplicação
  if now() < public.fn_thb_alunos_historico_marco() then
    raise exception '20261002b: marco no futuro (now() = %)', now();
  end if;
  select count(*) into v_n from public.thb_alunos_audit_log l
   where l.campo in ('turma_id','plano') and l.criado_em >= public.fn_thb_alunos_historico_marco();
  if v_n > 0 then
    raise exception '20261002b: % linha(s) de audit turma_id/plano depois do marco: atualize o marco para agora', v_n;
  end if;
end $guarda$;


-- ─── 1. Tabela do histórico ────────────────────────────────────────────────────────────────────────────────────────
create table public.thb_alunos_historico (
  id             bigint generated always as identity primary key,
  aluno_id       uuid not null,
  campo          text not null check (campo in ('plano','turma_id','turma_aurum_id','status_acesso','situacao_acesso')),
  valor_anterior text,
  valor_novo     text,
  alterado_por   uuid,
  origem         text,
  alterado_em    timestamptz not null default now()
);
comment on table public.thb_alunos_historico is
  'Histórico de plano/turma_id/turma_aurum_id/status_acesso/situacao_acesso de thb_alunos, gravado pelo trigger trg_thb_alunos_historico. '
  'aluno_id sem FK de propósito (import apaga aluno). Leitura só via fn_aluno_trajetoria. 20261002b.';

create index ix_thb_alunos_historico_aluno on public.thb_alunos_historico (aluno_id, alterado_em desc);

alter table public.thb_alunos_historico enable row level security;
revoke all on table public.thb_alunos_historico from public, anon, authenticated;
revoke insert, update, delete, truncate on table public.thb_alunos_historico from service_role;
do $seq$
declare v_seq text := pg_get_serial_sequence('public.thb_alunos_historico', 'id');
begin
  execute format('revoke all on sequence %s from public, anon, authenticated', v_seq);
end $seq$;


-- ─── 2. Trigger ────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_thb_alunos_historico()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.thb_alunos_historico (aluno_id, campo, valor_anterior, valor_novo, alterado_por, origem)
  select new.id, v.campo, v.anterior, v.novo, auth.uid(), coalesce(nullif(auth.role(), ''), session_user::text)
    from (values ('plano',           old.plano::text,           new.plano::text),
                 ('turma_id',        old.turma_id::text,        new.turma_id::text),
                 ('turma_aurum_id',  old.turma_aurum_id::text,  new.turma_aurum_id::text),
                 ('status_acesso',   old.status_acesso::text,   new.status_acesso::text),
                 ('situacao_acesso', old.situacao_acesso::text, new.situacao_acesso::text)) v(campo, anterior, novo)
   where v.anterior is distinct from v.novo;
  return null;
end
$$;
comment on function public.fn_thb_alunos_historico() is
  'Trigger AFTER UPDATE de thb_alunos: grava thb_alunos_historico. 20261002b.';
revoke all on function public.fn_thb_alunos_historico() from public, anon, authenticated;

create trigger trg_thb_alunos_historico
  after update on public.thb_alunos
  for each row
  when (old.plano is distinct from new.plano
     or old.turma_id is distinct from new.turma_id
     or old.turma_aurum_id is distinct from new.turma_aurum_id
     or old.status_acesso is distinct from new.status_acesso
     or old.situacao_acesso is distinct from new.situacao_acesso)
  execute function public.fn_thb_alunos_historico();


-- ─── 3. fn_aluno_trajetoria (20261002a + histórico) ──────────────────────────────────────────────────────────────────
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
    select coalesce((ult.em at time zone 'America/Sao_Paulo')::date, v_al.data_entrada_thb,
                    (v_al.importado_em at time zone 'America/Sao_Paulo')::date),
           ult.em, 'turma', x.tipo, x.rotulo || ' ' || coalesce(tt.codigo::text, '?'), tt.tipo::text, null, null,
           'Base de alunos', 'thb_alunos.' || x.campo, tt.id::text
      from (values ('turma_atual', 'Turma atual', 'turma_id', v_al.turma_id::text),
                   ('turma_aurum', 'Turma Aurum', 'turma_aurum_id', v_al.turma_aurum_id::text)) x(tipo, rotulo, campo, tid)
      join public.thb_turmas tt on tt.id::text = x.tid
      -- 20261002b: última mudança = greatest(último audit antes do marco, último histórico); greatest ignora nulo
      cross join lateral (select greatest(
                            (select l.criado_em from public.thb_alunos_audit_log l
                              where l.aluno_id = v_al.id and l.campo = x.campo
                                and l.criado_em < public.fn_thb_alunos_historico_marco()
                              order by l.criado_em desc limit 1),
                            (select h.alterado_em from public.thb_alunos_historico h
                              where h.aluno_id = v_al.id and h.campo = x.campo
                              order by h.alterado_em desc limit 1)) em) ult
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
       and (l.campo not in ('turma_id','plano') or l.criado_em < public.fn_thb_alunos_historico_marco())   -- 20261002b: depois do marco vem do histórico
    -- histórico de estado (20261002b): turma, turma Aurum, plano — 1 linha por mudança; autor no detalhe
    union all
    select (h.alterado_em at time zone 'America/Sao_Paulo')::date, h.alterado_em,
           case when h.campo in ('turma_id','turma_aurum_id') then 'turma' else 'vinculo' end,
           case h.campo when 'turma_id' then 'troca_turma' when 'turma_aurum_id' then 'troca_turma_aurum' else 'troca_plano' end,
           case h.campo when 'turma_id' then 'Troca de turma' when 'turma_aurum_id' then 'Troca de turma Aurum'
                        else 'Troca de plano' end,
           concat_ws(' · ',
             case when h.campo in ('turma_id','turma_aurum_id')
                    then coalesce(ta.codigo::text, h.valor_anterior, '—') || ' → ' || coalesce(tn.codigo::text, h.valor_novo, '—')
                  else coalesce(h.valor_anterior, '—') || ' → ' || coalesce(h.valor_novo, '—') end,
             case when h.alterado_por is not null then 'por ' || coalesce(pf.nome::text, '?')
                  when h.origem = 'service_role' then 'sem usuário (integração)'
                  when h.origem not in ('authenticated','service_role','anon') then 'sem usuário (rotina ou banco)' end),
           null, null,
           'Base de alunos · ' || case when h.alterado_por is null then 'automático' else coalesce(pf.nome::text, '?') end,
           'thb_alunos_historico.' || h.campo, h.id::text
      from public.thb_alunos_historico h
      left join public.thb_turmas ta on h.campo in ('turma_id','turma_aurum_id') and ta.id::text = h.valor_anterior
      left join public.thb_turmas tn on h.campo in ('turma_id','turma_aurum_id') and tn.id::text = h.valor_novo
      left join public.perfis pf on pf.id = h.alterado_por
     where h.aluno_id = v_al.id and h.campo in ('plano','turma_id','turma_aurum_id')
    -- acesso (20261002b): situacao_acesso + status_acesso do MESMO UPDATE (mesmo aluno, mesmo alterado_em = now() da
    --   transação) viram 1 linha: situação no título, status no detalhe. status sozinho continua 1 linha própria.
    union all
    select (h.alterado_em at time zone 'America/Sao_Paulo')::date, h.alterado_em, 'vinculo', h.campo,
           case when h.campo = 'situacao_acesso'
                then 'Situação de acesso: '
                     || case h.valor_anterior when 'em_dia' then 'Em dia' when 'a_vencer' then 'A vencer' when 'vencido' then 'Vencido'
                                              when 'acompanha_titular' then 'Acompanha titular' else coalesce(h.valor_anterior, '—') end
                     || ' → '
                     || case h.valor_novo when 'em_dia' then 'Em dia' when 'a_vencer' then 'A vencer' when 'vencido' then 'Vencido'
                                          when 'acompanha_titular' then 'Acompanha titular' else coalesce(h.valor_novo, '—') end
                else 'Acesso: ' || coalesce(h.valor_anterior, '—') || ' → ' || coalesce(h.valor_novo, '—') end,
           nullif(concat_ws(' · ',
             case when st.id is not null then 'status ' || coalesce(st.valor_anterior, '—') || ' → ' || coalesce(st.valor_novo, '—') end,
             case when h.alterado_por is not null then 'por ' || coalesce(pf.nome::text, '?')
                  when h.origem = 'service_role' then 'sem usuário (integração)'
                  when h.origem not in ('authenticated','service_role','anon') then 'sem usuário (rotina ou banco)' end), ''),
           null, null,
           'Base de alunos · ' || case when h.alterado_por is null then 'automático' else coalesce(pf.nome::text, '?') end,
           'thb_alunos_historico.' || h.campo || case when st.id is not null then '+status_acesso' else '' end, h.id::text
      from public.thb_alunos_historico h
      left join lateral (select s.id, s.valor_anterior, s.valor_novo
                           from public.thb_alunos_historico s
                          where h.campo = 'situacao_acesso' and s.aluno_id = h.aluno_id
                            and s.alterado_em = h.alterado_em and s.campo = 'status_acesso'
                          order by s.id limit 1) st on true
      left join public.perfis pf on pf.id = h.alterado_por
     where h.aluno_id = v_al.id and h.campo in ('situacao_acesso','status_acesso')
       and not (h.campo = 'status_acesso'
                and exists (select 1 from public.thb_alunos_historico s2
                             where s2.aluno_id = h.aluno_id and s2.alterado_em = h.alterado_em
                               and s2.campo = 'situacao_acesso'))
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
  'Trajetória do aluno no THB (fase 1 20261002a + histórico de estado 20261002b). Só equipe (gp_eh_equipe); valor só com gp_pode_ver_financeiro. Sem e-mail/telefone.';
revoke all on function public.fn_aluno_trajetoria(uuid) from public, anon;
grant execute on function public.fn_aluno_trajetoria(uuid) to authenticated;


-- ─── 4. Conferência de grants (aborta se algo nasceu aberto) ────────────────────────────────────────────────────────
do $confere$
declare r text;
begin
  foreach r in array array['anon', 'authenticated'] loop
    if has_table_privilege(r, 'public.thb_alunos_historico', 'select, insert, update, delete, truncate, references, trigger') then
      raise exception '20261002b: % tem privilégio em public.thb_alunos_historico', r;
    end if;
    if has_function_privilege(r, 'public.fn_thb_alunos_historico()', 'execute') then
      raise exception '20261002b: % executa public.fn_thb_alunos_historico()', r;
    end if;
    if has_function_privilege(r, 'public.fn_thb_alunos_historico_marco()', 'execute') then
      raise exception '20261002b: % executa public.fn_thb_alunos_historico_marco()', r;
    end if;
  end loop;
  if has_table_privilege('service_role', 'public.thb_alunos_historico', 'insert, update, delete, truncate') then
    raise exception '20261002b: service_role grava em public.thb_alunos_historico';
  end if;
  if has_function_privilege('anon', 'public.fn_aluno_trajetoria(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_aluno_trajetoria(uuid)', 'execute') then
    raise exception '20261002b: grants de public.fn_aluno_trajetoria errados';
  end if;
  if not exists (select 1 from pg_class c where c.oid = 'public.thb_alunos_historico'::regclass and c.relrowsecurity) then
    raise exception '20261002b: RLS desligada em public.thb_alunos_historico';
  end if;
end $confere$;


-- ═══ REVERSÃO (numa transação; nada é apagado: a tabela fica como arquivo) ═══════════════════════════════════════════
-- begin;
-- set local lock_timeout = '3s';
-- drop trigger if exists trg_thb_alunos_historico on public.thb_alunos;      -- para de gravar
-- -- devolver a F1: rodar de novo a seção "3. fn_aluno_trajetoria" da 20261002a_aluno_trajetoria.sql
-- --   (create or replace … até o grant execute), sem o resto daquele arquivo.
-- -- a tabela public.thb_alunos_historico, a função do trigger e fn_thb_alunos_historico_marco() FICAM
-- --   (trilha preservada; sem grant para anon/authenticated).
-- commit;
