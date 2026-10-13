'use client';

// Fonte REAL do dashboard da Black: RPCs dados_black_* do Supabase, pelo cliente do navegador com a sessão do usuário
// (mesmo padrão do ATM, modules/infra/atm/infrastructure/atm-data.ts). Só a chave anon pública vai ao navegador; quem
// decide o acesso são as RPCs (42501 sem acesso, P0002 fora do cadastro). Contrato de cada método e de onde vem cada
// campo: docs/dashboard-black/README.md.
//
// Função que ainda não existe no banco (PGRST202 / 42883) NÃO é falha: devolve semDado com o aviso
// "Fonte ainda não ligada" e a tela mostra "Sem dado". Qualquer outro erro vem em `erro` (a tela segura a última
// leitura e esmaece). Os mapeadores são puros e exportados para os testes (respostas cruas em respostas-rpc-black.ts).
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { FonteDadosBlack } from '../application/ports';
import { grupoSemDado } from '../domain/grupo';
import { faseDoNome } from '../domain/fase-campanha';
import {
  FASES, ISCAS,
  type Anuncio, type Campanha, type ConfigBlack, type Conjunto, type DesempenhoDia, type EtapaCampanha, type Fase, type Funil,
  type GrupoBlack, type GrupoResumoBlack, type MetasCard, type Isca, type LeadDetalhe, type LinhaPerfil, type Marcos, type MensageriaBlack,
  type Porta, type Profissao, type RecorteGrupo, type Resultado, type ResultadoAcao, type SegmentoGrupo, type TrafegoBlack,
  type Valor,
} from '../domain/tipos';

export const AVISO_NAO_LIGADA = 'Fonte ainda não ligada';
const AVISO_SEM_FONTE = 'Sem fonte no banco para este bloco.';

type Linha = Record<string, unknown>;

function objeto(v: unknown): Linha | null {
  return v && typeof v === 'object' && !Array.isArray(v) ? (v as Linha) : null;
}
function texto(v: unknown): string | null {
  if (typeof v === 'string') return v.trim() ? v : null;
  if (typeof v === 'number' && Number.isFinite(v)) return String(v);
  return null;
}
function num(v: unknown): Valor {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}
function booleano(v: unknown): boolean | null {
  return typeof v === 'boolean' ? v : null;
}
function linhas(v: unknown): Linha[] {
  return Array.isArray(v) ? v.map(objeto).filter((x): x is Linha => x !== null) : [];
}
/** Centavos (bigint do banco) -> reais. null continua null. */
function reais(v: unknown): Valor {
  const c = num(v);
  return c === null ? null : c / 100;
}

export const funcaoInexistente = (code: string | undefined) => code === 'PGRST202' || code === '42883';

function mensagemLeitura(code: string | undefined): string {
  if (code === '42501') return 'Sem permissão para ler este dashboard.';
  if (code === 'P0002') return 'Dashboard ou identificador não encontrado neste evento.';
  if (code === '22023') return 'Parâmetro inválido para este bloco.';
  return 'Não foi possível carregar os dados agora.';
}

function mensagemAcao(code: string | undefined): string {
  if (code === '42501') return 'Seu usuário não tem permissão para marcar testes neste dashboard.';
  if (code === 'P0002') return 'E-mail ou telefone não encontrado neste evento. Atualize os dados e tente novamente.';
  if (code === '22023') return 'E-mail, telefone ou motivo inválido. Confira os dados e tente novamente.';
  if (funcaoInexistente(code)) return 'A marcação de teste ainda não está disponível no banco.';
  return 'Não foi possível alterar a marcação de teste agora.';
}

/** Chama a RPC e trata o erro no padrão da tela. `mapear` recebe o `data` cru. */
async function ler<T>(nome: string, args: Record<string, unknown>, vazio: T, mapear: (data: unknown) => { data: T; semDado: boolean }): Promise<Resultado<T>> {
  try {
    const supabase = createBrowserSupabase();
    const { data, error } = await supabase.rpc(nome, args);
    if (error) {
      if (funcaoInexistente(error.code)) return { data: vazio, semDado: true, erro: null, aviso: AVISO_NAO_LIGADA };
      logQueryError(nome, { message: error.code ?? 'erro' });
      return { data: vazio, semDado: true, erro: mensagemLeitura(error.code) };
    }
    return { ...mapear(data), erro: null };
  } catch {
    logQueryError(nome, { message: 'falha de conexão' });
    return { data: vazio, semDado: true, erro: 'Falha de conexão ao carregar este bloco. Os últimos dados disponíveis foram mantidos.' };
  }
}

async function chamarAcao(nome: string, args: Record<string, unknown>): Promise<ResultadoAcao> {
  try {
    const supabase = createBrowserSupabase();
    const { data, error } = await supabase.rpc(nome, args);
    if (error) {
      logQueryError(nome, { message: error.code ?? 'erro' });
      return { data: null, erro: mensagemAcao(error.code) };
    }
    const n = num(data);
    return n === null ? { data: null, erro: 'O banco não confirmou a alteração.' } : { data: n, erro: null };
  } catch {
    logQueryError(nome, { message: 'falha de conexão' });
    return { data: null, erro: 'Não foi possível concluir a marcação agora.' };
  }
}

// ---------- config ----------

/**
 * O que existe no cadastro (dados.dashboards, migration 20261012231649): só o início do período. Orçamento e live vêm da
 * constante ORCAMENTO abaixo. As metas de leads, CPL e régua estão só no plano, sem tabela: ficam null ("Sem dado").
 */
const CADASTRO: Record<string, { inicio: string }> = { 'black-friday-2026-10': { inicio: '2026-10-04' } };

/**
 * Orçamento de tráfego e data da live, passados pelo Victor em 13/10/2026 (tabela "Orçamento de tráfego, Black Friday
 * 2026", sem o imposto do Meta, que é contabilizado à parte). Ainda não há tabela no banco: ficam aqui, no adaptador,
 * como o início do período. Captação (220.000) = C2 Iscas 70.000 + C3 Convite direto 150.000; a tela só tem a fase.
 * Live e abertura do carrinho: 03/11/2026 às 19h30 (PLANO-DASHBOARD-JORNADA.md).
 */
const METAS_PLANO: Record<string, {
  metaLeads: number; cplAlvoMedio: number; regua: { meta: number; teto: number }; cards: MetasCard;
}> = {
  // Victor, 13/10/2026: 15.000 leads até 03/11 (a meta diária fica para o gráfico de captação); CPL médio até R$ 16,70, ideal R$ 15, teto por conjunto R$ 20.
  'black-friday-2026-10': {
    metaLeads: 15000, cplAlvoMedio: 16.7, regua: { meta: 15, teto: 20 },
    cards: { mql: 0.6, ingressoGrupo: 0.85, conversaoPagina: 0.2, connectRate: 0.85, ctr: 0.02, cpc: 3, cpm: 50 },
  },
};

const ORCAMENTO: Record<string, { total: number; reserva: number; liveEm: string; porFase: Record<Fase, number> }> = {
  'black-friday-2026-10': {
    total: 428571, reserva: 16496, liveEm: '2026-11-03T19:30:00-03:00',
    porFase: { antecipacao: 17591, distribuicao: 47575, captacao: 220000, aquecimento: 26909, remarketing: 30000, live_carrinho: 70000 },
  },
};

export function configReal(chave: string): Resultado<ConfigBlack> {
  const c = CADASTRO[chave];
  const previstoPorFase = Object.fromEntries(FASES.map((f) => [f, null])) as ConfigBlack['previstoPorFase'];
  const orc = c ? ORCAMENTO[chave] : undefined;
  const mp = c ? METAS_PLANO[chave] : undefined;
  if (orc) for (const f of FASES) previstoPorFase[f] = orc.porFase[f];
  const data: ConfigBlack = {
    chave, inicio: c?.inicio ?? '', inicioCaptacao: null, liveEm: orc?.liveEm ?? null, metaLeads: mp?.metaLeads ?? null, metaLeadsDia: null,
    cplAlvoMedio: mp?.cplAlvoMedio ?? null, reguaCpl: mp?.regua ?? null,
    metas: mp?.cards ?? { mql: null, ingressoGrupo: null, conversaoPagina: null, connectRate: null, ctr: null, cpc: null, cpm: null },
    orcamentoTotal: orc?.total ?? null, previstoPorFase, reserva: orc?.reserva ?? null, baseDaCasa: null, semanas: [],
    fontes: {
      Cadastro: 'dados.dashboards.periodo_inicio (migration 20261012231649): início do período, 04/10/2026.',
      Tráfego: 'dados_black_trafego (mkt_trafego, coleta do Meta).',
      Leads: 'dados_black_perfil e dados_black_leads (migration 20261012234606).',
      Grupo: 'dados_black_grupo (webhook do SendFlow e foto dos grupos, migration 20261012234606).',
      Metas: 'Orçamento por fase, total, reserva, data da live, metas de leads, CPL, régua e dos cards: passados pelo Victor em 13/10/2026 (no adaptador).',
    },
  };
  if (!c) return { data, semDado: true, erro: 'Dashboard não encontrado neste cadastro.' };
  return { data, semDado: false, erro: null };
}

// ---------- tráfego ----------

/** Etapa e subtipo do nome da campanha -> funil da tela. Sem etapa (TEASER, MANIFESTO, CPF01) = null ("Sem etapa"). */
export function funilDaEtapa(etapa: EtapaCampanha | null, subtipo: string | null): Funil | null {
  if (etapa === 'C1') return 'c1';
  if (etapa === 'C3') return 'c3';
  if (etapa === 'C2' && subtipo === 'CONSULTORIA') return 'consultoria';
  if (etapa === 'C2' && subtipo === 'ISCA') return 'iscas';
  return null;
}

const etapaDe = (v: unknown): EtapaCampanha | null => (v === 'C1' || v === 'C2' || v === 'C3' ? v : null);

export const TRAFEGO_VAZIO: TrafegoBlack = { campanhas: [], conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null };

export function mapearTrafego(cru: unknown): { data: TrafegoBlack; semDado: boolean } {
  const r = objeto(cru);
  if (!r) return { data: TRAFEGO_VAZIO, semDado: true };
  const campanhas: Campanha[] = [];
  for (const c of linhas(r.campanhas)) {
    const id = texto(c.id); const nome = texto(c.nome);
    // O banco só aceita 'meta' em mkt_trafego; outra plataforma não tem lugar na tela e fica de fora.
    if (!id || !nome || c.plataforma !== 'meta') continue;
    const etapa = etapaDe(c.etapa); const subtipo = texto(c.subtipo);
    campanhas.push({ id, nome, canal: 'meta', funil: funilDaEtapa(etapa, subtipo), fase: faseDoNome(nome), etapa, subtipo, conflito: booleano(c.conflito), idExterno: texto(c.campanha_externa) });
  }
  const conjuntos: Conjunto[] = linhas(r.conjuntos).flatMap((j) => {
    const id = texto(j.id); const campanhaId = texto(j.campanha_id); const nome = texto(j.nome);
    return id && campanhaId && nome ? [{ id, campanhaId, nome, isca: null, conjuntoC3: null, idExterno: texto(j.conjunto_externa) }] : [];
  });
  const anuncios: Anuncio[] = linhas(r.anuncios).flatMap((a) => {
    const id = texto(a.id); const conjuntoId = texto(a.conjunto_id); const nome = texto(a.nome);
    return id && conjuntoId && nome
      ? [{ id, conjuntoId, nome, formato: null, paginaId: null, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null, idExterno: texto(a.anuncio_externa) }]
      : [];
  });
  const dias: DesempenhoDia[] = linhas(r.dias_anuncio).flatMap((d) => {
    const anuncioId = texto(d.anuncio_id); const dia = texto(d.dia); const gasto = reais(d.gasto_centavos); const impressoes = num(d.impressoes);
    // gasto e impressões são NOT NULL na tabela; linha sem eles não é desempenho medido.
    if (!anuncioId || !dia || gasto === null || impressoes === null) return [];
    return [{
      anuncioId, dia: dia.slice(0, 10), gasto, impressoes,
      cliquesLink: num(d.cliques_link), landingPageViews: num(d.landing_page_views), alcance: num(d.alcance), frequencia: num(d.frequencia),
      videoP50: num(d.video_p50), videoP75: num(d.video_p75), thruplay: num(d.video_thruplay),
    }];
  });
  const porCampanha = new Map<string, number>();
  for (const d of linhas(r.dias_campanha)) {
    const id = texto(d.campanha_id); const g = reais(d.gasto_centavos);
    if (id && g !== null) porCampanha.set(id, (porCampanha.get(id) ?? 0) + g);
  }
  return {
    data: {
      campanhas, conjuntos, anuncios, paginas: [], dias, totais: [], coletadoEm: texto(r.coletado_em),
      anuncioDesde: texto(r.anuncio_desde), gastoCampanhas: [...porCampanha].map(([campanhaId, gasto]) => ({ campanhaId, gasto })),
    },
    semDado: campanhas.length === 0,
  };
}

// ---------- perfil ----------

const PORTAS: readonly Porta[] = ['inscricao_direta', 'consultoria', 'isca'];
const PROFISSOES: readonly Profissao[] = ['advogado', 'contador', 'estudante_direito', 'outros'];
const FUNIL_DA_PORTA: Record<Porta, Funil> = { inscricao_direta: 'c3', consultoria: 'consultoria', isca: 'iscas' };

export function mapearPerfil(cru: unknown): { data: LinhaPerfil[]; semDado: boolean } {
  const data = linhas(cru).flatMap((x): LinhaPerfil[] => {
    const leadId = texto(x.lead_id); const pessoaId = texto(x.pessoa_id); const criadoEm = texto(x.criado_em);
    if (!leadId || !pessoaId || !criadoEm) return [];
    const porta = PORTAS.includes(x.porta as Porta) ? (x.porta as Porta) : null;
    const isca = ISCAS.includes(x.isca as Isca) ? (x.isca as Isca) : null;
    const canal = x.canal === 'meta' || x.canal === 'google' ? x.canal : null;
    const profissao = PROFISSOES.includes(x.profissao as Profissao) ? (x.profissao as Profissao) : null;
    const campos = objeto(x.campos);
    return [{
      leadId, pessoaId, criadoEm, primeiraPorta: x.primeira_porta === true,
      porta, funil: porta ? FUNIL_DA_PORTA[porta] : null, isca, conjuntoC3: null,
      // Ids internos do tráfego: preenchidos depois, ao casar o anúncio do Meta com o tráfego (domain/alinhar.ts).
      campanhaId: null, conjuntoId: null, anuncioId: null,
      campanhaMeta: texto(x.campanha_id), conjuntoMeta: texto(x.conjunto_id), anuncioMeta: texto(x.anuncio_id),
      paginaId: texto(x.pagina), pagina: texto(x.pagina),
      origem: canal ? 'pago' : null, canal,
      utmSource: texto(x.utm_source), utmMedium: texto(x.utm_medium), utmCampaign: texto(x.utm_campaign),
      utmContent: texto(x.utm_content), utmTerm: texto(x.utm_term),
      profissao, profissaoBruta: texto(x.profissao_bruta), mql: booleano(x.mql),
      uf: texto(x.uf), ufOrigem: texto(x.uf) ? 'ddd' : null,
      listaOrigem: null, temperaturaBase: null, jaNaBase: null,
      entrouGrupoEm: texto(x.entrou_grupo_em), entradaGrupoAproximada: booleano(x.entrada_grupo_aproximada),
      teste: x.teste === true, pareceTeste: booleano(x.parece_teste),
      aCorrigir: Array.isArray(x.a_corrigir) ? x.a_corrigir.filter((v): v is string => typeof v === 'string') : [],
      campos,
    }];
  });
  return { data, semDado: false };
}

export function mapearLeads(cru: unknown): { data: LeadDetalhe[]; semDado: boolean } {
  const data = linhas(cru).flatMap((x) => {
    const leadId = texto(x.lead_id);
    return leadId ? [{ leadId, nome: texto(x.nome), email: texto(x.email), telefone: texto(x.telefone) }] : [];
  });
  return { data, semDado: false };
}

// ---------- grupo ----------

const SEGMENTOS: readonly SegmentoGrupo[] = ['advogado', 'contador', 'outros'];

export function mapearGrupo(cru: unknown): { data: GrupoResumoBlack; semDado: boolean } {
  const r = objeto(cru);
  if (!r) return { data: grupoSemDado(), semDado: true };
  const periodo = objeto(r.periodo); const leads = objeto(r.leads); const at = objeto(r.atualizado); const rec = objeto(r.recorte);
  const recorte: RecorteGrupo | null = rec && typeof rec.tipo === 'string' && typeof rec.valor === 'string'
    ? { tipo: rec.tipo as RecorteGrupo['tipo'], valor: rec.valor } : null;
  const grupos: GrupoBlack[] = linhas(r.grupos).flatMap((g) => {
    const campanha = texto(g.campanha);
    if (!campanha) return [];
    return [{
      campanha, segmento: SEGMENTOS.includes(g.segmento as SegmentoGrupo) ? (g.segmento as SegmentoGrupo) : null,
      unicos: num(g.unicos), unicosWebhook: num(g.unicos_webhook), unicosSoFoto: num(g.unicos_so_foto), unicosCruzados: num(g.unicos_cruzados),
    }];
  });
  return {
    data: {
      periodo: { de: texto(periodo?.de), ate: texto(periodo?.ate) }, recorte, grupos,
      unicosGruposMql: num(r.unicos_grupos_mql), unicosGruposTotal: num(r.unicos_grupos_total), unicosCruzadosMql: num(r.unicos_cruzados_mql),
      leads: {
        unicos: num(leads?.unicos), mql: num(leads?.mql), advogado: num(leads?.advogado), estudanteDireito: num(leads?.estudante_direito),
        advogadoMaisEstudante: num(leads?.advogado_mais_estudante), contador: num(leads?.contador), outros: num(leads?.outros),
        semProfissao: num(leads?.sem_profissao), naoMql: num(leads?.nao_mql),
      },
      atualizado: { ultimoEventoWebhook: texto(at?.ultimo_evento_webhook), ultimaFoto: texto(at?.ultima_foto) },
    },
    semDado: false,
  };
}

// ---------- fonte ----------

const semFonte = <T,>(data: T): Promise<Resultado<T>> => Promise.resolve({ data, semDado: true, erro: null, aviso: AVISO_SEM_FONTE });

export const fonteSupabaseBlack: FonteDadosBlack = {
  modo: 'real',
  agora: () => new Date(),
  config: (chave) => Promise.resolve(configReal(chave)),
  trafego: (chave, p) => ler('dados_black_trafego', { p_chave: chave, p_de: p.de, p_ate: p.ate }, TRAFEGO_VAZIO, mapearTrafego),
  perfil: (chave, p, opcoes) =>
    ler('dados_black_perfil', { p_chave: chave, p_de: p.de, p_ate: p.ate, p_incluir_teste: opcoes?.incluirTeste === true }, [] as LinhaPerfil[], mapearPerfil),
  leads: (chave, leadIds) =>
    leadIds.length === 0
      ? Promise.resolve({ data: [], semDado: false, erro: null })
      : ler('dados_black_leads', { p_chave: chave, p_lead_ids: leadIds.slice(0, 500) }, [] as LeadDetalhe[], mapearLeads),
  grupo: (chave, p, recorte) =>
    ler('dados_black_grupo', { p_chave: chave, p_de: p.de, p_ate: p.ate, p_incluir_teste: false, p_recorte: recorte }, grupoSemDado(recorte), mapearGrupo),
  marcarTeste: (chave, lead) =>
    chamarAcao('dados_marcar_teste', { p_chave: chave, p_email: lead.email, p_telefone: lead.telefone, p_motivo: 'teste' }),
  desmarcarTeste: (chave, lead) =>
    chamarAcao('dados_desmarcar_teste', { p_chave: chave, p_email: lead.email, p_telefone: lead.telefone }),
  // Sem fonte no banco: Sem dado, nunca zero.
  mensageria: () => semFonte<MensageriaBlack>({ canais: [], envios: [], regua: [] }),
  marcos: () => semFonte<Marcos>({ presencaLive: null, vendas: null }),
};
