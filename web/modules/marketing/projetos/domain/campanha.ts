// Nome de campanha no padrão da casa (Victor, 05/10/2026; revisão de 06/10/2026). Domínio puro: sem Next, sem Supabase.
//
//   GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA (opcional, só em teste de página)
//   ex.: RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1
//        CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY   (descrição de várias partes, sem página)
//
// A DESCRIÇÃO é tudo o que vem depois do OBJETIVO e pode ter várias partes separadas por " | ". A PÁGINA só é lida no
// ÚLTIMO campo, com pelo menos uma parte de descrição antes, e só no formato do slug da casa (ak1, bl2, jt10, ak1-b);
// senão o último campo é parte da descrição.
//
// A MESMA regra existe no banco (mkt.campanha_traduzir, migration 20261006c, que trocou a da 20261005m). Mudou aqui,
// muda lá (e o contrário). As listas (gestores, objetivos, projetos) moram no banco (mkt.campanha_gestores,
// mkt.campanha_objetivos, mkt.projetos) e chegam por parâmetro: este arquivo não guarda cópia delas.

import { SIGLA_RE, CODIGO_PAGINA_RE } from './projetos';

export type ErroCampanha =
  | 'vazio'
  | 'numero_de_campos'
  | 'gestor_desconhecido'
  | 'sigla_invalida'
  | 'projeto_nao_cadastrado'
  | 'objetivo_desconhecido'
  | 'descricao_vazia'
  | 'campo_vazio';

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
  /** Tudo depois do objetivo (sem a página), as partes juntadas por " | ". */
  descricao: string | null;
  descricaoPartes: string[];
  /** Código da página em minúsculas (como em mkt.paginas.codigo), ou null sem página. */
  pagina: string | null;
  /** Quantos campos (separados por |) o nome tem. */
  campos: number;
  erros: ErroCampanha[];
  avisos: AvisoCampanha[];
  nomeCanonico: string | null;
}

export const ROTULO_ERRO: Record<ErroCampanha, string> = {
  vazio: 'Nome vazio',
  numero_de_campos: 'Menos de 3 campos separados por |',
  gestor_desconhecido: 'Gestor fora da lista',
  sigla_invalida: 'Sigla do projeto fora do formato (ex.: PB26)',
  projeto_nao_cadastrado: 'Projeto não cadastrado',
  objetivo_desconhecido: 'Objetivo fora da lista',
  descricao_vazia: 'Sem descrição',
  campo_vazio: 'Campo vazio entre | (ex.: "| |")',
};

/** O motivo exato de cada erro, com o que foi escrito (para a tela de campanhas fora do padrão). */
export function motivoErro(erro: string, c: { gestor?: string | null; projeto?: string | null; objetivo?: string | null; campos?: number | null }): string {
  switch (erro) {
    case 'gestor_desconhecido': return c.gestor ? `Gestor ${c.gestor} não está na lista` : 'Gestor vazio';
    case 'sigla_invalida': return c.projeto ? `Projeto ${c.projeto} fora do formato da sigla (ex.: PB26)` : 'Projeto vazio';
    case 'projeto_nao_cadastrado': return c.projeto ? `Projeto ${c.projeto} não cadastrado` : 'Projeto não cadastrado';
    case 'objetivo_desconhecido': return c.objetivo ? `Objetivo ${c.objetivo} não está na lista` : 'Objetivo vazio';
    case 'numero_de_campos': return c.campos != null ? `Menos de 3 campos (tem ${c.campos})` : ROTULO_ERRO.numero_de_campos;
    case 'descricao_vazia': return 'Sem descrição (só gestor, projeto e objetivo)';
    case 'pagina_invalida': return 'Código de página fora do padrão (leitura antiga)';
    default: return ROTULO_ERRO[erro as ErroCampanha] ?? erro;
  }
}

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase();
const limpa = (s: string) => s.replace(/\s+/g, ' ').trim();

const SLUG_PAGINA = CODIGO_PAGINA_RE;

export function traduzirCampanha(nome: string | null | undefined, listas: ListasCampanha): CampanhaTraduzida {
  const bruto = nome ?? '';
  const partes = bruto.split('|').map(limpa);
  const vazio = (erro: ErroCampanha, campos: number): CampanhaTraduzida => ({
    padrao: false, gestor: null, projeto: null, objetivo: null, descricao: null, descricaoPartes: [], pagina: null, campos,
    erros: [erro], avisos: [], nomeCanonico: null,
  });
  if (bruto.trim() === '') return vazio('vazio', 0);
  if (partes.length < 3) return vazio('numero_de_campos', partes.length);

  const erros: ErroCampanha[] = [];
  const avisos: AvisoCampanha[] = [];
  const gestor = partes[0].toUpperCase();
  const projeto = partes[1].toUpperCase();
  let objetivo = partes[2].toUpperCase();
  const ultimo = partes[partes.length - 1].toLowerCase();
  const temPagina = partes.length >= 5 && SLUG_PAGINA.test(ultimo);
  const pagina = temPagina ? ultimo : null;
  const descricaoPartes = partes.slice(3, temPagina ? -1 : undefined).map((x) => x.toUpperCase());
  const descricao = descricaoPartes.join(' | ');

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
  else if (descricaoPartes.includes('')) erros.push('campo_vazio');

  const nomeCanonico = [gestor, projeto, objetivo, ...descricaoPartes, ...(pagina !== null ? [pagina.toUpperCase()] : [])].join(' | ');
  if (bruto !== bruto.toUpperCase()) avisos.push('minusculas');
  if (semAcento(bruto) !== semAcento(nomeCanonico)) avisos.push('espacos_extras');

  return {
    padrao: erros.length === 0, gestor, projeto, objetivo, descricao, descricaoPartes, pagina, campos: partes.length, erros, avisos, nomeCanonico,
  };
}
