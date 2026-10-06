// Regras puras da tela de disparos: simulador de supressões, conflito de agenda (48 h) e taxas do resultado.
import { motivoSupressao } from '../../domain/regras';
import type { Contato, FichaDisparo, Negocio, ProdutoKey, Supressao } from '../../domain/types';

const H48 = 48 * 3600_000;

export interface Simulacao {
  base: number;
  suprimidos: number;
  elegiveis: number;
  porMotivo: Record<Supressao, number>;
}

/**
 * Aplica as 4 supressões obrigatórias sobre a base. Sem log de disparo no mock, `ultimoDisparoEm` é null;
 * "já comprou" = produtos dos negócios ganhos do contato.
 */
export function simularSupressoes(
  contatos: Pick<Contato, 'id' | 'optOut'>[],
  negocios: Pick<Negocio, 'contatoId' | 'status' | 'etapa' | 'produto'>[],
  produtoOfertado: ProdutoKey,
  agora: Date,
): Simulacao {
  const porContato = new Map<string, typeof negocios>();
  for (const n of negocios) {
    const l = porContato.get(n.contatoId) ?? [];
    l.push(n);
    porContato.set(n.contatoId, l);
  }
  const porMotivo: Record<Supressao, number> = { em_negociacao: 0, disparo_48h: 0, opt_out: 0, ja_comprou: 0 };
  let suprimidos = 0;
  for (const c of contatos) {
    const ns = porContato.get(c.id) ?? [];
    const m = motivoSupressao({
      contato: c,
      negociosAbertosEtapas: ns.filter((n) => n.status === 'aberto').map((n) => n.etapa),
      ultimoDisparoEm: null,
      produtosComprados: ns.filter((n) => n.status === 'ganho').map((n) => n.produto),
    }, produtoOfertado, agora);
    if (m) { porMotivo[m] += 1; suprimidos += 1; }
  }
  return { base: contatos.length, suprimidos, elegiveis: contatos.length - suprimidos, porMotivo };
}

/** Fichas que contam na agenda (rascunho e reprovada não saem). */
export function contaNaAgenda(f: Pick<FichaDisparo, 'status'>): boolean {
  return f.status !== 'rascunho' && f.status !== 'reprovada';
}

/**
 * Ids das fichas em conflito: mesmo produto a menos de 48 h uma da outra.
 * Regra: a mesma pessoa não recebe disparo da casa em 48 h.
 */
export function fichasEmConflito(fichas: Pick<FichaDisparo, 'id' | 'produto' | 'agendadoPara' | 'status'>[]): Set<string> {
  const ativas = fichas.filter(contaNaAgenda);
  const ids = new Set<string>();
  for (let i = 0; i < ativas.length; i++) {
    for (let j = i + 1; j < ativas.length; j++) {
      const a = ativas[i];
      const b = ativas[j];
      if (a.produto !== b.produto) continue;
      if (Math.abs(new Date(a.agendadoPara).getTime() - new Date(b.agendadoPara).getTime()) < H48) {
        ids.add(a.id);
        ids.add(b.id);
      }
    }
  }
  return ids;
}

/** Fichas do mesmo produto a menos de 48 h de um horário proposto (aviso na ficha nova). */
export function conflitosCom(
  fichas: Pick<FichaDisparo, 'id' | 'produto' | 'agendadoPara' | 'status'>[],
  produto: ProdutoKey,
  quandoIso: string,
): string[] {
  const t = new Date(quandoIso).getTime();
  if (Number.isNaN(t)) return [];
  return fichas
    .filter((f) => contaNaAgenda(f) && f.produto === produto && Math.abs(new Date(f.agendadoPara).getTime() - t) < H48)
    .map((f) => f.id);
}

/** Dias da agenda: de `antes` dias atrás até `depois` dias à frente, em datas locais (meia-noite). */
export function diasDaAgenda(agora: Date, antes = 7, depois = 7): Date[] {
  const base = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate());
  return Array.from({ length: antes + depois + 1 }, (_, i) => new Date(base.getFullYear(), base.getMonth(), base.getDate() - antes + i));
}

export function mesmoDia(a: Date, b: Date): boolean {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

/** Taxas do resultado sobre o que foi entregue (falhas sobre o enviado). */
export function taxasResultado(r: NonNullable<FichaDisparo['resultado']>) {
  const pct = (n: number, d: number) => (d ? Math.round((n / d) * 100) : 0);
  return {
    leitura: pct(r.lidas, r.entregues),
    resposta: pct(r.respostas, r.entregues),
    falha: pct(r.falhas, r.entregues + r.falhas),
  };
}

/** Partes do texto do template, separando as variáveis {{x}} para destacar. */
export function partesTemplate(texto: string): { texto: string; variavel: boolean }[] {
  return texto.split(/(\{\{[^}]+\}\})/g).filter(Boolean).map((t) => ({ texto: t, variavel: /^\{\{[^}]+\}\}$/.test(t) }));
}

export interface ResumoDisparos {
  aguardando: number;
  /** Fichas que contam na agenda, agendadas de agora até 7 dias à frente. */
  proximos7: number;
  /** Fichas em conflito de 48 h (as duas pontas contam). */
  conflitos: number;
  /** Somas das fichas com resultado; taxas sobre essas somas (null sem resultado). */
  entregues: number;
  leitura: number | null;
  resposta: number | null;
}

/** Números da faixa do topo de Disparos. */
export function resumoDisparos(fichas: Pick<FichaDisparo, 'id' | 'produto' | 'agendadoPara' | 'status' | 'resultado'>[], agora: Date): ResumoDisparos {
  const ini = agora.getTime();
  const fim = ini + 7 * 24 * 3600_000;
  const proximos7 = fichas.filter((f) => {
    const t = new Date(f.agendadoPara).getTime();
    return contaNaAgenda(f) && t >= ini && t <= fim;
  }).length;
  const comResultado = fichas.map((f) => f.resultado).filter((r): r is NonNullable<FichaDisparo['resultado']> => !!r);
  const soma = (k: 'entregues' | 'lidas' | 'respostas') => comResultado.reduce((s, r) => s + r[k], 0);
  const entregues = soma('entregues');
  const pct = (n: number) => (entregues ? Math.round((n / entregues) * 100) : null);
  return {
    aguardando: fichas.filter((f) => f.status === 'aguardando_aprovacao').length,
    proximos7,
    conflitos: fichasEmConflito(fichas).size,
    entregues,
    leitura: pct(soma('lidas')),
    resposta: pct(soma('respostas')),
  };
}
