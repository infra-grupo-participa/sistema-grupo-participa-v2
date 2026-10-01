-- Respondi: desfaz as aplicações na ficha que a regra corrigida (20261004c revisada) não produziria.
--   aluno_mudou        → a resposta deixou de casar com o aluno (e-mail, CPF e telefone discordavam)
--   por_telefone       → dado pessoal (profissão, redes, CPF, endereço) vindo de resposta casada só por telefone
--   socio_por_telefone → CPF/endereço de sócio casado só por telefone
--   regex              → link de rede social fora do domínio oficial
--   cpf_dup            → CPF que já é documento de outro aluno
-- Só restaura quando o valor atual da ficha ainda é o que o Respondi gravou (ninguém mexeu depois).
-- Endereço: limpa cep/logradouro/número/complemento/bairro/cidade (antes estavam vazios, era a condição
-- para aplicar); `estado` volta ao valor_antes quando foi o Respondi que o preencheu.
-- Medido antes (30/09/2026, depois de fn_respondi_casar revisada): 37 linhas
--   profissão 14 · Instagram 8 telefone + 2 regex + 1 aluno mudou · endereço 6 + 2 sócio · nível 3 · CPF sócio 1.
-- Idempotente: marca revertido_em e não toca linha já revertida.

do $mig$
begin
  create temp table _rv on commit drop as
  with ap as (
    select p.*, r.aluno_id r_aluno, r.casado_por, r.dados, f.familia
      from respondi.aplicacoes p
      left join respondi.respostas r on r.uuid = p.resposta_uuid
      left join respondi.formularios f on f.slug = r.form_slug
     where p.revertido_em is null and p.regra like 'respondi:%'
  )
  select id, aluno_id, campo, valor_antes, valor_novo from ap
   where case
     when regra in ('respondi:inclusao_socio','respondi:cpf_socio_valido') or (regra = 'respondi:endereco' and familia = 'socios') then
          (dados->>'socio_aluno_id') is distinct from aluno_id::text
       or (regra = 'respondi:inclusao_socio' and r_aluno::text is distinct from valor_novo)
       or (regra <> 'respondi:inclusao_socio' and coalesce(dados->>'socio_casado_por','') not in ('email','cpf'))
       or (regra = 'respondi:inclusao_socio' and coalesce(casado_por,'') not in ('email','cpf'))
       or (regra = 'respondi:cpf_socio_valido' and exists (select 1 from public.thb_alunos x
             where x.id <> ap.aluno_id and regexp_replace(coalesce(x.documento,''),'\D','','g') = ap.valor_novo))
     else
          r_aluno is distinct from aluno_id
       or (regra in ('respondi:profissao','respondi:facebook','respondi:instagram','respondi:youtube','respondi:cpf_valido','respondi:endereco')
           and coalesce(casado_por,'') not in ('email','cpf'))
       or (regra = 'respondi:facebook' and valor_novo !~* '^https?://([a-z0-9-]+\.)?(facebook\.com|fb\.com)/[^\s<>"]+$')
       or (regra = 'respondi:youtube' and valor_novo !~* '^https?://([a-z0-9-]+\.)?(youtube\.com|youtu\.be)/[^\s<>"]+$')
       or (regra = 'respondi:instagram' and valor_novo !~* '^https?://(www\.)?instagram\.com/[a-z0-9._]{3,30}/?(\?[^\s<>"]*)?$')
       or (regra = 'respondi:cpf_valido' and exists (select 1 from public.thb_alunos x
             where x.id <> ap.aluno_id and regexp_replace(coalesce(x.documento,''),'\D','','g') = ap.valor_novo))
   end;

  -- só o que a ficha ainda mostra igual ao que o Respondi gravou
  create temp table _ok on commit drop as
  select v.* from _rv v join public.thb_alunos a on a.id = v.aluno_id
   where case v.campo
     when 'profissao' then a.profissao = v.valor_novo
     when 'link_facebook' then a.link_facebook = v.valor_novo
     when 'instagram_url' then a.instagram_url = v.valor_novo
     when 'youtube_url' then a.youtube_url = v.valor_novo
     when 'documento' then a.documento = v.valor_novo
     when 'nivel_resultado' then a.nivel_resultado = v.valor_novo
     when 'turma' then v.valor_novo in (a.turma_id::text, a.turma_aurum_id::text)
     when 'socio_de_aluno_id' then a.socio_de_aluno_id::text = v.valor_novo
     when 'endereco' then concat_ws(' | ', a.cep, a.endereco_logradouro, a.endereco_numero, a.endereco_complemento, a.bairro, a.cidade, a.estado) = v.valor_novo
   end;

  update public.thb_alunos a set profissao = o.valor_antes from _ok o where o.aluno_id = a.id and o.campo = 'profissao';
  update public.thb_alunos a set link_facebook = o.valor_antes from _ok o where o.aluno_id = a.id and o.campo = 'link_facebook';
  update public.thb_alunos a set instagram_url = o.valor_antes from _ok o where o.aluno_id = a.id and o.campo = 'instagram_url';
  update public.thb_alunos a set youtube_url = o.valor_antes from _ok o where o.aluno_id = a.id and o.campo = 'youtube_url';
  update public.thb_alunos a set documento = o.valor_antes, tipo_documento = case when o.valor_antes is null then null else a.tipo_documento end from _ok o where o.aluno_id = a.id and o.campo = 'documento';
  update public.thb_alunos a set nivel_resultado = o.valor_antes from _ok o where o.aluno_id = a.id and o.campo = 'nivel_resultado';
  update public.thb_alunos a set turma_id = case when t.tipo = 'aurum' then a.turma_id else o.valor_antes::smallint end,
                                 turma_aurum_id = case when t.tipo = 'aurum' then null else a.turma_aurum_id end
    from _ok o join public.thb_turmas t on t.id = o.valor_novo::smallint
   where o.aluno_id = a.id and o.campo = 'turma';
  update public.thb_alunos a set socio_de_aluno_id = o.valor_antes::uuid, socio_de_nome = null
    from _ok o where o.aluno_id = a.id and o.campo = 'socio_de_aluno_id';
  update public.thb_alunos a set cep = null, endereco_logradouro = null, endereco_numero = null,
         endereco_complemento = null, bairro = null, cidade = null,
         estado = case when o.valor_novo like '%| ' || a.estado then o.valor_antes else a.estado end
    from _ok o where o.aluno_id = a.id and o.campo = 'endereco';

  -- marca tudo que a regra nova não produziria, inclusive o que a ficha já tinha mudado depois
  update respondi.aplicacoes p set revertido_em = now() from _rv v where v.id = p.id;

  raise notice 'respondi: % fora da regra, % restauradas na ficha', (select count(*) from _rv), (select count(*) from _ok);
end
$mig$;

-- Complemento (kirad, 30/09): a 1ª rodada deixou `estado` (UF do Respondi) e `tipo_documento='cpf'`
-- nas fichas revertidas. A aplicação antiga não registrava a UF anterior; nas 8 revertidas o `estado`
-- é exatamente a UF da resposta e a ficha não tinha CEP/logradouro/cidade — tratada como vinda do Respondi.
update public.thb_alunos a set estado = null
  from respondi.aplicacoes p
 where p.aluno_id = a.id and p.regra = 'respondi:endereco' and p.revertido_em is not null
   and p.valor_antes is null and a.cep is null and a.cidade is null and a.estado is not null
   and p.valor_novo like '%| ' || a.estado;
update public.thb_alunos a set tipo_documento = null
  from respondi.aplicacoes p
 where p.aluno_id = a.id and p.campo = 'documento' and p.revertido_em is not null
   and a.documento is null and a.tipo_documento = 'cpf';
