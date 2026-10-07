// Estratégias na demonstração (NEXT_PUBLIC_COMERCIAL_FONTE ausente): mesmo contrato e mesmas mensagens das RPCs da
// migration 20261007150701, com uma base de alunos fictícia (nomes inventados). Nada sai do navegador.
import type { EstrategiasRepository, ResultadoAcao } from '../application/estrategias-ports';
import type { Resultado } from '../application/ports';
import {
  LIMITE_FILA, LIMITE_FUNIL, filtrosVazios, limparFiltros, podeTransformar, proximasSituacoes, validarFiltros, validarSolicitacao,
  type AcessoEstrategias, type Estrategia, type FiltrosPublico, type ModeloPublico, type NovaSolicitacao, type OpcoesFiltro,
  type PreviaPublico, type SituacaoEstrategia, type TipoAcao,
} from '../domain/estrategias';
import type { ProdutoKey } from '../domain/types';

const agoraIso = () => new Date().toISOString();

/** Modelo pronto do caso da Dra. Elaine (o mesmo semeado no banco). */
export const MODELO_PROPRIA_HOLDING: ModeloPublico = {
  chave: 'alunos_querem_propria_holding',
  nome: 'Alunos que querem a própria holding',
  descricao: 'Alunos do Time Holding Brasil que, nas pesquisas, disseram que querem fazer a própria holding e ainda não '
    + 'compraram Sessão de Viabilidade, Croqui ou a Holding do escritório. Potenciais clientes da escada A.',
  filtros: {
    base: 'alunos',
    alunos: { tiposTurma: ['thb'] },
    respondi: {
      regras: [
        { perguntas: ['O seu interesse hoje é:'], contem: ['fazer a minha holding'] },
        { perguntas: ['Em qual Nível você está hoje?'], contem: ['nível pessoal'] },
        { perguntas: ['Qual seu objetivo com Holding Familiar?'], contem: ['fazer a minha'] },
        { perguntas: ['1. Por que você ingressou no Treinamento Holding Masters? Qual é o seu objetivo?'], contem: ['fazer a minha', 'própria holding'] },
      ],
    },
    naoComprou: { produtos: ['1663254', '1664749', '5238525', '1542521', '5243340', '3595938', '5301413'] },
    excluir: { emNegociacao: true, outraAcao: true },
  },
};

const OPCOES: OpcoesFiltro = {
  niveis: ['bronze', 'prata', 'ouro', 'platina', 'diamante'],
  turmas: ['T30', 'T31', 'T32', 'T33', 'T34', 'T35', 'T36', 'T37', 'T38'].map((codigo) => ({ codigo, tipo: 'thb' }))
    .concat(['A8', 'A9', 'A10'].map((codigo) => ({ codigo, tipo: 'aurum' }))),
  planos: ['anual', 'mensal', 'vitalicio'],
  statusAcesso: ['ativo', 'expirado', 'removido'],
  linhas: [
    { chave: 'ht', nome: 'Holding Total', escada: 'B' }, { chave: 'acelera', nome: 'Acelera Holding', escada: 'B' },
    { chave: 'hm', nome: 'Holding Masters', escada: 'B' }, { chave: 'aurum', nome: 'Aurum', escada: 'B' },
    { chave: 'ethb', nome: 'ETHB', escada: 'B' }, { chave: 'sv', nome: 'Sessão de Viabilidade', escada: 'A' },
  ],
  produtos: [
    { id: '1542521', nome: 'Croqui Estrutural' }, { id: '5243340', nome: 'Croqui Estrutural (Escritório)' },
    { id: '3595938', nome: 'Holding Familiar' }, { id: '5301413', nome: 'Holding Familiar (Escritório)' },
    { id: '1560865', nome: 'Holding Total' }, { id: '5064314', nome: 'Holding Masters' },
    { id: '1663254', nome: 'Sessão de Viabilidade' }, { id: '5238525', nome: 'Sessão de Viabilidade (Escritório)' },
  ],
  projetos: ['cnhf-2026-08', 'imersao-holding-total-2026-09', 'seminario-elaine-2026-09'],
  canais: ['activecampaign', 'clint', 'hotmart', 'whatsapp'],
  perguntas: [
    { pergunta: 'O seu interesse hoje é:', formularios: 3 },
    { pergunta: 'Em qual Nível você está hoje?', formularios: 3 },
    { pergunta: '1. Por que você ingressou no Treinamento Holding Masters? Qual é o seu objetivo?', formularios: 12 },
    { pergunta: 'Qual seu objetivo com Holding Familiar?', formularios: 2 },
  ],
};

interface AlunoDemo {
  id: string; nome: string; email: string; nivel: string; turma: string; tipo: string;
  querPropria: boolean; comprouEscadaA: boolean; emNegociacao: boolean; optOut: boolean;
}

const PRIMEIROS = ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa', 'Fábio', 'Gabriela', 'Hugo', 'Isabela', 'João', 'Larissa', 'Marcelo'];
const SOBRENOMES = ['Alves', 'Barros', 'Cardoso', 'Dias', 'Esteves', 'Freitas', 'Gomes', 'Lima', 'Moraes', 'Nunes'];

function baseDemo(): AlunoDemo[] {
  return Array.from({ length: 240 }, (_, i) => {
    const nome = `${PRIMEIROS[i % PRIMEIROS.length]} ${SOBRENOMES[(i * 7) % SOBRENOMES.length]}`;
    return {
      id: `al-${i}`, nome, email: `demo${i}@exemplo.com`,
      nivel: OPCOES.niveis[i % OPCOES.niveis.length], turma: OPCOES.turmas[i % 9].codigo, tipo: i % 12 === 11 ? 'aurum' : 'thb',
      querPropria: i % 3 === 0, comprouEscadaA: i % 31 === 0, emNegociacao: i % 9 === 0, optOut: i % 47 === 0,
    };
  });
}

const mascarar = (email: string) => {
  const [u, d] = email.split('@');
  return `${u.slice(0, 2)}***@${d}`;
};

export class MockEstrategiasRepository implements EstrategiasRepository {
  private base = baseDemo();
  private emAcao = new Set<string>();
  private seq = 0;
  private lista: Estrategia[] = [];

  constructor(private papel: AcessoEstrategias = { solicitar: true, gestor: true }) {
    const ontem = new Date(Date.now() - 86_400_000).toISOString();
    this.lista = [
      this.novo({
        titulo: 'Própria holding: alunos do THB', objetivo: 'Oferecer Sessão de Viabilidade a quem quer fazer a própria holding.',
        publico: 'Alunos do Time Holding Brasil que disseram nas pesquisas que querem fazer a própria holding.',
        filtros: MODELO_PROPRIA_HOLDING.filtros, modelo: MODELO_PROPRIA_HOLDING.chave, linha: 'sv', oferta: 'Sessão de Viabilidade',
        prazo: null, prioridade: 'alta', observacoes: '',
      }, 'Elaine Montenegro', ontem),
    ];
  }

  private novo(s: NovaSolicitacao, solicitante = 'Você', em = agoraIso()): Estrategia {
    const id = `est-${++this.seq}`;
    return {
      id, titulo: s.titulo.trim(), objetivo: s.objetivo.trim(), publico: s.publico.trim(), filtros: limparFiltros(s.filtros),
      modelo: s.modelo, linha: s.linha, oferta: s.oferta.trim() || null, prazo: s.prazo, prioridade: s.prioridade,
      observacoes: s.observacoes.trim(), solicitanteId: 'demo', solicitanteNome: solicitante, situacao: 'solicitada', motivoRecusa: null,
      responsavelId: null, responsavelNome: null, acaoTipo: null, filaId: null, funilId: null, acaoCriadaEm: null, acaoPessoas: null,
      criadoEm: em, atualizadoEm: em, placar: null,
      historico: [{ de: null, para: 'solicitada', porNome: solicitante, nota: null, em }],
    };
  }

  /** Mesma ordem de motivos do banco: opt-out, já comprou, em negociação, em outra ação. */
  private candidatos(f: FiltrosPublico) {
    const l = limparFiltros(f);
    const tipos = l.alunos?.tiposTurma ?? [];
    const niveis = l.alunos?.niveis ?? [];
    const turmas = l.alunos?.turmas ?? [];
    const pesquisa = (l.respondi?.regras.length ?? 0) > 0;
    const naoComprou = (l.naoComprou?.produtos?.length ?? 0) + (l.naoComprou?.linhas?.length ?? 0) > 0;
    return this.base
      .filter((a) => (!tipos.length || tipos.includes(a.tipo)) && (!niveis.length || niveis.includes(a.nivel))
        && (!turmas.length || turmas.includes(a.turma)) && (!pesquisa || a.querPropria))
      .map((a) => ({
        a,
        motivo: a.optOut ? 'optOut' as const
          : naoComprou && a.comprouEscadaA ? 'jaComprou' as const
            : l.excluir?.emNegociacao !== false && a.emNegociacao ? 'emNegociacao' as const
              : l.excluir?.outraAcao !== false && this.emAcao.has(a.id) ? 'outraAcao' as const : null,
      }));
  }

  async acesso(): Promise<AcessoEstrategias> { return { ...this.papel }; }

  async pedidos(): Promise<Estrategia[]> {
    return structuredClone(this.lista.map(({ historico, ...e }) => { void historico; return e; }));
  }

  async pedido(id: string): Promise<Estrategia | null> {
    const e = this.lista.find((x) => x.id === id);
    return e ? structuredClone(e) : null;
  }

  async modelos(): Promise<ModeloPublico[]> { return [structuredClone(MODELO_PROPRIA_HOLDING)]; }
  async opcoes(): Promise<OpcoesFiltro> { return structuredClone(OPCOES); }

  async previa(filtros: FiltrosPublico): Promise<Resultado & { previa?: PreviaPublico }> {
    const msg = validarFiltros(filtros);
    if (msg) return { ok: false, msg };
    const c = this.candidatos(filtros);
    const conta = (m: string) => c.filter((x) => x.motivo === m).length;
    const elegiveis = c.filter((x) => !x.motivo);
    return {
      ok: true,
      previa: {
        total: elegiveis.length,
        excluidos: { optOut: conta('optOut'), jaComprou: conta('jaComprou'), emNegociacao: conta('emNegociacao'), outraAcao: conta('outraAcao') },
        amostra: this.papel.gestor
          ? elegiveis.slice(0, 8).map(({ a }) => ({ nome: `${a.nome.split(' ')[0]} ${a.nome.split(' ')[1][0]}.`, email: mascarar(a.email), nivel: a.nivel, turma: a.turma }))
          : [],
      },
    };
  }

  async salvar(s: NovaSolicitacao): Promise<Resultado & { id?: string }> {
    if (!this.papel.solicitar) return { ok: false, msg: 'Sem permissão para solicitar estratégia.' };
    const msg = validarSolicitacao(s, new Date());
    if (msg) return { ok: false, msg };
    if (s.id) {
      const e = this.lista.find((x) => x.id === s.id);
      if (!e) return { ok: false, msg: 'Pedido não encontrado.' };
      if (e.situacao !== 'solicitada') return { ok: false, msg: 'O Comercial já começou a analisar: o pedido não muda mais.' };
      Object.assign(e, { ...this.novo(s), id: e.id, historico: e.historico, solicitanteNome: e.solicitanteNome, criadoEm: e.criadoEm });
      return { ok: true, msg: 'Pedido atualizado.', id: e.id };
    }
    const e = this.novo(s);
    this.lista.unshift(e);
    return { ok: true, msg: 'Pedido enviado ao Comercial.', id: e.id };
  }

  async mudarSituacao(id: string, situacao: SituacaoEstrategia, nota?: string | null): Promise<Resultado> {
    if (!this.papel.gestor) return { ok: false, msg: 'Só o gestor comercial muda a situação.' };
    const e = this.lista.find((x) => x.id === id);
    if (!e) return { ok: false, msg: 'Pedido não encontrado.' };
    if (!proximasSituacoes(e.situacao).includes(situacao)) return { ok: false, msg: 'Mudança de situação não permitida.' };
    const n = (nota ?? '').trim();
    if (situacao === 'recusada' && n.length < 3) return { ok: false, msg: 'Diga o motivo da recusa.' };
    e.historico = [...(e.historico ?? []), { de: e.situacao, para: situacao, porNome: 'Você', nota: n || null, em: agoraIso() }];
    e.situacao = situacao;
    e.motivoRecusa = situacao === 'recusada' ? n : null;
    e.responsavelNome = e.responsavelNome ?? 'Você';
    e.atualizadoEm = agoraIso();
    return { ok: true, msg: 'Situação atualizada.' };
  }

  async transformar(id: string, tipo: TipoAcao, linha?: ProdutoKey | null, filtros?: FiltrosPublico | null): Promise<ResultadoAcao> {
    if (!this.papel.gestor) return { ok: false, msg: 'Só o gestor comercial transforma em ação.' };
    const e = this.lista.find((x) => x.id === id);
    if (!e) return { ok: false, msg: 'Pedido não encontrado.' };
    if (e.acaoTipo) return { ok: false, msg: 'Este pedido já virou ação.' };
    if (!podeTransformar(e)) return { ok: false, msg: 'Pedido recusado ou encerrado não vira ação.' };
    const f = filtros ?? e.filtros;
    if (filtrosVazios(f)) return { ok: false, msg: 'Defina o público (filtros) antes de criar a ação.' };
    const l = linha ?? e.linha;
    if (!l) return { ok: false, msg: 'Escolha o produto (linha) da ação.' };
    const eleg = this.candidatos(f).filter((x) => !x.motivo);
    const lim = tipo === 'fila' ? LIMITE_FILA : LIMITE_FUNIL;
    if (eleg.length > lim) return { ok: false, msg: `Mais de ${lim} pessoas: refine o público.` };
    if (!eleg.length) return { ok: false, msg: 'O público não tem ninguém elegível.' };
    eleg.forEach(({ a }) => this.emAcao.add(a.id));
    const n = eleg.length;
    e.historico = [...(e.historico ?? []), { de: e.situacao, para: 'em_execucao', porNome: 'Você',
      nota: `Virou ${tipo === 'fila' ? 'fila de recuperação' : 'funil próprio'} com ${n} pessoa(s).`, em: agoraIso() }];
    Object.assign(e, {
      acaoTipo: tipo, filaId: tipo === 'fila' ? `fila-${e.id}` : null, funilId: tipo === 'funil' ? `funil-${e.id}` : null,
      acaoCriadaEm: agoraIso(), acaoPessoas: n, filtros: limparFiltros(f), linha: l, situacao: 'em_execucao',
      responsavelNome: e.responsavelNome ?? 'Você', atualizadoEm: agoraIso(),
      placar: { naLista: n, abordadas: Math.round(n * 0.4), emConversa: Math.round(n * 0.15), vendas: Math.round(n * 0.03), receita: Math.round(n * 0.03) * 1200 },
    });
    return { ok: true, msg: `Ação criada com ${n} pessoa(s).`, filaId: e.filaId, funilId: e.funilId, pessoas: n };
  }
}
