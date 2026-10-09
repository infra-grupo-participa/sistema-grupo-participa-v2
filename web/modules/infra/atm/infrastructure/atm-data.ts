'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { dashboardAtmSemDado, type DashboardAtm, type LeadAtm, type NumeroGrupoAtm, type PeriodoAplicadoAtm } from '../domain/dashboard';
import type { DatasPeriodoAtm } from '../domain/periodo';

export type Resultado<T> = { data: T; semDado: boolean; erro: string | null };
export type ResultadoAcao = { data: number | null; erro: string | null };
export type DisparoDetalheAtm = {
  id: number | null;
  dataHora: string | null;
  enviadoEm: string | null;
  canal: 'whatsapp_api' | 'email' | 'sms' | 'ligacao' | 'grupo' | null;
  canalPago: boolean | null;
  tipo: string | null;
  ferramenta: string | null;
  numero: string | null;
  campanha: string | null;
  publicoLista: string | null;
  publicoOrigem: string | null;
  copyTexto: string | null;
  copyLink: string | null;
  enviados: number | null;
  entregues: number | null;
  lidas: number | null;
  cliques: number | null;
  falhas: number | null;
  custoCentavos: number | null;
  origem: string | null;
  retornoEm: string | null;
};
export type MetricaTrafegoAtm = {
  gastoCentavos: number | null;
  impressoes: number | null;
  alcance: number | null;
  frequencia: number | null;
  cliquesLink: number | null;
  cliquesTotal: number | null;
  cliquesSaida: number | null;
  landingPageViews: number | null;
  engajamento: number | null;
  videoPlays: number | null;
  videoThruplay: number | null;
  videoP25: number | null;
  videoP50: number | null;
  videoP75: number | null;
  videoP100: number | null;
  cpmCentavos: number | null;
  ctrPct: number | null;
  cpcCentavos: number | null;
};
export type DiaTrafegoAtm = MetricaTrafegoAtm & { dia: string | null };
export type CampanhaTrafegoAtm = {
  id: string | null;
  nome: string | null;
  status: string | null;
  objetivo: string | null;
  conta: string | null;
  gastoCentavos: number | null;
  primeiroDia: string | null;
  ultimoDia: string | null;
};
export type DadosTrafegoAtm = {
  periodoDe: string | null;
  periodoAte: string | null;
  moeda: string | null;
  coletadoEm: string | null;
  calculados: string[];
  total: MetricaTrafegoAtm & {
    alcanceMotivo: string | null;
    alcanceDe: string | null;
    alcanceAte: string | null;
    dias: number | null;
    primeiroDia: string | null;
    ultimoDia: string | null;
  };
  dias: DiaTrafegoAtm[];
  campanhas: CampanhaTrafegoAtm[];
};
type Linha = Record<string, unknown>;

function objeto(v: unknown): Linha | null {
  return typeof v === 'object' && v !== null && !Array.isArray(v) ? v as Linha : null;
}
function texto(v: unknown): string | null { return typeof v === 'string' ? v : null; }
function metricaTrafego(row: Linha): MetricaTrafegoAtm {
  return {
    gastoCentavos: num(row.gasto_centavos), impressoes: num(row.impressoes), alcance: num(row.alcance), frequencia: num(row.frequencia),
    cliquesLink: num(row.cliques_link), cliquesTotal: num(row.cliques_total), cliquesSaida: num(row.cliques_saida),
    landingPageViews: num(row.landing_page_views), engajamento: num(row.engajamento), videoPlays: num(row.video_plays),
    videoThruplay: num(row.video_thruplay), videoP25: num(row.video_p25), videoP50: num(row.video_p50), videoP75: num(row.video_p75),
    videoP100: num(row.video_p100), cpmCentavos: num(row.cpm_centavos), ctrPct: num(row.ctr_pct), cpcCentavos: num(row.cpc_centavos),
  };
}
export function trafegoAtmSemDado(): DadosTrafegoAtm {
  return {
    periodoDe: null, periodoAte: null, moeda: null, coletadoEm: null, calculados: [],
    total: { ...metricaTrafego({}), alcanceMotivo: null, alcanceDe: null, alcanceAte: null, dias: null, primeiroDia: null, ultimoDia: null },
    dias: [], campanhas: [],
  };
}

function num(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function booleano(v: unknown): boolean | null { return typeof v === 'boolean' ? v : null; }
function linhas(v: unknown): Linha[] {
  if (!Array.isArray(v)) return [];
  return v.filter((x): x is Linha => typeof x === 'object' && x !== null);
}

function mensagemLeitura(codigo?: string): string | null {
  if (codigo === 'PGRST202') return null;
  if (codigo === '42501') return 'Sem permissão para ler este dashboard.';
  if (codigo === 'P0002') return 'Dashboard ou identificador não encontrado neste evento.';
  if (codigo === '22023') return 'Período inválido ou acima do limite de 400 dias.';
  return 'Não foi possível carregar os dados agora.';
}

async function rpc(nome: string, chave: string, periodo?: DatasPeriodoAtm, adicionais: Record<string, unknown> = {}): Promise<Resultado<Linha[]>> {
  try {
    const argumentos: Record<string, unknown> = { p_chave: chave, ...adicionais };
    if (periodo) Object.assign(argumentos, periodo);
    const { data, error } = await createBrowserSupabase().rpc(nome, argumentos);
    if (error) {
      logQueryError(nome, { message: error.code || 'SEM_CODIGO' });
      return { data: [], semDado: error.code === 'PGRST202', erro: mensagemLeitura(error.code) };
    }
    return { data: linhas(data), semDado: false, erro: null };
  } catch {
    logQueryError(nome, { message: 'NETWORK' });
    return { data: [], semDado: true, erro: 'Falha de conexão ao carregar este bloco. Os últimos dados disponíveis foram mantidos.' };
  }
}

export async function carregarAtmResumo(chave: string, periodo?: DatasPeriodoAtm): Promise<Resultado<DashboardAtm>> {
  const r = await rpc('dados_atm_resumo', chave, periodo);
  const row = r.data[0];
  if (!row) return { data: dashboardAtmSemDado(chave), semDado: true, erro: r.erro };
  const base = dashboardAtmSemDado(chave);
  const valor = (key: string) => {
    const n = num(row[key]);
    return { valor: n ?? 0, semDado: n === null };
  };
  const valorCentavos = (key: string) => {
    const n = num(row[key]);
    return { valor: n === null ? 0 : n / 100, semDado: n === null };
  };
  const investimentoTotalCentavos = num(row.investimento_total_centavos);
  const metricaDependenteDoInvestimento = (key: string) => investimentoTotalCentavos === null
    ? { valor: 0, semDado: true }
    : valorCentavos(key);
  const periodoAplicado: PeriodoAplicadoAtm = {
    de: typeof row.periodo_de === 'string' ? row.periodo_de : null,
    ate: typeof row.periodo_ate === 'string' ? row.periodo_ate : null,
    leadsTeste: num(row.leads_teste),
    grupoTeste: num(row.grupo_teste),
    vendasTeste: num(row.vendas_teste),
    receitaTesteBruta: num(row.receita_teste_bruta),
  };
  return {
    data: {
      ...base,
      periodo: periodoAplicado,
      resumo: {
        custoTrafego: valorCentavos('custo_trafego_centavos'),
        investimentoTotal: valorCentavos('investimento_total_centavos'),
        disparos: valor('disparos_qtd'), leads: valor('leads'), ingressosGrupo: valor('grupo_entradas'),
        percentualIngressoGrupo: valor('grupo_pct'), taxaEvasao: valor('evasao_pct'),
        custoDisparo: valorCentavos('custo_disparo_centavos'),
        cpl: metricaDependenteDoInvestimento('cpl_centavos'),
        preCheckout: valor('pre_checkout_pessoas'), vendas: valor('vendas'),
        conversaoPreCheckout: valor('conversao_pre_checkout_pct'),
        cac: metricaDependenteDoInvestimento('cac_centavos'),
        faturamentoBruto: valor('receita_bruta'), faturamentoLiquido: valor('receita_liquida'),
        roas: metricaDependenteDoInvestimento('roas_liquido'),
      },
      semDado: false,
    },
    semDado: false,
    erro: r.erro,
  };
}

export async function carregarAtmSerie(chave: string, periodo?: DatasPeriodoAtm): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_serie_diaria', chave, periodo);
}

export async function carregarAtmLeads(chave: string, periodo?: DatasPeriodoAtm, incluirTeste = false): Promise<Resultado<LeadAtm[]>> {
  const r = await rpc('dados_atm_leads', chave, periodo, { p_incluir_teste: incluirTeste });
  return {
    data: r.data.map((x, i) => ({
      id: String(x.pessoa_id ?? x.email ?? x.telefone ?? i),
      pessoaId: typeof x.pessoa_id === 'string' ? x.pessoa_id : null,
      dataHora: typeof x.primeiro_em === 'string' ? x.primeiro_em : null,
      nome: typeof x.nome === 'string' ? x.nome : null,
      email: typeof x.email === 'string' ? x.email : null,
      telefone: typeof x.telefone === 'string' ? x.telefone : null,
      teste: x.teste === true,
      entrouGrupo: booleano(x.entrou_grupo),
      aluno: booleano(x.eh_aluno),
      instrucao: typeof x.instrucao === 'string' ? x.instrucao : null,
      turma: typeof x.turma === 'string' ? x.turma : null,
      utmSource: typeof x.utm_source === 'string' ? x.utm_source : null,
      estado: typeof x.estado === 'string' ? x.estado : null,
      listaOrigem: typeof x.lista_origem === 'string' ? x.lista_origem : null,
      seminarioOrigem: typeof x.seminario_origem === 'string' ? x.seminario_origem : null,
      noPreCheckout: booleano(x.no_pre_checkout),
      comprou: booleano(x.comprou),
    })),
    semDado: r.semDado,
    erro: r.erro,
  };
}

export async function carregarAtmGrupo(chave: string, periodo?: DatasPeriodoAtm, incluirTeste = false): Promise<Resultado<NumeroGrupoAtm[]>> {
  const r = await rpc('dados_atm_grupo_numeros', chave, periodo, { p_incluir_teste: incluirTeste });
  return {
    data: r.data.map((x) => ({
      foneKey: typeof x.fone_key === 'string' ? x.fone_key : '',
      nome: typeof x.nome === 'string' ? x.nome : null,
      entrouEm: typeof x.entrou_em === 'string' ? x.entrou_em : null,
      saiuEm: typeof x.saiu_em === 'string' ? x.saiu_em : null,
      noGrupo: booleano(x.no_grupo),
      ehLead: booleano(x.eh_lead),
      teste: x.teste === true,
      testeMotivo: typeof x.teste_motivo === 'string' ? x.teste_motivo : null,
    })),
    semDado: r.semDado,
    erro: r.erro,
  };
}

export async function marcarAtmTeste(chave: string, email: string | null, telefone: string | null): Promise<ResultadoAcao> {
  return chamarAcao('dados_marcar_teste', { p_chave: chave, p_email: email, p_telefone: telefone, p_motivo: 'teste' });
}

export async function desmarcarAtmTeste(chave: string, email: string | null, telefone: string | null): Promise<ResultadoAcao> {
  return chamarAcao('dados_desmarcar_teste', { p_chave: chave, p_email: email, p_telefone: telefone });
}

async function chamarAcao(nome: string, argumentos: Record<string, unknown>): Promise<ResultadoAcao> {
  try {
    const { data, error } = await createBrowserSupabase().rpc(nome, argumentos);
    if (error) {
      logQueryError(nome, { message: error.code || 'SEM_CODIGO' });
      return { data: null, erro: mensagemAcao(error.code) };
    }
    const n = num(data);
    return n === null ? { data: null, erro: 'O banco não confirmou a alteração.' } : { data: n, erro: null };
  } catch {
    logQueryError(nome, { message: 'NETWORK' });
    return { data: null, erro: 'Não foi possível concluir a marcação agora.' };
  }
}

function mensagemAcao(codigo?: string): string {
  if (codigo === '42501') return 'Seu usuário não tem permissão para marcar testes neste dashboard.';
  if (codigo === 'P0002') return 'E-mail ou telefone não encontrado neste evento. Atualize os dados e tente novamente.';
  if (codigo === '22023') return 'E-mail, telefone ou motivo inválido. Confira os dados e tente novamente.';
  if (codigo === 'PGRST202') return 'A marcação de teste ainda não está disponível no banco.';
  return 'Não foi possível alterar a marcação de teste agora.';
}

export async function carregarAtmCanais(chave: string, periodo?: DatasPeriodoAtm): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_disparos_canais', chave, periodo);
}
export async function carregarAtmDisparosLista(chave: string, periodo?: DatasPeriodoAtm): Promise<Resultado<DisparoDetalheAtm[]>> {
  const r = await rpc('dados_atm_disparos_lista', chave, periodo);
  return {
    data: r.data.map((x) => ({
      id: num(x.disparo_id),
      dataHora: typeof x.data_hora === 'string' ? x.data_hora : null,
      enviadoEm: typeof x.enviado_em === 'string' ? x.enviado_em : null,
      canal: x.canal === 'whatsapp_api' || x.canal === 'email' || x.canal === 'sms' || x.canal === 'ligacao' || x.canal === 'grupo' ? x.canal : null,
      canalPago: booleano(x.canal_pago),
      tipo: typeof x.tipo === 'string' ? x.tipo : null,
      ferramenta: typeof x.ferramenta === 'string' ? x.ferramenta : null,
      numero: typeof x.numero === 'string' ? x.numero : null,
      campanha: typeof x.campanha === 'string' ? x.campanha : null,
      publicoLista: typeof x.publico_lista === 'string' ? x.publico_lista : null,
      publicoOrigem: typeof x.publico_origem === 'string' ? x.publico_origem : null,
      copyTexto: typeof x.copy_texto === 'string' ? x.copy_texto : null,
      copyLink: typeof x.copy_link === 'string' ? x.copy_link : null,
      enviados: num(x.tamanho_lista),
      entregues: num(x.entregues),
      lidas: num(x.lidas),
      cliques: num(x.cliques),
      falhas: num(x.falhas),
      custoCentavos: num(x.custo_centavos),
      origem: typeof x.origem === 'string' ? x.origem : null,
      retornoEm: typeof x.retorno_em === 'string' ? x.retorno_em : null,
    })),
    semDado: r.semDado,
    erro: r.erro,
  };
}
export async function carregarAtmTrafego(chave: string, periodo?: DatasPeriodoAtm): Promise<Resultado<DadosTrafegoAtm>> {
  const nome = 'dados_atm_trafego';
  const vazio = trafegoAtmSemDado();
  try {
    const argumentos: Record<string, unknown> = { p_chave: chave };
    if (periodo) Object.assign(argumentos, periodo);
    const { data, error } = await createBrowserSupabase().rpc(nome, argumentos);
    if (error) {
      logQueryError(nome, { message: error.code || 'SEM_CODIGO' });
      return { data: vazio, semDado: true, erro: mensagemLeitura(error.code) };
    }
    const root = objeto(data);
    if (!root) return { data: vazio, semDado: true, erro: null };
    const totalRaw = objeto(root.total) ?? {};
    const diasRaw = Array.isArray(root.dias) ? root.dias.map(objeto).filter((row): row is Linha => row !== null) : [];
    const campanhasRaw = Array.isArray(root.campanhas) ? root.campanhas.map(objeto).filter((row): row is Linha => row !== null) : [];
    const total: DadosTrafegoAtm['total'] = {
      ...metricaTrafego(totalRaw),
      alcanceMotivo: texto(totalRaw.alcance_motivo),
      alcanceDe: texto(totalRaw.alcance_de),
      alcanceAte: texto(totalRaw.alcance_ate),
      dias: num(totalRaw.dias),
      primeiroDia: texto(totalRaw.primeiro_dia),
      ultimoDia: texto(totalRaw.ultimo_dia),
    };
    const dias: DiaTrafegoAtm[] = diasRaw.map((row) => ({ dia: texto(row.dia), ...metricaTrafego(row) }));
    const campanhas: CampanhaTrafegoAtm[] = campanhasRaw.map((row) => ({
      id: row.id == null ? null : String(row.id),
      nome: texto(row.nome),
      status: texto(row.status),
      objetivo: texto(row.objetivo),
      conta: texto(row.conta),
      gastoCentavos: num(row.gasto_centavos),
      primeiroDia: texto(row.primeiro_dia),
      ultimoDia: texto(row.ultimo_dia),
    }));
    return {
      data: {
        periodoDe: texto(root.periodo_de),
        periodoAte: texto(root.periodo_ate),
        moeda: texto(root.moeda),
        coletadoEm: texto(root.coletado_em),
        calculados: Array.isArray(root.calculados) ? root.calculados.filter((item): item is string => typeof item === 'string') : [],
        total,
        dias,
        campanhas,
      },
      semDado: false,
      erro: null,
    };
  } catch {
    logQueryError(nome, { message: 'NETWORK' });
    return { data: vazio, semDado: true, erro: 'Falha de conexão ao carregar este bloco. Os últimos dados disponíveis foram mantidos.' };
  }
}
export async function carregarAtmComparecimento(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_comparecimento', chave);
}
export async function carregarAtmPosLive(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_pos_live', chave);
}
