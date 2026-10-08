-- 20261008190805 (20261008ey) crm_conversa_nova_mesmo_contato — ENSAIO (produção, ROLLBACK). Esperado: exclui 13 + 6; mensagem nova Infobip e QR
-- abre conversa nova no mesmo contato (0 pessoa criada); crm_mensagens mostra só a mensagem nova (1 e 1).
begin;
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
-- ── ENSAIO: gestor exclui; mensagem nova (Infobip e QR) abre conversa nova no mesmo contato. Termina em 'ENSAIO_OK' = ROLLBACK. ──
do $t$
declare
  v_g uuid := 'bd5361bc-3c3f-4f85-8b5a-f21433d040e3';
  v_c1 uuid := 'd8ef24ec-0976-4136-a8f3-a4088745a582'; v_c2 uuid := '46a18d1d-d0b4-448e-be9c-75933b1dee8b';
  cv1 crm.conversa%rowtype; cv2 crm.conversa%rowtype; v_num text; v_txt text; v_n1 crm.conversa%rowtype; v_n2 crm.conversa%rowtype;
  v_out text := ''; v_p0 int;
begin
  select * into cv1 from crm.conversa where id = v_c1;
  select * into cv2 from crm.conversa where id = v_c2;
  select numero into v_num from crm.numero_whatsapp where id = cv1.numero_id;
  select count(*) into v_p0 from pessoas.pessoas;
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_g::text, true);
  execute 'set local role authenticated';
  v_out := 'excluir c1=' || (public.crm_excluir_conversa(v_c1, 'mensagem de teste') ->> 'mensagens')
        || ' c2=' || (public.crm_excluir_conversa(v_c2, 'mensagem de teste') ->> 'mensagens');
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true); perform set_config('request.jwt.claim.sub', '', true);
  v_txt := crm.whatsapp_entrada(jsonb_build_object('to', v_num, 'from', cv1.telefone, 'messageId', 'ensaio-' || gen_random_uuid(),
             'message', jsonb_build_object('type', 'TEXT', 'text', 'Oi de novo'), 'receivedAt', now()));
  select * into v_n1 from crm.conversa where numero_id = cv1.numero_id and telefone = cv1.telefone and excluida_em is null;
  v_out := v_out || ' | infobip=' || v_txt || ' nova=' || (v_n1.id <> v_c1)::text
        || ' mesmo contato=' || (pessoas.atual(v_n1.pessoa_id) = pessoas.atual(cv1.pessoa_id))::text;
  v_txt := crm.evolution_entrada(jsonb_build_object('canalId', cv2.numero_id, 'id', 'ENSAIO' || substr(md5(random()::text), 1, 12),
             'telefone', cv2.telefone, 'fromMe', false, 'tipo', 'texto', 'texto', 'Oi pelo QR', 'em', now()));
  select * into v_n2 from crm.conversa where numero_id = cv2.numero_id and telefone = cv2.telefone and excluida_em is null;
  v_out := v_out || ' | evolution=' || v_txt || ' nova=' || (v_n2.id <> v_c2)::text
        || ' mesmo contato=' || (pessoas.atual(v_n2.pessoa_id) = pessoas.atual(cv2.pessoa_id))::text
        || ' pessoas criadas=' || ((select count(*) from pessoas.pessoas) - v_p0);
  perform set_config('request.jwt.claims', json_build_object('sub', v_g, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', v_g::text, true);
  execute 'set local role authenticated';
  v_out := v_out || ' | crm_mensagens contato1=' || jsonb_array_length(public.crm_mensagens(cv1.pessoa_id, 500))
        || ' contato2=' || jsonb_array_length(public.crm_mensagens(cv2.pessoa_id, 500));
  execute 'reset role';
  raise exception 'ENSAIO_OK %', coalesce(v_out, 'NULL');
end $t$;
rollback;
