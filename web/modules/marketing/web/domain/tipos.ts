// Marketing > Web: o formato do que as funções public.mkt_web_* devolvem (migration 20261005n). O modo de
// demonstração devolve o mesmo formato.

export interface Visao {
  kpis: {
    sessoes: number; visitantes: number; engajadas: number; leads: number; visivel_ms_medio: number; paginas_por_sessao: number;
    com_raiva: number; com_erro: number; de_anuncio: number; resultados: Record<string, number>;
  };
  serie: { dia: string; sessoes: number; visualizacoes: number; engajadas: number; leads: number }[];
  coleta: { ligada: boolean; pausada: boolean; ultimo_pacote: string | null };
}

export interface LinhaPagina {
  pagina_id: number | null; dominio: string; caminho: string; codigo: string | null; nome: string | null; funcao: string | null;
  visualizacoes: number; sessoes: number; entradas: number; rejeicoes: number; entradas_lead: number; saidas_rapidas: number;
  rolagem_media: number; visivel_ms_medio: number; lcp_p75: number | null;
}

export interface Funil {
  id: string; nome: string;
  etapas: { ordem: number; nome: string; sessoes: number; caminhos: string[]; eventos: string[] }[];
}

export interface Origem {
  total: number; cliques_meta: number; cliques_google: number;
  fontes: { fonte: string; meio: string | null; sessoes: number; engajadas: number; leads: number }[];
  campanhas: { campanha: string; sessoes: number; engajadas: number; leads: number; padrao: boolean; pagina: string | null; projeto: string | null }[];
  anuncios: { anuncio: string; campanha: string | null; sessoes: number; engajadas: number; leads: number }[];
  sites: { site: string; sessoes: number }[];
}

export interface Velocidade {
  paginas: {
    caminho: string; dispositivo: string; n: number; lcp_p75: number | null; inp_p75: number | null; cls_p75: number | null;
    fcp_p75: number | null; ttfb_p75: number | null; lcp_bom: number; peso_kb_mediano: number | null;
  }[];
  serie: { dia: string; lcp_p75: number | null; n: number }[];
}

export interface Leitura {
  visualizacoes: number;
  rolagem: { chegou_25: number; chegou_50: number; chegou_75: number; chegou_100: number; media: number; media_30s: number | null; vaivem_medio: number | null };
  secoes: { secao: string; ordem: number | null; segundos: number; viram: number; medidas: number }[];
  ctas: { cta: string; viram: number; medidas: number; cliques: number }[];
  mapa: { secoes: string[]; ctas: string[]; campos: string[] } | null;
}

export interface Problemas {
  cliques: number; raiva: number; mortos: number; automaticos: number; sessoes_com_raiva: number;
  top_raiva: { seletor: string; texto: string; n: number; sessoes: number }[];
  top_mortos: { seletor: string; texto: string; n: number; sessoes: number }[];
  mais_clicados: { seletor: string; texto: string; n: number }[];
  erros: number; sessoes_com_erro: number;
  top_erros: { mensagem: string; arquivo: string | null; n: number; sessoes: number }[];
  erros_fora: { tipo: string; n: number; sessoes: number }[];
}

export interface Formulario {
  medidas: number; viram: number; comecaram: number; enviaram: number; tempo_mediano_s: number | null;
  campos: { campo: string; entraram: number; focos: number; segundos_medio: number | null; preenchidos: number; com_erro: number; ordem: number | null }[];
  pararam_em: { campo: string; n: number }[];
}

export interface Instalacao {
  coleta_geral: string;
  projetos: {
    id: number; sigla: string; nome: string; ativo: boolean; coleta: boolean; eventos_lead: string[];
    funis: { id: string; nome: string; etapas: { nome: string; caminhos?: string[]; eventos?: string[] }[] }[];
    dominios: string[]; ultimo_pacote: string | null;
  }[];
  recusas_7d: { motivo: string; vezes: number }[];
  falhas_7d: number;
}

/** nome do erro de fora na tela (radar.erro_de_fora_nome) */
export const NOME_ERRO_FORA: Record<string, string> = {
  app_android: 'Script do app do Facebook (Android)',
  app_iphone: 'Script do app no iPhone',
  sem_detalhe: 'Script de outro site sem detalhe',
  extensao: 'Extensão do navegador',
  aviso: 'Aviso inofensivo do navegador',
  outro_site: 'Script de outro site',
};

export const APARELHO: Record<string, string> = { mobile: 'Celular', tablet: 'Tablet', desktop: 'Computador' };

export const MOTIVO_RECUSA: Record<string, string> = {
  projeto: 'Projeto desconhecido ou com a coleta desligada',
  dominio: 'Domínio fora das páginas cadastradas',
  identificador: 'Identificador fora do formato',
  tamanho: 'Pacote grande demais',
  json: 'Pacote ilegível',
  limite_ip: 'Excesso de envios do mesmo IP',
  limite_sessao: 'Excesso de envios da mesma visita',
};

// ─── Fase 2 (migration 20261005q) ────────────────────────────────────────────────────────────────────────────────────
/** mkt_web_fluxo: a visita como sequência de caminhos (recarregar não é passo) */
export interface Fluxo {
  sessoes: number; uma_pagina: number; passos_medio: number;
  nomes: Record<string, string>;
  paginas: { caminho: string; vistas: number; entradas: number; saidas: number; leads: number }[];
  passagens: { de: string; para: string; n: number; leads: number }[];
  caminhos: { passos: string[]; mais: boolean; n: number; leads: number }[];
}

/** os números de uma página que as regras de achados leem (formato do api_oportunidades do Radar) */
export interface PaginaMelhorias {
  pagina_id: number; codigo: string | null; nome: string; funcao: string; caminho: string;
  visitas: number; sessoes: number; leads: number; mql: number; dias: number;
  entradas: number; rejeicoes: number; leads_entrada: number; mql_entrada: number;
  por_aparelho?: { dispositivo: string; entradas: number; rejeicoes: number; leads: number }[];
  por_criativo?: { campanha: string; criativo: string; entradas: number; rejeicoes: number; leads: number }[];
  friccao?: { com_raiva: number; com_erro: number; com_friccao: number; friccao_leads: number; sem_friccao: number; sem_leads: number } | null;
  lcp?: { faixa: 'bom' | 'medio' | 'ruim'; entradas: number; rejeicoes: number; leads: number }[];
  por_dia?: { dia: string; entradas: number }[];
}

/** a leitura de uma página (formato do api_leitura do Radar) */
export interface LeituraMelhorias {
  pagina_id: number; visitas: number; medidas: number; medidas_lead: number; medidas_mql: number;
  secoes: { secao: string; ordem: number; viram: number; chegaram: number; viram_lead: number; viram_mql: number }[];
  primeiro_cta: { dispositivo: string; medidas: number; viram: number; ficaram: number; ficaram_sem_ver: number; leads_de_quem_viu: number }[];
  ctas: { cta: string; ordem: number; medidas: number; viram: number; clicaram: number; leads: number }[];
  leads_com_botao: number;
  form: { viram: number; abriram: number; comecaram: number; enviaram: number;
    campos: { campo: string; ordem: number; tocaram: number; focaram: number; com_erro: number; pararam: number }[] };
}

export interface BaseMelhorias { sessoes: number; leads: number; dias: number; paginas: PaginaMelhorias[]; leituras?: LeituraMelhorias[] }
export interface Melhorias { de: string; ate: string; antes_de: string; antes_ate: string; atual: BaseMelhorias; antes: BaseMelhorias }

/** mkt_web_comparar: um lado (página ou projeto inteiro, num período) */
export interface LadoComparar {
  pagina_id: number | null; de: string; ate: string; nome: string | null; caminho: string | null;
  visitas: number; leads: number; mql: number; entradas: number; rejeicoes: number; leads_entrada: number; vistas: number;
  rolagem_media: number; visivel_ms_medio: number; lcp_p75: number | null; dias: number;
  por_aparelho: { chave: string; visitas: number; leads: number }[];
  por_origem: { chave: string; visitas: number; leads: number }[];
}
export interface Comparacao2 { a: LadoComparar; b: LadoComparar }

/** mkt_web_calor: ponto = [x %, y como fração da altura, tipo (0 clique, 1 raiva, 2 morto, 3 os dois), índice do elemento] */
export interface Calor {
  url: string | null; visitas: number; largura: number | null; altura_doc: number | null;
  pontos: [number, number, number, number][]; amostra: boolean; elementos: [string, string][];
  contagem: { cliques: number; raiva: number; mortos: number; fixos: number } | null;
  alcance: number[] | null;
  top: { sel: string; txt: string; n: number; raiva: number; morto: number; fixo: boolean }[];
  captura: { img: string; largura: number; altura: number; medido_em: string } | null;
}

export interface TesteLab {
  medido_em: string; nota: number | null; notas: { desempenho?: number; acessibilidade?: number; praticas?: number; seo?: number } | null;
  lcp_ms: number | null; fcp_ms: number | null; tbt_ms: number | null; si_ms: number | null; cls: number | null;
  oportunidades: { id: string; titulo: string; ms: number }[]; erro: string | null;
}
export interface Lab {
  ligado: boolean; coleta: boolean;
  paginas: { pagina_id: number; nome: string; caminho: string; estrategia: 'mobile' | 'desktop'; ultimo: TesteLab | null;
    anterior_nota: number | null; serie: { quando: string; nota: number; lcp_ms: number | null }[] }[];
}

/** mkt_web_leads: lead da Web ligado à base de pessoas (sem dado pessoal: só a referência opaca e o id da ficha) */
export interface LeadsPessoas {
  base: boolean; pode_abrir: boolean; leads_web: number; navegadores_lead: number; com_ref: number;
  pessoas: number | null; mql: number | null; nao_mql: number | null;
  lista: { ref: string; pessoa_id: string; quando: string | null; mql: boolean; nao_mql: boolean }[];
}

/** mkt_web_connect: connect rate = page views ÷ cliques no link; conversão = leads ÷ page views */
export interface Connect {
  trafego: boolean; cliques_link: boolean;
  campanhas: { campanha: string; campanha_externa: string; plataforma: string; pagina: string | null; gasto: number | null;
    impressoes: number | null; cliques_link: number | null; dias_com_gasto: number; page_views: number; engajadas: number; leads: number;
    connect_rate: number | null; conversao: number | null }[];
  sem_campanha: { page_views: number; campanhas: number } | null;
  anuncios: { anuncio: string; campanha: string | null; page_views: number; engajadas: number; leads: number }[];
}
