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
  acesso?: AcessoV2 | null;
}

/** Contrato de public.gp_meu_acesso(), migration 20261007180503. */
export interface AcessoV2 {
  equipe: boolean;
  master: boolean;
  vinculos: { departamento: string; area: string | null; papel: 'responsavel' | 'membro' }[];
  capacidades: string[];
  ver: string[];
  editar: string[];
}

export function acessoValido(data: unknown): AcessoV2 | null {
  if (!data || typeof data !== 'object') return null;
  const a = data as Record<string, unknown>;
  if (typeof a.equipe !== 'boolean' || typeof a.master !== 'boolean' ||
      !Array.isArray(a.vinculos) || !Array.isArray(a.capacidades) || !Array.isArray(a.ver) || !Array.isArray(a.editar)) return null;
  if (!a.capacidades.every((x) => typeof x === 'string') || !a.ver.every((x) => typeof x === 'string') ||
      !a.editar.every((x) => typeof x === 'string')) return null;
  if (!a.vinculos.every((x) => x && typeof x === 'object' && typeof x.departamento === 'string' &&
      (x.area === null || typeof x.area === 'string') && (x.papel === 'responsavel' || x.papel === 'membro'))) return null;
  return a as unknown as AcessoV2;
}

/** Linha bruta de `perfis` (campos relevantes para auth). */
export interface PerfilData {
  id: string;
  nome?: string | null;
  email?: string | null;
  cargo?: string | null;
  status?: string | null;
  pode_ver_cpf_completo?: boolean | null;
  time?: string | null;
  avatar_url?: string | null;
  areas?: string[] | null;
  setores?: string[] | null;
  funcoes?: string[] | null;
}

/**
 * Constrói o GpUser canônico a partir da linha de `perfis`.
 * Modelo unificado (migration unifica_modelo_cargos_fase_a): cargo + areas (setores) + funcoes.
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

/** Domínio de e-mail da equipe. O sistema interno é exclusivo dele. */
export const DOMINIO_EQUIPE = '@advmais.com';

/**
 * O e-mail pertence à equipe? Regra do sistema interno: `auth.users` é compartilhada
 * pelos 7 sistemas do grupo (aluno, lead, workbook, CNHF…), então sessão válida não
 * basta — só entra quem tem e-mail do domínio da equipe.
 * Espelha `public.gp_eh_equipe()` no banco (migration 20260921).
 */
export function ehEmailDaEquipe(email: string | null | undefined): boolean {
  return String(email ?? '').trim().toLowerCase().endsWith(DOMINIO_EQUIPE);
}
