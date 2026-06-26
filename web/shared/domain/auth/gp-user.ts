import { type Cargo, normalizeCargo } from './cargo';

/** Entidade de usuário autenticado no modelo canônico. */
export interface GpUser {
  id: string;
  nome: string;
  email: string;
  cargo: Cargo;
  status: string | null;
  setores: string[];
  funcoes: string[];
  podeVerCpf: boolean;
  time: string | null;
  avatarUrl: string | null;
}

/** Linha bruta de `perfis` (campos relevantes para auth). */
export interface PerfilData {
  id: string;
  nome?: string | null;
  email?: string | null;
  cargo?: string | null;
  status?: string | null;
  nivel_hierarquia?: string | null;
  eh_dev?: boolean | null;
  pode_ver_cpf_completo?: boolean | null;
  time?: string | null;
  avatar_url?: string | null;
  areas?: string[] | null;
  setores?: string[] | null;
  funcoes?: string[] | null;
}

/**
 * Constrói o GpUser canônico a partir da linha de `perfis`.
 * Porta fiel do mapeamento de getUserProfile() em auth.js.
 * Lê `setores`/`funcoes`; faz fallback para `areas` (nome legado da coluna).
 */
export function buildGpUser(data: PerfilData): GpUser {
  const cargo = normalizeCargo(data);
  const setores = Array.isArray(data.setores)
    ? data.setores
    : Array.isArray(data.areas)
      ? data.areas
      : [];
  const funcoes = Array.isArray(data.funcoes) ? data.funcoes : [];
  return {
    id: data.id,
    nome: data.nome || '',
    email: data.email || '',
    cargo,
    status: data.status || null,
    setores,
    funcoes,
    podeVerCpf: data.pode_ver_cpf_completo === true || cargo === 'dev' || cargo === 'admin',
    time: data.time || null,
    avatarUrl: data.avatar_url || null,
  };
}
