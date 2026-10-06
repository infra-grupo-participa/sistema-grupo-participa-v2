// Marketing > Tráfego: tipos do que as funções public.trafego_* devolvem (migration 20261005p). Domínio puro.

export type Subarea = 'interno' | 'aurum' | 'diamante';
export type Tipo = 'interno' | 'externo';
export type Dono = 'grupo' | 'diamante' | 'aurum';

export const ROTULO_SUBAREA: Record<Subarea, string> = { interno: 'Interno', aurum: 'Aurum', diamante: 'Diamantes' };
export const ROTULO_TIPO: Record<Tipo, string> = { interno: 'Interno', externo: 'Externo' };
export const ROTULO_DONO: Record<Dono, string> = { grupo: 'Grupo Participa', diamante: 'Diamante', aurum: 'Aluno Aurum' };
export const DONOS: Dono[] = ['grupo', 'diamante', 'aurum'];

export interface Codigo { codigo: string; nome: string }

export interface ConfigTrafego {
  plataformas: Codigo[];
  status: Codigo[];
  fases: Codigo[];
  gestores: { sigla: string; nome: string }[];
  /** true = a base de pessoas (20261005o) existe e os leads da Central vêm dela. */
  base_pessoas: boolean;
  /** true = a Web (20261005n) existe e as page views vêm dela. */
  base_web: boolean;
  /** Objetivo do nome de campanha → fase (mkt_trafego.objetivo_fase). Objetivo ausente = sem fase automática. */
  objetivo_fase: Record<string, string>;
  /** Último dia completo (São Paulo), AAAA-MM-DD. */
  dia_ontem: string;
}

/** Uma linha da Central do Tráfego (mkt_trafego.resumo). Nulo = sem fonte ou sem dado, nunca zero inventado. */
export interface LinhaResumo {
  projeto_id: number;
  sigla: string;
  nome: string;
  subarea: Subarea | null;
  tipo: Tipo | null;
  projeto_ativo: boolean;
  etiqueta_clickup: string | null;
  inicio: string | null;
  fim: string | null;
  status: string | null;
  status_nome: string | null;
  /** Gestores do projeto (vários; marcados à mão). */
  gestores: string[];
  /** Gestores que aparecem no nome das campanhas do projeto. */
  gestores_campanhas: string[];
  receita: number | null;
  investido: number | null;
  por_plataforma: Record<string, number> | null;
  moedas: string[];
  verba_maxima: number | null;
  verba_diaria: number | null;
  verba_fases: number;
  fases: number;
  pct_verba: number | null;
  impressoes: number | null;
  /** Cliques no link: o clique do CTR, do CPC e do connect rate. */
  cliques_link: number | null;
  /** Todos os cliques (só informação). */
  cliques_total: number | null;
  leads_plataforma: number | null;
  /** Page views das páginas de captura do projeto (Web). */
  page_views: number | null;
  leads: number | null;
  mql: number | null;
  cpl: number | null;
  ctr: number | null;
  cpc: number | null;
  cpm: number | null;
  pct_mql: number | null;
  connect_rate: number | null;
  conversao_pagina: number | null;
  gasto_ontem: number | null;
  dia_ontem: string;
  ritmo_ontem: number | null;
  ultimo_dia: string | null;
  meta_leads: number | null;
  meta_receita: number | null;
  meta_cpl: number | null;
  meta_pct_mql: number | null;
  obs: string | null;
  campanhas: number;
  campanhas_fora_padrao: number;
}

export interface Conta {
  id: number;
  plataforma: string;
  conta_externa: string;
  nome: string;
  dono: Dono;
  cliente: string | null;
  moeda: string;
  ativa: boolean;
  obs: string | null;
  campanhas: number;
}

export interface Campanha {
  id: number;
  plataforma: string;
  conta_id: number;
  conta: string;
  moeda: string;
  campanha_externa: string;
  nome: string;
  status_plataforma: string | null;
  fora_padrao: boolean;
  erros: string[];
  avisos: string[];
  gestor: string | null;
  objetivo: string | null;
  descricao: string | null;
  pagina: string | null;
  projeto_id: number | null;
  projeto_sigla: string | null;
  projeto_manual: boolean;
  /** Fase efetiva: a marcada à mão, senão a do objetivo, senão null ("sem fase"). */
  fase: string | null;
  fase_manual: string | null;
  fase_objetivo: string | null;
  gasto: number | null;
  impressoes: number | null;
  cliques_link: number | null;
  cliques_total: number | null;
  leads_plataforma: number | null;
  ultimo_dia: string | null;
}

/** Linha do quadro planejado × gasto: fase planejada (id) ou só com campanhas nela (id null = sem planejamento). */
export interface FaseProjeto {
  id: number | null;
  fase: string;
  nome: string;
  verba: number | null;
  inicio: string | null;
  fim: string | null;
  obs: string | null;
  gasto: number | null;
  campanhas: number;
}

export interface DiaSerie { dia: string; gasto: number; impressoes: number; cliques_link: number; leads_plataforma: number | null }

export interface VidaProjeto {
  resumo: LinhaResumo;
  fases: FaseProjeto[];
  gasto_sem_fase: number | null;
  campanhas_sem_fase: number;
  serie: DiaSerie[];
  campanhas: Campanha[];
}

export interface Resposta { ok: boolean; msg: string; id?: number; avisos?: string[] }

export const ROTULO_AVISO: Record<string, string> = {
  fases_acima_da_verba: 'A soma das fases passou da verba máxima.',
  diaria_acima_da_maxima: 'A verba diária está acima da verba máxima.',
};
