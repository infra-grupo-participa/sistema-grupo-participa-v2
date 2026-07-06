// Traduz os códigos de validação de progresso (form-progress) em mensagens públicas
// específicas em pt-BR. Substitui o "Não foi possível concluir a operação." genérico,
// permitindo ao aluno saber exatamente o que falta preencher.

import { NIVEL_MIN_FATURAMENTO, type ProgressError } from '../domain/form-progress';

const NIVEL_NOME: Record<string, string> = {
  iniciante: 'Iniciante',
  em_formacao: 'Em Formação',
  pessoal: 'Pessoal',
  profissional: 'Profissional',
  ouro: 'Ouro',
  platina: 'Platina',
  diamante: 'Diamante',
  diamante_vermelho: 'Diamante Vermelho',
};

const brl = (v: number) => `R$ ${v.toLocaleString('pt-BR')}`;

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
    case 'faturamento_abaixo_nivel': {
      // err.field carrega o nível para compor a mensagem com o mínimo da faixa.
      const nivel = String(err.field ?? '');
      const min = NIVEL_MIN_FATURAMENTO[nivel];
      return min
        ? `O nível ${NIVEL_NOME[nivel] ?? nivel} exige faturamento a partir de ${brl(min)}. Confira o valor digitado ou selecione o nível compatível com o seu faturamento.`
        : 'O faturamento declarado está abaixo do mínimo do nível selecionado.';
    }
    case 'faturamento_acima_teto':
      return 'O faturamento informado parece incorreto (valor alto demais). Confira o número digitado — informe o valor em reais, sem centavos.';
    case 'refazer_nivel_nao_elegivel':
      return 'Para refazer o processo você precisa selecionar um nível a partir de Ouro (que emite placa).';
    case 'refazer_nivel_nao_superior': {
      const anterior = String(err.field ?? '');
      const nome = NIVEL_NOME[anterior] ?? anterior;
      return anterior
        ? `Seu nível atual é ${nome}. Ao refazer, escolha um nível superior — este e os inferiores estão bloqueados.`
        : 'Ao refazer, escolha um nível superior ao atual.';
    }
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
