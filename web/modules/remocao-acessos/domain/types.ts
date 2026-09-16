// Tipos do módulo Remoção de Acessos. Espelham o JSON das funções ra_* do banco
// (migration 20260916_remocao_acessos.sql).

export type TipoCaso = 'reembolso' | 'chargeback' | 'disputa';
export type StatusCaso = 'alerta' | 'aguardando_triagem' | 'mantem_acesso' | 'em_remocao' | 'concluido';
export type SituacaoItem = 'pendente' | 'feito' | 'nao_se_aplica';
export type Recomendacao = 'remover' | 'verificar';

export interface MeuPapel {
  pode_ver: boolean;
  pode_triar: boolean;
  pode_configurar: boolean;
  meus_itens: string[];
}

export interface CasoFila {
  id: string;
  tipo: TipoCaso;
  status: StatusCaso;
  nome: string | null;
  email: string | null;
  documento: string | null;
  produto_nome: string | null;
  oferta_codigo: string | null;
  valor: number | null;
  hotmart_transaction: string;
  ocorrido_em: string;
  prazo_em: string | null;
  concluido_em: string | null;
  eh_programa: boolean;
  recomendacao: Recomendacao | null;
  pessoas: number;
  itens_total: number;
  itens_feitos: number;
  meus_pendentes: number;
}

export interface CompraAnterior {
  transacao: string;
  produto: string | null;
  oferta: string | null;
  valor: number | null;
  status: string;
  data: string | null;
}

export interface Sugestao {
  recomendacao?: Recomendacao;
  motivo?: string;
  compras_anteriores?: CompraAnterior[];
  aluno?: {
    instrucao: string | null;
    espaco: string | null;
    turma: string | null;
    data_expiracao: string | null;
    data_entrada_thb: string | null;
    status_central: string | null;
    eh_socio: boolean | null;
  } | null;
  historico_expiracao?: { de: string | null; para: string | null; origem: string | null; em: string }[];
  aviso?: string;
}

export interface ItemCaso {
  id: string;
  item: string;
  rotulo: string;
  situacao: SituacaoItem;
  responsavel: string | null;
  marcado_por: string | null;
  marcado_em: string | null;
  corrigido: boolean;
  obs: string | null;
  pode_marcar: boolean;
}

export interface PessoaCaso {
  id: string;
  nome: string | null;
  email: string | null;
  papel: 'titular' | 'socio';
  aluno_id: string | null;
  itens: ItemCaso[];
}

export interface EventoCaso {
  acao: string;
  em: string;
  por: string | null;
  detalhe: Record<string, unknown>;
}

export interface CasoDetalhe {
  caso: CasoFila & {
    telefone: string | null;
    sugestao: Sugestao;
    decisao_obs: string | null;
    triado_em: string | null;
    triado_por_nome: string | null;
    aluno_id: string | null;
  };
  pessoas: PessoaCaso[];
  historico: EventoCaso[];
  pode_triar: boolean;
}

export interface ItemCatalogo {
  item: string;
  rotulo: string;
  ordem: number;
  so_programa: boolean;
  ativo: boolean;
  responsavel_id: string | null;
  responsavel: string | null;
  email: string | null;
}

export interface Resultado {
  ok: boolean;
  msg: string;
}
