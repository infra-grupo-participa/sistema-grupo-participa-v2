-- 20261004h — Backfill de respondi.aplicacoes.confianca/motivo nas aplicações anteriores à 20261004f.
-- Mesma regra da aplicação (respondi.conferencia, 20261004f). Não toca a ficha: só classifica a trilha.
-- Exige a 20261004f aplicada. Idempotente: só preenche onde confianca is null.
--
-- CONTAGEM ANTES (só leitura, mesma expressão do passo 1; rodar e colar no relatório antes de aplicar):
--   select case when p.regra in ('respondi:inclusao_socio','respondi:cpf_socio_valido')
--                    or (p.regra = 'respondi:endereco' and f.familia = 'socios')
--                 then case when r.uuid is null then 'resposta de origem não encontrada'
--                           else nullif(concat_ws(' · ', 'titular: ' || k.motivo_titular, k.motivo_socio), '') end
--               else coalesce(k.motivo_titular, 'resposta de origem não encontrada') end motivo,
--          (p.revertido_em is not null) revertida, count(*)
--     from respondi.aplicacoes p
--     left join respondi.respostas r on r.uuid = p.resposta_uuid
--     left join respondi.formularios f on f.slug = r.form_slug
--     left join lateral respondi.conferencia(p.resposta_uuid) k on true
--    where p.confianca is null and p.regra like 'respondi:%'
--    group by 1, 2 order by 3 desc;          -- motivo null = certo
--   (regra de respondi.conferencia, já com a revisão kirad: casado só por CPF com e-mail diferente = a_confirmar.)
--   (herança: a_confirmar quando o vínculo socio_de_aluno_id com o titular ATUAL ficar a_confirmar no passo 1.)
--
-- Reversão: update respondi.aplicacoes set confianca = null, motivo = null where <ids desta rodada>;
--   (nenhum dado da ficha muda; a coluna é só observação).

do $$
declare v_r int; v_h int;
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'respondi' and table_name = 'aplicacoes' and column_name = 'confianca') then
    raise exception '20261004h: aplique a 20261004f antes';
  end if;

  -- 1. Aplicações vindas de resposta
  with c as (
    select p.id,
           case when p.regra in ('respondi:inclusao_socio','respondi:cpf_socio_valido')
                     or (p.regra = 'respondi:endereco' and f.familia = 'socios')
                  then case when r.uuid is null then 'resposta de origem não encontrada'
                            else nullif(concat_ws(' · ', 'titular: ' || k.motivo_titular, k.motivo_socio), '') end
                else coalesce(k.motivo_titular, 'resposta de origem não encontrada') end motivo
      from respondi.aplicacoes p
      left join respondi.respostas r on r.uuid = p.resposta_uuid
      left join respondi.formularios f on f.slug = r.form_slug
      left join lateral respondi.conferencia(p.resposta_uuid) k on true
     where p.confianca is null and p.regra like 'respondi:%'
  )
  update respondi.aplicacoes p
     set confianca = case when c.motivo is null then 'certo' else 'a_confirmar' end, motivo = c.motivo
    from c where c.id = p.id;
  get diagnostics v_r = row_count;

  -- 2. Herança do titular: só o vínculo com o titular ATUAL (socio_de_aluno_id da ficha), como no aplicar (20261004f)
  update respondi.aplicacoes h
     set confianca = case when x.duvida then 'a_confirmar' else 'certo' end,
         motivo = case when x.duvida then 'herdado do titular; vínculo de sócio a confirmar' end
    from (select h2.id, exists (select 1 from respondi.aplicacoes s
                                 where s.aluno_id = h2.aluno_id and s.campo = 'socio_de_aluno_id'
                                   and s.revertido_em is null and s.confianca = 'a_confirmar'
                                   and s.valor_novo = a.socio_de_aluno_id::text) duvida
            from respondi.aplicacoes h2 join public.thb_alunos a on a.id = h2.aluno_id
           where h2.confianca is null and h2.regra like 'heranca:%') x
   where x.id = h.id;
  get diagnostics v_h = row_count;

  raise notice '20261004h: % de resposta e % de herança classificadas; a_confirmar não revertidas: %',
    v_r, v_h, (select count(*) from respondi.aplicacoes where confianca = 'a_confirmar' and revertido_em is null);
end $$;
