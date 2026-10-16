-- Reversão de 20261016234500_dados_atm_grupo_leads_apto.sql: volta a RPC à versão de 20261015210000 (sem Central e sem apto).
-- Depois: delete da versão 20261016234500 em supabase_migrations.schema_migrations.
set local lock_timeout = '3s';
set local statement_timeout = '10s';
drop function if exists public.dados_atm_grupo_leads(text, date, date);
create function public.dados_atm_grupo_leads(p_chave text, p_de date default null, p_ate date default null)
returns table (
  fone_grupo text, origem text, na_lista boolean, na_base boolean,
  nome text, email text, telefone text, turma text, instrucao text,
  entrou_em timestamptz, saiu_em timestamptz, no_grupo boolean, entrada_aproximada boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards;
  v_ini timestamptz; v_fim timestamptz;
begin
  -- contato.ver primeiro (pentester 15/10): sem ele, nem a existência da chave vaza pela diferença P0002 x 42501
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  d := dados.atm_cadastro(p_chave);   -- 42501 sem acesso ao dashboard, P0002 chave fora do cadastro ou outro modelo
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with g as (
    select p.fone8, coalesce(p.fone_key, p.fone8) as fone, p.pessoa_id, p.entrou_em, p.saiu_em, p.no_grupo, p.entrada_aproximada
      from dados.v_grupo_pessoas_todos p
     where p.chave = d.chave and p.entrou_em >= v_ini and p.entrou_em < v_fim and not p.teste
  ),
  lst as materialized (
    select distinct on (right(controle.fone_key(a.telefone), 8))
           right(controle.fone_key(a.telefone), 8) as fk8, a.nome, m.email_norm as email, a.telefone
      from dados.lista_membros m
      join public.thb_alunos a on pessoas.norm_email(a.email) = m.email_norm
     where m.chave = d.chave and a.telefone is not null
     order by right(controle.fone_key(a.telefone), 8), a.eh_socio, a.id
  ),
  ld as materialized (
    select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id, x.nome, x.email, x.telefone, x.primeiro_em
      from dados.atm_leads(d.chave) x
     where not coalesce(x.teste, false)
  ),
  c as (
    select g.*, l.nome as l_nome, l.email as l_email, l.telefone as l_tel,
           b.nome as b_nome, b.email as b_email, b.telefone as b_tel, (l.fk8 is not null) as em_lista, coalesce(b.achou, false) as em_base
      from g
      left join lst l on l.fk8 = g.fone8
      left join lateral (select true as achou, ld.nome, ld.email, ld.telefone from ld
                          where ld.fk8 = g.fone8 or (g.pessoa_id is not null and ld.pessoa_id = g.pessoa_id)
                          order by (ld.fk8 = g.fone8) desc, ld.primeiro_em limit 1) b on true
  )
  select c.fone,
         case when c.em_lista then 'lista_disparo' when c.em_base then 'base_leads' else 'nao_encontrado' end,
         c.em_lista, c.em_base,
         coalesce(c.l_nome, c.b_nome), coalesce(c.l_email, c.b_email), coalesce(c.l_tel, c.b_tel, c.fone),
         pf.turma, pf.instrucao,
         c.entrou_em, c.saiu_em, c.no_grupo, c.entrada_aproximada
    from c
    left join lateral (select x.turma, x.instrucao from dados.perfil(coalesce(c.l_email, c.b_email)) x
                        where coalesce(c.l_email, c.b_email) is not null limit 1) pf on true
   order by c.entrou_em desc, c.fone;
end
$function$;

comment on function public.dados_atm_grupo_leads(text, date, date) is
  '20261015210000: aba Leads do modal Ingresso no grupo (acao-black e seminario-atm). Um número do grupo uma vez, cruzado com a lista do disparo e a base de leads. Exige contato.ver.';

revoke all on function public.dados_atm_grupo_leads(text, date, date) from public, anon;
grant execute on function public.dados_atm_grupo_leads(text, date, date) to authenticated;
