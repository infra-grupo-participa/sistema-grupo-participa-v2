-- Respondi → ficha do aluno.
--
-- fn_respondi_casar: liga cada resposta a um aluno (thb_alunos), na ordem
--   Se e-mail, CPF e telefone apontam para alunos diferentes, a resposta fica sem aluno.
--   Dado pessoal (CPF, endereço, profissão, redes) só entra de casamento por e-mail ou CPF.
--   1) e-mail igual (lower/trim), só se um único aluno tem esse e-mail;
--   2) CPF válido igual ao documento;
--   3) telefone: últimos 11 dígitos iguais, só se aponta para um único aluno.
--   Em "Inclusão sócios", dados.socio_aluno_id recebe o aluno declarado como sócio
--   (e-mail, CPF ou telefone do sócio), pelo mesmo critério.
--
-- fn_respondi_aplicar: preenche na ficha SÓ campo vazio, com a resposta mais recente,
--   e grava cada alteração em respondi.aplicacoes (antes/depois/regra/resposta).
--   Campos: profissão, Facebook, Instagram, YouTube, endereço completo (só quando a
--   ficha não tem endereço nenhum), documento (CPF válido), nível de resultado,
--   turma, titular do sócio. Espaço de instrução e plano NÃO são tocados: dependem
--   da compra, não do que o aluno declarou.
--   Sócio herda do titular turma e data de entrada quando estiverem vazias (decisão do João, 30/09/2026).
--
-- As duas são idempotentes e só executáveis pela service role.

create or replace function public.fn_respondi_casar()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare v jsonb;
begin
  create temp table _al on commit drop as
    select a.id,
           nullif(lower(trim(a.email)),'') as email,
           nullif(regexp_replace(coalesce(a.documento,''),'\D','','g'),'') as cpf,
           nullif(right(regexp_replace(coalesce(a.telefone_e164, a.telefone,''),'\D','','g'),11),'') as fone,
           (a.cancelado_em is null) as ativo
      from public.thb_alunos a;

  -- chave → aluno, só quando única (preferindo ativo quando há ativo e cancelado)
  create temp table _k on commit drop as
  with k as (
    select 'email' t, email k, id, ativo from _al where email is not null
    union all select 'cpf', cpf, id, ativo from _al where length(cpf)=11
    union all select 'fone', fone, id, ativo from _al where length(fone)>=10
  ), r as (
    select t, k, id, ativo,
           count(*) over (partition by t,k) n,
           count(*) filter (where ativo) over (partition by t,k) na
      from k
  )
  select t, k, id from r where n = 1 or (na = 1 and ativo);

  -- e-mail, CPF e telefone que apontam para alunos DIFERENTES = não casa (seria dado de uma pessoa na ficha de outra)
  create temp table _mt on commit drop as
  select r2.uuid,
         case when (e.id is null or e.id = coalesce(e.id, c.id, f.id)) and (c.id is null or c.id = coalesce(e.id, c.id, f.id))
                   and (f.id is null or f.id = coalesce(e.id, c.id, f.id)) then coalesce(e.id, c.id, f.id) end id,
         case when e.id is not null then 'email' when c.id is not null then 'cpf' when f.id is not null then 'telefone' end por
    from respondi.respostas r2
    left join _k e on e.t='email' and e.k = lower(trim(r2.email))
    left join _k c on c.t='cpf'   and c.k = regexp_replace(r2.cpf,'\D','','g')
    left join _k f on f.t='fone'  and f.k = right(regexp_replace(r2.telefone,'\D','','g'),11);

  -- também desfaz o vínculo que deixou de valer
  update respondi.respostas r
     set aluno_id = m.id, casado_por = case when m.id is null then null else m.por end
    from _mt m
   where m.uuid = r.uuid
     and (r.aluno_id is distinct from m.id or r.casado_por is distinct from case when m.id is null then null else m.por end);

  update respondi.respostas r
     set dados = case when m.id is null or m.id = r.aluno_id then r.dados - 'socio_aluno_id' - 'socio_casado_por'
                      else r.dados || jsonb_build_object('socio_aluno_id', m.id, 'socio_casado_por', m.por) end
    from (
      select r2.uuid,
             case when (e.id is null or e.id = coalesce(e.id, c.id, f.id)) and (c.id is null or c.id = coalesce(e.id, c.id, f.id))
                       and (f.id is null or f.id = coalesce(e.id, c.id, f.id)) then coalesce(e.id, c.id, f.id) end id,
             case when e.id is not null then 'email' when c.id is not null then 'cpf' else 'telefone' end por
        from respondi.respostas r2
        join respondi.formularios fo on fo.slug = r2.form_slug and fo.familia = 'socios'
        left join _k e on e.t='email' and e.k = nullif(lower(trim(r2.dados->>'socio_email')),'')
        left join _k c on c.t='cpf'   and c.k = nullif(regexp_replace(coalesce(r2.dados->>'socio_cpf',''),'\D','','g'),'')
        left join _k f on f.t='fone'  and f.k = nullif(right(regexp_replace(coalesce(r2.dados->>'socio_telefone',''),'\D','','g'),11),'')
    ) m
   where m.uuid = r.uuid
     and ((r.dados->>'socio_aluno_id') is distinct from case when m.id is null or m.id = r.aluno_id then null else m.id::text end
          or (r.dados->>'socio_casado_por') is distinct from case when m.id is null or m.id = r.aluno_id then null else m.por end);

  select jsonb_build_object(
    'respostas', count(*),
    'casadas', count(*) filter (where aluno_id is not null),
    'por_email', count(*) filter (where casado_por='email'),
    'por_cpf', count(*) filter (where casado_por='cpf'),
    'por_telefone', count(*) filter (where casado_por='telefone'),
    'socio_casado', count(*) filter (where dados ? 'socio_aluno_id'),
    'alunos_ativos_com_resposta', (select count(distinct r.aluno_id) from respondi.respostas r join public.thb_alunos a on a.id=r.aluno_id and a.cancelado_em is null)
  ) into v from respondi.respostas;
  return v;
end;
$function$;
revoke all on function public.fn_respondi_casar() from public, anon, authenticated;
grant execute on function public.fn_respondi_casar() to service_role;

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
  select distinct on (alvo) alvo aluno_id, uuid, respondido_em,
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
         c.v novo, c.uuid, c.regra
    from _c c join public.thb_alunos a on a.id = c.aluno_id
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
  select a.id, 'endereco', a.estado, concat_ws(' | ', e.cep, e.logradouro, e.numero, e.complemento, e.bairro, e.cidade, coalesce(nullif(trim(a.estado),''), e.uf)), e.uuid, 'respondi:endereco'
    from _e e join public.thb_alunos a on a.id = e.aluno_id
   where a.cancelado_em is null and nullif(trim(a.cep),'') is null and nullif(trim(a.endereco_logradouro),'') is null and nullif(trim(a.cidade),'') is null;

  select jsonb_build_object('ensaio', p_ensaio,
           'por_campo', (select jsonb_object_agg(campo, n) from (select campo, count(*) n from _m group by 1) x),
           'alunos_ativos_tocados', (select count(distinct m.aluno_id) from _m m join public.thb_alunos a on a.id=m.aluno_id and a.cancelado_em is null))
    into v;

  if p_ensaio then return v; end if;

  insert into respondi.aplicacoes (aluno_id, campo, valor_antes, valor_novo, resposta_uuid, regra)
  select aluno_id, campo, antes, novo, uuid, regra from _m;

  update public.thb_alunos a set profissao = m.novo from _m m where m.aluno_id=a.id and m.campo='profissao';
  update public.thb_alunos a set link_facebook = m.novo from _m m where m.aluno_id=a.id and m.campo='link_facebook';
  update public.thb_alunos a set instagram_url = m.novo from _m m where m.aluno_id=a.id and m.campo='instagram_url';
  update public.thb_alunos a set youtube_url = m.novo from _m m where m.aluno_id=a.id and m.campo='youtube_url';
  update public.thb_alunos a set documento = m.novo, tipo_documento = 'cpf' from _m m where m.aluno_id=a.id and m.campo='documento';
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
  insert into respondi.aplicacoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select s.id, 'turma', null, t.turma_id::text, 'heranca:turma_do_titular'
    from public.thb_alunos s join public.thb_alunos t on t.id=s.socio_de_aluno_id
   where s.eh_socio and s.cancelado_em is null and s.turma_id is null and t.turma_id is not null;
  update public.thb_alunos s set turma_id = t.turma_id
    from public.thb_alunos t where t.id=s.socio_de_aluno_id and s.eh_socio and s.cancelado_em is null and s.turma_id is null and t.turma_id is not null;
  insert into respondi.aplicacoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select s.id, 'data_entrada_thb', null, t.data_entrada_thb::text, 'heranca:data_entrada_do_titular'
    from public.thb_alunos s join public.thb_alunos t on t.id=s.socio_de_aluno_id
   where s.eh_socio and s.cancelado_em is null and s.data_entrada_thb is null and t.data_entrada_thb is not null;
  update public.thb_alunos s set data_entrada_thb = t.data_entrada_thb
    from public.thb_alunos t where t.id=s.socio_de_aluno_id and s.eh_socio and s.cancelado_em is null and s.data_entrada_thb is null and t.data_entrada_thb is not null;

  return v || jsonb_build_object('aplicadas', (select count(*) from respondi.aplicacoes where aplicado_em >= now() - interval '1 minute'));
end;
$function$;
revoke all on function public.fn_respondi_aplicar(boolean) from public, anon, authenticated;
grant execute on function public.fn_respondi_aplicar(boolean) to service_role;
