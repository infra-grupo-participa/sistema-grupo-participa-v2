// Comercial > CRM: tipos e regras puras (sem Next, sem Supabase). A regra de movimento é a mesma de
// crm.validar_movimento (migration 20261005o); o banco é quem decide, a tela usa esta para avisar antes.

export type TipoPipeline = 'ativacao' | 'vendas' | 'recuperacao_carrinho' | 'recuperacao_venda';
export type TipoEtapa = 'aberta' | 'ganho' | 'perdido';
export type StatusNegocio = 'aberto' | 'ganho' | 'perdido';

export const PIPELINES: TipoPipeline[] = ['ativacao', 'vendas', 'recuperacao_carrinho', 'recuperacao_venda'];

export interface Etapa { id: number; nome: string; ordem: number; tipo: TipoEtapa; ativa: boolean }
export interface Pipeline { id: number; tipo: TipoPipeline; nome: string; descricao: string | null; ativo: boolean; etapas: Etapa[] }
export interface MotivoPerda { id: number; pipeline_id: number | null; nome: string; ativo: boolean }
export interface Pessoal { id: string; nome: string }
export interface ProjetoRef { id: number; sigla: string; nome: string; ativo: boolean }
export interface Permissoes { pode_ver: boolean; pode_editar: boolean; pode_ver_doc: boolean; pode_ver_contato: boolean }

export interface ConfigCrm {
  pipelines: Pipeline[];
  motivos: MotivoPerda[];
  responsaveis: Pessoal[];
  projetos: ProjetoRef[];
  permissoes: Permissoes;
}

export interface Negocio {
  id: string;
  pipeline_id: number;
  etapa_id: number;
  status: StatusNegocio;
  pessoa_id: string;
  pessoa: string | null;
  eh_aluno: boolean;
  situacao_pessoa: 'ativa' | 'revisar' | 'mesclada';
  projeto_id: number | null;
  projeto: string | null;
  responsavel_id: string | null;
  responsavel: string | null;
  proximo_passo: string | null;
  proximo_passo_em: string | null;
  entrou_etapa_em: string;
  criado_em: string;
  fechado_em: string | null;
  motivo_perda: string | null;
  externo_tipo: string | null;
}

export type CodigoMovimento = 'mesma_etapa' | 'etapa_inativa' | 'reabrir_antes' | 'motivo_obrigatorio';

export const MSG_MOVIMENTO: Record<CodigoMovimento, string> = {
  mesma_etapa: 'O negócio já está nesta etapa.',
  etapa_inativa: 'Etapa desativada.',
  reabrir_antes: 'Negócio fechado: reabra (volte para uma etapa aberta) antes de fechar de novo.',
  motivo_obrigatorio: 'Informe o motivo da perda.',
};

/** null = pode mover. Mesma regra de crm.validar_movimento. */
export function validarMovimento(de: Pick<Etapa, 'id' | 'tipo'>, para: Pick<Etapa, 'id' | 'tipo' | 'ativa'>, temMotivo: boolean): CodigoMovimento | null {
  if (de.id === para.id) return 'mesma_etapa';
  if (!para.ativa) return 'etapa_inativa';
  if (de.tipo !== 'aberta' && para.tipo !== 'aberta') return 'reabrir_antes';
  if (para.tipo === 'perdido' && !temMotivo) return 'motivo_obrigatorio';
  return null;
}

export const statusDaEtapa = (t: TipoEtapa): StatusNegocio => (t === 'aberta' ? 'aberto' : t);

/** Para onde o negócio pode ir a partir da etapa atual (etapas ativas do pipeline, sem a atual). */
export function destinosPossiveis(etapas: Etapa[], atual: Etapa): Etapa[] {
  return etapas
    .filter((e) => e.ativa && e.id !== atual.id && (atual.tipo === 'aberta' || e.tipo === 'aberta'))
    .sort((a, b) => a.ordem - b.ordem || a.id - b.id);
}

/** Colunas do quadro: uma por etapa ativa (ou inativa que ainda tem negócio), na ordem. */
export function agruparPorEtapa(etapas: Etapa[], negocios: Negocio[]): { etapa: Etapa; itens: Negocio[] }[] {
  return [...etapas]
    .sort((a, b) => a.ordem - b.ordem || a.id - b.id)
    .map((etapa) => ({ etapa, itens: negocios.filter((n) => n.etapa_id === etapa.id) }))
    .filter((c) => c.etapa.ativa || c.itens.length > 0);
}

/** Próximo passo vencido (data antes de hoje) num negócio aberto. Datas em AAAA-MM-DD. */
export function passoAtrasado(n: Pick<Negocio, 'status' | 'proximo_passo_em'>, hojeISO: string): boolean {
  return n.status === 'aberto' && !!n.proximo_passo_em && n.proximo_passo_em < hojeISO;
}

export function filtrarNegocios(negocios: Negocio[], f: { projeto?: number | null; responsavel?: string | null; semResponsavel?: boolean }): Negocio[] {
  return negocios.filter((n) =>
    (f.projeto == null || n.projeto_id === f.projeto)
    && (f.semResponsavel ? n.responsavel_id == null : f.responsavel == null || n.responsavel_id === f.responsavel));
}
