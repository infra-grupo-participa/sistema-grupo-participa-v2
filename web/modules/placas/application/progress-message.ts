// Traduz os códigos de validação de progresso (form-progress) em mensagens públicas
// específicas em pt-BR. Substitui o "Não foi possível concluir a operação." genérico,
// permitindo ao aluno saber exatamente o que falta preencher.

import type { ProgressError } from '../domain/form-progress';

const FIELD_LABEL: Record<string, string> = {
  nome: 'Nome completo',
  email: 'E-mail',
  telefone: 'WhatsApp',
  turma: 'Turma',
  documento_nf: 'Documento',
  interesse: 'Interesse',
  espaco_instrucao: 'Espaço de instrução',
  nivel: 'Nível',
  cep: 'CEP',
  logradouro: 'Logradouro',
  numero: 'Número',
  bairro: 'Bairro',
  cidade: 'Cidade',
  estado_uf: 'Estado',
  pais: 'País',
};

export function progressErrorMessage(err: ProgressError): string {
  const label = err.field ? FIELD_LABEL[err.field] ?? err.field : '';
  switch (err.code) {
    case 'missing_step1_field':
      return label ? `Preencha o campo obrigatório: ${label}.` : 'Preencha todos os campos obrigatórios.';
    case 'missing_step2_field':
      return 'Selecione uma opção de interesse.';
    case 'missing_step3_field':
      return label ? `Selecione: ${label}.` : 'Selecione o espaço de instrução e o nível.';
    case 'missing_faturamento':
      return 'Informe o faturamento declarado.';
    case 'missing_proof':
      return 'Envie o documento comprobatório.';
    case 'invalid_proof_url':
      return 'O comprovante enviado é inválido. Reenvie o arquivo.';
    case 'missing_declaracao':
      return 'Envie a declaração assinada.';
    case 'invalid_declaracao_url':
      return 'A declaração enviada é inválida. Reenvie o arquivo.';
    case 'missing_address':
      return label ? `Preencha o endereço: ${label}.` : 'Preencha o endereço completo.';
    case 'invalid_submit_step':
    case 'invalid_non_eligible_progress':
    case 'invalid_cadastro_status':
    case 'invalid_eligible_status':
      return 'Não foi possível finalizar. Revise as etapas e tente novamente.';
    default:
      return 'Não foi possível concluir a operação.';
  }
}
