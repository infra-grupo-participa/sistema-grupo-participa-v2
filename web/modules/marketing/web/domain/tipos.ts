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
