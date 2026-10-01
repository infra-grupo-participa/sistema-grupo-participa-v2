-- Trajetória do aluno: formulários do Respondi entram na linha do tempo.
--   comprovação de nível  → atendimento/nivel (marco de nível)
--   inclusão de sócios    → socios (do titular e do sócio declarado)
--   demais famílias       → eventos (capítulo "Outros eventos"), fonte 'Respondi'
-- Recria fn_aluno_trajetoria a partir do corpo VIGENTE (pg_get_functiondef), acrescentando um ramo
-- ao union antes do select final. Idempotente: não faz nada se o ramo já existe.
do $mig$
declare
  d text := pg_get_functiondef('public.fn_aluno_trajetoria(uuid)'::regprocedure);
  ancora text := E'  )\n  select u.dia::date, u.momento::timestamptz';
  ramo text := $r$
    -- Respondi: formulários respondidos pelo aluno (ou em que foi declarado sócio)
    union all
    select (rr.respondido_em at time zone 'America/Sao_Paulo')::date, rr.respondido_em,
           case rf.familia when 'nivel' then 'atendimento' when 'socios' then 'socios' else 'eventos' end,
           case rf.familia when 'nivel' then 'nivel' when 'socios' then 'inclusao_socio' else 'formulario' end,
           case when rf.familia = 'socios' and rr.aluno_id is distinct from v_al.id then 'Declarado como sócio: ' || rf.nome else rf.nome end,
           nullif(concat_ws(' · ', rf.workspace,
             case when rf.familia = 'nivel' then 'nível declarado ' || (rr.dados->>'nivel_codigo') end,
             case when rr.dados ? 'turma_codigo' then 'turma ' || (rr.dados->>'turma_codigo') end), ''),
           null, null, 'Respondi', 'respondi.respostas', rr.uuid::text
      from respondi.respostas rr
      join respondi.formularios rf on rf.slug = rr.form_slug
     where rr.aluno_id = v_al.id
        or (rf.familia = 'socios' and (rr.dados->>'socio_aluno_id') = v_al.id::text)
$r$;
begin
  if position('respondi.respostas rr' in d) > 0 then return; end if;
  if position(ancora in d) = 0 then raise exception 'âncora do select final não encontrada em fn_aluno_trajetoria'; end if;
  execute replace(d, ancora, ramo || ancora);
end
$mig$;

-- O ramo "declarado como sócio" (aqui e em fn_aluno_respondi) filtra por dados->>'socio_aluno_id':
-- sem índice o OR caía em seq scan de respondi.respostas (18 ms, 6.106 buffers por ficha).
create index if not exists respostas_socio_aluno_idx on respondi.respostas ((dados->>'socio_aluno_id'));
