'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { normalizarNumericos, type ResumoPresencial, type LeadPresencial, type VendaPresencial, type DisparoPresencial, type DiaPresencial } from '../domain/presencial';

export type Resultado<T> = { data: T | null; erro: string | null };

async function chamar<T>(nome: string, chave: string): Promise<Resultado<T>> {
  try {
    const { data, error } = await createBrowserSupabase().rpc(nome, { p_chave: chave });
    if (error) {
      logQueryError(nome, { message: error.code || 'SEM_CODIGO' });
      return { data: null, erro: mensagemErro(error.code) };
    }
    return { data: data as T, erro: null };
  } catch {
    logQueryError(nome, { message: 'NETWORK' });
    return { data: null, erro: mensagemErro() };
  }
}

export function mensagemErro(code?: string): string {
  if (code === '42501') return 'Você não tem acesso a este dashboard.';
  if (code === 'PGRST202') return 'Esta função ainda não está no banco. Avise quem cuida do sistema.';
  if (code === 'P0002') return 'Dashboard não cadastrado no banco.';
  return 'Não foi possível carregar agora.';
}

export async function carregarResumo(chave: string): Promise<Resultado<ResumoPresencial>> {
  const r = await chamar<ResumoPresencial[]>('dados_presencial_resumo', chave);
  return { ...r, data: r.data?.[0] ? normalizarNumericos(r.data[0], ['custo_disparo_centavos', 'custo_por_pre_checkout_centavos', 'conversao_pct', 'receita_bruta', 'receita_liquida', 'cac_centavos']) : null };
}
export const carregarLeads = (chave: string) => chamar<LeadPresencial[]>('dados_presencial_leads', chave);
export async function carregarVendas(chave: string): Promise<Resultado<VendaPresencial[]>> {
  const r = await chamar<VendaPresencial[]>('dados_presencial_vendas', chave);
  return { ...r, data: r.data?.map((v) => normalizarNumericos(v, ['valor_bruto', 'valor_liquido'])) ?? null };
}
export async function carregarDisparos(chave: string): Promise<Resultado<DisparoPresencial[]>> {
  const r = await chamar<DisparoPresencial[]>('dados_presencial_disparos', chave);
  return { ...r, data: r.data?.map((v) => normalizarNumericos(v, ['custo_centavos', 'entrega_pct', 'leitura_pct', 'clique_pct'])) ?? null };
}
export const carregarSerieDiaria = (chave: string) => chamar<DiaPresencial[]>('dados_presencial_serie_diaria', chave);
