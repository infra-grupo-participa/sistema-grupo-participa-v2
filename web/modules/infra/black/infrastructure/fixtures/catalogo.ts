// Catálogo FICTÍCIO do modo demonstração do dashboard da Black. Nada aqui é campanha, pessoa ou página real:
// gestor `ZZ` (não existe), descrição começando com FICTÍCIO, páginas em exemplo.test (domínio reservado).
// Os únicos números reais são os do CONFIG, cada um com a fonte ao lado.
import type { Campanha, ConfigBlack, Conjunto, Fase, Isca, ConjuntoC3, LinhaBlack, NoBlack, Pagina, Valor } from '../../domain/tipos';

export const CHAVE_BLACK = 'black-friday-2026-10';
const CONCEPCAO = 'CONCEPCAO-TRAFEGO-CAIO.md (cérebro do Victor, Projetos/dashboard-black-friday, DRE de 10/10/2026)';
const PUBLICOS = 'gp-operacoes/projetos/2026-10-black-friday/publicos.md (05/10/2026)';

/** Semanas segunda a domingo, PROVISÓRIO (BLOQUEIO 5 do plano: "semana do ciclo" sem datas oficiais). */
const SEMANAS = [
  { rotulo: 'Semana de 28/09 (provisório)', de: '2026-10-04', ate: '2026-10-04' },
  { rotulo: 'Semana de 05/10 (provisório)', de: '2026-10-05', ate: '2026-10-11' },
  { rotulo: 'Semana de 12/10 (provisório)', de: '2026-10-12', ate: '2026-10-18' },
  { rotulo: 'Semana de 19/10 (provisório)', de: '2026-10-19', ate: '2026-10-25' },
  { rotulo: 'Semana de 26/10 (provisório)', de: '2026-10-26', ate: '2026-11-01' },
  { rotulo: 'Semana de 02/11 (provisório)', de: '2026-11-02', ate: '2026-11-03' },
];

export const CONFIG_BLACK: ConfigBlack = {
  chave: CHAVE_BLACK,
  inicio: '2026-10-04', // primeiro dia dos fixtures (antecipação); data real do teaser não conferida
  inicioCaptacao: '2026-10-12', // CONCEPCAO: "15 mil leads em 23 dias (12/10 a 03/11)"
  liveEm: '2026-11-03T19:30:00-03:00', // CONCEPCAO: "O carrinho abre às 19h30" em 03/11 (Live do Método Perfeito)
  metaLeads: 15000, // CONCEPCAO: "pelo menos 15.000 leads na lista do Método Perfeito até 03/11"
  metaLeadsDia: 650, // CONCEPCAO: "cerca de 650 leads por dia"
  cplAlvoMedio: 16.7, // CONCEPCAO: "CPL médio precisa ficar em até R$ 16,70"
  reguaCpl: { meta: 15, teto: 20 }, // CONCEPCAO: "a régua da casa é meta de R$ 15 e teto de R$ 20"
  metas: { mql: 0.6, ingressoGrupo: 0.85, conversaoPagina: 0.2, connectRate: 0.85, ctr: 0.02, cpc: 3, cpm: 50 }, // Victor, 13/10/2026
  orcamentoTotal: 428571, // CONCEPCAO: "Verba de mídia: R$ 428.571"
  previstoPorFase: { // CONCEPCAO, tabela "Orçamento por fase"
    antecipacao: 17591, distribuicao: 47575, captacao: 220000, aquecimento: 26909, remarketing: 30000, live_carrinho: 70000,
  } satisfies Record<Fase, Valor>,
  reserva: 16496, // CONCEPCAO, linha "Reserva"
  baseDaCasa: 188013, // PUBLICOS, total das bases 0 a 9d (o fluxograma do Arthur arredonda para "cerca de 189 mil")
  semanas: SEMANAS,
  fontes: {
    plano: CONCEPCAO,
    publicos: PUBLICOS,
    trafego: 'FICTÍCIO: fixture do modo demonstração (gerador.ts, semente 20261103)',
    leads: 'FICTÍCIO: fixture do modo demonstração (gerador.ts, semente 20261103)',
    mensageria: 'FICTÍCIO: fixture do modo demonstração (não existe fonte real de disparo)',
    estado: 'Estado pelo DDD do telefone (espelho de dados.ddd_uf)',
  },
};

/** Sub-verbas da captação (CONCEPCAO, linhas "C2: iscas" e "C3: convite direto"). */
export const PREVISTO_CAPTACAO = { iscas: 70000, c3: 150000 } as const;

/** Bases do C3 base, com o rótulo EXATO de publicos.md (coluna "Base") e a temperatura da régua de 05/10. */
export const BASES_PUBLICOS: readonly { codigo: string; base: string; temperatura: string; pessoas: number }[] = [
  { codigo: '0', base: 'Superquente, alunos THB fora do Programa', temperatura: 'Superquente', pessoas: 770 },
  { codigo: '1', base: 'Ex-aluno (HM, Curso Prático, Aurum, Diamante)', temperatura: 'Quente', pessoas: 6715 },
  { codigo: '2', base: 'Leads Holding Masters', temperatura: 'Quente', pessoas: 3456 },
  { codigo: '3', base: 'Comprador Acelera', temperatura: 'Quente', pessoas: 290 },
  { codigo: '4', base: 'Pré-checkout Acelera', temperatura: 'Quente', pessoas: 1140 },
  { codigo: '5', base: 'Comprador de Holding Total e Imersão', temperatura: 'MQL', pessoas: 8352 },
  { codigo: '6', base: 'MQL do CNHF', temperatura: 'Lançamentos gratuitos', pessoas: 10951 },
  { codigo: '7', base: 'Leads do CNHF', temperatura: 'Lançamentos gratuitos', pessoas: 11153 },
  { codigo: '8', base: 'Leads do Holding Total', temperatura: 'Lançamentos gratuitos', pessoas: 22825 },
  { codigo: '9a', base: 'Lançamento gratuito, Holding Pro Acelerado', temperatura: 'Lançamentos gratuitos', pessoas: 10157 },
  { codigo: '9b', base: 'Lançamento gratuito, Jornada HF', temperatura: 'Lançamentos gratuitos', pessoas: 188 },
  { codigo: '9c', base: 'Lançamento gratuito, Curso Online de HF', temperatura: 'Lançamentos gratuitos', pessoas: 54476 },
  { codigo: '9d', base: 'Lançamento gratuito, Segredos HF', temperatura: 'Lançamentos gratuitos', pessoas: 57540 },
];

export const PAGINAS: readonly Pagina[] = [
  { id: 'pg-fluxograma', url: 'https://exemplo.test/isca-fluxograma', rotulo: 'FICTÍCIO isca Fluxograma', porta: 'isca', isca: 'Fluxograma' },
  { id: 'pg-checkup', url: 'https://exemplo.test/isca-checkup', rotulo: 'FICTÍCIO isca Checkup', porta: 'isca', isca: 'Checkup' },
  { id: 'pg-futurometro', url: 'https://exemplo.test/isca-futurometro', rotulo: 'FICTÍCIO isca Futurômetro', porta: 'isca', isca: 'Futurômetro' },
  { id: 'pg-consultoria', url: 'https://exemplo.test/aplicacao-consultoria', rotulo: 'FICTÍCIO aplicação da consultoria', porta: 'consultoria', isca: null },
  { id: 'pg-metodo', url: 'https://exemplo.test/metodo-perfeito', rotulo: 'FICTÍCIO inscrição Método Perfeito', porta: 'inscricao_direta', isca: null },
];

/** Plano de cada conjunto no gerador: período, gasto médio por dia e CPL-alvo (para as 3 cores do farol). */
export interface PlanoConjunto {
  conjunto: Conjunto; de: string; ate: string; gastoDia: number; cplAlvo: number | null;
  anuncios: { nome: string; formato: 'video' | 'imagem' | null }[]; paginaId: string | null;
}

/**
 * Classificação que a RPC dados_black_trafego devolve (contrato de 16/10/2026): `linha` por campanha e por conjunto, `no`
 * e `isca` por conjunto. Aqui é escrita à mão, no formato do banco, para a demonstração passar pelo mesmo caminho da tela.
 */
const LINHA_DA_CAMPANHA: Readonly<Record<string, LinhaBlack | null>> = {
  'cp-antecipacao': 'c1', 'cp-distribuicao': 'distribuicao', 'cp-manifesto': 'c1', 'cp-reels': 'distribuicao', 'cp-sem-etapa': null,
  'cp-consultoria': 'consultoria', 'cp-iscas': 'iscas', 'cp-c3': 'c3', 'cp-remarketing': 'remarketing_pagina',
  'cp-aquecimento': 'lembrete', 'cp-carrinho': 'carrinho', 'cp-google': 'c3',
};
const NO_DO_CONJUNTO: Readonly<Record<string, NoBlack | null>> = {
  'cj-teaser': 'teaser', 'cj-pf-aberto': 'reels_pago', 'cj-pf-interesses': 'reels_pago', 'cj-manifesto': 'manifesto', 'cj-reels': 'reels_pago',
  'cj-sem-etapa': null, 'cj-consultoria': 'consultoria', 'cj-fluxograma': 'iscas', 'cj-checkup': 'iscas', 'cj-futurometro': 'iscas',
  'cj-c3-base': 'c3', 'cj-c3-quente': 'c3', 'cj-c3-aberto': 'c3', 'cj-remarketing': 'remarketing_pagina', 'cj-aquecimento': 'lembrete',
  'cj-carrinho': 'carrinho', 'cj-google': 'c3',
};
const ISCA_DO_BANCO: Readonly<Record<Isca, string>> = { Fluxograma: 'FLUXOGRAMA', Checkup: 'CHECKUP', Futurômetro: 'FUTUROMETRO' };
const cj = (id: string, campanhaId: string, nome: string, isca: Isca | null = null, conjuntoC3: ConjuntoC3 | null = null): Conjunto =>
  ({
    id, campanhaId, nome, isca, conjuntoC3,
    linha: LINHA_DA_CAMPANHA[campanhaId] ?? null, no: NO_DO_CONJUNTO[id] ?? null,
    iscaBanco: isca ? ISCA_DO_BANCO[isca] : id === 'cj-consultoria' ? 'CONSULTORIA' : null,
  });
const videos = (prefixo: string, n: number) => Array.from({ length: n }, (_, i) => ({ nome: `${prefixo} ${String(i + 1).padStart(2, '0')}`, formato: 'video' as const }));

const CAMPANHAS_SEM_LINHA: readonly Campanha[] = [
  { id: 'cp-antecipacao', nome: 'ZZ | BF26 | ANTECIPAÇÃO | FICTÍCIO TEASER', canal: 'meta', funil: 'c1', fase: 'antecipacao', etapa: 'C1', subtipo: 'TEASER' },
  { id: 'cp-distribuicao', nome: 'ZZ | BF26 | DISTRIBUIÇÃO | FICTÍCIO C1 CORTES', canal: 'meta', funil: 'c1', fase: 'distribuicao', etapa: 'C1' },
  { id: 'cp-manifesto', nome: 'ZZ | BF26 | DISTRIBUIÇÃO | FICTÍCIO C1 MANIFESTO', canal: 'meta', funil: 'c1', fase: 'distribuicao', etapa: 'C1', subtipo: 'MANIFESTO' },
  { id: 'cp-reels', nome: 'ZZ | BF26 | DISTRIBUIÇÃO | FICTÍCIO C1 REELS', canal: 'meta', funil: 'c1', fase: 'distribuicao', etapa: 'C1', subtipo: 'REELS' },
  { id: 'cp-sem-etapa', nome: 'ZZ | BF26 | DISTRIBUIÇÃO | FICTÍCIO SEM ETAPA NO NOME', canal: 'meta', funil: null, fase: 'distribuicao', etapa: null, subtipo: null },
  { id: 'cp-consultoria', nome: 'ZZ | BF26 | LEADS | FICTÍCIO C2 CONSULTORIA', canal: 'meta', funil: 'consultoria', fase: 'captacao', etapa: 'C2', subtipo: 'CONSULTORIA' },
  { id: 'cp-iscas', nome: 'ZZ | BF26 | LEADS | FICTÍCIO C2 ISCAS', canal: 'meta', funil: 'iscas', fase: 'captacao', etapa: 'C2', subtipo: 'ISCA' },
  { id: 'cp-c3', nome: 'ZZ | BF26 | LEADS | FICTÍCIO C3 CONVITE', canal: 'meta', funil: 'c3', fase: 'captacao', etapa: 'C3', subtipo: 'LEADS' },
  { id: 'cp-remarketing', nome: 'ZZ | BF26 | REMARKETING | FICTÍCIO C2 C3', canal: 'meta', funil: 'c3', fase: 'remarketing' },
  { id: 'cp-aquecimento', nome: 'ZZ | BF26 | LEMBRETE | FICTÍCIO AQUECIMENTO INSCRITOS', canal: 'meta', funil: null, fase: 'aquecimento' },
  { id: 'cp-carrinho', nome: 'ZZ | BF26 | CARRINHO | FICTÍCIO CARRINHO', canal: 'meta', funil: null, fase: 'live_carrinho' },
  { id: 'cp-google', nome: 'ZZ | BF26 | LEADS | FICTÍCIO GOOGLE PESQUISA', canal: 'google', funil: 'c3', fase: 'captacao' },
];

export const CAMPANHAS: readonly Campanha[] = CAMPANHAS_SEM_LINHA.map((c) => ({ ...c, linha: LINHA_DA_CAMPANHA[c.id] ?? null }));

export const PLANOS: readonly PlanoConjunto[] = [
  { conjunto: cj('cj-teaser', 'cp-antecipacao', 'FICTÍCIO TEASER ABERTO'), de: '2026-10-04', ate: '2026-10-12', gastoDia: 1950, cplAlvo: null, anuncios: videos('FICTÍCIO TEASER', 2), paginaId: null },
  { conjunto: cj('cj-pf-aberto', 'cp-distribuicao', 'FICTÍCIO PF ABERTO'), de: '2026-10-12', ate: '2026-11-02', gastoDia: 800, cplAlvo: null, anuncios: videos('FICTÍCIO CORTE ABERTO', 3), paginaId: null },
  { conjunto: cj('cj-pf-interesses', 'cp-distribuicao', 'FICTÍCIO PF INTERESSES'), de: '2026-10-12', ate: '2026-11-02', gastoDia: 700, cplAlvo: null, anuncios: videos('FICTÍCIO CORTE INTERESSES', 3), paginaId: null },
  { conjunto: cj('cj-manifesto', 'cp-manifesto', 'FICTÍCIO MANIFESTO ABERTO'), de: '2026-10-12', ate: '2026-11-02', gastoDia: 450, cplAlvo: null, anuncios: videos('FICTÍCIO MANIFESTO ABERTO', 2), paginaId: null },
  { conjunto: cj('cj-reels', 'cp-reels', 'FICTÍCIO REELS ABERTO'), de: '2026-10-12', ate: '2026-11-02', gastoDia: 300, cplAlvo: null, anuncios: videos('FICTÍCIO REELS ABERTO', 2), paginaId: null },
  { conjunto: cj('cj-sem-etapa', 'cp-sem-etapa', 'FICTÍCIO SEM ETAPA'), de: '2026-10-12', ate: '2026-10-14', gastoDia: 100, cplAlvo: null, anuncios: videos('FICTÍCIO SEM ETAPA', 1), paginaId: null },
  { conjunto: cj('cj-consultoria', 'cp-consultoria', 'FICTÍCIO CONSULTORIA PÚBLICO AQUECIDO'), de: '2026-10-12', ate: '2026-11-02', gastoDia: 700, cplAlvo: 30, anuncios: videos('FICTÍCIO CONVITE CONSULTORIA', 3), paginaId: 'pg-consultoria' },
  { conjunto: cj('cj-fluxograma', 'cp-iscas', 'FICTÍCIO | FLUXOGRAMA', 'Fluxograma'), de: '2026-10-12', ate: '2026-11-02', gastoDia: 950, cplAlvo: 12, anuncios: videos('FICTÍCIO ISCA FLUXOGRAMA', 2), paginaId: 'pg-fluxograma' },
  { conjunto: cj('cj-checkup', 'cp-iscas', 'FICTÍCIO | CHECKUP', 'Checkup'), de: '2026-10-15', ate: '2026-11-02', gastoDia: 800, cplAlvo: 18, anuncios: videos('FICTÍCIO ISCA CHECKUP', 2), paginaId: 'pg-checkup' },
  { conjunto: cj('cj-futurometro', 'cp-iscas', 'FICTÍCIO | FUTUROMETRO', 'Futurômetro'), de: '2026-10-15', ate: '2026-11-02', gastoDia: 700, cplAlvo: 24, anuncios: videos('FICTÍCIO ISCA FUTURÔMETRO', 2), paginaId: 'pg-futurometro' },
  { conjunto: cj('cj-c3-base', 'cp-c3', 'FICTÍCIO BASE', null, 'base'), de: '2026-10-12', ate: '2026-11-03', gastoDia: 1500, cplAlvo: 9, anuncios: videos('FICTÍCIO CONVITE BASE', 2), paginaId: 'pg-metodo' },
  { conjunto: cj('cj-c3-quente', 'cp-c3', 'FICTÍCIO QUENTE', null, 'quente'), de: '2026-10-12', ate: '2026-11-03', gastoDia: 1400, cplAlvo: 14, anuncios: videos('FICTÍCIO CONVITE QUENTE', 2), paginaId: 'pg-metodo' },
  { conjunto: cj('cj-c3-aberto', 'cp-c3', 'FICTÍCIO ABERTO', null, 'aberto'), de: '2026-10-12', ate: '2026-11-03', gastoDia: 1300, cplAlvo: 22, anuncios: videos('FICTÍCIO CONVITE ABERTO', 2), paginaId: 'pg-metodo' },
  { conjunto: cj('cj-remarketing', 'cp-remarketing', 'FICTÍCIO VIU 50 A 75% SEM CADASTRO'), de: '2026-10-13', ate: '2026-11-02', gastoDia: 900, cplAlvo: 16, anuncios: videos('FICTÍCIO REMARKETING', 2), paginaId: 'pg-metodo' },
  { conjunto: cj('cj-aquecimento', 'cp-aquecimento', 'FICTÍCIO INSCRITOS E LEADS DE ISCA'), de: '2026-10-12', ate: '2026-11-03', gastoDia: 1050, cplAlvo: null, anuncios: videos('FICTÍCIO MANIFESTO', 2), paginaId: null },
  { conjunto: cj('cj-carrinho', 'cp-carrinho', 'FICTÍCIO LISTA DO MÉTODO PERFEITO'), de: '2026-11-03', ate: '2026-11-03', gastoDia: 9000, cplAlvo: null, anuncios: videos('FICTÍCIO CARRINHO', 1), paginaId: null },
  { conjunto: cj('cj-google', 'cp-google', 'FICTÍCIO PESQUISA MARCA'), de: '2026-10-12', ate: '2026-11-03', gastoDia: 0, cplAlvo: 20, // zerado: ainda não há campanha de Google (Victor, 12/10/2026)
    anuncios: [{ nome: 'FICTÍCIO ANÚNCIO DE PESQUISA 01', formato: null }, { nome: 'FICTÍCIO ANÚNCIO DE PESQUISA 02', formato: null }], paginaId: 'pg-metodo' },
];

/** Peso de cada UF nos leads fictícios (mais SP, RJ e MG, como pede o plano). Não é distribuição real. */
export const PESO_UF: Readonly<Record<string, number>> = {
  SP: 28, RJ: 14, MG: 11, PR: 6, RS: 6, SC: 4, BA: 5, DF: 3, GO: 3, PE: 3, CE: 2.5, ES: 2,
  PA: 1.5, MA: 1, MT: 1.2, MS: 1.2, PB: 1, RN: 1, AL: 0.8, PI: 0.8, SE: 0.7, AM: 1, TO: 0.5, RO: 0.5, AC: 0.3, AP: 0.3, RR: 0.3,
};
