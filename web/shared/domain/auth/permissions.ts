import type { GpUser } from './gp-user';

// API canônica de permissões (pura: recebe GpUser | null). Porta fiel de auth.js.

export const ehDev = (u: GpUser | null) => u?.cargo === 'dev';
export const ehAdmin = (u: GpUser | null) => u?.cargo === 'admin';
export const ehAdminOuAcima = (u: GpUser | null) => u?.cargo === 'dev' || u?.cargo === 'admin';
export const ehOperador = (u: GpUser | null) => u?.cargo === 'operador';
export const ehVisualizador = (u: GpUser | null) => u?.cargo === 'visualizador';

export function ehGestor(u: GpUser | null, setor?: string): boolean {
  if (u?.cargo !== 'gestor') return false;
  if (!setor) return (u.setores || []).length > 0;
  return (u.setores || []).includes(setor);
}

/** Pode VISUALIZAR a página de um setor? (porta de podeVer) */
export function podeVer(u: GpUser | null, setor: string): boolean {
  if (!setor || !u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'visualizador') return true;
  if (u.cargo === 'gestor' || u.cargo === 'operador') return (u.setores || []).includes(setor);
  return false;
}

/** Pode EDITAR (mutar dados) em um setor? (porta de podeEditar) */
export function podeEditar(u: GpUser | null, setor: string): boolean {
  if (!setor || !u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'visualizador') return false;
  if (u.cargo === 'gestor') return (u.setores || []).includes(setor);
  if (u.cargo === 'operador') {
    const temSetor = (u.setores || []).includes(setor);
    const temFuncaoSetor = (u.funcoes || []).some((f) => f && f.startsWith(setor + '.'));
    return temSetor && temFuncaoSetor;
  }
  return false;
}

/** Tem uma função específica? (porta de temFuncao) */
export function temFuncao(u: GpUser | null, funcao: string): boolean {
  if (!funcao || !u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'visualizador') return false;
  if (u.cargo === 'gestor') return (u.setores || []).includes(String(funcao).split('.')[0]);
  if (u.cargo === 'operador') return (u.funcoes || []).includes(funcao);
  return false;
}

/** Pode ver CPF/documento sem máscara? (LGPD, porta de podeVerCpf) */
export function podeVerCpf(u: GpUser | null): boolean {
  if (!u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  return u.podeVerCpf === true;
}

/** Mascara documento conforme podeVerCpf(). Porta fiel de mascarar(). */
export function mascarar(u: GpUser | null, valor: unknown): string {
  if (podeVerCpf(u)) return String(valor ?? '');
  const s = String(valor ?? '');
  if (!s.trim()) return s;
  const digits = s.replace(/\D/g, '');
  if (digits.length >= 4) {
    return '*'.repeat(Math.max(0, s.length - 4)) + digits.slice(-4);
  }
  return '*'.repeat(s.length);
}
