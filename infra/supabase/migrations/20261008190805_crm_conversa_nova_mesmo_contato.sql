-- 20261008190805 crm_conversa_nova_mesmo_contato — APLICADA em 08/10/2026 (md5 dos statements gravados = 3991888b24c07b05ef0b72b29a2a0cd7 = este arquivo SEM estas 4 linhas de cabeçalho).
-- Complemento da 20261008190613: mensagem nova do mesmo telefone no mesmo número, depois da exclusão, abre conversa nova
-- (limpa) no MESMO contato da excluída, em vez de casar de novo por telefone (que pode cair em outra pessoa).
-- Ensaio: 20261008190805_ensaio.sql · decisões e medidas: 20261008190613.explain.md
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if md5(pg_get_functiondef('crm.whatsapp_entrada(jsonb)'::regprocedure)) <> '7a3298b94cc11f660b28b3303e38b221' then
    raise exception 'premissa: crm.whatsapp_entrada mudou';
  end if;
  if md5(pg_get_functiondef('crm.evolution_entrada(jsonb)'::regprocedure)) <> '0c1d619c72f3e411ff0a41d57778a660' then
    raise exception 'premissa: crm.evolution_entrada mudou';
  end if;
end $g$;

do $p$
declare r record; d text; n int;
begin
  for r in select * from (values
    (1, 'crm.whatsapp_entrada(jsonb)',
     $a$    v_reg := pessoas.registrar(jsonb_build_object('telefone', v_de, 'evento', 'cadastro'), 'crm', null);
    if not coalesce((v_reg ->> 'ok')::boolean, false) then return 'telefone_fora_do_padrao'; end if;
    v_pessoa := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);$a$,
     $b$    -- conversa excluída deste número + telefone (crm_excluir_conversa): a nova nasce limpa, no MESMO contato
    v_pessoa := (select pessoas.atual(x.pessoa_id) from crm.conversa x
                  where x.numero_id = v_num.id and x.telefone = v_de and x.excluida_em is not null
                  order by x.excluida_em desc limit 1);
    if v_pessoa is null then
      v_reg := pessoas.registrar(jsonb_build_object('telefone', v_de, 'evento', 'cadastro'), 'crm', null);
      if not coalesce((v_reg ->> 'ok')::boolean, false) then return 'telefone_fora_do_padrao'; end if;
      v_pessoa := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);
    end if;$b$, 1),
    (2, 'crm.evolution_entrada(jsonb)',
     $a$    v_reg := pessoas.registrar(jsonb_build_object('telefone', v_de, 'evento', 'cadastro'), 'crm', null);
    if not coalesce((v_reg ->> 'ok')::boolean, false) then return 'telefone_fora_do_padrao'; end if;
    v_pessoa := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);$a$,
     $b$    -- conversa excluída deste número + telefone (crm_excluir_conversa): a nova nasce limpa, no MESMO contato
    v_pessoa := (select pessoas.atual(x.pessoa_id) from crm.conversa x
                  where x.numero_id = n.id and x.telefone = v_de and x.excluida_em is not null
                  order by x.excluida_em desc limit 1);
    if v_pessoa is null then
      v_reg := pessoas.registrar(jsonb_build_object('telefone', v_de, 'evento', 'cadastro'), 'crm', null);
      if not coalesce((v_reg ->> 'ok')::boolean, false) then return 'telefone_fora_do_padrao'; end if;
      v_pessoa := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);
    end if;$b$, 1)
  ) v(ordem, fn, velho, novo, qtd) order by ordem loop
    d := pg_get_functiondef(r.fn::regprocedure);
    n := (length(d) - length(replace(d, r.velho, ''))) / length(r.velho);
    if n <> r.qtd then
      raise exception 'patch %: trecho de % aparece % vez(es), esperado %', r.ordem, r.fn, n, r.qtd;
    end if;
    execute replace(d, r.velho, r.novo);
  end loop;
end $p$;
