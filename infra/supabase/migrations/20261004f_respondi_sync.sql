-- 20261004f — Sincronização diária do Respondi (pg_cron → ops.cron_post → Edge Function respondi-sync).
--
-- A Edge loga no Respondi, percorre os workspaces 160/161/162/3380/574, baixa só o formulário cujo
-- respondents_count mudou, grava por public.fn_respondi_carga (20261004b), casa (fn_respondi_casar) e aplica
-- na ficha (fn_respondi_aplicar(false)). Cada execução é uma linha em respondi.sync_execucoes.
--
-- Revisão kirad (30/09) + decisão do João ("se for um dado muito certo pode colocar; se tiver dúvida, coloca, mas
-- coloca uma observação"):
--   * Toda aplicação grava respondi.aplicacoes.confianca ('certo' | 'a_confirmar') e motivo. Regra em
--     respondi.conferencia(uuid): CERTO = e-mail da resposta igual ao da ficha E CPF da resposta igual ao documento
--     da ficha — documento que não foi preenchido pelo próprio Respondi (senão o Respondi confirmaria a si mesmo).
--     Casado só por CPF (e-mail diferente) = a_confirmar.
--     Sócio: certo só se titular E sócio forem certos. Resto = a_confirmar, com o motivo.
--     A barreira existente fica: dado pessoal não vem de casamento só por telefone (20261004c/e).
--   * A tela lê as a_confirmar por public.fn_aluno_respondi_a_confirmar(aluno) (gate gp_eh_equipe).
--   * fn_respondi_aplicar mantém a assinatura (boolean): create or replace, sem sobrecarga. Recriada do corpo da
--     20261004c (a 20261004e não a redefine); o bloco 6 aborta se o corpo vivo no banco for outro.
--   * Trava de 2%: a base é o `casadas` da última execução 'ok' (não desarma no dia seguinte); na 1ª, a contagem
--     antes de casar. casar + trava na mesma transação: queda > 2% → rollback, status 'travada', HTTP 500.
--     Destravar depois de conferir que a queda é legítima:
--       update respondi.sync_execucoes set status = 'ok', casadas = <valor novo> where id = <id da travada>;
--   * Execução única por linha 'em_curso' (índice único parcial), sem advisory lock: funciona atrás do pooler.
--     'em_curso' com mais de 10 min vira 'erro' na execução seguinte.
--
-- As 5 perguntas (PROTOCOLO-SUSTENTABILIDADE):
--   1. Escala: ~390 respostas/mês; 25 formulários com resposta em 90 dias, de 249. Custo por formulário que mudou,
--      não pela base. respondi.conferencia roda só nos candidatos a aplicar (_c), não em todas as respostas.
--      sync_execucoes cresce 1 linha/dia. 10x = ~3.900/mês: cabe; o que não couber nos 110 s fica em `pendentes`.
--   2. Índice: escrita da carga é upsert pela pk (slug, uuid). conferencia: respostas pela pk, thb_alunos pela pk,
--      aplicacoes por aplicacoes_aluno_idx (aluno_id). Base da trava: sync_execucoes_ok_idx (parcial status='ok').
--      Execução única: sync_execucoes_em_curso_uk. Lista da tela: aplicacoes_aluno_idx.
--   3. Frequência: 1x/dia (09:10 UTC = 06:10 BRT); o dado muda ~13 respostas/dia.
--   4. Repetição: formulário com respondents_count igual ao n_respostas gravado não é baixado. O carga.py gravava
--      len(respostas concluídas); a Edge grava respondents_count → a 1ª execução rebaixa uma vez onde diferem.
--   5. Reversão: select cron.unschedule('respondi-sync'); (sem deploy). Aplicações revertíveis (20261004e);
--      confianca/motivo são colunas novas e anuláveis; carga é upsert, nunca apaga.
--
-- Credenciais (repo público: NENHUM valor aqui). O João cadastra à mão, no SQL editor:
--   select vault.create_secret('<e-mail da conta do Respondi>', 'respondi_email');
--   select vault.create_secret('<senha>', 'respondi_senha');
-- Sem as duas a Edge responde 503 {erro:'credencial ausente'}; sem respondi_sync_chave, 401.
--
-- Provas depois de aplicar (orquestrador):
--   select p.oid::regprocedure, p.proacl from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where p.proname in ('sync_credenciais','conferencia','fn_respondi_aplicar','fn_aluno_respondi_a_confirmar');
--   select jobname, schedule, command from cron.job where jobname = 'respondi-sync';
--   begin; explain (analyze, buffers) select public.fn_respondi_aplicar(true); rollback;
--   explain (analyze, buffers) select casadas from respondi.sync_execucoes where status = 'ok' order by terminada_em desc limit 1;
--   explain (analyze, buffers) select count(*) from respondi.respostas where aluno_id is not null;

-- 1. Chave do header (aleatória, gerada aqui). Idempotente.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'respondi_sync_chave') then
    perform vault.create_secret(
      replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', ''),
      'respondi_sync_chave', 'Header x-sync-chave do cron respondi-sync (Edge respondi-sync confere). 20261004f.');
  end if;
end $$;

-- 2. Credenciais para a Edge (lê via SUPABASE_DB_URL, mesmo modelo de fin.hotmart_credenciais_conta).
create or replace function respondi.sync_credenciais()
returns table(email text, senha text, chave text)
language sql
stable
security definer
set search_path to ''
as $function$
  select (select decrypted_secret from vault.decrypted_secrets where name = 'respondi_email'),
         (select decrypted_secret from vault.decrypted_secrets where name = 'respondi_senha'),
         (select decrypted_secret from vault.decrypted_secrets where name = 'respondi_sync_chave');
$function$;
-- Só postgres (dono): a Edge entra como postgres via SUPABASE_DB_URL; service_role não precisa ler senha.
revoke all on function respondi.sync_credenciais() from public, anon, authenticated, service_role;

-- 3. Execuções (trava de execução única + base da trava de 2%).
create table if not exists respondi.sync_execucoes (
  id            bigserial primary key,
  iniciada_em   timestamptz not null default now(),
  terminada_em  timestamptz,
  status        text not null default 'em_curso' check (status in ('em_curso','ok','travada','erro')),
  casadas       integer,
  baixados      integer,
  respostas     integer,
  pendentes     jsonb,
  ms            integer,
  motivo        text
);
create unique index if not exists sync_execucoes_em_curso_uk on respondi.sync_execucoes (status) where status = 'em_curso';
create index if not exists sync_execucoes_ok_idx on respondi.sync_execucoes (terminada_em desc) where status = 'ok';
alter table respondi.sync_execucoes enable row level security;
revoke all on table respondi.sync_execucoes from public, anon, authenticated;
revoke all on sequence respondi.sync_execucoes_id_seq from public, anon, authenticated;
grant all on table respondi.sync_execucoes to service_role;
grant all on sequence respondi.sync_execucoes_id_seq to service_role;

-- 4. Confiança de cada aplicação (null = anterior ao backfill 20261004h).
alter table respondi.aplicacoes add column if not exists confianca text check (confianca in ('certo','a_confirmar'));
alter table respondi.aplicacoes add column if not exists motivo text;

-- 5. Conferência de uma resposta: motivo de dúvida do titular e do sócio (null = certo).
--    Documento da ficha só confirma se NÃO veio do próprio Respondi (aplicação 'documento' não revertida).
--    CERTO exige e-mail da resposta = e-mail da ficha E CPF = documento (kirad 30/09: CPF sozinho não basta).
create or replace function respondi.conferencia(p_uuid uuid)
returns table(motivo_titular text, motivo_socio text)
language sql
stable
set search_path to ''
as $function$
  with x as (
    select r.aluno_id, r.casado_por, r.cpf, r.dados,
           coalesce((select lower(trim(a.email)) = lower(trim(r.email)) from public.thb_alunos a where a.id = r.aluno_id), false) email_t,
           coalesce((select lower(trim(a.email)) = lower(trim(r.dados->>'socio_email')) from public.thb_alunos a
                      where a.id = (r.dados->>'socio_aluno_id')::uuid), false) email_s,
           (select nullif(regexp_replace(coalesce(a.documento,''),'\D','','g'),'') from public.thb_alunos a
             where a.id = r.aluno_id
               and not exists (select 1 from respondi.aplicacoes p where p.aluno_id = a.id and p.campo = 'documento'
                                  and p.revertido_em is null and p.regra like 'respondi:%')) doc_t,
           (select nullif(regexp_replace(coalesce(a.documento,''),'\D','','g'),'') from public.thb_alunos a
             where a.id = (r.dados->>'socio_aluno_id')::uuid
               and not exists (select 1 from respondi.aplicacoes p where p.aluno_id = a.id and p.campo = 'documento'
                                  and p.revertido_em is null and p.regra like 'respondi:%')) doc_s
      from respondi.respostas r where r.uuid = p_uuid
  )
  select case when x.aluno_id is null then 'titular não casado'
              when x.email_t and x.cpf is not null and x.cpf = x.doc_t then null
              when x.casado_por = 'cpf' and not x.email_t then 'casado só por CPF, e-mail diferente'
              when x.casado_por = 'email' or x.email_t then 'casado só por e-mail; CPF sem conferência'
              when x.casado_por = 'telefone' then 'casado só por telefone'
              when x.casado_por = 'cpf' then 'casado por CPF que veio do próprio Respondi'
              else 'casamento sem conferência' end,
         case when not (x.dados ? 'socio_aluno_id') then null
              when x.email_s and regexp_replace(coalesce(x.dados->>'socio_cpf',''),'\D','','g') = x.doc_s then null
              when x.dados->>'socio_casado_por' = 'cpf' and not x.email_s then 'sócio casado só por CPF, e-mail diferente'
              when x.dados->>'socio_casado_por' = 'email' or x.email_s then 'sócio casado só por e-mail; CPF sem conferência'
              when x.dados->>'socio_casado_por' = 'telefone' then 'sócio casado só por telefone'
              when x.dados->>'socio_casado_por' = 'cpf' then 'sócio casado por CPF que veio do próprio Respondi'
              else 'sócio sem conferência' end
    from x;
$function$;
revoke all on function respondi.conferencia(uuid) from public, anon, authenticated;
grant execute on function respondi.conferencia(uuid) to service_role;

-- 6. fn_respondi_aplicar: mesma assinatura, corpo da 20261004c + confiança. Aborta se o corpo vivo for outro.
do $$
declare v text;
begin
  select md5(replace(prosrc, E'\r', '')) into v from pg_proc where oid = to_regprocedure('public.fn_respondi_aplicar(boolean)');
  if v is null then
    raise exception '20261004f: public.fn_respondi_aplicar(boolean) não existe';
  end if;
  -- d474… = corpo da 20261004c; 6a2531e8… = o mesmo corpo aplicado sem comentários (vivo em 01/10);
  -- b96750efcab083a362744dafae4fcc92 = este corpo (reaplicação)
  if v not in ('d4740970f69b7ee8bac00f070bdfd8fb', '6a2531e8ba47c77cc60d9325dc0eac8a', 'b96750efcab083a362744dafae4fcc92') then
    raise exception '20261004f: corpo vivo de fn_respondi_aplicar difere da 20261004c (md5 %); ler pg_get_functiondef e refazer', v;
  end if;
  if (select count(*) from pg_proc where proname = 'fn_respondi_aplicar' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception '20261004f: há sobrecarga de fn_respondi_aplicar';
  end if;
end $$;

create or replace function public.fn_respondi_aplicar(p_ensaio boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
#variable_conflict use_column
declare v jsonb;
begin
  -- candidatos: (aluno, campo, valor novo, resposta, regra), mais recente primeiro
  create temp table _c on commit drop as
  with r as (
    select r.*, f.familia from respondi.respostas r join respondi.formularios f on f.slug = r.form_slug
     where r.aluno_id is not null
  ), rp as (
    -- dado pessoal (CPF, endereço, profissão, redes) só quando o casamento foi por e-mail ou CPF:
    -- casado só por telefone, quem respondeu pode ser outra pessoa (secretária, cônjuge)
    select * from r where casado_por in ('email','cpf')
  ), cand as (
    select aluno_id, 'profissao' campo, left(trim(dados->>'profissao'),200) v, uuid, respondido_em, 'respondi:profissao' regra
      from rp where familia in ('questionario_inicial','cadastro') and length(trim(dados->>'profissao')) between 3 and 200
    union all
    select aluno_id, 'link_facebook', trim(dados->>'facebook'), uuid, respondido_em, 'respondi:facebook'
      from rp where trim(dados->>'facebook') ~* '^https?://([a-z0-9-]+\.)?(facebook\.com|fb\.com)/[^\s<>"]+$'
    union all
    select aluno_id, 'instagram_url',
           case when trim(dados->>'instagram') ~* '^https?://' then trim(dados->>'instagram')
                else 'https://instagram.com/' || regexp_replace(regexp_replace(trim(dados->>'instagram'),'^(www\.)?instagram\.com/','','i'),'^@','') end,
           uuid, respondido_em, 'respondi:instagram'
      from rp where trim(dados->>'instagram') ~* '^(@?[a-z0-9._]{3,30}|(https?://)?(www\.)?instagram\.com/[a-z0-9._]{3,30}/?(\?[^\s<>"]*)?)$'
    union all
    select aluno_id, 'youtube_url', trim(dados->>'youtube'), uuid, respondido_em, 'respondi:youtube'
      from rp where trim(dados->>'youtube') ~* '^https?://([a-z0-9-]+\.)?(youtube\.com|youtu\.be)/[^\s<>"]+$'
    union all
    select aluno_id, 'documento', cpf, uuid, respondido_em, 'respondi:cpf_valido'
      from rp where cpf is not null and (dados->>'cpf_valido')::boolean
    union all
    select aluno_id, 'nivel_resultado', dados->>'nivel_codigo', uuid, respondido_em, 'respondi:nivel_declarado'
      from r where familia = 'nivel' and dados ? 'nivel_codigo'
    union all
    select r.aluno_id, 'turma', t.id::text, r.uuid, r.respondido_em, 'respondi:turma_declarada'
      from r join public.thb_turmas t on t.codigo = r.dados->>'turma_codigo'
     where r.familia in ('nivel','questionario_inicial','socios','cadastro')
    union all
    -- sócio declarado pelo titular em "Inclusão sócios" (titular casado só por telefone pode ser outra pessoa)
    select (dados->>'socio_aluno_id')::uuid, 'socio_de_aluno_id', aluno_id::text, uuid, respondido_em, 'respondi:inclusao_socio'
      from rp where familia = 'socios' and dados ? 'socio_aluno_id'
    union all
    select (dados->>'socio_aluno_id')::uuid, 'documento', regexp_replace(dados->>'socio_cpf','\D','','g'), uuid, respondido_em, 'respondi:cpf_socio_valido'
      from r where familia = 'socios' and dados ? 'socio_aluno_id' and (dados->>'socio_cpf_valido')::boolean
       and dados->>'socio_casado_por' in ('email','cpf')
  )
  select distinct on (aluno_id, campo) * from cand where v is not null and v <> ''
   order by aluno_id, campo, respondido_em desc;

  -- endereço: bloco inteiro, só para ficha sem endereço nenhum
  create temp table _e on commit drop as
  with r as (
    select r.aluno_id alvo, r.uuid, r.respondido_em, r.dados, '' p from respondi.respostas r
      join respondi.formularios f on f.slug=r.form_slug and f.familia in ('cadastro','evento')
     where r.aluno_id is not null and r.casado_por in ('email','cpf')
    union all
    select (r.dados->>'socio_aluno_id')::uuid, r.uuid, r.respondido_em, r.dados, 'socio_' from respondi.respostas r
      join respondi.formularios f on f.slug=r.form_slug and f.familia='socios'
     where r.dados ? 'socio_aluno_id' and r.dados->>'socio_casado_por' in ('email','cpf')
  )
  select distinct on (alvo) alvo aluno_id, uuid, respondido_em, (p = 'socio_') socio,
         nullif(regexp_replace(coalesce(dados->>(p||'cep'),''),'\D','','g'),'') cep,
         nullif(trim(dados->>(p||'endereco')),'') logradouro,
         nullif(trim(dados->>(p||'numero')),'') numero,
         nullif(trim(dados->>(p||'complemento')),'') complemento,
         nullif(trim(dados->>(p||'bairro')),'') bairro,
         nullif(trim(dados->>(p||'cidade')),'') cidade,
         dados->>(p||'uf_sigla') uf
    from r
   where length(regexp_replace(coalesce(dados->>(p||'cep'),''),'\D','','g')) = 8
     and length(trim(coalesce(dados->>(p||'endereco'),''))) >= 3
     and length(trim(coalesce(dados->>(p||'cidade'),''))) >= 2
   order by alvo, respondido_em desc;

  -- o que muda de fato (campo vazio hoje)
  create temp table _m on commit drop as
  select a.id aluno_id, c.campo,
         case c.campo when 'profissao' then a.profissao when 'link_facebook' then a.link_facebook
              when 'instagram_url' then a.instagram_url when 'youtube_url' then a.youtube_url
              when 'documento' then a.documento when 'nivel_resultado' then a.nivel_resultado
              when 'turma' then (select case when t.tipo='aurum' then a.turma_aurum_id else a.turma_id end::text
                                   from public.thb_turmas t where t.id = c.v::smallint)
              when 'socio_de_aluno_id' then a.socio_de_aluno_id::text end antes,
         c.v novo, c.uuid, c.regra,
         -- 20261004f: observação de confiança (null = certo). Sócio: vale a do titular E a do sócio.
         case when c.regra in ('respondi:inclusao_socio','respondi:cpf_socio_valido')
              then nullif(concat_ws(' · ', 'titular: ' || k.motivo_titular, k.motivo_socio), '')
              else coalesce(k.motivo_titular, 'resposta sem conferência') end motivo
    from _c c join public.thb_alunos a on a.id = c.aluno_id
    left join lateral respondi.conferencia(c.uuid) k on true
   -- só ativos: update em cancelado dispara trg_aluno_retornou e pode reativá-lo
   where a.cancelado_em is null and case c.campo
           when 'profissao' then nullif(trim(a.profissao),'') is null
           when 'link_facebook' then nullif(trim(a.link_facebook),'') is null
           when 'instagram_url' then nullif(trim(a.instagram_url),'') is null
           when 'youtube_url' then nullif(trim(a.youtube_url),'') is null
           when 'documento' then nullif(regexp_replace(coalesce(a.documento,''),'\D','','g'),'') is null
                and not exists (select 1 from public.thb_alunos x where x.id <> a.id and regexp_replace(coalesce(x.documento,''),'\D','','g') = c.v)
                and not exists (select 1 from _c y where y.campo = 'documento' and y.v = c.v and y.aluno_id <> c.aluno_id)
           when 'nivel_resultado' then a.nivel_resultado is null
           -- turma Aurum vai para turma_aurum_id, THB para turma_id
           when 'turma' then (select case when t.tipo='aurum' then a.turma_aurum_id is null else a.turma_id is null end
                                from public.thb_turmas t where t.id = c.v::smallint)
           when 'socio_de_aluno_id' then a.eh_socio and a.socio_de_aluno_id is null and c.v <> a.id::text
                and not exists (select 1 from public.thb_alunos t where t.id = c.v::uuid and t.socio_de_aluno_id = a.id)
                and not exists (select 1 from _c y where y.campo = 'socio_de_aluno_id' and y.aluno_id = c.v::uuid and y.v = a.id::text)
         end
  union all
  select a.id, 'endereco', a.estado, concat_ws(' | ', e.cep, e.logradouro, e.numero, e.complemento, e.bairro, e.cidade, coalesce(nullif(trim(a.estado),''), e.uf)), e.uuid, 'respondi:endereco',
         case when e.socio then nullif(concat_ws(' · ', 'titular: ' || k.motivo_titular, k.motivo_socio), '')
              else coalesce(k.motivo_titular, 'resposta sem conferência') end
    from _e e join public.thb_alunos a on a.id = e.aluno_id
    left join lateral respondi.conferencia(e.uuid) k on true
   where a.cancelado_em is null and nullif(trim(a.cep),'') is null and nullif(trim(a.endereco_logradouro),'') is null and nullif(trim(a.cidade),'') is null;

  select jsonb_build_object('ensaio', p_ensaio,
           'por_campo', (select jsonb_object_agg(campo, n) from (select campo, count(*) n from _m group by 1) x),
           'a_confirmar', coalesce((select jsonb_object_agg(campo, n) from (select campo, count(*) n from _m where motivo is not null group by 1) x), '{}'::jsonb),
           'alunos_ativos_tocados', (select count(distinct m.aluno_id) from _m m join public.thb_alunos a on a.id=m.aluno_id and a.cancelado_em is null))
    into v;

  if p_ensaio then return v; end if;

  insert into respondi.aplicacoes (aluno_id, campo, valor_antes, valor_novo, resposta_uuid, regra, confianca, motivo)
  select aluno_id, campo, antes, novo, uuid, regra, case when motivo is null then 'certo' else 'a_confirmar' end, motivo from _m;

  update public.thb_alunos a set profissao = m.novo from _m m where m.aluno_id=a.id and m.campo='profissao';
  update public.thb_alunos a set link_facebook = m.novo from _m m where m.aluno_id=a.id and m.campo='link_facebook';
  update public.thb_alunos a set instagram_url = m.novo from _m m where m.aluno_id=a.id and m.campo='instagram_url';
  update public.thb_alunos a set youtube_url = m.novo from _m m where m.aluno_id=a.id and m.campo='youtube_url';
  update public.thb_alunos a set documento = m.novo, tipo_documento = 'CPF' from _m m where m.aluno_id=a.id and m.campo='documento';
  update public.thb_alunos a set nivel_resultado = m.novo from _m m where m.aluno_id=a.id and m.campo='nivel_resultado';
  update public.thb_alunos a set turma_id = t.id from _m m join public.thb_turmas t on t.id = m.novo::smallint and t.tipo <> 'aurum'
   where m.aluno_id=a.id and m.campo='turma';
  update public.thb_alunos a set turma_aurum_id = t.id from _m m join public.thb_turmas t on t.id = m.novo::smallint and t.tipo = 'aurum'
   where m.aluno_id=a.id and m.campo='turma';
  update public.thb_alunos a set socio_de_aluno_id = m.novo::uuid, socio_de_nome = tit.nome
    from _m m join public.thb_alunos tit on tit.id = m.novo::uuid
   where m.aluno_id=a.id and m.campo='socio_de_aluno_id';
  update public.thb_alunos a set cep=e.cep, endereco_logradouro=e.logradouro, endereco_numero=e.numero,
         endereco_complemento=e.complemento, bairro=e.bairro, cidade=e.cidade, estado=coalesce(nullif(trim(a.estado),''), e.uf)
    from _e e join _m m on m.aluno_id=e.aluno_id and m.campo='endereco'
   where a.id=e.aluno_id;

  -- sócio herda do titular turma e data de entrada quando vazias
  insert into respondi.aplicacoes (aluno_id, campo, valor_antes, valor_novo, regra, confianca, motivo)
  select s.id, 'turma', null, t.turma_id::text, 'heranca:turma_do_titular',
         case when exists (select 1 from respondi.aplicacoes p where p.aluno_id = s.id and p.campo = 'socio_de_aluno_id'
                and p.revertido_em is null and p.confianca = 'a_confirmar' and p.valor_novo = t.id::text) then 'a_confirmar' else 'certo' end,
         case when exists (select 1 from respondi.aplicacoes p where p.aluno_id = s.id and p.campo = 'socio_de_aluno_id'
                and p.revertido_em is null and p.confianca = 'a_confirmar' and p.valor_novo = t.id::text) then 'herdado do titular; vínculo de sócio a confirmar' end
    from public.thb_alunos s join public.thb_alunos t on t.id=s.socio_de_aluno_id
   where s.eh_socio and s.cancelado_em is null and s.turma_id is null and t.turma_id is not null;
  update public.thb_alunos s set turma_id = t.turma_id
    from public.thb_alunos t where t.id=s.socio_de_aluno_id and s.eh_socio and s.cancelado_em is null and s.turma_id is null and t.turma_id is not null;
  insert into respondi.aplicacoes (aluno_id, campo, valor_antes, valor_novo, regra, confianca, motivo)
  select s.id, 'data_entrada_thb', null, t.data_entrada_thb::text, 'heranca:data_entrada_do_titular',
         case when exists (select 1 from respondi.aplicacoes p where p.aluno_id = s.id and p.campo = 'socio_de_aluno_id'
                and p.revertido_em is null and p.confianca = 'a_confirmar' and p.valor_novo = t.id::text) then 'a_confirmar' else 'certo' end,
         case when exists (select 1 from respondi.aplicacoes p where p.aluno_id = s.id and p.campo = 'socio_de_aluno_id'
                and p.revertido_em is null and p.confianca = 'a_confirmar' and p.valor_novo = t.id::text) then 'herdado do titular; vínculo de sócio a confirmar' end
    from public.thb_alunos s join public.thb_alunos t on t.id=s.socio_de_aluno_id
   where s.eh_socio and s.cancelado_em is null and s.data_entrada_thb is null and t.data_entrada_thb is not null;
  update public.thb_alunos s set data_entrada_thb = t.data_entrada_thb
    from public.thb_alunos t where t.id=s.socio_de_aluno_id and s.eh_socio and s.cancelado_em is null and s.data_entrada_thb is null and t.data_entrada_thb is not null;

  return v || jsonb_build_object('aplicadas', (select count(*) from respondi.aplicacoes where aplicado_em >= now() - interval '1 minute'));
end;
$function$;
revoke all on function public.fn_respondi_aplicar(boolean) from public, anon, authenticated;
grant execute on function public.fn_respondi_aplicar(boolean) to service_role;

-- 7. Tela: aplicações a confirmar do aluno (contrato: campo, confianca, motivo, formulario, respondido_em).
create or replace function public.fn_aluno_respondi_a_confirmar(p_aluno_id uuid)
returns table(campo text, confianca text, motivo text, formulario text, respondido_em timestamptz)
language plpgsql
stable
security definer
set search_path to ''
as $function$
#variable_conflict use_column
begin
  if not coalesce(public.gp_eh_equipe(), false) then return; end if;
  return query
  select p.campo, p.confianca, p.motivo, f.nome, r.respondido_em
    from respondi.aplicacoes p
    left join respondi.respostas r on r.uuid = p.resposta_uuid
    left join respondi.formularios f on f.slug = r.form_slug
   where p.aluno_id = p_aluno_id and p.revertido_em is null and p.confianca = 'a_confirmar'
   order by p.aplicado_em desc
   limit 100;
end;
$function$;
revoke all on function public.fn_aluno_respondi_a_confirmar(uuid) from public, anon;
grant execute on function public.fn_aluno_respondi_a_confirmar(uuid) to authenticated, service_role;

-- 8. Cron diário, idempotente. Segredo lido do Vault dentro do command (nunca literal).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'respondi-sync') then
    perform cron.unschedule('respondi-sync');
  end if;
end $$;
select cron.schedule('respondi-sync', '10 9 * * *', $cron$
  select ops.cron_post('respondi-sync',
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/respondi-sync',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'respondi_sync_chave')),
    timeout_milliseconds := 150000)
$cron$);

-- 9. Asserts: funções fechadas (anon nunca; authenticated só na RPC da tela), tabela fechada, command sem segredo.
do $$
declare v_acl text; v_cmd text; f text;
begin
  select coalesce(proacl::text, 'null') into v_acl from pg_proc where oid = 'respondi.sync_credenciais()'::regprocedure;
  if v_acl = 'null' or v_acl ~ 'service_role=' then
    raise exception '20261004f: sync_credenciais executável por service_role/PUBLIC: %', v_acl;
  end if;
  foreach f in array array['respondi.sync_credenciais()', 'respondi.conferencia(uuid)', 'public.fn_respondi_aplicar(boolean)'] loop
    select coalesce(proacl::text, 'null') into v_acl from pg_proc where oid = f::regprocedure;
    if v_acl = 'null' or v_acl ~ '(^|[{,])=X' or v_acl ~ '(anon|authenticated)=' then
      raise exception '20261004f: proacl de % aberto: %', f, v_acl;
    end if;
  end loop;
  select coalesce(proacl::text, 'null') into v_acl from pg_proc where oid = 'public.fn_aluno_respondi_a_confirmar(uuid)'::regprocedure;
  if v_acl = 'null' or v_acl ~ '(^|[{,])=X' or v_acl ~ 'anon=' then
    raise exception '20261004f: proacl de fn_aluno_respondi_a_confirmar aberto: %', v_acl;
  end if;
  if has_table_privilege('anon', 'respondi.sync_execucoes', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'respondi.sync_execucoes', 'select,insert,update,delete') then
    raise exception '20261004f: respondi.sync_execucoes acessível a anon/authenticated';
  end if;
  select command into v_cmd from cron.job where jobname = 'respondi-sync';
  if v_cmd is null or v_cmd !~ 'ops\.cron_post' or v_cmd ~ '[0-9a-f]{64}' then
    raise exception '20261004f: command do cron respondi-sync fora do padrão';
  end if;
end $$;
