// Construtor de funis: regras puras. Cada funil tem etapas próprias, mas toda etapa declara um PAPEL do
// playbook (entrada, qualificação, oferta, negociação, pagamento, ganho). É o papel que faz as regras da
// casa valerem em qualquer funil que alguém criar.
import { ETAPAS } from './catalogo';
import type { CampoKey, CorEtapa, EtapaFunil, EtapaKey, Funil, Negocio, Vendedor } from './types';

export const ROTULO_PAPEL: Record<EtapaKey, string> = {
  primeiro_contato: 'Entrada (primeiro contato)',
  qualificar: 'Qualificação',
  apresentar_oferta: 'Oferta',
  negociar: 'Negociação',
  aguardar_pagamento: 'Pagamento',
  fechado: 'Ganho',
};

export const AJUDA_PAPEL: Record<EtapaKey, string> = {
  primeiro_contato: 'Lead chegou e espera o primeiro contato. Conta para o tempo de resposta.',
  qualificar: 'Conversa em andamento. Conta como "respondeu" no fechamento do dia.',
  apresentar_oferta: 'Oferta apresentada.',
  negociar: 'Conta como "em negociação" e fica fora de disparo em massa.',
  aguardar_pagamento: 'Pagamento em andamento. Também fica fora de disparo em massa.',
  fechado: 'Ganho. Só entra com pagamento aprovado na Hotmart: ninguém move para cá à mão.',
};

/** Cor da etapa → token do tema. */
export const COR_ETAPA: Record<CorEtapa, string> = {
  neutral: 'var(--fg-3)',
  accent: 'var(--accent)',
  info: 'var(--info)',
  cyan: 'var(--cyan)',
  purple: 'var(--purple)',
  yellow: 'var(--yellow)',
  green: 'var(--green)',
  red: 'var(--red)',
};
export const CORES_ETAPA = Object.keys(COR_ETAPA) as CorEtapa[];

const COR_PADRAO: Record<EtapaKey, CorEtapa> = {
  primeiro_contato: 'info', qualificar: 'cyan', apresentar_oferta: 'purple', negociar: 'accent', aguardar_pagamento: 'yellow', fechado: 'green',
};

/** As 6 etapas do playbook como ponto de partida de um funil novo. */
export function etapasPadrao(prefixo = 'e'): EtapaFunil[] {
  return ETAPAS.map((e) => ({
    id: `${prefixo}-${e.key}`,
    nome: e.label,
    papel: e.key,
    cor: COR_PADRAO[e.key],
    slaAtencaoMin: e.slaAtencaoMin,
    slaCriticoMin: e.slaCriticoMin,
    camposObrigatorios: [...e.camposObrigatorios],
    criterio: e.criterio,
  }));
}

export function etapaDoFunil(f: Funil | undefined, etapaId: string): EtapaFunil | undefined {
  return f?.etapas.find((e) => e.id === etapaId);
}

export interface ProblemaFunil { campo: string; msg: string }

/** O que impede salvar o funil. Lista vazia = pode salvar. */
export function validarFunil(f: Pick<Funil, 'nome' | 'agrupadorId' | 'tipo' | 'eventosHotmart' | 'etapas' | 'distribuicao'>, vendedores: Vendedor[]): ProblemaFunil[] {
  const p: ProblemaFunil[] = [];
  if (!f.nome.trim()) p.push({ campo: 'nome', msg: 'Dê um nome ao funil.' });
  if (!f.agrupadorId) p.push({ campo: 'agrupador', msg: 'Escolha o agrupador.' });
  if (f.tipo === 'hotmart' && !f.eventosHotmart.length) p.push({ campo: 'eventos', msg: 'Funil automático precisa de ao menos um evento da Hotmart.' });
  if (f.etapas.length < 2) p.push({ campo: 'etapas', msg: 'O funil precisa de pelo menos 2 etapas.' });
  if (f.etapas.some((e) => !e.nome.trim())) p.push({ campo: 'etapas', msg: 'Toda etapa precisa de nome.' });
  const nomes = f.etapas.map((e) => e.nome.trim().toLowerCase());
  if (new Set(nomes).size !== nomes.length) p.push({ campo: 'etapas', msg: 'Há duas etapas com o mesmo nome.' });
  const ganhos = f.etapas.filter((e) => e.papel === 'fechado');
  if (ganhos.length !== 1) p.push({ campo: 'etapas', msg: 'O funil precisa de exatamente uma etapa de Ganho.' });
  else if (f.etapas[f.etapas.length - 1].papel !== 'fechado') p.push({ campo: 'etapas', msg: 'A etapa de Ganho precisa ser a última.' });
  for (const e of f.etapas) {
    if ((e.slaAtencaoMin == null) !== (e.slaCriticoMin == null)) p.push({ campo: 'etapas', msg: `"${e.nome}": preencha os dois alertas ou nenhum.` });
    else if (e.slaAtencaoMin != null && e.slaCriticoMin != null && e.slaAtencaoMin >= e.slaCriticoMin) p.push({ campo: 'etapas', msg: `"${e.nome}": o alerta crítico precisa vir depois do de atenção.` });
  }
  if (f.distribuicao) {
    const ativos = new Set(vendedores.filter((v) => v.ativo).map((v) => v.id));
    const soma = f.distribuicao.filter((d) => ativos.has(d.vendedorId)).reduce((s, d) => s + d.percentual, 0);
    if (soma !== 100) p.push({ campo: 'distribuicao', msg: 'A distribuição própria precisa somar 100%.' });
  }
  return p;
}

/** Campos que faltam para ENTRAR na etapa destino (inclui os das etapas anteriores). */
export function camposFaltandoNoFunil(n: Pick<Negocio, 'campos'>, f: Funil, destinoId: string): CampoKey[] {
  const ate = f.etapas.findIndex((e) => e.id === destinoId);
  if (ate < 0) return [];
  const exigidos = new Set<CampoKey>();
  f.etapas.slice(0, ate + 1).forEach((e) => e.camposObrigatorios.forEach((c) => exigidos.add(c)));
  return [...exigidos].filter((c) => !String(n.campos[c] ?? '').trim());
}

export type BloqueioMover = 'ganho_so_com_pagamento' | 'campos_faltando' | 'negocio_encerrado' | 'etapa_inexistente' | null;

export function bloqueioMoverNoFunil(n: Pick<Negocio, 'campos' | 'status'>, f: Funil, destinoId: string): BloqueioMover {
  if (n.status !== 'aberto') return 'negocio_encerrado';
  const d = etapaDoFunil(f, destinoId);
  if (!d) return 'etapa_inexistente';
  if (d.papel === 'fechado') return 'ganho_so_com_pagamento';
  return camposFaltandoNoFunil(n, f, destinoId).length ? 'campos_faltando' : null;
}

/** Etapa onde um negócio novo entra: a primeira. */
export function etapaInicial(f: Funil): EtapaFunil {
  return f.etapas[0];
}

/** Uma etapa pode ser removida do editor se não tem negócio aberto nela. */
export function podeRemoverEtapa(etapaId: string, negociosDoFunil: Pick<Negocio, 'etapaId' | 'status'>[]): boolean {
  return !negociosDoFunil.some((n) => n.etapaId === etapaId && n.status === 'aberto');
}

/** "5 min", "24 h", "7 dias" — para mostrar alertas configurados. */
export function fmtMinutos(min: number | null): string {
  if (min == null) return '—';
  if (min < 60) return `${min} min`;
  if (min < 24 * 60 || min % (24 * 60) !== 0) return `${Math.round(min / 60)} h`;
  const d = min / (24 * 60);
  return `${d} ${d === 1 ? 'dia' : 'dias'}`;
}
