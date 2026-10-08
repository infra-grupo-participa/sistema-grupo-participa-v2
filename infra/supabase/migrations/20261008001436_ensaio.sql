-- 20261008001436 (20261008rg) — ENSAIO (produção, termina em ROLLBACK). Roda a migration inteira e prova cada regra com JWT real.
-- Esperado: Jonathan/Arthur/Victor Hugo gestor nas duas regras; Elaine/Marcio/Aldri gestor do CRM e NÃO de Estratégias
-- (transformar → 'Só o gestor comercial transforma em ação.'); Marcos e Jusy só vendedor, 0 linhas de contato de outro
-- vendedor no crm_log; visualizador → 42501; nenhum e-mail aberto no resumo; resumo gravado já mascarado; distribuição ok.
begin;
-- 20261008rg — CRM: Registro (crm_log) com visibilidade no banco e sem dado pessoal; regra única de gestor; distribuição
-- conferida pela mesma regra de vendedor ativo. Onda 1 da auditoria do CRM Comercial (itens 4 e 5), ok do Arthur em 07/10/2026.
--
-- 1. crm.mascara_texto(text): mascara e-mail (formato de pessoas.mascara_email: a***@dominio) e sequência de 10+ dígitos
--    (telefone/CPF; formato de pessoas.mascara_fim: só os 4 últimos). Não toca UUID, código de transação (HP…), data nem
--    hora. Regra copiada (não chamada) porque o authenticated não tem USAGE no schema pessoas.
-- 2. crm.tg_log_mascara: BEFORE INSERT em crm.log. Todo escritor do log (crm.tg_log, crm.log_registrar e quem mais
--    inserir) grava o resumo já mascarado. O log continua imutável: as linhas antigas são mascaradas na LEITURA (item 3).
-- 3. public.crm_log: assinatura nova (+ p_antes = cursor) → drop + create.
--    * visibilidade explícita no corpo, igual à policy crm.log.log_ler (que já valia, pois crm_log é SECURITY INVOKER):
--      gestor (crm.eh_gestor) vê tudo; vendedor vê o que fez, as pessoas que pode ver (crm.pessoas_do_vendedor: contato
--      sem dono, contato dele, contato de negócio dele) e — novo, na função e na policy — os negócios de que é dono;
--    * limite no servidor (máx. 500 por página) e paginação por cursor (p_antes = id da última linha recebida);
--    * resumo e mudanças passam por crm.mascara_texto na leitura.
-- 4. Gestor: crm.eh_responsavel_comercial() = master (acesso.master) OU responsável do departamento comercial
--    (acesso.vinculo, sem área, papel responsavel) OU cargo gestor com área comercial (legado).
--    crm.eh_gestor()            = acesso.eh_admin() OU crm.eh_responsavel_comercial()   (mesmo conjunto de antes)
--    crm.estrategia_eh_gestor() = crm.eh_responsavel_comercial()                        (sai o cargo dev/admin + área)
--    Admins de sistema por exceção (Elaine, Marcio, Aldri, Cristiane, Fernanda, Isabela) seguem gestores do CRM pela
--    regra de sistema, mas NÃO transformam pedidos de Estratégias.
-- 5. crm.confere_distribuicao: soma só quem passa em crm.vendedor_ativo (a regra de crm.escolher_dono).
--
-- Corpos existentes conferidos por md5 do VIVO antes de trocar (guarda abaixo). Reversão: o texto anterior de cada corpo
-- está no .explain.md desta migration (seção Reversão); a trigger sai com drop trigger log_mascara on crm.log.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
declare r record;
begin
  for r in select * from (values
    ('public.crm_log(text,text,text,uuid,timestamp with time zone,timestamp with time zone,integer)', 'cab7f8c160dd9d7573ebbc748fceefff'),
    ('crm.eh_gestor()', '5c6b525daf646b5155e38b6dc095121b'),
    ('crm.estrategia_eh_gestor()', '8537dd81f0ea57cd98242ae7cc5ad59e'),
    ('crm.confere_distribuicao(uuid)', '1c47ef7a2ed26f0cf8d46def26c49aa6'),
    ('crm.vendedor_ativo(uuid)', '88ed7a106a9b2db2a447c55a75464a1c'),
    ('crm.pessoas_do_vendedor()', '73f14cfdc5b2d0c1debcfee8c39a7110')
  ) v(fn, esperado) loop
    if md5(pg_get_functiondef(r.fn::regprocedure)) <> r.esperado then
      raise exception 'premissa: % mudou (md5 vivo %, esperado %)', r.fn, md5(pg_get_functiondef(r.fn::regprocedure)), r.esperado;
    end if;
  end loop;
  if coalesce((select md5(qual) from pg_policies where schemaname = 'crm' and tablename = 'log' and policyname = 'log_ler'), '-')
     <> '0ebab3c0b711e2e2ed4bf98d3d90dd01' then
    raise exception 'premissa: policy crm.log.log_ler mudou';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'crm.log'::regclass and tgname = 'log_mascara') then
    raise exception 'premissa: trigger crm.log.log_mascara já existe';
  end if;
end $g$;

-- ── 1. máscara ──
create or replace function crm.mascara_texto(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare v text := p; m text; d text;
begin
  if v is null or v = '' then return v; end if;
  if position('@' in v) > 0 then
    for m in select distinct x[1] from regexp_matches(v, '([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+)', 'g') x loop
      v := replace(v, m, left(split_part(m, '@', 1), 1) || '***@' || split_part(m, '@', 2));
    end loop;
  end if;
  if v ~ '\d{4}' then
    for m in select distinct x[1] from regexp_matches(v, '(?<![A-Za-z0-9-])(\+?\(?\d[\d ().-]{8,}\d)(?![A-Za-z0-9-])', 'g') x loop
      continue when m ~ '\d{4}-\d{2}-\d{2}' or m ~ '\d{8}-\d{4}-\d{4}';   -- data ISO e UUID só com dígitos
      d := regexp_replace(m, '\D', '', 'g');
      if length(d) >= 10 then v := replace(v, m, repeat('*', length(d) - 4) || right(d, 4)); end if;
    end loop;
  end if;
  return v;
end $$;
revoke execute on function crm.mascara_texto(text) from public, anon;
grant execute on function crm.mascara_texto(text) to authenticated, service_role;

-- ── 2. todo resumo novo entra mascarado ──
create or replace function crm.tg_log_mascara()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.resumo := crm.mascara_texto(new.resumo);
  return new;
end $$;
revoke execute on function crm.tg_log_mascara() from public, anon;

create trigger log_mascara before insert on crm.log for each row execute function crm.tg_log_mascara();

-- ── 3. crm_log: visibilidade, limite e cursor no servidor ──
drop function public.crm_log(text, text, text, uuid, timestamptz, timestamptz, integer);

create function public.crm_log(p_autor text default null, p_entidade text default null, p_entidade_id text default null,
                               p_pessoa uuid default null, p_desde timestamptz default null, p_ate timestamptz default null,
                               p_limite integer default 500, p_antes bigint default null)
returns jsonb language plpgsql stable set search_path = '' as $function$
declare
  v_lim int := least(greatest(coalesce(p_limite, 500), 1), 500);
  v_eu uuid := auth.uid();
  v_gestor boolean := coalesce(crm.eh_gestor(), false);
  v_vend boolean := coalesce(crm.eh_vendedor(), false);
  v_autor uuid; v_g uuid[]; v_pes uuid[]; v_neg text[]; v_cur_em timestamptz; v jsonb;
begin
  perform crm.exige_comercial();
  if p_autor is not null and p_autor <> 'sistema' then
    begin v_autor := p_autor::uuid; exception when others then raise exception 'Autor inválido.' using errcode = '22023'; end;
  end if;
  if p_pessoa is not null then v_g := crm.pessoa_grupo(p_pessoa); end if;
  if p_antes is not null then
    select l.em into v_cur_em from crm.log l where l.id = p_antes;
    if v_cur_em is null then raise exception 'Cursor inválido.' using errcode = '22023'; end if;
  end if;
  if not v_gestor and v_vend then
    -- mesma regra da policy crm.log.log_ler
    v_pes := array(select crm.pessoas_do_vendedor());
    v_neg := array(select n.id::text from crm.negocio n where n.dono_id = v_eu);
  end if;
  with pg as (
    select l.em, l.id, l.pessoa_id, jsonb_build_object(
             'id', l.id::text, 'em', l.em, 'autorId', l.autor_id, 'acao', l.acao, 'entidade', l.entidade,
             'entidadeId', l.entidade_id, 'resumo', crm.mascara_texto(l.resumo),
             'mudancas', coalesce((select jsonb_agg(jsonb_build_object('campo', m->>'campo',
                                                                       'antes', crm.mascara_texto(m->>'de'),
                                                                       'depois', crm.mascara_texto(m->>'para')))
                                     from jsonb_array_elements(l.mudancas) m), '[]'::jsonb)) j
      from crm.log l
     where (p_autor is null or (p_autor = 'sistema' and l.autor_id is null) or l.autor_id = v_autor)
       and (p_entidade is null or l.entidade = p_entidade)
       and (p_entidade_id is null or l.entidade_id = p_entidade_id)
       and (v_g is null or l.pessoa_id = any(v_g))
       and (p_desde is null or l.em >= p_desde)
       and (p_ate is null or l.em <= p_ate)
       and (p_antes is null or (l.em, l.id) < (v_cur_em, p_antes))
       and (v_gestor
            or (v_vend and (l.autor_id = v_eu
                            or l.pessoa_id = any(v_pes)
                            or (l.entidade = 'negocio' and l.entidade_id = any(v_neg)))))
     order by l.em desc, l.id desc
     limit v_lim),
  al as (select * from crm.atual_de(array(select distinct pg.pessoa_id from pg)))
  select coalesce(jsonb_agg(pg.j || jsonb_build_object('contatoId', al.atual) order by pg.em desc, pg.id desc), '[]'::jsonb)
    into v
    from pg left join al on al.pessoa_id = pg.pessoa_id;
  return v;
end
$function$;
revoke execute on function public.crm_log(text, text, text, uuid, timestamptz, timestamptz, integer, bigint) from public, anon;
grant execute on function public.crm_log(text, text, text, uuid, timestamptz, timestamptz, integer, bigint) to authenticated, service_role;

-- policy alinhada à função (acrescenta: negócio de que o vendedor é dono, mesmo se o contato mudou de dono)
alter policy log_ler on crm.log using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor())
      and (autor_id = (select auth.uid())
           or pessoa_id in (select crm.pessoas_do_vendedor())
           or (entidade = 'negocio' and entidade_id in (select n.id::text from crm.negocio n where n.dono_id = (select auth.uid()))))));

-- ── 4. gestor: um núcleo só ──
create or replace function crm.eh_responsavel_comercial()
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(acesso.eh_master(), false)
      or exists (select 1 from acesso.vinculo v where v.perfil_id = acesso.eu() and v.vigente_ate is null
                   and v.departamento = 'comercial' and v.area is null and v.papel = 'responsavel')
      or coalesce((select p.status = 'ativo' and p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))
                     from public.perfis p where p.id = (select auth.uid())), false);
$$;
revoke execute on function crm.eh_responsavel_comercial() from public, anon;

create or replace function crm.eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008rg: admin de sistema (acesso.eh_admin) OU o núcleo do Comercial (crm.eh_responsavel_comercial)
  select coalesce(acesso.eh_admin(), false) or coalesce(crm.eh_responsavel_comercial(), false);
$$;

create or replace function crm.estrategia_eh_gestor()
returns boolean language sql stable security definer set search_path = '' as $$
  -- 20261008rg: só o núcleo do Comercial (master, responsável do comercial, cargo gestor + área comercial).
  -- Admin de sistema por exceção NÃO transforma pedido em ação (Elaine e Marcio são solicitantes).
  select coalesce(crm.eh_responsavel_comercial(), false);
$$;

-- ── 5. distribuição conferida pela regra de vendedor ativo de crm.escolher_dono ──
create or replace function crm.confere_distribuicao(p_funil uuid)
returns void language plpgsql stable set search_path = '' as $function$
declare v_soma int; v_tem boolean; v_propria boolean;
begin
  if p_funil is not null then
    select f.distribuicao_propria into v_propria from crm.funil f where f.id = p_funil;
    if not coalesce(v_propria, false) then return; end if;
  end if;
  select coalesce(sum(d.percentual) filter (where crm.vendedor_ativo(d.vendedor_id)), 0), count(*) > 0
    into v_soma, v_tem
    from crm.distribuicao d join crm.vendedor v on v.perfil_id = d.vendedor_id join public.perfis pf on pf.id = d.vendedor_id
   where d.ativo and d.funil_id is not distinct from p_funil;
  if (p_funil is null and v_tem and v_soma <> 100) or (p_funil is not null and v_soma <> 100) then
    raise exception '%', case when p_funil is null then 'A soma dos percentuais dos ativos precisa dar 100%.'
                              else 'A distribuição própria precisa somar 100%.' end using errcode = '23514';
  end if;
end
$function$;

notify pgrst, 'reload schema';

-- ═══ provas (JWT real de cada perfil, role authenticated) ═══
create temp table _r (ordem serial, quem text, prova text, resultado text) on commit drop;
grant all on _r to authenticated; grant usage on sequence _r_ordem_seq to authenticated;

do $t$
declare
  p record; v jsonb; v2 jsonb; n int; e text; vend_outros uuid[];
begin
  -- máscara: casos de borda
  insert into _r(quem, prova, resultado) values
    ('-', 'mascara email', crm.mascara_texto('Abriu o contato comercial de fulano.tal@gmail.com')),
    ('-', 'mascara fone/cpf', crm.mascara_texto('Dono do contato ALEXANDRE 01846203767: X; (11) 98888-7777.')),
    ('-', 'nao toca uuid/HP/data/valor', crm.mascara_texto('Trocou negocio 12345678-1234-1234-1234-123456789012 HP0000567358 em 2026-10-07 13:18 R$ 1.997,00')),
    ('-', 'linhas antigas que mudam na leitura', (select count(*)::text from crm.log l where l.resumo is distinct from crm.mascara_texto(l.resumo))),
    ('-', 'linhas antigas c/ e-mail ou fone apos mascara', (select count(*)::text from crm.log l where crm.mascara_texto(l.resumo) ~* '[a-z0-9._%+-]{2,}@[a-z0-9-]+\.[a-z]'));

  -- escrita nova entra mascarada (trigger) — linha some no rollback
  perform crm.log_registrar('editou', 'contato', 'ensaio-rg', null, 'Ensaio rg: contato beltrano@exemplo.com fone 21 99876-5432', '{}');
  insert into _r(quem, prova, resultado) values ('-', 'resumo gravado pela trigger',
    (select l.resumo from crm.log l where l.entidade_id = 'ensaio-rg' order by l.id desc limit 1));

  -- distribuição: soma atual continua 100 pela regra nova
  begin perform crm.confere_distribuicao(null); insert into _r(quem, prova, resultado) values ('-', 'confere_distribuicao(null)', 'ok');
  exception when others then insert into _r(quem, prova, resultado) values ('-', 'confere_distribuicao(null)', sqlstate || ' ' || sqlerrm); end;

  vend_outros := array(select v.perfil_id from crm.vendedor v);

  for p in
    select x.rotulo, pf.id from (values ('Jonathan', 'Jonathan Mendes'), ('Marcos', 'Marcos Paulo'), ('Jusy', 'Jusy'),
                                        ('Elaine', 'Elaine Montenegro'), ('Marcio', 'Marcio Carvalho de Sá'), ('Arthur', 'Arthur Galvão'),
                                        ('Aldri', 'Aldri Santana'), ('VictorHugo', 'Victor Hugo')) x(rotulo, nome)
      join public.perfis pf on pf.nome = x.nome and pf.status = 'ativo'
    union all
    (select 'visualizador', pf.id from public.perfis pf where pf.status = 'ativo' and pf.cargo = 'visualizador'
        and pf.email ilike '%@advmais.com' and not ('comercial' = any(coalesce(pf.areas, '{}'))) order by pf.nome limit 1)
  loop
    perform set_config('request.jwt.claims', json_build_object('sub', p.id, 'role', 'authenticated')::text, true);
    insert into _r(quem, prova, resultado) values
      (p.rotulo, 'eh_gestor / estrategia_eh_gestor / responsavel', crm.eh_gestor()::text || ' / ' || crm.estrategia_eh_gestor()::text || ' / ' || crm.eh_responsavel_comercial()::text);
    set local role authenticated;
    begin
      v := public.crm_log(p_limite => 500);
      n := jsonb_array_length(v);
      v2 := case when n > 0 then public.crm_log(p_limite => 500, p_antes => (v -> (n - 1) ->> 'id')::bigint) else '[]'::jsonb end;
      reset role;
      insert into _r(quem, prova, resultado) values
        (p.rotulo, 'crm_log pag1 / pag2 / pag2 mais antiga que pag1',
         n || ' / ' || jsonb_array_length(v2) || ' / ' ||
         coalesce(((v2 -> 0 ->> 'em')::timestamptz <= (v -> (n - 1) ->> 'em')::timestamptz
                   and not exists (select 1 from jsonb_array_elements(v) a join jsonb_array_elements(v2) b on a ->> 'id' = b ->> 'id'))::text, 'sem pag2')),
        (p.rotulo, 'crm_log: linhas fora da regra (nao fiz, pessoa fora de pessoas_do_vendedor, negocio nao e meu)',
         (select count(*)::text from jsonb_array_elements(v) j join crm.log l on l.id = (j ->> 'id')::bigint
           where l.autor_id is distinct from p.id
             and (l.pessoa_id is null or l.pessoa_id not in (select crm.pessoas_do_vendedor()))
             and not exists (select 1 from crm.negocio ng where ng.dono_id = p.id and ng.id::text = l.entidade_id and l.entidade = 'negocio'))),
        (p.rotulo, 'crm_log: linhas de contato cujo dono e OUTRO vendedor, sem negocio meu nem autoria minha',
         (select count(*)::text from jsonb_array_elements(v) j join crm.log l on l.id = (j ->> 'id')::bigint
           where l.autor_id is distinct from p.id
             and exists (select 1 from crm.pessoa_comercial pc where pc.pessoa_id = l.pessoa_id and pc.dono_id <> p.id and pc.dono_id = any(vend_outros))
             and not exists (select 1 from crm.negocio ng where ng.dono_id = p.id and ng.pessoa_id = l.pessoa_id))),
        (p.rotulo, 'crm_log: resumo com e-mail aberto', (select count(*)::text from jsonb_array_elements(v) j where j ->> 'resumo' ~* '[a-z0-9._%+-]{2,}@[a-z0-9-]+\.[a-z]'));
    exception when others then
      get stacked diagnostics e = returned_sqlstate;
      reset role;
      insert into _r(quem, prova, resultado) values (p.rotulo, 'crm_log', 'erro ' || e || ' ' || sqlerrm);
    end;
    set local role authenticated;
    begin
      v := public.crm_estrategia_transformar(gen_random_uuid(), 'funil');
      insert into _r(quem, prova, resultado) values (p.rotulo, 'crm_estrategia_transformar(id inexistente)', v ->> 'msg');
    exception when others then
      insert into _r(quem, prova, resultado) values (p.rotulo, 'crm_estrategia_transformar(id inexistente)', 'erro ' || sqlstate || ' ' || sqlerrm);
    end;
    reset role;
  end loop;
end $t$;

select quem, prova, resultado from _r order by ordem;
rollback;
