// Domínio puro de cargos/setores/funções (LGPD v2) — porta de usuarios/index.html.
import type { Cargo } from '@/shared/domain/auth';

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
