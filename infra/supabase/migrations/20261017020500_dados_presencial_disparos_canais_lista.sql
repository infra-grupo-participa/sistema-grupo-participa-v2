-- 20261017020500: disparos da Clínica de Miami no mesmo formato do ATM (por canal e um por linha)
--
-- STATUS: ver 20261017020500.explain.md.
-- POR QUE: pedido do Victor (16/10/2026, card 17tya50h3b7): a aba de disparos da Clínica reaproveita os componentes do ATM
--   (canais + lista), que leem dados_atm_disparos_canais e dados_atm_disparos_lista. Essas duas só aceitam dashboard do
--   modelo seminário (dados.atm_cadastro). A existente dados_presencial_disparos(p_chave) tem outro formato (14 colunas).
-- O QUE FAZ: cria public.dados_presencial_disparos_canais(p_chave, p_de, p_ate) e public.dados_presencial_disparos_lista(p_chave,
--   p_de, p_ate), com EXATAMENTE as colunas e os tipos de retorno das duas do ATM (conferido contra pg_get_functiondef em
--   16/10/2026) e o mesmo corpo. Única diferença: o gate é dados.presencial_cadastro (só modelo presencial-base; 42501 sem acesso,
--   P0002 chave fora do cadastro). Período por dados.periodo(periodo_inicio, periodo_fim, p_de, p_ate): o cadastro da Clínica
--   tem os dois nulos, então sem p_de/p_ate não há limite (mesma regra de sempre: nulo = sem limite daquele lado).
--   Não altera dados.atm_cadastro, nem dados_atm_*, nem dados_presencial_disparos.
-- GRANTS: só authenticated; revoke de public, anon e service_role. Sem service_role.
-- AS 5 PERGUNTAS: escala = dezenas de disparos por projeto; índice = disparos_projeto_enviado_idx (projeto_id, enviado_em desc);
--   frequência = a cada abertura da aba; repetição = leitura pura (stable); reversão = 20261017020500_reversao.sql.
-- IDEMPOTENTE: create or replace.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.dados_presencial_disparos_canais(p_chave text, p_de date default null, p_ate date default null)
 returns table (canal text, disparos integer, enviados integer, entregues integer, lidas integer, cliques integer,
                falhas integer, custo_centavos bigint, disparos_sem_custo integer, custo_completo boolean)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- só o modelo presencial-base
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select c.canal, count(x.id)::int, sum(x.tamanho_lista)::int, sum(x.entregues)::int, sum(x.lidas)::int,
         sum(x.cliques)::int, sum(x.falhas)::int,
         sum(x.custo_centavos)::bigint,
         count(x.id) filter (where x.custo_centavos is null)::int,
         count(x.id) > 0 and count(x.id) filter (where x.custo_centavos is null) = 0
    from (values (1, 'whatsapp_api'), (2, 'grupo'), (3, 'sms'), (4, 'ligacao'), (5, 'email')) c(ordem, canal)
    left join mkt_mensageria.disparos x
           on x.canal = c.canal and x.projeto_id = d.projeto_id and x.arquivado_em is null
          and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
   group by c.ordem, c.canal
   order by c.ordem;
end
$function$;

create or replace function public.dados_presencial_disparos_lista(p_chave text, p_de date default null, p_ate date default null)
 returns table (disparo_id bigint, data_hora timestamptz, enviado_em timestamptz, canal text, canal_pago boolean,
                tipo text, ferramenta text, numero text, campanha text, publico_lista text, publico_origem text,
                copy_texto text, copy_link text, tamanho_lista integer, entregues integer, lidas integer, cliques integer,
                falhas integer, custo_centavos integer, origem text, retorno_em timestamptz)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.presencial_cadastro(p_chave);   -- só o modelo presencial-base
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select x.id, coalesce(x.enviado_em, x.criado_em), x.enviado_em, x.canal, x.canal not in ('email', 'grupo'),
         x.tipo, f.nome, n.numero, x.campanha, x.publico_lista, x.publico_origem,
         x.copy_texto, x.copy_link, x.tamanho_lista, x.entregues, x.lidas, x.cliques,
         x.falhas, x.custo_centavos, x.origem, x.retorno_em
    from mkt_mensageria.disparos x
    left join mkt_mensageria.ferramentas f on f.id = x.ferramenta_id
    left join mkt_mensageria.numeros n on n.id = x.numero_id
   where x.projeto_id = d.projeto_id and x.arquivado_em is null
     and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
   order by coalesce(x.enviado_em, x.criado_em), x.id;
end
$function$;

revoke all on function public.dados_presencial_disparos_canais(text, date, date) from public, anon, service_role;
revoke all on function public.dados_presencial_disparos_lista(text, date, date) from public, anon, service_role;
grant execute on function public.dados_presencial_disparos_canais(text, date, date) to authenticated;
grant execute on function public.dados_presencial_disparos_lista(text, date, date) to authenticated;

do $c$
declare f text;
begin
  foreach f in array array['public.dados_presencial_disparos_canais(text,date,date)', 'public.dados_presencial_disparos_lista(text,date,date)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('service_role', f, 'execute')
       or not has_function_privilege('authenticated', f, 'execute') then
      raise exception '20261017020500: permissões erradas em %', f;
    end if;
  end loop;
end
$c$;
