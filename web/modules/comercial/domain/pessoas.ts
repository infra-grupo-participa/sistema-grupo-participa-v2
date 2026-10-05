// Comercial > base única de pessoas: o formato do que as funções public.pessoas_* devolvem (migration 20261005o).
// E-mail, telefone e documento já chegam MASCARADOS do banco para quem não pode ver (a tela só mostra).
import type { MotivoRevisao, Passo } from './identidade';

export type Situacao = 'ativa' | 'revisar' | 'mesclada';

export interface ItemBusca {
  tipo: 'pessoa' | 'aluno';
  /** null quando é aluno que ainda não está na base (tipo = 'aluno') */
  id: string | null;
  aluno_id?: string;
  ref?: string;
  nome: string | null;
  situacao: Situacao | null;
  teste: boolean;
  email: string | null;
  telefone: string | null;
  eh_aluno: boolean;
  eh_comprador: boolean;
  turma: string | null;
  projetos: string[];
  negocios_abertos: number;
  criado_em: string | null;
}

export interface Origem {
  id: number; quando: string; projeto_id: number | null; projeto: string | null; pagina_id: number | null; pagina: string | null;
  campanha: string | null; campanha_padrao: boolean | null; utm_source: string | null; utm_medium: string | null;
  utm_campaign: string | null; utm_content: string | null; utm_term: string | null; de_anuncio: boolean; fonte: string;
}

export type TipoEvento = 'lead' | 'mql' | 'nao_mql' | 'cadastro' | 'compra' | 'ativacao' | 'crm' | 'vinculo' | 'mescla' | 'revisao';

export interface Evento {
  id: number; tipo: TipoEvento; quando: string; projeto: string | null; fonte: string; ref_tipo: string | null; ref_id: string | null;
  detalhe: Record<string, unknown>; por: string | null;
}

export interface CompraRef { id: string; produto: string | null; status: string | null; data: string | null; preco: number | null }

export interface NegocioFicha {
  id: string; pipeline_id: number; pipeline: string; pipeline_tipo: string; etapa_id: number; etapa: string; etapa_tipo: string;
  status: 'aberto' | 'ganho' | 'perdido'; projeto: string | null; projeto_id: number | null; responsavel_id: string | null;
  responsavel: string | null; proximo_passo: string | null; proximo_passo_em: string | null; motivo_perda: string | null;
  criado_em: string; fechado_em: string | null;
}

export interface Ficha {
  pessoa: {
    id: string; ref: string; nome: string | null; situacao: Situacao; teste: boolean; criado_em: string; mesclada_de: string | null;
    email: string | null; telefone: string | null; documento: string | null;
  };
  aluno: { id: string; nome: string | null; turma: string | null; cancelado: boolean } | null;
  comprador_id: string | null;
  identificadores: { tipo: Passo; origem: string; criado_em: string; valor: string }[];
  origens: Origem[];
  eventos: Evento[];
  compras: CompraRef[];
  negocios: NegocioFicha[];
  revisoes: { id: number; motivo: MotivoRevisao; criado_em: string }[];
  permissoes: { pode_editar: boolean; pode_ver_doc: boolean; pode_ver_contato: boolean };
}

export interface RevisaoPendente {
  id: number;
  motivo: MotivoRevisao;
  criado_em: string;
  detalhe: { casou_por?: string | null; tipos?: string[] };
  pessoa: { id: string; nome: string | null; situacao: Situacao; eh_aluno: boolean; turma: string | null; criado_em: string };
  candidatos: { id: string; nome: string | null; eh_aluno: boolean; turma: string | null; situacao: Situacao }[];
}

export interface Resposta { ok: boolean; msg: string; id?: string; pessoa_id?: string; revisao?: string | null; codigo?: string }

export const ROTULO_EVENTO: Record<TipoEvento, string> = {
  lead: 'Entrou como lead',
  mql: 'Virou MQL',
  nao_mql: 'Não MQL',
  cadastro: 'Cadastrada no Comercial',
  compra: 'Compra',
  ativacao: 'Ativada',
  crm: 'CRM',
  vinculo: 'Ligada a aluno/comprador',
  mescla: 'Registro duplicado juntado',
  revisao: 'Revisão de identidade',
};

export const ROTULO_SITUACAO: Record<Situacao, string> = { ativa: 'Ativa', revisar: 'Em revisão', mesclada: 'Juntada a outra' };

export const ROTULO_IDENTIFICADOR: Record<Passo, string> = { documento: 'Documento', telefone: 'Telefone', email: 'E-mail', nome_cep: 'Nome + CEP' };

/** Como o histórico da ficha junta eventos próprios e compras lidas da Hotmart (referência), do mais novo ao mais antigo. */
export function linhaDoTempo(f: Pick<Ficha, 'eventos' | 'compras'>): { quando: string; titulo: string; detalhe: string | null; fonte: 'evento' | 'hotmart' }[] {
  const ev = f.eventos.map((e) => ({
    quando: e.quando,
    titulo: ROTULO_EVENTO[e.tipo] ?? e.tipo,
    detalhe: [e.projeto, typeof e.detalhe?.etapa === 'string' ? e.detalhe.etapa : null, typeof e.detalhe?.acao === 'string' ? e.detalhe.acao : null, e.por]
      .filter(Boolean).join(' · ') || null,
    fonte: 'evento' as const,
  }));
  const co = f.compras.filter((c) => c.data).map((c) => ({
    quando: c.data as string,
    titulo: 'Compra na Hotmart',
    detalhe: [c.produto, c.status].filter(Boolean).join(' · ') || null,
    fonte: 'hotmart' as const,
  }));
  return [...ev, ...co].sort((a, b) => (a.quando < b.quando ? 1 : a.quando > b.quando ? -1 : 0));
}
