// Regras puras da tela de configuração do Comercial: rascunho da distribuição, simulador e formatos.
import { escolherDono, montarSck, somaPercentuais } from '../../domain/regras';
import type { ProdutoKey, Vendedor } from '../../domain/types';

export type RascunhoDistribuicao = Record<string, { percentual: number; ativo: boolean }>;

export function rascunhoDe(vendedores: Vendedor[]): RascunhoDistribuicao {
  return Object.fromEntries(vendedores.map((v) => [v.id, { percentual: v.percentual, ativo: v.ativo }]));
}

/** Vendedores com o rascunho aplicado (para somar e simular antes de salvar). */
export function aplicarRascunho(vendedores: Vendedor[], r: RascunhoDistribuicao): Vendedor[] {
  return vendedores.map((v) => ({ ...v, ...(r[v.id] ?? {}) }));
}

/** Percentual digitado → inteiro entre 0 e 100 (vazio vira 0). */
export function normalizarPercentual(txt: string): number {
  const n = Math.round(Number(String(txt).replace(',', '.')));
  if (!Number.isFinite(n)) return 0;
  return Math.max(0, Math.min(100, n));
}

export interface EstadoDistribuicao {
  soma: number;
  valida: boolean;
  alterada: boolean;
}

export function estadoDistribuicao(vendedores: Vendedor[], r: RascunhoDistribuicao): EstadoDistribuicao {
  const soma = somaPercentuais(aplicarRascunho(vendedores, r));
  const alterada = vendedores.some((v) => r[v.id] && (r[v.id].percentual !== v.percentual || r[v.id].ativo !== v.ativo));
  return { soma, valida: soma === 100, alterada };
}

/**
 * Para onde iriam os próximos `n` leads SEM dono, aplicando `escolherDono` em sequência
 * (cada escolha conta no ciclo da seguinte). null = ninguém elegível.
 */
export function simularDistribuicao(vendedores: Vendedor[], n: number): (string | null)[] {
  const recebidos: Record<string, number> = {};
  const saida: (string | null)[] = [];
  for (let i = 0; i < n; i++) {
    const id = escolherDono({ donoId: null }, vendedores, recebidos);
    saida.push(id);
    if (id) recebidos[id] = (recebidos[id] ?? 0) + 1;
  }
  return saida;
}

/** Prazo do playbook em minutos → "5 min", "24 h", "7 dias". */
export function fmtMinutos(min: number | null): string {
  if (min == null) return '—';
  if (min < 60) return `${min} min`;
  if (min < 24 * 60 || min % (24 * 60) !== 0) {
    const h = min / 60;
    return `${Number.isInteger(h) ? h : h.toFixed(1).replace('.', ',')} h`;
  }
  const d = min / (24 * 60);
  return `${d} ${d === 1 ? 'dia' : 'dias'}`;
}

/** Prévia do SCK do link novo (mesma função que o repositório usa ao criar). */
export function previaSck(produto: ProdutoKey, acao: string, canal: string, sigla: string | undefined, hoje: Date): string | null {
  if (!acao.trim() || !sigla) return null;
  return montarSck(produto, acao, hoje, canal, sigla);
}
