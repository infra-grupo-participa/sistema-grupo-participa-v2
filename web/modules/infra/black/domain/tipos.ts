// Tipos do dashboard da Black Friday 2026 (Infra › Dashboards › CSM, modelo 'jornada-captacao').
// Contrato e decisões: docs/dashboard-black/README.md. Plano: PLANO-TECNICO-V2.md (cérebro do Victor).

/** null = sem dado (fonte não mediu); 0 = zero medido. Nunca trocar um pelo outro. */
export type Valor = number | null;

export type Funil = 'c1' | 'consultoria' | 'iscas' | 'c3';
export type FiltroFunil = 'todos' | Funil;
export type Canal = 'meta' | 'google';
export type FiltroCanal = 'todos' | Canal;
/** As 6 fases do Caio (CONCEPCAO-TRAFEGO-CAIO.md). NÃO são os códigos de mkt_trafego.fases. */
export type Fase = 'antecipacao' | 'distribuicao' | 'captacao' | 'aquecimento' | 'remarketing' | 'live_carrinho';
export type Isca = 'Fluxograma' | 'Futurômetro' | 'Checkup';
export type ConjuntoC3 = 'base' | 'quente' | 'aberto';
export type Porta = 'isca' | 'consultoria' | 'inscricao_direta';
export type OrigemLead = 'pago' | 'base_api' | 'grupo_legado' | 'organico';
export type AbaBlack = 'visao' | 'jornada' | 'criativos' | 'mensageria' | 'historico';
export type Profissao = 'advogado' | 'contador' | 'outros';

/** AAAA-MM-DD no fuso de São Paulo, inclusivo nas duas pontas. */
export interface Periodo { de: string; ate: string }
export interface FiltroCriativos { campanha?: string; conjunto?: string; anuncio?: string; pagina?: string }
export interface Recorte { funil: FiltroFunil; canal: FiltroCanal; periodo: string; aba: AbaBlack; criativos: FiltroCriativos }

export interface ConfigBlack {
  chave: string;
  /** Primeiro dia com gasto (antecipação). */
  inicio: string;
  /** Primeiro dia da meta diária de leads. */
  inicioCaptacao: string;
  /** ISO com fuso (-03:00). */
  liveEm: string;
  metaLeads: number;
  metaLeadsDia: number;
  cplAlvoMedio: number;
  reguaCpl: { meta: number; teto: number };
  orcamentoTotal: number;
  previstoPorFase: Record<Fase, Valor>;
  reserva: Valor;
  /** Tamanho da base da casa (nó "Base da casa" da Jornada). */
  baseDaCasa: Valor;
  semanas: { rotulo: string; de: string; ate: string }[];
  /** Nome curto da fonte → descrição com caminho e data. Vai nas dicas da tela. */
  fontes: Record<string, string>;
}

export interface Campanha { id: string; nome: string; canal: Canal; funil: Funil | null; fase: Fase | null }
export interface Conjunto { id: string; campanhaId: string; nome: string; isca: Isca | null; conjuntoC3: ConjuntoC3 | null }
export interface Anuncio {
  id: string; conjuntoId: string; nome: string; formato: 'video' | 'imagem' | null;
  paginaId: string | null; miniaturaUrl: string | null; linkPrevia: string | null; linkGerenciador: string | null;
}
export interface Pagina { id: string; url: string; rotulo: string; porta: Porta | null; isca: Isca | null }
export interface DesempenhoDia {
  anuncioId: string; dia: string; gasto: number; impressoes: number;
  cliquesLink: Valor; landingPageViews: Valor; alcance: Valor; frequencia: Valor;
  videoP50: Valor; videoP75: Valor; thruplay: Valor;
}
/** Alcance e frequência do período inteiro: não somam entre dias nem entre campanhas. */
export interface TotalPeriodo { nivel: 'campanha' | 'conjunto' | 'anuncio'; id: string; alcance: Valor; frequencia: Valor }
export interface TrafegoBlack {
  campanhas: Campanha[]; conjuntos: Conjunto[]; anuncios: Anuncio[]; paginas: Pagina[];
  dias: DesempenhoDia[]; totais: TotalPeriodo[]; coletadoEm: string | null;
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
export interface Resultado<T> { data: T; semDado: boolean; erro: string | null }

export const FUNIS: readonly Funil[] = ['c1', 'consultoria', 'iscas', 'c3'];
export const FASES: readonly Fase[] = ['antecipacao', 'distribuicao', 'captacao', 'aquecimento', 'remarketing', 'live_carrinho'];
export const ISCAS: readonly Isca[] = ['Fluxograma', 'Futurômetro', 'Checkup'];
export const CONJUNTOS_C3: readonly ConjuntoC3[] = ['base', 'quente', 'aberto'];

export const ROTULO_FUNIL: Record<Funil, string> = { c1: 'C1', consultoria: 'Consultoria', iscas: 'Iscas', c3: 'C3' };
export const ROTULO_FASE: Record<Fase, string> = {
  antecipacao: '0. Antecipação', distribuicao: '1. Distribuição', captacao: '2. Captação',
  aquecimento: '3. Aquecimento', remarketing: '4. Remarketing', live_carrinho: '5. Live e carrinho',
};
export const ROTULO_CANAL: Record<Canal, string> = { meta: 'Meta', google: 'Google' };
export const ROTULO_PORTA: Record<Porta, string> = { isca: 'Isca', consultoria: 'Consultoria', inscricao_direta: 'Inscrição direta' };
export const ROTULO_ORIGEM: Record<OrigemLead, string> = { pago: 'Tráfego pago', base_api: 'Base por API', grupo_legado: 'Grupo legado', organico: 'Orgânico' };
export const ROTULO_CONJUNTO_C3: Record<ConjuntoC3, string> = { base: 'Base', quente: 'Quente', aberto: 'Aberto' };
export const ROTULO_PROFISSAO: Record<Profissao, string> = { advogado: 'Advogado', contador: 'Contador', outros: 'Outros' };
export const NAO_INFORMADO = 'Não informado';
