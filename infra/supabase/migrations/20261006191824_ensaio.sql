-- 20261006191824: ENSAIO (não aplica nada: termina em ROLLBACK). Rodar inteiro, como postgres, numa chamada só:
--   python3 aplica_sql.py ensaio infra/supabase/migrations/20261006191824_ensaio.sql
--   (o script troca o "select … from _z_out; rollback;" do fim por um RAISE: a transação aborta e a saída volta na mensagem).
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006191824_crm_hotmart_sem_retroativo.sql,
-- da guarda até antes da REVERSÃO). Antes dele, a foto do ANTES; depois, as provas. Só contagens saem: nenhum nome,
-- e-mail ou telefone. Perfis reais por SELECT (gestor = admin ativo mais antigo; vendedores = crm.vendedor ativos;
-- vis = perfil ativo fora do comercial), só ids em temp. Compras simuladas com e-mail fictício @ensaio.invalid.
-- Esperado: nenhuma linha começando com "ERRADO".
--   0 fixtures e foto do antes        1 o que saiu e o que ficou       2 backup completo
--   3 nada tocado fora da seleção      4 contatos visíveis (gestor, vendedores, busca, ficha/jornada)
--   5 compra simulada: sem negócio aberto não cria ganho; com negócio aberto converte; recuperação após compra
--   6 explain da lista do vendedor e do gestor     7 permissões

begin;
set local lock_timeout = '3s';
set local statement_timeout = '280s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
create function pg_temp.ok(p_passo text, p_cond boolean, p_det text) returns void
language sql as $$
  insert into pg_temp._z_out (passo, linha)
  values (p_passo, case when coalesce(p_cond, false) then 'OK      ' else 'ERRADO  ' end || coalesce(p_det, ''));
$$;
create function pg_temp.info(p_passo text, p_det text) returns void
language sql as $$ insert into pg_temp._z_out (passo, linha) values (p_passo, 'INFO    ' || coalesce(p_det, '')); $$;

create temp table _v (k text primary key, u uuid) on commit drop;
insert into _v select 'gestor', p.id from public.perfis p where p.cargo = 'admin' and p.status = 'ativo' order by p.criado_em limit 1;
insert into _v select 'vend_' || v.sigla, v.perfil_id from crm.vendedor v join public.perfis p on p.id = v.perfil_id
 where v.ativo and p.status = 'ativo' order by v.sigla;
insert into _v select 'vis', p.id from public.perfis p
 where p.status = 'ativo' and p.cargo not in ('admin', 'dev') and not ('comercial' = any(coalesce(p.areas, '{}')))
 order by p.criado_em limit 1;

create function pg_temp.chamar(p_perfil uuid, p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  execute p_sql into v;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  return jsonb_build_object('erro', sqlerrm, 'estado', sqlstate);
end $$;

-- lista inteira como a tela pede (lotes de 500, p_busca nulo): {total, sem_dono}
create function pg_temp.lista(p_perfil uuid) returns jsonb language plpgsql as $$
declare v jsonb; t int := 0; s int := 0; o int := 0;
begin
  loop
    v := pg_temp.chamar(p_perfil, format('select public.crm_contatos(null, 500, %s)', o));
    if v ? 'erro' then return v; end if;
    t := t + jsonb_array_length(v -> 'itens');
    s := s + (select count(*) from jsonb_array_elements(v -> 'itens') e where e ->> 'donoId' is null);
    exit when not (v ->> 'temMais')::boolean or o > 20000;
    o := o + 500;
  end loop;
  return jsonb_build_object('total', t, 'sem_dono', s);
end $$;

-- ─── 0. Fixtures e foto do ANTES ───
select pg_temp.ok('0.fixtures', (select count(*) from _v where k = 'gestor') = 1 and (select count(*) from _v where k like 'vend_%') >= 2
                                and (select count(*) from _v where k = 'vis') = 1,
  format('gestor=%s vendedores=%s vis=%s', (select count(*) from _v where k = 'gestor'),
         (select count(*) from _v where k like 'vend_%'), (select count(*) from _v where k = 'vis')));

create temp table _neg_antes on commit drop as
select n.id, n.status, n.origem, n.dono_id, md5(row(n.*)::text) h from crm.negocio n;
create temp table _pc_antes on commit drop as select pc.pessoa_id, md5(row(pc.*)::text) h from crm.pessoa_comercial pc;
create temp table _contagem (k text, momento text, total int, sem_dono int) on commit drop;
insert into _contagem select v.k, 'antes', (l ->> 'total')::int, (l ->> 'sem_dono')::int
  from _v v cross join lateral pg_temp.lista(v.u) l where v.k <> 'vis';
select pg_temp.info('0.antes_negocios', format('total=%s abertos=%s ganhos=%s perdidos=%s | ganhos compra_aprovada sem dono=%s',
  count(*), count(*) filter (where status = 'aberto'), count(*) filter (where status = 'ganho'),
  count(*) filter (where status = 'perdido'),
  count(*) filter (where status = 'ganho' and origem = 'compra_aprovada' and dono_id is null))) from _neg_antes;
select pg_temp.info('0.antes_contatos', string_agg(format('%s: %s visíveis (%s sem dono)', k, total, sem_dono), ' | ' order by k))
  from _contagem where momento = 'antes';
-- um contato que hoje aparece para o vendedor só por ser sem dono e sem negócio nenhum (para provar a busca depois)
create temp table _escondido on commit drop as
select c.pessoa_id, d.d_email email
  from (select pc.pessoa_id, pc.criado_em from crm.pessoa_comercial pc
         where pc.dono_id is null
           and exists (select 1 from crm.negocio n where n.pessoa_id = pc.pessoa_id and n.origem = 'compra_aprovada' and n.dono_id is null)
           and not exists (select 1 from crm.negocio n where n.pessoa_id = pc.pessoa_id and (n.origem <> 'compra_aprovada' or n.dono_id is not null))
         order by pc.criado_em, pc.pessoa_id limit 20) c
 cross join lateral pessoas.dados(c.pessoa_id) d
 where d.d_email is not null
 order by c.criado_em, c.pessoa_id limit 1;

-- ═══ CORPO DA MIGRATION (copiado sem mudança) ═══
do $guarda$
declare v_n int;
begin
  if not exists (select 1 from crm.log l where l.id = 1920721 and l.entidade = 'config'
                    and l.em = '2026-10-06 12:39:07.927731+00'
                    and l.mudancas @> '[{"campo": "hotmart_ligado", "para": true}]'::jsonb) then
    raise exception '20261006191824: marco de crm.log (id 1920721, hotmart ligado em 06/10 12:39:07 UTC) não confere';
  end if;
  if md5(pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) <> '2ecc46733e92a5268621c7bb7baeb9bd' then
    raise exception '20261006191824: corpo vivo de crm.hotmart_processar mudou desde 06/10 (md5 diferente); reler e regerar';
  end if;
  if md5(pg_get_functiondef('public.crm_contatos(text,integer,integer)'::regprocedure)) <> '59751a23c6f4769264ba3a7c046ce7f4' then
    raise exception '20261006191824: corpo vivo de public.crm_contatos mudou desde 06/10 (md5 diferente); reler e regerar';
  end if;
  if exists (select 1 from pg_class c join pg_namespace s on s.oid = c.relnamespace
              where s.nspname = 'arquivo' and c.relname like 'crm\_%\_retro\_20261006') then
    raise exception '20261006191824: já existe tabela arquivo.crm_*_retro_20261006 (migration já rodou?)';
  end if;
end
$guarda$;

-- ─── 1. Seleção ───────────────────────────────────────────────────────────────────────────────────────────────────
create temp table _retro on commit drop as
with marco as (select '2026-10-06 12:39:07.927731+00'::timestamptz m)
select n.id
  from crm.negocio n
  join crm.funil f on f.id = n.funil_id
 cross join marco
 where n.origem = 'compra_aprovada' and n.status = 'ganho' and n.dono_id is null and f.tipo = 'hotmart'
   and n.criado_em >= marco.m and n.criado_em < marco.m + interval '10 minutes'
   and exists (select 1 from crm.hotmart_processado h
                where h.negocio_id = n.id and h.classe = 'aprovada' and h.resultado = 'ganho: negócio novo'
                  and h.quando < marco.m
                  and h.processado_em >= marco.m and h.processado_em < marco.m + interval '10 minutes')
   and not exists (select 1 from crm.atividade a where a.negocio_id = n.id)
   and not exists (select 1 from crm.nota x where x.negocio_id = n.id)
   and not exists (select 1 from crm.log l where l.entidade = 'negocio' and l.entidade_id = n.id::text
                                             and l.autor_tipo in ('pessoa', 'mcp'));
create unique index on _retro (id);

do $conta$
declare v_n int := (select count(*) from _retro);
begin
  if v_n <> 2640 then
    raise exception '20261006191824: seleção deu % negócios (esperado 2.640, medido em 06/10); remedir antes de aplicar', v_n;
  end if;
end
$conta$;

-- ─── 2. Backup completo (arquivo.*, sem acesso pela API) ───────────────────────────────────────────────────────────
create table arquivo.crm_negocio_retro_20261006 as
  select n.* from crm.negocio n where n.id in (select id from _retro);
create table arquivo.crm_hotmart_processado_retro_20261006 as
  select h.* from crm.hotmart_processado h where h.negocio_id in (select id from _retro);
create table arquivo.crm_log_retro_20261006 as
  select l.* from crm.log l where l.entidade = 'negocio' and l.entidade_id in (select id::text from _retro);
create table arquivo.crm_atividade_retro_20261006 as
  select a.* from crm.atividade a where a.negocio_id in (select id from _retro);
create table arquivo.crm_nota_retro_20261006 as
  select x.* from crm.nota x where x.negocio_id in (select id from _retro);
create table arquivo.crm_notificacao_retro_20261006 as
  select x.* from crm.notificacao x where x.ref_id in (select id::text from _retro);
create table arquivo.crm_slack_fila_retro_20261006 as
  select s.* from crm.slack_fila s
   where s.ref in (select n.transacao_ganho from crm.negocio n where n.id in (select id from _retro));

do $perm$
declare t text;
begin
  foreach t in array array['crm_negocio_retro_20261006', 'crm_hotmart_processado_retro_20261006', 'crm_log_retro_20261006',
                           'crm_atividade_retro_20261006', 'crm_nota_retro_20261006', 'crm_notificacao_retro_20261006',
                           'crm_slack_fila_retro_20261006'] loop
    execute format('revoke all on table arquivo.%I from public, anon, authenticated, service_role', t);
    execute format('comment on table arquivo.%I is %L', t,
      'Backup de 20261006191824 (negócios ganhos retroativos da carga Hotmart de 06/10/2026, D8). Nunca DROP sem decisão do Victor.');
  end loop;
end
$perm$;

do $confere_backup$
begin
  if (select count(*) from arquivo.crm_negocio_retro_20261006) <> (select count(*) from _retro) then
    raise exception '20261006191824: backup de negócios incompleto';
  end if;
  if (select count(*) from arquivo.crm_atividade_retro_20261006) + (select count(*) from arquivo.crm_nota_retro_20261006) > 0 then
    raise exception '20261006191824: há atividade/nota nos negócios selecionados (não deveria: a seleção exclui)';
  end if;
end
$confere_backup$;

-- ─── 3. Tira os negócios (1 linha de crm.log por negócio, com motivo) ───────────────────────────────────────────────
update crm.hotmart_processado h
   set negocio_id = null, resultado = left(h.resultado || ' · arquivado 20261006191824', 300)
 where h.negocio_id in (select id from _retro);

do $tira$
declare r record;
begin
  perform set_config('crm.canal', 'migracao', true);
  for r in select id from _retro order by id loop
    perform set_config('crm.resumo',
      'Negócio ganho retroativo da carga Hotmart de 06/10 (D8) arquivado em arquivo.crm_negocio_retro_20261006', true);
    delete from crm.negocio n where n.id = r.id;
  end loop;
  perform set_config('crm.resumo', '', true);
  perform set_config('crm.canal', '', true);
end
$tira$;

-- ─── 4. Compra aprovada sem negócio aberto não cria ganho ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION crm.hotmart_processar(p jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_chave text := p ->> 'chave';
  v_classe text := p ->> 'classe';
  v_tx text := p ->> 'transacao';
  v_quando timestamptz := coalesce((p ->> 'quando')::timestamptz, now());
  v_desde timestamptz;
  v_email text := pessoas.norm_email(p ->> 'email');
  v_tel text := pessoas.norm_telefone(p ->> 'telefone');
  v_nome text := nullif(left(btrim(coalesce(p ->> 'nome', '')), 160), '');
  v_ins int; v_res jsonb; v_pessoa uuid; v_atual uuid; v_g uuid[];
  pc crm.produto_comercial%rowtype; v_linha_nome text; v_oferta text; v_orfa boolean := false; v_valor numeric;
  n crm.negocio%rowtype; f crm.funil%rowtype; v_etapa uuid; v_dono uuid; v_pcid uuid; v_camp uuid; v_neg uuid;
  v_criados int := 0; v_abertos int := 0; v_funis int := 0; v_resultado text; v_rotulo text; v_sinc boolean;
begin
  -- 1. idempotência (PK). Reprocesso explícito ('forcar') reaproveita a linha.
  if coalesce((p ->> 'forcar')::boolean, false) then
    update crm.hotmart_processado x set resultado = 'processando', processado_em = now(), tentativas = x.tentativas + 1
     where x.chave = v_chave;
  else
    insert into crm.hotmart_processado (chave, fonte, ref, conta, classe, transacao, produto_id, oferta_codigo, quando)
    values (v_chave, p ->> 'fonte', p ->> 'ref', p ->> 'conta', v_classe, v_tx, p ->> 'produto_id', p ->> 'oferta_codigo', v_quando)
    on conflict (chave) do nothing;
    get diagnostics v_ins = row_count;
    if v_ins = 0 then return 'duplicado'; end if;
  end if;

  perform set_config('crm.canal', 'hotmart', true); -- crm.tg_log: autor_tipo 'integracao'
  select c.hotmart_desde into v_desde from crm.config c; -- crm.hotmart_entrada garante não nulo

  -- 2. pessoa por e-mail (F0). Sem e-mail não há pessoa (o webhook sempre manda; medido 0 sem e-mail em PURCHASE_*).
  if v_email is null then
    v_resultado := 'sem_email';
  elsif v_quando < v_desde - interval '1 hour' and v_classe <> 'reembolso' and v_classe <> 'chargeback' then
    v_resultado := 'antes_do_corte'; -- D8: sem retroativo (reembolso de venda antiga ainda marca o negócio, se houver)
  end if;
  if v_resultado is not null then
    update crm.hotmart_processado x set resultado = v_resultado where x.chave = v_chave;
    return v_resultado;
  end if;

  v_res := pessoas.resolver(v_nome, v_email, v_tel, null, false, null);
  v_pessoa := (v_res ->> 'pessoa_id')::uuid;
  perform pessoas.anexar(v_pessoa, 'email', v_email, v_email, 'hotmart');
  if v_tel is not null then perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), 'hotmart'); end if;
  v_atual := pessoas.atual(v_pessoa);
  v_g := pessoas.grupo(v_atual);

  -- 3. jornada da pessoa (toda classe, todo produto das 2 contas)
  insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, detalhe, quando)
  values (v_atual,
          case when v_classe = 'aprovada' then 'compra'
               when v_classe in ('reembolso', 'chargeback', 'disputa') then 'reembolso' else 'checkout' end,
          'hotmart', case when v_tx is not null then 'hotmart.transacao' else 'hotmart.evento' end,
          left(coalesce(v_tx, p ->> 'ref'), 80),
          jsonb_strip_nulls(jsonb_build_object('classe', v_classe, 'conta', p ->> 'conta', 'produto', p ->> 'produto_id',
                            'oferta', p ->> 'oferta_codigo', 'valor', p -> 'valor', 'metodo', p ->> 'metodo',
                            'recorrencia', p -> 'recorrencia', 'sck', p ->> 'sck', 'casou_por', v_res ->> 'como')),
          v_quando);

  -- 4. camada comercial: só produto vinculado ao comercial com linha
  select * into pc from crm.produto_comercial x where x.produto_id = p ->> 'produto_id' and x.no_comercial and x.linha is not null;
  if not found then
    update crm.hotmart_processado x set resultado = 'jornada: produto fora do comercial', pessoa_id = v_atual where x.chave = v_chave;
    return 'jornada: produto fora do comercial';
  end if;
  select l.nome into v_linha_nome from crm.linha l where l.chave = pc.linha;

  -- oferta: só entra no negócio se estiver no catálogo (FK fin.ofertas). Fora = aviso (catalogar no mesmo dia).
  if p ->> 'oferta_codigo' is not null then
    select o.oferta_codigo into v_oferta from fin.ofertas o where o.oferta_codigo = p ->> 'oferta_codigo';
    if v_oferta is null then
      v_orfa := true;
      select pr.sincroniza into v_sinc from fin.produtos pr where pr.produto_id = pc.produto_id;
      perform crm.slack_enfileirar('oferta_orfa', p ->> 'oferta_codigo',
        format(':label: *Oferta fora do catálogo* · %s · oferta %s (conta %s). Catalogar hoje em Comercial › Produtos%s.',
               crm.slack_esc(coalesce(pc.nome_comercial, v_linha_nome)), crm.slack_esc(p ->> 'oferta_codigo'),
               crm.slack_esc(p ->> 'conta'),
               case when coalesce(v_sinc, false) then '' else ' (o produto está com sincronização de ofertas desligada no Financeiro)' end));
    end if;
  end if;
  v_valor := coalesce((p ->> 'valor')::numeric,
                      (select o.preco from fin.ofertas o where o.oferta_codigo = v_oferta),
                      (select l.ticket_ref from crm.linha l where l.chave = pc.linha), 0);
  v_valor := greatest(round(v_valor, 2), 0);

  -- 5. por classe
  if v_classe = 'aprovada' then
    if coalesce((p ->> 'recorrencia')::numeric, 1) > 1 then
      v_resultado := 'jornada: recorrência ' || (p ->> 'recorrencia') || ' não é venda nova';
    elsif v_tx is null then
      v_resultado := 'jornada: aprovada sem transação';
    elsif exists (select 1 from crm.negocio x where x.transacao_ganho = v_tx) then
      v_resultado := 'ja_ganho';
    else
      select * into n from crm.negocio x
       where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'aberto'
       order by x.ultima_interacao_em desc nulls last, x.criado_em, x.id
       limit 1 for update;
      if found then
        select e.id into v_etapa from crm.etapa_funil e
         where e.funil_id = n.funil_id and e.papel = 'fechado' and e.arquivada_em is null;
        perform set_config('crm.resumo', format('Venda aprovada na Hotmart (transação %s): negócio ganho', v_tx), true);
        perform set_config('crm.ganho_hotmart', 'on', true);
        update crm.negocio x
           set status = 'ganho', etapa_id = v_etapa, etapa_desde = now(), fechado_em = v_quando, transacao_ganho = v_tx,
               valor = v_valor, oferta_codigo = coalesce(v_oferta, x.oferta_codigo), ultima_interacao_em = now(),
               atualizado_em = now()
         where x.id = n.id;
        perform set_config('crm.ganho_hotmart', 'off', true);
        v_neg := n.id; v_resultado := 'ganho';
      else
        -- 20261006191824 (D8, decisão do Victor 06/10/2026): compra aprovada SEM negócio aberto da pessoa na linha
        -- NÃO cria negócio ganho nem contato comercial. A compra fica na jornada (pessoas.eventos tipo 'compra',
        -- gravado no passo 3, e crm_jornada lê fin.hotmart_transacoes). Ganho no CRM = venda que o comercial trabalhou.
        v_resultado := 'jornada: compra sem negócio aberto (não cria ganho)';
      end if;
    end if;

  elsif v_classe in ('carrinho_abandonado', 'compra_em_aberto', 'cartao_recusado', 'expirada') then
    if v_quando < now() - interval '48 hours' then
      v_resultado := 'jornada: checkout com mais de 48 h';
    elsif exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = any(v_g) and x.opt_out) then
      v_resultado := 'jornada: opt-out';
    elsif exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.linha = pc.linha and x.status = 'ganho'
                     and x.fechado_em > now() - interval '30 days')
       or exists (select 1 from pessoas.eventos e
                    join crm.produto_comercial y on y.produto_id = e.detalhe ->> 'produto' and y.no_comercial and y.linha = pc.linha
                   where e.pessoa_id = any(v_g) and e.tipo = 'compra' and e.fonte = 'hotmart'
                     and e.quando > now() - interval '30 days') then
      -- 20261006191824: compra direta não vira mais negócio ganho; a compra na jornada também conta
      v_resultado := 'jornada: já comprou a linha em 30 dias';
    else
      for f in select x.* from crm.funil x
                where x.ativo and x.tipo = 'hotmart' and x.linha = pc.linha and v_classe = any(x.eventos_hotmart)
                  and (pc.agrupador_id is null or x.agrupador_id = pc.agrupador_id)
                order by x.criado_em, x.id loop
        v_funis := v_funis + 1;
        perform pg_advisory_xact_lock(hashtext('crm.dist:' || f.id::text)); -- mesmo lock de crm_criar_negocio (F2)
        if exists (select 1 from crm.negocio x where x.pessoa_id = any(v_g) and x.funil_id = f.id and x.status = 'aberto') then
          v_abertos := v_abertos + 1;
          continue;
        end if;
        select e.id into v_etapa from crm.etapa_funil e where e.funil_id = f.id and e.arquivada_em is null order by e.ordem limit 1;
        continue when v_etapa is null;
        v_dono := crm.escolher_dono(v_atual, f.id);
        v_pcid := crm.garantir_pc(v_atual);
        if v_dono is not null then
          perform set_config('crm.resumo', format('Dono do contato %s: %s (distribuição, Hotmart)', crm.nome_pessoa(v_atual), crm.nome_perfil(v_dono)), true);
          update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pcid and x.dono_id is null;
        end if;
        select c.id into v_camp from crm.campanha c where c.funil_id = f.id and c.ativa and c.canal = 'hotmart' order by c.criado_em limit 1;
        v_rotulo := case v_classe when 'carrinho_abandonado' then 'carrinho abandonado' when 'compra_em_aberto' then 'boleto/pix gerado'
                                  when 'cartao_recusado' then 'cartão recusado' else 'pagamento expirado' end;
        perform set_config('crm.resumo', format('Hotmart: %s → negócio em %s (dono: %s)', v_rotulo, f.nome, crm.nome_perfil(v_dono)), true);
        insert into crm.negocio (pessoa_id, funil_id, etapa_id, campanha_id, linha, origem, dono_id, valor, oferta_codigo, campos, utm,
                                 ultima_interacao_em)
        values (v_atual, f.id, v_etapa, v_camp, pc.linha, v_classe, v_dono, v_valor, v_oferta,
                jsonb_build_object('origem', 'Hotmart · ' || v_rotulo),
                case when p ->> 'sck' is not null then jsonb_build_object('sck', p ->> 'sck') else '{}'::jsonb end, null)
        returning id into v_neg;
        v_criados := v_criados + 1;
      end loop;
      v_resultado := case when v_criados > 0 then 'negocio_criado: ' || v_criados
                          when v_abertos > 0 then 'ja_aberto'
                          when v_funis = 0 then 'jornada: nenhum funil hotmart da linha escuta ' || v_classe
                          else 'jornada: funil sem etapa' end;
    end if;

  elsif v_classe in ('reembolso', 'chargeback') then
    perform set_config('crm.resumo', format('Hotmart: %s da transação %s', v_classe, coalesce(v_tx, '?')), true);
    update crm.negocio x set reembolsado_em = coalesce(x.reembolsado_em, now()), atualizado_em = now()
     where v_tx is not null and x.transacao_ganho = v_tx and x.reembolsado_em is null
     returning * into n;
    if found then
      v_neg := n.id; v_resultado := v_classe || '_marcado';
      perform crm.slack_enfileirar(v_classe, coalesce(v_tx, v_chave),
        format(':rotating_light: *%s* · %s · %s · R$ %s · vendedor: %s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|abrir negócio>',
               case when v_classe = 'reembolso' then 'Reembolso' else 'Chargeback' end,
               crm.slack_esc(crm.primeiro_nome(v_atual)), crm.slack_esc(coalesce(v_linha_nome, pc.linha)),
               to_char(n.valor, 'FM999G999G990D00'), crm.slack_esc(crm.nome_perfil(n.dono_id)), n.id));
    else
      v_resultado := 'jornada: sem negócio ganho desta transação';
    end if;

  elsif v_classe = 'disputa' then
    select * into n from crm.negocio x where v_tx is not null and x.transacao_ganho = v_tx;
    if found then
      v_neg := n.id; v_resultado := 'disputa_avisada';
      perform crm.slack_enfileirar('disputa', coalesce(v_tx, v_chave),
        format(':warning: *Disputa aberta na Hotmart* · %s · %s · R$ %s · vendedor: %s · <https://grupoparticipa.app.br/comercial/funil?negocio=%s|abrir negócio>',
               crm.slack_esc(crm.primeiro_nome(v_atual)), crm.slack_esc(coalesce(v_linha_nome, pc.linha)),
               to_char(n.valor, 'FM999G999G990D00'), crm.slack_esc(crm.nome_perfil(n.dono_id)), n.id));
    else
      v_resultado := 'jornada: disputa sem negócio ganho';
    end if;
  end if;

  perform set_config('crm.resumo', '', true);
  update crm.hotmart_processado x
     set resultado = left(coalesce(v_resultado, 'ok'), 300), pessoa_id = v_atual, negocio_id = v_neg, oferta_orfa = v_orfa
   where x.chave = v_chave;
  return v_resultado;
end
$function$

;

-- Grants: os mesmos de antes (só postgres executa; quem chama é o trigger da F3). Reafirmados.
revoke all on function crm.hotmart_processar(jsonb) from public, anon, authenticated, service_role;

-- ─── 5. Lista do vendedor sem o sem-dono parado ────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crm_contatos(p_busca text DEFAULT NULL::text, p_limite integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_lim int := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_off int := greatest(coalesce(p_offset, 0), 0);
  v_t text := nullif(btrim(coalesce(p_busca, '')), '');
  v_email text; v_fk text; v_like text; v_ids uuid[];
  v jsonb;
begin
  perform crm.exige_comercial();
  if v_t is not null then
    if length(v_t) < 3 then return jsonb_build_object('itens', '[]'::jsonb, 'temMais', false); end if;
    v_email := pessoas.norm_email(v_t);
    v_fk := pessoas.chave_telefone(v_t);
    v_like := case when v_email is null and v_fk is null
                   then '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%' end;
    -- candidatos por índice (mesmas expressões da F0), depois o grupo de cada um
    v_ids := array(
      select distinct pessoas.atual(s.x) from (
        select i.pessoa_id x from pessoas.identificadores i where v_email is not null and i.tipo = 'email' and i.chave = v_email
        union select i.pessoa_id from pessoas.identificadores i where v_fk is not null and i.tipo = 'telefone' and i.chave = v_fk
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_email is not null and lower(btrim(a.email)) = v_email and a.email is not null and a.email <> ''
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_email is not null and lower(btrim((c.email)::text)) = v_email
        union select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
               where v_fk is not null and controle.fone_key(coalesce(a.telefone_e164, a.telefone)) = v_fk and a.cancelado_em is null
        union select p.id from pessoas.pessoas p join public.compradores c on c.id = p.comprador_id
               where v_fk is not null and controle.fone_key((c.telefone)::text) = v_fk and c.telefone is not null
        union (select p.id from pessoas.pessoas p where v_like is not null and p.nome is not null and p.nome ilike v_like limit 200)
        union (select p.id from pessoas.pessoas p join public.thb_alunos a on a.id = p.aluno_id
                where v_like is not null and a.nome ilike v_like limit 200)
      ) s);
    v_ids := array(select g from unnest(v_ids) u, unnest(pessoas.grupo(u)) g);
  end if;

  select coalesce(jsonb_agg(x.j order by x.criado_em desc, x.pid), '[]'::jsonb) into v from (
    select pc.criado_em, pc.pessoa_id pid, jsonb_build_object(
             'id', atu.id, 'nome', coalesce(d.d_nome, '(sem nome)'),
             'email', case when pc.completo then d.d_email else pessoas.mascara_email(d.d_email) end,
             'telefone', case when pc.completo then d.d_telefone else pessoas.mascara_fim(d.d_telefone) end,
             'cidade', coalesce(al.cidade, cp.endereco_cidade::text),
             'uf', case when upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) ~ '^[A-Z]{2}$'
                        then upper(btrim(coalesce(al.estado, cp.endereco_estado::text))) end,
             'perfil', pc.perfil, 'atuaComHolding', pc.atua_com_holding, 'donoId', pc.dono_id, 'tags', to_jsonb(pc.tags),
             'utm', jsonb_build_object('source', pc.utm_primeira->>'source', 'medium', pc.utm_primeira->>'medium',
                                       'campaign', pc.utm_primeira->>'campaign', 'content', pc.utm_primeira->>'content',
                                       'sck', pc.utm_primeira->>'sck'),
             'score', pc.score, 'ehAluno', d.d_aluno_id is not null, 'optOut', pc.opt_out, 'criadoEm', pc.criado_em) j
      from (select pc0.*, (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())) completo
              from crm.pessoa_comercial pc0
              join pessoas.pessoas pp on pp.id = pc0.pessoa_id
             where (v_ids is null or pc0.pessoa_id = any(v_ids))
               and (v_gestor or pc0.dono_id = v_eu or pc0.pessoa_id in (select crm.pessoas_negocio_meu())
                    -- 20261006191824: sem dono só entra na LISTA do vendedor se tiver negócio aberto (ou negócio sem dono,
                    -- que o vendedor já vê no funil). Na BUSCA (p_busca) continua valendo todo sem dono, como antes.
                    or (pc0.dono_id is null
                        and (v_ids is not null
                             or exists (select 1 from crm.negocio n
                                         where n.pessoa_id in (pc0.pessoa_id, pessoas.atual(pc0.pessoa_id))
                                           and (n.status = 'aberto' or n.dono_id is null)))))
               and (pp.situacao <> 'mesclada'   -- alias: vale a linha da pessoa atual, se ela tiver camada comercial
                    or not exists (select 1 from crm.pessoa_comercial x where x.pessoa_id = pessoas.atual(pc0.pessoa_id)))
             order by pc0.criado_em desc, pc0.pessoa_id
             limit v_lim + 1 offset v_off) pc
      cross join lateral (select pessoas.atual(pc.pessoa_id) id) atu
      cross join lateral pessoas.dados(atu.id) d
      left join public.thb_alunos al on al.id = d.d_aluno_id
      left join public.compradores cp on cp.id = d.d_comprador_id) x;
  return jsonb_build_object('itens', coalesce((select jsonb_agg(e order by o) from jsonb_array_elements(v) with ordinality t(e, o) where o <= v_lim), '[]'::jsonb),
                            'temMais', jsonb_array_length(v) > v_lim);
end
$function$

;

-- Grants: os mesmos de antes (authenticated e service_role executam; public/anon não). Reafirmados.
revoke all on function public.crm_contatos(text, integer, integer) from public, anon;
grant execute on function public.crm_contatos(text, integer, integer) to authenticated, service_role;

do $confere$
begin
  if exists (select 1 from crm.negocio n where n.id in (select id from _retro)) then
    raise exception '20261006191824: sobrou negócio selecionado em crm.negocio';
  end if;
  if exists (select 1 from crm.hotmart_processado h where h.negocio_id in (select id from _retro)) then
    raise exception '20261006191824: crm.hotmart_processado ainda aponta para negócio arquivado';
  end if;
  if position('não cria ganho' in pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) = 0
     or position('''compra_aprovada'', ''ganho''' in pg_get_functiondef('crm.hotmart_processar(jsonb)'::regprocedure)) > 0 then
    raise exception '20261006191824: crm.hotmart_processar não ficou com a regra nova';
  end if;
  if has_function_privilege('anon', 'public.crm_contatos(text,integer,integer)'::regprocedure, 'execute')
     or has_function_privilege('authenticated', 'crm.hotmart_processar(jsonb)'::regprocedure, 'execute') then
    raise exception '20261006191824: permissão errada nas funções recriadas';
  end if;
end
$confere$;

-- ═══ PROVAS ═══

-- ─── 1. O que saiu e o que ficou ───
select pg_temp.ok('1.sairam', (select count(*) from _retro) = 2640
                              and (select count(*) from crm.negocio where id in (select id from _retro)) = 0,
  format('selecionados=%s, ainda em crm.negocio=%s', (select count(*) from _retro),
         (select count(*) from crm.negocio where id in (select id from _retro))));
select pg_temp.info('1.depois_negocios', format('total=%s abertos=%s ganhos=%s perdidos=%s | ganhos compra_aprovada=%s',
  count(*), count(*) filter (where status = 'aberto'), count(*) filter (where status = 'ganho'),
  count(*) filter (where status = 'perdido'), count(*) filter (where status = 'ganho' and origem = 'compra_aprovada')))
  from crm.negocio;
select pg_temp.info('1.saida_por_funil', string_agg(format('%s=%s', f.nome, x.n), ' | ' order by f.nome))
  from (select b.funil_id, count(*) n from arquivo.crm_negocio_retro_20261006 b group by 1) x join crm.funil f on f.id = x.funil_id;
select pg_temp.ok('1.pessoas_ficam', (select count(*) from crm.pessoa_comercial) = (select count(*) from _pc_antes)
                                     and not exists (select 1 from _pc_antes a left join crm.pessoa_comercial pc on pc.pessoa_id = a.pessoa_id
                                                      where pc.pessoa_id is null or md5(row(pc.*)::text) <> a.h),
  format('contatos comerciais antes=%s depois=%s (nenhum alterado)', (select count(*) from _pc_antes), (select count(*) from crm.pessoa_comercial)));
select pg_temp.ok('1.compra_na_jornada',
  (select count(*) from pessoas.eventos e where e.tipo = 'compra' and e.fonte = 'hotmart'
     and e.ref_id in (select transacao_ganho from arquivo.crm_negocio_retro_20261006)) >= 2640,
  format('eventos de compra das transações arquivadas em pessoas.eventos: %s',
    (select count(*) from pessoas.eventos e where e.tipo = 'compra' and e.fonte = 'hotmart'
       and e.ref_id in (select transacao_ganho from arquivo.crm_negocio_retro_20261006))));
select pg_temp.ok('1.log_da_saida',
  (select count(*) from crm.log l where l.acao = 'excluiu' and l.entidade = 'negocio' and l.canal = 'migracao'
     and l.entidade_id in (select id::text from _retro) and l.resumo like 'Negócio ganho retroativo%') = 2640,
  format('linhas "excluiu" em crm.log com motivo: %s', (select count(*) from crm.log l where l.acao = 'excluiu'
     and l.entidade = 'negocio' and l.entidade_id in (select id::text from _retro) and l.resumo like 'Negócio ganho retroativo%')));

-- ─── 2. Backup completo ───
select pg_temp.ok('2.backup', (select count(*) from arquivo.crm_negocio_retro_20261006) = 2640
    and not exists (select 1 from arquivo.crm_negocio_retro_20261006 b join _neg_antes a on a.id = b.id where md5(row(b.*)::text) <> a.h),
  format('negocio=%s (idênticos ao antes) processado=%s log=%s atividade=%s nota=%s notificacao=%s slack=%s',
    (select count(*) from arquivo.crm_negocio_retro_20261006), (select count(*) from arquivo.crm_hotmart_processado_retro_20261006),
    (select count(*) from arquivo.crm_log_retro_20261006), (select count(*) from arquivo.crm_atividade_retro_20261006),
    (select count(*) from arquivo.crm_nota_retro_20261006), (select count(*) from arquivo.crm_notificacao_retro_20261006),
    (select count(*) from arquivo.crm_slack_fila_retro_20261006)));
select pg_temp.ok('2.processado_marcado',
  not exists (select 1 from crm.hotmart_processado h where h.negocio_id in (select id from _retro))
  and (select count(*) from crm.hotmart_processado h where h.resultado like '%· arquivado 20261006191824')
      = (select count(*) from arquivo.crm_hotmart_processado_retro_20261006),
  format('linhas marcadas=%s', (select count(*) from crm.hotmart_processado h where h.resultado like '%· arquivado 20261006191824')));
select pg_temp.ok('2.backup_fechado',
  (select count(*) from information_schema.role_table_grants g where g.table_schema = 'arquivo' and g.table_name like 'crm\_%\_retro\_20261006'
     and g.grantee in ('anon', 'authenticated', 'service_role', 'PUBLIC')) = 0,
  'arquivo.crm_*_retro_20261006 sem grant para anon/authenticated/service_role/public');

-- ─── 3. Nada tocado fora da seleção (dono, atividade, nota, Clint, abertos) ───
select pg_temp.ok('3.intocados',
  not exists (select 1 from _neg_antes a left join crm.negocio n on n.id = a.id
               where a.id not in (select id from _retro) and (n.id is null or md5(row(n.*)::text) <> a.h)),
  format('negócios fora da seleção: %s, todos idênticos ao antes; com dono=%s, abertos=%s',
    (select count(*) from _neg_antes where id not in (select id from _retro)),
    (select count(*) from _neg_antes where id not in (select id from _retro) and dono_id is not null),
    (select count(*) from _neg_antes where id not in (select id from _retro) and status = 'aberto')));
select pg_temp.ok('3.nenhum_com_dono_ou_trabalho',
  not exists (select 1 from arquivo.crm_negocio_retro_20261006 b where b.dono_id is not null)
  and not exists (select 1 from arquivo.crm_log_retro_20261006 l where l.autor_tipo in ('pessoa', 'mcp')),
  'arquivados: 0 com dono, 0 linha de log feita por pessoa ou MCP');

-- ─── 4. Contatos visíveis ───
insert into _contagem select v.k, 'depois', (l ->> 'total')::int, (l ->> 'sem_dono')::int
  from _v v cross join lateral pg_temp.lista(v.u) l where v.k <> 'vis';
select pg_temp.info('4.' || a.k, format('lista antes=%s (sem dono %s) → depois=%s (sem dono %s)', a.total, a.sem_dono, d.total, d.sem_dono))
  from _contagem a join _contagem d on d.k = a.k and d.momento = 'depois' where a.momento = 'antes';
select pg_temp.ok('4.gestor_ve_tudo', d.total = (select count(*) from crm.pessoa_comercial) and d.total = a.total,
  format('gestor: %s = contatos comerciais %s', d.total, (select count(*) from crm.pessoa_comercial)))
  from _contagem a join _contagem d on d.k = a.k and d.momento = 'depois' where a.momento = 'antes' and a.k = 'gestor';
select pg_temp.ok('4.vendedor_sem_parado', bool_and(d.total < a.total), string_agg(format('%s caiu %s', a.k, a.total - d.total), ' | '))
  from _contagem a join _contagem d on d.k = a.k and d.momento = 'depois' where a.momento = 'antes' and a.k like 'vend_%';
do $p4$
declare v jsonb; v_u uuid := (select u from _v where k like 'vend_%' order by k limit 1); v_em text := (select email from _escondido);
        v_lista jsonb; v_achou boolean := false; o int := 0; v_j jsonb;
begin
  if v_em is null then perform pg_temp.ok('4.busca', false, 'sem contato de teste'); return; end if;
  -- some da lista do vendedor
  loop
    v_lista := pg_temp.chamar(v_u, format('select public.crm_contatos(null, 500, %s)', o));
    v_achou := v_achou or exists (select 1 from jsonb_array_elements(v_lista -> 'itens') e where (e ->> 'id')::uuid = (select pessoa_id from _escondido));
    exit when not (v_lista ->> 'temMais')::boolean;
    o := o + 500;
  end loop;
  perform pg_temp.ok('4.sumiu_da_lista', not v_achou, 'contato só-comprador sem dono fora da lista do vendedor');
  -- continua na busca, com e-mail mascarado (não é dele)
  v := pg_temp.chamar(v_u, format('select public.crm_contatos(%L, 50, 0)', v_em));
  perform pg_temp.ok('4.acha_na_busca',
    exists (select 1 from jsonb_array_elements(v -> 'itens') e where (e ->> 'id')::uuid = (select pessoa_id from _escondido)
                                                               and e ->> 'email' is distinct from v_em),
    format('busca do vendedor por e-mail: %s item(ns), e-mail mascarado', jsonb_array_length(v -> 'itens')));
  -- ficha (jornada) continua abrindo para o vendedor e mostra a compra
  v_j := pg_temp.chamar(v_u, format('select public.crm_jornada(%L)', (select pessoa_id from _escondido)));
  perform pg_temp.ok('4.ficha_com_compra',
    not (v_j ? 'erro') and exists (select 1 from jsonb_array_elements(case when jsonb_typeof(v_j) = 'array' then v_j else v_j -> 'itens' end) e
                                    where e::text ilike '%compra%'),
    coalesce(v_j ->> 'erro', 'jornada abre e tem item de compra'));
end
$p4$;

-- ─── 5. Compra simulada (dentro do ensaio) ───
create temp table _prod on commit drop as
select pc.produto_id, pc.linha from crm.produto_comercial pc
  join crm.funil f on f.linha = pc.linha and f.tipo = 'hotmart' and f.ativo
                  and (pc.agrupador_id is null or f.agrupador_id = pc.agrupador_id)
                  and 'carrinho_abandonado' = any(f.eventos_hotmart)
 where pc.no_comercial and pc.linha = 'ht' order by pc.produto_id limit 1;
do $p5$
declare v_p text := (select produto_id from _prod); r text; v_pa uuid; v_pb uuid; v_n int;
begin
  if v_p is null then perform pg_temp.ok('5.fixture', false, 'sem produto ht no comercial'); return; end if;
  -- A: compra aprovada de quem NÃO tem negócio aberto
  r := crm.hotmart_processar(jsonb_build_object('chave', 'tx:academy:ENSAIO-A:aprovada', 'fonte', 'webhook', 'ref', 'ENSAIO-A',
         'conta', 'academy', 'classe', 'aprovada', 'transacao', 'ENSAIO-A', 'produto_id', v_p, 'quando', now(),
         'email', 'compra.a@ensaio.invalid', 'nome', 'Ensaio A', 'valor', 297, 'recorrencia', 1));
  v_pa := pessoas.atual((select h.pessoa_id from crm.hotmart_processado h where h.chave = 'tx:academy:ENSAIO-A:aprovada'));
  perform pg_temp.ok('5.A_sem_aberto_nao_cria_ganho',
    r = 'jornada: compra sem negócio aberto (não cria ganho)'
    and not exists (select 1 from crm.negocio n where n.pessoa_id = v_pa)
    and not exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = v_pa)
    and exists (select 1 from pessoas.eventos e where e.pessoa_id = v_pa and e.tipo = 'compra' and e.ref_id = 'ENSAIO-A'),
    format('resultado "%s"; negócios=%s; contato comercial=%s; compra na jornada=%s', r,
      (select count(*) from crm.negocio n where n.pessoa_id = v_pa), (select count(*) from crm.pessoa_comercial pc where pc.pessoa_id = v_pa),
      (select count(*) from pessoas.eventos e where e.pessoa_id = v_pa and e.tipo = 'compra')));
  -- A2: reenvio da mesma compra
  r := crm.hotmart_processar(jsonb_build_object('chave', 'tx:academy:ENSAIO-A:aprovada', 'fonte', 'sync', 'ref', 'ENSAIO-A', 'conta', 'academy',
         'classe', 'aprovada', 'transacao', 'ENSAIO-A', 'produto_id', v_p, 'quando', now(), 'email', 'compra.a@ensaio.invalid'));
  perform pg_temp.ok('5.A_reenvio', r = 'duplicado', r);
  -- A3: depois de comprar, cartão recusado da mesma linha não abre recuperação (regra dos 30 dias pela jornada)
  r := crm.hotmart_processar(jsonb_build_object('chave', 'tx:academy:ENSAIO-A3:cartao_recusado', 'fonte', 'webhook', 'ref', 'ENSAIO-A3',
         'conta', 'academy', 'classe', 'cartao_recusado', 'transacao', 'ENSAIO-A3', 'produto_id', v_p, 'quando', now(),
         'email', 'compra.a@ensaio.invalid', 'valor', 297));
  perform pg_temp.ok('5.A_comprou_nao_entra_em_recuperacao', r = 'jornada: já comprou a linha em 30 dias'
    and not exists (select 1 from crm.negocio n where n.pessoa_id = v_pa), r);
  -- B: carrinho abandonado abre negócio; a compra aprovada converte esse negócio em ganho
  r := crm.hotmart_processar(jsonb_build_object('chave', 'ev:ENSAIO-B', 'fonte', 'webhook', 'ref', 'ENSAIO-B', 'conta', 'academy',
         'classe', 'carrinho_abandonado', 'produto_id', v_p, 'quando', now(), 'email', 'compra.b@ensaio.invalid', 'nome', 'Ensaio B'));
  v_pb := pessoas.atual((select h.pessoa_id from crm.hotmart_processado h where h.chave = 'ev:ENSAIO-B'));
  perform pg_temp.ok('5.B_carrinho_abre', r like 'negocio_criado:%'
    and exists (select 1 from crm.negocio n where n.pessoa_id = v_pb and n.status = 'aberto' and n.origem = 'carrinho_abandonado'), r);
  r := crm.hotmart_processar(jsonb_build_object('chave', 'tx:academy:ENSAIO-B:aprovada', 'fonte', 'webhook', 'ref', 'ENSAIO-B2',
         'conta', 'academy', 'classe', 'aprovada', 'transacao', 'ENSAIO-B', 'produto_id', v_p, 'quando', now(),
         'email', 'compra.b@ensaio.invalid', 'valor', 297, 'recorrencia', 1));
  select count(*) into v_n from crm.negocio n where n.pessoa_id = v_pb;
  perform pg_temp.ok('5.B_aberto_vira_ganho', r = 'ganho'
    and exists (select 1 from crm.negocio n where n.pessoa_id = v_pb and n.status = 'ganho' and n.transacao_ganho = 'ENSAIO-B'
                                            and n.origem = 'carrinho_abandonado')
    and v_n = 1, format('resultado "%s"; negócios da pessoa=%s (o mesmo, agora ganho)', r, v_n));
  -- C: cartão recusado de pessoa nova continua abrindo negócio (trabalho do vendedor)
  r := crm.hotmart_processar(jsonb_build_object('chave', 'tx:academy:ENSAIO-C:cartao_recusado', 'fonte', 'webhook', 'ref', 'ENSAIO-C',
         'conta', 'academy', 'classe', 'cartao_recusado', 'transacao', 'ENSAIO-C', 'produto_id', v_p, 'quando', now(),
         'email', 'compra.c@ensaio.invalid', 'valor', 297));
  perform pg_temp.ok('5.C_cartao_recusado_abre', r like 'negocio_criado:%', r);
  perform pg_temp.ok('5.nenhum_ganho_sem_aberto',
    not exists (select 1 from crm.negocio n where n.origem = 'compra_aprovada' and n.criado_em >= now() - interval '1 minute'),
    'nenhum negócio origem compra_aprovada criado no ensaio');
end
$p5$;

-- ─── 6. explain (analyze) 2× da lista como a tela pede (vendedor e gestor, 1ª página de 500) ───
do $p6$
declare vk text; i int; t0 timestamptz; v jsonb; ms numeric;
begin
  foreach vk in array array[(select x.k from _v x where x.k like 'vend_%' order by x.k limit 1), 'gestor'] loop
    for i in 1..2 loop
      t0 := clock_timestamp();
      v := pg_temp.chamar((select x.u from _v x where x.k = vk), 'select public.crm_contatos(null, 500, 0)');
      ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
      perform pg_temp.info('6.tempo_' || vk || '_' || i, format('crm_contatos(null,500,0): %s ms, %s itens%s', ms,
        jsonb_array_length(coalesce(v -> 'itens', '[]')), coalesce(' ERRO ' || (v ->> 'erro'), '')));
    end loop;
  end loop;
end
$p6$;

-- ─── 7. Permissões ───
select pg_temp.ok('7.grants',
  has_function_privilege('authenticated', 'public.crm_contatos(text,integer,integer)'::regprocedure, 'execute')
  and not has_function_privilege('anon', 'public.crm_contatos(text,integer,integer)'::regprocedure, 'execute')
  and not has_function_privilege('authenticated', 'crm.hotmart_processar(jsonb)'::regprocedure, 'execute')
  and not has_function_privilege('anon', 'crm.hotmart_processar(jsonb)'::regprocedure, 'execute'),
  format('crm_contatos %s | hotmart_processar %s',
    (select p.proacl::text from pg_proc p where p.oid = 'public.crm_contatos(text,integer,integer)'::regprocedure),
    (select p.proacl::text from pg_proc p where p.oid = 'crm.hotmart_processar(jsonb)'::regprocedure)));
do $p7$
declare v jsonb;
begin
  v := pg_temp.chamar((select u from _v where k = 'vis'), 'select public.crm_contatos(null, 10, 0)');
  perform pg_temp.ok('7.visualizador_barrado', v ->> 'estado' = '42501', coalesce(v ->> 'erro', 'NÃO deu erro'));
end
$p7$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
