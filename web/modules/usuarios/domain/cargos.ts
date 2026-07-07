// Domínio puro de cargos/setores/funções (LGPD v2) — porta de usuarios/index.html.
import type { Cargo, Setor } from '@/shared/domain/auth';

export const CARGO_META: Record<Cargo, { label: string; description: string; rank: number }> = {
  dev: { label: 'Dev', description: 'Acesso total incluindo painel técnico. Apenas outro dev pode atribuir.', rank: 500 },
  admin: { label: 'Admin', description: 'Acesso total aos dados operacionais. Gerencia usuários não-dev.', rank: 400 },
  gestor: { label: 'Gestor', description: 'Vê e edita tudo dos setores marcados. Não gerencia usuários.', rank: 300 },
  operador: { label: 'Operador', description: 'Executa funções específicas dentro dos setores atribuídos.', rank: 200 },
  visualizador: { label: 'Visualizador', description: 'Vê todas as páginas em leitura. CPF mascarado.', rank: 100 },
};

export const CARGO_ORDEM: Cargo[] = ['dev', 'admin', 'gestor', 'operador', 'visualizador'];

export const SETOR_META: Record<string, { label: string }> = {
  ativacao: { label: 'Ativação (HT + HM)' },
  social_media: { label: 'Social Media' },
  placas: { label: 'Placas' },
  depoimentos: { label: 'Depoimentos' },
  centro_controle: { label: 'Centro de Controle' },
};

export const USER_STATUS = ['ativo', 'pendente', 'negado'] as const;

/**
 * Catálogo de funções por setor (chave = `setor.acao`).
 * Operador só edita um setor se tiver o setor em `areas` E ao menos uma função do setor.
 * Gestor herda todas as funções dos seus setores; dev/admin têm tudo.
 */
export const FUNCAO_META: Record<string, { setor: Setor; label: string }> = {
  'placas.operar': { setor: 'placas', label: 'Operar fluxo de placas' },
  'placas.hm_liberar': { setor: 'placas', label: 'Manipular / liberar Acesso HM' },
  'depoimentos.moderador': { setor: 'depoimentos', label: 'Moderar depoimentos' },
  'centro_controle.operar': { setor: 'centro_controle', label: 'Editar dados de alunos' },
  'social_media.operar': { setor: 'social_media', label: 'Operar Social Media' },
  'ativacao.ht_ver': { setor: 'ativacao', label: 'Ver ativações HT' },
  'ativacao.ht_operar': { setor: 'ativacao', label: 'Operar ativações HT' },
  'ativacao.hm_ver': { setor: 'ativacao', label: 'Ver ativações HM' },
  'ativacao.hm_operar': { setor: 'ativacao', label: 'Operar ativações HM' },
};

/** Cargos que um usuário com `meuCargo` pode atribuir. Porta de cargosGrantaveis. */
export function cargosGrantaveis(meuCargo: Cargo): Cargo[] {
  if (meuCargo === 'dev') return CARGO_ORDEM;
  if (meuCargo === 'admin') return ['admin', 'gestor', 'operador', 'visualizador'];
  return [];
}

/** Pode editar o usuário alvo? Porta de podeEditarUsuario. */
export function podeEditarUsuario(meuCargo: Cargo, alvoCargo: Cargo): boolean {
  if (meuCargo === 'dev') return true;
  if (alvoCargo === 'dev') return false;
  return meuCargo === 'admin';
}
