'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { dashboardAtmSemDado, type DashboardAtm } from '../domain/dashboard';

export type Resultado<T> = { data: T; semDado: boolean; erro: string | null };
type Linha = Record<string, unknown>;

function num(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function metrica(v: unknown) {
  const valor = num(v);
  return { valor: valor ?? 0, semDado: valor === null || valor === 0 };
}
function linhas(v: unknown): Linha[] {
  if (!Array.isArray(v)) return [];
  return v.filter((x): x is Linha => typeof x === 'object' && x !== null);
}

async function rpc(nome: string, chave: string): Promise<Resultado<Linha[]>> {
  try {
    const { data, error } = await createBrowserSupabase().rpc(nome, { p_chave: chave });
    if (error) {
      // PGRST202: a RPC ainda não existe (migration do ATM não aplicada). É o estado "sem dado ainda", não erro.
      if (error.code === 'PGRST202') return { data: [], semDado: true, erro: null };
      logQueryError(nome, { message: error.code || 'SEM_CODIGO' });
      return { data: [], semDado: true, erro: error.code === '42501' ? 'Sem permissão para ler este dashboard.' : null };
    }
    return { data: linhas(data), semDado: false, erro: null };
  } catch {
    logQueryError(nome, { message: 'NETWORK' });
    return { data: [], semDado: true, erro: null };
  }
}

export async function carregarAtmResumo(chave: string): Promise<Resultado<DashboardAtm>> {
  const r = await rpc('dados_atm_resumo', chave);
  const row = r.data[0];
  if (!row) return { data: dashboardAtmSemDado(chave), semDado: true, erro: r.erro };
  const base = dashboardAtmSemDado(chave);
  const valor = (key: string) => metrica(row[key]);
  return {
    data: {
      ...base,
      resumo: {
        disparos: valor('disparos_qtd'), leads: valor('leads'), ingressosGrupo: valor('grupo_entradas'),
        percentualIngressoGrupo: valor('grupo_pct'), taxaEvasao: valor('evasao_pct'),
        custoDisparo: metrica(num(row.custo_disparo_centavos) === null ? null : Number(row.custo_disparo_centavos) / 100),
        cpl: metrica(num(row.cpl_centavos) === null ? null : Number(row.cpl_centavos) / 100),
        preCheckout: valor('pre_checkout_pessoas'), vendas: valor('vendas'),
        conversaoPreCheckout: valor('conversao_pre_checkout_pct'),
        cac: metrica(num(row.cac_centavos) === null ? null : Number(row.cac_centavos) / 100),
        faturamentoBruto: valor('receita_bruta'), faturamentoLiquido: valor('receita_liquida'), roas: valor('roas_liquido'),
      },
      semDado: r.semDado,
    },
    semDado: false,
    erro: r.erro,
  };
}

export async function carregarAtmSerie(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_serie_diaria', chave);
}
export async function carregarAtmLeads(chave: string): Promise<Resultado<DashboardAtm['leads']>> {
  const r = await rpc('dados_atm_leads', chave);
  return {
    data: r.data.map((x, i) => ({
      id: String(x.pessoa_id ?? x.email ?? x.telefone ?? i),
      dataHora: typeof x.primeiro_em === 'string' ? x.primeiro_em : null,
      nome: typeof x.nome === 'string' ? x.nome : null,
      email: typeof x.email === 'string' ? x.email : null,
      telefone: typeof x.telefone === 'string' ? x.telefone : null,
      entrouGrupo: typeof x.entrou_grupo === 'boolean' ? x.entrou_grupo : null,
      aluno: typeof x.eh_aluno === 'boolean' ? x.eh_aluno : null,
      utmSource: typeof x.utm_source === 'string' ? x.utm_source : null,
      estado: typeof x.estado === 'string' ? x.estado : null,
      listaOrigem: typeof x.lista_origem === 'string' ? x.lista_origem : null,
      seminarioOrigem: typeof x.seminario_origem === 'string' ? x.seminario_origem : null,
    })),
    semDado: r.semDado || r.data.length === 0,
    erro: r.erro,
  };
}
export async function carregarAtmCanais(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_disparos_canais', chave);
}
export async function carregarAtmComparecimento(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_comparecimento', chave);
}
export async function carregarAtmPosLive(chave: string): Promise<Resultado<Linha[]>> {
  return rpc('dados_atm_pos_live', chave);
}
