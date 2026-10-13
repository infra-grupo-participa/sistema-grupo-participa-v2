-- Ensaio de 20261013180931 (transação desfeita). Só contagens e sqlstate: nenhum dado pessoal sai daqui.
-- (1) foto: subgrupo que não veio na foto não vira "saiu"; quem sumiu do subgrupo que veio, vira.
-- (2) portas: resumo para a equipe; lista só com contato.ver (membro sem: 42501; master: lê); anon, fora da equipe,
--     outra chave, parâmetro inválido e chamada direta às funções internas recusados; ver e baixar gravam o log.
-- (3) Turma Especial: um e-mail da base em hash tira a pessoa das listas e da planilha.
-- (4) contagens das 3 listas e de cada guia; tempo como authenticated com o limite de 8 s.
begin;
create temp table _z_out (em serial, passo text, linha text);
grant all on pg_temp._z_out to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
-- 20261013180931: base de pessoas da Black para a área de listas (continuação de 20261013174100)
--
-- POR QUE (pedido do Victor via Maestro, 13/10/2026): a lista de disparo vai morar no dashboard, numa área de listas com
-- várias listas (fora do grupo, advogados/contadores/outros fora do grupo, quem não preencheu tal formulário, advogados para
-- a consultoria...). O banco entrega a base deduplicada com os atributos de cada pessoa; a tela monta cada lista.
--
-- O QUE FAZ (Fase 1 das listas, decisões do Victor de 13/10 em Projetos/dashboard-black-friday/CONCEPCAO-LISTAS-MENSAGERIA.md)
--   a. dados.grupo_foto_processar: "sumiu da foto = saiu" só quando o subgrupo da pessoa veio na foto. O SendFlow não exporta
--      subgrupo cheio (consultoria #1 e #2 em 13/10), e a 1ª foto marcou 372 pessoas como "saiu" por engano.
--   b. dados.turma_especial_chaves: a Turma Especial em sha256 (e-mail, fone8, documento), carregada da planilha da Isabela.
--   c. dados.black_base_pessoas(): uma linha por pessoa (dedup por fone8 OU e-mail, sem teste, sem Turma Especial) com
--      nome, e-mail, telefone e situação dele, segmento (advogado com estudante, contador, outros com sem profissão),
--      situação no grupo da Black e no da consultoria (no_grupo/saiu/nunca, e de qual subgrupo saiu) e formulários.
--   d. dados.black_lista(base, lista, segmento): as 3 listas fixas (live_consultoria, fora_grupo, sairam_grupo).
--      Fora do grupo = em relação ao grupo da Black, e quem saiu conta como fora.
--   e. dados.black_lista_downloads: log de cada ver/baixar (quem, lista, segmento, linhas, quando), gravado no servidor.
--   f. public.dados_black_listas_resumo(chave): só contagens, para os cartões (acesso ao dashboard).
--   g. public.dados_black_lista(chave, lista, segmento, acao): a lista com dado pessoal; acesso ao dashboard E contato.ver
--      (pentester 13/10); grava o log antes de devolver.
--   h. dados.black_lista_disparo_montar (planilha): passa a tirar a Turma Especial do banco.
--
-- AS 5 PERGUNTAS
--   escala: ~2 mil registros, ~1 mil pessoas; resposta de ~400 KB; dedup em temp table, ~0,1 s.
--   índice: os mesmos de 20261013174100; turma_especial_chaves pk (tipo, hash), 67 pessoas.
--   frequência: sob demanda (cada abertura da Mensageria = 1 resumo; cada ver/baixar = 1 lista + 1 linha de log).
--   repetição: leitura pura; a foto passa a marcar saída só no subgrupo exportado (idempotente como antes).
--   reversão: 20261013180931_reversao.sql (volta grupo_foto_processar e black_lista_disparo_montar aos corpos de
--             20261013174100, tira o resto; o log de downloads vai junto).
-- Ensaio: 20261013180931_ensaio.sql. Detalhe: 20261013180931.explain.md e docs/dashboard-black/README.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) <> '19441b5142b9eaa32cc61a1f242b0e53' then
    raise exception '20261013180931: corpo vivo de dados.grupo_foto_processar não é o de 20261013174100. Reler.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> 'a84ef934b7a36ca887e7f8d278ec42c0' then
    raise exception '20261013180931: corpo vivo de dados.black_lista_disparo_montar não é o de 20261013174100. Reler.';
  end if;
  if to_regprocedure('acesso.tem(text)') is null or to_regprocedure('dados.black_evento(text)') is null or to_regclass('dados.black_leads') is null then
    raise exception '20261013180931: dados.black_evento ou dados.black_leads ausente.';
  end if;
end
$g$;

-- a. Saída só no subgrupo exportado
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
  -- 20261013190000: só quando o subgrupo dele veio nesta foto. O SendFlow não exporta subgrupo cheio (consultoria #1 e #2
  -- em 13/10): sem esta trava, todo mundo de um subgrupo cheio virava "saiu" na primeira foto.
  update dados.grupo_participantes p
     set no_grupo = false, saiu_em = v_agora, ultima_foto_id = f.id
   where p.grupo_id = f.grupo_id and p.no_grupo
     and not exists (select 1 from pg_temp._foto x where x.fone8 = p.fone8)
     and string_to_array(p.grupos, ', ') && (select array_agg(distinct x.grupo) from pg_temp._foto x where x.grupo is not null);

  select count(*) filter (where no_grupo), count(*) filter (where not no_grupo) into v_no, v_sairam
    from dados.grupo_participantes where grupo_id = f.grupo_id;
  update dados.grupo_fotos
     set etapa = 'feito', concluido_em = v_agora, linhas = v_linhas, numeros_no_grupo = v_no, numeros_sairam = v_sairam,
         erro = null
   where id = f.id;
  return v_no;
end
$function$;

-- c. Turma Especial no banco, só como hash (sha256 hex do valor normalizado): a lista sai sem ela sem depender do Apps Script
create table if not exists dados.turma_especial_chaves (
  tipo text not null check (tipo in ('email', 'fone8', 'documento')),
  hash text not null check (hash ~ '^[0-9a-f]{64}$'),
  carregado_em timestamptz not null default now(),
  primary key (tipo, hash)
);
comment on table dados.turma_especial_chaves is
  'Turma Especial (planilha da Isabela 1fLrJL4E..., aba Página1) em hash sha256 hex: email minúsculo, 8 últimos dígitos de '
  'DDD + Número, documento só dígitos. Toda lista de disparo sai sem ela. Recarga: docs/dashboard-black/README.md. 20261013180931.';
alter table dados.turma_especial_chaves enable row level security;
revoke all on dados.turma_especial_chaves from public, anon, authenticated, service_role;

-- d. A base: uma linha por pessoa, com os atributos para montar qualquer lista
create or replace function dados.black_base_pessoas()
returns jsonb language plpgsql volatile set search_path = '' as $$
-- 20261013190000: base deduplicada dos leads da Black. Pessoa = componente ligado por telefone (8 últimos dígitos) OU
-- e-mail. Fora: teste (marcação, parece_teste; no grupo, telefone cujos registros de formulário são todos teste) e a
-- Turma Especial (dados.turma_especial_chaves). Devolve {resumo, pessoas[]}; cada pessoa traz nome, email, telefone,
-- profissão normalizada, situação em cada grupo e cada formulário preenchido. Mesma regra de dedup e de telefone de
-- dados.black_lista_disparo_montar (20261013174100).
declare
  v_chave constant text := 'black-friday-2026-10';
  v_mudou int;
  v_volta int := 0;
  r jsonb;
begin
  drop table if exists pg_temp._b, pg_temp._te, pg_temp._bt, pg_temp._bp;   -- 2ª chamada na mesma transação
  create temp table _b (
    id bigserial, fonte text not null, criado_em timestamptz, nome text, email text, prof text,
    bruto text, dig text, fone8 text, fk text, grupo_estado text, grupo_nome text, parcial boolean not null default false,
    teste boolean not null default false, comp bigint
  ) on commit drop;

  -- formulários da Black (view já normaliza e marca teste): captacao | fluxograma, checkup, futurometro (isca) | consultoria (página)
  insert into _b (fonte, criado_em, nome, email, prof, bruto, teste)
  select case when l.pagina in ('fluxograma', 'checkup', 'futurometro') then 'isca' when l.pagina = 'consultoria' then 'pagina_consultoria' else 'captacao' end,
         l.criado_em, nullif(btrim(l.nome), ''), l.email, l.profissao_classe, nullif(btrim(l.whatsapp), ''),
         coalesce(l.teste, false) or coalesce(l.parece_teste, false)
    from dados.black_leads l;

  -- Respondi da consultoria (JmSmjBBS), concluídas e parciais com contato
  insert into _b (fonte, criado_em, nome, email, prof, bruto, parcial, teste)
  select 'respondi_consultoria', x.respondido_em, nullif(btrim(x.dados->>'nome'), ''), nullif(lower(btrim(x.email)), ''),
         case btrim(x.dados->>'profissao') when 'Advogado(a)' then 'advogado' when 'Contador(a)' then 'contador'
              when 'Estudante de Direito' then 'estudante_direito' when '' then null
              else case when x.dados->>'profissao' is null then null else 'outros' end end,
         nullif(btrim(coalesce(x.dados->>'telefone', x.telefone)), ''),
         coalesce((x.dados->>'parcial')::boolean, false),
         dados.teste_ativo(v_chave, x.email, coalesce(x.dados->>'telefone', x.telefone))
         or coalesce(lower(x.email) like '%teste%' or x.dados->>'nome' ilike '%teste%' or lower(x.email) like '%@advmais.com%', false)
    from respondi.respostas x
   where x.form_slug = 'JmSmjBBS'
     and (nullif(btrim(x.email), '') is not null or length(regexp_replace(coalesce(x.dados->>'telefone', x.telefone, ''), '[^0-9]', '', 'g')) >= 10);

  -- grupos: foto (número completo quando veio) e entrada do webhook que a foto nunca viu
  insert into _b (fonte, criado_em, bruto, fone8, fk, grupo_estado, grupo_nome)
  select case when g.papel = 'lista' then 'grupo_consultoria' else 'grupo_black' end, p.visto_primeiro_em, p.numero, p.fone8, p.fone_key,
         case when p.no_grupo then 'no_grupo' else 'saiu' end, coalesce(p.grupos, g.sendflow_campanha)
    from dados.grupo_participantes p
    join dados.dashboard_grupos g on g.id = p.grupo_id
   where g.chave = v_chave;
  insert into _b (fonte, criado_em, fone8, fk, grupo_estado, grupo_nome)
  select case when g.papel = 'lista' then 'grupo_consultoria' else 'grupo_black' end, min(j.ocorreu_em), right(j.fone_key, 8), max(j.fone_key),
         case when (array_agg(j.tipo order by j.ocorreu_em desc, j.id desc))[1] = 'entrada' then 'no_grupo' else 'saiu' end,
         g.sendflow_campanha
    from crm.evento_jornada j
    join dados.dashboard_grupos g on g.chave = v_chave and g.sendflow_campanha = j.tag
   where j.fonte = 'sendflow' and j.tipo in ('entrada', 'saida') and j.fone_key is not null
     and not exists (select 1 from dados.grupo_participantes p where p.grupo_id = g.id and p.fone8 = right(j.fone_key, 8))
   group by g.papel, g.sendflow_campanha, right(j.fone_key, 8);

  update _b set dig = nullif(regexp_replace(coalesce(bruto, ''), '[^0-9]', '', 'g'), '');
  update _b set fone8 = right(dig, 8) where fone8 is null and length(dig) >= 8;

  -- teste no grupo: telefone marcado, ou cujos registros de formulário são todos teste
  update _b g set teste = true
   where g.fonte like 'grupo_%'
     and (exists (select 1 from dados.marcacoes_teste m where m.chave = v_chave and m.desmarcado_em is null
                    and m.tipo = 'fone' and m.valor = g.fone8)
          or (exists (select 1 from _b f where f.fonte not like 'grupo_%' and f.fone8 = g.fone8)
              and not exists (select 1 from _b f where f.fonte not like 'grupo_%' and f.fone8 = g.fone8 and not f.teste)));

  -- pessoa = componente ligado por fone8 ou e-mail
  update _b set comp = id;
  loop
    with kf as (select fone8, min(comp) m from _b where fone8 is not null group by fone8),
         ke as (select email, min(comp) m from _b where email is not null group by email),
         novo as (
      select b.id, least(b.comp, coalesce(kf.m, b.comp), coalesce(ke.m, b.comp)) as m
        from _b b left join kf on kf.fone8 = b.fone8 left join ke on ke.email = b.email
    )
    update _b b set comp = novo.m from novo where novo.id = b.id and novo.m < b.comp;
    get diagnostics v_mudou = row_count;
    v_volta := v_volta + 1;
    exit when v_mudou = 0 or v_volta > 50;
  end loop;
  if v_mudou <> 0 then
    raise exception 'black_base_pessoas: dedup não convergiu em 50 voltas';
  end if;

  -- Turma Especial: a pessoa inteira sai se qualquer e-mail ou telefone dela casar
  create temp table _te on commit drop as
  select distinct b.comp from _b b
   where exists (select 1 from dados.turma_especial_chaves t where t.tipo = 'email' and b.email is not null
                   and t.hash = encode(extensions.digest(b.email, 'sha256'), 'hex'))
      or exists (select 1 from dados.turma_especial_chaves t where t.tipo = 'fone8' and b.fone8 is not null
                   and t.hash = encode(extensions.digest(b.fone8, 'sha256'), 'hex'));

  -- telefone: 55 + DDD válido + 8 ou 9 dígitos; 10/11 dígitos com DDD válido ganha o 55
  create temp table _bt on commit drop as
  select b.*,
         case
           when b.dig ~ '^55[0-9]{10,11}$' and u1.ddd is not null then b.dig
           when b.dig ~ '^[0-9]{10,11}$' and b.dig !~ '^55' and u2.ddd is not null then '55' || b.dig
         end as tel_ok,
         case
           when b.dig is null then null
           when b.dig ~ '^55[0-9]{10,11}$' and u1.ddd is not null then null
           when b.dig ~ '^[0-9]{10,11}$' and b.dig !~ '^55' and u2.ddd is not null then null
           when b.dig ~ '^55' and length(b.dig) in (12, 13) then 'DDD inválido'
           when length(b.dig) between 11 and 15 and b.dig !~ '^55' then 'DDI fora do Brasil (prefixo ' || left(b.dig, 3) || ')'
           else 'Número com ' || length(b.dig) || ' dígitos'
         end as motivo
    from _b b
    left join dados.ddd_uf u1 on u1.ddd = substr(b.dig, 3, 2)
    left join dados.ddd_uf u2 on u2.ddd = left(b.dig, 2);

  create temp table _bp on commit drop as
  with base as (select bt.* from _bt bt where not bt.teste and bt.comp not in (select comp from _te))
  select b.comp,
         (array_agg(b.nome order by b.criado_em desc nulls last, b.id desc) filter (where b.nome is not null))[1] as nome,
         (array_agg(b.email order by b.criado_em desc nulls last, b.id desc) filter (where b.email is not null))[1] as email,
         (array_agg(b.tel_ok order by (b.fonte like 'grupo_%'), b.criado_em desc nulls last, b.id desc) filter (where b.tel_ok is not null))[1] as telefone,
         (array_agg('55' || b.fk order by b.criado_em desc nulls last, b.id desc)
            filter (where b.dig is null and b.fk ~ '^[0-9]{10}$' and exists (select 1 from dados.ddd_uf u where u.ddd = left(b.fk, 2))))[1] as tel_incompleto,
         (array_agg(b.bruto order by b.criado_em desc nulls last, b.id desc) filter (where b.motivo is not null))[1] as fora_bruto,
         (array_agg(b.motivo order by b.criado_em desc nulls last, b.id desc) filter (where b.motivo is not null))[1] as fora_motivo,
         (array_agg(b.prof order by b.criado_em desc nulls last, b.id desc) filter (where b.prof is not null))[1] as prof,
         -- 'saiu' só se não está mais em nenhum grupo Black (pode ter saído de um subgrupo e estar em outro)
         case when bool_or(b.fonte = 'grupo_black' and b.grupo_estado = 'no_grupo') then 'no_grupo'
              when bool_or(b.fonte = 'grupo_black') then 'saiu' else 'nunca' end as grupo_black,
         case when bool_or(b.fonte = 'grupo_consultoria' and b.grupo_estado = 'no_grupo') then 'no_grupo'
              when bool_or(b.fonte = 'grupo_consultoria') then 'saiu' else 'nunca' end as grupo_consultoria,
         bool_or(b.fonte = 'captacao') as f_captacao,
         bool_or(b.fonte = 'isca') as f_isca,
         bool_or(b.fonte = 'respondi_consultoria' and not b.parcial) as f_respondi,
         bool_or(b.fonte = 'respondi_consultoria' and b.parcial) and not bool_or(b.fonte = 'respondi_consultoria' and not b.parcial) as f_respondi_so_parcial,
         bool_or(b.fonte = 'pagina_consultoria') as f_pagina,
         string_agg(distinct b.grupo_nome, ', ') filter (where b.fonte = 'grupo_black' and b.grupo_estado = 'saiu') as saiu_black_de,
         string_agg(distinct b.grupo_nome, ', ') filter (where b.fonte = 'grupo_consultoria' and b.grupo_estado = 'saiu') as saiu_consultoria_de,
         array_agg(distinct b.fonte order by b.fonte) as fontes,
         min(b.criado_em) as primeiro, max(b.criado_em) as ultimo
    from base b
   group by b.comp;

  select jsonb_build_object(
    'gerado_em', now(),
    'resumo', jsonb_build_object(
      'registros', (select count(*) from _bt),
      'registros_por_fonte', (select jsonb_object_agg(fonte, n) from (select fonte, count(*) n from _bt group by fonte) s),
      'pessoas_por_fonte', (select jsonb_object_agg(f, n) from (select f, count(*) n from _bp, unnest(fontes) f group by f) s),
      'registros_teste', (select count(*) from _bt where teste),
      'pessoas_so_teste', (select count(distinct comp) from _bt where comp not in (select comp from _bt where not teste)),
      'pessoas_turma_especial', (select count(*) from _te where comp in (select comp from _bt where not teste)),
      'pessoas', (select count(*) from _bp),
      'duplicados_fundidos', (select count(*) from _bt where not teste and comp not in (select comp from _te)) - (select count(*) from _bp),
      'telefone_padrao', (select count(*) from _bp where telefone is not null),
      'telefone_incompleto', (select count(*) from _bp where telefone is null and tel_incompleto is not null),
      'telefone_fora_do_padrao', (select count(*) from _bp where telefone is null and tel_incompleto is null and fora_motivo is not null),
      'sem_telefone', (select count(*) from _bp where telefone is null and tel_incompleto is null and fora_motivo is null),
      'segmento', (select jsonb_object_agg(p, n) from (select case when prof in ('advogado', 'estudante_direito') then 'advogado' when prof = 'contador' then 'contador' else 'outros' end p, count(*) n from _bp group by 1) s),
      'sem_profissao', (select count(*) from _bp where prof is null),
      'grupo_black', (select jsonb_object_agg(grupo_black, n) from (select grupo_black, count(*) n from _bp group by 1) s),
      'grupo_consultoria', (select jsonb_object_agg(grupo_consultoria, n) from (select grupo_consultoria, count(*) n from _bp group by 1) s),
      'ultimo_dado_em', (select max(criado_em) from _bt),
      'voltas_dedup', v_volta),
    'pessoas', coalesce((select jsonb_agg(jsonb_build_object(
        'nome', p.nome, 'email', p.email,
        'telefone', coalesce(p.telefone, p.tel_incompleto),
        'telefone_situacao', case when p.telefone is not null then 'padrao' when p.tel_incompleto is not null then 'incompleto'
                                  when p.fora_motivo is not null then 'fora_do_padrao' else 'sem_telefone' end,
        'telefone_como_veio', case when p.telefone is null then coalesce(p.fora_bruto, p.tel_incompleto) end,
        'motivo', case when p.telefone is not null then null
                       when p.tel_incompleto is not null then 'Número sem o 9 (o grupo só guardou DDD + 8 dígitos)'
                       when p.fora_motivo is not null then p.fora_motivo else 'Sem telefone' end,
        'segmento', case when p.prof in ('advogado', 'estudante_direito') then 'advogado' when p.prof = 'contador' then 'contador' else 'outros' end,
        'sem_profissao', p.prof is null,
        'profissao_detalhe', coalesce(p.prof, 'sem_dado'),
        'grupo_black', p.grupo_black, 'grupo_consultoria', p.grupo_consultoria,
        'saiu_black_de', p.saiu_black_de, 'saiu_consultoria_de', p.saiu_consultoria_de,
        'form_captacao', p.f_captacao, 'form_isca', p.f_isca, 'form_respondi_consultoria', p.f_respondi,
        'form_respondi_consultoria_parcial', p.f_respondi_so_parcial, 'form_pagina_consultoria', p.f_pagina,
        'fontes', to_jsonb(p.fontes), 'primeiro_contato', p.primeiro, 'ultimo_contato', p.ultimo
      ) order by p.primeiro, p.comp) from _bp p), '[]'::jsonb)
  ) into r;
  return r;
end
$$;
revoke all on function dados.black_base_pessoas() from public, anon, authenticated, service_role;


-- e. As listas fixas da Fase 1 (presets). p_lista: live_consultoria | fora_grupo | sairam_grupo;
--    p_segmento: geral | advogado (com estudante de direito) | contador | outros (outros + sem profissão).
--    Toda lista: dedup, sem teste, sem Turma Especial (já fora da base). Telefone padrão vai em `linhas`; o resto em
--    `fora_padrao` com o motivo (arquivo à parte).
create or replace function dados.black_lista(p_base jsonb, p_lista text, p_segmento text)
returns jsonb language sql immutable set search_path = '' as $$
  with p as (
    select x from jsonb_array_elements(p_base->'pessoas') x
     where case p_lista
             when 'live_consultoria' then true
             when 'fora_grupo' then x->>'grupo_black' in ('nunca', 'saiu')
             when 'sairam_grupo' then x->>'grupo_black' = 'saiu' or x->>'grupo_consultoria' = 'saiu'
           end
       and (coalesce(p_segmento, 'geral') = 'geral' or x->>'segmento' = p_segmento)
  )
  select jsonb_build_object(
    'lista', p_lista, 'segmento', coalesce(p_segmento, 'geral'),
    'linhas', coalesce((select jsonb_agg(x) from p where x->>'telefone_situacao' = 'padrao'), '[]'::jsonb),
    'fora_padrao', coalesce((select jsonb_agg(x) from p where x->>'telefone_situacao' <> 'padrao'), '[]'::jsonb))
$$;
revoke all on function dados.black_lista(jsonb, text, text) from public, anon, authenticated, service_role;

-- f. Log de cada "ver" e "baixar" (sem dado pessoal: quem, qual lista, segmento, quantas linhas, quando)
create table if not exists dados.black_lista_downloads (
  id bigint generated always as identity primary key,
  em timestamptz not null default now(),
  perfil_id uuid,
  perfil_email text,
  acao text not null check (acao in ('ver', 'baixar')),
  lista text not null,
  segmento text not null,
  linhas integer not null,
  linhas_fora_padrao integer not null
);
comment on table dados.black_lista_downloads is
  'Quem viu ou baixou cada lista de disparo da Black, gravado pela própria RPC (public.dados_black_lista). 20261013180931.';
create index if not exists black_lista_downloads_em_idx on dados.black_lista_downloads (em desc);
alter table dados.black_lista_downloads enable row level security;
revoke all on dados.black_lista_downloads from public, anon, authenticated, service_role;

-- g. Contagens dos cartões (sem dado pessoal): quem tem acesso ao dashboard
create or replace function public.dados_black_listas_resumo(p_chave text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
-- 20261013190000: números dos cartões da área de listas (Mensageria). Só contagens.
declare
  d dados.dashboards := dados.black_evento(p_chave);
  b jsonb := dados.black_base_pessoas();
  r jsonb := '{}'::jsonb;
  l text; s text; x jsonb;
begin
  foreach l in array array['live_consultoria', 'fora_grupo', 'sairam_grupo'] loop
    foreach s in array array['geral', 'advogado', 'contador', 'outros'] loop
      continue when l = 'live_consultoria' and s <> 'geral';
      x := dados.black_lista(b, l, s);
      r := r || jsonb_build_object(l || ':' || s, jsonb_build_object(
        'linhas', jsonb_array_length(x->'linhas'), 'fora_padrao', jsonb_array_length(x->'fora_padrao'),
        'sem_profissao', (select count(*) from jsonb_array_elements(x->'linhas') e where (e->>'sem_profissao')::boolean),
        'saiu_black', (select count(*) from jsonb_array_elements(x->'linhas') e where e->>'grupo_black' = 'saiu'),
        'saiu_consultoria', (select count(*) from jsonb_array_elements(x->'linhas') e where e->>'grupo_consultoria' = 'saiu')));
    end loop;
  end loop;
  return jsonb_build_object('gerado_em', b->'gerado_em', 'ultimo_dado_em', b->'resumo'->'ultimo_dado_em',
    'turma_especial', b->'resumo'->'pessoas_turma_especial', 'pessoas', b->'resumo'->'pessoas', 'listas', r);
end
$$;
revoke all on function public.dados_black_listas_resumo(text) from public, anon, service_role;
grant execute on function public.dados_black_listas_resumo(text) to authenticated;

-- h. A lista com dado pessoal: acesso ao dashboard E contato.ver (master sempre; os outros, por acesso_capacidade_definir).
--    Grava o log no servidor antes de devolver.
create or replace function public.dados_black_lista(p_chave text, p_lista text, p_segmento text, p_acao text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
-- 20261013190000: lista de disparo da Black para "Ver" (gaveta) e "Baixar CSV". Sem acesso ou sem contato.ver: 42501.
declare
  d dados.dashboards := dados.black_evento(p_chave);
  b jsonb;
  x jsonb;
  v_email text;
begin
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if p_lista is null or p_lista not in ('live_consultoria', 'fora_grupo', 'sairam_grupo')
     or coalesce(p_segmento, 'geral') not in ('geral', 'advogado', 'contador', 'outros')
     or (p_lista = 'live_consultoria' and coalesce(p_segmento, 'geral') <> 'geral')
     or p_acao is null or p_acao not in ('ver', 'baixar') then
    raise exception 'lista, segmento ou ação inválidos' using errcode = '22023';
  end if;
  b := dados.black_base_pessoas();
  x := dados.black_lista(b, p_lista, coalesce(p_segmento, 'geral'));
  select p.email into v_email from public.perfis p where p.id = auth.uid();
  insert into dados.black_lista_downloads (perfil_id, perfil_email, acao, lista, segmento, linhas, linhas_fora_padrao)
  values (auth.uid(), v_email, p_acao, p_lista, coalesce(p_segmento, 'geral'),
          jsonb_array_length(x->'linhas'), jsonb_array_length(x->'fora_padrao'));
  return x || jsonb_build_object('gerado_em', b->'gerado_em', 'turma_especial', b->'resumo'->'pessoas_turma_especial');
end
$$;
revoke all on function public.dados_black_lista(text, text, text, text) from public, anon, service_role;
grant execute on function public.dados_black_lista(text, text, text, text) to authenticated;

-- i. A planilha automática (20261013174100) também tira a Turma Especial no banco
CREATE OR REPLACE FUNCTION dados.black_lista_disparo_montar()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
-- 20261013172751: lista de disparo da Black. Um registro por envio/participante, de 5 fontes; pessoa = componente
-- ligado por telefone (8 últimos dígitos) OU e-mail. Teste sai (marcação ou parece_teste). A Turma Especial NÃO sai aqui:
-- é o Apps Script que tira (a planilha da Isabela não entra no banco). Devolve {resumo, pessoas[]}.
declare
  v_chave constant text := 'black-friday-2026-10';
  v_mudou int;
  v_volta int := 0;
  r jsonb;
begin
  drop table if exists pg_temp._r, pg_temp._t, pg_temp._p, pg_temp._k, pg_temp._te;   -- 20261013190000: 2ª chamada na transação
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
   group by g.papel, g.sendflow_campanha, right(j.fone_key, 8);

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
  -- 20261013190000: Turma Especial sai aqui também (antes só no Apps Script): a pessoa inteira, por e-mail ou telefone
  create temp table _te on commit drop as
  select distinct t.comp from _t t
   where exists (select 1 from dados.turma_especial_chaves k where k.tipo = 'email' and t.email is not null
                   and k.hash = encode(extensions.digest(t.email, 'sha256'), 'hex'))
      or exists (select 1 from dados.turma_especial_chaves k where k.tipo = 'fone8' and t.fone8 is not null
                   and k.hash = encode(extensions.digest(t.fone8, 'sha256'), 'hex'));
  create temp table _p on commit drop as
  with base as (select * from _t where not teste and comp not in (select comp from _te))
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
      'pessoas_so_teste', (select count(distinct comp) from _t where comp not in (select comp from _t where not teste)),
      'turma_especial', (select count(*) from _te where comp in (select comp from _t where not teste)),
      'registros_validos', (select count(*) from _t where not teste),
      'pessoas', (select count(*) from _p),
      'duplicados_fundidos', (select count(*) from _t where not teste and comp not in (select comp from _te)) - (select count(*) from _p),
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
$function$;
revoke all on function dados.black_lista_disparo_montar() from public, anon, authenticated, service_role;

revoke all on function dados.grupo_foto_processar(bigint, text) from public, anon, authenticated, service_role;

do $c$
begin
  if (select proacl::text from pg_proc where oid = 'public.dados_black_lista(text,text,text,text)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'public.dados_black_listas_resumo(text)'::regprocedure) <> '{postgres=X/postgres,authenticated=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.black_base_pessoas()'::regprocedure) <> '{postgres=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.black_lista(jsonb,text,text)'::regprocedure) <> '{postgres=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> '{postgres=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) <> '{postgres=X/postgres}'
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_lista(text,text,text,text)'::regprocedure)
     or not (select prosecdef from pg_proc where oid = 'public.dados_black_listas_resumo(text)'::regprocedure)
     or (select prosecdef from pg_proc where oid = 'dados.black_base_pessoas()'::regprocedure)
     or (select relacl::text from pg_class where oid = 'dados.turma_especial_chaves'::regclass) <> '{postgres=arwdDxtm/postgres}'
     or (select relacl::text from pg_class where oid = 'dados.black_lista_downloads'::regclass) <> '{postgres=arwdDxtm/postgres}' then
    raise exception '20261013180931: conferência final falhou (ACL ou security definer)';
  end if;
end
$c$;

insert into pg_temp._z_out(passo, linha) select '0 md5 novos', (select md5(prosrc) from pg_proc where oid = 'dados.grupo_foto_processar(bigint,text)'::regprocedure) || ' / ' || (select md5(prosrc) from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure);

-- (1) foto com dois subgrupos (grupo e números fictícios)
do $t$
declare v_g uuid; v_f bigint;
begin
  insert into dados.dashboards select (jsonb_populate_record(d, jsonb_build_object('chave', 'ensaio-base-z', 'ativo', false))).*
    from dados.dashboards d where d.chave = 'black-friday-2026-10';
  insert into dados.dashboard_grupos (chave, sendflow_campanha, papel) values ('ensaio-base-z', 'Ensaio Z', 'lista') returning id into v_g;
  insert into dados.grupo_fotos (grupo_id, etapa) values (v_g, 'baixar') returning id into v_f;
  perform dados.grupo_foto_processar(v_f, 'Posição;Grupo;Nome;Número;Saiu' || chr(10) || '1;Z #1;A;5511900000001;Não;' || chr(10) || '2;Z #2;B;5511900000002;Não;');
  insert into dados.grupo_fotos (grupo_id, etapa) values (v_g, 'baixar') returning id into v_f;
  perform dados.grupo_foto_processar(v_f, 'Posição;Grupo;Nome;Número;Saiu' || chr(10) || '1;Z #2;B;5511900000002;Não;');
  insert into dados.grupo_fotos (grupo_id, etapa) values (v_g, 'baixar') returning id into v_f;
  perform dados.grupo_foto_processar(v_f, 'Posição;Grupo;Nome;Número;Saiu' || chr(10) || '1;Z #2;C;5511900000003;Não;');
  insert into pg_temp._z_out(passo, linha)
  select '1 foto ' || p.fone8, case when p.no_grupo then 'no_grupo' else 'saiu' end
    from dados.grupo_participantes p where p.grupo_id = v_g order by p.fone8;
end
$t$;

-- (2) portas
do $t$
declare r jsonb; t0 timestamptz; v_master text; l text; s text;
begin
  select m.perfil_id::text into v_master from acesso.master m join public.perfis p on p.id = m.perfil_id
   where p.status = 'ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1;
  -- membro da equipe (não master)
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  r := public.dados_black_listas_resumo('black-friday-2026-10');
  insert into pg_temp._z_out(passo, linha) values ('2 membro resumo', 'ok, ' || (r->>'pessoas') || ' pessoas');
  begin
    perform public.dados_black_lista('black-friday-2026-10', 'live_consultoria', 'geral', 'ver');
    insert into pg_temp._z_out(passo, linha) values ('2 membro lista', case when acesso.tem('contato.ver') then 'tem contato.ver: leu' else 'PASSOU (ERRO)' end);
  exception when others then insert into pg_temp._z_out(passo, linha) values ('2 membro lista', sqlstate); end;
  begin
    perform dados.black_base_pessoas();
    insert into pg_temp._z_out(passo, linha) values ('2 base direto', 'PASSOU (ERRO)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('2 base direto', sqlstate); end;
  reset role;
  -- master
  perform set_config('request.jwt.claims', json_build_object('sub', v_master, 'role', 'authenticated')::text, true);
  set local statement_timeout = '8s';
  set local role authenticated;
  t0 := clock_timestamp();
  r := public.dados_black_listas_resumo('black-friday-2026-10');
  insert into pg_temp._z_out(passo, linha) values ('3 resumo ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int::text);
  insert into pg_temp._z_out(passo, linha) values ('3 resumo', jsonb_build_object('pessoas', r->'pessoas', 'turma_especial', r->'turma_especial', 'ultimo_dado_em', r->'ultimo_dado_em')::text);
  insert into pg_temp._z_out(passo, linha) select '3 ' || k, v::text from jsonb_each(r->'listas') e(k, v);
  t0 := clock_timestamp();
  r := public.dados_black_lista('black-friday-2026-10', 'fora_grupo', 'advogado', 'baixar');
  insert into pg_temp._z_out(passo, linha) values ('3 lista ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int::text);
  insert into pg_temp._z_out(passo, linha) values ('3 chaves da linha', (select string_agg(k, ',' order by k) from jsonb_object_keys(r->'linhas'->0) k));
  r := public.dados_black_lista('black-friday-2026-10', 'sairam_grupo', 'geral', 'ver');
  insert into pg_temp._z_out(passo, linha)
  select '3 sairam por grupo', 'black ' || count(*) filter (where e->>'grupo_black' = 'saiu') || ', consultoria ' || count(*) filter (where e->>'grupo_consultoria' = 'saiu')
    from jsonb_array_elements(r->'linhas') e;
  foreach l in array array['live_consultoria:advogado', 'xx:geral', 'fora_grupo:yy', 'fora_grupo:geral:zz'] loop
    begin
      perform public.dados_black_lista('black-friday-2026-10', split_part(l, ':', 1), split_part(l, ':', 2), coalesce(nullif(split_part(l, ':', 3), ''), 'ver'));
      insert into pg_temp._z_out(passo, linha) values ('3 invalido ' || l, 'PASSOU (ERRO)');
    exception when others then insert into pg_temp._z_out(passo, linha) values ('3 invalido ' || l, sqlstate); end;
  end loop;
  begin
    perform public.dados_black_lista('atm-elaine-1-2026-10', 'fora_grupo', 'geral', 'ver');
    insert into pg_temp._z_out(passo, linha) values ('3 outra chave', 'PASSOU (ERRO)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('3 outra chave', sqlstate); end;
  reset role;
  -- fora da equipe e anon
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000000abcd","role":"authenticated"}', true);
  set local role authenticated;
  begin
    perform public.dados_black_listas_resumo('black-friday-2026-10');
    insert into pg_temp._z_out(passo, linha) values ('2 fora da equipe resumo', 'PASSOU (ERRO)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('2 fora da equipe resumo', sqlstate); end;
  reset role;
  set local role anon;
  begin
    perform public.dados_black_lista('black-friday-2026-10', 'fora_grupo', 'geral', 'ver');
    insert into pg_temp._z_out(passo, linha) values ('2 anon lista', 'PASSOU (ERRO)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('2 anon lista', sqlstate); end;
  begin
    perform public.dados_black_listas_resumo('black-friday-2026-10');
    insert into pg_temp._z_out(passo, linha) values ('2 anon resumo', 'PASSOU (ERRO)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('2 anon resumo', sqlstate); end;
  reset role;
  insert into pg_temp._z_out(passo, linha)
  select '2 log', string_agg(acao || ' ' || lista || ':' || segmento || ' linhas ' || linhas || ' fora ' || linhas_fora_padrao || ' email? ' || (perfil_email is not null), ' | ' order by id)
    from dados.black_lista_downloads;
end
$t$;

-- (4) Turma Especial
do $t$
declare a int; b int; m1 int; m2 int; r jsonb;
begin
  r := dados.black_base_pessoas();
  a := (r->'resumo'->>'pessoas')::int;
  m1 := (dados.black_lista_disparo_montar()->'resumo'->>'pessoas')::int;
  insert into dados.turma_especial_chaves (tipo, hash)
  select 'email', encode(extensions.digest(p->>'email', 'sha256'), 'hex')
    from jsonb_array_elements(r->'pessoas') p where p->>'email' is not null limit 1;
  r := dados.black_base_pessoas();
  b := (r->'resumo'->>'pessoas')::int;
  m2 := (dados.black_lista_disparo_montar()->'resumo'->>'pessoas')::int;
  insert into pg_temp._z_out(passo, linha) values ('4 turma especial base', 'antes ' || a || ', depois ' || b || ', removidos ' || (r->'resumo'->>'pessoas_turma_especial'));
  insert into pg_temp._z_out(passo, linha) values ('4 turma especial planilha', 'antes ' || m1 || ', depois ' || m2);
end
$t$;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
