-- 20261013190752: lista de vendas (histórico) da seção "Sessão de Viabilidade" do dashboard ATM
--
-- STATUS: APLICADA em produção em 13/10/2026 (ok do Victor, alinhado com o JP), versão 20261013190752, com a linha em
-- supabase_migrations.schema_migrations na mesma transação; md5 gravado = ae5312df56af3c0959a1bd3c17d129ae = este arquivo antes desta
-- troca de STATUS. Escrita e ensaiada (BEGIN ... ROLLBACK) em 13/10/2026.
-- Ensaio: 20261013190752_ensaio.sql. Reversão: 20261013190752_reversao.sql. Situação e prova: 20261013190752.explain.md.
-- Depende de 20261008191000 (marcação de teste) e 20261007180503 (schema acesso), já aplicadas.
--
-- POR QUE (card 17tya50ga3c, Seminário ATM, chave atm-elaine-1-2026-10)
--   A seção "Sessão de Viabilidade" precisa da LISTA das vendas, com nome e telefone, lida do banco. Hoje só existem
--   dados.atm_vendas_todas / dados.atm_vendas (internas, sem nome e telefone) e as contagens de public.dados_atm_resumo.
--   public.dados_presencial_vendas traz nome e telefone, mas é do modelo presencial-base, não corta vendas_desde, não
--   filtra pago/1ª cobrança e não trata teste. Não há RPC pública com a lista do ATM.
--
-- O QUE FAZ
--   public.dados_atm_sv_vendas(p_chave text, p_incluir_teste boolean default false), só leitura, nova (nenhuma função
--   existente muda). As linhas são EXATAMENTE as de dados.atm_vendas_todas (a regra de venda do dashboard fica num lugar
--   só: pagas, 1ª cobrança, desde vendas_desde, oferta do cadastro + ofertas_extra); nome, telefone e status vêm de
--   dados.transacoes pela transação; oferta_codigo é a da transação no espelho fin.hotmart_transacoes (quando o
--   dashboard não tem ofertas_extra, a única possível é a do cadastro). Com p_incluir_teste = false (padrão) as vendas
--   de comprador marcado como teste saem, igual às contagens de dados_atm_resumo.
--   Acesso, nesta ordem:
--     1. dados.atm_cadastro: equipe (@advmais ativo) e dashboard ativo do modelo seminario-atm (42501 / P0002), igual a
--        public.dados_atm_leads;
--     2. capacidade contato.ver (acesso.tem: master sempre; os outros por acesso_capacidade_definir), igual a
--        public.dados_black_lista; sem ela, 42501;
--     3. p_incluir_teste = true só para master (acesso.eh_master); os outros, 42501.
--   Grants: revoke de public, anon e service_role; execute só para authenticated; pós-condição no fim do arquivo.
--
-- AS 5 PERGUNTAS
--   escala: vendas de uma oferta por edição (ATM 1: 0 vendas pagas desde vendas_desde em 13/10; 16 transações na oferta).
--   índice: dados.transacoes lê fin.hotmart_transacoes por conta/oferta (hotmart_transacoes_oferta_idx); a oferta da
--           transação sai pela PK (hotmart_transacoes_pkey). Nada novo. O espelho é lido na forma exigida pela trava de
--           conta (fin.trava_conta_hotmart): (select * from fin.hotmart_transacoes where conta = v_conta).
--   frequência: uma chamada por abertura/atualização da seção (mesma cadência das outras RPCs do ATM).
--   repetição: dados.transacoes roda 2 vezes por chamada (uma dentro de atm_vendas_todas, uma para nome/telefone);
--              é o preço de não copiar a regra de venda. Medido no ensaio (ver explain.md).
--   reversão: 20261013190752_reversao.sql (drop da função; nada mais foi criado).
--
-- IDEMPOTENTE: create or replace; revoke/grant repetíveis.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

-- 0. Guarda de premissa
do $g$
declare v text;
begin
  foreach v in array array['dados.atm_cadastro(text)', 'dados.atm_vendas_todas(text)', 'dados.transacoes(text,text)',
                           'acesso.tem(text)', 'acesso.eh_master()'] loop
    if to_regprocedure(v) is null then
      raise exception 'premissa: falta %', v;
    end if;
  end loop;
  if to_regclass('fin.hotmart_transacoes') is null then
    raise exception 'premissa: falta fin.hotmart_transacoes';
  end if;
end
$g$;

-- 1. A lista
create or replace function public.dados_atm_sv_vendas(p_chave text, p_incluir_teste boolean default false)
returns table(transacao text, aprovado_em timestamp with time zone, pedido_em timestamp with time zone, dia_aprovado date,
              nome text, email text, telefone text, valor_bruto numeric, valor_liquido numeric, moeda text, status text,
              oferta_codigo text, teste boolean)
language plpgsql stable security definer set search_path = '' as $$
-- 20261013190752: vendas do ATM (regra de dados.atm_vendas_todas) com nome, telefone, status e oferta, para a seção
-- "Sessão de Viabilidade". Sem acesso ao dashboard ou sem contato.ver: 42501. Teste só para master.
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);   -- 42501 não equipe, P0002 chave fora do cadastro ou outro modelo
  v_teste boolean := coalesce(p_incluir_teste, false);
  v_conta text := d.conta_hotmart;   -- espelho lido na forma da trava de conta (fin.trava_conta_hotmart)
begin
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  if v_teste and not coalesce(acesso.eh_master(), false) then
    raise exception 'só master vê as vendas marcadas como teste' using errcode = '42501';
  end if;
  return query
  select v.transacao, v.aprovado_em, v.pedido_em, v.dia_aprovado,
         t.nome, v.email, t.telefone,
         v.valor_bruto, v.valor_liquido, v.moeda, t.status,
         coalesce(h.oferta_codigo,
                  case when coalesce(cardinality(d.ofertas_extra), 0) = 0 then d.oferta_codigo end),
         v.teste
    from dados.atm_vendas_todas(d.chave) v
    left join dados.transacoes(d.conta_hotmart, d.oferta_codigo) t on t.transacao = v.transacao
    left join (select * from fin.hotmart_transacoes where conta = v_conta) h on h.transacao = v.transacao
   where v_teste or not v.teste
   order by v.aprovado_em desc nulls last, v.transacao;
end
$$;
comment on function public.dados_atm_sv_vendas(text, boolean) is
  'Lista de vendas do ATM (regra de dados.atm_vendas_todas) com nome, telefone, status e oferta. Acesso ao dashboard + contato.ver; p_incluir_teste só master. 20261013190752.';

revoke all on function public.dados_atm_sv_vendas(text, boolean) from public, anon, service_role;
grant execute on function public.dados_atm_sv_vendas(text, boolean) to authenticated;

-- pós-condição: authenticated executa; anon, service_role e PUBLIC não
do $p$
declare f constant text := 'public.dados_atm_sv_vendas(text,boolean)';
begin
  if not has_function_privilege('authenticated', f, 'execute')
     or has_function_privilege('anon', f, 'execute')
     or has_function_privilege('service_role', f, 'execute')
     or exists (select 1 from pg_proc p cross join lateral aclexplode(p.proacl) a
                 where p.oid = f::regprocedure and a.grantee = 0) then
    raise exception 'pós-condição: grant errado em %', f;
  end if;
  if not (select p.prosecdef from pg_proc p where p.oid = f::regprocedure) then
    raise exception 'pós-condição: % não é security definer', f;
  end if;
end
$p$;

notify pgrst, 'reload schema';
