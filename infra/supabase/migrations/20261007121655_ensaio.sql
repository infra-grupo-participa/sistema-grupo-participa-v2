-- Ensaio de 20261007a_crm_ac_lead_vira_pessoa — tudo numa transação que termina em ROLLBACK. Nada persiste.
-- Webhook chamado como service_role (igual à Edge), token lido do Vault dentro da transação (nunca impresso).
-- E-mails de teste @exemplo.invalid. Esperado (tabela _r no fim):
--   migracao.reprocesso   AC com e-mail sem pessoa = 0; pessoa_criada = nº de e-mails distintos; resto anexado
--   lead_novo             receber → pessoas_criadas 1; evento 'pessoa_criada'; +1 pessoa, identificadores email+telefone
--                         origem activecampaign; +1 pessoa_comercial sem dono; evento 'lead' fonte activecampaign
--   lead_repetido         2º evento do mesmo lead → 'anexado', mesma pessoa, 0 pessoa nova
--   pessoa_existente      e-mail de aluno que já tem pessoa → 'anexado', 0 pessoa nova, 0 identificador novo
--   sem_email_sem_fone    'sem_identificador', sem pessoa
--   sem_email_fone_novo   'sem_pessoa', sem pessoa (telefone nunca cria)
--   telefone_depois       pessoa criada pelo reprocesso (sem número) ganha o telefone no evento seguinte
--   unnichat              e-mail desconhecido → 'sem_pessoa', 0 pessoa nova (inalterado)
--   kill_switch           activecampaign_cria_pessoa=false → 'sem_pessoa'
--   negocios              crm.negocio igual ao de antes
--   acl                   antes = depois (anexar: só postgres; receber/reprocessar: postgres + service_role)
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _r (k text, v jsonb) on commit drop;
grant all on _r to service_role;
create temp table _b on commit drop as
select (select count(*) from pessoas.pessoas) pessoas, (select count(*) from pessoas.identificadores) ident,
       (select count(*) from crm.negocio) negocios, (select count(*) from crm.pessoa_comercial) pc,
       (select count(distinct email_norm) from crm.evento_jornada where fonte = 'activecampaign' and pessoa_id is null
          and resultado = 'sem_pessoa' and email_norm is not null) ac_emails,
       (select count(*) from crm.evento_jornada where fonte = 'activecampaign' and pessoa_id is null
          and resultado = 'sem_pessoa' and email_norm is not null) ac_eventos;
insert into _r select 'acl.antes', jsonb_agg(jsonb_build_object(p.oid::regprocedure::text, p.proacl::text) order by p.proname)
  from pg_proc p where p.oid in (to_regprocedure('crm.anexar_integracao(bigint)'), to_regprocedure('public.crm_integracao_receber(text,text,jsonb)'),
                                 to_regprocedure('public.crm_integracao_reprocessar(integer)'));
insert into _r select 'base', to_jsonb(b) from _b b;

-- MIGRATION (conteúdo idêntico ao arquivo)
-- 20261007a_crm_ac_lead_vira_pessoa — decisão do Arthur em 07/10/2026 ("Prefiro o caminho A"):
-- todo lead novo do ActiveCampaign vira PESSOA no CRM, com a jornada desde o primeiro evento. NÃO vira negócio.
--
-- Antes: evento do AC sem pessoa casada ficava `sem_pessoa` em crm.evento_jornada (crm.anexar_integracao não cria pessoa).
-- Agora, SÓ para a fonte activecampaign:
--   1. Casamento igual ao de antes: e-mail primeiro (crm.pessoa_por_email); sem e-mail, telefone pela chave
--      controle.fone_key (pessoas.candidatos_telefone) com exatamente 1 candidato e nome compatível; nome nunca casa.
--   2. Com e-mail válido e ninguém casado → pessoas.registrar({email, telefone, nome, evento 'lead'}, 'activecampaign')
--      (cascata da F0: o que só bate por nome/telefone de outra pessoa vira `revisar`, nunca junta). O evento fica
--      `pessoa_criada` (valor novo) com pessoa_id. Trava a mesma chave de pessoas.resolver (advisory xact lock por e-mail)
--      ANTES de procurar: 3 eventos do mesmo lead no mesmo segundo viram 1 pessoa.
--   3. Pessoa criada ganha a linha comercial (crm.garantir_pc, sem dono): pela regra do Victor (20261006191824) aparece
--      na BUSCA do vendedor e na lista do gestor; na lista do vendedor só com negócio aberto. Nenhum negócio é criado.
--   4. Evento seguinte do AC de pessoa criada pelo AC sem telefone guardado anexa o telefone (os eventos antigos só
--      guardaram a chave fone_key, não o número).
--   5. Sem e-mail: nada muda (sem candidato = sem_pessoa; sem e-mail e sem telefone = sem_identificador).
--   Unnichat e SendFlow: nada muda (o ramo novo testa e.fonte = 'activecampaign').
--   6. Reprocessa os eventos do AC que estão sem pessoa (lote único, ordem de id).
-- Kill-switch: crm.config.activecampaign_cria_pessoa (novo, true). false = volta ao comportamento anterior (sem_pessoa).
--
-- Objetos: CHECKs (evento_jornada resultado + par resultado/pessoa; pessoas.identificadores.origem e pessoas.eventos.fonte
-- ganham 'activecampaign', como a F3 fez com 'hotmart'); crm.config + 1 coluna; crm.anexar_integracao muda de assinatura
-- (drop + create, + p_telefone default null); crm_integracao_receber e crm_integracao_reprocessar recriadas do corpo VIVO
-- (mesma assinatura, opções e grants) só para passar o telefone e contar pessoas criadas.

-- Guarda de premissa: corpos vivos (md5 de prosrc lido em 07/10/2026) e CHECKs exatamente como lidos.
do $g$
declare r record; v_n int;
begin
  for r in select * from (values
      ('crm.anexar_integracao(bigint)', 'b5a19b2af365c327d039e3b385d9875b'),
      ('public.crm_integracao_receber(text,text,jsonb)', 'd4fef48329d41516dfee04542e18e356'),
      ('public.crm_integracao_reprocessar(integer)', '52a83405fd1ec058d821aa1bd961e7ce'),
      ('pessoas.registrar(jsonb,text,uuid)', 'e082542bde3f7abc431d562bb4e032e0'),
      ('pessoas.resolver(text,text,text,text,boolean,uuid)', '40eaf91a3fbe23dda1dfd4585af79137'),
      ('crm.garantir_pc(uuid)', '9563837f8ad7d4094c74903a75a1415c')) v(sig, esperado)
  loop
    if (select md5(p.prosrc) from pg_proc p where p.oid = to_regprocedure(r.sig)) is distinct from r.esperado then
      raise exception '20261007a: corpo vivo de % mudou (md5 esperado %). Releia pg_get_functiondef antes de aplicar.', r.sig, r.esperado;
    end if;
  end loop;
  for r in select * from (values
      ('crm.evento_jornada', 'evento_jornada_resultado_check',
       'CHECK ((resultado = ANY (ARRAY[''pendente''::text, ''anexado''::text, ''sem_pessoa''::text, ''telefone_ambiguo''::text, ''sem_identificador''::text])))'),
      ('crm.evento_jornada', 'evento_jornada_check', 'CHECK (((resultado = ''anexado''::text) = (pessoa_id IS NOT NULL)))'),
      ('pessoas.identificadores', 'identificadores_origem_check',
       'CHECK ((origem = ANY (ARRAY[''formulario''::text, ''crm''::text, ''importacao''::text, ''hotmart''::text])))'),
      ('pessoas.eventos', 'eventos_fonte_check',
       'CHECK ((fonte = ANY (ARRAY[''formulario''::text, ''crm''::text, ''importacao''::text, ''sistema''::text, ''hotmart''::text])))')
    ) v(tab, con, def)
  loop
    if (select pg_get_constraintdef(c.oid) from pg_constraint c where c.conrelid = r.tab::regclass and c.conname = r.con)
       is distinct from r.def then
      raise exception '20261007a: CHECK % de % mudou. Releia pg_get_constraintdef.', r.con, r.tab;
    end if;
  end loop;
  if exists (select 1 from information_schema.columns where table_schema = 'crm' and table_name = 'config'
              and column_name = 'activecampaign_cria_pessoa') then
    raise exception '20261007a: crm.config.activecampaign_cria_pessoa já existe';
  end if;
  select count(*) into v_n from crm.evento_jornada where fonte = 'activecampaign' and pessoa_id is null
     and resultado in ('pendente', 'sem_pessoa') and email_norm is not null;
  if v_n > 2000 then
    raise exception '20261007a: % eventos do AC sem pessoa (esperado < 2000): reprocessar em lotes à parte', v_n;
  end if;
end
$g$;

-- 1. CHECKs: só ACRESCENTAM valores (lista antiga conferida na guarda)
alter table crm.evento_jornada drop constraint evento_jornada_resultado_check;
alter table crm.evento_jornada add constraint evento_jornada_resultado_check
  check (resultado in ('pendente', 'anexado', 'pessoa_criada', 'sem_pessoa', 'telefone_ambiguo', 'sem_identificador'));
alter table crm.evento_jornada drop constraint evento_jornada_check;
alter table crm.evento_jornada add constraint evento_jornada_check
  check ((resultado in ('anexado', 'pessoa_criada')) = (pessoa_id is not null));
alter table pessoas.identificadores drop constraint identificadores_origem_check;
alter table pessoas.identificadores add constraint identificadores_origem_check
  check (origem in ('formulario', 'crm', 'importacao', 'hotmart', 'activecampaign'));
alter table pessoas.eventos drop constraint eventos_fonte_check;
alter table pessoas.eventos add constraint eventos_fonte_check
  check (fonte in ('formulario', 'crm', 'importacao', 'sistema', 'hotmart', 'activecampaign'));

-- 2. Kill-switch
alter table crm.config add column activecampaign_cria_pessoa boolean not null default true;
comment on column crm.config.activecampaign_cria_pessoa is
  '20261007a: evento do AC com e-mail e sem pessoa casada cria a pessoa (pessoas.registrar, fonte activecampaign) + linha comercial sem dono. Nunca cria negócio. false = fica sem_pessoa como antes.';

-- 3. crm.anexar_integracao: + p_telefone (só o AC usa) e o ramo de criação. Assinatura muda → drop + create.
drop function crm.anexar_integracao(bigint);
create function crm.anexar_integracao(p_id bigint, p_telefone text default null)
 returns text
 language plpgsql
 set search_path to ''
as $function$
declare e crm.evento_jornada%rowtype; v_pessoa uuid; v_res text; v_n int; v_ent text; v_nome_ent text;
        v_tel text; v_reg jsonb; v_canal text;
begin
  select * into e from crm.evento_jornada where id = p_id for update;
  if not found then return null; end if;
  if e.email_norm is not null then
    -- 20261007a: o AC pode criar a pessoa; a mesma trava de pessoas.resolver vem ANTES da busca, para o 2º evento do
    -- mesmo lead (chegando junto) esperar a pessoa do 1º em vez de criar outra
    if e.fonte = 'activecampaign' then
      perform pg_advisory_xact_lock(hashtext('pessoas.resolver:' || e.email_norm));
    end if;
    v_pessoa := crm.pessoa_por_email(e.email_norm);
    v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
  elsif e.fone_key is not null then
    select count(*), min(t.ent), min(t.nome_ent) into v_n, v_ent, v_nome_ent from pessoas.candidatos_telefone(e.fone_key) t;
    if v_n = 0 then v_res := 'sem_pessoa';
    elsif v_n = 1 and pessoas.nomes_compativeis(e.nome, v_nome_ent) then
      v_pessoa := (pessoas.garantir(array[v_ent]))[1];
      v_res := case when v_pessoa is null then 'sem_pessoa' else 'anexado' end;
    else v_res := 'telefone_ambiguo';
    end if;
  else
    v_res := 'sem_identificador';
  end if;

  -- 20261007a (decisão do Arthur, caminho A): lead novo do AC vira pessoa, com a jornada desde o 1º evento. Sem negócio.
  if e.fonte = 'activecampaign' then
    v_tel := pessoas.norm_telefone(p_telefone);
    if v_res = 'sem_pessoa' and e.email_norm is not null
       and coalesce((select c.activecampaign_cria_pessoa from crm.config c), false) then
      v_reg := pessoas.registrar(jsonb_build_object('email', e.email_norm, 'telefone', v_tel, 'nome', e.nome, 'evento', 'lead'),
                                 'activecampaign', null);
      if coalesce((v_reg ->> 'ok')::boolean, false) and (v_reg ->> 'pessoa_id') is not null then
        v_pessoa := (v_reg ->> 'pessoa_id')::uuid;
        v_res := case when coalesce((v_reg ->> 'nova')::boolean, false) then 'pessoa_criada' else 'anexado' end;
        if v_res = 'pessoa_criada' then
          v_canal := current_setting('crm.canal', true);
          perform set_config('crm.canal', 'activecampaign', true);   -- crm.tg_log: autor_tipo 'integracao'
          perform crm.garantir_pc(v_pessoa);
          perform set_config('crm.canal', coalesce(v_canal, ''), true);
        end if;
      end if;
    elsif v_res = 'anexado' and v_tel is not null
          and exists (select 1 from pessoas.identificadores i
                       where i.pessoa_id = v_pessoa and i.tipo = 'email' and i.origem = 'activecampaign')
          and not exists (select 1 from pessoas.identificadores i where i.pessoa_id = v_pessoa and i.tipo = 'telefone') then
      -- pessoa criada pelo AC sem telefone guardado (eventos antigos só tinham a chave): anexa o número agora
      perform pessoas.anexar(v_pessoa, 'telefone', v_tel, pessoas.chave_telefone(v_tel), 'activecampaign');
    end if;
  end if;

  update crm.evento_jornada set pessoa_id = v_pessoa, resultado = v_res, processado_em = now() where id = p_id;
  return v_res;
end
$function$;
revoke all on function crm.anexar_integracao(bigint, text) from public, anon, authenticated, service_role;

-- 4. crm_integracao_receber: corpo vivo + telefone para o AC + contagem de pessoas criadas (mesma assinatura e grants)
create or replace function public.crm_integracao_receber(p_fonte text, p_chave text, p_eventos jsonb)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_ligado boolean; v_seg text; e jsonb; v_id bigint; v_res text;
  v_novos int := 0; v_dup int := 0; v_anex int := 0; v_inval int := 0; v_criadas int := 0;
  v_tipo text; v_quando timestamptz; v_utm jsonb;
begin
  if p_fonte is null or p_fonte not in ('activecampaign', 'unnichat', 'sendflow') then
    return jsonb_build_object('ok', false, 'msg', 'Fonte inválida.');
  end if;
  select ds.decrypted_secret into v_seg from vault.decrypted_secrets ds where ds.name = 'crm_webhook_' || p_fonte;
  if coalesce(v_seg, '') = '' or p_chave is null
     or extensions.digest(p_chave, 'sha256') <> extensions.digest(v_seg, 'sha256') then
    return jsonb_build_object('ok', false, 'msg', 'Não autorizado.', 'autorizado', false);
  end if;
  select case p_fonte when 'activecampaign' then c.activecampaign_ligado when 'unnichat' then c.unnichat_ligado
                      when 'sendflow' then c.sendflow_ligado end
    into v_ligado from crm.config c;
  if not coalesce(v_ligado, false) then
    return jsonb_build_object('ok', true, 'ignorado', 'desligado', 'autorizado', true);
  end if;
  if jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 or jsonb_array_length(p_eventos) > 100 then
    return jsonb_build_object('ok', false, 'msg', 'Envie de 1 a 100 eventos.', 'autorizado', true);
  end if;
  for e in select x from jsonb_array_elements(p_eventos) x loop
    v_tipo := lower(btrim(coalesce(e ->> 'tipo', '')));
    begin
      v_quando := coalesce(nullif(e ->> 'ocorreuEm', '')::timestamptz, now());
    exception when others then v_quando := null;
    end;
    if jsonb_typeof(e) <> 'object' or nullif(btrim(coalesce(e ->> 'id', '')), '') is null or length(e ->> 'id') > 200
       or v_tipo !~ '^[a-z0-9_.:-]{1,60}$' or v_quando is null or v_quando > now() + interval '1 day' then
      v_inval := v_inval + 1; continue;
    end if;
    v_utm := jsonb_strip_nulls(jsonb_build_object(
               'source', left(nullif(e #>> '{utm,source}', ''), 300), 'medium', left(nullif(e #>> '{utm,medium}', ''), 300),
               'campaign', left(nullif(e #>> '{utm,campaign}', ''), 300), 'content', left(nullif(e #>> '{utm,content}', ''), 300)));
    insert into crm.evento_jornada (fonte, fonte_evento_id, tipo, ocorreu_em, email_norm, fone_key, nome, lista, tag, dados)
    values (p_fonte, btrim(e ->> 'id'), v_tipo, v_quando,
            pessoas.norm_email(e ->> 'email'), pessoas.chave_telefone(e ->> 'telefone'),
            nullif(left(btrim(coalesce(e ->> 'nome', '')), 160), ''),
            nullif(left(btrim(coalesce(e ->> 'lista', '')), 200), ''), nullif(left(btrim(coalesce(e ->> 'tag', '')), 200), ''),
            case when v_utm = '{}'::jsonb then '{}'::jsonb else jsonb_build_object('utm', v_utm) end)
    on conflict (fonte, fonte_evento_id) do nothing
    returning id into v_id;
    if v_id is null then v_dup := v_dup + 1; continue; end if;
    v_novos := v_novos + 1;
    -- casamento nunca derruba a gravação do evento (fica 'pendente' e dá para reprocessar)
    begin
      -- 20261007a: só o AC leva o telefone (cria/completa a pessoa); o número não é gravado no evento
      v_res := crm.anexar_integracao(v_id, case when p_fonte = 'activecampaign' then left(e ->> 'telefone', 40) end);
      if v_res in ('anexado', 'pessoa_criada') then v_anex := v_anex + 1; end if;
      if v_res = 'pessoa_criada' then v_criadas := v_criadas + 1; end if;
    exception when others then
      raise warning 'crm_integracao_receber: casamento do evento % falhou (%)', v_id, sqlstate;
    end;
    v_id := null;
  end loop;
  return jsonb_build_object('ok', true, 'autorizado', true, 'novos', v_novos, 'duplicados', v_dup,
                            'anexados', v_anex, 'pessoas_criadas', v_criadas, 'invalidos', v_inval);
end
$function$;

-- 5. crm_integracao_reprocessar: corpo vivo + conta pessoa_criada (mesma assinatura e grants)
create or replace function public.crm_integracao_reprocessar(p_limite integer default 500)
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare r record; v_n int := 0; v_anex int := 0; v_criadas int := 0; v_res text;
begin
  for r in select e.id from crm.evento_jornada e
            where e.pessoa_id is null and e.resultado in ('pendente', 'sem_pessoa', 'telefone_ambiguo')
            order by e.id limit least(greatest(coalesce(p_limite, 500), 1), 5000) loop
    v_n := v_n + 1;
    v_res := crm.anexar_integracao(r.id);
    if v_res in ('anexado', 'pessoa_criada') then v_anex := v_anex + 1; end if;
    if v_res = 'pessoa_criada' then v_criadas := v_criadas + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'processados', v_n, 'anexados', v_anex, 'pessoas_criadas', v_criadas);
end
$function$;

-- 6. Reprocessa os eventos do AC que ficaram sem pessoa (só AC; Unnichat/SendFlow intocados). Ordem de id: o 1º evento
--    de cada lead cria a pessoa, os seguintes anexam.
do $r$
declare r record; v_res text; v_criadas int := 0; v_anex int := 0; v_resto int;
begin
  for r in select e.id from crm.evento_jornada e
            where e.fonte = 'activecampaign' and e.pessoa_id is null and e.resultado in ('pendente', 'sem_pessoa')
            order by e.id loop
    v_res := crm.anexar_integracao(r.id);
    if v_res = 'pessoa_criada' then v_criadas := v_criadas + 1; elsif v_res = 'anexado' then v_anex := v_anex + 1; end if;
  end loop;
  select count(*) into v_resto from crm.evento_jornada e
   where e.fonte = 'activecampaign' and e.pessoa_id is null and e.email_norm is not null and e.resultado in ('pendente', 'sem_pessoa');
  if v_resto > 0 then raise exception '20261007a: % eventos do AC com e-mail continuam sem pessoa', v_resto; end if;
  raise notice '20261007a: reprocessados AC: % pessoas criadas, % eventos anexados', v_criadas, v_anex;
end
$r$;

-- 7. Conferência final: grants iguais aos de antes
do $c$
begin
  if (select proacl::text from pg_proc where oid = to_regprocedure('crm.anexar_integracao(bigint,text)')) is distinct from '{postgres=X/postgres}'
     or (select proacl::text from pg_proc where oid = to_regprocedure('public.crm_integracao_receber(text,text,jsonb)'))
        is distinct from '{postgres=X/postgres,service_role=X/postgres}'
     or (select proacl::text from pg_proc where oid = to_regprocedure('public.crm_integracao_reprocessar(integer)'))
        is distinct from '{postgres=X/postgres,service_role=X/postgres}'
     or to_regprocedure('crm.anexar_integracao(bigint)') is not null then
    raise exception '20261007a: grants/assinaturas diferentes do esperado';
  end if;
end
$c$;

-- REVERSÃO (não executar junto):
--   desligar já (~10 s): update crm.config set activecampaign_cria_pessoa = false;
--   código: recriar crm.anexar_integracao(bigint) com o corpo de 20261006044653 e receber/reprocessar com o corpo dessa
--   versão; pessoas criadas ficam (identificador com origem 'activecampaign', evento 'lead' fonte 'activecampaign'):
--   nunca apagar, inativar/mesclar se preciso.

-- PROVAS
insert into _r select 'migracao.reprocesso', jsonb_build_object(
    'ac_sem_pessoa_com_email', (select count(*) from crm.evento_jornada where fonte = 'activecampaign' and pessoa_id is null and email_norm is not null and resultado in ('pendente','sem_pessoa')),
    'pessoa_criada', (select count(*) from crm.evento_jornada where fonte = 'activecampaign' and resultado = 'pessoa_criada'),
    'emails_distintos_antes', (select ac_emails from _b),
    'anexados', (select count(*) from crm.evento_jornada where fonte = 'activecampaign' and resultado = 'anexado'),
    'eventos_antes', (select ac_eventos from _b),
    'pessoas_novas', (select count(*) from pessoas.pessoas) - (select pessoas from _b),
    'pc_novas', (select count(*) from crm.pessoa_comercial) - (select pc from _b),
    'pc_novas_com_dono', (select count(*) from crm.pessoa_comercial pc join crm.evento_jornada e on e.pessoa_id = pc.pessoa_id and e.resultado = 'pessoa_criada' where pc.dono_id is not null),
    'revisar', (select count(*) from pessoas.pessoas p join crm.evento_jornada e on e.pessoa_id = p.id and e.resultado = 'pessoa_criada' where p.situacao = 'revisar'));

select set_config('ensaio.tk', (select decrypted_secret from vault.decrypted_secrets where name = 'crm_webhook_activecampaign'), true);
select set_config('ensaio.tku', (select decrypted_secret from vault.decrypted_secrets where name = 'crm_webhook_unnichat'), true);
select set_config('ensaio.aluno', (select lower(btrim(a.email)) from public.thb_alunos a join pessoas.pessoas p on p.aluno_id = a.id
  where pessoas.norm_email(a.email) is not null and p.mesclada_em is null order by a.id limit 1), true);
select set_config('ensaio.criado', (select email_norm from crm.evento_jornada where resultado = 'pessoa_criada' order by id limit 1), true);
create temp table _c on commit drop as select (select count(*) from pessoas.pessoas) p0, (select count(*) from pessoas.identificadores) i0;
grant all on _c to service_role;

set local role service_role;
insert into _r values ('lead_novo.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  '[{"id":"ensaio-20261007a-1","tipo":"subscribe","email":"Lead.Novo.20261007a@Exemplo.invalid","telefone":"(98) 99123-4007","nome":"Lead Ensaio Vinteoutubro"}]'));
reset role;
insert into _r select 'lead_novo', jsonb_build_object('resultado', e.resultado, 'pessoa', e.pessoa_id is not null,
    'situacao', p.situacao, 'nome', p.nome is not null,
    'ident', (select jsonb_agg(jsonb_build_object('tipo', i.tipo, 'origem', i.origem) order by i.tipo) from pessoas.identificadores i where i.pessoa_id = e.pessoa_id),
    'evento_lead', (select count(*) from pessoas.eventos x where x.pessoa_id = e.pessoa_id and x.tipo = 'lead' and x.fonte = 'activecampaign'),
    'pc', (select jsonb_build_object('dono_nulo', pc.dono_id is null) from crm.pessoa_comercial pc where pc.pessoa_id = e.pessoa_id),
    'log_pc', (select jsonb_agg(jsonb_build_object('autor_tipo', l.autor_tipo, 'canal', l.canal)) from crm.log l where l.entidade = 'contato' and l.pessoa_id = e.pessoa_id),
    'negocio', (select count(*) from crm.negocio n where n.pessoa_id = e.pessoa_id),
    'pessoas_novas', (select count(*) from pessoas.pessoas) - (select p0 from _c))
  from crm.evento_jornada e left join pessoas.pessoas p on p.id = e.pessoa_id where e.fonte_evento_id = 'ensaio-20261007a-1';

set local role service_role;
insert into _r values ('lead_repetido.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  '[{"id":"ensaio-20261007a-2","tipo":"contact_tag_added","email":"lead.novo.20261007a@exemplo.invalid","telefone":"98991234007","nome":"Lead Ensaio Vinteoutubro","tag":"ENSAIO"}]'));
reset role;
insert into _r select 'lead_repetido', jsonb_build_object('resultado', e2.resultado, 'mesma_pessoa', e2.pessoa_id = e1.pessoa_id,
    'pessoas_novas_total', (select count(*) from pessoas.pessoas) - (select p0 from _c))
  from crm.evento_jornada e1, crm.evento_jornada e2 where e1.fonte_evento_id = 'ensaio-20261007a-1' and e2.fonte_evento_id = 'ensaio-20261007a-2';

create temp table _c2 on commit drop as select (select count(*) from pessoas.pessoas) p0, (select count(*) from pessoas.identificadores) i0;
grant all on _c2 to service_role;
set local role service_role;
insert into _r values ('pessoa_existente.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  jsonb_build_array(jsonb_build_object('id', 'ensaio-20261007a-3', 'tipo', 'update', 'email', current_setting('ensaio.aluno'), 'nome', 'Outro Nome Qualquer'))));
insert into _r values ('sem_email_sem_fone.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  '[{"id":"ensaio-20261007a-4","tipo":"update","nome":"Sem Nada"}]'));
insert into _r values ('sem_email_fone_novo.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  '[{"id":"ensaio-20261007a-5","tipo":"update","telefone":"(98) 99123-4008","nome":"So Telefone"}]'));
reset role;
insert into _r select 'pessoa_existente', jsonb_build_object('resultado', e.resultado, 'pessoa', e.pessoa_id is not null,
    'pessoas_novas', (select count(*) from pessoas.pessoas) - (select p0 from _c2), 'ident_novos_total', (select count(*) from pessoas.identificadores) - (select i0 from _c2))
  from crm.evento_jornada e where e.fonte_evento_id = 'ensaio-20261007a-3';
insert into _r select 'sem_email', jsonb_agg(jsonb_build_object('id', e.fonte_evento_id, 'resultado', e.resultado, 'pessoa', e.pessoa_id is not null) order by e.id)
  from crm.evento_jornada e where e.fonte_evento_id in ('ensaio-20261007a-4', 'ensaio-20261007a-5');

set local role service_role;
insert into _r values ('telefone_depois.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  jsonb_build_array(jsonb_build_object('id', 'ensaio-20261007a-6', 'tipo', 'update', 'email', current_setting('ensaio.criado'), 'telefone', '(98) 99123-4009'))));
reset role;
insert into _r select 'telefone_depois', jsonb_build_object('resultado', e.resultado,
    'telefones', (select count(*) from pessoas.identificadores i where i.pessoa_id = e.pessoa_id and i.tipo = 'telefone' and i.origem = 'activecampaign'))
  from crm.evento_jornada e where e.fonte_evento_id = 'ensaio-20261007a-6';

create temp table _c3 on commit drop as select (select count(*) from pessoas.pessoas) p0;
grant all on _c3 to service_role;
set local role service_role;
insert into _r values ('unnichat.receber', public.crm_integracao_receber('unnichat', current_setting('ensaio.tku'),
  '[{"id":"ensaio-20261007a-u1","tipo":"teste","email":"unnichat.20261007a@exemplo.invalid","telefone":"(98) 99123-4010","nome":"Unni Ensaio"}]'));
reset role;
insert into _r select 'unnichat', jsonb_build_object('resultado', e.resultado, 'pessoa', e.pessoa_id is not null,
    'pessoas_novas', (select count(*) from pessoas.pessoas) - (select p0 from _c3))
  from crm.evento_jornada e where e.fonte_evento_id = 'ensaio-20261007a-u1';

update crm.config set activecampaign_cria_pessoa = false;
set local role service_role;
insert into _r values ('kill_switch.receber', public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
  '[{"id":"ensaio-20261007a-7","tipo":"subscribe","email":"desligado.20261007a@exemplo.invalid","nome":"Desligado Ensaio"}]'));
reset role;
insert into _r select 'kill_switch', jsonb_build_object('resultado', e.resultado, 'pessoa', e.pessoa_id is not null)
  from crm.evento_jornada e where e.fonte_evento_id = 'ensaio-20261007a-7';
update crm.config set activecampaign_cria_pessoa = true;

-- medida: receber com criação de pessoa, 2×
do $m$
declare t0 timestamptz; v jsonb; i int;
begin
  for i in 1..2 loop
    t0 := clock_timestamp();
    v := public.crm_integracao_receber('activecampaign', current_setting('ensaio.tk'),
      jsonb_build_array(jsonb_build_object('id', 'ensaio-20261007a-m' || i, 'tipo', 'subscribe',
        'email', 'medida' || i || '.20261007a@exemplo.invalid', 'telefone', '(98) 99123-401' || i, 'nome', 'Medida Ensaio')));
    insert into _r values ('medida.' || i, jsonb_build_object('ms', round(extract(epoch from clock_timestamp() - t0)::numeric * 1000, 1), 'r', v));
  end loop;
end
$m$;

insert into _r select 'negocios', jsonb_build_object('antes', (select negocios from _b), 'depois', (select count(*) from crm.negocio));
insert into _r select 'acl.depois', jsonb_agg(jsonb_build_object(p.oid::regprocedure::text, p.proacl::text) order by p.proname)
  from pg_proc p where p.oid in (to_regprocedure('crm.anexar_integracao(bigint,text)'), to_regprocedure('public.crm_integracao_receber(text,text,jsonb)'),
                                 to_regprocedure('public.crm_integracao_reprocessar(integer)'));
insert into _r select 'anon', jsonb_build_object(
    'anexar', has_function_privilege('anon', 'crm.anexar_integracao(bigint,text)', 'execute'),
    'anexar_auth', has_function_privilege('authenticated', 'crm.anexar_integracao(bigint,text)', 'execute'),
    'receber', has_function_privilege('anon', 'public.crm_integracao_receber(text,text,jsonb)', 'execute'),
    'receber_auth', has_function_privilege('authenticated', 'public.crm_integracao_receber(text,text,jsonb)', 'execute'),
    'reprocessar', has_function_privilege('anon', 'public.crm_integracao_reprocessar(integer)', 'execute'));
insert into _r select 'md5.novos', jsonb_object_agg(p.oid::regprocedure::text, md5(p.prosrc))
  from pg_proc p where p.oid in (to_regprocedure('crm.anexar_integracao(bigint,text)'), to_regprocedure('public.crm_integracao_receber(text,text,jsonb)'),
                                 to_regprocedure('public.crm_integracao_reprocessar(integer)'));
select k, v from _r;
rollback;

-- RESULTADO (07/10/2026, ~12:15 UTC, rodado via MCP com o fim trocado por `raise exception` com o conteúdo de _r = rollback
-- garantido; linhas de comentário/vazias removidas no envio). Eventos do AC chegando durante o ensaio (base: 83 eventos /
-- 35 e-mails sem pessoa; o reprocesso pegou os que chegaram até ali):
--   migracao.reprocesso   ac_sem_pessoa_com_email 0 · pessoa_criada 36 · anexados 65 · pessoas_novas 36 · pc_novas 36
--                         (0 com dono) · revisar 1
--   lead_novo             pessoa_criada · situacao ativa · ident [email/activecampaign, telefone/activecampaign] ·
--                         evento_lead 1 · pc dono_nulo · log contato integracao/activecampaign · negocio 0 · pessoas_novas 1
--                         receber → {novos 1, anexados 1, pessoas_criadas 1}
--   lead_repetido         anexado · mesma_pessoa true · pessoas_novas_total 1
--   pessoa_existente      anexado · pessoas_novas 0 · ident_novos 0
--   sem_email             sem e-mail e sem telefone → sem_identificador; sem e-mail com telefone novo → sem_pessoa (sem pessoa)
--   telefone_depois       anexado · telefones (origem activecampaign) 1
--   unnichat              sem_pessoa · pessoa false · pessoas_novas 0 · receber {anexados 0, pessoas_criadas 0}
--   kill_switch           sem_pessoa · pessoa false
--   medida (receber, 1 evento com criação)   18,6 ms / 14,8 ms
--   negocios              1029 → 1029
--   acl antes = depois    anexar {postgres=X/postgres}; receber/reprocessar {postgres=X/postgres,service_role=X/postgres};
--                         anon/authenticated sem EXECUTE nas 3
-- Depois do rollback (conferido): sem coluna activecampaign_cria_pessoa, anexar_integracao(bigint) de volta, receber com o
-- md5 antigo d4fef483…, 0 eventos 'ensaio-20261007a%', 0 pessoa_criada, 0 identificador/evento com origem activecampaign,
-- CHECK antigo, negócios 1029. NADA PERSISTIU.
