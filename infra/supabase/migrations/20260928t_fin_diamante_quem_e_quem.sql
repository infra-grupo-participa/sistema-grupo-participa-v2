-- 20260928t — Serviço Diamante, rodada 2 (João, 27/09/2026): "Exatus Contabilidade não é o nome dele, é Vitor Negrão…
-- tem gente com nome de empresa… tem gente com nome em caps… não pode ter nenhum dado divergente porque isso vai virar
-- cobrança… se a pessoa estiver devendo tem que estar bem escancarado".
--
-- 1) fin.nome_proprio(text): "JOÃO DA SILVA LTDA" → "João da Silva LTDA" (partículas minúsculas, siglas de empresa em
--    maiúscula, &amp; → &). fin.nome_de_empresa(text): o nome é de empresa (LTDA, sociedade, advocacia, contabilidade…).
-- 2) fin.diamante_clientes: e-mail de compra → cliente, copiado do cadastro operacional do projeto "Serviços Diamante"
--    (portal.clients + e-mails de portal.hotmart_purchases), 24 clientes reais (contas de teste fora). É a fonte do NOME e
--    de QUEM É QUEM: o Vitor Negrão compra por dois e-mails de empresas diferentes e é um cliente só. É uma CÓPIA — cliente
--    novo no portal precisa entrar aqui (quem não está cai no cadastro de alunos e, por último, no nome da Hotmart).
-- 3) fn_fin_diamante_servicos v3:
--    * pessoa = cliente do cadastro (pelo e-mail; ou por outro e-mail da mesma pessoa no grafo, se só houver um cliente);
--      senão a pessoa do grafo de identidade.
--    * nome = cadastro Diamante → cadastro do aluno (thb_alunos) → comprador da Hotmart; sempre por fin.nome_proprio.
--      nome_compra = o nome que está na Hotmart quando é outro (empresa que paga pela pessoa).
--    * 🔴 valor da mensalidade devida = valor da PRIMEIRA tentativa do mês. A Hotmart tenta cobrar meses atrasados de uma
--      vez (Vitor Negrão, 02/06/2026: R$ 3.200 numa tentativa = 4 × R$ 800); o max() somava esse valor em cima dos meses.
--    * meses: jsonb {"2026-01": "atrasado", "2025-12": "pago", …} por serviço, pelo mês em que a cobrança nasceu —
--      a grade de adimplência da tela.

create or replace function fin.nome_proprio(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(string_agg(
           case when w.i > 1 and lower(w.p) in ('de','da','do','das','dos','e','di','du','del','van','von') then lower(w.p)
                when upper(w.p) in ('LTDA','ME','EIRELI','S/A','SA','EPP','OAB','S.A.','SS','II','III') then upper(w.p)
                else initcap(lower(w.p)) end, ' ' order by w.i), '')
    from regexp_split_to_table(btrim(regexp_replace(replace(coalesce(p, ''), '&amp;', '&'), '\s+', ' ', 'g')), ' ')
         with ordinality as w(p, i)
   where w.p <> ''
$$;

create or replace function fin.nome_de_empresa(p text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(p, '') ~* '(\m(ltda|eireli|epp|s/a|s\.a\.|me)\M|sociedade|advogad|advocacia|contabil|assessoria|consultoria|planejamento|servi[cç]os|empreendimentos|associados|&|holding|escrit[oó]rio|com[eé]rcio|digital)'
$$;

create table if not exists fin.diamante_clientes (
  email text primary key,
  cliente_slug text not null,
  nome text not null
);
alter table fin.diamante_clientes enable row level security;
revoke all on fin.diamante_clientes from public, anon, authenticated;

insert into fin.diamante_clientes (email, cliente_slug, nome) values
  ('alimapiresadv@gmail.com', 'alessandro-lima', 'Alessandro Lima'),
  ('anthonylimasodre@gmail.com', 'anthony-sodre', 'Anthony Sodré'),
  ('bartirapaesadv@gmail.com', 'bartira-paes', 'Bartira Paes'),
  ('bernadete1609@gmail.com', 'bernadete', 'Bernadete'),
  ('brunocoutorocha@yahoo.com.br', 'bruno-couto', 'Bruno Couto Rocha'),
  ('ckellner.adv@gmail.com', 'claudia-kellner', 'Claudia Kellner'),
  ('contato@debemcomseusbens.com', 'cynthia-naranjo', 'Cynthia Naranjo'),
  ('crnaranjo82@gmail.com', 'cynthia-naranjo', 'Cynthia Naranjo'),
  ('deysebrandt@yahoo.com.br', 'deyse-engel', 'Deyse Engel'),
  ('fabianaparro@outlook.com', 'fabiana-parro', 'Fabiana Parro'),
  ('felipesbarros@gmail.com', 'felipe-schroeder', 'Felipe Schroeder de Barros'),
  ('debemcomseusbens@gmail.com', 'fernanda-lessa', 'Fernanda Lessa'),
  ('nicholle@debemcomseusbens.com.br', 'fernanda-lessa', 'Fernanda Lessa'),
  ('joao.eduardo.maciel@gmail.com', 'joao-eduardo-zanela', 'João Eduardo Zanela'),
  ('comercialpaixaoadvogados@gmail.com', 'katia-paixao', 'Katia Paixão'),
  ('drakatiapaixao@gmail.com', 'katia-paixao', 'Katia Paixão'),
  ('paixaoconsultoriajuridica@gmail.com', 'katia-paixao', 'Katia Paixão'),
  ('luciano.s@simionato.adv.br', 'luciano-simionato', 'Luciano Simionato'),
  ('matheusagborges@gmail.com', 'matheus-borges', 'Matheus Borges'),
  ('matheusagborges2@gmail.com', 'matheus-borges', 'Matheus Borges'),
  ('nairio.augusto@gmail.com', 'nairio', 'Naírio'),
  ('osvaldo@catena.adv.br', 'osvaldo-catena', 'Osvaldo Catena'),
  ('osvaldocatena@gmail.com', 'osvaldo-catena', 'Osvaldo Catena'),
  ('paulo@softhi.com.br', 'paulo-guaraciaba', 'Paulo Henrique Borges Guaraciaba'),
  ('pedrohnw@gmail.com', 'pedro-nery', 'Pedro Nery'),
  ('priscilaaziliani@gmail.com', 'priscila-ziliani', 'Priscila Ziliani'),
  ('molinoerua@gmail.com', 'rafael-molino', 'Rafael Molino'),
  ('rafaelmolino.adv@gmail.com', 'rafael-molino', 'Rafael Molino'),
  ('rlfgaspar@advocaciafg.com.br', 'roberto-gaspar', 'Roberto G. Fernandes'),
  ('advsuelyresende@gmail.com', 'suely-resende', 'Suely Resende'),
  ('vitor@exatusonline.com.br', 'vitor-negrao', 'Vitor Negrão'),
  ('vitor@negraoefares.com.br', 'vitor-negrao', 'Vitor Negrão'),
  ('wiliamlorodeoliveira@gmail.com', 'willian-loro', 'Willian Loro'),
  ('wloliveira@hotmail.com', 'willian-loro', 'Willian Loro')
on conflict (email) do update set cliente_slug = excluded.cliente_slug, nome = excluded.nome;

drop function if exists public.fn_fin_diamante_servicos();
create or replace function public.fn_fin_diamante_servicos()
returns table (
  pessoa_chave text, nome text, nome_compra text, nome_empresa boolean, cliente_cadastro boolean,
  email text, emails text[], telefone text, nivel text,
  servico text, ofertas text[], desconhecida boolean,
  primeira_paga date, ultima_paga date, pagamentos int, total_pago numeric, liquido numeric, mensalidade numeric,
  devendo_n int, devendo_valor numeric, devendo_desde date, antigo_n int, antigo_valor numeric, antigo_desde date,
  estornos int, tentativas int, ultima_tentativa date, meses jsonb, situacao text
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with base as (
    select t.*, ip.pessoa_chave grafo,
           coalesce(o.servico, 'desconhecida') serv, o.geracao, (o.oferta_codigo is null) descon
      from fin.vw_transacoes t
      join fin.produtos p on p.produto_id = t.produto_id and p.papel = 'servico'
      left join fin.identidade ip on ip.no = 'e:' || t.email
      left join fin.diamante_ofertas o on o.oferta_codigo = t.oferta_codigo
     where t.email is not null
  ), cli_grafo as (
    -- cliente do cadastro alcançado por OUTRO e-mail da mesma pessoa no grafo — só se for um cliente só
    select i.pessoa_chave grafo, min(dc.cliente_slug) slug
      from fin.identidade i join fin.diamante_clientes dc on 'e:' || dc.email = i.no
     group by i.pessoa_chave having count(distinct dc.cliente_slug) = 1
  ), tx as (
    select coalesce('c:' || dc.cliente_slug, 'c:' || cg.slug, b.grafo, 'e:' || b.email) pessoa, b.*
      from base b
      left join fin.diamante_clientes dc on dc.email = b.email
      left join cli_grafo cg on cg.grafo = b.grafo
  ), parc as (
    -- uma linha por mensalidade (e-mail × oferta × recorrência): OVERDUE é por tentativa
    select x.pessoa, x.serv, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao) parcela,
           bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'pago') paga, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde,
           (array_agg(x.valor_oferta order by x.pedido_em))[1] valor
      from tx x
     group by x.pessoa, x.serv, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), reg as (
    select x.pessoa, x.serv, max(x.aprovado_em) ult_reg
      from tx x where x.grupo = 'pago' and x.geracao = 'regularizacao'
     group by x.pessoa, x.serv
  ), devida as (
    select p.* from parc p
      left join reg r on r.pessoa = p.pessoa and r.serv = p.serv
     where p.atrasou and not p.quitada and (r.ult_reg is null or r.ult_reg < p.desde)
  ), div as (
    select d.pessoa, d.serv,
           count(*) filter (where d.desde >= now() - interval '120 days')::int n,
           coalesce(sum(d.valor) filter (where d.desde >= now() - interval '120 days'), 0) valor,
           min(d.desde) filter (where d.desde >= now() - interval '120 days') desde,
           count(*) filter (where d.desde < now() - interval '120 days')::int an,
           coalesce(sum(d.valor) filter (where d.desde < now() - interval '120 days'), 0) avalor,
           min(d.desde) filter (where d.desde < now() - interval '120 days') adesde
      from devida d group by d.pessoa, d.serv
  ), mes as (
    -- grade de adimplência: mês em que a cobrança nasceu → pior estado daquele mês no serviço
    select m.pessoa, m.serv, jsonb_object_agg(m.mes, m.estado) meses
      from (select p.pessoa, p.serv, to_char(p.desde at time zone 'America/Sao_Paulo', 'YYYY-MM') mes,
                   case when bool_or(dv.parcela is not null) then 'atrasado'
                        when bool_or(p.paga) then 'pago'
                        when bool_or(p.quitada) then 'estornado'
                        else 'tentativa' end estado
              from parc p
              left join devida dv on dv.pessoa = p.pessoa and dv.serv = p.serv and dv.email = p.email
                                 and dv.oferta_codigo = p.oferta_codigo and dv.parcela = p.parcela
             where p.desde >= now() - interval '24 months'
             group by 1, 2, 3) m
     group by m.pessoa, m.serv
  ), agg as (
    select x.pessoa, x.serv,
           array_agg(distinct x.oferta_codigo) ofertas,
           bool_or(x.descon) descon,
           min(x.dia_aprovado) filter (where x.grupo = 'pago') prim,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ult,
           count(*) filter (where x.grupo = 'pago')::int pagos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) total,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liq,
           (array_agg(x.valor_oferta order by x.aprovado_em desc) filter (where x.grupo = 'pago' and coalesce(x.geracao, '') <> 'regularizacao'))[1] mens,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           count(*)::int tentativas,
           max(x.dia_pedido) ult_tent
      from tx x
     group by x.pessoa, x.serv
  ), ems as (
    -- todos os e-mails da pessoa: os das compras + os do grafo + os do cadastro Diamante
    select distinct z.pessoa, z.email from (
      select x.pessoa, x.email from tx x
      union select x.pessoa, substr(i.no, 3) from tx x join fin.identidade i on i.pessoa_chave = x.grafo and i.no like 'e:%'
      union select 'c:' || dc.cliente_slug, dc.email from fin.diamante_clientes dc
    ) z where z.pessoa in (select pessoa from tx)
  ), aluno as (
    select e.pessoa,
           (array_agg(a.nivel_resultado order by array_position(
              array['diamante_vermelho','diamante','platina','ouro','profissional','em_formacao','pessoal','iniciante'], a.nivel_resultado)
              ) filter (where a.nivel_resultado is not null))[1] nivel,
           (array_agg(a.nome order by (a.nivel_resultado is null), a.nome))[1] nome
      from ems e join public.thb_alunos a on lower(trim(a.email)) = e.email
     group by e.pessoa
  ), pes as (
    select x.pessoa,
           (array_agg(x.nome order by x.pedido_em desc))[1] nome_hotmart,
           (array_agg(x.email order by x.pedido_em desc))[1] email,
           (array_agg(h.comprador_telefone order by x.pedido_em desc) filter (where h.comprador_telefone is not null))[1] tel
      from tx x join fin.hotmart_transacoes h on h.transacao = x.transacao
     group by x.pessoa
  ), cad as (
    select 'c:' || dc.cliente_slug pessoa, min(dc.nome) nome from fin.diamante_clientes dc group by dc.cliente_slug
  )
  select a.pessoa,
         fin.nome_proprio(coalesce(cd.nome, al.nome, pe.nome_hotmart)),
         case when fin.nome_proprio(pe.nome_hotmart) is distinct from fin.nome_proprio(coalesce(cd.nome, al.nome, pe.nome_hotmart))
              then fin.nome_proprio(pe.nome_hotmart) end,
         (cd.nome is null and al.nome is null and fin.nome_de_empresa(pe.nome_hotmart)),
         (cd.nome is not null),
         pe.email,
         (select array_agg(e.email order by e.email) from ems e where e.pessoa = a.pessoa),
         case when coalesce(public.gp_pode_ver_cpf(), false) then pe.tel
              when pe.tel is not null then '···' || right(regexp_replace(pe.tel, '\D', '', 'g'), 4) end,
         al.nivel,
         a.serv, a.ofertas, a.descon,
         a.prim, a.ult, a.pagos, a.total, a.liq, a.mens,
         coalesce(d.n, 0), coalesce(d.valor, 0), (d.desde at time zone 'America/Sao_Paulo')::date,
         coalesce(d.an, 0), coalesce(d.avalor, 0), (d.adesde at time zone 'America/Sao_Paulo')::date,
         a.estornos, a.tentativas, a.ult_tent, coalesce(ms.meses, '{}'::jsonb),
         case when coalesce(d.n, 0) > 0 then 'devendo'
              when a.pagos = 0 then 'nunca_pagou'
              when a.ult >= v_hoje - 40 then 'em_dia'
              when coalesce(d.an, 0) > 0 then 'parou_devendo'
              else 'encerrado' end
    from agg a
    join pes pe on pe.pessoa = a.pessoa
    left join cad cd on cd.pessoa = a.pessoa
    left join aluno al on al.pessoa = a.pessoa
    left join div d on d.pessoa = a.pessoa and d.serv = a.serv
    left join mes ms on ms.pessoa = a.pessoa and ms.serv = a.serv;
end $$;
revoke all on function public.fn_fin_diamante_servicos() from public, anon;
grant execute on function public.fn_fin_diamante_servicos() to authenticated;
