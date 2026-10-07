// Mapeamento PURO do jsonb das RPCs `public.crm_*` de leitura para os tipos do domínio: F1 (migration 20261005s),
// WhatsApp/F4 (20261006051434: conversas, mensagens, templates, fichas, status) e F5 (20261006044653: filas, links).
// Sem Supabase, sem React: recebe o `data` cru e devolve o tipo, ou lança erro com mensagem clara.
// "É zero ≠ não sei": formato inesperado vira exceção, nunca lista vazia.
import type {
  Agrupador, Atividade, Campanha, ConfigComercial, EscopoMcp, PainelHotmart, TokenMcp, Contato, Conversa, Dashboard, EtapaFunil, EventoTimeline, FaixaScore,
  FichaDisparo, FilaRecuperacao, Funil, ItemFila, LinkRastreavel, LogCrm, Mensagem, MotivoPerdaConfig, Negocio, Notificacao,
  OfertaHotmart, OfertaOrfa, PainelPessoa, PontoJornada, PreferenciasNotificacao, ProdutoHotmart, ProdutoKey,
  SessaoComercial, SinalRecuperacao, StatusFicha, StatusFila, StatusMensagem, StatusWhatsapp, Supressao, Template, Utm,
  Vendedor, WidgetPainel,
} from '../domain/types';
import type { ContatoLinha, PaginaContatos, ResumoContatos } from '../domain/contatos';
import { CANAIS_ENTRADA, type CanalEntrada, type OrigemContato } from '../domain/catalogacao';

type Obj = Record<string, unknown>;

/** Erro de formato: o banco respondeu, mas não no contrato combinado. */
export class FormatoInesperado extends Error {
  constructor(rpc: string, detalhe: string) {
    super(`Resposta inesperada do banco (${rpc}): ${detalhe}.`);
    this.name = 'FormatoInesperado';
  }
}

// ── Leitores de campo (tolerantes a null, estritos no tipo) ──

function obj(v: unknown, rpc: string, onde = 'item'): Obj {
  if (v === null || typeof v !== 'object' || Array.isArray(v)) throw new FormatoInesperado(rpc, `${onde} não é objeto`);
  return v as Obj;
}

function lista(v: unknown, rpc: string): unknown[] {
  if (!Array.isArray(v)) throw new FormatoInesperado(rpc, `esperava lista, veio ${v === null ? 'null' : typeof v}`);
  return v;
}

const str = (v: unknown): string => (v === null || v === undefined ? '' : String(v));
const strOuNull = (v: unknown): string | null => (v === null || v === undefined || v === '' ? null : String(v));
const bool = (v: unknown): boolean => v === true;
function num(v: unknown): number {
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : 0;
}
function numOuNull(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}
const strs = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x) => x !== null && x !== undefined).map(String) : []);

function utm(v: unknown): Utm {
  if (!v || typeof v !== 'object') return {};
  const u = v as Obj;
  return {
    source: strOuNull(u.source), medium: strOuNull(u.medium), campaign: strOuNull(u.campaign),
    content: strOuNull(u.content), sck: strOuNull(u.sck),
  };
}

function utmOuNull(v: unknown): Utm | null {
  if (!v || typeof v !== 'object') return null;
  return utm(v);
}

// ── Erro de RPC → mensagem para a tela ──

export interface ErroRpc {
  code?: string;
  message?: string;
}

/** Mensagem clara para `useDados` mostrar. Nunca devolve lista vazia: quem chama lança. */
export function mensagemErroRpc(rpc: string, e: ErroRpc): string {
  if (e.code === '42501') return e.message || 'Sem acesso ao Comercial.';
  if (e.code === 'PGRST202' || e.code === '42883') {
    return `O banco ainda não tem a função ${rpc} (migration do CRM não aplicada).`;
  }
  if (e.code === '22023') return e.message || 'Parâmetro inválido.';
  return `Não foi possível carregar do banco (${rpc})${e.message ? `: ${e.message}` : ''}.`;
}

/**
 * A RPC ainda não existe no banco (migration não aplicada): PostgREST responde PGRST202; o Postgres, 42883.
 * O repositório usa isto para cair no caminho antigo, sem erro na tela.
 */
export function rpcAusente(e: ErroRpc | null | undefined): boolean {
  return !!e && (e.code === 'PGRST202' || e.code === '42883');
}

// ── Leituras ──

export function mapSessao(d: unknown): SessaoComercial {
  const o = obj(d, 'crm_sessao', 'sessão');
  const papel = o.papel === 'gestor' ? 'gestor' : o.papel === 'vendedor' ? 'vendedor' : null;
  if (!o.vendedorId || !papel) throw new FormatoInesperado('crm_sessao', 'sem vendedorId ou papel');
  return { vendedorId: str(o.vendedorId), papel };
}

export function mapConfig(d: unknown): ConfigComercial {
  // crm.config sem linha → null: é "não sei", não "vazio".
  const o = obj(d, 'crm_config', 'configuração');
  return {
    horarioContato: str(o.horarioContato), limiteNegociosAbertos: numOuNull(o.limiteNegociosAbertos),
    // crm_config expõe mcpLigado a partir da 20261006n; antes dela (ou se vier fora do formato) = "não sei" (null), nunca "desligado".
    mcpLigado: typeof o.mcpLigado === 'boolean' ? o.mcpLigado : null,
  };
}

export function mapVendedores(d: unknown): Vendedor[] {
  return lista(d, 'crm_vendedores').map((x) => {
    const o = obj(x, 'crm_vendedores');
    return {
      id: str(o.id), nome: str(o.nome), sigla: str(o.sigla),
      papel: o.papel === 'gestor' ? 'gestor' : 'vendedor',
      ativo: bool(o.ativo), percentual: num(o.percentual), disparaApi: bool(o.disparaApi),
    };
  });
}

export function mapAgrupadores(d: unknown): Agrupador[] {
  return lista(d, 'crm_agrupadores').map((x) => {
    const o = obj(x, 'crm_agrupadores');
    return { id: str(o.id), nome: str(o.nome), produto: strOuNull(o.produto) as Agrupador['produto'], ordem: num(o.ordem) };
  });
}

function mapEtapa(x: unknown): EtapaFunil {
  const o = obj(x, 'crm_funis', 'etapa');
  return {
    id: str(o.id), nome: str(o.nome), papel: str(o.papel) as EtapaFunil['papel'], cor: str(o.cor) as EtapaFunil['cor'],
    slaAtencaoMin: numOuNull(o.slaAtencaoMin), slaCriticoMin: numOuNull(o.slaCriticoMin),
    camposObrigatorios: strs(o.camposObrigatorios) as EtapaFunil['camposObrigatorios'], criterio: str(o.criterio),
  };
}

function mapCampanha(x: unknown): Campanha {
  // `regraJson` (máquina, F2/F3) fica de fora: o domínio só mostra a regra legível.
  const o = obj(x, 'crm_funis', 'campanha');
  return {
    id: str(o.id), nome: str(o.nome), canal: str(o.canal) as Campanha['canal'], regra: str(o.regra),
    ativa: bool(o.ativa), criadoEm: str(o.criadoEm),
  };
}

export function mapFunis(d: unknown): Funil[] {
  return lista(d, 'crm_funis').map((x) => {
    const o = obj(x, 'crm_funis', 'funil');
    const dist = o.distribuicao;
    return {
      id: str(o.id), nome: str(o.nome), icone: str(o.icone) || 'kanban', projeto: strOuNull(o.projeto),
      agrupadorId: str(o.agrupadorId), produto: str(o.produto) as Funil['produto'], tipo: o.tipo === 'hotmart' ? 'hotmart' : 'manual',
      eventosHotmart: strs(o.eventosHotmart) as Funil['eventosHotmart'],
      etapas: Array.isArray(o.etapas) ? o.etapas.map(mapEtapa) : [],
      campanhas: Array.isArray(o.campanhas) ? o.campanhas.map(mapCampanha) : [],
      distribuicao: Array.isArray(dist)
        ? dist.map((y) => { const p = obj(y, 'crm_funis', 'distribuição'); return { vendedorId: str(p.vendedorId), percentual: num(p.percentual) }; })
        : null,
      ativo: bool(o.ativo), criadoEm: str(o.criadoEm),
    };
  });
}

export function mapMotivosPerda(d: unknown): MotivoPerdaConfig[] {
  return lista(d, 'crm_motivos_perda').map((x) => {
    const o = obj(x, 'crm_motivos_perda');
    return {
      key: str(o.key), label: str(o.label), reativa: bool(o.reativa), bloqueia: bool(o.bloqueia),
      alertaGestor: bool(o.alertaGestor), nota: strOuNull(o.nota), sistema: bool(o.sistema), ativo: bool(o.ativo),
    };
  });
}

/** crm_contatos devolve { itens, temMais } (página sem sobreposição: alias filtrado antes do limite). */
export function mapPaginaContatos(d: unknown): { itens: Contato[]; temMais: boolean } {
  const o = obj(d, 'crm_contatos');
  return { itens: mapContatos(o.itens), temMais: bool(o.temMais) };
}

export function mapContatos(d: unknown): Contato[] {
  return lista(d, 'crm_contatos').map((x) => {
    const o = obj(x, 'crm_contatos');
    return {
      id: str(o.id), nome: str(o.nome), email: strOuNull(o.email), telefone: strOuNull(o.telefone),
      cidade: strOuNull(o.cidade), uf: strOuNull(o.uf),
      perfil: strOuNull(o.perfil) as Contato['perfil'], atuaComHolding: strOuNull(o.atuaComHolding) as Contato['atuaComHolding'],
      donoId: strOuNull(o.donoId), tags: strs(o.tags), utm: utm(o.utm), score: numOuNull(o.score),
      ehAluno: bool(o.ehAluno), optOut: bool(o.optOut), criadoEm: str(o.criadoEm),
      ...(o.origem === undefined ? {} : { origem: mapOrigemContato(o.origem) }),
    };
  });
}

/** Canal desconhecido (valor novo no banco) cai em 'sistema' em vez de quebrar a lista. */
export function canalEntrada(v: unknown): CanalEntrada {
  return (CANAIS_ENTRADA as readonly string[]).includes(String(v)) ? (v as CanalEntrada) : 'sistema';
}

/** 'origem' de crm.contatos_itens (20261007141044): null = contato ainda não catalogado. */
export function mapOrigemContato(v: unknown): OrigemContato | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const o = v as Obj;
  return {
    canal: canalEntrada(o.canal), entrouEm: str(o.entrouEm), projeto: strOuNull(o.projeto),
    projetoNome: strOuNull(o.projetoNome), linha: strOuNull(o.linha),
    ...(o.mqlDesde === undefined ? {} : { mqlDesde: strOuNull(o.mqlDesde) }),
  };
}

/** crm_contatos_pagina (20261006m) devolve { itens, total }; cada item = contato + lancamentos, ultimaInteracaoEm, abertos. */
export function mapPaginaServidor(d: unknown): PaginaContatos {
  const rpc = 'crm_contatos_pagina';
  const o = obj(d, rpc);
  const itens = lista(o.itens, rpc);
  const base = mapContatos(itens);
  return {
    total: num(o.total),
    itens: base.map((c, i): ContatoLinha => {
      const x = obj(itens[i], rpc);
      return {
        ...c,
        lancamentos: num(x.lancamentos),
        ultimaInteracaoEm: strOuNull(x.ultimaInteracaoEm),
        abertos: (Array.isArray(x.abertos) ? x.abertos : []).map((a) => {
          const n = obj(a, rpc, 'negócio aberto');
          return { id: str(n.id), produto: str(n.produto) as ProdutoKey, etapaNome: str(n.etapaNome) };
        }),
      };
    }),
  };
}

/** crm_contatos_resumo (20261006m). */
export function mapResumoContatos(d: unknown): ResumoContatos {
  const o = obj(d, 'crm_contatos_resumo');
  return {
    total: num(o.total), semDono: num(o.semDono), optOut: num(o.optOut), alunos: num(o.alunos),
    ufs: strs(o.ufs), tags: strs(o.tags),
    ...(Array.isArray(o.canais) ? {
      canais: o.canais.map((x) => { const c = obj(x, 'crm_contatos_resumo', 'canal'); return { canal: canalEntrada(c.canal), total: num(c.total) }; }),
    } : {}),
    ...(Array.isArray(o.projetos) ? {
      projetos: o.projetos.map((x) => { const p = obj(x, 'crm_contatos_resumo', 'projeto'); return { chave: str(p.chave), nome: strOuNull(p.nome), total: num(p.total) }; }),
    } : {}),
    ...(o.semProjeto === undefined ? {} : { semProjeto: num(o.semProjeto) }),
  };
}

/** crm_contatos_por_ids (20261006m) devolve { itens }; com duplicados, cada item traz `duplicados` (ids). */
export function mapContatosPorIds(d: unknown): { contatos: Contato[]; duplicados: Map<string, string[]> } {
  const o = obj(d, 'crm_contatos_por_ids');
  const itens = lista(o.itens, 'crm_contatos_por_ids');
  const contatos = mapContatos(itens);
  const duplicados = new Map<string, string[]>();
  itens.forEach((x, i) => {
    const dup = (x as Obj).duplicados;
    if (Array.isArray(dup)) duplicados.set(contatos[i].id, strs(dup));
  });
  return { contatos, duplicados };
}

export function mapNegocios(d: unknown): Negocio[] {
  return lista(d, 'crm_negocios').map((x) => {
    const o = obj(x, 'crm_negocios');
    const sla = o.sla && typeof o.sla === 'object' ? (o.sla as Obj) : null;
    const pa = o.proximaAtividade && typeof o.proximaAtividade === 'object' ? (o.proximaAtividade as Obj) : null;
    const campos = o.campos && typeof o.campos === 'object' && !Array.isArray(o.campos)
      ? Object.fromEntries(Object.entries(o.campos as Obj).map(([k, v]) => [k, str(v)]))
      : {};
    return {
      id: str(o.id), contatoId: str(o.contatoId), produto: str(o.produto) as Negocio['produto'],
      origem: str(o.origem) as Negocio['origem'], funilId: str(o.funilId), campanhaId: strOuNull(o.campanhaId),
      etapaId: str(o.etapaId), etapaNome: str(o.etapaNome), etapa: str(o.etapa) as Negocio['etapa'],
      // Etapa sem alerta no banco = null explícito (não cai no padrão do playbook).
      sla: sla ? { atencaoMin: num(sla.atencaoMin), criticoMin: num(sla.criticoMin) } : null,
      status: str(o.status) as Negocio['status'], donoId: strOuNull(o.donoId), valor: num(o.valor),
      campos: campos as Negocio['campos'], motivoPerda: strOuNull(o.motivoPerda),
      criadoEm: str(o.criadoEm), etapaDesde: str(o.etapaDesde), fechadoEm: strOuNull(o.fechadoEm),
      proximaAtividade: pa
        ? { id: str(pa.id), tipo: str(pa.tipo) as Atividade['tipo'], titulo: str(pa.titulo), venceEm: str(pa.venceEm) }
        : null,
      ultimaInteracaoEm: strOuNull(o.ultimaInteracaoEm),
    };
  });
}

export function mapAtividades(d: unknown): Atividade[] {
  return lista(d, 'crm_atividades').map((x) => {
    const o = obj(x, 'crm_atividades');
    return {
      id: str(o.id), negocioId: strOuNull(o.negocioId), contatoId: str(o.contatoId), donoId: str(o.donoId),
      tipo: str(o.tipo) as Atividade['tipo'], titulo: str(o.titulo), venceEm: str(o.venceEm),
      concluidaEm: strOuNull(o.concluidaEm), resultado: strOuNull(o.resultado), cadenciaDia: numOuNull(o.cadenciaDia),
    };
  });
}

export function mapEventos(d: unknown): EventoTimeline[] {
  return lista(d, 'crm_eventos').map((x) => {
    const o = obj(x, 'crm_eventos');
    return {
      id: str(o.id), contatoId: str(o.contatoId), negocioId: strOuNull(o.negocioId), tipo: str(o.tipo) as EventoTimeline['tipo'],
      titulo: str(o.titulo), detalhe: strOuNull(o.detalhe), em: str(o.em), autorId: strOuNull(o.autorId),
    };
  });
}

export function mapJornada(d: unknown): PontoJornada[] {
  return lista(d, 'crm_jornada').map((x) => {
    const o = obj(x, 'crm_jornada');
    return {
      id: str(o.id), contatoId: str(o.contatoId), tipo: str(o.tipo) as PontoJornada['tipo'], em: str(o.em),
      titulo: str(o.titulo), detalhe: strOuNull(o.detalhe), fonte: str(o.fonte) as PontoJornada['fonte'],
      lancamento: strOuNull(o.lancamento), produto: strOuNull(o.produto) as PontoJornada['produto'],
      utm: utmOuNull(o.utm), valor: numOuNull(o.valor), negocioId: strOuNull(o.negocioId),
    };
  });
}

export function mapLog(d: unknown): LogCrm[] {
  return lista(d, 'crm_log').map((x) => {
    const o = obj(x, 'crm_log');
    return {
      id: str(o.id), em: str(o.em), autorId: strOuNull(o.autorId), acao: str(o.acao) as LogCrm['acao'],
      entidade: str(o.entidade) as LogCrm['entidade'], entidadeId: str(o.entidadeId), contatoId: strOuNull(o.contatoId),
      resumo: str(o.resumo),
      mudancas: Array.isArray(o.mudancas)
        ? o.mudancas.map((m) => { const p = obj(m, 'crm_log', 'mudança'); return { campo: str(p.campo), antes: strOuNull(p.antes), depois: strOuNull(p.depois) }; })
        : [],
    };
  });
}

function mapWidgets(v: unknown, rpc: string): WidgetPainel[] {
  return lista(v ?? [], rpc).map((x) => {
    const o = obj(x, rpc, 'widget');
    const larg = num(o.largura);
    return {
      id: str(o.id), titulo: str(o.titulo), metrica: str(o.metrica) as WidgetPainel['metrica'],
      visual: str(o.visual) as WidgetPainel['visual'], periodo: str(o.periodo) as WidgetPainel['periodo'],
      agrupar: (strOuNull(o.agrupar) ?? 'nenhum') as WidgetPainel['agrupar'],
      largura: (larg >= 1 && larg <= 4 ? larg : 1) as WidgetPainel['largura'], funilId: strOuNull(o.funilId),
    };
  });
}

export function mapDashboards(d: unknown): Dashboard[] {
  return lista(d, 'crm_dashboards').map((x) => {
    const o = obj(x, 'crm_dashboards');
    return {
      id: str(o.id), nome: str(o.nome), descricao: strOuNull(o.descricao), donoId: str(o.donoId),
      compartilhado: bool(o.compartilhado), widgets: mapWidgets(o.widgets, 'crm_dashboards'),
      criadoEm: str(o.criadoEm), atualizadoEm: str(o.atualizadoEm),
    };
  });
}

/** null = a pessoa ainda não personalizou (quem chama usa o padrão de fábrica). */
export function mapPainel(d: unknown): PainelPessoa | null {
  if (d === null || d === undefined) return null;
  const o = obj(d, 'crm_painel', 'painel');
  return { vendedorId: str(o.vendedorId), widgets: mapWidgets(o.widgets, 'crm_painel') };
}

export function mapNotificacoes(d: unknown): Notificacao[] {
  return lista(d, 'crm_notificacoes').map((x) => {
    const o = obj(x, 'crm_notificacoes');
    return {
      id: str(o.id), vendedorId: str(o.vendedorId), gatilho: str(o.gatilho) as Notificacao['gatilho'],
      titulo: str(o.titulo), corpo: str(o.corpo), href: str(o.href), em: str(o.em), lida: bool(o.lida),
    };
  });
}

/**
 * null = ainda não salvou (quem chama usa o padrão). Gatilho ausente no jsonb herda o valor do padrão:
 * o banco aceita objeto parcial (`gatilhos - array[...] = '{}'` só barra chave desconhecida).
 */
export function mapPreferencias(d: unknown, padrao: PreferenciasNotificacao): PreferenciasNotificacao {
  if (d === null || d === undefined) return padrao;
  const o = obj(d, 'crm_preferencias', 'preferências');
  const g = o.gatilhos && typeof o.gatilhos === 'object' ? (o.gatilhos as Obj) : {};
  const gatilhos = { ...padrao.gatilhos };
  for (const k of Object.keys(gatilhos) as (keyof typeof gatilhos)[]) {
    if (typeof g[k] === 'boolean') gatilhos[k] = g[k] as boolean;
  }
  return {
    vendedorId: str(o.vendedorId) || padrao.vendedorId, desktop: bool(o.desktop), gatilhos,
    silencioInicio: strOuNull(o.silencioInicio), silencioFim: strOuNull(o.silencioFim),
  };
}

export function mapProdutosHotmart(d: unknown): ProdutoHotmart[] {
  return lista(d, 'crm_produtos_hotmart').map((x) => mapProduto(x, 'crm_produtos_hotmart'));
}

function mapProduto(x: unknown, rpc: string): ProdutoHotmart {
  const o = obj(x, rpc, 'produto');
  const escada = o.escada === 'A' || o.escada === 'B' ? o.escada : null;
  return {
    produtoId: str(o.produtoId), nomeHotmart: str(o.nomeHotmart), conta: o.conta === 'escritorio' ? 'escritorio' : 'academy',
    familia: strOuNull(o.familia), noComercial: bool(o.noComercial), nomeComercial: strOuNull(o.nomeComercial),
    produtoKey: strOuNull(o.produtoKey) as ProdutoHotmart['produtoKey'], agrupadorId: strOuNull(o.agrupadorId), escada,
    // Produto sem oferta sincronizada: o banco devolve null (o tipo pede string).
    sincronizadoEm: str(o.sincronizadoEm),
  };
}

function mapOferta(x: unknown, rpc: string): OfertaHotmart {
  const o = obj(x, rpc, 'oferta');
  return {
    codigo: str(o.codigo), produtoId: str(o.produtoId), nomeHotmart: strOuNull(o.nomeHotmart), preco: numOuNull(o.preco),
    moeda: str(o.moeda) || 'BRL', modo: str(o.modo), principal: bool(o.principal), linkCheckout: str(o.linkCheckout),
    vigente: bool(o.vigente), condicao: strOuNull(o.condicao), validaAte: strOuNull(o.validaAte), uso: strOuNull(o.uso),
    transacoes: num(o.transacoes), ultimaVendaEm: strOuNull(o.ultimaVendaEm), vistaEm: str(o.vistaEm),
  };
}

export function mapOfertas(d: unknown): OfertaHotmart[] {
  return lista(d, 'crm_ofertas').map((x) => mapOferta(x, 'crm_ofertas'));
}

export function mapOfertasOrfas(d: unknown): OfertaOrfa[] {
  return lista(d, 'crm_ofertas_orfas').map((x) => {
    const o = obj(x, 'crm_ofertas_orfas');
    return { codigo: str(o.codigo), produtoId: strOuNull(o.produtoId), transacoes: num(o.transacoes), ultimaEm: str(o.ultimaEm) };
  });
}

export function mapBuscaPorLink(d: unknown): { produto: ProdutoHotmart | null; oferta: OfertaHotmart | null; codigo: string | null } {
  const o = obj(d, 'crm_buscar_por_link', 'resultado');
  return {
    produto: o.produto ? mapProduto(o.produto, 'crm_buscar_por_link') : null,
    oferta: o.oferta ? mapOferta(o.oferta, 'crm_buscar_por_link') : null,
    codigo: strOuNull(o.codigo),
  };
}

// ── WhatsApp (F4, migration 20261006051434) ──

const STATUS_MENSAGEM: readonly StatusMensagem[] = ['enviada', 'entregue', 'lida', 'falhou'];

function mapMensagem(x: unknown, rpc: string): Mensagem {
  const o = obj(x, rpc, 'mensagem');
  if (o.direcao !== 'entrada' && o.direcao !== 'saida') throw new FormatoInesperado(rpc, 'mensagem sem direção');
  const status = STATUS_MENSAGEM.includes(o.status as StatusMensagem) ? (o.status as StatusMensagem) : null;
  const envio = o.envio === 'na_fila' || o.envio === 'enviando' ? o.envio : null;
  return {
    id: str(o.id), contatoId: str(o.contatoId), canal: o.canal === 'email' || o.canal === 'nota' ? o.canal : 'whatsapp',
    direcao: o.direcao, texto: str(o.texto), em: str(o.em), status, autorId: strOuNull(o.autorId),
    templateId: strOuNull(o.templateId), envio, erro: strOuNull(o.erro), tipo: str(o.tipo) || 'texto', fichaId: strOuNull(o.fichaId),
  };
}

export function mapConversas(d: unknown): Conversa[] {
  return lista(d, 'crm_conversas').map((x) => {
    const o = obj(x, 'crm_conversas');
    if (!o.ultimaMensagem) throw new FormatoInesperado('crm_conversas', 'conversa sem última mensagem');
    return {
      contatoId: str(o.contatoId), ultimaMensagem: mapMensagem(o.ultimaMensagem, 'crm_conversas'), naoLidas: num(o.naoLidas),
      janelaAteEm: strOuNull(o.janelaAteEm), atribuidaA: strOuNull(o.atribuidaA),
    };
  });
}

/** Ordem cronológica (a RPC já devolve assim). */
export function mapMensagens(d: unknown): Mensagem[] {
  return lista(d, 'crm_mensagens').map((x) => mapMensagem(x, 'crm_mensagens'));
}

export function mapTemplates(d: unknown): Template[] {
  return lista(d, 'crm_templates').map((x) => {
    const o = obj(x, 'crm_templates', 'template');
    return {
      id: str(o.id), nome: str(o.nome), categoria: o.categoria === 'utility' ? 'utility' : 'marketing', texto: str(o.texto),
      aprovado: bool(o.aprovado), idioma: str(o.idioma), variaveis: num(o.variaveis),
    };
  });
}

const STATUS_FICHA: readonly StatusFicha[] = ['rascunho', 'aguardando_aprovacao', 'aprovada', 'reprovada', 'enviada'];

export function mapFichas(d: unknown): FichaDisparo[] {
  return lista(d, 'crm_fichas').map((x) => {
    const o = obj(x, 'crm_fichas', 'ficha');
    if (!STATUS_FICHA.includes(o.status as StatusFicha)) throw new FormatoInesperado('crm_fichas', `status de ficha desconhecido (${str(o.status)})`);
    const r = o.resultado && typeof o.resultado === 'object' ? (o.resultado as Obj) : null;
    return {
      id: str(o.id), codigo: str(o.codigo), objetivo: str(o.objetivo), produto: str(o.produto) as ProdutoKey, filtro: str(o.filtro),
      quantidade: num(o.quantidade), supressoes: strs(o.supressoes) as Supressao[], suprimidos: num(o.suprimidos),
      templateId: str(o.templateId), numeroEnvio: str(o.numeroEnvio), agendadoPara: str(o.agendadoPara),
      operadorId: str(o.operadorId), link: str(o.link), status: o.status as StatusFicha, aprovadoPor: strOuNull(o.aprovadoPor),
      criadoEm: str(o.criadoEm), motivoStatus: strOuNull(o.motivoStatus),
      resultado: r ? { entregues: num(r.entregues), lidas: num(r.lidas), respostas: num(r.respostas), falhas: num(r.falhas), naFila: num(r.naFila) } : null,
    };
  });
}

export function mapWhatsappStatus(d: unknown): StatusWhatsapp {
  // crm.config sem linha → null: "não sei", não "desligado".
  const o = obj(d, 'crm_whatsapp_status', 'status');
  const n = o.numero && typeof o.numero === 'object' ? (o.numero as Obj) : null;
  return {
    whatsappLigado: bool(o.whatsappLigado), envioLigado: bool(o.envioLigado), escritaLigada: bool(o.escritaLigada),
    numero: n ? { id: str(n.id), nome: str(n.nome), final: str(n.final), ativo: bool(n.ativo) } : null,
    templatesAprovados: num(o.templatesAprovados), naFila: num(o.naFila), falhasHoje: num(o.falhasHoje),
    janelaHoras: num(o.janelaHoras) || 24, maxDestinatarios: num(o.maxDestinatarios),
  };
}

// ── Filas de recuperação e links (F5, migration 20261006044653) ──

const FAIXAS: readonly FaixaScore[] = ['A', 'B', 'C', 'D'];

function mapItemFila(x: unknown): ItemFila {
  const o = obj(x, 'crm_filas', 'item da fila');
  if (!FAIXAS.includes(o.faixa as FaixaScore)) throw new FormatoInesperado('crm_filas', `faixa desconhecida (${str(o.faixa)})`);
  return {
    id: str(o.id), contatoId: str(o.contatoId), score: num(o.score), faixa: o.faixa as FaixaScore,
    sinais: strs(o.sinais) as SinalRecuperacao[], status: str(o.status) as StatusFila, responsavelId: strOuNull(o.responsavelId),
    alteradoPor: strOuNull(o.alteradoPor), alteradoEm: strOuNull(o.alteradoEm),
  };
}

export function mapFilas(d: unknown): FilaRecuperacao[] {
  return lista(d, 'crm_filas').map((x) => {
    const o = obj(x, 'crm_filas', 'fila');
    return {
      id: str(o.id), nome: str(o.nome), produto: str(o.produto) as ProdutoKey, criadaEm: str(o.criadaEm),
      ofertaVigente: strOuNull(o.ofertaVigente), itens: lista(o.itens, 'crm_filas').map(mapItemFila),
      ofertaCodigo: strOuNull(o.ofertaCodigo), projeto: strOuNull(o.projeto), encerradaEm: strOuNull(o.encerradaEm),
    };
  });
}

export function mapLinks(d: unknown): LinkRastreavel[] {
  return lista(d, 'crm_links').map((x) => {
    const o = obj(x, 'crm_links', 'link');
    return {
      id: str(o.id), vendedorId: str(o.vendedorId), produto: str(o.produto) as ProdutoKey, acao: str(o.acao), url: str(o.url),
      sck: str(o.sck), canal: str(o.canal), ofertaCodigo: strOuNull(o.ofertaCodigo), projeto: strOuNull(o.projeto),
      conteudo: strOuNull(o.conteudo), criadoEm: str(o.criadoEm), arquivadoEm: strOuNull(o.arquivadoEm),
    };
  });
}

// ── Integração Hotmart (F3, migration 20261006043612) ──

export function mapPainelHotmart(d: unknown): PainelHotmart {
  const rpc = 'crm_hotmart_painel';
  const o = obj(d, rpc, 'painel');
  if (typeof o.hotmartLigado !== 'boolean') throw new FormatoInesperado(rpc, 'sem hotmartLigado');
  const sl = o.slack && typeof o.slack === 'object' ? (o.slack as Obj) : {};
  return {
    hotmartLigado: o.hotmartLigado,
    slackLigado: bool(o.slackLigado),
    desde: strOuNull(o.desde),
    ultimoProcessadoEm: strOuNull(o.ultimoProcessadoEm),
    porResultado: lista(o.porResultado ?? [], rpc).map((x) => {
      const r = obj(x, rpc, 'contagem');
      return { fonte: str(r.fonte), classe: str(r.classe), resultado: str(r.resultado), n: num(r.n) };
    }),
    erros: lista(o.erros ?? [], rpc).map((x) => {
      const r = obj(x, rpc, 'erro');
      if (!r.chave) throw new FormatoInesperado(rpc, 'erro sem chave');
      return { chave: str(r.chave), classe: str(r.classe), resultado: str(r.resultado), em: str(r.em), tentativas: num(r.tentativas) };
    }),
    ofertasOrfas: strs(o.ofertasOrfas),
    slack: { pendentes: num(sl.pendentes), enviados: num(sl.enviados), descartados: num(sl.descartados) },
  };
}

// ── MCP (F7, migration 20261006050132) ──

export function escoposMcp(v: unknown): EscopoMcp[] {
  return strs(v).filter((e): e is EscopoMcp => e === 'ler' || e === 'operar');
}

export function mapTokensMcp(d: unknown): TokenMcp[] {
  const rpc = 'crm_mcp_tokens';
  return lista(d, rpc).map((x) => {
    const o = obj(x, rpc, 'token');
    if (!o.id) throw new FormatoInesperado(rpc, 'token sem id');
    return {
      id: str(o.id), nome: str(o.nome), prefixo: str(o.prefixo), escopos: escoposMcp(o.escopos),
      perfilId: str(o.perfilId), perfilNome: str(o.perfilNome), criadoEm: str(o.criadoEm), expiraEm: str(o.expiraEm),
      revogadoEm: strOuNull(o.revogadoEm), ultimoUsoEm: strOuNull(o.ultimoUsoEm), ativo: bool(o.ativo),
    };
  });
}
