-- 20261013140000: dashboard da Black. (1) o recorte de ANÚNCIO aceita vários ids do Meta (criativo = anúncios de mesmo nome);
-- (2) utm_source=metaads passa a valer como canal Meta. Numa transação (o arquivo não abre nem fecha uma).
-- NÃO APLICADA. Escrita em 13/10/2026 (UTC) na branch victor-black-funil-mql-grupo; só o Victor/João aplicam.
-- Não muda tabela nem dado, só 2 funções internas e 1 view (sem leitura para anon/authenticated).
set local lock_timeout = '5s';

-- guarda: as duas funções precisam estar como a migration 20261012234606 deixou (senão alguém mudou depois)
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_no_recorte(jsonb,text,text,text,text,text)'::regprocedure) <> '1cdc422828e0988e16c95de78c87e052' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_no_recorte não é o gravado por 20261012234606 (md5 1cdc4228…). Reler antes de aplicar.';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.black_recorte_valido(jsonb)'::regprocedure) <> '394cb0aebe3d877f775e679459511be5' then
    raise exception 'migration 20261013140000: corpo vivo de dados.black_recorte_valido não é o gravado por 20261012234606 (md5 394cb0ae…). Reler antes de aplicar.';
  end if;
end
$g$;

-- 1. recorte de anúncio com lista de ids (valor = ids do Meta só com dígitos, separados por vírgula; até 2000 caracteres)
create or replace function dados.black_no_recorte(p_recorte jsonb, p_porta text, p_isca text,
                                                  p_campanha_id text, p_conjunto_id text, p_anuncio_id text)
 returns boolean
 language sql
 immutable
 set search_path to ''
as $function$
  -- 20261012234606
  -- 20261013140000: tipo anuncio aceita vários ids do Meta separados por vírgula (criativo = anúncios de mesmo nome)
  select p_recorte is null
      or case p_recorte ->> 'tipo'
           when 'porta' then (p_recorte ->> 'valor') = p_porta
           when 'isca' then (p_recorte ->> 'valor') = p_isca
           when 'campanha' then (p_recorte ->> 'valor') = p_campanha_id
           when 'conjunto' then (p_recorte ->> 'valor') = p_conjunto_id
           when 'anuncio' then p_anuncio_id = any (string_to_array(p_recorte ->> 'valor', ','))
         end
$function$;
revoke all on function dados.black_no_recorte(jsonb, text, text, text, text, text) from public, anon, authenticated, service_role;

create or replace function dados.black_recorte_valido(p_recorte jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to ''
as $function$
begin
  -- 20261012234606: null, {} e jsonb null = sem recorte. 20261013140000: anúncio aceita lista de ids (só dígitos e vírgula)
  if p_recorte is null or p_recorte = '{}'::jsonb or jsonb_typeof(p_recorte) = 'null' then return null; end if;
  if jsonb_typeof(p_recorte) <> 'object'
     or exists (select 1 from jsonb_object_keys(p_recorte) k where k not in ('tipo', 'valor'))
     or jsonb_typeof(p_recorte -> 'tipo') is distinct from 'string'
     or jsonb_typeof(p_recorte -> 'valor') is distinct from 'string'
     or p_recorte ->> 'tipo' not in ('porta', 'isca', 'campanha', 'conjunto', 'anuncio')
     or length(p_recorte ->> 'valor') not between 1 and 2000
     or (p_recorte ->> 'tipo' = 'anuncio' and (p_recorte ->> 'valor') !~ '^[0-9]+(,[0-9]+)*$')
     or (p_recorte ->> 'tipo' <> 'anuncio' and length(p_recorte ->> 'valor') > 200) then
    raise exception 'recorte inválido: {"tipo": porta|isca|campanha|conjunto|anuncio, "valor": texto}' using errcode = '22023';
  end if;
  return p_recorte;
end
$function$;
revoke all on function dados.black_recorte_valido(jsonb) from public, anon, authenticated, service_role;

-- 2. utm_source=metaads é Meta (canal 'meta' e utm_campaign nome|id no padrão). Resto da view idêntico ao de 20261012234606.
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
       case when lower(n.us) in ('fb', 'facebook', 'ig', 'instagram', 'meta', 'metaads') then 'meta'
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
               and not (lower(coalesce(n.us, '')) in ('fb', 'facebook', 'ig', 'instagram', 'meta', 'metaads') and n.uc ~ '\|[0-9]+$')
              then 'utm_campaign_fora_do_padrao' end
       ], null) as a_corrigir,
       n.campos
  from n;
revoke all on dados.black_leads from public, anon, authenticated, service_role;
