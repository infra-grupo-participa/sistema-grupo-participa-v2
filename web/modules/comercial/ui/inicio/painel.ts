// Regras do painel de início, puras e testáveis: o que pede ação agora e o controle das 9h do gestor.
import { contaNaFila } from '../../domain/atendimento';
import { mesmoDia } from '../../domain/fechamento';
import { atividadeAtrasada, semProximoPasso, situacaoSla } from '../../domain/regras';
import type { Atividade, Conversa, FichaDisparo, Negocio, Vendedor } from '../../domain/types';

export type TipoAcao = 'sla_critico' | 'conversa' | 'atividade_atrasada' | 'sla_atencao' | 'atividade_hoje';

/** Ordem de urgência: prazo estourado e lead esperando vêm antes do que ainda cabe no dia. */
const PESO: Record<TipoAcao, number> = {
  sla_critico: 0, conversa: 1, atividade_atrasada: 2, sla_atencao: 3, atividade_hoje: 4,
};

export interface ItemAcao {
  id: string;
  tipo: TipoAcao;
  /** Negócio que abre no drawer. null = sem negócio (só conversa solta). */
  negocioId: string | null;
  contatoId: string;
  donoId: string | null;
  /** Referência de tempo para ordenar dentro do mesmo tipo (mais antigo primeiro). */
  quando: string;
  atividade?: Atividade;
  conversa?: Conversa;
  negocio?: Negocio;
}

/** Negócio de um contato para abrir: aberto antes de encerrado, do dono antes de outro, mais recente. */
export function negocioDoContato(negocios: Negocio[], contatoId: string, donoId: string | null): Negocio | null {
  const doContato = negocios.filter((n) => n.contatoId === contatoId);
  if (!doContato.length) return null;
  const nota = (n: Negocio) => (n.status === 'aberto' ? 0 : 2) + (donoId && n.donoId !== donoId ? 1 : 0);
  return [...doContato].sort((a, b) => nota(a) - nota(b) || b.criadoEm.localeCompare(a.criadoEm))[0];
}

/**
 * Lista "Agir agora". `donoId` = vendedor da sessão; null = time inteiro (visão do gestor).
 * Entra: negócio aberto com prazo em atenção/crítico, conversa com lead esperando resposta,
 * atividade atrasada e atividade de hoje ainda aberta.
 */
export function itensAgirAgora(p: {
  negocios: Negocio[]; conversas: Conversa[]; atividades: Atividade[]; donoId: string | null; agora: Date;
}): ItemAcao[] {
  const { negocios, conversas, atividades, donoId, agora } = p;
  const meu = (id: string | null) => donoId == null || id === donoId;
  const porId = new Map(negocios.map((n) => [n.id, n]));
  const itens: ItemAcao[] = [];

  for (const n of negocios) {
    if (n.status !== 'aberto' || !meu(n.donoId)) continue;
    const s = situacaoSla(n, agora);
    if (s === 'critico' || s === 'atencao') {
      itens.push({ id: `sla-${n.id}`, tipo: s === 'critico' ? 'sla_critico' : 'sla_atencao', negocioId: n.id, contatoId: n.contatoId, donoId: n.donoId, quando: n.etapaDesde, negocio: n });
    }
  }

  for (const c of conversas) {
    if (c.naoLidas <= 0 || !c.atribuidaA || !meu(c.atribuidaA) || !contaNaFila(c)) continue;
    const n = negocioDoContato(negocios, c.contatoId, c.atribuidaA);
    itens.push({ id: `conv-${c.contatoId}`, tipo: 'conversa', negocioId: n?.id ?? null, contatoId: c.contatoId, donoId: c.atribuidaA, quando: c.ultimaMensagem.em, conversa: c, negocio: n ?? undefined });
  }

  for (const a of atividades) {
    if (a.concluidaEm || !meu(a.donoId)) continue;
    const n = a.negocioId ? porId.get(a.negocioId) : negocioDoContato(negocios, a.contatoId, a.donoId) ?? undefined;
    if (n && n.status !== 'aberto') continue;
    const atrasada = atividadeAtrasada(a, agora);
    if (!atrasada && !mesmoDia(a.venceEm, agora)) continue;
    itens.push({ id: `atv-${a.id}`, tipo: atrasada ? 'atividade_atrasada' : 'atividade_hoje', negocioId: n?.id ?? null, contatoId: a.contatoId, donoId: a.donoId, quando: a.venceEm, atividade: a, negocio: n });
  }

  return itens.sort((a, b) => PESO[a.tipo] - PESO[b.tipo] || a.quando.localeCompare(b.quando));
}

export type Urgencia = 'atrasado' | 'agora' | 'hoje';
export const ROTULO_URGENCIA: Record<Urgencia, string> = { atrasado: 'Atrasado', agora: 'Agora', hoje: 'Hoje' };

/** Faixa de urgência de cada tipo: prazo estourado e atividade vencida, o que pede resposta já, e o resto do dia. */
export const URGENCIA: Record<TipoAcao, Urgencia> = {
  sla_critico: 'atrasado', atividade_atrasada: 'atrasado', conversa: 'agora', sla_atencao: 'agora', atividade_hoje: 'hoje',
};

/** Agrupa a lista (já ordenada) por urgência, mantendo a ordem e omitindo grupos vazios. */
export function agruparPorUrgencia(itens: ItemAcao[]): { urgencia: Urgencia; itens: ItemAcao[] }[] {
  return (['atrasado', 'agora', 'hoje'] as Urgencia[])
    .map((u) => ({ urgencia: u, itens: itens.filter((i) => URGENCIA[i.tipo] === u) }))
    .filter((g) => g.itens.length);
}

export interface CargaVendedor {
  vendedorId: string;
  abertos: number;
  criticos: number;
  semProximo: number;
  atrasadas: number;
}

/** Carga por vendedor ativo: negócios abertos, prazo crítico, sem próximo passo e atividades atrasadas. */
export function cargaPorVendedor(negocios: Negocio[], atividades: Atividade[], vendedores: Vendedor[], agora: Date): CargaVendedor[] {
  return vendedores
    .filter((v) => v.ativo)
    .map((v) => {
      const abertos = negocios.filter((n) => n.status === 'aberto' && n.donoId === v.id);
      return {
        vendedorId: v.id,
        abertos: abertos.length,
        criticos: abertos.filter((n) => situacaoSla(n, agora) === 'critico').length,
        semProximo: abertos.filter(semProximoPasso).length,
        atrasadas: atividades.filter((a) => a.donoId === v.id && atividadeAtrasada(a, agora)).length,
      };
    })
    .sort((a, b) => b.abertos - a.abertos);
}

export interface Controle9h {
  semDono: Negocio[];
  perdidosOutroVendedor: Negocio[];
  semProximo: Negocio[];
  fichasAguardando: FichaDisparo[];
}

/** Conferência das 9h do gestor (playbook, seção 5.2). Meta de cada lista: zero. */
export function controle9h(negocios: Negocio[], fichas: FichaDisparo[], agora: Date): Controle9h {
  return {
    semDono: negocios.filter((n) => n.status === 'aberto' && !n.donoId),
    perdidosOutroVendedor: negocios.filter((n) => n.status === 'perdido' && n.motivoPerda === 'ja_atendido_outro_vendedor' && mesmoDia(n.fechadoEm, agora)),
    semProximo: negocios.filter(semProximoPasso),
    fichasAguardando: fichas.filter((f) => f.status === 'aguardando_aprovacao'),
  };
}

/** "Bom dia" / "Boa tarde" / "Boa noite" pela hora de Brasília. */
export function saudacao(agora: Date): string {
  const h = Number(agora.toLocaleString('en-US', { timeZone: 'America/Sao_Paulo', hour: 'numeric', hour12: false })) % 24;
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
}

// ── Perspectiva (gestor vendo o painel de um vendedor) ──

export const VER_TIME = 'time';

export interface Perspectiva {
  /** Dono dos dados mostrados. null = time inteiro. */
  donoId: string | null;
  /** De quem é o painel personalizado mostrado. */
  painelDe: string;
  /** Gestor olhando o painel de outra pessoa (sem trocar a sessão). */
  deOutro: boolean;
}

/** Vendedor só vê o próprio; o gestor (e o leitor, que vê como ele) escolhe entre o time e qualquer vendedor (`ver`). */
export function perspectiva(sessao: { vendedorId: string; papel: 'gestor' | 'vendedor' | 'leitor' }, ver: string): Perspectiva {
  const visaoTime = sessao.papel === 'gestor' || sessao.papel === 'leitor';
  if (!visaoTime || ver === VER_TIME) return { donoId: visaoTime ? null : sessao.vendedorId, painelDe: sessao.vendedorId, deOutro: false };
  return { donoId: ver, painelDe: ver, deOutro: ver !== sessao.vendedorId };
}

/** "Jonathan Mendes" → "Jonathan"; nome curto fica inteiro ("Marcos Paulo"). */
export function nomeCurto(nome: string): string {
  return nome.length <= 12 ? nome : nome.split(' ')[0];
}

export interface CargaPessoa extends Omit<CargaVendedor, 'vendedorId'> {
  conversasEsperando: number;
}

/** Carga de quem está no painel (null = time inteiro), com as conversas esperando resposta. */
export function cargaDe(p: { negocios: Negocio[]; atividades: Atividade[]; conversas: Conversa[]; donoId: string | null; agora: Date }): CargaPessoa {
  const { negocios, atividades, conversas, donoId, agora } = p;
  const meu = (id: string | null) => (donoId == null ? true : id === donoId);
  const abertos = negocios.filter((n) => n.status === 'aberto' && meu(n.donoId));
  return {
    abertos: abertos.length,
    criticos: abertos.filter((n) => situacaoSla(n, agora) === 'critico').length,
    semProximo: abertos.filter(semProximoPasso).length,
    atrasadas: atividades.filter((a) => meu(a.donoId) && atividadeAtrasada(a, agora)).length,
    conversasEsperando: conversas.filter((c) => c.naoLidas > 0 && c.atribuidaA && meu(c.atribuidaA) && contaNaFila(c)).length,
  };
}
