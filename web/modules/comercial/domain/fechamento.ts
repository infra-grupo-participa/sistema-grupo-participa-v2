// Fechamento do dia (playbook, seção 12). Números com definição exata, no total e por vendedor.
import { atividadeAtrasada, semProximoPasso } from './regras';
import type { Atividade, EventoTimeline, MotivoPerda, Negocio, ProdutoKey } from './types';

export interface LinhaFechamento {
  abordados: number;
  entraramEmContato: number;
  responderam: number;
  emNegociacao: number;
  entraramEmNegociacaoHoje: number;
  vendas: number;
  receita: number;
}

export interface FechamentoDia {
  total: LinhaFechamento;
  porVendedor: Record<string, LinhaFechamento>;
  vendasPorProduto: { produto: ProdutoKey; quantidade: number; valor: number }[];
  alertas: {
    semProximaAtividade: number;
    atrasadasPorVendedor: Record<string, number>;
    semDono: number;
    perdidosPorMotivo: Partial<Record<MotivoPerda, number>>;
  };
}

const vazia = (): LinhaFechamento => ({
  abordados: 0, entraramEmContato: 0, responderam: 0, emNegociacao: 0, entraramEmNegociacaoHoje: 0, vendas: 0, receita: 0,
});

/** Mesmo dia no fuso de Brasília. */
export function mesmoDia(iso: string | null | undefined, dia: Date): boolean {
  if (!iso) return false;
  const f = (d: Date) => d.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo' });
  return f(new Date(iso)) === f(dia);
}

export function calcularFechamento(
  negocios: Negocio[],
  atividades: Atividade[],
  eventos: EventoTimeline[],
  dia: Date,
): FechamentoDia {
  const total = vazia();
  const porVendedor: Record<string, LinhaFechamento> = {};
  const linha = (id: string | null) => (id ? (porVendedor[id] ??= vazia()) : null);
  const somar = (id: string | null, k: keyof LinhaFechamento, n = 1) => {
    total[k] += n;
    const l = linha(id);
    if (l) l[k] += n;
  };

  // Abordados: leads únicos com contato ativo concluído no dia (WhatsApp ou ligação).
  const abordados = new Map<string, string>();
  for (const a of atividades) {
    if ((a.tipo === 'whatsapp' || a.tipo === 'ligacao') && mesmoDia(a.concluidaEm, dia)) abordados.set(a.contatoId, a.donoId);
  }
  abordados.forEach((dono) => somar(dono, 'abordados'));

  const negocioPorId = new Map(negocios.map((n) => [n.id, n]));
  const contatosQueEntraram = new Set<string>();
  const responderam = new Set<string>();
  for (const e of eventos) {
    if (!mesmoDia(e.em, dia)) continue;
    const n = e.negocioId ? negocioPorId.get(e.negocioId) : undefined;
    if (e.tipo === 'mensagem' && e.titulo.startsWith('Lead escreveu') && !abordados.has(e.contatoId) && !contatosQueEntraram.has(e.contatoId)) {
      contatosQueEntraram.add(e.contatoId);
      somar(n?.donoId ?? null, 'entraramEmContato');
    }
    if (e.tipo === 'etapa' && e.detalhe === 'qualificar' && !responderam.has(e.contatoId)) {
      responderam.add(e.contatoId);
      somar(n?.donoId ?? null, 'responderam');
    }
    if (e.tipo === 'etapa' && e.detalhe === 'negociar') somar(n?.donoId ?? null, 'entraramEmNegociacaoHoje');
  }

  const vendasProduto = new Map<ProdutoKey, { quantidade: number; valor: number }>();
  const perdidosPorMotivo: Partial<Record<MotivoPerda, number>> = {};
  let semProximaAtividade = 0;
  let semDono = 0;
  for (const n of negocios) {
    if (n.status === 'aberto' && (n.etapa === 'negociar' || n.etapa === 'aguardar_pagamento')) somar(n.donoId, 'emNegociacao');
    if (n.status === 'ganho' && mesmoDia(n.fechadoEm, dia)) {
      somar(n.donoId, 'vendas');
      somar(n.donoId, 'receita', n.valor);
      const v = vendasProduto.get(n.produto) ?? { quantidade: 0, valor: 0 };
      vendasProduto.set(n.produto, { quantidade: v.quantidade + 1, valor: v.valor + n.valor });
    }
    if (n.status === 'perdido' && n.motivoPerda && mesmoDia(n.fechadoEm, dia)) {
      perdidosPorMotivo[n.motivoPerda] = (perdidosPorMotivo[n.motivoPerda] ?? 0) + 1;
    }
    if (semProximoPasso(n)) semProximaAtividade++;
    if (n.status === 'aberto' && !n.donoId) semDono++;
  }

  const atrasadasPorVendedor: Record<string, number> = {};
  for (const a of atividades) {
    if (atividadeAtrasada(a, dia)) atrasadasPorVendedor[a.donoId] = (atrasadasPorVendedor[a.donoId] ?? 0) + 1;
  }

  return {
    total,
    porVendedor,
    vendasPorProduto: [...vendasProduto].map(([produto, v]) => ({ produto, ...v })),
    alertas: { semProximaAtividade, atrasadasPorVendedor, semDono, perdidosPorMotivo },
  };
}

/** Conversão entre etapas do funil: quantos chegaram a cada etapa (negócio que passou dela conta). */
export function funilPorEtapa(negocios: Negocio[], ordem: string[]): { etapa: string; chegaram: number }[] {
  return ordem.map((e, i) => ({
    etapa: e,
    chegaram: negocios.filter((n) => n.status === 'ganho' || ordem.indexOf(n.etapa) >= i).length,
  }));
}
