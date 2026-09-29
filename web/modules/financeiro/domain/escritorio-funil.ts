// Funil do setor Escritório (Sessão de Viabilidade → Croqui → Holding Familiar), z92 (30/09/2026).
// Só tipos: a regra (atribuição a evento, entrada, conversão, estornos, máscara de telefone, visibilidade da conta
// Soluções) mora no SQL — fn_fin_escritorio_funil / fn_fin_escritorio_funil_pessoas. Contrato:
// infra/supabase/migrations/20260930z92.explain.md, seção "Contrato para o front".

/** evento = linha de fin.eventos (setor escritorio); os outros 3 são os baldes de id negativo (-3, -2, -1). */
export type TipoLinhaFunilEscritorio = 'evento' | 'perene' | 'croqui' | 'direto_hf';

export interface LinhaFunilEscritorio {
  /** id em fin.eventos; baldes: -3 Sessão sem evento, -2 entrou pelo Croqui, -1 entrou direto na HF. É o p_evento do drill-down. */
  evento_id: number;
  tipo: TipoLinhaFunilEscritorio;
  nome: string;
  categoria: string | null;
  inicio: string | null;
  fim: string | null;
  sessoes_vendas: number;
  sessoes_pessoas: number;
  sessoes_valor: number;
  sessoes_estornos: number;
  sessoes_estornos_valor: number;
  /** Pessoas cuja ENTRADA no funil é esta linha — denominador das %. Cada pessoa está em uma linha só. */
  pessoas: number;
  croqui_pessoas: number;
  croqui_pct: number | null;
  croqui_valor: number;
  hf_pessoas: number;
  hf_pct: number | null;
  hf_valor: number;
  mediana_dias_sessao_croqui: number | null;
  mediana_dias_croqui_hf: number | null;
  /** false = vendas da conta Hotmart do escritório (2025+) ainda não entram. Igual em todas as linhas. */
  escritorio_visivel: boolean;
}

export type EtapaEscritorio = 'sessao' | 'croqui' | 'hf';

export interface PessoaFunilEscritorio {
  evento_id: number;
  nome: string | null;
  email: string;
  /** Completo com gp_pode_ver_cpf(); senão '···' + 4 finais (mascarado no banco). */
  telefone: string | null;
  cidade: string | null;
  uf: string | null;
  entrada: EtapaEscritorio;
  etapa_alcancada: EtapaEscritorio;
  contas: string | null;
  sessao_em: string | null;
  sessao_valor: number | null;
  sessao_evento_origem: 'oferta' | 'janela' | 'perene' | null;
  croqui_em: string | null;
  croqui_valor: number | null;
  hf_em: string | null;
  hf_valor: number | null;
  dias_sessao_croqui: number | null;
  dias_croqui_hf: number | null;
}

/** Colunas que as RPCs devolvem — o teste de contrato confere contra o RETURNS TABLE da z92. */
export const COLUNAS_FUNIL_ESCRITORIO: readonly (keyof LinhaFunilEscritorio)[] = [
  'evento_id', 'tipo', 'nome', 'categoria', 'inicio', 'fim',
  'sessoes_vendas', 'sessoes_pessoas', 'sessoes_valor', 'sessoes_estornos', 'sessoes_estornos_valor',
  'pessoas', 'croqui_pessoas', 'croqui_pct', 'croqui_valor', 'hf_pessoas', 'hf_pct', 'hf_valor',
  'mediana_dias_sessao_croqui', 'mediana_dias_croqui_hf', 'escritorio_visivel',
];

export const COLUNAS_PESSOA_FUNIL_ESCRITORIO: readonly (keyof PessoaFunilEscritorio)[] = [
  'evento_id', 'nome', 'email', 'telefone', 'cidade', 'uf', 'entrada', 'etapa_alcancada', 'contas',
  'sessao_em', 'sessao_valor', 'sessao_evento_origem', 'croqui_em', 'croqui_valor', 'hf_em', 'hf_valor',
  'dias_sessao_croqui', 'dias_croqui_hf',
];
