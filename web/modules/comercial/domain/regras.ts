// Regras do playbook do Comercial, puras e testáveis. O backend vai repetir as que travam escrita
// (campos obrigatórios, ganho só com pagamento, troca de dono só pelo gestor); aqui elas guiam a tela.
import { ETAPAS, etapa } from './catalogo';
import type {
  Atividade, CampoKey, Contato, EtapaKey, FaixaScore, Negocio, ProdutoKey, SinalRecuperacao, Supressao, Vendedor,
} from './types';

// ── Alerta de tempo na etapa (playbook, seção 4.2) ──

export type SituacaoSla = 'ok' | 'atencao' | 'critico' | 'sem_sla';

/**
 * Alerta de tempo parado na etapa. Usa o alerta da etapa personalizada do funil (`sla`) quando o negócio traz;
 * sem ele, o padrão do playbook para o papel da etapa.
 */
export function situacaoSla(n: Pick<Negocio, 'etapa' | 'etapaDesde' | 'status'> & { sla?: Negocio['sla'] }, agora: Date): SituacaoSla {
  if (n.status !== 'aberto') return 'sem_sla';
  const padrao = etapa(n.etapa);
  const atencao = n.sla !== undefined ? n.sla?.atencaoMin ?? null : padrao.slaAtencaoMin;
  const critico = n.sla !== undefined ? n.sla?.criticoMin ?? null : padrao.slaCriticoMin;
  if (atencao == null || critico == null) return 'sem_sla';
  const desde = new Date(n.etapaDesde).getTime();
  if (Number.isNaN(desde)) return 'sem_sla';
  const min = (agora.getTime() - desde) / 60000;
  if (min >= critico) return 'critico';
  if (min >= atencao) return 'atencao';
  return 'ok';
}

/** "há 12 min", "há 3 h", "há 2 dias" — tempo parado na etapa. */
export function tempoNaEtapa(desdeIso: string, agora: Date): string {
  const min = Math.max(0, Math.floor((agora.getTime() - new Date(desdeIso).getTime()) / 60000));
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  if (h < 24) return `${h} h`;
  const d = Math.floor(h / 24);
  return `${d} ${d === 1 ? 'dia' : 'dias'}`;
}

// ── Mudança de etapa (playbook, seções 4.2 e 4.3) ──

/** Campos que faltam para o negócio ENTRAR na etapa destino (inclui os das etapas puladas). */
export function camposFaltando(n: Pick<Negocio, 'campos'>, destino: EtapaKey): CampoKey[] {
  const ate = ETAPAS.findIndex((e) => e.key === destino);
  const exigidos = new Set<CampoKey>();
  ETAPAS.slice(0, ate + 1).forEach((e) => e.camposObrigatorios.forEach((c) => exigidos.add(c)));
  return [...exigidos].filter((c) => !String(n.campos[c] ?? '').trim());
}

export type BloqueioEtapa = 'ganho_so_com_pagamento' | 'campos_faltando' | 'negocio_encerrado' | null;

/** Pode mover para a etapa destino? "Fechado" só pela Hotmart: ganho é pagamento aprovado. */
export function bloqueioMudancaEtapa(n: Pick<Negocio, 'campos' | 'status'>, destino: EtapaKey): BloqueioEtapa {
  if (n.status !== 'aberto') return 'negocio_encerrado';
  if (destino === 'fechado') return 'ganho_so_com_pagamento';
  return camposFaltando(n, destino).length ? 'campos_faltando' : null;
}

/** Negócio aberto sem próxima atividade com data vira perdido (inegociável 4). */
export function semProximoPasso(n: Pick<Negocio, 'status' | 'proximaAtividade'>): boolean {
  return n.status === 'aberto' && !n.proximaAtividade;
}

export function atividadeAtrasada(a: Pick<Atividade, 'concluidaEm' | 'venceEm'>, agora: Date): boolean {
  return !a.concluidaEm && new Date(a.venceEm).getTime() < agora.getTime();
}

// ── Distribuição (playbook, seção 5.1) ──

/**
 * Dono de um negócio novo. Ordem: contato já tem dono → mesmo dono; senão, distribuição por percentual entre
 * os vendedores ativos, escolhendo quem está mais abaixo da sua cota (determinístico, sem sorteio).
 * `abertosPorVendedor` = quantos negócios cada um recebeu no ciclo atual.
 */
export function escolherDono(
  contato: Pick<Contato, 'donoId'>,
  vendedores: Vendedor[],
  recebidosNoCiclo: Record<string, number>,
): string | null {
  if (contato.donoId && vendedores.some((v) => v.id === contato.donoId && v.ativo)) return contato.donoId;
  const elegiveis = vendedores.filter((v) => v.ativo && v.percentual > 0);
  if (!elegiveis.length) return null;
  const total = elegiveis.reduce((s, v) => s + (recebidosNoCiclo[v.id] ?? 0), 0) + 1;
  let melhor: Vendedor | null = null;
  let maiorDeficit = -Infinity;
  for (const v of elegiveis) {
    const deficit = (v.percentual / 100) * total - (recebidosNoCiclo[v.id] ?? 0);
    if (deficit > maiorDeficit) { maiorDeficit = deficit; melhor = v; }
  }
  return melhor?.id ?? null;
}

export function somaPercentuais(vendedores: Vendedor[]): number {
  return vendedores.filter((v) => v.ativo).reduce((s, v) => s + v.percentual, 0);
}

// ── Score de recuperação (montar-fila-de-recuperacao.md, modelo do Acelera) ──

const PESO: Partial<Record<SinalRecuperacao, number>> = {
  boleto_aberto: 40, carrinho: 24, ficha_completa: 20, senhas: 16, chat: 12, workbook: 6, apostila: 4,
  pesquisa: 6, comunidade: 4, grupo: 3, advogado_contador: 4, quer_parceria: 6,
};

/** Comportamento de compra conta só o maior (boleto em aberto OU carrinho). Teto 100. */
export function calcularScore(sinais: SinalRecuperacao[]): number {
  const s = new Set(sinais);
  let total = s.has('boleto_aberto') ? 40 : s.has('carrinho') ? 24 : 0;
  for (const k of s) if (k !== 'boleto_aberto' && k !== 'carrinho') total += PESO[k] ?? 0;
  return Math.min(100, total);
}

export function faixaDoScore(score: number): FaixaScore {
  if (score >= 60) return 'A';
  if (score >= 40) return 'B';
  if (score >= 25) return 'C';
  return 'D';
}

/** Ninguém toca em C e D antes de A e B estarem zeradas. */
export function faixaLiberada(faixa: FaixaScore, pendentesAB: number): boolean {
  return faixa === 'A' || faixa === 'B' || pendentesAB === 0;
}

// ── Supressões de disparo (playbook, seção 7) ──

export interface CandidatoDisparo {
  contato: Pick<Contato, 'id' | 'optOut'>;
  negociosAbertosEtapas: EtapaKey[];
  ultimoDisparoEm: string | null;
  produtosComprados: ProdutoKey[];
}

export function motivoSupressao(c: CandidatoDisparo, produtoOfertado: ProdutoKey, agora: Date): Supressao | null {
  if (c.contato.optOut) return 'opt_out';
  if (c.produtosComprados.includes(produtoOfertado)) return 'ja_comprou';
  if (c.negociosAbertosEtapas.some((e) => e === 'negociar' || e === 'aguardar_pagamento')) return 'em_negociacao';
  if (c.ultimoDisparoEm && agora.getTime() - new Date(c.ultimoDisparoEm).getTime() < 48 * 3600_000) return 'disparo_48h';
  return null;
}

// ── Rastreabilidade (playbook, seção 8) ──

/** SCK no padrão `produto-acao-data-canal`, com a sigla do vendedor no fim. */
export function montarSck(produto: ProdutoKey, acao: string, data: Date, canal: string, sigla: string): string {
  const ymd = `${data.getFullYear()}${String(data.getMonth() + 1).padStart(2, '0')}${String(data.getDate()).padStart(2, '0')}`;
  const limpa = (s: string) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '');
  return [produto, limpa(acao), ymd, limpa(canal), limpa(sigla)].join('-');
}

// ── Telefone ──

/**
 * Chave de identidade por telefone = regra de `controle.fone_key` do banco (decisão D2): DDD + últimos 8 dígitos.
 * Junta celular com/sem o 9 e com/sem DDI 55 (pega quem compra com e-mail diferente), sem juntar DDDs diferentes.
 * Só dígitos; menos de 10 → null; 12/13 começando com 55 → DDD após o 55 + 8 últimos; 10/11 → 2 primeiros + 8
 * últimos; outro tamanho → 10 últimos.
 */
export function chaveTelefone(tel: string | null | undefined): string | null {
  const d = String(tel ?? '').replace(/\D/g, '');
  if (d.length < 10) return null;
  if ((d.length === 12 || d.length === 13) && d.startsWith('55')) return d.slice(2, 4) + d.slice(-8);
  if (d.length === 10 || d.length === 11) return d.slice(0, 2) + d.slice(-8);
  return d.slice(-10);
}

/** +55 (11) 98765-4321 a partir de dígitos E.164 ou nacionais. */
export function fmtTelefone(tel: string | null | undefined): string {
  if (!tel) return '—';
  let d = tel.replace(/\D/g, '');
  if (d.startsWith('55') && d.length >= 12) d = d.slice(2);
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return tel;
}
