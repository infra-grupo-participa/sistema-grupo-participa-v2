-- Ensaio de 20261012234606 (transação desfeita). A (20261012231649) e C (20261012233334) aplicadas. REPEATABLE READ: dado novo chegando não muda o md5.
-- Números do ATM e da Clínica antes e depois (md5), contagens por página, grupo com e sem recorte, travas de acesso,
-- marcar/desmarcar na Black e no ATM (vai e volta), reversão no fim. Só contagens: nenhum dado pessoal sai do ensaio.
begin transaction isolation level repeatable read;
create temp table _z_out (em bigserial, passo text, linha text) on commit drop;
grant all on pg_temp._z_out to authenticated, anon; grant all on sequence pg_temp._z_out_em_seq to authenticated, anon;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '1 antes md5 atm_resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '1 antes md5 atm_leads', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '1 antes md5 atm_grupo_numeros', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '1 antes md5 atm testes', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '1 antes md5 clinica resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_presencial_resumo('clinica-miami-2026-12') x)::text);
reset role;
select set_config('request.jwt.claims', '{}', true);

-- ===== MIGRATION =====
-- 20261012234606: leads da Black (5 páginas), perfil sem dado pessoal, ingresso no grupo por campanha, marcar teste na Black
--
-- STATUS: ver 20261012234606.explain.md.
-- POR QUE: pedido do Victor (13/10/2026), via Maestro. O dashboard da Black lê do banco os leads das 5 páginas, o perfil, os
--   MQLs e o ingresso nos 3 grupos do WhatsApp, com o dado sujo marcado como "a corrigir" (sem alterar a fonte).
--   Depende da A (20261012231649, aplicada; e da C 20261012233334 (arquivo 20261013120000), aplicada antes: linha da Black em dados.dashboards e dados.black_cadastro).
-- O QUE FAZ:
--   1. dados.black_leads (view, security_invoker, sem leitura para anon/authenticated): uma linha por envio, desde
--      04/10/2026 00:00 -03, das 5 páginas: captação (metodo.pesquisa_respostas origem metodo-perfeito), fluxograma (mesma
--      tabela, origem fluxograma-holding-familiar), consultoria (metodo.consultoria_aplicacoes origem consultoria-ao-vivo),
--      checkup (rede.diagnosticos) e futurômetro (rede.futurometros). Profissão exata da fonte e a classe derivada pelo texto
--      exato ('Advogado(a)', 'Contador(a)', 'Estudante de Direito'; outro texto = outros; vazio = sem profissão).
--   2. dados.black_pertence: o "aparece neste evento" da Black (leads ou grupo), para o marcar teste.
--   3. dados_marcar_teste / dados_desmarcar_teste / dados_testes: um ramo por modelo. Chave de modelo jornada-captacao vai
--      para dados.black_cadastro + dados.black_pertence; qualquer outra segue exatamente o caminho de antes (atm_cadastro +
--      atm_pertence). Mesma tabela dados.marcacoes_teste, sem mecanismo novo.
--   4. public.dados_black_perfil: uma linha por envio no período, sem nome, e-mail nem telefone (pessoa_id = md5 com sal
--      sorteado a cada chamada: agrupa a pessoa dentro da resposta, não vale entre chamadas nem volta ao telefone).
--   5. public.dados_black_leads: nome, e-mail e telefone de até 500 lead_id (a gaveta da tela).
--   6. public.dados_black_grupo: pessoas ÚNICAS por telefone (8 últimos dígitos) que entraram em cada grupo no período,
--      pelo evento do webhook (crm.evento_jornada) e, para quem o webhook perdeu, pela 1ª vez visto na foto
--      (dados.grupo_participantes). Leads únicos por classe de profissão. Com recorte {tipo, valor} (porta/isca/campanha/
--      conjunto/anúncio): leads do recorte e unicos_cruzados (lead do recorte cujo telefone entrou no grupo).
--   7. dados.dashboard_grupos: as 3 campanhas da Black, nome, release e contas conferidos no SendFlow em 13/10/2026.
--      sendflow_conta_id NULL: cada campanha usa 3 contas e a foto exporta sem accountId (cobre as 3).
--   8. Testes conhecidos da auditoria de 12/10 marcados por e-mail (10 e-mails hoje; @advmais.com = equipe).
-- AS 5 PERGUNTAS: escala: ~190 envios hoje (5 tabelas pequenas), até ~25 mil na Black inteira; 3 linhas em dashboard_grupos;
--   índice: as 5 fontes são lidas inteiras com filtro de data (pequenas); evento_jornada filtrada por fonte+tag (130 linhas
--   sendflow hoje); frequência: abertura do dashboard e o cron da foto (3 exports a cada ~9 min, mesmo cron do ATM);
--   repetição: create or replace + insert on conflict do nothing (idempotente); reversão: 20261012234606_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if not exists (select 1 from dados.dashboards where chave = 'black-friday-2026-10' and modelo = 'jornada-captacao') then
    raise exception '20261012234606: a migration A (20261012231649) não está aplicada.';
  end if;
  if to_regprocedure('dados.black_cadastro(text)') is null then
    raise exception '20261012234606: dados.black_cadastro não existe (aplicar a A antes).';
  end if;
  -- corpos vivos que esta migration reescreve ou usa: se mudaram, reler antes
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '2632356addaa503a8c1e6415ab6cb06d'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '99ed0ca0dc9c1268b2be18c9c055b84b'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_testes(text)'::regprocedure) <> '15cc20af1d1593c869a1787908406d64'
     or (select md5(prosrc) from pg_proc where oid = 'dados.atm_pertence(text,text,text)'::regprocedure) <> '7945be0a410031528e24bd21a4c876ca'
     or (select md5(prosrc) from pg_proc where oid = 'dados.teste_ativo(text,text,text)'::regprocedure) <> '62b892dac3581cfcc08f8b2ec04582f2'
     or (select md5(prosrc) from pg_proc where oid = 'controle.fone_key(text)'::regprocedure) <> '8ae6c891be75f0b128fcb8bb09f36f12' then
    raise exception '20261012234606: corpo vivo de função de teste ou fone_key mudou. Reler.';
  end if;
  if exists (select 1 from dados.dashboard_grupos
              where sendflow_release_id in ('D94OTzpfoK13WeiM3IcM', 'ZHCd0RrBGYkUBXAi53FN', 'CiHdZJsQn06SYzGPMhMH')
                and chave <> 'black-friday-2026-10') then
    raise exception '20261012234606: release da Black já ligado a outra chave. Reler.';
  end if;
end
$g$;

-- 1. leads da Black, uma linha por envio
create or replace view dados.black_leads with (security_invoker = true) as
with b as (
  select 'captacao'::text as pagina, r.id::text as id_fonte, r.criado_em, r.nome, r.email, r.whatsapp, r.profissao,
         r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
         jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal,
           'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding)) as campos
    from metodo.pesquisa_respostas r
   where r.origem = 'metodo-perfeito' and r.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'fluxograma', r.id::text, r.criado_em, r.nome, r.email, r.whatsapp, r.profissao,
         r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
         jsonb_strip_nulls(jsonb_build_object('atuacao', r.atuacao, 'faixa_etaria', r.faixa_etaria, 'renda_mensal', r.renda_mensal,
           'aluno', r.aluno, 'aluno_programa', r.aluno_programa, 'holding', r.holding))
    from metodo.pesquisa_respostas r
   where r.origem = 'fluxograma-holding-familiar' and r.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'consultoria', c.id::text, c.criado_em, c.nome, c.email, c.whatsapp, c.profissao,
         c.utm_source, c.utm_medium, c.utm_campaign, c.utm_content, c.utm_term,
         jsonb_strip_nulls(jsonb_build_object('cursos', to_jsonb(c.cursos), 'momento', c.momento, 'dificuldade', c.dificuldade,
           'quer_levar_caso', c.quer_levar_caso, 'participa_camera', c.participa_camera, 'nota_indicacao', c.nota_indicacao))
    from metodo.consultoria_aplicacoes c
   where c.origem = 'consultoria-ao-vivo' and c.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'checkup', g.id::text, g.criado_em, g.nome, g.email, g.whatsapp, g.profissao,
         g.utm_source, g.utm_medium, g.utm_campaign, g.utm_content, g.utm_term,
         jsonb_strip_nulls(jsonb_build_object('faixa', g.faixa, 'pontos_total', g.pontos_total, 'mql_fonte', g.mql))
    from rede.diagnosticos g
   where g.criado_em >= timestamptz '2026-10-04 00:00:00-03'
  union all
  select 'futurometro', f.id::text, f.criado_em, f.nome, f.email, f.whatsapp, f.profissao,
         f.utm_source, f.utm_medium, f.utm_campaign, f.utm_content, f.utm_term,
         jsonb_strip_nulls(jsonb_build_object('casos_ativos', f.casos_ativos, 'satisfeito', f.satisfeito))
    from rede.futurometros f
   where f.criado_em >= timestamptz '2026-10-04 00:00:00-03'
), n as (
  select b.*,
         nullif(lower(btrim(b.email)), '') as email_norm,
         controle.fone_key(b.whatsapp) as fk,
         nullif(btrim(b.profissao), '') as prof,
         nullif(btrim(b.utm_source), '') as us, nullif(btrim(b.utm_medium), '') as um, nullif(btrim(b.utm_campaign), '') as uc,
         nullif(btrim(b.utm_content), '') as ut, nullif(btrim(b.utm_term), '') as ue
    from b
)
select n.pagina || ':' || n.id_fonte as lead_id,
       n.pagina, n.id_fonte, n.criado_em, n.nome, n.email_norm as email, n.whatsapp,
       n.profissao,
       case when n.prof is null then null
            when n.prof = 'Advogado(a)' then 'advogado'
            when n.prof = 'Contador(a)' then 'contador'
            when n.prof = 'Estudante de Direito' then 'estudante_direito'
            else 'outros' end as profissao_classe,
       coalesce(n.prof in ('Advogado(a)', 'Contador(a)', 'Estudante de Direito'), false) as mql,
       n.utm_source, n.utm_medium, n.utm_campaign, n.utm_content, n.utm_term,
       -- padrão Meta dos anúncios (auditoria 12/10): utm_campaign = nome|id, utm_medium = conjunto|id, utm_content = anúncio|id
       substring(n.uc from '\|([0-9]+)$') as campanha_id,
       substring(n.um from '\|([0-9]+)$') as conjunto_id,
       substring(n.ut from '\|([0-9]+)$') as anuncio_id,
       case when n.pagina = 'captacao' then 'inscricao_direta' when n.pagina = 'consultoria' then 'consultoria' else 'isca' end as porta,
       case n.pagina when 'fluxograma' then 'Fluxograma' when 'checkup' then 'Checkup' when 'futurometro' then 'Futurômetro' end as isca,
       case when lower(n.us) in ('fb', 'facebook', 'ig', 'instagram', 'meta') then 'meta'
            when lower(n.us) in ('google', 'googleads', 'google_ads') then 'google' end as canal,
       n.fk as fone_key,
       right(n.fk, 8) as fone8,
       left(n.fk, 2) as ddd,
       case when n.fk is null then null else coalesce((select u.uf from dados.ddd_uf u where u.ddd = left(n.fk, 2)), 'Outros') end as uf,
       coalesce('f:' || right(n.fk, 8), 'e:' || n.email_norm, 'l:' || n.pagina || ':' || n.id_fonte) as pessoa_chave,
       dados.teste_ativo('black-friday-2026-10', n.email_norm, n.whatsapp) as teste,
       -- heurística da auditoria de 12/10 (só sinaliza; quem tira do número é a marcação)
       coalesce(n.email_norm like '%teste%' or n.nome ilike '%teste%' or n.email_norm like '%@advmais.com%', false) as parece_teste,
       array_remove(array[
         case when n.prof is null then 'profissao_vazia' end,
         case when n.us is null and n.um is null and n.uc is null and n.ut is null and n.ue is null then 'sem_utm' end,
         case when not (n.us is null and n.um is null and n.uc is null and n.ut is null and n.ue is null)
               and n.uc is distinct from 'black-friday-2026-10'
               and not (lower(coalesce(n.us, '')) in ('fb', 'facebook', 'ig', 'instagram', 'meta') and n.uc ~ '\|[0-9]+$')
              then 'utm_campaign_fora_do_padrao' end
       ], null) as a_corrigir,
       n.campos
  from n;

revoke all on dados.black_leads from public, anon, authenticated, service_role;
comment on view dados.black_leads is
  '20261012234606: leads da Black (5 páginas) desde 04/10/2026, uma linha por envio. Dado pessoal: só pelas RPCs dados_black_*.';

-- 2a. trava da chave: o modelo jornada-captacao é genérico, mas estes dados (view, marcações) são só da Black
create or replace function dados.black_evento(p_chave text)
 returns dados.dashboards
 language plpgsql
 stable
 set search_path to ''
as $function$
declare d dados.dashboards := dados.black_cadastro(p_chave);   -- 42501 sem acesso, P0002 fora do cadastro ou outro modelo
begin
  -- 20261012234606 (pentester): outra chave do mesmo modelo não lê nem marca a Black
  if d.chave is distinct from 'black-friday-2026-10' then
    raise exception 'dashboard não cadastrado' using errcode = 'P0002';
  end if;
  return d;
end
$function$;
revoke all on function dados.black_evento(text) from public, anon, authenticated, service_role;

-- 2. pertence (para o marcar teste)
create or replace function dados.black_pertence(p_chave text, p_tipo text, p_valor text)
 returns boolean
 language sql
 stable
 set search_path to ''
as $function$
  -- 20261012234606
  select p_chave = 'black-friday-2026-10' and case p_tipo
    when 'email' then exists (select 1 from dados.black_leads l where l.email = p_valor)
    when 'fone' then
         exists (select 1 from dados.black_leads l where l.fone8 = p_valor)
      or exists (select 1 from dados.v_grupo_pessoas_todos e where e.chave = p_chave and e.fone8 = p_valor)
    else false end
$function$;
revoke all on function dados.black_pertence(text, text, text) from public, anon, authenticated, service_role;

-- 3. marcar teste: um ramo por modelo. Fora de jornada-captacao, o caminho é o de antes, linha a linha.
create or replace function public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  v_black boolean := exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao');
  d dados.dashboards := case when v_black then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not (case when v_black then dados.black_pertence(d.chave, 'email', v_email)
                                       else dados.atm_pertence(d.chave, 'email', v_email) end) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not (case when v_black then dados.black_pertence(d.chave, 'fone', right(v_fk, 8))
                                    else dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) end) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$function$;

create or replace function public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$function$;

create or replace function public.dados_testes(p_chave text)
 returns table(id bigint, tipo text, valor text, motivo text, marcado_por_email text, marcado_em timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  -- 20261012234606: ramo da Black (jornada-captacao); os outros modelos seguem por atm_cadastro, como antes
  d dados.dashboards := case when exists (select 1 from dados.dashboards x where x.chave = p_chave and x.modelo = 'jornada-captacao')
                             then dados.black_evento(p_chave) else dados.atm_cadastro(p_chave) end;
begin
  return query
  select m.id, m.tipo, m.valor, m.motivo, m.marcado_por_email, m.marcado_em
    from dados.marcacoes_teste m
   where m.chave = d.chave and m.desmarcado_em is null
   order by m.marcado_em desc, m.id desc;
end
$function$;

-- grants de antes (create or replace mantém; reafirmados)
revoke all on function public.dados_marcar_teste(text, text, text, text) from public, anon;
revoke all on function public.dados_desmarcar_teste(text, text, text) from public, anon;
revoke all on function public.dados_testes(text) from public, anon;
grant execute on function public.dados_marcar_teste(text, text, text, text) to authenticated;
grant execute on function public.dados_desmarcar_teste(text, text, text) to authenticated;
grant execute on function public.dados_testes(text) to authenticated;

-- recorte opcional (contrato com a tela, 13/10): {"tipo": porta|isca|campanha|conjunto|anuncio, "valor": texto}
--   porta: inscricao_direta | consultoria | isca; isca: Fluxograma | Checkup | Futurômetro; campanha/conjunto/anuncio: id do Meta
create or replace function dados.black_no_recorte(p_recorte jsonb, p_porta text, p_isca text,
                                                  p_campanha_id text, p_conjunto_id text, p_anuncio_id text)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  -- 20261012234606
  select p_recorte is null
      or (p_recorte ->> 'valor') = case p_recorte ->> 'tipo'
           when 'porta' then p_porta when 'isca' then p_isca when 'campanha' then p_campanha_id
           when 'conjunto' then p_conjunto_id when 'anuncio' then p_anuncio_id end
$function$;
revoke all on function dados.black_no_recorte(jsonb, text, text, text, text, text) from public, anon, authenticated, service_role;

create or replace function dados.black_recorte_valido(p_recorte jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
begin
  -- 20261012234606: null, {} e jsonb null = sem recorte
  if p_recorte is null or p_recorte = '{}'::jsonb or jsonb_typeof(p_recorte) = 'null' then return null; end if;
  if jsonb_typeof(p_recorte) <> 'object'
     or exists (select 1 from jsonb_object_keys(p_recorte) k where k not in ('tipo', 'valor'))
     or jsonb_typeof(p_recorte -> 'tipo') is distinct from 'string'
     or jsonb_typeof(p_recorte -> 'valor') is distinct from 'string'
     or p_recorte ->> 'tipo' not in ('porta', 'isca', 'campanha', 'conjunto', 'anuncio')
     or length(p_recorte ->> 'valor') not between 1 and 200 then
    raise exception 'recorte inválido: {"tipo": porta|isca|campanha|conjunto|anuncio, "valor": texto}' using errcode = '22023';
  end if;
  return p_recorte;
end
$function$;
revoke all on function dados.black_recorte_valido(jsonb) from public, anon, authenticated, service_role;

-- 4. perfil (sem dado pessoal)
create or replace function public.dados_black_perfil(p_chave text, p_de date default null, p_ate date default null,
                                                     p_incluir_teste boolean default false)
 returns table(lead_id text, pessoa_id text, criado_em timestamptz, primeira_porta boolean, pagina text, porta text, isca text,
               campanha_id text, conjunto_id text, anuncio_id text, canal text,
               utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text,
               profissao text, profissao_bruta text, mql boolean, uf text,
               entrou_grupo_em timestamptz, entrada_grupo_aproximada boolean,
               teste boolean, parece_teste boolean, a_corrigir text[], campos jsonb)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.black_evento(p_chave);   -- 42501 sem acesso, P0002 fora do cadastro ou outro modelo
  v_de timestamptz := (coalesce(p_de, d.periodo_inicio)::timestamp at time zone 'America/Sao_Paulo');
  v_ate timestamptz := ((coalesce(p_ate, (now() at time zone 'America/Sao_Paulo')::date) + 1)::timestamp at time zone 'America/Sao_Paulo');
  v_sal text := gen_random_uuid()::text;   -- pessoa_id só vale dentro desta resposta
begin
  return query
  with l as (
    select l.*, dados.teste_ativo(d.chave, l.email, l.whatsapp) as t,
           row_number() over (partition by l.pessoa_chave order by l.criado_em, l.lead_id) = 1 as primeira
      from dados.black_leads l
  ), g as (
    select e.fone8, min(e.entrou_em) as entrou_em, bool_or(e.entrada_aproximada) filter (where e.entrou_em is not null) as aprox
      from dados.v_grupo_pessoas_todos e
     where e.chave = d.chave
     group by e.fone8
  )
  select l.lead_id, md5(v_sal || l.pessoa_chave), l.criado_em, l.primeira, l.pagina, l.porta, l.isca,
         l.campanha_id, l.conjunto_id, l.anuncio_id, l.canal,
         l.utm_source, l.utm_medium, l.utm_campaign, l.utm_content, l.utm_term,
         l.profissao_classe, l.profissao, l.mql, l.uf,
         g.entrou_em, g.aprox,
         l.t, l.parece_teste, l.a_corrigir, l.campos
    from l
    left join g on g.fone8 = l.fone8
   where l.criado_em >= v_de and l.criado_em < v_ate
     and (p_incluir_teste or not l.t)
   order by l.criado_em, l.lead_id;
end
$function$;
revoke all on function public.dados_black_perfil(text, date, date, boolean) from public, anon, service_role;
grant execute on function public.dados_black_perfil(text, date, date, boolean) to authenticated;

-- 5. detalhe com dado pessoal, só por lead_id
create or replace function public.dados_black_leads(p_chave text, p_lead_ids text[])
 returns table(lead_id text, nome text, email text, telefone text)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.black_evento(p_chave);
begin
  if p_lead_ids is null or cardinality(p_lead_ids) = 0 then return; end if;
  if cardinality(p_lead_ids) > 500 then
    raise exception 'no máximo 500 leads por chamada' using errcode = '22023';
  end if;
  return query
  select l.lead_id, l.nome, l.email, l.whatsapp
    from dados.black_leads l
   where l.lead_id = any (p_lead_ids)
   order by l.criado_em, l.lead_id;
end
$function$;
revoke all on function public.dados_black_leads(text, text[]) from public, anon, service_role;
grant execute on function public.dados_black_leads(text, text[]) to authenticated;

-- 6. ingresso no grupo: únicos por telefone por campanha, leads únicos por classe, cruzamento com recorte
create or replace function public.dados_black_grupo(p_chave text, p_de date default null, p_ate date default null,
                                                    p_incluir_teste boolean default false, p_recorte jsonb default null)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
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
  ), tst as (
    select m.valor as fone8 from dados.marcacoes_teste m
     where m.chave = d.chave and m.desmarcado_em is null and m.tipo = 'fone'
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

-- 7. as 3 campanhas da Black (lidas do SendFlow em 13/10/2026: nome exato, release; 3 contas cada, conta NULL)
insert into dados.dashboard_grupos (chave, sendflow_campanha, sendflow_release_id, sendflow_conta_id) values
  ('black-friday-2026-10', 'BF26 - Live 03/11 - Advogados', 'D94OTzpfoK13WeiM3IcM', null),
  ('black-friday-2026-10', 'BF26 - Live 03/11 - Contadores', 'ZHCd0RrBGYkUBXAi53FN', null),
  ('black-friday-2026-10', 'BF26 - Live 03/11 - Outros', 'CiHdZJsQn06SYzGPMhMH', null)
on conflict (chave, sendflow_campanha) do nothing;

-- 8. testes conhecidos (auditoria de 12/10: e-mail ou nome com "teste", ou e-mail @advmais.com)
insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
select distinct 'black-friday-2026-10', 'email', l.email,
       case when l.email like '%@advmais.com%' then 'equipe' else 'teste' end,
       null::uuid, 'migration 20261012234606 (auditoria 12/10)'
  from dados.black_leads l
 where l.parece_teste and l.email like '%@%'
on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;

do $c$
begin
  if (select count(*) from dados.dashboard_grupos where chave = 'black-friday-2026-10') <> 3 then
    raise exception '20261012234606: dashboard_grupos da Black não tem 3 linhas';
  end if;
  if has_table_privilege('anon', 'dados.black_leads', 'select') or has_table_privilege('authenticated', 'dados.black_leads', 'select') then
    raise exception '20261012234606: black_leads legível por anon/authenticated';
  end if;
  if not has_function_privilege('authenticated', 'public.dados_black_perfil(text,date,date,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_black_leads(text,text[])', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_black_grupo(text,date,date,boolean,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.dados_black_perfil(text,date,date,boolean)', 'execute')
     or has_function_privilege('anon', 'public.dados_black_leads(text,text[])', 'execute')
     or has_function_privilege('anon', 'public.dados_black_grupo(text,date,date,boolean,jsonb)', 'execute')
     or has_function_privilege('anon', 'public.dados_marcar_teste(text,text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.black_pertence(text,text,text)', 'execute')
     or has_function_privilege('authenticated', 'dados.black_no_recorte(jsonb,text,text,text,text,text)', 'execute') then
    raise exception '20261012234606: permissões erradas';
  end if;
end
$c$;

grant select on pg_temp._z_out to authenticated;

-- ===== TESTES =====
insert into pg_temp._z_out (passo, linha) select '3 view por pagina (postgres)', (select jsonb_object_agg(pagina, n) from (select pagina, count(*) n from dados.black_leads group by 1) z)::text;
insert into pg_temp._z_out (passo, linha) select '3 profissao bruta x classe', (select jsonb_agg(jsonb_build_object('p', pagina, 'bruta', profissao, 'classe', profissao_classe, 'n', n) order by pagina, profissao) from (select pagina, profissao, profissao_classe, count(*) n from dados.black_leads group by 1,2,3) z)::text;
insert into pg_temp._z_out (passo, linha) select '3 a_corrigir', (select jsonb_object_agg(k, n) from (select unnest(a_corrigir) k, count(*) n from dados.black_leads group by 1) z)::text;
insert into pg_temp._z_out (passo, linha) select '3 marcados pela migration (motivo)', (select jsonb_object_agg(motivo, n) from (select motivo, count(*) n from dados.marcacoes_teste where chave = 'black-friday-2026-10' and desmarcado_em is null group by 1) z)::text;
insert into pg_temp._z_out (passo, linha) select '3 linhas teste na view por pagina', (select jsonb_object_agg(pagina, n) from (select pagina, count(*) n from dados.black_leads where teste group by 1) z)::text;
insert into pg_temp._z_out (passo, linha) select '3 parece_teste sem marca', (select count(*) from dados.black_leads where parece_teste and not teste)::text;
insert into pg_temp._z_out (passo, linha) select '3 utm por combinacao', (select jsonb_agg(jsonb_build_object('s', utm_source, 'm', utm_medium, 'c', utm_campaign, 'n', n) order by n desc) from (select utm_source, utm_medium, utm_campaign, count(*) n from dados.black_leads group by 1,2,3) z)::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '4 depois md5 atm_resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '4 depois md5 atm_leads', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '4 depois md5 atm_grupo_numeros', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '4 depois md5 atm testes', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '4 depois md5 clinica resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_presencial_resumo('clinica-miami-2026-12') x)::text);
reset role;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
create temp table _z_p on commit drop as select * from public.dados_black_perfil('black-friday-2026-10');
insert into pg_temp._z_out (passo, linha) select '5 perfil sem teste por pagina', (select jsonb_object_agg(pagina, n) from (select pagina, count(*) n from pg_temp._z_p group by 1) z)::text;
insert into pg_temp._z_out (passo, linha) select '5 perfil com teste', (select count(*) from public.dados_black_perfil('black-friday-2026-10', null, null, true))::text;
insert into pg_temp._z_out (passo, linha) select '5 perfil pessoas', jsonb_build_object('linhas', (select count(*) from pg_temp._z_p), 'pessoas', (select count(distinct pessoa_id) from pg_temp._z_p), 'primeiras', (select count(*) from pg_temp._z_p where primeira_porta), 'mql_linhas', (select count(*) from pg_temp._z_p where mql), 'com_grupo', (select count(*) from pg_temp._z_p where entrou_grupo_em is not null))::text;
insert into pg_temp._z_out (passo, linha) select '5 perfil so 12/10', (select count(*) from public.dados_black_perfil('black-friday-2026-10', '2026-10-12', '2026-10-12'))::text;
insert into pg_temp._z_out (passo, linha) select '6 grupo sem recorte', public.dados_black_grupo('black-friday-2026-10')::text;
insert into pg_temp._z_out (passo, linha) select '6 grupo recorte porta inscricao_direta', public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"inscricao_direta"}')::text;
insert into pg_temp._z_out (passo, linha) select '6 grupo recorte vazio = sem recorte', (public.dados_black_grupo('black-friday-2026-10', null, null, false, '{}') = public.dados_black_grupo('black-friday-2026-10'))::text;
insert into pg_temp._z_out (passo, linha) select '7 gaveta 3 leads (so contagem)', (select count(*) from public.dados_black_leads('black-friday-2026-10', (select array_agg(lead_id) from (select lead_id from pg_temp._z_p limit 3) z)))::text;
do $t$ begin perform public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"pagina","valor":"x"}');
  insert into pg_temp._z_out (passo, linha) values ('8 recorte tipo pagina', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 recorte tipo pagina', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_grupo('black-friday-2026-10', null, null, false, '{"tipo":"porta","valor":"isca","x":"1"}');
  insert into pg_temp._z_out (passo, linha) values ('8 recorte chave extra', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 recorte chave extra', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_leads('black-friday-2026-10', array(select g::text from generate_series(1,501) g));
  insert into pg_temp._z_out (passo, linha) values ('8 leads mais de 500', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 leads mais de 500', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_perfil('atm-elaine-1-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('8 chave do ATM no perfil da Black', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 chave do ATM no perfil da Black', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_marcar_teste('clinica-miami-2026-12', 'a@b.c');
  insert into pg_temp._z_out (passo, linha) values ('8 chave da Clinica no marcar teste', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 chave da Clinica no marcar teste', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform (select count(*) from dados.black_leads);
  insert into pg_temp._z_out (passo, linha) values ('8 select direto na view (equipe)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 select direto na view (equipe)', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform dados.black_pertence('black-friday-2026-10','email','a@b.c');
  insert into pg_temp._z_out (passo, linha) values ('8 black_pertence direto (equipe)', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 black_pertence direto (equipe)', sqlstate || ' ' || sqlerrm); end $t$;

reset role;
select set_config('request.jwt.claims', '{}', true);
-- 2ª chave do mesmo modelo (pentester): não pode ler nem marcar a Black
insert into dados.dashboards select (jsonb_populate_record(null::dados.dashboards, to_jsonb(d) || '{"chave":"ensaio-outra-jornada"}')).* from dados.dashboards d where d.chave = 'black-friday-2026-10';
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
do $t$ begin perform public.dados_black_perfil('ensaio-outra-jornada');
  insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada perfil', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada perfil', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_leads('ensaio-outra-jornada', array['captacao:1']);
  insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada leads', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada leads', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_grupo('ensaio-outra-jornada');
  insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada grupo', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada grupo', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_marcar_teste('ensaio-outra-jornada', 'ninguem-ensaio@nao.existe');
  insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada marcar', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada marcar', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_testes('ensaio-outra-jornada');
  insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada testes', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8b outra chave jornada testes', sqlstate || ' ' || sqlerrm); end $t$;

insert into pg_temp._z_out (passo, linha) select '8b pessoa_id muda entre chamadas', ((select min(pessoa_id) from public.dados_black_perfil('black-friday-2026-10') where lead_id = (select min(lead_id) from pg_temp._z_p)) <> (select pessoa_id from pg_temp._z_p where lead_id = (select min(lead_id) from pg_temp._z_p)))::text;
do $t$ begin perform public.dados_marcar_teste('black-friday-2026-10', 'ninguem-ensaio@nao.existe');
  insert into pg_temp._z_out (passo, linha) values ('8 e-mail fora da Black', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('8 e-mail fora da Black', sqlstate || ' ' || sqlerrm); end $t$;

create temp table _z_e on commit drop as select l.email, count(*) n from public.dados_black_leads('black-friday-2026-10', (select array_agg(lead_id) from (select lead_id from pg_temp._z_p order by criado_em desc limit 500) z)) l where l.email is not null group by 1 order by 2 desc, 1 limit 1;
insert into pg_temp._z_out (passo, linha) select '9 black marcar', jsonb_build_object('linhas_da_pessoa', (select n from pg_temp._z_e), 'antes', (select count(*) from pg_temp._z_p), 'marcou', public.dados_marcar_teste('black-friday-2026-10', (select email from pg_temp._z_e)))::text;
insert into pg_temp._z_out (passo, linha) select '9 black depois de marcar', jsonb_build_object('perfil', (select count(*) from public.dados_black_perfil('black-friday-2026-10')), 'na_lista', (select count(*) from public.dados_testes('black-friday-2026-10') t where t.valor = (select email from pg_temp._z_e)))::text;
insert into pg_temp._z_out (passo, linha) select '9 black desmarcar', public.dados_desmarcar_teste('black-friday-2026-10', (select email from pg_temp._z_e))::text;
insert into pg_temp._z_out (passo, linha) select '9 black depois de desmarcar', (select count(*) from public.dados_black_perfil('black-friday-2026-10'))::text;
reset role;
create temp table _z_a on commit drop as select l.email from dados.atm_leads('atm-elaine-1-2026-10') l where l.email is not null and not dados.teste_ativo('atm-elaine-1-2026-10', l.email, null) order by l.email limit 1;
grant select on pg_temp._z_a, pg_temp._z_e to authenticated;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '10 atm leads antes', (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false))::text;
insert into pg_temp._z_out (passo, linha) select '10 atm marcar', public.dados_marcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a))::text;
insert into pg_temp._z_out (passo, linha) select '10 atm leads com a marca', (select count(*) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false))::text;
insert into pg_temp._z_out (passo, linha) select '10 atm desmarcar', public.dados_desmarcar_teste('atm-elaine-1-2026-10', (select email from pg_temp._z_a))::text;
do $t$ begin perform public.dados_marcar_teste('atm-elaine-1-2026-10', 'ninguem-ensaio@nao.existe');
  insert into pg_temp._z_out (passo, linha) values ('10 atm e-mail fora do evento', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('10 atm e-mail fora do evento', sqlstate || ' ' || sqlerrm); end $t$;

reset role;
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '11 depois do vai-e-volta md5 atm_resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '11 depois do vai-e-volta md5 atm_leads', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '11 depois do vai-e-volta md5 atm_grupo_numeros', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '11 depois do vai-e-volta md5 atm testes', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '11 depois do vai-e-volta md5 clinica resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_presencial_resumo('clinica-miami-2026-12') x)::text);
reset role;
select set_config('request.jwt.claims', '{}', true);

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
do $t$ begin perform public.dados_black_perfil('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('12 fora da equipe perfil', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('12 fora da equipe perfil', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_grupo('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('12 fora da equipe grupo', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('12 fora da equipe grupo', sqlstate || ' ' || sqlerrm); end $t$;

reset role;
set local role anon;
do $t$ begin perform public.dados_black_perfil('black-friday-2026-10');
  insert into pg_temp._z_out (passo, linha) values ('12 anon perfil', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('12 anon perfil', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform public.dados_black_leads('black-friday-2026-10', array['captacao:x']);
  insert into pg_temp._z_out (passo, linha) values ('12 anon leads', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('12 anon leads', sqlstate || ' ' || sqlerrm); end $t$;

do $t$ begin perform (select count(*) from dados.black_leads);
  insert into pg_temp._z_out (passo, linha) values ('12 anon view', 'ERRO DO ENSAIO: passou');
exception when others then insert into pg_temp._z_out (passo, linha) values ('12 anon view', sqlstate || ' ' || sqlerrm); end $t$;

reset role;
select set_config('request.jwt.claims', '{}', true);
insert into pg_temp._z_out (passo, linha) select '13 grants', (select string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text,'null'), ' ; ' order by 1) from pg_proc p where p.proname in ('dados_black_perfil','dados_black_leads','dados_black_grupo','black_pertence','black_no_recorte','black_recorte_valido','dados_marcar_teste','dados_desmarcar_teste','dados_testes'));
insert into pg_temp._z_out (passo, linha) select '13 view acl e opcoes', (select coalesce(relacl::text,'null') || ' ' || coalesce(reloptions::text,'') from pg_class where oid = 'dados.black_leads'::regclass);

-- ===== REVERSÃO =====
-- Reversão de 20261012234606. Numa transação. Rodar ANTES da reversão da A (20261012231649).
-- As 3 RPCs de teste voltam ao corpo de antes (só atm_cadastro + atm_pertence, md5 de prosrc conferidos na migration).
-- As marcações de teste da Black e as 3 linhas de dashboard_grupos saem; a foto do grupo da Black (grupo_participantes,
-- FK em dashboard_grupos) sai junto se existir. crm.evento_jornada não é tocada (é a timeline do CRM, tag BF26).

drop function if exists public.dados_black_grupo(text, date, date, boolean, jsonb);
drop function if exists public.dados_black_leads(text, text[]);
drop function if exists public.dados_black_perfil(text, date, date, boolean);
drop function if exists dados.black_recorte_valido(jsonb);
drop function if exists dados.black_no_recorte(jsonb, text, text, text, text, text);

create or replace function public.dados_marcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text, p_motivo text DEFAULT 'teste'::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  v_por uuid := auth.uid();
  v_por_email text := nullif(auth.jwt() ->> 'email', '');
  n int := 0; k int;
begin
  if p_motivo is null or p_motivo not in ('teste', 'equipe') then
    raise exception 'motivo inválido (teste ou equipe)' using errcode = '22023';
  end if;
  if v_email is null and nullif(btrim(p_telefone), '') is null then
    raise exception 'informe e-mail ou telefone' using errcode = '22023';
  end if;
  if v_email is not null and v_email not like '%@%' then
    raise exception 'e-mail inválido' using errcode = '22023';
  end if;
  if nullif(btrim(p_telefone), '') is not null and v_fk is null then
    raise exception 'telefone inválido (precisa de DDD + número)' using errcode = '22023';
  end if;
  if v_email is not null and not dados.atm_pertence(d.chave, 'email', v_email) then
    raise exception 'e-mail não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_fk is not null and not dados.atm_pertence(d.chave, 'fone', right(v_fk, 8)) then
    raise exception 'telefone não aparece neste evento' using errcode = 'P0002';
  end if;
  if v_email is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'email', v_email, p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  if v_fk is not null then
    insert into dados.marcacoes_teste (chave, tipo, valor, motivo, marcado_por, marcado_por_email)
    values (d.chave, 'fone', right(v_fk, 8), p_motivo, v_por, v_por_email)
    on conflict (chave, tipo, valor) where desmarcado_em is null do nothing;
    get diagnostics k = row_count; n := n + k;
  end if;
  return n;
end
$function$;

create or replace function public.dados_desmarcar_teste(p_chave text, p_email text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_email text := nullif(lower(btrim(p_email)), '');
  v_fk text := controle.fone_key(p_telefone);
  n int;
begin
  if v_email is null and v_fk is null then
    raise exception 'informe e-mail ou telefone válido' using errcode = '22023';
  end if;
  update dados.marcacoes_teste m
     set desmarcado_em = now(), desmarcado_por = auth.uid(), desmarcado_por_email = nullif(auth.jwt() ->> 'email', '')
   where m.chave = d.chave and m.desmarcado_em is null
     and ((m.tipo = 'email' and m.valor = v_email) or (m.tipo = 'fone' and m.valor = right(v_fk, 8)));
  get diagnostics n = row_count;
  return n;
end
$function$;

create or replace function public.dados_testes(p_chave text)
 returns table(id bigint, tipo text, valor text, motivo text, marcado_por_email text, marcado_em timestamp with time zone)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
begin
  return query
  select m.id, m.tipo, m.valor, m.motivo, m.marcado_por_email, m.marcado_em
    from dados.marcacoes_teste m
   where m.chave = d.chave and m.desmarcado_em is null
   order by m.marcado_em desc, m.id desc;
end
$function$;

drop function if exists dados.black_pertence(text, text, text);
drop function if exists dados.black_evento(text);
drop view if exists dados.black_leads;

delete from dados.marcacoes_teste where chave = 'black-friday-2026-10';
delete from dados.grupo_participantes p using dados.dashboard_grupos g where g.id = p.grupo_id and g.chave = 'black-friday-2026-10';
delete from dados.dashboard_grupos where chave = 'black-friday-2026-10';

do $c$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.dados_marcar_teste(text,text,text,text)'::regprocedure) <> '2632356addaa503a8c1e6415ab6cb06d'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_desmarcar_teste(text,text,text)'::regprocedure) <> '99ed0ca0dc9c1268b2be18c9c055b84b'
     or (select md5(prosrc) from pg_proc where oid = 'public.dados_testes(text)'::regprocedure) <> '15cc20af1d1593c869a1787908406d64' then
    raise exception 'reversão 20261012234606: corpo das RPCs de teste não voltou ao de antes';
  end if;
end
$c$;

insert into pg_temp._z_out (passo, linha) select '14 depois da reversao', jsonb_build_object('view', to_regclass('dados.black_leads') is null, 'grupos', (select count(*) from dados.dashboard_grupos where chave = 'black-friday-2026-10'), 'marcas', (select count(*) from dados.marcacoes_teste where chave = 'black-friday-2026-10'))::text;
select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated","email":"ensaio@ensaio"}', true);
set local role authenticated;
insert into pg_temp._z_out (passo, linha) select '15 depois da reversao md5 atm_resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_resumo('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '15 depois da reversao md5 atm_leads', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_leads('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '15 depois da reversao md5 atm_grupo_numeros', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_atm_grupo_numeros('atm-elaine-1-2026-10', null, null, false) x)::text);
insert into pg_temp._z_out (passo, linha) select '15 depois da reversao md5 atm testes', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_testes('atm-elaine-1-2026-10') x)::text);
insert into pg_temp._z_out (passo, linha) select '15 depois da reversao md5 clinica resumo', md5((select jsonb_agg(to_jsonb(x) order by to_jsonb(x)::text) from public.dados_presencial_resumo('clinica-miami-2026-12') x)::text);
reset role;
select set_config('request.jwt.claims', '{}', true);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
