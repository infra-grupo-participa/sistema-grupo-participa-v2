-- 20261015230200: importar o CSV do Studio grava NULL (e não 0) quando chat ou reações não vêm no arquivo.
--
-- POR QUE (correção pedida pelo orquestrador em 15/10/2026): dados_black_live_importar (20261015220000) fazia
-- coalesce(chat, 0) e coalesce(reacoes, 0). Coluna ausente ou célula vazia do CSV virava 0 no banco, e 0 é um número
-- ("ninguém escreveu no chat"), não a ausência do número. A tela somava esse 0 como dado. A regra do desenho é: ausência
-- é NULL (o mesmo que a origem 'api' já faz com reações). A leitura (dados_black_lives, dados_black_live_detalhe) já trata
-- NULL: sum() sem nenhuma linha preenchida devolve null e o detalhe devolve a chave com null.
--
-- O QUE FAZ (só o corpo de public.dados_black_live_importar; assinatura, grants, security definer e search_path não mudam)
--   a. Prévia e gravação: (e ->> 'chat')::int e (e ->> 'reacoes')::int, sem coalesce. Chave ausente = NULL.
--   b. A comparação da prévia (alteradas) já usava "is distinct from", que trata NULL: reenviar o mesmo arquivo continua
--      dando alteradas = 0; trocar 0 por ausente (ou o contrário) conta como alteração.
--   c. A validação não muda: chat e reacoes inteiros >= 0 ou ausentes. Um "chat": null explícito continua recusado (22023);
--      o front omite a chave.
--   d. Dados já gravados NÃO são tocados. Conferido em produção contra os 3 CSVs do Studio (6/10, 8/10 e 13/10): os arquivos
--      não têm nenhuma célula vazia de chat nem de reações (298 linhas, todas preenchidas), então os 0 gravados são 0 do
--      arquivo. Nada a corrigir.
--
-- AS 5 PERGUNTAS
--   escala: a importação é feita por um master, até 2.000 linhas por chamada, ~100 por live. Não cresce com a base.
--   índice: lê black_live_minuto pela PK (video_id, origem, seg); a consulta não muda de forma. Plano no .explain.md.
--   frequência: manual (botão de importar da aba Lives), poucas vezes por live.
--   repetição: uma chamada de prévia e uma de gravação por arquivo; idempotente.
--   reversão: 20261015230200_reversao.sql devolve o corpo anterior (md5 do prosrc 277d99ca683afb3d11c33663106ffb9a).
set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('public.dados_black_live_importar(text,text,jsonb,boolean)') is null then
    raise exception '20261015230200: aplique antes 20261015220000 (dados_black_live_importar ausente)';
  end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure)
       <> '277d99ca683afb3d11c33663106ffb9a' then
    raise exception '20261015230200: dados_black_live_importar não está no corpo esperado (alguém mudou depois da 20261015220000)';
  end if;
end
$g$;

create or replace function public.dados_black_live_importar(p_chave text, p_video_id text, p_linhas jsonb, p_confirmar boolean)
returns jsonb
language plpgsql security definer set search_path = '' as $function$
declare
  d dados.dashboards := dados.black_evento_master(p_chave);   -- 42501 se não for master, P0002 fora da Black
  v_n int; v_invalidas int; v_dup int; v_alt int; v_exist int;
  v_pico int; v_pico_seg int; v_dur int;
begin
  if not exists (select 1 from dados.black_lives l where l.video_id = p_video_id and l.chave = d.chave and l.ativo) then
    raise exception 'live não cadastrada' using errcode = 'P0002';
  end if;
  if jsonb_typeof(p_linhas) is distinct from 'array' then
    raise exception 'p_linhas deve ser uma lista' using errcode = '22023';
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n < 1 or v_n > 2000 then
    raise exception 'p_linhas deve ter de 1 a 2000 linhas' using errcode = '22023';
  end if;
  -- toda linha: objeto com seg e espectadores inteiros >= 0; chat e reacoes inteiros >= 0 ou ausentes
  select count(*) into v_invalidas
    from jsonb_array_elements(p_linhas) e
   where jsonb_typeof(e) <> 'object'
      or jsonb_typeof(e -> 'seg') is distinct from 'number' or (e ->> 'seg') !~ '^[0-9]{1,7}$'
      or jsonb_typeof(e -> 'espectadores') is distinct from 'number' or (e ->> 'espectadores') !~ '^[0-9]{1,7}$'
      or (e ? 'chat' and (jsonb_typeof(e -> 'chat') is distinct from 'number' or (e ->> 'chat') !~ '^[0-9]{1,7}$'))
      or (e ? 'reacoes' and (jsonb_typeof(e -> 'reacoes') is distinct from 'number' or (e ->> 'reacoes') !~ '^[0-9]{1,7}$'));
  if v_invalidas > 0 then
    raise exception 'p_linhas tem % linha(s) inválida(s)', v_invalidas using errcode = '22023';
  end if;

  -- sem tabela temporária (a função roda mais de uma vez na mesma transação nos ensaios): o CTE "n" repete em cada consulta
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores
               from jsonb_array_elements(p_linhas) e)
  select count(*) - count(distinct seg), max(espectadores), max(seg) + 60,
         min(seg) filter (where espectadores = (select max(espectadores) from n))
    into v_dup, v_pico, v_dur, v_pico_seg from n;
  if v_dup > 0 then
    raise exception 'p_linhas tem seg repetido' using errcode = '22023';
  end if;
  select count(*) into v_exist from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
  with n as (select (e ->> 'seg')::int as seg, (e ->> 'espectadores')::int as espectadores,
                    (e ->> 'chat')::int as chat, (e ->> 'reacoes')::int as reacoes
               from jsonb_array_elements(p_linhas) e)
  select count(*) into v_alt
    from n
    full join (select seg, espectadores, chat, reacoes from dados.black_live_minuto
                where video_id = p_video_id and origem = 'studio') o using (seg)
   where n.espectadores is null or o.espectadores is null
      or n.espectadores is distinct from o.espectadores or n.chat is distinct from o.chat or n.reacoes is distinct from o.reacoes;

  if p_confirmar is true and v_alt > 0 then
    delete from dados.black_live_minuto where video_id = p_video_id and origem = 'studio';
    insert into dados.black_live_minuto (video_id, origem, seg, espectadores, chat, reacoes)
    select p_video_id, 'studio', (e ->> 'seg')::int, (e ->> 'espectadores')::int,
           (e ->> 'chat')::int, (e ->> 'reacoes')::int
      from jsonb_array_elements(p_linhas) e;
    update dados.black_lives set atualizado_em = now() where video_id = p_video_id;
  end if;
  return jsonb_build_object('linhas', v_n, 'pico', v_pico, 'pico_seg', v_pico_seg, 'duracao_seg', v_dur,
                            'existentes', v_exist, 'alteradas', v_alt, 'gravado', (p_confirmar is true and v_alt > 0));
end
$function$;

do $conf$
declare v_src text; v_acl text;
begin
  select p.prosrc, p.proacl::text into v_src, v_acl from pg_proc p
   where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure;
  if v_src ~ 'coalesce' then
    raise exception '20261015230200: o corpo novo ainda tem coalesce';
  end if;
  if has_function_privilege('anon', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute')
     or has_function_privilege('service_role', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_black_live_importar(text,text,jsonb,boolean)', 'execute') then
    raise exception '20261015230200: grants de dados_black_live_importar mudaram';
  end if;
  if not exists (select 1 from pg_proc p where p.oid = 'public.dados_black_live_importar(text,text,jsonb,boolean)'::regprocedure
                    and p.prosecdef and p.proconfig @> array['search_path=""']) then
    raise exception '20261015230200: dados_black_live_importar perdeu security definer ou search_path vazio';
  end if;
end
$conf$;
