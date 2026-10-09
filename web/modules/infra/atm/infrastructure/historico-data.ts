'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { ordenarEdicoes, ROTULO_CAMPO_FONTE, type CampoFonteHistorico, type EdicaoHistorico } from '../domain/historico';
import type { Resultado } from './atm-data';

const RPC = 'dados_historico_edicoes';
export const TEMPO_LIMITE_HISTORICO_MS = 15_000;
const CAMPOS_FONTE = Object.keys(ROTULO_CAMPO_FONTE) as CampoFonteHistorico[];

function num(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
/** Centavos (bigint/numeric do banco) para reais. Ausente continua ausente. */
function reais(v: unknown): number | null {
  const n = num(v);
  return n === null ? null : n / 100;
}
function texto(v: unknown): string | null {
  return typeof v === 'string' && v.trim() !== '' ? v : null;
}

function fontes(v: unknown): EdicaoHistorico['fontes'] {
  if (typeof v !== 'object' || v === null || Array.isArray(v)) return {};
  const obj = v as Record<string, unknown>;
  const saida: EdicaoHistorico['fontes'] = {};
  for (const c of CAMPOS_FONTE) {
    const t = texto(obj[c]);
    if (t) saida[c] = t;
  }
  return saida;
}

function provisorio(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : [];
}

export function mapearEdicaoHistorico(x: Record<string, unknown>): EdicaoHistorico | null {
  const chave = texto(x.chave);
  if (!chave) return null;
  return {
    chave,
    familia: texto(x.familia) ?? '',
    rotulo: texto(x.rotulo) ?? chave,
    ordem: num(x.ordem),
    dataInicio: texto(x.data_inicio),
    dataFim: texto(x.data_fim),
    leads: num(x.leads),
    investTrafego: reais(x.invest_trafego_centavos),
    investDisparo: reais(x.invest_disparo_centavos),
    grupo: num(x.grupo),
    picoD1: num(x.pico_d1),
    picoD2: num(x.pico_d2),
    picoD3: num(x.pico_d3),
    vendas: num(x.vendas),
    receitaLiquida: reais(x.receita_liquida_centavos),
    preCheckout: num(x.pre_checkout),
    fontes: fontes(x.fontes),
    provisorio: provisorio(x.provisorio),
  };
}

function mensagem(codigo?: string): string | null {
  if (codigo === 'PGRST202') return null; // função ainda não existe no banco: "sem dado ainda", sem erro
  if (codigo === '42501') return 'Sem permissão para ler o histórico.';
  if (codigo === '22023') return 'Família de edições inválida.';
  return 'Não foi possível carregar o histórico agora.';
}

/** Lê as edições da família pela RPC, com tempo limite. Falha nunca devolve zero: devolve `semDado` e a mensagem. */
export async function carregarHistoricoEdicoes(familia: string): Promise<Resultado<EdicaoHistorico[]>> {
  try {
    const { data, error } = await createBrowserSupabase()
      .rpc(RPC, { p_familia: familia })
      .abortSignal(AbortSignal.timeout(TEMPO_LIMITE_HISTORICO_MS));
    if (error) {
      // Tempo limite: o supabase-js devolve code '' e a mensagem "TimeoutError: ..." ou "AbortError: ...".
      const codigo = error.code || (/abort|timeout/i.test(error.message ?? '') ? 'TIMEOUT' : 'SEM_CODIGO');
      logQueryError(RPC, { message: codigo });
      if (codigo === 'TIMEOUT') return { data: [], semDado: true, erro: 'O histórico demorou demais para responder. Os últimos dados foram mantidos.' };
      return { data: [], semDado: true, erro: mensagem(error.code) };
    }
    const linhas = Array.isArray(data) ? data.filter((x): x is Record<string, unknown> => typeof x === 'object' && x !== null) : [];
    const edicoes = linhas.map(mapearEdicaoHistorico).filter((e): e is EdicaoHistorico => e !== null);
    return { data: ordenarEdicoes(edicoes), semDado: edicoes.length === 0, erro: null };
  } catch {
    logQueryError(RPC, { message: 'NETWORK' });
    return { data: [], semDado: true, erro: 'Falha de conexão ao carregar o histórico. Os últimos dados foram mantidos.' };
  }
}
