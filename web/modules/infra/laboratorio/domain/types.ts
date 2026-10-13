// Modelo do Laboratório (schema lab, migration 20261013165350). Campos com o mesmo nome das colunas.
import type { Resultado } from './estatistica';

export type Nivel = 1 | 2 | 3;
export type Status = 'rascunho' | 'no_ar' | 'em_leitura' | 'concluido' | 'cancelado';
export type MetricaTipo = 'taxa' | 'custo';
export type Area = 'trafego' | 'comercial' | 'atendimento' | 'conteudo' | 'crm' | 'rh' | 'operacoes' | 'financeiro' | 'produto' | 'outro';

export const AREAS: { k: Area; l: string }[] = [
  { k: 'trafego', l: 'Tráfego' }, { k: 'comercial', l: 'Comercial' }, { k: 'atendimento', l: 'Atendimento' },
  { k: 'conteudo', l: 'Conteúdo' }, { k: 'crm', l: 'CRM / Mensageria' }, { k: 'rh', l: 'RH' },
  { k: 'operacoes', l: 'Operações' }, { k: 'financeiro', l: 'Financeiro' }, { k: 'produto', l: 'Produto' }, { k: 'outro', l: 'Outra' },
];
export const rotuloArea = (a: string) => AREAS.find((x) => x.k === a)?.l ?? a;

export const NIVEIS: Record<Nivel, { nome: string; quando: string }> = {
  1: { nome: 'Decisão registrada', quando: 'Decisão pequena, fácil de desfazer ou sem volume para testar. 5 minutos.' },
  2: { nome: 'Piloto com comparação', quando: 'Decisão relevante, mas não dá para sortear. Dá uma boa pista, não uma prova.' },
  3: { nome: 'Teste controlado', quando: 'Decisão relevante, com volume e sorteio possível. Prova causa e efeito.' },
};

export const STATUS: Record<Status, { l: string; tom: 'neutral' | 'info' | 'warning' | 'success' | 'danger' }> = {
  rascunho: { l: 'Rascunho', tom: 'neutral' },
  no_ar: { l: 'No ar', tom: 'info' },
  em_leitura: { l: 'Em leitura', tom: 'warning' },
  concluido: { l: 'Concluído', tom: 'success' },
  cancelado: { l: 'Cancelado', tom: 'danger' },
};

export interface LeituraSalva {
  id: string;
  em: string;
  a_n: number | null; a_x: number | null; b_n: number | null; b_x: number | null;
  medicao_ok: boolean;
  nota: string | null;
  calculo: Record<string, unknown>;
  classificacao: Resultado | null;
  lido_por_nome: string | null;
}

export interface Experimento {
  id: string;
  area: Area;
  nivel: Nivel;
  titulo: string;
  status: Status;
  decisao: string | null;
  hipotese: string | null;
  previsao: string | null;
  variavel: string | null;
  nao_muda: string | null;
  sorteio: string | null;
  metrica_tipo: MetricaTipo | null;
  metrica_decisao: string | null;
  metricas_diagnostico: string | null;
  taxa_base: number | null;
  regua: number | null;
  perguntas_regua: Partial<Record<'vale' | 'dados' | 'conta' | 'alavanca', string>>;
  amostra_minima: number | null;
  grupo_piloto: string | null;
  grupo_comparacao: string | null;
  medicao_antes: string | null;
  confundidores: string | null;
  alarme: string | null;
  decisao_combinada: Partial<Record<Resultado, string>>;
  controle_a: string | null;
  controle_b: string | null;
  inicio: string | null;
  leitura_em: string | null;
  revisao_em: string | null;
  clickup: string | null;
  monta_id: string | null; confere_id: string | null; le_id: string | null;
  monta_nome?: string | null; confere_nome?: string | null; le_nome?: string | null;
  revisao_bateu: 'sim' | 'nao' | 'nao_sabe' | null;
  resultado: Resultado | null;
  confianca: number | null;
  o_que_fizemos: string | null;
  aprendizado: string | null;
  concluido_em: string | null;
  mudancas: { em: string; campos: string[]; motivo: string }[];
  criado_por_nome: string | null;
  criado_em: string;
  pode_editar: boolean;
  n_leituras?: number;
  leituras?: LeituraSalva[];
}

export interface Pessoa { id: string; nome: string }

export interface Res { ok: boolean; msg: string; id?: string; faltando?: string[]; exige_motivo?: boolean }
