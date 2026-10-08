'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { dashboardAtmSemDado, type DashboardAtm, type LeadAtm, type NumeroGrupoAtm, type PeriodoAplicadoAtm } from '../domain/dashboard';
import type { DatasPeriodoAtm } from '../domain/periodo';

export type Resultado<T> = { data: T; semDado: boolean; erro: string | null };
export type ResultadoAcao = { data: number | null; erro: string | null };
type Linha = Record<string, unknown>;

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
        disparos: valor('disparos_qtd'), leads: valor('leads'), ingressosGrupo: valor('grupo_entradas'),
        percentualIngressoGrupo: valor('grupo_pct'), taxaEvasao: valor('evasao_pct'),
        custoDisparo: valorCentavos('custo_disparo_centavos'),
        cpl: valorCentavos('cpl_centavos'),
        preCheckout: valor('pre_checkout_pessoas'), vendas: valor('vendas'),
        conversaoPreCheckout: valor('conversao_pre_checkout_pct'),
        cac: valorCentavos('cac_centavos'),
        faturamentoBruto: valor('receita_bruta'), faturamentoLiquido: valor('receita_liquida'), roas: valor('roas_liquido'),
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
export async function carregarAtmComparecimento(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_comparecimento', chave);
}
export async function carregarAtmPosLive(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_pos_live', chave);
}
