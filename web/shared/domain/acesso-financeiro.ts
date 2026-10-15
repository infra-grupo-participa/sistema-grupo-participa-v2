// Domínio puro. Espelha gp_pode_ver_financeiro() / gp_pode_operar_financeiro() no banco.
//
// Mora em shared/domain (não em modules/financeiro) desde 15/10/2026, quando o módulo Contas a Receber virou o
// departamento Financeiro (/financeiro, pedido do João): o registro de departamentos (`departamentos.ts`) precisa
// da MESMA regra para o gate do departamento, e shared/domain não importa de modules/. O módulo reexporta daqui
// (`modules/financeiro/domain/acesso.ts`), então tela, sidebar, home e departamento leem uma fonte só.
//
// Diferente de podeVer(), o financeiro NÃO libera 'visualizador': quem tem visão
// geral de leitura não enxerga dinheiro. Se as duas regras divergirem, a tela abre
// e vem vazia (o guard real é o do Postgres) — por isso elas andam juntas.
import type { GpUser } from './auth';

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
