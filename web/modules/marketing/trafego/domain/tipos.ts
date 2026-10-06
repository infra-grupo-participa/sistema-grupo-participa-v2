// Marketing > Tráfego: tipos do que as funções public.trafego_* devolvem (migration 20261005p). Domínio puro.

export type Subarea = 'interno' | 'aurum' | 'diamante';
export type Tipo = 'interno' | 'externo';
export type Dono = 'grupo' | 'diamante' | 'aurum';

/** Subárea antiga (mkt.projetos.subarea_trafego): desde a 20261006a é derivada de tipo e unidade. A tela filtra por tipo e unidade. */
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
  /** true = a Web fase 2 (20261005q, public.mkt_web_connect) existe e as page views vêm dela. */
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
  /** Interno ou externo (mkt.projetos.tipo, 20261006a). */
  tipo: Tipo | null;
  /** Unidade dentro do tipo (csm, escritorio, aurum, diamantes; 20261006a). Nulo = não marcada. */
  unidade?: string | null;
  unidade_nome?: string | null;
  tipo_lancamento?: string | null;
  tipo_lancamento_nome?: string | null;
  especialista?: string | null;
  /** Contas de anúncio ligadas ao projeto (ids de mkt_trafego.contas). */
  contas_projeto?: number[];
  /** false = projeto externo: a receita não entra por ora (Victor, 06/10/2026). */
  receita_aplica?: boolean;
  /** Período de captação e do evento (20261006a). A captação é o padrão da receita e da meta de leads. */
  captacao_inicio?: string | null;
  captacao_fim?: string | null;
  evento_inicio?: string | null;
  evento_fim?: string | null;
  /** Checklist de montagem: itens prontos e itens que se aplicam (20261006a). */
  checklist_feitos?: number | null;
  checklist_total?: number | null;
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
  /** Receita gerada (Hotmart): soma de public.compras aprovadas dos produtos ligados ao projeto, no período. Nulo = sem vínculo. */
  receita: number | null;
  /** Compras aprovadas que entraram (todas as moedas). Nulo = public.compras sem as colunas da Hotmart (banco local). */
  receita_compras?: number | null;
  /** Compras aprovadas em outra moeda (não entram na soma em reais). */
  receita_outras_moedas?: number | null;
  receita_sem_valor?: number | null;
  /** Vínculos produto Hotmart → projeto cadastrados. */
  receita_vinculos?: number;
  /** Vínculos sem período (sem "de" e o projeto sem início): não somam. */
  receita_sem_periodo?: number;
  /** false = public.compras sem as colunas da Hotmart neste banco. */
  receita_fonte?: boolean;
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
  /** Page views da Web fase 2: visitas vindas das campanhas do projeto, uma por visita (a mesma de mkt_web_connect). */
  page_views: number | null;
  /** Dessas visitas, as que viraram lead (o numerador da conversão da página, como na Web). */
  leads_pagina: number | null;
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
  /** Unidade da conta (csm, escritorio, aurum, diamantes; 20261006b). Nulo = não classificada. */
  unidade?: string | null;
  /** Conta principal: aparece primeiro na seleção (20261006b). */
  principal?: boolean;
}

/** Unidade que combina com o dono da conta (a mesma regra de public.trafego_conta_marcar). */
export function unidadesDoDono(dono: Dono): string[] {
  return dono === 'grupo' ? ['csm', 'escritorio'] : dono === 'aurum' ? ['aurum'] : ['diamantes'];
}

/** Ordem da lista de contas (a mesma do banco): ativas, principais, plataforma, nome. */
export function ordenarContas<T extends Pick<Conta, 'ativa' | 'plataforma' | 'nome'> & { principal?: boolean }>(cs: T[]): T[] {
  return [...cs].sort((a, b) => Number(b.ativa) - Number(a.ativa) || Number(!!b.principal) - Number(!!a.principal)
    || a.plataforma.localeCompare(b.plataforma) || a.nome.localeCompare(b.nome));
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
  /** O projeto como está escrito no nome (2º campo), mesmo sem cadastro. 20261005p. */
  projeto_lido?: string | null;
  /** Quantos campos o nome tem (para o motivo "menos de 3 campos"). */
  campos?: number | null;
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

// ─── Fase 2 (migration 20261005r) ─────────────────────────────────────────────────────────────────────────────────────

export type RegraAlerta =
  | 'acima_verba_diaria' | 'cpl_acima_meta' | 'leads_abaixo_meta' | 'ritmo_fase' | 'verba_perto_fim' | 'fora_padrao' | 'sem_fase'
  | 'conta_fora_projeto' | 'checklist_incompleto';

/** Regra do resumo do dia, com o limiar da tabela mkt_trafego.alerta_regras. */
export interface Regra {
  codigo: RegraAlerta; nome: string; ligada: boolean; limiar: number; unidade: 'pct' | 'dias'; gravidade: 'alta' | 'media'; descricao: string;
}

/** Um alerta do resumo do dia ("o que está pegando fogo"). projeto_id nulo = campanhas sem projeto. */
export interface Alerta {
  regra: RegraAlerta;
  nome: string;
  gravidade: 'alta' | 'media';
  limiar: number;
  unidade: 'pct' | 'dias';
  projeto_id: number | null;
  sigla: string | null;
  projeto_nome: string | null;
  /** O número que disparou (gasto de ontem, CPL, leads, gasto da fase, % da verba, nº de campanhas). */
  valor: number;
  /** Contra o quê (verba diária, meta de CPL, leads esperados, gasto esperado da fase, limiar). */
  referencia: number | null;
  detalhe: {
    pct?: number | null; fase?: string; fase_nome?: string; direcao?: 'acima' | 'abaixo'; verba?: number; inicio?: string; fim?: string;
    meta?: number; periodo?: 'captacao' | 'projeto'; dias?: number; investido?: number; verba_maxima?: number;
    /** conta_fora_projeto: nomes das contas de fora onde as campanhas gastaram. */
    contas?: string[];
    /** checklist_incompleto: os itens de "antes" pendentes. */
    itens?: string[];
  };
}

export interface ColetaInfo { em: string; ok: boolean; erro: string | null }

export interface ResumoDia {
  /** Último dia completo (São Paulo) que os alertas olham. */
  dia: string;
  /** Nenhum gasto coletado ainda: verba, ritmo, CPL e % da verba não têm como disparar. */
  sem_coleta: boolean;
  base_pessoas: boolean;
  projetos_avaliados: number;
  alertas: Alerta[];
  regras: Regra[];
  coletas: Partial<Record<'meta' | 'google' | 'clickup', ColetaInfo>>;
}

/** Vínculo produto Hotmart → projeto (cadastro à mão). */
export interface ProdutoHotmart {
  id: number; projeto_id: number; projeto_sigla: string; produto_id: string; oferta_codigo: string | null;
  de: string | null; ate: string | null; obs: string | null;
  /** O período que vale: "de" ou o início do projeto; "até" ou o fim do projeto (nulo = até hoje). */
  de_efetivo: string | null; ate_efetivo: string | null;
}

/** Produto que já apareceu em public.compras (para escolher no cadastro). */
export interface ProdutoVisto { produto_id: string; nome: string | null; aprovadas: number; primeira: string | null; ultima: string | null }

export interface TarefaClickup {
  id: string; nome: string; status: string | null; criada_em: string | null; atualizada_em: string | null;
  inicio: string | null; prazo: string | null; concluida_em: string | null; responsaveis: string[]; url: string | null;
}

export interface ClickupProjeto {
  etiqueta: string | null;
  /** O workspace do ClickUp está configurado (mkt_trafego.coleta_config clickup_team_id). */
  configurado: boolean;
  ultima_coleta: ColetaInfo | null;
  tarefas: TarefaClickup[];
}

export const ROTULO_AVISO_PRODUTO: Record<string, string> = {
  produto_em_outro_projeto: 'Este produto também está ligado a outro projeto num período que se cruza: a compra conta nos dois.',
  sem_periodo: 'Sem "de" e o projeto sem data de início: este vínculo não soma até ter uma data.',
  produto_sem_compras: 'Nenhuma compra deste produto apareceu ainda na Hotmart (confira o id).',
};

// ─── Cadastro do projeto (migration 20261006a) ───────────────────────────────────────────────────────────────────────

/** Onde se resolve um item automático do checklist (a tela leva até lá). 20261006d. */
export type AcaoChecklist = 'projeto' | 'paginas' | 'hotmart' | 'modelo' | 'planejamento' | 'fases' | 'gerador' | 'campanhas';

/** Item do checklist de montagem. Automático: o banco confere (codigo). Manual: alguém marca (id; item do projeto, 20261006d). */
export interface ItemChecklist {
  codigo?: string;
  id?: number;
  texto: string;
  /** Antes de subir as campanhas, durante, encerramento (20261006d). */
  momento?: 'antes' | 'durante' | 'encerramento';
  acao?: AcaoChecklist;
  /** Item manual que veio do modelo aplicado. */
  do_modelo?: boolean;
  /** false = não se aplica a este projeto (fica fora da conta). */
  aplica: boolean;
  ok: boolean;
  detalhe?: string | null;
  tipo_lancamento?: string | null;
  marcado_em?: string | null;
  marcado_por?: string | null;
}

export interface Checklist {
  automaticos: ItemChecklist[]; manuais: ItemChecklist[]; feitos: number; total: number;
  /** Campanhas esperadas do projeto (do modelo), com "criada" (20261006d). */
  esperadas?: { id: number; objetivo: string; fase: string | null; descricao: string | null; pagina: string | null; criada: boolean }[];
  /** Modelo aplicado (nulo = nenhum). */
  modelo?: { id: number | null; nome: string; aplicado_em: string } | null;
  /** Textos dos itens de "antes" ainda pendentes (o resumo do dia avisa em captação). */
  pendentes_antes?: string[];
}
