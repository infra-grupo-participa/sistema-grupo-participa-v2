// Catalogação de origem dos contatos: de onde cada um veio (canal) e de qual projeto (chave do projeto, a mesma
// string do utm_campaign, da etiqueta do ClickUp e de crm.funil.projeto). O banco faz o mesmo em
// crm.catalogo_resolver / crm.origem_catalogar (migration 20261007141044); esta versão serve à demonstração, à validação
// do formulário e aos rótulos da tela. Sem React, sem Supabase.

export type CanalEntrada =
  | 'hotmart' | 'clint' | 'activecampaign' | 'whatsapp' | 'sendflow' | 'unnichat' | 'respondi' | 'manual' | 'mcp' | 'sistema';

export const CANAIS_ENTRADA: readonly CanalEntrada[] = [
  'hotmart', 'clint', 'activecampaign', 'whatsapp', 'sendflow', 'unnichat', 'respondi', 'manual', 'mcp', 'sistema',
];

export const ROTULO_CANAL: Record<CanalEntrada, string> = {
  hotmart: 'Hotmart', clint: 'Clint', activecampaign: 'ActiveCampaign', whatsapp: 'WhatsApp', sendflow: 'SendFlow',
  unnichat: 'Unnichat', respondi: 'Respondi', manual: 'Cadastro manual', mcp: 'Claude (MCP)', sistema: 'Sistema',
};

/** Rótulo curto para o selo da lista. */
export const SELO_CANAL: Record<CanalEntrada, string> = {
  hotmart: 'Hotmart', clint: 'Clint', activecampaign: 'AC', whatsapp: 'WhatsApp', sendflow: 'SendFlow',
  unnichat: 'Unnichat', respondi: 'Respondi', manual: 'Manual', mcp: 'MCP', sistema: 'Sistema',
};

export type CampoRegra =
  | 'utm_campaign' | 'ac_lista' | 'ac_tag' | 'hotmart_oferta' | 'funil' | 'hotmart_produto' | 'respondi_form' | 'sck';

/** Ordem em que o banco testa os campos de um evento (o primeiro que liga a projeto decide). */
export const ORDEM_CAMPOS: readonly CampoRegra[] = [
  'utm_campaign', 'ac_lista', 'ac_tag', 'hotmart_oferta', 'funil', 'hotmart_produto', 'respondi_form', 'sck',
];

export const ROTULO_CAMPO_REGRA: Record<CampoRegra, string> = {
  utm_campaign: 'UTM campaign', ac_lista: 'Lista do ActiveCampaign', ac_tag: 'Tag do ActiveCampaign',
  hotmart_oferta: 'Oferta da Hotmart', funil: 'Funil (Clint ou CRM)', hotmart_produto: 'Produto da Hotmart',
  respondi_form: 'Formulário do Respondi', sck: 'SCK (pista fraca)',
};

export const DICA_CAMPO_REGRA: Record<CampoRegra, string> = {
  utm_campaign: 'utm_campaign igual a uma chave de projeto já liga sozinho; regra só para valores fora do padrão.',
  ac_lista: 'Casa pelo id (ex.: 603) ou pelo nome da lista (ex.: começa com "Patrimônio Brasil").',
  ac_tag: 'Nome da tag como o AC manda (ex.: começa com "PB ").',
  hotmart_oferta: 'Código da oferta (off=…). Use a janela de datas quando a oferta é reaproveitada entre edições.',
  funil: 'Nome do funil, como aparece no CRM (ex.: "Clint · MQLS").',
  hotmart_produto: 'Id do produto. Sozinho raramente diz o projeto: prefira a oferta com datas.',
  respondi_form: 'Slug do formulário.',
  sck: 'Texto livre, sem padrão confiável: só como último recurso.',
};

export type OperadorRegra = 'igual' | 'comeca' | 'contem';
export const ROTULO_OPERADOR: Record<OperadorRegra, string> = { igual: 'é igual a', comeca: 'começa com', contem: 'contém' };

/** Por que um contato está sem projeto. */
export type MotivoSemProjeto = 'regra_sem_projeto' | 'sem_regra' | 'sem_dado';
export type MotivoProjeto = 'regra' | 'utm' | 'sck' | 'funil' | 'manual' | MotivoSemProjeto;

export const ROTULO_MOTIVO: Record<MotivoProjeto, string> = {
  regra: 'Regra de catalogação', utm: 'UTM com a chave do projeto', sck: 'Link rastreável do CRM', funil: 'Funil do projeto',
  manual: 'Definido pelo gestor', regra_sem_projeto: 'Conhecido, sem projeto (lista ou funil geral do produto)',
  sem_regra: 'Nenhuma regra casou: classifique', sem_dado: 'Sem lista, tag, produto nem funil para catalogar',
};

/** O que a linha da lista mostra. */
export interface OrigemContato {
  canal: CanalEntrada;
  entrouEm: string;
  projeto: string | null;
  projetoNome: string | null;
  /** Linha de produto (ht, hm, acelera…) quando há compra ou funil, mesmo sem projeto. */
  linha: string | null;
  /** É MQL desde (regra tipo 'mql', ex.: tag "PB MQL"); null = não é MQL. */
  mqlDesde?: string | null;
}

/** 'projeto': o valor liga ao projeto. 'mql': a tag/lista liga ao projeto E marca MQL. */
export type TipoRegra = 'projeto' | 'mql';
export const CAMPOS_MQL: readonly CampoRegra[] = ['ac_tag', 'ac_lista', 'respondi_form'];

export interface RegraCatalogo {
  /** null = nova. */
  id: number | null;
  /** Ausente = 'projeto'. */
  tipo?: TipoRegra;
  campo: CampoRegra;
  operador: OperadorRegra;
  padrao: string;
  /** null = "conhecido, sem projeto". */
  projeto: string | null;
  projetoNome?: string | null;
  valeDe: string | null;
  valeAte: string | null;
  prioridade: number;
  ativo: boolean;
  nota: string | null;
  /** Contatos que esta regra ligou (só leitura). */
  contatos?: number;
}

export interface ListaAc { id: string; nome: string }
export interface ProjetoCatalogo { chave: string; nome: string | null; contatos: number }
export interface PendenciaCatalogo { campo: CampoRegra; valor: string; nome: string | null; contatos: number }

export interface ResumoCatalogo {
  total: number;
  comProjeto: number;
  produtoSemProjeto: number;
  semNada: number;
  /** Contatos marcados MQL por regra. */
  mql: number;
  motivos: Record<MotivoSemProjeto, number>;
  porCanal: { canal: CanalEntrada; total: number; comProjeto: number }[];
  semProjetoPorLinha: { linha: string; total: number }[];
}

export interface PainelCatalogo {
  /** Edita regras e listas: área de Dados (Victor Hugo), admin, dev. */
  podeEditar: boolean;
  /** Classifica contato a contato (projeto à mão): Dados ou gestor comercial. */
  podeClassificar: boolean;
  regras: RegraCatalogo[];
  listasAc: ListaAc[];
  projetos: ProjetoCatalogo[];
  resumo: ResumoCatalogo;
  pendencias: PendenciaCatalogo[];
}

/** "Como entrou" da ficha. */
export interface OrigemDetalhada extends OrigemContato {
  motivo: MotivoProjeto;
  manual: boolean;
  detalhe: DetalheOrigem;
  regra: { id: number; campo: CampoRegra; operador: OperadorRegra; padrao: string } | null;
  podeDefinir: boolean;
  mqlProjeto?: string | null;
  mqlProjetoNome?: string | null;
}

export interface DetalheOrigem {
  hotmart?: { em?: string; produtoId?: string; produto?: string; ofertaCodigo?: string; classe?: string; conta?: string; linha?: string; primeiraEm?: string };
  activecampaign?: { em?: string; tipo?: string; lista?: string; listaNome?: string; tag?: string; utm?: Record<string, string>; primeiraEm?: string };
  clint?: { em?: string; funil?: string; linha?: string; primeiraEm?: string };
  crm?: { em?: string; funil?: string; linha?: string; projetoDoFunil?: string; primeiraEm?: string };
  projetoVeioDe?: { fonte?: string; campo?: string; valor?: string; em?: string };
}

export const CHAVE_PROJETO = /^[a-z0-9][a-z0-9-]{1,79}$/;

/** Nome legível: o do cadastro; sem cadastro, a chave sem hífen e com o ano-mês no fim ("cnhf · 2026-08"). */
export function nomeProjeto(chave: string | null, nome?: string | null): string {
  if (!chave) return 'Sem projeto';
  if (nome && nome.trim()) return nome.trim();
  const m = chave.match(/^(.*?)-(\d{4})-(\d{2})$/);
  const base = (m ? m[1] : chave).replace(/-/g, ' ');
  const titulo = base.charAt(0).toUpperCase() + base.slice(1);
  return m ? `${titulo} · ${m[2]}-${m[3]}` : titulo;
}

/** Mesmo texto comparável do banco (crm.catalogo_norm): minúsculo, sem acento, espaços colapsados. */
export function normCatalogo(s: string | null | undefined, cortarFim = true): string {
  const t = String(s ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, ' ');
  return cortarFim ? t.trim() : t.trimStart();
}

/** "Começa com" mantém o espaço do fim do padrão: "PB " casa "PB MQL", não "PBX". */
export function casaRegra(operador: OperadorRegra, padrao: string, valor: string | null | undefined): boolean {
  const v = normCatalogo(valor);
  const p = normCatalogo(padrao);
  if (!v || !p) return false;
  if (operador === 'igual') return v === p;
  if (operador === 'comeca') return `${v} `.startsWith(normCatalogo(padrao, false));
  return v.includes(p);
}

export type CamposEvento = Partial<Record<CampoRegra | 'ac_lista_nome' | 'funil_projeto', string | null>>;

export interface Resolucao { projeto: string | null; regraId: number | null; motivo: MotivoProjeto; campo: CampoRegra | null; valor: string | null }

const ORDEM_OPERADOR: Record<OperadorRegra, number> = { igual: 0, comeca: 1, contem: 2 };

/**
 * Resolve UM evento (mesma ordem e desempate de crm.catalogo_resolver). `chavesConhecidas` = projetos cadastrados
 * (utm_campaign igual a uma delas liga sozinho). `quando` = data do evento (AAAA-MM-DD) para as regras com janela.
 */
export function resolverProjeto(
  campos: CamposEvento, regras: RegraCatalogo[], opcoes: { quando?: string | null; chavesConhecidas?: Iterable<string>; listas?: ListaAc[] } = {},
): Resolucao {
  const conhecidas = new Set(opcoes.chavesConhecidas ?? []);
  for (const r of regras) if (r.ativo && r.projeto) conhecidas.add(r.projeto);
  const dia = (opcoes.quando ?? '').slice(0, 10);
  let semProjeto: Resolucao | null = null;
  let tinha = false;
  for (const campo of ORDEM_CAMPOS) {
    let v = (campos[campo] ?? '').trim();
    if (campo === 'ac_lista' && v === '0') v = '';
    if (!v) continue;
    tinha = true;
    if (campo === 'utm_campaign' && conhecidas.has(v.toLowerCase())) {
      return { projeto: v.toLowerCase(), regraId: null, motivo: 'utm', campo, valor: v };
    }
    if (campo === 'funil' && campos.funil_projeto && conhecidas.has(campos.funil_projeto)) {
      return { projeto: campos.funil_projeto, regraId: null, motivo: 'funil', campo, valor: v };
    }
    const nomeLista = campo === 'ac_lista' ? (campos.ac_lista_nome ?? opcoes.listas?.find((l) => l.id === v)?.nome ?? null) : null;
    const achada = regras
      .filter((r) => r.ativo && r.campo === campo
        && (!r.valeDe || !dia || dia >= r.valeDe) && (!r.valeAte || !dia || dia <= r.valeAte)
        && (casaRegra(r.operador, r.padrao, v) || (!!nomeLista && casaRegra(r.operador, r.padrao, nomeLista))))
      .sort((a, b) => a.prioridade - b.prioridade || ORDEM_OPERADOR[a.operador] - ORDEM_OPERADOR[b.operador]
        || b.padrao.length - a.padrao.length || (a.id ?? 0) - (b.id ?? 0))[0];
    if (achada) {
      if (achada.projeto) return { projeto: achada.projeto, regraId: achada.id, motivo: 'regra', campo, valor: v };
      semProjeto ??= { projeto: null, regraId: achada.id, motivo: 'regra_sem_projeto', campo, valor: v };
    }
  }
  return semProjeto ?? { projeto: null, regraId: null, motivo: tinha ? 'sem_regra' : 'sem_dado', campo: null, valor: null };
}

/** Rascunho do formulário de regra (strings, como a tela edita). */
export interface RascunhoRegra {
  id: number | null;
  tipo: TipoRegra;
  campo: CampoRegra;
  operador: OperadorRegra;
  padrao: string;
  projeto: string;
  semProjeto: boolean;
  valeDe: string;
  valeAte: string;
  prioridade: string;
  ativo: boolean;
  nota: string;
}

export function rascunhoRegra(r?: Partial<RegraCatalogo> | null): RascunhoRegra {
  return {
    id: r?.id ?? null, tipo: r?.tipo ?? 'projeto', campo: r?.campo ?? 'ac_lista', operador: r?.operador ?? 'igual', padrao: r?.padrao ?? '',
    projeto: r?.projeto ?? '', semProjeto: !!r && r.id != null && !r.projeto && (r.tipo ?? 'projeto') === 'projeto', valeDe: r?.valeDe ?? '', valeAte: r?.valeAte ?? '',
    prioridade: String(r?.prioridade ?? 100), ativo: r?.ativo ?? true, nota: r?.nota ?? '',
  };
}

/** Mesmas regras do banco (crm_catalogo_regra_salvar). */
export function validarRegra(r: RascunhoRegra): { ok: true; regra: RegraCatalogo } | { ok: false; erro: string } {
  const padrao = r.padrao.trim();
  if (!padrao) return { ok: false, erro: 'Escreva o valor ou o pedaço do nome.' };
  if (padrao.length > 200) return { ok: false, erro: 'Valor longo demais (até 200 letras).' };
  const semProjeto = r.tipo === 'mql' ? false : r.semProjeto;
  if (r.tipo === 'mql' && !CAMPOS_MQL.includes(r.campo)) {
    return { ok: false, erro: 'Regra de MQL: tag ou lista do ActiveCampaign (ou formulário do Respondi).' };
  }
  const projeto = semProjeto ? null : r.projeto.trim().toLowerCase() || null;
  if (!semProjeto && !projeto) return { ok: false, erro: 'Escolha o projeto ou marque "sem projeto".' };
  if (projeto && !CHAVE_PROJETO.test(projeto)) {
    return { ok: false, erro: 'Chave do projeto inválida: minúsculas, números e hífen (ex.: seminario-conjunto-2026-11).' };
  }
  if (r.valeDe && r.valeAte && r.valeAte < r.valeDe) return { ok: false, erro: 'A data final vem antes da inicial.' };
  const prioridade = Number(r.prioridade || 100);
  if (!Number.isInteger(prioridade) || prioridade < 0 || prioridade > 1000) return { ok: false, erro: 'Prioridade de 0 a 1000.' };
  if (r.nota.length > 300) return { ok: false, erro: 'Nota até 300 letras.' };
  return {
    ok: true,
    regra: {
      id: r.id, tipo: r.tipo, campo: r.campo, operador: r.operador, padrao, projeto, valeDe: r.valeDe || null, valeAte: r.valeAte || null,
      prioridade, ativo: r.ativo, nota: r.nota.trim() || null,
    },
  };
}

/** Frase da regra: "Lista do ActiveCampaign começa com "Patrimônio Brasil" → Patrimônio Brasil 2026". */
export function fraseRegra(r: Pick<RegraCatalogo, 'tipo' | 'campo' | 'operador' | 'padrao' | 'projeto' | 'projetoNome' | 'valeDe' | 'valeAte'>): string {
  const janela = r.valeDe || r.valeAte ? ` (de ${r.valeDe ?? '…'} a ${r.valeAte ?? '…'})` : '';
  const destino = r.projeto ? `${nomeProjeto(r.projeto, r.projetoNome)}${r.tipo === 'mql' ? ' · MQL' : ''}` : 'sem projeto';
  return `${ROTULO_CAMPO_REGRA[r.campo]} ${ROTULO_OPERADOR[r.operador]} "${r.padrao}"${janela} → ${destino}`;
}

/** Linhas do "Como entrou" (ficha), da fonte de entrada para as outras. Sem dado pessoal: só o que catalogou. */
export function linhasComoEntrou(o: Pick<OrigemDetalhada, 'canal' | 'detalhe'>): { fonte: string; texto: string; em: string | null }[] {
  const d = o.detalhe ?? {};
  const linhas: { chave: string; fonte: string; texto: string; em: string | null }[] = [];
  if (d.hotmart) {
    const prod = d.hotmart.produto ?? (d.hotmart.produtoId ? `produto ${d.hotmart.produtoId}` : 'produto');
    const ofe = d.hotmart.ofertaCodigo ? ` · oferta ${d.hotmart.ofertaCodigo}` : '';
    linhas.push({ chave: 'hotmart', fonte: 'Hotmart', texto: `${prod}${ofe}${d.hotmart.classe ? ` (${d.hotmart.classe.replace(/_/g, ' ')})` : ''}`, em: d.hotmart.primeiraEm ?? d.hotmart.em ?? null });
  }
  if (d.activecampaign) {
    const a = d.activecampaign;
    const partes = [
      a.lista ? `lista ${a.listaNome ? `"${a.listaNome}"` : a.lista}` : null,
      a.tag ? `tag "${a.tag}"` : null,
      a.utm?.campaign ? `utm_campaign ${a.utm.campaign}` : null,
    ].filter(Boolean);
    linhas.push({ chave: 'activecampaign', fonte: 'ActiveCampaign', texto: partes.length ? partes.join(' · ') : 'atualização de contato, sem lista nem tag', em: a.primeiraEm ?? a.em ?? null });
  }
  if (d.clint) linhas.push({ chave: 'clint', fonte: 'Clint', texto: `funil ${d.clint.funil ?? '?'}`, em: d.clint.primeiraEm ?? d.clint.em ?? null });
  if (d.crm) linhas.push({ chave: 'crm', fonte: 'CRM', texto: `primeiro negócio no funil ${d.crm.funil ?? '?'}`, em: d.crm.primeiraEm ?? d.crm.em ?? null });
  linhas.sort((a, b) => (a.chave === o.canal ? -1 : b.chave === o.canal ? 1 : (a.em ?? '').localeCompare(b.em ?? '')));
  return linhas.map(({ fonte, texto, em }) => ({ fonte, texto, em }));
}

/** MQL de UM evento (mesma regra de crm.catalogo_mql): regra tipo 'mql' que casa a tag/lista. */
export function mqlDoEvento(
  campos: CamposEvento, regras: RegraCatalogo[], opcoes: { quando?: string | null; listas?: ListaAc[] } = {},
): RegraCatalogo | null {
  const dia = (opcoes.quando ?? '').slice(0, 10);
  return regras
    .filter((r) => r.ativo && r.tipo === 'mql' && (!r.valeDe || !dia || dia >= r.valeDe) && (!r.valeAte || !dia || dia <= r.valeAte))
    .filter((r) => {
      const v = (campos[r.campo] ?? '').trim();
      if (!v || (r.campo === 'ac_lista' && v === '0')) return false;
      const nome = r.campo === 'ac_lista' ? (campos.ac_lista_nome ?? opcoes.listas?.find((l) => l.id === v)?.nome ?? null) : null;
      return casaRegra(r.operador, r.padrao, v) || (!!nome && casaRegra(r.operador, r.padrao, nome));
    })
    .sort((a, b) => a.prioridade - b.prioridade || ORDEM_OPERADOR[a.operador] - ORDEM_OPERADOR[b.operador]
      || b.padrao.length - a.padrao.length || (a.id ?? 0) - (b.id ?? 0))[0] ?? null;
}
