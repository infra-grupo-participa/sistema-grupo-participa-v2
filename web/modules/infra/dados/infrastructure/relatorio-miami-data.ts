'use client';

import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import { lerRespostaRelatorio, type RespostaRelatorioMiami } from '../domain/relatorio-miami';
import { mensagemErro, type Resultado } from './presencial-data';

export type ResultadoRelatorio = Resultado<RespostaRelatorioMiami> & { permanente: boolean };

export const TIMEOUT_RELATORIO_MS = 15_000;
// Falha que repetir não conserta (função fora do banco, sem acesso, dashboard não cadastrado): o polling para e só o botão Atualizar tenta de novo.
const CODIGOS_PERMANENTES = ['PGRST202', '42501', 'P0002'];

/** Uma chamada a public.dados_miami_relatorio. Com `md5` da cópia que a tela já tem, o banco responde `igual` sem reenviar o conteúdo. */
export async function carregarRelatorioMiami(chave: string, md5: string | null): Promise<ResultadoRelatorio> {
  try {
    const argumentos = md5 ? { p_chave: chave, p_md5: md5 } : { p_chave: chave };
    const { data, error } = await createBrowserSupabase().rpc('dados_miami_relatorio', argumentos).abortSignal(AbortSignal.timeout(TIMEOUT_RELATORIO_MS));
    if (error) {
      logQueryError('dados_miami_relatorio', { message: error.code || 'SEM_CODIGO' });
      return { data: null, erro: mensagemErro(error.code), permanente: CODIGOS_PERMANENTES.includes(error.code) };
    }
    const resposta = lerRespostaRelatorio(data);
    if (!resposta) {
      logQueryError('dados_miami_relatorio', { message: 'FORMATO' });
      return { data: null, erro: 'A resposta do banco veio em formato inesperado.', permanente: false };
    }
    return { data: resposta, erro: null, permanente: false };
  } catch {
    logQueryError('dados_miami_relatorio', { message: 'NETWORK' });
    return { data: null, erro: mensagemErro(), permanente: false };
  }
}
