// Nome de campanha no padrão da casa (Victor, 05/10/2026). Domínio puro: sem Next, sem Supabase.
//
//   GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA (opcional, só em teste de página)
//   ex.: RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1
//
// A MESMA regra existe no banco (mkt.campanha_traduzir, migration 20261005m). Mudou aqui, muda lá (e o contrário).
// As listas (gestores, objetivos, projetos) moram no banco (mkt.campanha_gestores, mkt.campanha_objetivos,
// mkt.projetos) e chegam por parâmetro: este arquivo não guarda cópia delas.

import { SIGLA_RE, CODIGO_PAGINA_RE } from './projetos';

export type ErroCampanha =
  | 'vazio'
  | 'numero_de_campos'
  | 'gestor_desconhecido'
  | 'sigla_invalida'
  | 'projeto_nao_cadastrado'
  | 'objetivo_desconhecido'
  | 'descricao_vazia'
  | 'pagina_invalida';

/** Avisos não tiram o nome do padrão: só dizem que ele não estava na forma canônica. */
export type AvisoCampanha = 'minusculas' | 'espacos_extras' | 'sem_acento';

export interface ListasCampanha {
  /** Iniciais dos gestores (CF, RS, EF). */
  gestores: string[];
  /** Objetivos na forma canônica (LEADS, DISTRIBUIÇÃO…). */
  objetivos: string[];
  /** Siglas cadastradas. Ausente = não confere se o projeto existe (só o formato). */
  projetos?: string[];
}

export interface CampanhaTraduzida {
  /** true = nenhum erro. "Fora do padrão" = false. */
  padrao: boolean;
  gestor: string | null;
  projeto: string | null;
  objetivo: string | null;
  descricao: string | null;
  /** Código da página em minúsculas (como em mkt.paginas.codigo), ou null se o nome tem 4 campos. */
  pagina: string | null;
  erros: ErroCampanha[];
  avisos: AvisoCampanha[];
  nomeCanonico: string | null;
}

export const ROTULO_ERRO: Record<ErroCampanha, string> = {
  vazio: 'Nome vazio',
  numero_de_campos: 'Precisa de 4 ou 5 campos separados por |',
  gestor_desconhecido: 'Gestor fora da lista',
  sigla_invalida: 'Sigla do projeto fora do formato (ex.: PB26)',
  projeto_nao_cadastrado: 'Projeto não cadastrado',
  objetivo_desconhecido: 'Objetivo fora da lista',
  descricao_vazia: 'Descrição vazia',
  pagina_invalida: 'Código de página fora do padrão (ex.: AK1, BL2, AK1-B)',
};

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase();
const limpa = (s: string) => s.replace(/\s+/g, ' ').trim();

export function traduzirCampanha(nome: string | null | undefined, listas: ListasCampanha): CampanhaTraduzida {
  const bruto = nome ?? '';
  const vazio = (erro: ErroCampanha): CampanhaTraduzida => ({
    padrao: false, gestor: null, projeto: null, objetivo: null, descricao: null, pagina: null,
    erros: [erro], avisos: [], nomeCanonico: null,
  });
  if (bruto.trim() === '') return vazio('vazio');

  const partes = bruto.split('|').map(limpa);
  if (partes.length !== 4 && partes.length !== 5) return vazio('numero_de_campos');

  const erros: ErroCampanha[] = [];
  const avisos: AvisoCampanha[] = [];
  const gestor = partes[0].toUpperCase();
  const projeto = partes[1].toUpperCase();
  let objetivo = partes[2].toUpperCase();
  const descricao = partes[3].toUpperCase();
  const pagina = partes.length === 5 ? partes[4].toLowerCase() : null;

  if (!listas.gestores.includes(gestor)) erros.push('gestor_desconhecido');

  if (!SIGLA_RE.test(projeto)) erros.push('sigla_invalida');
  else if (listas.projetos && !listas.projetos.includes(projeto)) erros.push('projeto_nao_cadastrado');

  const canon = listas.objetivos.find((o) => semAcento(o) === semAcento(objetivo));
  if (!canon) erros.push('objetivo_desconhecido');
  else {
    if (canon !== objetivo) avisos.push('sem_acento');
    objetivo = canon;
  }

  if (descricao === '') erros.push('descricao_vazia');
  if (pagina !== null && !CODIGO_PAGINA_RE.test(pagina)) erros.push('pagina_invalida');

  const nomeCanonico = [gestor, projeto, objetivo, descricao, ...(pagina !== null ? [pagina.toUpperCase()] : [])].join(' | ');
  if (bruto !== bruto.toUpperCase()) avisos.push('minusculas');
  if (semAcento(bruto) !== semAcento(nomeCanonico)) avisos.push('espacos_extras');

  return { padrao: erros.length === 0, gestor, projeto, objetivo, descricao, pagina, erros, avisos, nomeCanonico };
}
