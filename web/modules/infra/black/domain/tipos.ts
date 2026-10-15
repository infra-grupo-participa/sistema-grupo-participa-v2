// Tipos do dashboard da Black Friday 2026 (Infra › Dashboards › CSM, modelo 'jornada-captacao').
// Contrato e decisões: docs/dashboard-black/README.md. Plano: PLANO-TECNICO-V2.md (cérebro do Victor).

/** null = sem dado (fonte não mediu); 0 = zero medido. Nunca trocar um pelo outro. */
export type Valor = number | null;

export type Funil = 'c1' | 'consultoria' | 'iscas' | 'c3';
/** C2 é o agrupamento das portas Consultoria e Iscas no filtro global. */
export type FiltroFunil = 'todos' | 'c2' | Funil;
export type Canal = 'meta' | 'google';
export type FiltroCanal = 'todos' | Canal;
/** As 6 fases do Caio (CONCEPCAO-TRAFEGO-CAIO.md). NÃO são os códigos de mkt_trafego.fases. */
export type Fase = 'antecipacao' | 'distribuicao' | 'captacao' | 'aquecimento' | 'remarketing' | 'live_carrinho';
export type Isca = 'Fluxograma' | 'Futurômetro' | 'Checkup';
export type ConjuntoC3 = 'base' | 'quente' | 'aberto';
export type Porta = 'isca' | 'consultoria' | 'inscricao_direta';
export type OrigemLead = 'pago' | 'base_api' | 'grupo_legado' | 'organico';
export type AbaBlack = 'visao' | 'jornada' | 'criativos' | 'mensageria' | 'historico';
/** As 4 respostas da pergunta de profissão (decisão do Victor de 12/10/2026, noite: sem a opção do patrimônio da família). */
export type Profissao = 'advogado' | 'contador' | 'estudante_direito' | 'outros';

/** AAAA-MM-DD no fuso de São Paulo, inclusivo nas duas pontas. */
export interface Periodo { de: string; ate: string }
export interface FiltroCriativos { campanha?: string; conjunto?: string; anuncio?: string; pagina?: string }
export interface Recorte { funil: FiltroFunil; canal: FiltroCanal; periodo: string; periodoPersonalizado?: Periodo | null; aba: AbaBlack; criativos: FiltroCriativos; historicoModo?: 'dia-a-dia' | 'geral' }

/** Régua de CPL do Caio (meta e teto, em reais). */
export interface ReguaCpl { meta: number; teto: number }

/** Metas dos cards com fórmula (Victor, 13/10/2026). Taxas em fração (0,6 = 60%); CPM, CPC em reais. null = sem meta. */
export interface MetasCard {
  mql: Valor; ingressoGrupo: Valor; conversaoPagina: Valor; connectRate: Valor; ctr: Valor; cpc: Valor; cpm: Valor;
}

/**
 * Configuração do evento. Na fonte real só `inicio` vem do cadastro (dados.dashboards.periodo_inicio); as metas
 * existem só no plano (CONCEPCAO), não no banco, e ficam null ("Sem dado") até terem cadastro. Ver o README.
 */
export interface ConfigBlack {
  chave: string;
  /** Primeiro dia com gasto (antecipação). */
  inicio: string;
  /** Primeiro dia da meta diária de leads. null = sem cadastro. */
  inicioCaptacao: string | null;
  /** ISO com fuso (-03:00). null = sem cadastro. */
  liveEm: string | null;
  metaLeads: Valor;
  metaLeadsDia: Valor;
  cplAlvoMedio: Valor;
  reguaCpl: ReguaCpl | null;
  metas: MetasCard;
  orcamentoTotal: Valor;
  previstoPorFase: Record<Fase, Valor>;
  reserva: Valor;
  /** Tamanho da base da casa (nó "Base da casa" da Jornada). */
  baseDaCasa: Valor;
  semanas: { rotulo: string; de: string; ate: string }[];
  /** Nome curto da fonte → descrição com caminho e data. Vai nas dicas da tela. */
  fontes: Record<string, string>;
}

/** Etapa do nome da campanha (mkt_trafego.etapa_black): C1, C2 ou C3; null = sem o código no nome ("Sem etapa"). */
export type EtapaCampanha = 'C1' | 'C2' | 'C3';
export type EstadoColetaCampanha = 'atual' | 'falha_recente' | 'velha' | 'sem_coleta';
export interface EstadoColetaConta {
  estado: EstadoColetaCampanha; ultimaOkEm: string | null; ultimaFalhaEm: string | null;
  validadeMin: number | null;
}
export interface Campanha {
  id: string; nome: string; canal: Canal; funil: Funil | null; fase: Fase | null;
  /** Só a fonte real preenche: etapa e subtipo como vêm do banco, e se o nome tem dois subtipos (conflito). */
  etapa?: EtapaCampanha | null; subtipo?: string | null; conflito?: boolean | null;
  /** Prova de cobertura de coleta por conta, contrato proposto da RPC dados_black_trafego. */
  primeiraVistaEm?: string | null; coleta?: EstadoColetaConta | null; semEntregaComprovada?: boolean;
  /** Id da campanha no Meta (mkt_trafego.campanhas.campanha_externa), quando dados_black_trafego devolver. */
  idExterno?: string | null;
}
export interface Conjunto {
  id: string; campanhaId: string; nome: string; isca: Isca | null; conjuntoC3: ConjuntoC3 | null;
  /** Id do conjunto no Meta (mkt_trafego.conjuntos.conjunto_externa), quando dados_black_trafego devolver. */
  idExterno?: string | null;
}
export interface Anuncio {
  id: string; conjuntoId: string; nome: string; formato: 'video' | 'imagem' | null;
  paginaId: string | null; miniaturaUrl: string | null; linkPrevia: string | null; linkGerenciador: string | null;
  /** Id do anúncio no Meta (mkt_trafego.anuncios.anuncio_externa). Só a fonte real preenche; casa com o lead pela utm. */
  idExterno?: string | null;
}
export interface Pagina { id: string; url: string; rotulo: string; porta: Porta | null; isca: Isca | null }
export interface DesempenhoDia {
  anuncioId: string; dia: string; gasto: number; impressoes: number;
  cliquesLink: Valor; landingPageViews: Valor; alcance: Valor; frequencia: Valor;
  videoP50: Valor; videoP75: Valor; thruplay: Valor;
}
/** Alcance e frequência do período inteiro: não somam entre dias nem entre campanhas. */
export interface TotalPeriodo {
  nivel: 'campanha' | 'conjunto' | 'anuncio'; id: string; alcance: Valor; frequencia: Valor;
  /** Só campanha: intervalo do total salvo em mkt_trafego.desempenho_total. */
  de?: string | null; ate?: string | null; gasto?: Valor; impressoes?: Valor; coletadoEm?: string | null;
}
export interface TrafegoBlack {
  campanhas: Campanha[]; conjuntos: Conjunto[]; anuncios: Anuncio[]; paginas: Pagina[];
  dias: DesempenhoDia[]; totais: TotalPeriodo[]; coletadoEm: string | null;
  /** Fonte real: primeiro dia com quebra por anúncio (antes dele o gasto só existe por campanha). */
  anuncioDesde?: string | null;
  /** Fonte real: gasto do período por campanha (dias_campanha), em reais. Confere com a soma por anúncio. */
  gastoCampanhas?: { campanhaId: string; gasto: number }[];
  /** Fonte real: gasto diário de campanha, para a régua e as séries de investimento. */
  gastoCampanhasDiario?: { campanhaId: string; dia: string; gasto: number }[];
}

/** Uma linha por cadastro (porta). Sem dado pessoal: nome, e-mail e telefone só em LeadDetalhe. */
export interface LinhaPerfil {
  leadId: string; pessoaId: string; criadoEm: string; primeiraPorta: boolean;
  porta: Porta | null; funil: Funil | null; isca: Isca | null; conjuntoC3: ConjuntoC3 | null;
  campanhaId: string | null; conjuntoId: string | null; anuncioId: string | null; paginaId: string | null;
  origem: OrigemLead | null; canal: Canal | null;
  utmSource: string | null; utmMedium: string | null; utmCampaign: string | null; utmContent: string | null; utmTerm: string | null;
  profissao: Profissao | null; profissaoBruta: string | null;
  /** UF derivada do DDD do telefone ('Outros' = DDD fora da tabela dados.ddd_uf). */
  uf: string | null; ufOrigem: 'ddd' | null;
  listaOrigem: string | null; temperaturaBase: string | null; jaNaBase: boolean | null;
  entrouGrupoEm: string | null; teste: boolean;
  // Campos do contrato da B (dados_black_perfil). Opcionais: o demo não tem todos.
  /** Página do envio, string exata da fonte: captacao, fluxograma, consultoria, checkup ou futurometro. */
  pagina?: string | null;
  /** MQL calculado no banco (advogado, contador ou estudante de Direito). */
  mql?: boolean | null;
  /** Sugestão do banco de que o envio é teste. Só sugere: nunca marca sozinho. */
  pareceTeste?: boolean | null;
  /** Problemas de cadastro que o banco apontou (profissao_vazia, sem_utm, utm_campaign_fora_do_padrao). */
  aCorrigir?: string[];
  /** Entrada no grupo vinda só da foto do grupo (sem a hora exata do webhook). */
  entradaGrupoAproximada?: boolean | null;
  /** Ids do Meta como vieram da utm (o que vem depois do |). Os campos campanhaId/conjuntoId/anuncioId da tela são
   * os ids internos do tráfego, preenchidos só quando o anúncio do Meta casa com um anúncio do tráfego. */
  campanhaMeta?: string | null; conjuntoMeta?: string | null; anuncioMeta?: string | null;
  /** Respostas próprias de cada página, como vieram do banco. */
  campos?: Record<string, unknown> | null;
}
export interface LeadDetalhe { leadId: string; nome: string | null; email: string | null; telefone: string | null }

export type CanalDisparo = 'api' | 'sms' | 'ligacao' | 'grupo' | 'email';
export const CANAIS_DISPARO: readonly CanalDisparo[] = ['api', 'sms', 'ligacao', 'grupo', 'email'];
/** Canal pago tem custo por envio; grupo e e-mail não têm (custo null, a tela diz "Sem custo por envio"). */
export const CANAL_PAGO: Record<CanalDisparo, boolean> = { api: true, sms: true, ligacao: true, grupo: false, email: false };

/**
 * Métricas de um canal (ou de um envio). Cada canal usa as que fazem sentido para ele (o rótulo vem da tela):
 * `lidas` = lidas na API, atendidas na ligação, abertos no e-mail; `falhas` = não atendidas na ligação,
 * devolvidos no e-mail. Métrica que o canal não mede fica null ("Sem dado"), nunca zero.
 */
export interface MetricasDisparo {
  enviados: Valor; entregues: Valor; lidas: Valor; cliques: Valor; falhas: Valor; custo: Valor;
}
export interface CanalMensageria extends MetricasDisparo { canal: CanalDisparo; envios: number }
/** Um envio (disparo): cada um tem o seu objetivo; o custo é do envio, não de um resultado depois dele. */
export interface EnvioMensageria extends MetricasDisparo {
  id: string; canal: CanalDisparo; titulo: string; objetivo: string;
  /** Data e hora do envio, `AAAA-MM-DDTHH:MM` no horário de Brasília. */
  enviadoEm: string;
  /** Tamanho da base para a qual o envio saiu (pessoas, ou membros nos grupos). */
  base: Valor; copy: string | null;
}
export interface MensageriaBlack {
  canais: CanalMensageria[];
  /** Envios do período, do mais recente para o mais antigo. */
  envios: EnvioMensageria[];
  regua: { janela: '2h' | '12h' | '24h'; enviados: Valor; ingressos: Valor }[];
}
export interface Marcos { presencaLive: Valor; vendas: Valor }
/**
 * Resultado de uma leitura. `erro` = falha (a tela segura a última leitura e esmaece). `aviso` = sem dado
 * legítimo com motivo (ex.: "Fonte ainda não ligada" quando a função ainda não existe no banco): não é falha.
 */
export interface Resultado<T> { data: T; semDado: boolean; erro: string | null; aviso?: string | null }
/** Resultado de uma ação (marcar ou desmarcar teste): quantas marcações mudaram, ou o erro. */
export interface ResultadoAcao { data: number | null; erro: string | null }

/** Segmento do grupo de WhatsApp no contrato da B. */
export type SegmentoGrupo = 'advogado' | 'contador' | 'outros';
/** Um grupo do SendFlow. `campanha` = nome exato da campanha no SendFlow. */
export interface GrupoBlack {
  campanha: string; segmento: SegmentoGrupo | null;
  unicos: Valor; unicosWebhook: Valor; unicosSoFoto: Valor;
  /** Dos leads do recorte, quantos estão neste grupo. null sem recorte. */
  unicosCruzados: Valor;
  leadsNoGrupo?: Valor; leadsDoSegmento?: Valor;
  leadsNoGrupoPorClasse?: { advogado: Valor; estudanteDireito: Valor; contador: Valor; outros: Valor; semProfissao: Valor };
}
/** Leads únicos (pessoa por telefone, 8 últimos dígitos; senão e-mail) do período e do recorte, sem teste. */
export interface LeadsGrupoBlack {
  unicos: Valor; mql: Valor; advogado: Valor; estudanteDireito: Valor; advogadoMaisEstudante: Valor;
  contador: Valor; outros: Valor; semProfissao: Valor; naoMql: Valor;
}
/** Recorte que o servidor aplica no grupo (p_recorte). */
export type TipoRecorteGrupo = 'porta' | 'isca' | 'campanha' | 'conjunto' | 'anuncio';
export interface RecorteGrupo { tipo: TipoRecorteGrupo; valor: string }
/** Resposta de dados_black_grupo, já em camelCase. */
export interface GrupoResumoBlack {
  periodo: { de: string | null; ate: string | null };
  recorte: RecorteGrupo | null;
  /** Taxa geral agregada pelo banco, sem cruzar membros do grupo com leads. `pct` vem em pontos percentuais. */
  ingressoGeral?: { numerosUnicosNoGrupo: Valor; leadsUnicos: Valor; pct: Valor } | null;
  grupos: GrupoBlack[];
  unicosGruposMql: Valor; unicosGruposTotal: Valor;
  /** Dos leads MQL do recorte, quantos estão nos grupos de MQL. null sem recorte. */
  unicosCruzadosMql: Valor;
  leadsEmAlgumGrupo?: Valor; leadsEmMaisDeUmGrupo?: Valor;
  leads: LeadsGrupoBlack;
  atualizado: { ultimoEventoWebhook: string | null; ultimaFoto: string | null };
}

export const FUNIS: readonly Funil[] = ['c1', 'consultoria', 'iscas', 'c3'];
export const FASES: readonly Fase[] = ['antecipacao', 'distribuicao', 'captacao', 'aquecimento', 'remarketing', 'live_carrinho'];
export const ISCAS: readonly Isca[] = ['Fluxograma', 'Futurômetro', 'Checkup'];
export const CONJUNTOS_C3: readonly ConjuntoC3[] = ['base', 'quente', 'aberto'];

export const ROTULO_FUNIL: Record<Funil, string> = { c1: 'C1', consultoria: 'Consultoria', iscas: 'Iscas', c3: 'C3' };
export const ROTULO_FILTRO_FUNIL: Record<FiltroFunil, string> = { todos: 'Todos', c1: 'C1', c2: 'C2', consultoria: 'Consultoria', iscas: 'Iscas', c3: 'C3' };
export const ROTULO_FASE: Record<Fase, string> = {
  antecipacao: '0. Antecipação', distribuicao: '1. Distribuição', captacao: '2. Captação',
  aquecimento: '3. Aquecimento', remarketing: '4. Remarketing', live_carrinho: '5. Live e carrinho',
};
export const ROTULO_CANAL: Record<Canal, string> = { meta: 'Meta', google: 'Google' };
export const ROTULO_PORTA: Record<Porta, string> = { isca: 'Isca', consultoria: 'Consultoria', inscricao_direta: 'Inscrição direta' };
export const ROTULO_ORIGEM: Record<OrigemLead, string> = { pago: 'Tráfego pago', base_api: 'Base por API', grupo_legado: 'Grupo legado', organico: 'Orgânico' };
export const ROTULO_CONJUNTO_C3: Record<ConjuntoC3, string> = { base: 'Base', quente: 'Quente', aberto: 'Aberto' };
export const ROTULO_PROFISSAO: Record<Profissao, string> = {
  advogado: 'Advogado', contador: 'Contador', estudante_direito: 'Estudante de Direito', outros: 'Outros',
};
/** MQL do evento inteiro = advogado, contador ou estudante de Direito (Victor, 12/10/2026). */
export const PROFISSOES_MQL: ReadonlySet<Profissao> = new Set<Profissao>(['advogado', 'contador', 'estudante_direito']);
export const NAO_INFORMADO = 'Não informado';
