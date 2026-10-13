'use client';

// Listas de disparo da Black (Fase 1): duas RPCs, com a sessão do usuário (só a chave anon pública vai ao navegador).
// - dados_black_listas_resumo: só contagens (cartões), para quem tem acesso ao dashboard.
// - dados_black_lista: a lista com dado pessoal, para "Ver" e "Baixar CSV"; exige também a capacidade contato.ver e
//   grava no servidor o log (quem, lista, segmento, linhas, quando) em dados.black_lista_downloads.
// Migration 20261013180931. Os mapeadores são puros e exportados para os testes.
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';
import type { ListaId, PessoaLista, Segmento, SituacaoGrupo } from '../domain/listas';

export interface ContagemLista { linhas: number; foraPadrao: number; semProfissao: number }
export interface ResumoListas {
  geradoEm: Date | null;
  ultimoDadoEm: Date | null;
  turmaEspecial: number;
  pessoas: number;
  /** chave `lista:segmento` */
  listas: Record<string, ContagemLista>;
}
export interface ListaLida { linhas: PessoaLista[]; foraPadrao: PessoaLista[]; turmaEspecial: number; geradoEm: Date | null }

type Obj = Record<string, unknown>;
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)) ? Number(v) : 0);
const txt = (v: unknown) => (typeof v === 'string' && v.trim() !== '' ? v : null);
const data = (v: unknown) => { const s = txt(v); const d = s ? new Date(s) : null; return d && !Number.isNaN(d.getTime()) ? d : null; };
const situacao = (v: unknown): SituacaoGrupo => (v === 'no_grupo' || v === 'saiu' ? v : 'nunca');

export function mapearResumo(cru: unknown): ResumoListas {
  const o = (cru && typeof cru === 'object' ? cru : {}) as Obj;
  const listas: Record<string, ContagemLista> = {};
  for (const [k, v] of Object.entries((o.listas && typeof o.listas === 'object' ? o.listas : {}) as Obj)) {
    const x = (v ?? {}) as Obj;
    listas[k] = { linhas: num(x.linhas), foraPadrao: num(x.fora_padrao), semProfissao: num(x.sem_profissao) };
  }
  return { geradoEm: data(o.gerado_em), ultimoDadoEm: data(o.ultimo_dado_em), turmaEspecial: num(o.turma_especial), pessoas: num(o.pessoas), listas };
}

export function mapearPessoa(cru: unknown): PessoaLista {
  const x = (cru ?? {}) as Obj;
  const seg = x.segmento === 'advogado' || x.segmento === 'contador' ? x.segmento : 'outros';
  return {
    nome: txt(x.nome), email: txt(x.email), telefone: txt(x.telefone), telefoneComoVeio: txt(x.telefone_como_veio), motivo: txt(x.motivo),
    segmento: seg, semProfissao: x.sem_profissao === true,
    grupoBlack: situacao(x.grupo_black), grupoConsultoria: situacao(x.grupo_consultoria),
    saiuBlackDe: txt(x.saiu_black_de), saiuConsultoriaDe: txt(x.saiu_consultoria_de),
    fontes: Array.isArray(x.fontes) ? x.fontes.filter((f): f is string => typeof f === 'string') : [],
  };
}

export function mapearLista(cru: unknown): ListaLida {
  const o = (cru && typeof cru === 'object' ? cru : {}) as Obj;
  const arr = (v: unknown) => (Array.isArray(v) ? v.map(mapearPessoa) : []);
  return { linhas: arr(o.linhas), foraPadrao: arr(o.fora_padrao), turmaEspecial: num(o.turma_especial), geradoEm: data(o.gerado_em) };
}

export function mensagemErro(code: string | undefined): string {
  if (code === '42501') return 'Seu usuário não tem permissão para ver os contatos das listas. Peça ao Victor a permissão "contato.ver".';
  if (code === 'P0002') return 'Dashboard não encontrado.';
  if (code === '22023') return 'Lista ou segmento inválido.';
  if (code === 'PGRST202' || code === '42883') return 'As listas ainda não estão ligadas no banco.';
  return 'Não foi possível ler a lista agora. Tente de novo.';
}

export async function lerResumoListas(chave: string): Promise<{ data: ResumoListas | null; erro: string | null }> {
  try {
    const { data, error } = await createBrowserSupabase().rpc('dados_black_listas_resumo', { p_chave: chave });
    if (error) {
      logQueryError('dados_black_listas_resumo', { message: error.code ?? 'erro' });
      // 42501 no resumo = sem acesso ao dashboard (não é falta de contato.ver)
      return { data: null, erro: error.code === '42501' ? 'Sem permissão para ler este dashboard.' : mensagemErro(error.code) };
    }
    return { data: mapearResumo(data), erro: null };
  } catch {
    logQueryError('dados_black_listas_resumo', { message: 'falha de conexão' });
    return { data: null, erro: 'Falha de conexão ao ler as listas.' };
  }
}

export async function lerLista(chave: string, lista: ListaId, segmento: Segmento, acao: 'ver' | 'baixar'): Promise<{ data: ListaLida | null; erro: string | null }> {
  try {
    const { data, error } = await createBrowserSupabase().rpc('dados_black_lista', { p_chave: chave, p_lista: lista, p_segmento: segmento, p_acao: acao });
    if (error) { logQueryError('dados_black_lista', { message: error.code ?? 'erro' }); return { data: null, erro: mensagemErro(error.code) }; }
    return { data: mapearLista(data), erro: null };
  } catch {
    logQueryError('dados_black_lista', { message: 'falha de conexão' });
    return { data: null, erro: 'Falha de conexão ao ler a lista.' };
  }
}
