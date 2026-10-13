-- 20261013174100: lista de disparo da Black automática (planilha "[BLACK FRIDAY/26] LISTA DISPARO LIVE CONSULTORIA 13/10")
--
-- POR QUE (pedido do Victor via Maestro, ok de 13/10/2026): a lista da live da consultoria era montada à mão (596 linhas
-- em 12/10). Passa a sair do banco, de hora em hora, para a mesma planilha (mesmo link e cabeçalho).
--
-- O QUE FAZ
--   a. dados.grupo_participantes.numero: o número como veio no CSV do SendFlow (só dígitos, 10 a 15). fone_key guarda só
--      DDD + 8 dígitos (perde o 9 e o DDI); sem o número completo, quem só está no grupo não sai no formato 55+DDD+número.
--   b. dados.grupo_foto_processar passa a gravar numero (único ajuste; o resto do corpo é o vivo, md5 conferido).
--   c. dados.dashboard_grupos.papel ('dashboard' | 'lista'): grupo 'lista' tem foto e entra na lista, mas não nos cards.
--      Grupo novo: "Consultoria ao Vivo - Aberto" (release 55zPFLZLHRg7JbXtkPeJ, conta RoWnnm8HUTDZjBITqAFG, a mesma
--      conta "Disparo 1" do ATM), chave black-friday-2026-10, papel 'lista'. O ciclo dados.grupo_foto_ciclo já pega.
--   d. dados_black_grupo: grp só com papel = 'dashboard' (cards do dashboard iguais aos de antes).
--   e. dados.black_lista_disparo_montar(): fontes (dados.black_leads: captação, iscas e página nova da consultoria;
--      Respondi JmSmjBBS; grupos da Black e da consultoria, foto + webhook), tira teste, junta a pessoa por fone8 OU
--      e-mail, padroniza o telefone (55 + DDD válido + número) e separa o fora do padrão. Turma Especial: no Apps Script.
--   f. dados.black_lista_leituras: cada leitura (só contagens).
--   g. dados.black_lista_config: só o sha256 da chave que o Apps Script gera na instalação (a chave não sai de lá).
--   h. public.black_lista_disparo(p_chave): porta do Apps Script, anon + chave; fechada enquanto o hash estiver vazio;
--      no máximo 1 leitura a cada 5 min (pentester 13/10).
--
-- AS 5 PERGUNTAS
--   escala: ~2 mil registros, ~1,5 mil pessoas; resposta JSON de ~300 KB; dedup em memória (temp table) em < 1 s.
--   índice: grupo_participantes único (grupo_id, fone8); respondi.respostas (form_slug); black_leads lê tabelas pequenas.
--   frequência: 24 leituras por dia (gatilho horário); +1 export do SendFlow a cada 10 min (grupo novo no ciclo de foto).
--   repetição: leitura pura (só grava a linha de contagem); a planilha é regravada inteira a cada hora.
--   reversão: 20261013174100_reversao.sql (tira grupo, coluna papel, numero, funções e tabela; volta os corpos vivos).
-- Ensaio: 20261013174100_ensaio.sql. Detalhe: 20261013174100.explain.md e docs/dashboard-black/README.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '96b769d2f4a22b557a3a0a4ed97ac470' then
    raise exception '20261013174100: corpo vivo de dados_black_grupo mudou. Reler.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) <> 'a0f65f0f4bd1aa7c8da22d4e163ea87f' then
    raise exception '20261013174100: corpo vivo de dados.grupo_foto_processar mudou. Reler.';
  end if;
  if to_regclass('dados.black_leads') is null or to_regprocedure('extensions.digest(text,text)') is null then
    raise exception '20261013174100: dados.black_leads ou pgcrypto ausente.';
  end if;
end
$g$;

-- a. Número completo do participante
alter table dados.grupo_participantes add column if not exists numero text check (numero is null or numero ~ '^[0-9]{10,15}$');
comment on column dados.grupo_participantes.numero is
  'Número como veio no CSV do SendFlow, só dígitos (com DDI e o 9). fone_key guarda só DDD + 8. 20261013174100.';

-- b. Foto grava o número
CREATE OR REPLACE FUNCTION dados.grupo_foto_processar(p_foto_id bigint, p_csv text)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261008200000: CSV "Posição;Grupo;Nome;Número;Saiu" (o nome pode ter ';': nome = campos do meio).
-- As linhas de dado vêm com ';' no fim e CRLF (o cabeçalho não): tira os dois antes de separar.
-- Devolve quantos números estão no grupo nesta foto. Aborta (sem mexer em nada) se o cabeçalho não bater.
declare
  f dados.grupo_fotos;
  v_agora timestamptz := now();
  v_cab text;
  v_linhas int;
  v_no int;
  v_sairam int;
begin
  select * into f from dados.grupo_fotos where id = p_foto_id;
  if not found then
    raise exception 'foto % não existe', p_foto_id;
  end if;
  if length(coalesce(p_csv, '')) > 5000000 then
    raise exception 'CSV do SendFlow acima de 5 MB (% caracteres)', length(p_csv);
  end if;
  v_cab := split_part(replace(replace(coalesce(p_csv, ''), chr(65279), ''), chr(13), ''), chr(10), 1);
  if v_cab <> 'Posição;Grupo;Nome;Número;Saiu' then
    -- sem o conteúdo da linha na mensagem (pode ser um participante): só tamanho e md5
    raise exception 'cabeçalho inesperado no CSV do SendFlow (% caracteres, md5 %)', length(v_cab), md5(v_cab);
  end if;

  create temp table if not exists pg_temp._foto (fone8 text, fone_key text, numero text, nome text, grupo text, no_grupo boolean) on commit drop;
  truncate pg_temp._foto;
  insert into pg_temp._foto (fone8, fone_key, numero, nome, grupo, no_grupo)
  select right(controle.fone_key(a[array_length(a, 1) - 1]), 8),
         controle.fone_key(a[array_length(a, 1) - 1]),
         -- 20261013172751: o número como veio (só dígitos, com DDI e o 9): fone_key perde o 9 e o DDI
         case when regexp_replace(a[array_length(a, 1) - 1], '[^0-9]', '', 'g') ~ '^[0-9]{10,15}$'
              then regexp_replace(a[array_length(a, 1) - 1], '[^0-9]', '', 'g') end,
         left(nullif(btrim(array_to_string(a[3:array_length(a, 1) - 2], ';')), ''), 200),
         left(nullif(btrim(a[2]), ''), 100),
         lower(btrim(a[array_length(a, 1)])) <> 'sim'
    from (select string_to_array(regexp_replace(l, ';\s*$', ''), ';') as a
            from unnest(string_to_array(replace(replace(p_csv, chr(65279), ''), chr(13), ''), chr(10))) with ordinality as t(l, n)
           where t.n > 1 and btrim(t.l) <> '') x
   where array_length(a, 1) >= 5 and controle.fone_key(a[array_length(a, 1) - 1]) is not null;
  get diagnostics v_linhas = row_count;

  with agg as (
    select fone8, max(fone_key) as fone_key, max(numero) as numero,
           (array_agg(nome order by no_grupo desc) filter (where nome is not null))[1] as nome,
           left(string_agg(distinct grupo, ', ' order by grupo) filter (where no_grupo), 500) as grupos,
           bool_or(no_grupo) as no_grupo
      from pg_temp._foto group by fone8
  )
  insert into dados.grupo_participantes as p (grupo_id, fone8, fone_key, numero, nome, grupos, no_grupo, visto_primeiro_em,
                                              visto_ultimo_em, saiu_em, primeira_foto_id, ultima_foto_id)
  select f.grupo_id, a.fone8, a.fone_key, a.numero, a.nome, a.grupos, a.no_grupo, v_agora,
         case when a.no_grupo then v_agora end, case when not a.no_grupo then v_agora end, f.id, f.id
    from agg a
  on conflict (grupo_id, fone8) do update
     set fone_key        = coalesce(excluded.fone_key, p.fone_key),
         numero          = coalesce(excluded.numero, p.numero),
         nome            = coalesce(excluded.nome, p.nome),
         grupos          = coalesce(excluded.grupos, p.grupos),
         no_grupo        = excluded.no_grupo,
         visto_ultimo_em = case when excluded.no_grupo then v_agora else p.visto_ultimo_em end,
         saiu_em         = case when excluded.no_grupo then null
                                when p.no_grupo then v_agora
                                else coalesce(p.saiu_em, v_agora) end,
         ultima_foto_id  = f.id;

  -- quem estava no grupo e sumiu da foto: saiu agora
  update dados.grupo_participantes p
     set no_grupo = false, saiu_em = v_agora, ultima_foto_id = f.id
   where p.grupo_id = f.grupo_id and p.no_grupo
     and not exists (select 1 from pg_temp._foto x where x.fone8 = p.fone8);

  select count(*) filter (where no_grupo), count(*) filter (where not no_grupo) into v_no, v_sairam
    from dados.grupo_participantes where grupo_id = f.grupo_id;
  update dados.grupo_fotos
     set etapa = 'feito', concluido_em = v_agora, linhas = v_linhas, numeros_no_grupo = v_no, numeros_sairam = v_sairam,
         erro = null
   where id = f.id;
  return v_no;
end
$function$;


revoke all on function dados.grupo_foto_processar(bigint, text) from public, anon, authenticated, service_role;

-- c. Papel do grupo e o grupo da consultoria
alter table dados.dashboard_grupos add column if not exists papel text not null default 'dashboard'
  check (papel in ('dashboard', 'lista'));
comment on column dados.dashboard_grupos.papel is
  '''dashboard'' entra nos cards; ''lista'' só tem foto e entra na lista de disparo (ex.: grupo da consultoria da Black). 20261013174100.';
insert into dados.dashboard_grupos (chave, sendflow_campanha, sendflow_release_id, sendflow_conta_id, papel)
select 'black-friday-2026-10', 'Consultoria ao Vivo - Aberto', '55zPFLZLHRg7JbXtkPeJ', 'RoWnnm8HUTDZjBITqAFG', 'lista'
 where not exists (select 1 from dados.dashboard_grupos where sendflow_release_id = '55zPFLZLHRg7JbXtkPeJ');

-- d. Cards do dashboard sem os grupos de lista
CREATE OR REPLACE FUNCTION public.dados_black_grupo(p_chave text, p_de date DEFAULT NULL::date, p_ate date DEFAULT NULL::date, p_incluir_teste boolean DEFAULT false, p_recorte jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  d dados.dashboards := dados.black_evento(p_chave);
  v_rec jsonb := dados.black_recorte_valido(p_recorte);
  v_de timestamptz := (coalesce(p_de, d.periodo_inicio)::timestamp at time zone 'America/Sao_Paulo');
  v_ate timestamptz := ((coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date) + 1)::timestamp at time zone 'America/Sao_Paulo');
  r jsonb;
begin
  with grp as (
    select g.id, g.sendflow_campanha, g.sendflow_release_id,
           case when g.sendflow_campanha ~ ' - Advogados$' then 'advogado'
                when g.sendflow_campanha ~ ' - Contadores$' then 'contador'
                when g.sendflow_campanha ~ ' - Outros$' then 'outros' end as segmento
      from dados.dashboard_grupos g
     where g.chave = d.chave
       and g.papel = 'dashboard'   -- 20261013172751: grupo só de lista de disparo (ex.: consultoria) fica fora dos cards
  ), bl as materialized (   -- 20261013023136: telefone dos envios da Black, lido uma vez só
    select l.fone8, l.email, l.whatsapp from dados.black_leads l where l.fone8 is not null
  ), tst as (
    -- 20261013023136: fora do grupo, (1) o telefone marcado como teste e (2) o telefone cujos envios da Black são TODOS
    -- teste (dados.teste_ativo: marcação por e-mail ou por fone), olhando todos os envios da Black, não só os do período.
    -- Telefone misto (um envio teste e outro não) continua contando até decisão do Victor (docs/dashboard-black/README.md).
    -- teste_ativo só roda nos envios dos telefones candidatos (os que têm algum envio de e-mail marcado), não na base toda.
    select m.valor as fone8 from dados.marcacoes_teste m
     where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone'
    union
    select bl.fone8 from bl
     where bl.fone8 in (select c.fone8 from bl c
                          join dados.marcacoes_teste m on m.chave = d.chave and m.desmarcado_em is null
                                                      and m.tipo = 'email' and m.valor = c.email)
     group by bl.fone8
    having bool_and(dados.teste_ativo(d.chave, bl.email, bl.whatsapp))
  ), wh_todos as (   -- toda entrada que o webhook já viu (para saber quem a foto precisa cobrir)
    select distinct grp.id as grupo_id, right(j.fone_key, 8) as fone8
      from crm.evento_jornada j
      join grp on grp.sendflow_campanha = j.tag
     where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
  ), wh as (
    select distinct grp.id as grupo_id, right(j.fone_key, 8) as fone8
      from crm.evento_jornada j
      join grp on grp.sendflow_campanha = j.tag
     where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
       and j.ocorreu_em >= v_de and j.ocorreu_em < v_ate
  ), fo as (   -- foto: só quem o webhook nunca viu entrar naquele grupo
    select distinct p.grupo_id, p.fone8
      from dados.grupo_participantes p
      join grp on grp.id = p.grupo_id
     where p.visto_primeiro_em >= v_de and p.visto_primeiro_em < v_ate
       and not exists (select 1 from wh_todos w where w.grupo_id = p.grupo_id and w.fone8 = p.fone8)
  ), ent as (
    select x.grupo_id, x.fone8, bool_or(x.via = 'webhook') as via_webhook
      from (select grupo_id, fone8, 'webhook' as via from wh union all select grupo_id, fone8, 'foto' from fo) x
     where p_incluir_teste or x.fone8 not in (select fone8 from tst)
     group by x.grupo_id, x.fone8
  ), ld as (
    select l.*
      from dados.black_leads l
     where l.criado_em >= v_de and l.criado_em < v_ate
       and (p_incluir_teste or not dados.teste_ativo(d.chave, l.email, l.whatsapp))
       and dados.black_no_recorte(v_rec, l.porta, l.isca, l.campanha_id, l.conjunto_id, l.anuncio_id)
  ), pessoa as (   -- classe da pessoa = a do envio mais recente que tem profissão
    select ld.pessoa_chave,
           (array_agg(ld.profissao_classe order by ld.criado_em desc, ld.lead_id desc) filter (where ld.profissao_classe is not null))[1] as classe,
           max(ld.fone8) as fone8
      from ld group by ld.pessoa_chave
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object('de', (v_de at time zone 'America/Sao_Paulo')::date, 'ate', ((v_ate at time zone 'America/Sao_Paulo')::date - 1)),
    'recorte', v_rec,
    'incluir_teste', p_incluir_teste,
    'grupos', coalesce((select jsonb_agg(jsonb_build_object(
        'campanha', grp.sendflow_campanha, 'segmento', grp.segmento,
        'unicos', (select count(*) from ent where ent.grupo_id = grp.id),
        'unicos_webhook', (select count(*) from ent where ent.grupo_id = grp.id and ent.via_webhook),
        'unicos_so_foto', (select count(*) from ent where ent.grupo_id = grp.id and not ent.via_webhook),
        'unicos_cruzados', case when v_rec is null then null else
            (select count(*) from pessoa pe where pe.fone8 is not null
                and exists (select 1 from ent where ent.grupo_id = grp.id and ent.fone8 = pe.fone8)) end
      ) order by grp.segmento, grp.sendflow_campanha) from grp), '[]'::jsonb),
    'unicos_grupos_mql', (select count(distinct ent.fone8) from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador')),
    'unicos_grupos_total', (select count(distinct ent.fone8) from ent),
    'unicos_cruzados_mql', case when v_rec is null then null else
        (select count(*) from pessoa pe where pe.fone8 is not null and exists
           (select 1 from ent join grp on grp.id = ent.grupo_id where grp.segmento in ('advogado', 'contador') and ent.fone8 = pe.fone8)) end,
    'leads', jsonb_build_object(
        'unicos', (select count(*) from pessoa),
        'mql', (select count(*) from pessoa where classe in ('advogado', 'contador', 'estudante_direito')),
        'advogado', (select count(*) from pessoa where classe = 'advogado'),
        'estudante_direito', (select count(*) from pessoa where classe = 'estudante_direito'),
        'advogado_mais_estudante', (select count(*) from pessoa where classe in ('advogado', 'estudante_direito')),
        'contador', (select count(*) from pessoa where classe = 'contador'),
        'outros', (select count(*) from pessoa where classe = 'outros'),
        'sem_profissao', (select count(*) from pessoa where classe is null),
        'nao_mql', (select count(*) from pessoa where classe = 'outros' or classe is null)),
    'atualizado', jsonb_build_object(
        'ultimo_evento_webhook', (select max(j.ocorreu_em) from crm.evento_jornada j join grp on grp.sendflow_campanha = j.tag where j.fonte = 'sendflow'),
        'ultima_foto', (select max(p.visto_ultimo_em) from dados.grupo_participantes p join grp on grp.id = p.grupo_id))
  ) into r;
  return r;
end
$function$;
revoke all on function public.dados_black_grupo(text, date, date, boolean, jsonb) from public, anon, service_role;
grant execute on function public.dados_black_grupo(text, date, date, boolean, jsonb) to authenticated;

-- f. A lista: dados.black_lista_disparo_montar() (interna) e public.black_lista_disparo(p_chave) (porta do Apps Script)
create or replace function dados.black_lista_disparo_montar()
returns jsonb language plpgsql volatile set search_path = '' as $$
-- 20261013172751: lista de disparo da Black. Um registro por envio/participante, de 5 fontes; pessoa = componente
-- ligado por telefone (8 últimos dígitos) OU e-mail. Teste sai (marcação ou parece_teste). A Turma Especial NÃO sai aqui:
-- é o Apps Script que tira (a planilha da Isabela não entra no banco). Devolve {resumo, pessoas[]}.
declare
  v_chave constant text := 'black-friday-2026-10';
  v_mudou int;
  v_volta int := 0;
  r jsonb;
begin
  create temp table _r (
    id bigserial, fonte text not null, criado_em timestamptz, nome text, email text,
    bruto text, dig text, fone8 text, fk text, teste boolean not null default false, comp bigint
  ) on commit drop;

  -- 1. formulários da Black (captação, iscas, página nova da consultoria): a view já normaliza e marca teste
  insert into _r (fonte, criado_em, nome, email, bruto, teste)
  select 'lead:' || l.pagina, l.criado_em, nullif(btrim(l.nome), ''), l.email, nullif(btrim(l.whatsapp), ''),
         coalesce(l.teste, false) or coalesce(l.parece_teste, false)
    from dados.black_leads l;

  -- 2. Respondi da consultoria (JmSmjBBS); mesma regra de teste da view
  insert into _r (fonte, criado_em, nome, email, bruto, teste)
  select 'respondi:consultoria', x.respondido_em, nullif(btrim(x.dados->>'nome'), ''), nullif(lower(btrim(x.email)), ''),
         nullif(btrim(coalesce(x.dados->>'telefone', x.telefone)), ''),
         dados.teste_ativo(v_chave, x.email, coalesce(x.dados->>'telefone', x.telefone))
         or coalesce(lower(x.email) like '%teste%' or x.dados->>'nome' ilike '%teste%' or lower(x.email) like '%@advmais.com%', false)
    from respondi.respostas x
   where x.form_slug = 'JmSmjBBS';

  -- 3. grupos (os 3 da Black e o da consultoria): foto do SendFlow (número completo quando a foto já o trouxe) ...
  insert into _r (fonte, criado_em, bruto, fone8, fk)
  select case when g.papel = 'lista' then 'grupo:consultoria' else 'grupo:black' end, p.visto_primeiro_em,
         p.numero, p.fone8, p.fone_key
    from dados.grupo_participantes p
    join dados.dashboard_grupos g on g.id = p.grupo_id
   where g.chave = v_chave;
  -- ... e entrada do webhook que a foto nunca viu (só DDD + 8 dígitos)
  insert into _r (fonte, criado_em, fone8, fk)
  select case when g.papel = 'lista' then 'grupo:consultoria' else 'grupo:black' end, min(j.ocorreu_em), right(j.fone_key, 8),
         max(j.fone_key)
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.chave = v_chave and g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo = 'entrada' and j.fone_key is not null
     and not exists (select 1 from dados.grupo_participantes p where p.grupo_id = g.id and p.fone8 = right(j.fone_key, 8))
   group by g.papel, right(j.fone_key, 8);

  update _r set dig = nullif(regexp_replace(coalesce(bruto, ''), '[^0-9]', '', 'g'), '');
  update _r set fone8 = right(dig, 8) where fone8 is null and length(dig) >= 8;

  -- 4. teste no grupo: telefone marcado como teste, ou cujos registros de formulário são TODOS teste (mesma regra do card)
  update _r g set teste = true
   where g.fonte like 'grupo:%'
     and (exists (select 1 from dados.marcacoes_teste m where m.chave = v_chave and m.desmarcado_em is null
                    and m.tipo = 'fone' and m.valor = g.fone8)
          or (exists (select 1 from _r f where f.fonte not like 'grupo:%' and f.fone8 = g.fone8)
              and not exists (select 1 from _r f where f.fonte not like 'grupo:%' and f.fone8 = g.fone8 and not f.teste)));

  -- 5. pessoa = componente ligado por fone8 ou e-mail (propagação do menor id até parar)
  update _r set comp = id;
  loop
    with kf as (select fone8, min(comp) m from _r where fone8 is not null group by fone8),
         ke as (select email, min(comp) m from _r where email is not null group by email),
         novo as (
      select r.id, least(r.comp, coalesce(kf.m, r.comp), coalesce(ke.m, r.comp)) as m
        from _r r left join kf on kf.fone8 = r.fone8 left join ke on ke.email = r.email
    )
    update _r r set comp = novo.m from novo where novo.id = r.id and novo.m < r.comp;
    get diagnostics v_mudou = row_count;
    v_volta := v_volta + 1;
    exit when v_mudou = 0 or v_volta > 50;
  end loop;
  if v_mudou <> 0 then
    raise exception 'black_lista_disparo: dedup não convergiu em 50 voltas';
  end if;

  -- 6. telefone: padrão = 55 + DDD válido + 8 ou 9 dígitos. Sem DDI (10/11 dígitos com DDD válido) ganha o 55.
  --    Foto antiga ou webhook (só DDD + 8): 55 + DDD + 8, marcado como incompleto. O resto vai para "fora do padrão".
  create temp table _t on commit drop as
  select r.*,
         case
           when r.dig is null then null
           when r.dig ~ '^55[0-9]{10,11}$' and exists (select 1 from dados.ddd_uf u where u.ddd = substr(r.dig, 3, 2)) then r.dig
           when r.dig ~ '^[0-9]{10,11}$' and r.dig !~ '^55' and exists (select 1 from dados.ddd_uf u where u.ddd = left(r.dig, 2)) then '55' || r.dig
         end as tel_ok,
         case
           when r.dig is null then null
           when r.dig ~ '^55[0-9]{10,11}$' and exists (select 1 from dados.ddd_uf u where u.ddd = substr(r.dig, 3, 2)) then null
           when r.dig ~ '^[0-9]{10,11}$' and r.dig !~ '^55' and exists (select 1 from dados.ddd_uf u where u.ddd = left(r.dig, 2)) then null
           when r.dig ~ '^55' and length(r.dig) in (12, 13) then 'DDD inválido'
           when length(r.dig) between 11 and 15 and r.dig !~ '^55' then 'DDI fora do Brasil (prefixo ' || left(r.dig, 3) || ')'
           else 'Número com ' || length(r.dig) || ' dígitos'
         end as motivo
    from _r r;

  -- uma passada por agregação (sem subconsulta por linha): custo linear no volume
  create temp table _p on commit drop as
  with base as (select * from _t where not teste)
  select b.comp,
         (array_agg(b.nome order by b.criado_em desc nulls last, b.id desc) filter (where b.nome is not null))[1] as nome,
         (array_agg(b.email order by b.criado_em desc nulls last, b.id desc) filter (where b.email is not null))[1] as email,
         -- telefone completo de formulário > completo do grupo > incompleto (só DDD + 8) do grupo
         (array_agg(b.tel_ok order by (b.fonte like 'grupo:%'), b.criado_em desc nulls last, b.id desc)
            filter (where b.tel_ok is not null))[1] as telefone,
         (array_agg(b.bruto || '|' || b.motivo order by b.criado_em desc nulls last, b.id desc)
            filter (where b.motivo is not null))[1] as fora,
         (array_agg('55' || b.fk order by b.criado_em desc nulls last, b.id desc)
            filter (where b.dig is null and b.fk ~ '^[0-9]{10}$' and u.ddd is not null))[1] as tel_incompleto,
         array_agg(distinct b.fonte order by b.fonte) as fontes,
         min(b.criado_em) as primeiro
    from base b
    left join dados.ddd_uf u on u.ddd = left(b.fk, 2)
   group by b.comp;
  create temp table _k on commit drop as
  select comp, array_agg(distinct email) filter (where email is not null) as emails,
         array_agg(distinct fone8) filter (where fone8 is not null) as fones8
    from _t group by comp;

  select jsonb_build_object(
    'gerado_em', now(),
    'resumo', jsonb_build_object(
      'registros', (select count(*) from _t),
      'registros_por_fonte', (select jsonb_object_agg(fonte, n) from (select fonte, count(*) n from _t group by fonte) s),
      'pessoas_por_fonte', (select jsonb_object_agg(f, n) from (select f, count(*) n from _p, unnest(fontes) f group by f) s),
      'registros_teste', (select count(*) from _t where teste),
      'pessoas_so_teste', (select count(distinct comp) from _t) - (select count(*) from _p),
      'registros_validos', (select count(*) from _t where not teste),
      'pessoas', (select count(*) from _p),
      'duplicados_fundidos', (select count(*) from _t where not teste) - (select count(*) from _p),
      'lista', (select count(*) from _p where telefone is not null or tel_incompleto is not null or fora is null),
      'fora_do_padrao', (select count(*) from _p where telefone is null and tel_incompleto is null and fora is not null),
      'telefone_incompleto', (select count(*) from _p where telefone is null and tel_incompleto is not null),
      'sem_telefone', (select count(*) from _p where telefone is null and tel_incompleto is null and fora is null),
      'voltas_dedup', v_volta),
    'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
        'aba', case when p.telefone is null and p.tel_incompleto is null and p.fora is not null then 'fora' else 'lista' end,
        'nome', coalesce(p.nome, ''), 'email', coalesce(p.email, ''),
        'telefone', coalesce(p.telefone, p.tel_incompleto, ''),
        'telefone_como_veio', coalesce(split_part(p.fora, '|', 1), ''),
        'motivo', coalesce(split_part(p.fora, '|', 2), ''),
        'emails', coalesce(to_jsonb(k.emails), '[]'::jsonb), 'fones8', coalesce(to_jsonb(k.fones8), '[]'::jsonb),
        'fontes', to_jsonb(p.fontes)) order by p.primeiro, p.comp) from _p p join _k k on k.comp = p.comp), '[]'::jsonb)
  ) into r;
  return r;
end
$$;
revoke all on function dados.black_lista_disparo_montar() from public, anon, authenticated, service_role;

-- g. Registro de cada leitura (sem dado pessoal) e o hash da chave do Apps Script
create table if not exists dados.black_lista_leituras (
  id bigint generated always as identity primary key,
  em timestamptz not null default now(),
  pessoas integer, lista integer, fora_do_padrao integer
);
comment on table dados.black_lista_leituras is
  'Cada leitura da lista de disparo da Black pelo Apps Script (só contagens). 20261013174100.';
alter table dados.black_lista_leituras enable row level security;
revoke all on dados.black_lista_leituras from public, anon, authenticated, service_role;

create table if not exists dados.black_lista_config (
  id boolean primary key default true check (id),
  chave_sha256 text check (chave_sha256 is null or chave_sha256 ~ '^[0-9a-f]{64}$'),
  atualizado_em timestamptz not null default now()
);
comment on table dados.black_lista_config is
  'sha256 (hex) da chave que o Apps Script da lista de disparo da Black gerou na instalação. Só o hash: a chave fica só '
  'nas Script Properties do projeto do Victor. Vazio = porta fechada. 20261013174100.';
alter table dados.black_lista_config enable row level security;
revoke all on dados.black_lista_config from public, anon, authenticated, service_role;
insert into dados.black_lista_config (id) values (true) on conflict (id) do nothing;

-- h. Porta do Apps Script: fail-closed sem hash cadastrado; no máximo 1 leitura a cada 5 min
create or replace function public.black_lista_disparo(p_chave text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
-- 20261013172751: chamada pelo Apps Script (projeto do Victor) da planilha "[BLACK FRIDAY/26] LISTA DISPARO LIVE
-- CONSULTORIA 13/10", de hora em hora, com a anon key + p_chave. Sem a chave certa: 42501 e nada sai.
declare
  v_hash text;
  r jsonb;
begin
  select c.chave_sha256 into v_hash from dados.black_lista_config c where c.id;
  if v_hash is null or p_chave is null or length(p_chave) < 32
     or encode(extensions.digest(p_chave, 'sha256'), 'hex') <> v_hash then
    raise exception 'não autorizado' using errcode = '42501';
  end if;
  if exists (select 1 from dados.black_lista_leituras l where l.em > now() - interval '5 minutes') then
    raise exception 'leitura recente: tente de novo em 5 min' using errcode = '54000';
  end if;
  r := dados.black_lista_disparo_montar();
  insert into dados.black_lista_leituras (pessoas, lista, fora_do_padrao)
  values ((r->'resumo'->>'pessoas')::int, (r->'resumo'->>'lista')::int, (r->'resumo'->>'fora_do_padrao')::int);
  return r;
end
$$;
revoke all on function public.black_lista_disparo(text) from public, anon, authenticated, service_role;
grant execute on function public.black_lista_disparo(text) to anon;

-- Conferência
do $c$
begin
  if (select proacl::text from pg_proc where oid = 'public.dados_black_grupo(text,date,date,boolean,jsonb)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure) <> '{postgres=X/postgres,anon=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> '{postgres=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) <> '{postgres=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.black_lista_disparo(text)'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure)
     or (select count(*) from dados.dashboard_grupos where chave = 'black-friday-2026-10' and papel = 'lista') <> 1
     or (select count(*) from dados.dashboard_grupos where chave = 'black-friday-2026-10' and papel = 'dashboard') <> 3 then
    raise exception '20261013174100: conferência final falhou (ACL, security definer ou grupos)';
  end if;
end
$c$;
