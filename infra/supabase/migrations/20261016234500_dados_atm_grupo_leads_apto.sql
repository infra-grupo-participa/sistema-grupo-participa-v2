-- 20261016234500: troca public.dados_atm_grupo_leads(p_chave, p_de, p_ate) para cruzar também com a Central de Alunos e
-- dizer quem é apto. Aba Leads e aba Resumo do modal "Ingresso no grupo" e hint do card nas Ações da Black. Pedido do
-- Victor Hugo em 16/10/2026: o link do grupo foi também para grupos antigos e muita gente entra com número diferente do
-- da lista, então o grupo tem gente que não está nem na lista nem na base.
--
-- STATUS: APLICADA em produção em 16/10/2026 às 13:26 UTC (md5 do arquivo aplicado, antes desta linha:
-- c093acfea5593dd49be2771b1e54b5ac). Ensaio: 20261016234500_ensaio.sql. Reversão: 20261016234500_reversao.sql (volta a versão de
-- 20261015210000). Relatório: 20261016234500.explain.md.
--
-- O QUE MUDA (sobre 20261015210000)
--   - Casamento novo com public.thb_alunos pelos 3 telefones (telefone, telefone_e164, telefone_profissional), 8 últimos
--     dígitos da controle.fone_key, igual ao resto. Traz nome e e-mail da Central.
--   - origem ganha 'central_alunos'. Ordem: lista_disparo > base_leads > central_alunos > nao_encontrado.
--   - Colunas novas no fim: na_central (o número está na Central) e apto.
--   - apto (regra do Victor, 16/10): Sim só para quem está na lista do disparo da chave, pelo telefone (na_lista) ou pelo
--     e-mail achado na base de leads ou na Central (dados.lista_membros.email_norm). Lead fora da lista não é apto;
--     achado só na Central e fora da lista também não.
--   - turma e instrucao: dados.perfil do e-mail achado (lista, base ou Central, nessa ordem).
--   - O tipo de retorno muda, então é drop + create (mesmo nome, mesma assinatura, mesmo ACL).
--
-- AS 5 PERGUNTAS
--   escala: os números do grupo da chave (46 na black-thb em 16/10), a lista (386), dados.atm_leads e thb_alunos
--     desaninhado nos 3 telefones (seq scan de thb_alunos, ~milhares de linhas). índice: fone8 casado em hash.
--   frequência: passa a rodar também no refresh do dashboard (60 s) para quem tem contato.ver, para o card contar os
--     aptos. repetição: 1 chamada por refresh. reversão: 20261016234500_reversao.sql.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('public.dados_atm_grupo_leads(text, date, date)') is null then
    raise exception '20261016234500: public.dados_atm_grupo_leads(text, date, date) não existe';
  end if;
  if to_regprocedure('dados.atm_leads(text)') is null or to_regprocedure('dados.perfil(text)') is null
     or to_regprocedure('dados.atm_cadastro(text)') is null or to_regclass('dados.v_grupo_pessoas_todos') is null then
    raise exception '20261016234500: dependência ausente';
  end if;
end
$g$;

drop function public.dados_atm_grupo_leads(text, date, date);

create function public.dados_atm_grupo_leads(p_chave text, p_de date default null, p_ate date default null)
returns table (
  fone_grupo text, origem text, na_lista boolean, na_base boolean,
  nome text, email text, telefone text, turma text, instrucao text,
  entrou_em timestamptz, saiu_em timestamptz, no_grupo boolean, entrada_aproximada boolean,
  na_central boolean, apto boolean
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
  ce as materialized (
    -- Central de Alunos pelos 3 telefones; quando o mesmo número aparece em mais de um aluno, quem está na lista primeiro
    select distinct on (t.fk8) t.fk8, t.nome, t.email
      from (select right(controle.fone_key(f.tel), 8) as fk8, a.nome, pessoas.norm_email(a.email) as email, a.eh_socio, a.id
              from public.thb_alunos a
             cross join lateral (values (a.telefone), (a.telefone_e164), (a.telefone_profissional)) f(tel)
             where nullif(btrim(f.tel), '') is not null) t
     where length(t.fk8) = 8 and t.fk8 in (select g.fone8 from g)
     order by t.fk8, exists (select 1 from dados.lista_membros m where m.chave = d.chave and m.email_norm = t.email) desc, t.eh_socio, t.id
  ),
  c as (
    select g.*, l.nome as l_nome, l.email as l_email, l.telefone as l_tel,
           b.nome as b_nome, b.email as b_email, b.telefone as b_tel,
           k.nome as k_nome, k.email as k_email,
           (l.fk8 is not null) as em_lista, coalesce(b.achou, false) as em_base, (k.fk8 is not null) as em_central
      from g
      left join lst l on l.fk8 = g.fone8
      left join lateral (select true as achou, ld.nome, ld.email, ld.telefone from ld
                          where ld.fk8 = g.fone8 or (g.pessoa_id is not null and ld.pessoa_id = g.pessoa_id)
                          order by (ld.fk8 = g.fone8) desc, ld.primeiro_em limit 1) b on true
      left join ce k on k.fk8 = g.fone8
  )
  select c.fone,
         case when c.em_lista then 'lista_disparo' when c.em_base then 'base_leads'
              when c.em_central then 'central_alunos' else 'nao_encontrado' end,
         c.em_lista, c.em_base,
         coalesce(c.l_nome, c.b_nome, c.k_nome), coalesce(c.l_email, c.b_email, c.k_email), coalesce(c.l_tel, c.b_tel, c.fone),
         pf.turma, pf.instrucao,
         c.entrou_em, c.saiu_em, c.no_grupo, c.entrada_aproximada,
         c.em_central,
         -- lista_membros_email_idx (chave, email_norm): no ATM a lista da chave passa de 100 mil linhas
         (c.em_lista or exists (select 1 from dados.lista_membros m
                                 where m.chave = d.chave and m.email_norm is not null
                                   and m.email_norm = any (array[pessoas.norm_email(c.b_email), pessoas.norm_email(c.k_email)])))
    from c
    left join lateral (select x.turma, x.instrucao from dados.perfil(coalesce(c.l_email, c.b_email, c.k_email)) x
                        where coalesce(c.l_email, c.b_email, c.k_email) is not null limit 1) pf on true
   order by c.entrou_em desc, c.fone;
end
$function$;

comment on function public.dados_atm_grupo_leads(text, date, date) is
  '20261016234500: aba Leads e Resumo do modal Ingresso no grupo (acao-black e seminario-atm). Um número do grupo uma vez, cruzado com a lista do disparo, a base de leads e a Central de Alunos; apto = está na lista do disparo. Exige contato.ver.';

revoke all on function public.dados_atm_grupo_leads(text, date, date) from public, anon;
grant execute on function public.dados_atm_grupo_leads(text, date, date) to authenticated;
