// Domínio puro. Espelha ra_pode_ver() no banco.
//
// Como o financeiro, NÃO libera 'visualizador': o módulo mostra nome e contato de
// quem pediu reembolso. Se as duas regras divergirem, a tela abre e vem vazia
// (o guard real é o do Postgres), por isso elas andam juntas.
import type { GpUser } from '@/shared/domain/auth';

export const SETOR_REMOCAO = 'remocao_acessos';

export function podeVerRemocao(u: GpUser | null): boolean {
  if (!u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'gestor' || u.cargo === 'operador') return (u.setores || []).includes(SETOR_REMOCAO);
  return false;
}
