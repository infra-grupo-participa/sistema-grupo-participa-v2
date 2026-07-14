// Domínio puro. Espelha gp_pode_ver_financeiro() / gp_pode_operar_financeiro() no banco.
//
// Diferente de podeVer(), o financeiro NÃO libera 'visualizador': quem tem visão
// geral de leitura não enxerga dinheiro. Se as duas regras divergirem, a tela abre
// e vem vazia (o guard real é o do Postgres) — por isso elas andam juntas.
import type { GpUser } from '@/shared/domain/auth';

const SETOR = 'financeiro';

export function podeVerFinanceiro(u: GpUser | null): boolean {
  if (!u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'gestor' || u.cargo === 'operador') return (u.setores || []).includes(SETOR);
  return false;
}

export function podeOperarFinanceiro(u: GpUser | null): boolean {
  if (!u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'gestor') return (u.setores || []).includes(SETOR);
  if (u.cargo === 'operador') {
    return (u.setores || []).includes(SETOR) && (u.funcoes || []).includes('financeiro.operar');
  }
  return false;
}
