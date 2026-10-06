// Regras puras do assistente de funil e do "Comecei um novo projeto": passos e validação por passo,
// ponto de partida (em branco ou modelo), checklist de boas práticas, integrações mínimas e agrupamento
// por projeto na lista de funis. A validação que trava salvar continua em domain/funis.ts (validarFunil).
import { funilDoModelo } from '../../domain/modelos';
import { etapasPadrao, type ProblemaFunil } from '../../domain/funis';
import type { CampoKey, EtapaKey, Funil, ModeloFunil, Vendedor } from '../../domain/types';

// ── Ícones do funil (só nomes que existem no mapa de shared/ui/icons.tsx) ──

export const ICONES_FUNIL: { nome: string; rotulo: string }[] = [
  { nome: 'kanban', rotulo: 'Quadro' },
  { nome: 'zap', rotulo: 'Raio' },
  { nome: 'target', rotulo: 'Alvo' },
  { nome: 'flame', rotulo: 'Chama' },
  { nome: 'video', rotulo: 'Vídeo' },
  { nome: 'calendar', rotulo: 'Calendário' },
  { nome: 'briefcase', rotulo: 'Maleta' },
  { nome: 'user-check', rotulo: 'Pessoa confirmada' },
  { nome: 'trending-up', rotulo: 'Crescimento' },
  { nome: 'megaphone', rotulo: 'Megafone' },
  { nome: 'send', rotulo: 'Envio' },
  { nome: 'message', rotulo: 'Mensagem' },
  { nome: 'phone', rotulo: 'Telefone' },
  { nome: 'mail', rotulo: 'E-mail' },
  { nome: 'users', rotulo: 'Pessoas' },
  { nome: 'trophy', rotulo: 'Troféu' },
  { nome: 'gem', rotulo: 'Diamante' },
  { nome: 'wallet', rotulo: 'Carteira' },
  { nome: 'rotate', rotulo: 'Recuperação' },
  { nome: 'star', rotulo: 'Estrela' },
  { nome: 'handshake', rotulo: 'Acordo' },
  { nome: 'globe', rotulo: 'Mundo' },
  { nome: 'chart', rotulo: 'Gráfico' },
  { nome: 'clipboard', rotulo: 'Prancheta' },
];

/** Ícone do funil com reserva: funil antigo sem ícone (ou com nome fora do mapa) cai no padrão do tipo. */
export function iconeDoFunil(f: Pick<Funil, 'icone' | 'tipo'>): string {
  if (f.icone && ICONES_FUNIL.some((i) => i.nome === f.icone)) return f.icone;
  return f.tipo === 'hotmart' ? 'zap' : 'kanban';
}

// ── Passos do assistente ──

export type PassoAssistente = 'partida' | 'geral' | 'etapas' | 'campanhas' | 'distribuicao' | 'revisao';

export const PASSOS: { k: PassoAssistente; rotulo: string }[] = [
  { k: 'partida', rotulo: 'Ponto de partida' },
  { k: 'geral', rotulo: 'Geral' },
  { k: 'etapas', rotulo: 'Etapas' },
  { k: 'campanhas', rotulo: 'Campanhas e integrações' },
  { k: 'distribuicao', rotulo: 'Distribuição' },
  { k: 'revisao', rotulo: 'Revisão' },
];

const CAMPOS_DO_PASSO: Record<PassoAssistente, string[]> = {
  partida: [],
  geral: ['nome', 'agrupador', 'eventos'],
  etapas: ['etapas'],
  campanhas: [],
  distribuicao: ['distribuicao'],
  revisao: ['nome', 'agrupador', 'eventos', 'etapas', 'distribuicao'],
};

/** Problemas (de validarFunil) que impedem avançar a partir deste passo. A revisão exige todos. */
export function problemasDoPasso(passo: PassoAssistente, problemas: ProblemaFunil[]): ProblemaFunil[] {
  const campos = CAMPOS_DO_PASSO[passo];
  return problemas.filter((p) => campos.includes(p.campo));
}

/** Passo mais adiante que dá para alcançar: o primeiro com pendência (ou a revisão). */
export function passoMaximo(problemas: ProblemaFunil[]): number {
  const i = PASSOS.findIndex((p) => p.k !== 'revisao' && problemasDoPasso(p.k, problemas).length > 0);
  return i < 0 ? PASSOS.length - 1 : i;
}

// ── Ponto de partida ──

/** Campanha de UTM sugerida para a chave do projeto (funil em branco). */
function campanhaUtm(chave: string, id: string) {
  return { id, nome: `Captação ${chave}`, canal: 'utm' as const, regra: `utm_campaign = ${chave}`, ativa: true, criadoEm: '' };
}

/**
 * Aplica o ponto de partida ao funil (ao sair do passo Geral, quando o modelo mudou). Modelo: etapas e
 * campanhas do modelo, com a chave do projeto no lugar de {chave}. Em branco: etapas do playbook e, com
 * chave, a campanha de UTM do projeto. Nome, ícone, agrupador e produto escolhidos ficam.
 */
export function aplicarPartida(f: Funil, modelo: ModeloFunil | null, chave: string | null, prefixoId: string): Funil {
  if (modelo) {
    const base = funilDoModelo(modelo, { agrupadorId: f.agrupadorId, produto: f.produto, chave, prefixoId });
    return { ...f, etapas: base.etapas, campanhas: base.campanhas, projeto: chave };
  }
  return { ...f, etapas: etapasPadrao(prefixoId), campanhas: chave ? [campanhaUtm(chave, `${prefixoId}-c1`)] : [], projeto: chave };
}

/**
 * Só a chave do projeto mudou (mesmo modelo): troca a chave nas campanhas sem mexer nas etapas já editadas.
 * Sem chave antiga e sem campanha, sugere as campanhas do modelo (ou a de UTM).
 */
export function trocarChave(f: Funil, antiga: string | null, nova: string | null, modelo: ModeloFunil | null, prefixoId: string): Funil {
  const troca = (s: string) => {
    if (!antiga) return s;
    return nova ? s.replaceAll(antiga, nova) : s.replaceAll(` ${antiga}`, '').replaceAll(antiga, '');
  };
  let campanhas = f.campanhas.map((c) => ({ ...c, nome: troca(c.nome), regra: troca(c.regra) }));
  if (!antiga && nova && !campanhas.length) {
    campanhas = modelo
      ? funilDoModelo(modelo, { agrupadorId: f.agrupadorId, produto: f.produto, chave: nova, prefixoId }).campanhas
      : [campanhaUtm(nova, `${prefixoId}-c1`)];
  }
  return { ...f, campanhas, projeto: nova };
}

/** Dados de capa ao escolher o ponto de partida: nome (se ainda for o do modelo anterior), ícone e entrada. */
export function capaDoModelo(f: Funil, modelo: ModeloFunil | null, nomeAnterior: string): Funil {
  const nomeLivre = !f.nome.trim() || f.nome === nomeAnterior;
  if (!modelo) return { ...f, nome: nomeLivre ? '' : f.nome, icone: 'kanban', tipo: 'manual', eventosHotmart: [] };
  return { ...f, nome: nomeLivre ? modelo.nome : f.nome, icone: modelo.icone, tipo: modelo.tipo, eventosHotmart: [...modelo.eventosHotmart] };
}

// ── Boas práticas (revisão) ──

export type SituacaoPratica = 'ok' | 'pendente' | 'nao_se_aplica';

export interface BoaPratica {
  id: 'ganho_no_fim' | 'pagamento_antes_ganho' | 'alerta_entrada' | 'qualificacao_antes_oferta' | 'criterio_escrito' | 'campanha_com_chave' | 'distribuicao_100';
  titulo: string;
  situacao: SituacaoPratica;
  /** O que falta (pendente) ou por que vale assim (ok / não se aplica). */
  detalhe: string;
}

const QUALIFICACAO: CampoKey[] = ['perfil_profissional', 'atua_com_holding', 'produto_interesse'];
const PAPEIS_OFERTA: EtapaKey[] = ['apresentar_oferta', 'negociar', 'aguardar_pagamento'];

/** Checklist de boas práticas calculado do próprio funil. Não trava a criação: orienta. */
export function boasPraticas(f: Pick<Funil, 'tipo' | 'eventosHotmart' | 'etapas' | 'campanhas' | 'distribuicao' | 'projeto'>, vendedores: Vendedor[]): BoaPratica[] {
  const r: BoaPratica[] = [];
  const es = f.etapas;
  const ganhos = es.filter((e) => e.papel === 'fechado');
  const ganhoNoFim = ganhos.length === 1 && es[es.length - 1]?.papel === 'fechado';
  r.push({
    id: 'ganho_no_fim', titulo: 'Uma etapa de Ganho, no fim',
    situacao: ganhoNoFim ? 'ok' : 'pendente',
    detalhe: ganhoNoFim ? 'Ganho só entra com pagamento aprovado na Hotmart.' : ganhos.length === 0 ? 'Falta a etapa de Ganho.' : ganhos.length > 1 ? 'Há mais de uma etapa de Ganho.' : 'A etapa de Ganho precisa ser a última.',
  });

  const iPag = es.findIndex((e) => e.papel === 'aguardar_pagamento');
  const iGanho = es.findIndex((e) => e.papel === 'fechado');
  const pagOk = iPag >= 0 && iGanho > iPag;
  r.push({
    id: 'pagamento_antes_ganho', titulo: 'Etapa de pagamento antes do ganho',
    situacao: pagOk ? 'ok' : 'pendente',
    detalhe: pagOk ? 'Boleto e Pix em aberto ficam visíveis até aprovar.' : 'Sem etapa de Pagamento, quem gerou boleto some no meio da negociação.',
  });

  const entradas = es.filter((e) => e.papel === 'primeiro_contato');
  const semAlerta = entradas.filter((e) => e.slaAtencaoMin == null || e.slaCriticoMin == null);
  r.push({
    id: 'alerta_entrada', titulo: 'Alerta de tempo nas etapas de entrada',
    situacao: entradas.length && !semAlerta.length ? 'ok' : 'pendente',
    detalhe: !entradas.length ? 'Nenhuma etapa com papel de Entrada: o tempo de resposta não é medido.'
      : semAlerta.length ? `Sem alerta: ${semAlerta.map((e) => e.nome || 'sem nome').join(', ')}.`
        : 'Lead novo não esfria sem ninguém ver.',
  });

  if (f.tipo === 'hotmart') {
    r.push({ id: 'qualificacao_antes_oferta', titulo: 'Campos de qualificação antes da oferta', situacao: 'nao_se_aplica', detalhe: 'Funil automático de checkout: a pessoa já escolheu o produto.' });
  } else {
    const iOferta = es.findIndex((e) => PAPEIS_OFERTA.includes(e.papel));
    const exigidos = new Set(es.slice(0, iOferta < 0 ? es.length : iOferta + 1).flatMap((e) => e.camposObrigatorios));
    const ok = iOferta >= 0 && QUALIFICACAO.some((c) => exigidos.has(c));
    r.push({
      id: 'qualificacao_antes_oferta', titulo: 'Campos de qualificação antes da oferta',
      situacao: ok ? 'ok' : 'pendente',
      detalhe: ok ? 'Ninguém recebe oferta sem perfil conhecido.' : iOferta < 0 ? 'Nenhuma etapa de Oferta, Negociação ou Pagamento.' : 'Exija perfil, se atua com holding ou produto de interesse até a etapa de oferta.',
    });
  }

  const semCriterio = es.filter((e) => e.papel !== 'fechado' && !e.criterio.trim());
  r.push({
    id: 'criterio_escrito', titulo: 'Critério de passagem escrito',
    situacao: semCriterio.length ? 'pendente' : 'ok',
    detalhe: semCriterio.length ? `Sem critério: ${semCriterio.map((e) => e.nome || 'sem nome').join(', ')}.` : 'Todo vendedor sabe quando mover o negócio.',
  });

  const ativas = f.campanhas.filter((c) => c.ativa && c.regra.trim());
  if (f.tipo === 'hotmart') {
    r.push({
      id: 'campanha_com_chave', titulo: 'Entrada configurada',
      situacao: f.eventosHotmart.length ? 'ok' : 'pendente',
      detalhe: f.eventosHotmart.length ? 'Os eventos da Hotmart criam os negócios.' : 'Escolha os eventos da Hotmart.',
    });
  } else {
    const comChave = f.projeto ? ativas.filter((c) => `${c.nome} ${c.regra}`.includes(f.projeto!)) : ativas;
    r.push({
      id: 'campanha_com_chave', titulo: 'Campanha com a chave do projeto',
      situacao: comChave.length ? 'ok' : 'pendente',
      detalhe: !ativas.length ? 'Sem campanha ativa, o negócio só entra criado à mão.'
        : f.projeto && !comChave.length ? `Nenhuma campanha usa a chave ${f.projeto}.`
          : f.projeto ? `A chave ${f.projeto} liga o lead ao ClickUp, ao Drive e ao utm_campaign.` : 'Defina a chave do projeto no passo Geral para amarrar a UTM.',
    });
  }

  if (!f.distribuicao) {
    r.push({ id: 'distribuicao_100', titulo: 'Distribuição somando 100%', situacao: 'ok', detalhe: 'Usa a distribuição geral do Comercial.' });
  } else {
    const ativos = new Set(vendedores.filter((v) => v.ativo).map((v) => v.id));
    const soma = f.distribuicao.filter((d) => ativos.has(d.vendedorId)).reduce((s, d) => s + d.percentual, 0);
    r.push({ id: 'distribuicao_100', titulo: 'Distribuição somando 100%', situacao: soma === 100 ? 'ok' : 'pendente', detalhe: soma === 100 ? 'Distribuição própria fechada.' : `Soma hoje: ${soma}%.` });
  }
  return r;
}

// ── Integrações mínimas (passo 4) ──

export interface Integracao { id: string; nome: string; explicacao: string }

/** Checklist mínimo para o funil funcionar sozinho. Todas "a conectar" até o backend existir. */
export function integracoesDoFunil(f: Pick<Funil, 'tipo' | 'campanhas'>): Integracao[] {
  const canais = new Set(f.campanhas.map((c) => c.canal));
  const lista: Integracao[] = [
    { id: 'hotmart', nome: 'Webhook da Hotmart', explicacao: 'Checkout abandonado, boleto e cartão recusado criam negócio; pagamento aprovado move para Ganho.' },
    { id: 'links', nome: 'Links rastreáveis por vendedor', explicacao: 'UTM do projeto e SCK com a sigla do vendedor: a venda cai no nome de quem trabalhou.' },
    { id: 'whatsapp', nome: 'Número oficial de WhatsApp', explicacao: 'Infobip ou Unnichat: conversa fica no histórico do contato e respeita a janela de 24 h.' },
  ];
  if (f.tipo === 'manual' || canais.has('formulario')) {
    lista.push({ id: 'formulario', nome: 'Formulário ou pesquisa', explicacao: 'A resposta da pesquisa vira negócio já com os campos de qualificação preenchidos.' });
  }
  lista.push({ id: 'slack', nome: 'Alertas no Slack', explicacao: 'Prazo crítico e lead sem dono avisam o canal do Comercial no mesmo minuto.' });
  return lista;
}

// ── Lista de funis agrupada por projeto ──

export interface GrupoProjeto<T> { projeto: string | null; funis: T[] }

/** Funis soltos primeiro; depois um grupo por projeto, na ordem em que o projeto aparece. */
export function agruparPorProjeto<T extends Pick<Funil, 'projeto'>>(funis: T[]): GrupoProjeto<T>[] {
  const soltos = funis.filter((f) => !f.projeto);
  const grupos = new Map<string, T[]>();
  for (const f of funis) {
    if (!f.projeto) continue;
    grupos.set(f.projeto, [...(grupos.get(f.projeto) ?? []), f]);
  }
  const r: GrupoProjeto<T>[] = soltos.length ? [{ projeto: null, funis: soltos }] : [];
  grupos.forEach((fs, projeto) => r.push({ projeto, funis: fs }));
  return r;
}

/** "A → B → C" com as etapas do funil (prévia nos cartões de modelo e de projeto). */
export function cadeiaEtapas(etapas: { nome: string }[]): string {
  return etapas.map((e) => e.nome).join(' → ');
}
