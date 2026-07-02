// Constantes e tipos do wizard público de solicitação de placa.

export const TOTAL_STEPS = 6;
export const STEP_NAMES = ['', 'Seus dados', 'Interesse', 'Seu nível', 'Comprovação', 'Declaração', 'Endereço'];
export const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'];

export const INTERESSES = [
  { v: 'pessoal', l: 'Apenas fazer a minha Holding e/ou da minha família', sub: 'Interesse exclusivamente pessoal, sem intenção de oferecer o serviço a terceiros.' },
  { v: 'familia_e_possivel', l: 'Minha Holding + possibilidade de oferecer a outros clientes', sub: 'Interesse pessoal com abertura para eventualmente prestar o serviço a outros.' },
  { v: 'profissional', l: 'Trabalhar com Holding Familiar', sub: 'Objetivo principal é prestar o serviço de Holding como profissão.' },
];

export const ESPACOS = [
  { v: 'holding_masters', l: 'Holding Masters' },
  { v: 'aurum', l: 'Mentoria Aurum' },
  { v: 'coach_platina', l: 'Coach Platina' },
  { v: 'mastermind', l: 'Mastermind Diamante' },
];

export const NIVEIS = [
  { v: 'iniciante', ic: 'sprout', nm: 'Iniciante', fx: 'Ainda não comecei' },
  { v: 'em_formacao', ic: 'biblioteca', nm: 'Em Formação', fx: 'Estudando o curso' },
  { v: 'pessoal', ic: 'user', nm: 'Pessoal', fx: 'Só minha holding' },
  { v: 'profissional', ic: 'briefcase', nm: 'Profissional', fx: 'Oferecendo a clientes' },
  { v: 'ouro', ic: 'medal', nm: 'Ouro', fx: 'Primeiros R$ 50k faturado' },
  { v: 'platina', ic: 'coins', nm: 'Platina', fx: 'R$ 500k em 12 meses' },
  { v: 'diamante', ic: 'gem', nm: 'Diamante', fx: 'R$ 1M em 12 meses' },
  { v: 'diamante_vermelho', ic: 'gem', nm: 'Diamante Vermelho', fx: 'R$ 5M em 12 meses' },
];

export type Form = Record<string, string>;
export type View = 'loading' | 'form' | 'success' | 'cadastro' | 'tracking' | 'error';

/** Config personalizável (níveis/faixas + textos) resolvida no server e injetada no client. */
export interface FormConfig {
  niveis: { v: string; ic: string; nm: string; fx: string }[];
  textos: { upload_info: string; cadastro_info: string; espacos: { v: string; l: string }[] };
}
