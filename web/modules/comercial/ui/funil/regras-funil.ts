// Regras de tela do funil, puras e testáveis: filtro da lista, resumo da faixa de números,
// o único sinal de urgência do card e o "quando" curto do próximo passo.
import { atividadeAtrasada, situacaoSla, tempoNaEtapa } from '../../domain/regras';
import type { Contato, Negocio } from '../../domain/types';

export type FiltroDono = 'todos' | 'meus' | 'sem_dono' | string;
/** Filtros que nascem dos números da faixa (clicar em "Sem dono 3" filtra o kanban). */
export type FiltroAlerta = 'critico' | 'sem_proximo' | 'sem_dono' | null;

export interface CriteriosFunil {
  dono: FiltroDono;
  busca: string;
  alerta: FiltroAlerta;
  vendedorId: string | null | undefined;
}

export function filtrarNegocios(
  negocios: Negocio[], f: CriteriosFunil, contatoPorId: Map<string, Pick<Contato, 'nome' | 'email' | 'telefone'>>, agora: Date,
): Negocio[] {
  const q = f.busca.trim().toLowerCase();
  return negocios.filter((n) => {
    if (f.dono === 'meus' && n.donoId !== f.vendedorId) return false;
    if (f.dono === 'sem_dono' && n.donoId) return false;
    if (!['todos', 'meus', 'sem_dono'].includes(f.dono) && n.donoId !== f.dono) return false;
    if (f.alerta) {
      // Alerta só faz sentido em negócio aberto: a coluna de ganho some enquanto o filtro vale.
      if (n.status !== 'aberto') return false;
      if (f.alerta === 'critico' && situacaoSla(n, agora) !== 'critico') return false;
      if (f.alerta === 'sem_proximo' && n.proximaAtividade) return false;
      if (f.alerta === 'sem_dono' && n.donoId) return false;
    }
    if (q) {
      const c = contatoPorId.get(n.contatoId);
      if (!`${c?.nome ?? ''} ${c?.email ?? ''} ${c?.telefone ?? ''}`.toLowerCase().includes(q)) return false;
    }
    return true;
  });
}

export interface ResumoFunil {
  abertos: number; valor: number; criticos: number; semProximo: number; semDono: number;
  /** Abertos em etapa de Negociação ou Pagamento (definição de METRICAS.em_negociacao) e o valor somado. */
  emNegociacao: number; valorNegociacao: number;
}

export function resumoFunil(negocios: Negocio[], agora: Date): ResumoFunil {
  const abertos = negocios.filter((n) => n.status === 'aberto');
  const negociando = abertos.filter((n) => n.etapa === 'negociar' || n.etapa === 'aguardar_pagamento');
  return {
    abertos: abertos.length,
    valor: abertos.reduce((s, n) => s + n.valor, 0),
    criticos: abertos.filter((n) => situacaoSla(n, agora) === 'critico').length,
    semProximo: abertos.filter((n) => !n.proximaAtividade).length,
    semDono: abertos.filter((n) => !n.donoId).length,
    emNegociacao: negociando.length,
    valorNegociacao: negociando.reduce((s, n) => s + n.valor, 0),
  };
}

export type MotivoUrgencia = 'sla_critico' | 'atrasada' | 'sem_proximo' | 'sem_dono' | 'sla_atencao';

export interface Urgencia {
  motivo: MotivoUrgencia;
  /** red = viola regra agora; yellow = atenção. */
  tom: 'red' | 'yellow';
  texto: string;
}

/**
 * O único sinal de urgência do card (o resto fica neutro). Ordem: prazo crítico da etapa, próximo passo
 * atrasado, sem próximo passo, sem dono e, por último, prazo de atenção.
 */
export function urgenciaDoNegocio(n: Negocio, agora: Date): Urgencia | null {
  if (n.status !== 'aberto') return null;
  const sla = situacaoSla(n, agora);
  const tempo = tempoNaEtapa(n.etapaDesde, agora);
  if (sla === 'critico') return { motivo: 'sla_critico', tom: 'red', texto: `Crítico · ${tempo} nesta etapa` };
  const prox = n.proximaAtividade;
  if (prox && atividadeAtrasada({ concluidaEm: null, venceEm: prox.venceEm }, agora)) {
    return { motivo: 'atrasada', tom: 'red', texto: `Atrasada ${tempoNaEtapa(prox.venceEm, agora)}` };
  }
  if (!prox) return { motivo: 'sem_proximo', tom: 'red', texto: 'Sem próximo passo' };
  if (!n.donoId) return { motivo: 'sem_dono', tom: 'red', texto: 'Sem dono' };
  if (sla === 'atencao') return { motivo: 'sla_atencao', tom: 'yellow', texto: `Atenção · ${tempo} nesta etapa` };
  return null;
}

/** Ordem do kanban: urgência primeiro (crítico, atenção, ok, sem alerta) e, empatado, quem está há mais tempo. */
export function ordenarPorUrgencia(negocios: Negocio[], agora: Date): Negocio[] {
  const peso = { critico: 0, atencao: 1, ok: 2, sem_sla: 3 } as const;
  return [...negocios].sort((a, b) => peso[situacaoSla(a, agora)] - peso[situacaoSla(b, agora)] || a.etapaDesde.localeCompare(b.etapaDesde));
}

/** "hoje 14:00", "amanhã 10:00", "ontem 09:00", "12/10 14:00". */
export function quandoCurto(iso: string, agora: Date): string {
  const d = new Date(iso);
  const hora = d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  const dia = (x: Date) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
  const diff = Math.round((dia(d) - dia(agora)) / 86400000);
  if (diff === 0) return `hoje ${hora}`;
  if (diff === 1) return `amanhã ${hora}`;
  if (diff === -1) return `ontem ${hora}`;
  return `${d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })} ${hora}`;
}
