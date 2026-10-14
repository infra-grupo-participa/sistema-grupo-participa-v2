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
// ETIQUETA NO FIM (decisão de 14/10/2026): toda campanha do Meta ganha " | <etiqueta-clickup>" no fim, ex.:
//   CF | BF26 | LEADS | ADVOGADOS | AK1 | black-friday-2026-10
// O último campo é a etiqueta quando é igual a uma etiqueta cadastrada (mkt.projetos.etiqueta_clickup, por parâmetro em
// `etiquetas`) ou tem o formato slug-AAAA-MM. Ela sai antes de ler a página e a descrição (que continuam iguais às do nome
// sem etiqueta) e volta em `etiqueta`. Banco: mkt.campanha_traduzir, migration 20261014190000.
//
// A MESMA regra existe no banco (mkt.campanha_traduzir, migration 20261006e, que trocou a da 20261005m). Mudou aqui,
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
  /** Etiquetas do ClickUp cadastradas (mkt.projetos.etiqueta_clickup). Ausente = só o formato slug-AAAA-MM. */
  etiquetas?: string[];
}

/** Formato da etiqueta do ClickUp no fim do nome: slug com o mês no fim (black-friday-2026-10, atm-elaine-1-2026-10). */
export const ETIQUETA_RE = /^[a-z0-9]+(-[a-z0-9]+)*-20[0-9]{2}-[0-9]{2}$/;

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
  /** Etiqueta do ClickUp lida no último campo (minúsculas), ou null. Não conta em `campos`. */
  etiqueta: string | null;
  /** Quantos campos (separados por |) o nome tem, sem a etiqueta. */
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

/**
 * Abreviações de objetivo vistas em campanhas reais e o objetivo do padrão que elas querem dizer. NÃO viram objetivo
 * válido (a campanha continua fora do padrão); só deixam o motivo claro. RMKT: campanhas do Seminário de setembro
 * (RS | SEMSET26 | RMKT | …), auditoria 06/10/2026. Aceitar RMKT como sinônimo é pergunta aberta ao Victor.
 */
export const OBJETIVO_PADRAO_DE: Record<string, string> = { RMKT: 'REMARKETING' };

/** O motivo exato de cada erro, com o que foi escrito (para a tela de campanhas fora do padrão). */
export function motivoErro(erro: string, c: { gestor?: string | null; projeto?: string | null; objetivo?: string | null; campos?: number | null }): string {
  switch (erro) {
    case 'gestor_desconhecido': return c.gestor ? `Gestor ${c.gestor} não está na lista` : 'Gestor vazio';
    case 'sigla_invalida': return c.projeto ? `Projeto ${c.projeto} fora do formato da sigla (ex.: PB26)` : 'Projeto vazio';
    case 'projeto_nao_cadastrado': return c.projeto ? `Projeto ${c.projeto} não cadastrado` : 'Projeto não cadastrado';
    case 'objetivo_desconhecido': {
      if (!c.objetivo) return 'Objetivo vazio';
      const padrao = OBJETIVO_PADRAO_DE[c.objetivo.toUpperCase()];
      return padrao ? `Objetivo ${c.objetivo} não está na lista; o padrão é ${padrao}` : `Objetivo ${c.objetivo} não está na lista`;
    }
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
  // utm_campaign no formato nome|id (gp-operacoes): o id da plataforma no fim não é parte do nome (igual ao banco, 20261006e)
  const semId = bruto.replace(/\|\s*[0-9]{6,}\s*$/, '');
  let partes = semId.split('|').map(limpa);
  // 20261014190000: etiqueta do ClickUp no último campo sai antes de ler página e descrição (igual ao banco)
  let etiqueta: string | null = null;
  let semEtiqueta = semId;
  const ultimoCampo = (partes[partes.length - 1] ?? '').toLowerCase();
  if (partes.length >= 4 && (ETIQUETA_RE.test(ultimoCampo) || (listas.etiquetas ?? []).some((e) => e.toLowerCase() === ultimoCampo))) {
    etiqueta = ultimoCampo;
    partes = partes.slice(0, -1);
    semEtiqueta = semId.replace(/\|[^|]*$/, '').trim();
  }
  const vazio = (erro: ErroCampanha, campos: number): CampanhaTraduzida => ({
    padrao: false, gestor: null, projeto: null, objetivo: null, descricao: null, descricaoPartes: [], pagina: null,
    etiqueta, campos, erros: [erro], avisos: [], nomeCanonico: null,
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

  const nomeBase = [gestor, projeto, objetivo, ...descricaoPartes, ...(pagina !== null ? [pagina.toUpperCase()] : [])].join(' | ');
  // avisos de forma olham o nome sem a etiqueta (a etiqueta é em minúsculas por padrão)
  if (semEtiqueta !== semEtiqueta.toUpperCase()) avisos.push('minusculas');
  if (semAcento(semEtiqueta) !== semAcento(nomeBase)) avisos.push('espacos_extras');
  const nomeCanonico = etiqueta !== null ? `${nomeBase} | ${etiqueta}` : nomeBase;

  return {
    padrao: erros.length === 0, gestor, projeto, objetivo, descricao, descricaoPartes, pagina, etiqueta, campos: partes.length,
    erros, avisos, nomeCanonico,
  };
}
