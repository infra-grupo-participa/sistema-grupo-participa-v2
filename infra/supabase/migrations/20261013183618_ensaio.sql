-- Ensaio de 20261013183618 (transação desfeita). Só contagens e sqlstate.
-- (1) contagens antes e depois (incompletas fora); (2) religar a marca volta as contagens de antes; (3) planilha igual;
-- (4) membro não master sem contato.ver (Jéssica, antes de receber) recebe 42501 na lista; (5) reversão volta os md5.
begin;
create temp table _z_out (em serial, passo text, linha text);
grant all on pg_temp._z_out to authenticated, anon;
grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
insert into pg_temp._z_out(passo, linha) select '1 antes', (select string_agg(l || ':' || s || '=' || jsonb_array_length(dados.black_lista(b.b, l, s)->'linhas') || '+' || jsonb_array_length(dados.black_lista(b.b, l, s)->'fora_padrao'), ' ' order by l, s)
     from (select dados.black_base_pessoas() b) b,
          (values ('live_consultoria','geral'),('fora_grupo','geral'),('fora_grupo','advogado'),('fora_grupo','contador'),('fora_grupo','outros'),('sairam_grupo','geral'),('sairam_grupo','advogado'),('sairam_grupo','contador'),('sairam_grupo','outros')) t(l, s));
insert into pg_temp._z_out(passo, linha) select '1 antes pessoas/planilha', (dados.black_base_pessoas()->'resumo'->>'pessoas') || ' / ' || (dados.black_lista_disparo_montar()->'resumo'->>'pessoas');
-- 20261013183618: respostas INCOMPLETAS do Respondi da consultoria fora das listas de disparo (por enquanto)
--
-- POR QUE (Victor, 13/10/2026, via Maestro): quem não terminou o formulário JmSmjBBS (108 com contato) "por enquanto não"
-- entra. Sai das 3 listas da Mensageria, do CSV e da planilha. Continua no banco (respondi.respostas, dados.parcial = true).
-- Quem tem outra fonte (grupo, captação, página da consultoria, Respondi concluído) continua por ela; os dados da resposta
-- incompleta (nome, e-mail, telefone) não entram em nada enquanto ela estiver desligada.
--
-- O QUE FAZ
--   a. dados.black_lista_config.incluir_respondi_parcial boolean not null default false.
--      Religar: update dados.black_lista_config set incluir_respondi_parcial = true;
--   b. dados.black_base_pessoas e dados.black_lista_disparo_montar: a resposta incompleta só entra com a marca ligada.
--
-- AS 5 PERGUNTAS
--   escala: mesma da 20261013180931 (menos registros); índice: nenhum novo; frequência: igual;
--   repetição: só leitura; reversão: 20261013183618_reversao.sql (volta os corpos de 20261013180931 e tira a coluna).
-- Ensaio: 20261013183618_ensaio.sql. Detalhe: 20261013183618.explain.md.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_base_pessoas()'::regprocedure) <> '22079ed72e4a73217803d6c21cf4a3b3'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> '9c1a62bb3075748a2f60a2bf1dd0b852' then
    raise exception '20261013183618: corpo vivo mudou desde 20261013180931. Reler.';
  end if;
end
$g$;

alter table dados.black_lista_config add column if not exists incluir_respondi_parcial boolean not null default false;
comment on column dados.black_lista_config.incluir_respondi_parcial is
  'Resposta incompleta do Respondi JmSmjBBS entra nas listas de disparo? false por decisão do Victor (13/10/2026). 20261013183618.';

CREATE OR REPLACE FUNCTION dados.black_base_pessoas()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
     -- 20261013183515: resposta incompleta do Respondi só entra com dados.black_lista_config.incluir_respondi_parcial (decisão do
     -- Victor, 13/10: "por enquanto não"); a pessoa continua se tiver outra fonte
     and (not coalesce((x.dados->>'parcial')::boolean, false)
          or coalesce((select c.incluir_respondi_parcial from dados.black_lista_config c where c.id), false))
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
$function$;

revoke all on function dados.black_base_pessoas() from public, anon, authenticated, service_role;

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
   where x.form_slug = 'JmSmjBBS'
     -- 20261013183515: resposta incompleta do Respondi só entra com dados.black_lista_config.incluir_respondi_parcial (decisão do
     -- Victor, 13/10: "por enquanto não"); a pessoa continua se tiver outra fonte
     and (not coalesce((x.dados->>'parcial')::boolean, false)
          or coalesce((select c.incluir_respondi_parcial from dados.black_lista_config c where c.id), false));

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

do $c$
begin
  if (select proacl::text from pg_proc where oid = 'dados.black_base_pessoas()'::regprocedure) <> '{postgres=X/postgres}'
     or (select proacl::text from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> '{postgres=X/postgres}'
     or (select incluir_respondi_parcial from dados.black_lista_config where id) is distinct from false then
    raise exception '20261013183618: conferência final falhou';
  end if;
end
$c$;

insert into pg_temp._z_out(passo, linha) select '2 depois', (select string_agg(l || ':' || s || '=' || jsonb_array_length(dados.black_lista(b.b, l, s)->'linhas') || '+' || jsonb_array_length(dados.black_lista(b.b, l, s)->'fora_padrao'), ' ' order by l, s)
     from (select dados.black_base_pessoas() b) b,
          (values ('live_consultoria','geral'),('fora_grupo','geral'),('fora_grupo','advogado'),('fora_grupo','contador'),('fora_grupo','outros'),('sairam_grupo','geral'),('sairam_grupo','advogado'),('sairam_grupo','contador'),('sairam_grupo','outros')) t(l, s));
insert into pg_temp._z_out(passo, linha) select '2 depois pessoas/planilha', (dados.black_base_pessoas()->'resumo'->>'pessoas') || ' / ' || (dados.black_lista_disparo_montar()->'resumo'->>'pessoas');
insert into pg_temp._z_out(passo, linha) select '2 respondi pessoas', dados.black_base_pessoas()->'resumo'->'pessoas_por_fonte'->>'respondi_consultoria';
update dados.black_lista_config set incluir_respondi_parcial = true;
insert into pg_temp._z_out(passo, linha) select '3 religada', (select string_agg(l || ':' || s || '=' || jsonb_array_length(dados.black_lista(b.b, l, s)->'linhas') || '+' || jsonb_array_length(dados.black_lista(b.b, l, s)->'fora_padrao'), ' ' order by l, s)
     from (select dados.black_base_pessoas() b) b,
          (values ('live_consultoria','geral'),('fora_grupo','geral'),('fora_grupo','advogado'),('fora_grupo','contador'),('fora_grupo','outros'),('sairam_grupo','geral'),('sairam_grupo','advogado'),('sairam_grupo','contador'),('sairam_grupo','outros')) t(l, s));
update dados.black_lista_config set incluir_respondi_parcial = false;
select set_config('request.jwt.claims', '{"sub":"012bbcd3-cade-4889-a6ff-4804ed15c36d","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin
  insert into pg_temp._z_out(passo, linha) values ('4 jessica resumo', (public.dados_black_listas_resumo('black-friday-2026-10')->>'pessoas'));
  begin
    perform public.dados_black_lista('black-friday-2026-10', 'fora_grupo', 'geral', 'ver');
    insert into pg_temp._z_out(passo, linha) values ('4 jessica lista sem contato.ver', 'PASSOU (ERRO)');
  exception when others then insert into pg_temp._z_out(passo, linha) values ('4 jessica lista sem contato.ver', sqlstate); end;
end $t$;
reset role;
-- Reversão de 20261013183618: volta dados.black_base_pessoas (md5 22079ed7…) e dados.black_lista_disparo_montar (9c1a62bb…)
-- aos corpos de 20261013180931 (as incompletas voltam às listas) e tira a coluna incluir_respondi_parcial.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

CREATE OR REPLACE FUNCTION dados.black_base_pessoas()
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
$function$;

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

revoke all on function dados.black_base_pessoas() from public, anon, authenticated, service_role;
revoke all on function dados.black_lista_disparo_montar() from public, anon, authenticated, service_role;
alter table dados.black_lista_config drop column if exists incluir_respondi_parcial;

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_base_pessoas()'::regprocedure) <> '22079ed72e4a73217803d6c21cf4a3b3'
     or (select md5(prosrc) from pg_proc where oid = 'dados.black_lista_disparo_montar()'::regprocedure) <> '9c1a62bb3075748a2f60a2bf1dd0b852' then
    raise exception 'reversão 20261013183618: corpo não voltou ao de antes';
  end if;
end
$c$;

insert into pg_temp._z_out(passo, linha) select '5 revertida', (select string_agg(l || ':' || s || '=' || jsonb_array_length(dados.black_lista(b.b, l, s)->'linhas') || '+' || jsonb_array_length(dados.black_lista(b.b, l, s)->'fora_padrao'), ' ' order by l, s)
     from (select dados.black_base_pessoas() b) b,
          (values ('live_consultoria','geral'),('fora_grupo','geral'),('fora_grupo','advogado'),('fora_grupo','contador'),('fora_grupo','outros'),('sairam_grupo','geral'),('sairam_grupo','advogado'),('sairam_grupo','contador'),('sairam_grupo','outros')) t(l, s));
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
