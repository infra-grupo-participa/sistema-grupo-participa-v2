'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { comTempoLimite, lerRpcDisparos, TEMPO_LIMITE_LISTAS_MS, traduzirDisparosLista, type DisparoDetalheAtm, type Linha, type Resultado as ResultadoAtm } from '@/modules/infra/atm/infrastructure/atm-data';
import { normalizarNumericos, type ResumoPresencial, type LeadPresencial, type VendaPresencial, type DiaPresencial, type PagamentoPresencial, type PerfilCompradorPresencial, type PendenciaPresencial, type PessoaPendenciaPresencial, type SerieVendasPresencial, type VendaHoraPresencial, type GrupoPendencia, type DiamantePresencial, type FichaInteresseMiami } from '../domain/presencial';

export type Resultado<T> = { data: T | null; erro: string | null };

async function chamar<T>(nome: string, chave: string, adicionais: Record<string, string> = {}): Promise<Resultado<T>> {
  try {
    const { data, error } = await createBrowserSupabase().rpc(nome, { p_chave: chave, ...adicionais });
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
  if (code === '22023') return 'Grupo de pendências inválido.';
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
/**
 * Visão de disparos igual à do Seminário ATM e à das Ações da Black: as RPCs `dados_presencial_disparos_canais` e
 * `dados_presencial_disparos_lista` devolvem as mesmas colunas de `dados_atm_disparos_canais` e `dados_atm_disparos_lista`
 * e só recebem `p_chave` (sem período). A leitura, os estados e a tradução são as do ATM.
 */
const MENSAGEM_TEMPO_DISPAROS = 'Os disparos demoraram a responder. Os últimos dados disponíveis foram mantidos.';
export const carregarDisparosCanais = (chave: string, limiteMs = TEMPO_LIMITE_LISTAS_MS): Promise<ResultadoAtm<Linha[]>> =>
  comTempoLimite('dados_presencial_disparos_canais', lerRpcDisparos('dados_presencial_disparos_canais', chave), limiteMs, MENSAGEM_TEMPO_DISPAROS);
export async function carregarDisparosLista(chave: string, limiteMs = TEMPO_LIMITE_LISTAS_MS): Promise<ResultadoAtm<DisparoDetalheAtm[]>> {
  const r = await comTempoLimite('dados_presencial_disparos_lista', lerRpcDisparos('dados_presencial_disparos_lista', chave), limiteMs, MENSAGEM_TEMPO_DISPAROS);
  return { data: traduzirDisparosLista(r.data), semDado: r.semDado, erro: r.erro };
}
export const carregarSerieDiaria = (chave: string) => chamar<DiaPresencial[]>('dados_presencial_serie_diaria', chave);
export async function carregarPagamentos(chave: string): Promise<Resultado<PagamentoPresencial[]>> {
  const r = await chamar<PagamentoPresencial[]>('dados_presencial_pagamentos', chave);
  return { ...r, data: r.data?.map((v) => normalizarNumericos(v, ['receita_bruta'])) ?? null };
}
export const carregarPerfilCompradores = (chave: string) => chamar<PerfilCompradorPresencial[]>('dados_presencial_compradores_perfil', chave);
export const carregarPendencias = (chave: string) => chamar<PendenciaPresencial[]>('dados_presencial_pendencias', chave);
export async function carregarPessoasPendencias(chave: string, grupo: GrupoPendencia): Promise<Resultado<PessoaPendenciaPresencial[]>> {
  const r = await chamar<PessoaPendenciaPresencial[]>('dados_presencial_pendencias_pessoas', chave, { p_grupo: grupo });
  return { ...r, data: r.data?.map((v) => normalizarNumericos(v, ['valor_bruto'])) ?? null };
}
export async function carregarSerieVendas(chave: string): Promise<Resultado<SerieVendasPresencial[]>> {
  const r = await chamar<SerieVendasPresencial[]>('dados_presencial_serie_vendas', chave);
  return { ...r, data: r.data?.map((v) => normalizarNumericos(v, ['receita_bruta', 'receita_acumulada', 'conversao_pct'])) ?? null };
}
export async function carregarVendasPorHora(chave: string): Promise<Resultado<VendaHoraPresencial[]>> {
  const r = await chamar<VendaHoraPresencial[]>('dados_presencial_vendas_por_hora', chave);
  return { ...r, data: r.data?.map((v) => normalizarNumericos(v, ['receita_bruta'])) ?? null };
}

export const carregarDiamantesMiami = (chave: string) => chamar<DiamantePresencial[]>('dados_miami_diamantes', chave);
export const carregarFichasInteresseMiami = (chave: string) => chamar<FichaInteresseMiami[]>('dados_miami_interesse', chave);

export async function marcarLeadTeste(chave: string, pessoaId: string, teste: boolean): Promise<Resultado<{ pessoa_id: string; teste: boolean; alterado: boolean }>> {
  try {
    const { data, error } = await createBrowserSupabase().rpc('dados_presencial_marcar_teste', { p_chave: chave, p_pessoa_id: pessoaId, p_teste: teste });
    if (error) {
      logQueryError('dados_presencial_marcar_teste', { message: error.code || 'SEM_CODIGO' });
      return { data: null, erro: mensagemErroTeste(error.code) };
    }
    const resultado = Array.isArray(data) ? data[0] : data;
    if (!resultado || resultado.pessoa_id !== pessoaId || resultado.teste !== teste || typeof resultado.alterado !== 'boolean') {
      return { data: null, erro: 'A resposta do banco não confirmou a alteração.' };
    }
    return { data: resultado as { pessoa_id: string; teste: boolean; alterado: boolean }, erro: null };
  } catch {
    logQueryError('dados_presencial_marcar_teste', { message: 'NETWORK' });
    return { data: null, erro: mensagemErroTeste() };
  }
}

export function mensagemErroTeste(code?: string): string {
  if (code === '42501') return 'Só masters podem marcar ou desmarcar leads como teste.';
  if (code === '22023') return 'Não foi possível validar a pessoa ou a marcação.';
  if (code === 'P0002') return 'Esta pessoa não está no pré-checkout deste dashboard.';
  if (code === 'PGRST202') return 'A marcação de teste ainda não está disponível no banco.';
  return 'Não foi possível alterar a marcação de teste agora.';
}
