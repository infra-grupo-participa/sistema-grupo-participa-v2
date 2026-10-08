export type MetricaAtm = { valor: number; semDado: boolean };
export type CampoResumoLeadAtm = 'entrou_grupo' | 'aluno' | 'utm_source' | 'estado' | 'lista_origem' | 'seminario_origem';
export type CanalDisparoAtm = 'api' | 'grupo' | 'sms' | 'ligacao' | 'email';

export const CAMPOS_RESUMO_LEAD_ATM: { campo: CampoResumoLeadAtm; rotulo: string }[] = [
  { campo: 'entrou_grupo', rotulo: 'Entrou no grupo?' },
  { campo: 'aluno', rotulo: 'É aluno?' },
  { campo: 'utm_source', rotulo: 'utm_source' },
  { campo: 'estado', rotulo: 'Estado' },
  { campo: 'lista_origem', rotulo: 'Lista de origem' },
  { campo: 'seminario_origem', rotulo: 'Seminário de origem' },
];

export const CANAIS_DISPARO_ATM: { canal: CanalDisparoAtm; rotulo: string }[] = [
  { canal: 'api', rotulo: 'API' },
  { canal: 'grupo', rotulo: 'Grupo' },
  { canal: 'sms', rotulo: 'SMS' },
  { canal: 'ligacao', rotulo: 'Ligação' },
  { canal: 'email', rotulo: 'E-mail' },
];

export const METRICAS_RESUMO_ATM: { chave: keyof ResumoAtm; rotulo: string; formato: 'inteiro' | 'percentual' | 'moeda' | 'multiplicador' }[] = [
  { chave: 'disparos', rotulo: 'Disparos', formato: 'inteiro' },
  { chave: 'leads', rotulo: 'Leads', formato: 'inteiro' },
  { chave: 'ingressosGrupo', rotulo: 'Ingresso no grupo', formato: 'inteiro' },
  { chave: 'percentualIngressoGrupo', rotulo: '% ingresso no grupo', formato: 'percentual' },
  { chave: 'taxaEvasao', rotulo: 'Taxa de evasão', formato: 'percentual' },
  { chave: 'custoDisparo', rotulo: 'Custo com disparo', formato: 'moeda' },
  { chave: 'cpl', rotulo: 'CPL', formato: 'moeda' },
  { chave: 'preCheckout', rotulo: 'PRÉ-CHECKOUT', formato: 'inteiro' },
  { chave: 'vendas', rotulo: 'Vendas', formato: 'inteiro' },
  { chave: 'conversaoPreCheckout', rotulo: 'TAXA DE CONVERSÃO DO PRÉ-CHECKOUT', formato: 'percentual' },
  { chave: 'cac', rotulo: 'CAC', formato: 'moeda' },
  { chave: 'faturamentoBruto', rotulo: 'Faturamento bruto', formato: 'moeda' },
  { chave: 'faturamentoLiquido', rotulo: 'Faturamento líquido', formato: 'moeda' },
  { chave: 'roas', rotulo: 'ROAS', formato: 'multiplicador' },
];

export type ResumoAtm = {
  disparos: MetricaAtm;
  leads: MetricaAtm;
  ingressosGrupo: MetricaAtm;
  percentualIngressoGrupo: MetricaAtm;
  taxaEvasao: MetricaAtm;
  custoDisparo: MetricaAtm;
  cpl: MetricaAtm;
  preCheckout: MetricaAtm;
  vendas: MetricaAtm;
  conversaoPreCheckout: MetricaAtm;
  cac: MetricaAtm;
  faturamentoBruto: MetricaAtm;
  faturamentoLiquido: MetricaAtm;
  roas: MetricaAtm;
};

export type LeadAtm = {
  id: string;
  dataHora: string | null;
  nome: string | null;
  email: string | null;
  telefone: string | null;
  entrouGrupo: boolean | null;
  aluno: boolean | null;
  utmSource: string | null;
  estado: string | null;
  listaOrigem: string | null;
  seminarioOrigem: string | null;
};

export type SerieLeadsAtm = { dia: string; leads: number };
export type DistribuicaoLeadAtm = { campo: CampoResumoLeadAtm; valor: string; quantidade: number };
export type LinhaDisparoAtm = { dia: string | null; nome: string; status: string | null; enviados: MetricaAtm; entregues: MetricaAtm; abertos: MetricaAtm; cliques: MetricaAtm; falhas: MetricaAtm; custo: MetricaAtm };
export type CanalAtm = { resumo: MetricaAtm[]; linhas: LinhaDisparoAtm[]; semDado: boolean };
export type ComparecimentoAtm = {
  picoAudiencia: MetricaAtm;
  comparecimentoGrupo: MetricaAtm;
  comparecimentoLeads: MetricaAtm;
  totalLeads: MetricaAtm;
  totalGrupo: MetricaAtm;
  equipeNaSala: MetricaAtm;
  vendas: MetricaAtm;
  conversao: MetricaAtm;
  conversaoGrupo: MetricaAtm;
  conversaoPico: MetricaAtm;
};
export type CicloPosLiveAtm = { vendas: MetricaAtm; conversao: MetricaAtm };

export type DashboardAtm = {
  chave: string;
  resumo: ResumoAtm;
  leadsPorDia: SerieLeadsAtm[];
  leads: LeadAtm[];
  distribuicaoLeads: DistribuicaoLeadAtm[];
  disparos: Record<CanalDisparoAtm, CanalAtm>;
  comparecimento: ComparecimentoAtm;
  ciclosPosLive: { aberto: CicloPosLiveAtm; fechado: CicloPosLiveAtm };
  semDado: boolean;
};

const zero = (): MetricaAtm => ({ valor: 0, semDado: true });

export function dashboardAtmSemDado(chave: string): DashboardAtm {
  return {
    chave,
    resumo: {
      disparos: zero(), leads: zero(), ingressosGrupo: zero(), percentualIngressoGrupo: zero(), taxaEvasao: zero(),
      custoDisparo: zero(), cpl: zero(), preCheckout: zero(), vendas: zero(), conversaoPreCheckout: zero(), cac: zero(),
      faturamentoBruto: zero(), faturamentoLiquido: zero(), roas: zero(),
    },
    leadsPorDia: [],
    leads: [],
    distribuicaoLeads: [],
    disparos: {
      api: { resumo: [], linhas: [], semDado: true }, grupo: { resumo: [], linhas: [], semDado: true },
      sms: { resumo: [], linhas: [], semDado: true }, ligacao: { resumo: [], linhas: [], semDado: true },
      email: { resumo: [], linhas: [], semDado: true },
    },
    comparecimento: {
      picoAudiencia: zero(), comparecimentoGrupo: zero(), comparecimentoLeads: zero(), totalLeads: zero(), totalGrupo: zero(),
      equipeNaSala: zero(), vendas: zero(), conversao: zero(), conversaoGrupo: zero(), conversaoPico: zero(),
    },
    ciclosPosLive: { aberto: { vendas: zero(), conversao: zero() }, fechado: { vendas: zero(), conversao: zero() } },
    semDado: true,
  };
}
