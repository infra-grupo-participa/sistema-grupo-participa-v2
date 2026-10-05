// Marketing > Web: MODO DE DEMONSTRAÇÃO (só desenvolvimento local). Números INVENTADOS, gerados por sorteio com
// semente fixa, para ver as telas antes da virada. Nunca é usado em produção: web-data.ts só liga com
// NEXT_PUBLIC_WEB_DEMO=1 E NODE_ENV diferente de 'production', e a tela mostra a faixa "Dados de demonstração".
// O cadastro (PB26, páginas /ak1/, /obrigado/, /quase-la/, /pesquisa/) é o da migration 20261005m; o resto é ficção.
import type { Formulario, Funil, Instalacao, Leitura, LinhaPagina, Origem, Problemas, Velocidade, Visao } from '../domain/tipos';
import { diasEntre, somaDias } from '../domain/periodo';

export const DEMO_PROJETOS = [{ id: 1, sigla: 'PB26', nome: 'Patrimônio Brasil 2026' }];
export const DEMO_PAGINAS = [
  { id: 11, projeto_id: 1, codigo: 'ak1', nome: 'AK1', dominio: 'patrimoniobrasil.com.br', caminho: '/ak1/', funcao: 'captura' },
  { id: 12, projeto_id: 1, codigo: null, nome: 'Obrigado', dominio: 'patrimoniobrasil.com.br', caminho: '/obrigado/', funcao: 'obrigado' },
  { id: 13, projeto_id: 1, codigo: null, nome: 'Pesquisa da BL2', dominio: 'patrimoniobrasil.com.br', caminho: '/quase-la/', funcao: 'pesquisa' },
  { id: 14, projeto_id: 1, codigo: null, nome: 'Pesquisa pelo link', dominio: 'patrimoniobrasil.com.br', caminho: '/pesquisa/', funcao: 'pesquisa' },
];

/** sorteio com semente (mulberry32): o mesmo período dá sempre os mesmos números */
function sorteio(semente: string) {
  let h = 1779033703 ^ semente.length;
  for (let i = 0; i < semente.length; i++) { h = Math.imul(h ^ semente.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
  let a = h >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const entre = (r: () => number, min: number, max: number) => Math.round(min + r() * (max - min));

export function demoVisao(de: string, ate: string): Visao {
  const r = sorteio('visao' + de + ate);
  const n = diasEntre(de, ate) + 1;
  const serie = Array.from({ length: n }, (_, i) => {
    const sessoes = entre(r, 900, 1800);
    const engajadas = Math.round(sessoes * (0.45 + r() * 0.15));
    return { dia: somaDias(de, i), sessoes, visualizacoes: Math.round(sessoes * 1.3), engajadas, leads: Math.round(sessoes * (0.08 + r() * 0.05)) };
  });
  const soma = (k: 'sessoes' | 'engajadas' | 'leads') => serie.reduce((s, d) => s + d[k], 0);
  const sessoes = soma('sessoes');
  return {
    kpis: {
      sessoes, visitantes: Math.round(sessoes * 0.86), engajadas: soma('engajadas'), leads: soma('leads'),
      visivel_ms_medio: 41000, paginas_por_sessao: 1.32, com_raiva: Math.round(sessoes * 0.012), com_erro: Math.round(sessoes * 0.004),
      de_anuncio: Math.round(sessoes * 0.93), resultados: { mql: Math.round(soma('leads') * 0.31), nao_mql: Math.round(soma('leads') * 0.52) },
    },
    serie,
    coleta: { ligada: true, pausada: false, ultimo_pacote: new Date().toISOString() },
  };
}

export function demoPaginas(de: string, ate: string): LinhaPagina[] {
  const v = demoVisao(de, ate).kpis.sessoes;
  return [
    { pagina_id: 11, dominio: 'patrimoniobrasil.com.br', caminho: '/ak1/', codigo: 'ak1', nome: 'AK1', funcao: 'captura', visualizacoes: Math.round(v * 1.05), sessoes: v, entradas: Math.round(v * 0.97), rejeicoes: Math.round(v * 0.44), entradas_lead: Math.round(v * 0.1), saidas_rapidas: Math.round(v * 0.21), rolagem_media: 58, visivel_ms_medio: 39000, lcp_p75: 2300 },
    { pagina_id: 12, dominio: 'patrimoniobrasil.com.br', caminho: '/obrigado/', codigo: null, nome: 'Obrigado', funcao: 'obrigado', visualizacoes: Math.round(v * 0.1), sessoes: Math.round(v * 0.1), entradas: 12, rejeicoes: 3, entradas_lead: 0, saidas_rapidas: Math.round(v * 0.03), rolagem_media: 81, visivel_ms_medio: 15000, lcp_p75: 1500 },
    { pagina_id: 13, dominio: 'patrimoniobrasil.com.br', caminho: '/quase-la/', codigo: null, nome: 'Pesquisa da BL2', funcao: 'pesquisa', visualizacoes: Math.round(v * 0.05), sessoes: Math.round(v * 0.05), entradas: 4, rejeicoes: 1, entradas_lead: 0, saidas_rapidas: 9, rolagem_media: 74, visivel_ms_medio: 52000, lcp_p75: 2900 },
    { pagina_id: null, dominio: 'patrimoniobrasil.com.br', caminho: '/', codigo: null, nome: null, funcao: null, visualizacoes: Math.round(v * 0.02), sessoes: Math.round(v * 0.02), entradas: Math.round(v * 0.02), rejeicoes: Math.round(v * 0.012), entradas_lead: 2, saidas_rapidas: 5, rolagem_media: 33, visivel_ms_medio: 12000, lcp_p75: 4300 },
  ];
}

export function demoFunil(de: string, ate: string): Funil[] {
  const v = demoVisao(de, ate).kpis.sessoes;
  return [
    { id: 'ak1', nome: 'Funil AK1', etapas: [
      { ordem: 1, nome: 'Entrou na AK1', sessoes: Math.round(v * 0.97), caminhos: ['/ak1/', '/'], eventos: [] },
      { ordem: 2, nome: 'Abriu o formulário', sessoes: Math.round(v * 0.31), caminhos: [], eventos: ['abriu_formulario'] },
      { ordem: 3, nome: 'Enviou a inscrição', sessoes: Math.round(v * 0.1), caminhos: [], eventos: ['lead_qualificado', 'lead_inscricao'] },
      { ordem: 4, nome: 'Viu o obrigado', sessoes: Math.round(v * 0.094), caminhos: ['/obrigado/'], eventos: [] },
    ] },
    { id: 'recuperacao', nome: 'Pesquisa pelo link', etapas: [
      { ordem: 1, nome: 'Abriu o link', sessoes: 140, caminhos: ['/pesquisa/'], eventos: [] },
      { ordem: 2, nome: 'Concluiu a pesquisa', sessoes: 61, caminhos: [], eventos: ['pesquisa_whatsapp_concluida'] },
    ] },
  ];
}

export function demoOrigem(de: string, ate: string): Origem {
  const v = demoVisao(de, ate).kpis.sessoes;
  const c = (s: number, l: number) => ({ sessoes: s, engajadas: Math.round(s * 0.5), leads: l });
  return {
    total: v, cliques_meta: Math.round(v * 0.9), cliques_google: Math.round(v * 0.02),
    fontes: [
      { fonte: 'ig', meio: 'paid', ...c(Math.round(v * 0.62), Math.round(v * 0.07)) },
      { fonte: 'fb', meio: 'paid', ...c(Math.round(v * 0.27), Math.round(v * 0.025)) },
      { fonte: '(direto)', meio: null, ...c(Math.round(v * 0.07), Math.round(v * 0.004)) },
      { fonte: 'google', meio: 'cpc', ...c(Math.round(v * 0.02), Math.round(v * 0.002)) },
    ],
    campanhas: [
      { campanha: 'RS | PB26 | LEADS | DEMONSTRAÇÃO A | AK1', ...c(Math.round(v * 0.55), Math.round(v * 0.06)), padrao: true, pagina: 'ak1', projeto: 'PB26' },
      { campanha: 'CF | PB26 | LEADS | DEMONSTRAÇÃO B', ...c(Math.round(v * 0.3), Math.round(v * 0.03)), padrao: true, pagina: null, projeto: 'PB26' },
      { campanha: 'campanha_fora_do_padrao_demo', ...c(Math.round(v * 0.04), 3), padrao: false, pagina: null, projeto: null },
    ],
    anuncios: [
      { anuncio: '120200000000000001', campanha: 'RS | PB26 | LEADS | DEMONSTRAÇÃO A | AK1', ...c(Math.round(v * 0.3), Math.round(v * 0.04)) },
      { anuncio: '120200000000000002', campanha: 'RS | PB26 | LEADS | DEMONSTRAÇÃO A | AK1', ...c(Math.round(v * 0.25), Math.round(v * 0.02)) },
      { anuncio: '120200000000000003', campanha: 'CF | PB26 | LEADS | DEMONSTRAÇÃO B', ...c(Math.round(v * 0.3), Math.round(v * 0.03)) },
    ],
    sites: [{ site: 'l.instagram.com', sessoes: Math.round(v * 0.4) }, { site: 'm.facebook.com', sessoes: Math.round(v * 0.2) }],
  };
}

export function demoVelocidade(de: string, ate: string): Velocidade {
  const r = sorteio('vel' + de + ate);
  const n = diasEntre(de, ate) + 1;
  const linha = (caminho: string, dispositivo: string, lcp: number, inp: number, cls: number, qtd: number) => ({
    caminho, dispositivo, n: qtd, lcp_p75: lcp, inp_p75: inp, cls_p75: cls, fcp_p75: Math.round(lcp * 0.6), ttfb_p75: 380,
    lcp_bom: Math.round(qtd * (lcp <= 2500 ? 0.8 : 0.55)), peso_kb_mediano: 910,
  });
  return {
    paginas: [
      linha('/ak1/', 'mobile', 2700, 210, 0.04, 14000), linha('/ak1/', 'desktop', 1600, 90, 0.02, 1100),
      linha('/obrigado/', 'mobile', 1500, 120, 0.01, 1300), linha('/quase-la/', 'mobile', 4200, 540, 0.31, 600),
    ],
    serie: Array.from({ length: n }, (_, i) => ({ dia: somaDias(de, i), lcp_p75: entre(r, 2200, 3200), n: entre(r, 800, 1500) })),
  };
}

export function demoLeitura(): Leitura {
  return {
    visualizacoes: 15200,
    rolagem: { chegou_25: 13100, chegou_50: 9400, chegou_75: 6100, chegou_100: 3900, media: 58, media_30s: 34, vaivem_medio: 1.4 },
    secoes: [
      { secao: 'topo', ordem: 1, segundos: 152000, viram: 15000, medidas: 15100 },
      { secao: 'padrao', ordem: 2, segundos: 98000, viram: 11000, medidas: 15100 },
      { secao: 'caminho', ordem: 3, segundos: 61000, viram: 8200, medidas: 15100 },
      { secao: 'especialistas', ordem: 4, segundos: 40000, viram: 6100, medidas: 15100 },
      { secao: 'faq', ordem: 5, segundos: 18000, viram: 3500, medidas: 15100 },
    ],
    ctas: [
      { cta: 'topo', viram: 14800, medidas: 15100, cliques: 2900 },
      { cta: 'virada', viram: 7600, medidas: 15100, cliques: 950 },
      { cta: 'final', viram: 3700, medidas: 15100, cliques: 420 },
    ],
    mapa: { secoes: ['topo', 'padrao', 'caminho', 'especialistas', 'faq'], ctas: ['topo', 'virada', 'final'], campos: ['nome', 'email', 'telefone'] },
  };
}

export function demoProblemas(): Problemas {
  return {
    cliques: 21400, raiva: 160, mortos: 1450, automaticos: 980, sessoes_com_raiva: 90,
    top_raiva: [
      { seletor: 'div.modal-fundo', texto: '', n: 70, sessoes: 31 },
      { seletor: 'button[data-cta="topo"]', texto: 'Quero participar', n: 41, sessoes: 22 },
    ],
    top_mortos: [
      { seletor: 'img.foto-especialista', texto: '', n: 520, sessoes: 380 },
      { seletor: 'section#padrao > h2', texto: 'O caminho padrão', n: 310, sessoes: 250 },
    ],
    mais_clicados: [
      { seletor: 'button[data-cta="topo"]', texto: 'Quero participar', n: 2900 },
      { seletor: 'input#telefone', texto: '', n: 2100 },
      { seletor: 'img.foto-especialista', texto: '', n: 520 },
    ],
    erros: 12, sessoes_com_erro: 9,
    top_erros: [{ mensagem: 'Cannot read properties of null (reading "value") [demonstração]', arquivo: 'form.js', n: 12, sessoes: 9 }],
    erros_fora: [{ tipo: 'app_android', n: 410, sessoes: 330 }, { tipo: 'sem_detalhe', n: 160, sessoes: 70 }],
  };
}

export function demoFormulario(): Formulario {
  return {
    medidas: 15200, viram: 9900, comecaram: 3600, enviaram: 1510, tempo_mediano_s: 41,
    campos: [
      { campo: 'nome', entraram: 3600, focos: 3900, segundos_medio: 6, preenchidos: 3400, com_erro: 12, ordem: 1 },
      { campo: 'email', entraram: 3200, focos: 3700, segundos_medio: 9, preenchidos: 2900, com_erro: 260, ordem: 2 },
      { campo: 'telefone', entraram: 2700, focos: 3300, segundos_medio: 11, preenchidos: 2300, com_erro: 410, ordem: 3 },
    ],
    pararam_em: [{ campo: 'telefone', n: 1100 }, { campo: 'email', n: 620 }, { campo: 'nome', n: 370 }],
  };
}

export function demoInstalacao(): Instalacao {
  return {
    coleta_geral: 'ligada',
    projetos: [{
      id: 1, sigla: 'PB26', nome: 'Patrimônio Brasil 2026', ativo: true, coleta: false,
      eventos_lead: ['lead_qualificado', 'lead_inscricao', 'form_enviado'],
      funis: [{ id: 'ak1', nome: 'Funil AK1', etapas: [{ nome: 'Entrou na AK1', caminhos: ['/ak1/', '/'] }, { nome: 'Abriu o formulário', eventos: ['abriu_formulario'] }] }],
      dominios: ['patrimoniobrasil.com.br'], ultimo_pacote: null,
    }],
    recusas_7d: [],
    falhas_7d: 0,
  };
}
