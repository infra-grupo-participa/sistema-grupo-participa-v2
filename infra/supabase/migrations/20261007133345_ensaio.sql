-- Ensaio de 20261007133345_crm_criar_contato (ex-20261007h) — tudo numa transação que termina em ROLLBACK. Nada persiste.
-- JWT real: gestor Arthur 3bd183e5… e Jonathan bd5361bc… (admin, crm.eh_gestor true; não são vendedor ativo),
-- vendedor Marcos Paulo 9d347183… (único vendedor ativo), visualizador Luis Fernando 9d5fb8e7… (fora do Comercial).
-- E-mails fictícios @ensaio-20261007h.test (conferido: nenhum na base).
-- Esperado (tabela _r no fim):
--   a.gestor        ok, nova true, donoId null
--   a.repetido      ok, nova false, mesmo contatoId (e-mail com maiúsculas e espaços); identificadores de e-mail = 1; pessoas = 1
--   b.vendedor      ok, nova true, donoId = Marcos
--   a.vendedor      A existia sem dono → ok, nova false, donoId = Marcos (vendedor vira dono do que cadastra)
--   b.outro_dono    B com dono Ronan (posto à mão) → Marcos: ok false, "já está no CRM com outro dono (Ronan)…"; dono continua Ronan
--   b.gestor_dono   Jonathan pede dono Marcos para B → ok true, "já estava no CRM com outro dono (Ronan)…"; dono continua Ronan
--   validacao       nome curto / sem canal / e-mail inválido / telefone inválido / dono inválido → ok false com msg
--   z.vendedor_escolhe_ele  vendedor que manda dono = ele mesmo → ok, nova, donoId = Marcos
--   visualizador    sqlstate 42501
--   log             crm.log entidade contato: "Cadastrou o contato …" para A e B; "Cadastro repetido …: dono Marcos Paulo" para A
--   acl             anon false, authenticated true, public false
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _r (k text, v jsonb) on commit drop;
grant all on _r to authenticated;
insert into _r select 'base', jsonb_build_object(
  'ident', (select count(*) from pessoas.identificadores where tipo = 'email' and chave like '%@ensaio-20261007h.test'),
  'escrita_ligada', (select escrita_ligada from crm.config));

-- MIGRATION (conteúdo idêntico ao arquivo)
-- 20261007h_crm_criar_contato — "Novo contato" do CRM grava de verdade (bug do Arthur, 07/10/2026:
-- "Deu erro ao cadastrar o contato novo"). O front caía no caminho de demonstração porque não havia RPC de criar contato.
--
-- public.crm_criar_contato(p_dados jsonb) → {ok, msg?, contatoId?, nova?, donoId?}
--   p_dados: {nome, email?, telefone?, dono?}  (telefone ou e-mail: pelo menos um)
--   - Comercial: crm.exige_comercial() (42501 para quem não é do Comercial) + crm.guarda_escrita() (escrita_ligada).
--   - Pessoa: pessoas.registrar(..., 'crm', auth.uid()), a mesma porta de entrada da F0. Casamento do pessoas.resolver:
--     e-mail primeiro; telefone só sem e-mail, pela chave controle.fone_key (pessoas.chave_telefone), 1 candidato e
--     nome compatível; nome sozinho nunca casa (só abre revisão).
--   - Linha comercial: crm.pessoa_comercial (pessoa nova: insert com dono; existente: crm.garantir_pc).
--   - Dono: vendedor ativo que cadastra = ele; gestor = o dono escolhido (vendedor ativo) ou sem dono.
--     Pessoa já existente sem dono recebe esse dono; com dono diferente, o dono NÃO muda e a mensagem diz quem é.
--   - Log: crm.tg_log da crm.pessoa_comercial, com crm.resumo.
-- A catalogação de origem (20261007g, outro agente) integra depois (canal_entrada = 'manual'): esta RPC fica simples.
-- Reversão: drop function public.crm_criar_contato(jsonb); o front volta a dizer que a fonte não grava.

-- Guarda de premissa: funções que esta RPC chama, exatamente como lidas em 07/10/2026; a RPC ainda não existe.
do $g$
declare r record;
begin
  if to_regprocedure('public.crm_criar_contato(jsonb)') is not null then
    raise exception 'premissa: crm_criar_contato(jsonb) já existe';
  end if;
  for r in select * from (values
      ('pessoas.registrar(jsonb,text,uuid)', 'e082542bde3f7abc431d562bb4e032e0'),
      ('pessoas.resolver(text,text,text,text,boolean,uuid)', '40eaf91a3fbe23dda1dfd4585af79137'),
      ('crm.garantir_pc(uuid)', '9563837f8ad7d4094c74903a75a1415c'),
      ('crm.guarda_escrita()', 'f4d590cb31a755f1eb4b37bf18b8a031'),
      ('crm.exige_comercial()', 'b207b8a30ac578f7c3556c6345c908b2'),
      ('crm.vendedor_ativo(uuid)', 'c9aacbaa42c5bea773ea48035cad3051')) v(sig, esperado) loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception 'premissa: % mudou', r.sig;
    end if;
  end loop;
  if not exists (select 1 from pg_trigger where tgrelid = 'crm.pessoa_comercial'::regclass and tgname = 'pessoa_comercial_log_ins_del') then
    raise exception 'premissa: trigger de log da crm.pessoa_comercial sumiu';
  end if;
end
$g$;

create function public.crm_criar_contato(p_dados jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_r jsonb; v_eu uuid := auth.uid();
  v_nome text; v_email_in text; v_tel_in text; v_dono_in text;
  v_gestor boolean; v_dono_pedido uuid; v_dono uuid;
  v_reg jsonb; v_atual uuid; v_nova boolean; v_pc uuid; v_dono_atual uuid; v_nome_pessoa text;
  v_s text; v_c text; v_m text;
begin
  perform crm.exige_comercial();
  v_r := crm.guarda_escrita(); if v_r is not null then return v_r; end if;
  if p_dados is null or jsonb_typeof(p_dados) <> 'object' then return crm.res(false, 'Dados inválidos.'); end if;

  v_nome := nullif(btrim(coalesce(p_dados ->> 'nome', '')), '');
  if v_nome is null or length(v_nome) < 2 then return crm.res(false, 'Informe o nome.'); end if;
  if length(v_nome) > 160 then return crm.res(false, 'Nome longo demais (até 160 caracteres).'); end if;
  v_email_in := nullif(btrim(coalesce(p_dados ->> 'email', '')), '');
  v_tel_in := nullif(btrim(coalesce(p_dados ->> 'telefone', '')), '');
  if v_email_in is null and v_tel_in is null then return crm.res(false, 'Informe telefone ou e-mail.'); end if;
  if v_email_in is not null and pessoas.norm_email(v_email_in) is null then return crm.res(false, 'E-mail inválido.'); end if;
  if v_tel_in is not null and pessoas.norm_telefone(v_tel_in) is null then
    return crm.res(false, 'Telefone inválido: use DDD + número (celular com 9).');
  end if;

  -- Dono: gestor escolhe (ou deixa sem); vendedor ativo é o dono do que cadastra.
  v_gestor := coalesce(crm.eh_gestor(), false);
  v_dono_in := nullif(btrim(coalesce(p_dados ->> 'dono', '')), '');
  if v_dono_in is not null then
    v_dono_pedido := crm.uuid_ou_null(v_dono_in);
    if v_dono_pedido is null or not coalesce(crm.vendedor_ativo(v_dono_pedido), false) then
      return crm.res(false, 'Vendedor não encontrado ou inativo.');
    end if;
    if not v_gestor and v_dono_pedido is distinct from v_eu then
      return crm.res(false, 'Só o gestor escolhe outro dono.');
    end if;
  end if;
  v_dono := coalesce(v_dono_pedido, case when coalesce(crm.vendedor_ativo(v_eu), false) then v_eu end);

  v_reg := pessoas.registrar(jsonb_build_object('nome', v_nome, 'email', v_email_in, 'telefone', v_tel_in, 'evento', 'cadastro'),
                             'crm', v_eu);
  if not coalesce((v_reg ->> 'ok')::boolean, false) then
    return crm.res(false, coalesce(v_reg ->> 'msg', 'Não foi possível cadastrar.'));
  end if;
  v_atual := pessoas.atual((v_reg ->> 'pessoa_id')::uuid);
  v_nova := coalesce((v_reg ->> 'nova')::boolean, false);
  v_nome_pessoa := crm.nome_pessoa(v_atual);

  if v_nova then
    perform set_config('crm.resumo', left(format('Cadastrou o contato %s (dono: %s)', v_nome_pessoa, crm.nome_perfil(v_dono)), 1000), true);
    insert into crm.pessoa_comercial (pessoa_id, dono_id) values (v_atual, v_dono) on conflict (pessoa_id) do nothing;
    perform set_config('crm.resumo', '', true);
    v_pc := crm.garantir_pc(v_atual);
    return crm.res(true, 'Contato cadastrado.', jsonb_build_object('contatoId', v_atual, 'nova', true, 'donoId', v_dono));
  end if;

  -- Já existia (casou por e-mail ou telefone): nunca troca dono.
  v_pc := crm.garantir_pc(v_atual);
  select pc.dono_id into v_dono_atual from crm.pessoa_comercial pc where pc.pessoa_id = v_pc;
  if v_dono_atual is null and v_dono is not null then
    perform set_config('crm.resumo', left(format('Cadastro repetido de %s: dono %s', v_nome_pessoa, crm.nome_perfil(v_dono)), 1000), true);
    update crm.pessoa_comercial x set dono_id = v_dono, atualizado_em = now() where x.pessoa_id = v_pc and x.dono_id is null;
    perform set_config('crm.resumo', '', true);
    v_dono_atual := v_dono;
  end if;
  if v_dono_atual is not null and v_dono is not null and v_dono_atual <> v_dono then
    if not coalesce(crm.pode_ver_pessoa(v_atual), false) then
      return crm.res(false, format('Esse contato já está no CRM com outro dono (%s). O dono não mudou: fale com o gestor.',
                                   crm.nome_perfil(v_dono_atual)));
    end if;
    return crm.res(true, format('Esse contato já estava no CRM com outro dono (%s). O dono não mudou.', crm.nome_perfil(v_dono_atual)),
                   jsonb_build_object('contatoId', v_atual, 'nova', false, 'donoId', v_dono_atual));
  end if;
  return crm.res(true, 'Esse contato já estava no CRM: abri a ficha dele.',
                 jsonb_build_object('contatoId', v_atual, 'nova', false, 'donoId', v_dono_atual));
exception when check_violation or unique_violation or foreign_key_violation or not_null_violation
             or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
             or numeric_value_out_of_range or string_data_right_truncation or invalid_parameter_value then
  get stacked diagnostics v_s = returned_sqlstate, v_c = constraint_name, v_m = message_text;
  return crm.erro_dados(v_s, v_m, v_c);
end
$function$;

revoke all on function public.crm_criar_contato(jsonb) from public, anon;
grant execute on function public.crm_criar_contato(jsonb) to authenticated;
comment on function public.crm_criar_contato(jsonb) is
  '20261007h: "Novo contato" do CRM. pessoas.registrar(fonte crm) + crm.pessoa_comercial. Dono: vendedor ativo = ele; gestor = escolhido ou sem dono; existente com outro dono não muda. {ok, msg, contatoId, nova, donoId}.';
-- FIM DA MIGRATION

-- gestor Arthur
select set_config('request.jwt.claims', '{"sub":"3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('a.gestor', public.crm_criar_contato('{"nome":"Ensaio Contato A","email":"a@ensaio-20261007h.test"}'));
insert into _r values ('a.repetido', public.crm_criar_contato('{"nome":"Ensaio A de novo","email":"  A@Ensaio-20261007h.TEST "}'));
insert into _r values ('val.nome', public.crm_criar_contato('{"nome":"x","email":"z@ensaio-20261007h.test"}'));
insert into _r values ('val.canal', public.crm_criar_contato('{"nome":"Ensaio Z"}'));
insert into _r values ('val.email', public.crm_criar_contato('{"nome":"Ensaio Z","email":"nao-e-email"}'));
insert into _r values ('val.tel', public.crm_criar_contato('{"nome":"Ensaio Z","telefone":"(11) 1234"}'));
insert into _r values ('val.dono', public.crm_criar_contato('{"nome":"Ensaio Z","email":"z@ensaio-20261007h.test","dono":"db6e59ea-bb47-4d92-a169-a08ee4c30260"}'));
reset role;

-- vendedor Marcos Paulo
select set_config('request.jwt.claims', '{"sub":"9d347183-5395-434e-9e96-2a65dde1a3cd","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('b.vendedor', public.crm_criar_contato('{"nome":"Ensaio Contato B","email":"b@ensaio-20261007h.test"}'));
insert into _r values ('a.vendedor', public.crm_criar_contato('{"nome":"Ensaio Contato A","email":"a@ensaio-20261007h.test"}'));
insert into _r values ('z.vendedor_escolhe_ele', public.crm_criar_contato('{"nome":"Ensaio Z","email":"z@ensaio-20261007h.test","dono":"9d347183-5395-434e-9e96-2a65dde1a3cd"}'));
reset role;

-- B passa a ser do Ronan (como postgres, só no ensaio)
update crm.pessoa_comercial set dono_id = 'db6e59ea-bb47-4d92-a169-a08ee4c30260'
 where pessoa_id = ((select v from _r where k = 'b.vendedor') ->> 'contatoId')::uuid;
select set_config('request.jwt.claims', '{"sub":"9d347183-5395-434e-9e96-2a65dde1a3cd","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('b.outro_dono', public.crm_criar_contato('{"nome":"Ensaio Contato B","email":"b@ensaio-20261007h.test"}'));
reset role;
select set_config('request.jwt.claims', '{"sub":"bd5361bc-3c3f-4f85-8b5a-f21433d040e3","role":"authenticated"}', true);
set local role authenticated;
insert into _r values ('b.gestor_dono', public.crm_criar_contato('{"nome":"Ensaio Contato B","email":"b@ensaio-20261007h.test","dono":"9d347183-5395-434e-9e96-2a65dde1a3cd"}'));
reset role;

-- visualizador Luis Fernando
select set_config('request.jwt.claims', '{"sub":"9d5fb8e7-f61e-459d-be04-d103ec783c08","role":"authenticated"}', true);
set local role authenticated;
do $v$
begin
  perform public.crm_criar_contato('{"nome":"Ensaio V","email":"v@ensaio-20261007h.test"}');
  insert into _r values ('visualizador', '"passou"');
exception when others then
  insert into _r values ('visualizador', jsonb_build_object('sqlstate', sqlstate, 'msg', sqlerrm));
end
$v$;
reset role;

insert into _r select 'depois', jsonb_build_object(
  'ident_email', (select jsonb_object_agg(i.chave, i.n) from (select chave, count(*) n from pessoas.identificadores
                   where tipo = 'email' and chave like '%@ensaio-20261007h.test' group by chave) i),
  'mesmo_id_a', ((select v from _r where k = 'a.gestor') ->> 'contatoId') = ((select v from _r where k = 'a.repetido') ->> 'contatoId'),
  'dono_a', (select crm.nome_perfil(dono_id) from crm.pessoa_comercial where pessoa_id = ((select v from _r where k = 'a.gestor') ->> 'contatoId')::uuid),
  'dono_b', (select crm.nome_perfil(dono_id) from crm.pessoa_comercial where pessoa_id = ((select v from _r where k = 'b.vendedor') ->> 'contatoId')::uuid),
  'eventos_crm', (select count(*) from pessoas.eventos e where e.fonte = 'crm' and e.pessoa_id in (
                   ((select v from _r where k = 'a.gestor') ->> 'contatoId')::uuid, ((select v from _r where k = 'b.vendedor') ->> 'contatoId')::uuid)));
insert into _r select 'log', jsonb_agg(l.acao || ' | ' || l.canal || ' | ' || l.resumo order by l.id)
  from crm.log l where l.entidade = 'contato' and l.pessoa_id in (
    ((select v from _r where k = 'a.gestor') ->> 'contatoId')::uuid, ((select v from _r where k = 'b.vendedor') ->> 'contatoId')::uuid);
insert into _r values ('acl', jsonb_build_object(
  'anon', has_function_privilege('anon', 'public.crm_criar_contato(jsonb)', 'execute'),
  'authenticated', has_function_privilege('authenticated', 'public.crm_criar_contato(jsonb)', 'execute'),
  'proacl', (select proacl::text from pg_proc where oid = 'public.crm_criar_contato(jsonb)'::regprocedure)));
-- O MCP não devolve o SELECT de uma transação desfeita: o resultado sai na mensagem do erro, que também desfaz tudo.
do $fim$ begin raise exception 'RESULTADO %', (select jsonb_object_agg(k, v) from _r); end $fim$;
rollback;
