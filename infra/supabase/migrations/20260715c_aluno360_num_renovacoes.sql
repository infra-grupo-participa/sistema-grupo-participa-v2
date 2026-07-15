-- Ficha 360: expõe num_renovacoes (quantas vezes o aluno renovou o Holding Masters).
--
-- Fonte: public.compras (alimentada em tempo real pelo webhook hotmart-events-webhook).
-- Regra de renovação idêntica à do webhook (isRenovacao):
--   produto_id = '3507214' (Holding - Holding Masters / renovação)
--   OU (is_assinatura AND numero_recorrencia > 1)  -- assinatura já renovada
-- Cada linha assim é um evento de renovação → count = nº de renovações.
--
-- Retorna NULL quando o aluno não tem comprador_id (sem vínculo Hotmart) — o
-- drawer mostra "—" nesse caso, e "0" quando há vínculo mas nunca renovou.
--
-- Recriação idêntica ao corpo vigente de fn_aluno_360_safe + a coluna nova (json
-- por nome, então a ordem não afeta os consumidores).

CREATE OR REPLACE FUNCTION public.fn_aluno_360_safe(p_aluno_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_user_id uuid := auth.uid(); v_can_see boolean;
begin
  v_can_see := public.tem_permissao(v_user_id, 'alunos.ver_sensivel');
  return query
    select to_json(t) from (
      select
        v.id, v.nome, v.email, v.telefone, v.telefone_e164,
        public.mask_sensivel(v.documento, v_can_see) as documento,
        v.profissao, v.link_facebook, v.cep, v.endereco_logradouro, v.endereco_numero, v.endereco_complemento,
        v.bairro, v.cidade, v.estado, v.pais, v.turma_id, v.turma_codigo, v.turma_tipo, v.turma_aurum_id,
        ta.codigo as turma_aurum_codigo,
        v.plano, v.nivel_resultado, v.placa_aurum, v.eh_socio, v.socio_de_aluno_id, v.socio_de_nome, v.status_acesso,
        v.comprador_id, v.hotmart_ucode, v.tem_ht, v.data_compra_ht,
        v.tem_hm, v.data_compra_hm,
        v.tem_placa, v.placa_step, v.placa_encerrada, v.placa_protocolo, v.tem_depoimento, v.total_depoimentos,
        v.fonte, v.data_compra_importada, v.importado_em, v.atualizado_em,
        v.cs_estagio, v.cs_responsavel, v.cs_ultimo_contato_em, v.cs_proxima_acao_em, v.cs_no_grupo, v.cs_observacoes, v.sip_registrado,
        v.instagram_url, v.youtube_url, v.site_profissional, v.telefone_profissional,
        v.placa_solicitacao_id, v.tem_solicitacao_placa, v.placa_sol_status, v.placa_sol_step,
        v.placa_rastreio, v.placa_entrevista_data, v.placa_regularizacao_pendente,
        v.produto, v.instrucao, v.oferta, v.tipo_oferta, v.regra_acesso,
        v.data_expiracao, v.tempo_acesso, v.status_acesso_central, v.status_pagamento,
        v.valor_total, v.valor_pago, v.saldo_devedor, v.ultimo_pagamento, v.num_cobrancas,
        case when v.comprador_id is null then null else (
          select count(*)::int
          from public.compras cmp
          where cmp.comprador_id = v.comprador_id
            and (cmp.produto_id = '3507214'
                 or (cmp.is_assinatura = true and coalesce(cmp.numero_recorrencia, 1) > 1))
        ) end as num_renovacoes,
        v.origem_acesso, v.num_socios, v.tratamento_manual, v.obs_central, v.situacao_acesso, v.situacao_financeira, v.espaco_instrucao,
        a.tipo_documento, a.mes_expiracao, a.ano_expiracao,
        v_can_see as _can_see_sensivel
      from public.vw_aluno_360 v
      left join public.thb_alunos a on a.id = v.id
      left join public.thb_turmas ta on ta.id = v.turma_aurum_id
      where p_aluno_id is null or v.id = p_aluno_id
    ) t;
end;
$function$;
