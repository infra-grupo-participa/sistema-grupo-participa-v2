// Marketing > Web: MODO DE DEMONSTRAÇÃO (só desenvolvimento local). Números INVENTADOS, gerados por sorteio com
// semente fixa, para ver as telas antes da virada. Nunca é usado em produção: web-data.ts só liga com
// NEXT_PUBLIC_WEB_DEMO=1 E NODE_ENV diferente de 'production', e a tela mostra a faixa "Dados de demonstração".
// O cadastro (PB26, páginas /ak1/, /obrigado/, /quase-la/, /pesquisa/) é o da migration 20261005m; o resto é ficção.
import type {
  BaseMelhorias, Calor, Comparacao2, Connect, Formulario, Fluxo, Funil, Instalacao, Lab, LadoComparar, LeadsPessoas, Leitura, LinhaPagina,
  Melhorias, Origem, PaginaMelhorias, Problemas, Velocidade, Visao,
} from '../domain/tipos';
import { diasEntre, somaDias } from '../domain/periodo';
import { separarUtm } from '../../projetos/domain/utm';

// UTMs de demonstração no padrão do gp-operacoes (nome|id; Google só id), lidos pela mesma regra do banco (separarUtm).
const UTM_CAMPANHA_A = 'RS | PB26 | LEADS | DEMONSTRAÇÃO A | AK1|120200000000000100';
const UTM_CAMPANHA_B = 'CF | PB26 | LEADS | DEMONSTRAÇÃO B|120200000000000200';
const UTM_CAMPANHA_GOOGLE = '22000000000';
const UTM_ANUNCIOS = ['CRIATIVO VÍDEO DEPOIMENTO|120200000000000001', 'CRIATIVO CARROSSEL ESCRITÓRIO|120200000000000002', 'CRIATIVO ESTÁTICO PRAZO|120200000000000003'];
const campanhaDemo = (utm: string) => { const u = separarUtm(utm); return { campanha: u.nome ?? u.id ?? '', campanha_id: u.id }; };
const anuncioDemo = (utm: string) => { const u = separarUtm(utm); return { anuncio: u.nome ?? u.id ?? '', anuncio_id: u.id }; };

export const DEMO_PROJETOS = [{ id: 1, sigla: 'PB26', nome: 'Patrimônio Brasil 2026' }];
export const DEMO_PAGINAS = [
  { id: 11, projeto_id: 1, codigo: 'ak1', nome: 'AK1', dominio: 'patrimoniobrasil.com.br', caminho: '/ak1/', funcao: 'captura' },
  { id: 12, projeto_id: 1, codigo: null, nome: 'Obrigado', dominio: 'patrimoniobrasil.com.br', caminho: '/obrigado/', funcao: 'obrigado' },
  { id: 13, projeto_id: 1, codigo: null, nome: 'Pesquisa da BL2', dominio: 'patrimoniobrasil.com.br', caminho: '/quase-la/', funcao: 'pesquisa' },
  { id: 14, projeto_id: 1, codigo: null, nome: 'Pesquisa pelo link', dominio: 'patrimoniobrasil.com.br', caminho: '/pesquisa/', funcao: 'pesquisa' },
  // variação INVENTADA (não existe no cadastro): só para ver a tela de testes A/B no modo de demonstração
  { id: 15, projeto_id: 1, codigo: 'ak1-b', nome: 'AK1 B (demonstração)', dominio: 'patrimoniobrasil.com.br', caminho: '/ak1-b/', funcao: 'captura' },
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
      { ...campanhaDemo(UTM_CAMPANHA_A), ...c(Math.round(v * 0.55), Math.round(v * 0.06)), padrao: true, pagina: 'ak1', projeto: 'PB26' },
      { ...campanhaDemo(UTM_CAMPANHA_B), ...c(Math.round(v * 0.3), Math.round(v * 0.03)), padrao: true, pagina: null, projeto: 'PB26' },
      { ...campanhaDemo('campanha_fora_do_padrao_demo'), ...c(Math.round(v * 0.04), 3), padrao: false, pagina: null, projeto: null },
      { ...campanhaDemo(UTM_CAMPANHA_GOOGLE), ...c(Math.round(v * 0.02), 1), padrao: null, pagina: null, projeto: null },
    ],
    anuncios: [
      { ...anuncioDemo(UTM_ANUNCIOS[0]), campanha: campanhaDemo(UTM_CAMPANHA_A).campanha, ...c(Math.round(v * 0.3), Math.round(v * 0.04)) },
      { ...anuncioDemo(UTM_ANUNCIOS[1]), campanha: campanhaDemo(UTM_CAMPANHA_A).campanha, ...c(Math.round(v * 0.25), Math.round(v * 0.02)) },
      { ...anuncioDemo(UTM_ANUNCIOS[2]), campanha: campanhaDemo(UTM_CAMPANHA_B).campanha, ...c(Math.round(v * 0.3), Math.round(v * 0.03)) },
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

// ─── Fase 2 (migration 20261006h): tudo inventado ────────────────────────────────────────────────────────────────────
const NOMES_DEMO: Record<string, string> = Object.fromEntries(DEMO_PAGINAS.map((p) => [p.caminho, p.nome]));

export function demoFluxo(de: string, ate: string): Fluxo {
  const v = demoVisao(de, ate).kpis.sessoes;
  const r = (f: number) => Math.round(v * f);
  return {
    sessoes: v, uma_pagina: r(0.78), passos_medio: 1.31, nomes: NOMES_DEMO,
    paginas: [
      { caminho: '/ak1/', vistas: r(0.82), entradas: r(0.8), saidas: r(0.72), leads: r(0.09) },
      { caminho: '/ak1-b/', vistas: r(0.15), entradas: r(0.15), saidas: r(0.13), leads: r(0.015) },
      { caminho: '/obrigado/', vistas: r(0.1), entradas: r(0.005), saidas: r(0.07), leads: r(0.098) },
      { caminho: '/quase-la/', vistas: r(0.05), entradas: 3, saidas: r(0.045), leads: r(0.04) },
    ],
    passagens: [
      { de: '/ak1/', para: '(saiu)', n: r(0.72), leads: r(0.005) },
      { de: '/ak1/', para: '/obrigado/', n: r(0.085), leads: r(0.085) },
      { de: '/ak1-b/', para: '(saiu)', n: r(0.13), leads: 2 },
      { de: '/ak1-b/', para: '/obrigado/', n: r(0.013), leads: r(0.013) },
      { de: '/obrigado/', para: '(saiu)', n: r(0.07), leads: r(0.07) },
      { de: '/obrigado/', para: '/quase-la/', n: r(0.03), leads: r(0.03) },
      { de: '/quase-la/', para: '(saiu)', n: r(0.045), leads: r(0.04) },
    ],
    caminhos: [
      { passos: ['/ak1/'], mais: false, n: r(0.7), leads: r(0.004) },
      { passos: ['/ak1-b/'], mais: false, n: r(0.12), leads: 2 },
      { passos: ['/ak1/', '/obrigado/'], mais: false, n: r(0.06), leads: r(0.06) },
      { passos: ['/ak1/', '/obrigado/', '/quase-la/'], mais: false, n: r(0.025), leads: r(0.025) },
    ],
  };
}

function diasDe(de: string, ate: string) { return Array.from({ length: diasEntre(de, ate) + 1 }, (_, i) => somaDias(de, i)); }

function paginaDemo(p: Partial<PaginaMelhorias> & { pagina_id: number; codigo: string | null; nome: string; caminho: string }, de: string, ate: string, fator: number): PaginaMelhorias {
  const entradas = Math.round(1400 * fator * (diasEntre(de, ate) + 1) / 7);
  const rej = Math.round(entradas * 0.46), leads = Math.round(entradas * 0.1);
  return {
    funcao: 'captura', visitas: Math.round(entradas * 1.05), sessoes: entradas, leads, mql: Math.round(leads * 0.3), dias: diasEntre(de, ate) + 1,
    entradas, rejeicoes: rej, leads_entrada: leads, mql_entrada: Math.round(leads * 0.3),
    por_aparelho: [
      { dispositivo: 'mobile', entradas: Math.round(entradas * 0.85), rejeicoes: Math.round(entradas * 0.85 * 0.5), leads: Math.round(leads * 0.8) },
      { dispositivo: 'desktop', entradas: Math.round(entradas * 0.15), rejeicoes: Math.round(entradas * 0.15 * 0.3), leads: Math.round(leads * 0.2) },
    ],
    por_criativo: [
      { campanha: campanhaDemo(UTM_CAMPANHA_A).campanha, criativo: anuncioDemo(UTM_ANUNCIOS[0]).anuncio, criativo_id: anuncioDemo(UTM_ANUNCIOS[0]).anuncio_id, entradas: Math.round(entradas * 0.5), rejeicoes: Math.round(entradas * 0.5 * 0.4), leads: Math.round(leads * 0.6) },
      { campanha: campanhaDemo(UTM_CAMPANHA_A).campanha, criativo: anuncioDemo(UTM_ANUNCIOS[1]).anuncio, criativo_id: anuncioDemo(UTM_ANUNCIOS[1]).anuncio_id, entradas: Math.round(entradas * 0.3), rejeicoes: Math.round(entradas * 0.3 * 0.62), leads: Math.round(leads * 0.2) },
    ],
    friccao: { com_raiva: 40, com_erro: 12, com_friccao: 50, friccao_leads: 3, sem_friccao: Math.round(entradas * 0.5), sem_leads: Math.round(leads * 0.9) },
    lcp: [
      { faixa: 'bom', entradas: Math.round(entradas * 0.6), rejeicoes: Math.round(entradas * 0.6 * 0.38), leads: Math.round(leads * 0.7) },
      { faixa: 'medio', entradas: Math.round(entradas * 0.3), rejeicoes: Math.round(entradas * 0.3 * 0.55), leads: Math.round(leads * 0.25) },
      { faixa: 'ruim', entradas: Math.round(entradas * 0.1), rejeicoes: Math.round(entradas * 0.1 * 0.7), leads: Math.round(leads * 0.05) },
    ],
    por_dia: diasDe(de, ate).map((dia) => ({ dia, entradas: Math.round(entradas / (diasEntre(de, ate) + 1)) })),
    ...p,
  };
}

export function demoMelhorias(de: string, ate: string): Melhorias {
  const n = diasEntre(de, ate) + 1;
  const ak1 = paginaDemo({ pagina_id: 11, codigo: 'ak1', nome: 'AK1', caminho: '/ak1/' }, de, ate, 1);
  const ak1b = paginaDemo({ pagina_id: 15, codigo: 'ak1-b', nome: 'AK1 B (demonstração)', caminho: '/ak1-b/' }, de, ate, 0.9);
  ak1b.leads_entrada = Math.round(ak1b.entradas * 0.125);
  const m = ak1.visitas;
  const atual: BaseMelhorias = {
    sessoes: ak1.sessoes + ak1b.sessoes, leads: ak1.leads + ak1b.leads, dias: n, paginas: [ak1, ak1b],
    leituras: [{
      pagina_id: 11, visitas: m, medidas: m, medidas_lead: Math.round(m * 0.1), medidas_mql: Math.round(m * 0.03),
      secoes: [
        { secao: 'topo', ordem: 1, viram: m, chegaram: m, viram_lead: Math.round(m * 0.1), viram_mql: Math.round(m * 0.03) },
        { secao: 'padrao', ordem: 2, viram: Math.round(m * 0.7), chegaram: Math.round(m * 0.7), viram_lead: Math.round(m * 0.09), viram_mql: Math.round(m * 0.028) },
        { secao: 'caminho', ordem: 3, viram: Math.round(m * 0.62), chegaram: Math.round(m * 0.62), viram_lead: Math.round(m * 0.085), viram_mql: Math.round(m * 0.027) },
        { secao: 'especialistas', ordem: 4, viram: Math.round(m * 0.3), chegaram: Math.round(m * 0.3), viram_lead: Math.round(m * 0.07), viram_mql: Math.round(m * 0.026) },
        { secao: 'faq', ordem: 5, viram: Math.round(m * 0.25), chegaram: Math.round(m * 0.25), viram_lead: Math.round(m * 0.05), viram_mql: Math.round(m * 0.02) },
      ],
      primeiro_cta: [
        { dispositivo: 'mobile', medidas: Math.round(m * 0.85), viram: Math.round(m * 0.85 * 0.45), ficaram: Math.round(m * 0.85 * 0.6), ficaram_sem_ver: Math.round(m * 0.85 * 0.25), leads_de_quem_viu: Math.round(m * 0.07) },
        { dispositivo: 'desktop', medidas: Math.round(m * 0.15), viram: Math.round(m * 0.15 * 0.9), ficaram: Math.round(m * 0.15 * 0.7), ficaram_sem_ver: 5, leads_de_quem_viu: Math.round(m * 0.02) },
      ],
      ctas: [
        { cta: 'topo', ordem: 1, medidas: m, viram: Math.round(m * 0.5), clicaram: Math.round(m * 0.15), leads: Math.round(m * 0.06) },
        { cta: 'virada', ordem: 2, medidas: m, viram: Math.round(m * 0.4), clicaram: Math.round(m * 0.05), leads: Math.round(m * 0.03) },
      ],
      leads_com_botao: Math.round(m * 0.09),
      form: { viram: Math.round(m * 0.6), abriram: Math.round(m * 0.3), comecaram: Math.round(m * 0.2), enviaram: Math.round(m * 0.1),
        campos: [
          { campo: 'nome', ordem: 1, tocaram: Math.round(m * 0.2), focaram: Math.round(m * 0.2), com_erro: 3, pararam: Math.round(m * 0.02) },
          { campo: 'telefone', ordem: 2, tocaram: Math.round(m * 0.17), focaram: Math.round(m * 0.18), com_erro: 60, pararam: Math.round(m * 0.06) },
        ] },
    }],
  };
  const antes = { sessoes: atual.sessoes, leads: atual.leads, dias: n,
    paginas: [{ ...ak1, rejeicoes: Math.round(ak1.entradas * 0.36) }, ak1b] };
  return { de, ate, antes_de: somaDias(de, -n), antes_ate: somaDias(de, -1), atual, antes };
}

function ladoDemo(nome: string | null, caminho: string | null, de: string, ate: string, fator: number, taxaLead: number): LadoComparar {
  const visitas = Math.round(1300 * fator * (diasEntre(de, ate) + 1) / 7);
  const leads = Math.round(visitas * taxaLead);
  return {
    pagina_id: null, de, ate, nome, caminho, visitas, leads, mql: Math.round(leads * 0.3), entradas: Math.round(visitas * 0.95),
    rejeicoes: Math.round(visitas * 0.44), leads_entrada: leads, vistas: Math.round(visitas * 1.05), rolagem_media: 55, visivel_ms_medio: 40000,
    lcp_p75: 2400, dias: diasEntre(de, ate) + 1,
    por_aparelho: [{ chave: 'mobile', visitas: Math.round(visitas * 0.86), leads: Math.round(leads * 0.8) }, { chave: 'desktop', visitas: Math.round(visitas * 0.14), leads: Math.round(leads * 0.2) }],
    por_origem: [{ chave: 'ig', visitas: Math.round(visitas * 0.65), leads: Math.round(leads * 0.7) }, { chave: 'fb', visitas: Math.round(visitas * 0.3), leads: Math.round(leads * 0.25) }],
  };
}

export function demoComparar(pa: string | null, deA: string, ateA: string, pb: string | null, deB: string, ateB: string): Comparacao2 {
  return { a: ladoDemo(pa, null, deA, ateA, 1, 0.1), b: ladoDemo(pb, null, deB, ateB, 0.9, 0.12) };
}

export function demoCalor(dispositivo: string): Calor {
  const r = sorteio('calor' + dispositivo);
  const pontos: [number, number, number, number][] = [];
  for (let i = 0; i < 900; i++) {
    const quente = r() < 0.5;
    pontos.push([quente ? 40 + r() * 20 : r() * 100, quente ? 0.08 + r() * 0.04 : r(), r() < 0.03 ? 1 : r() < 0.08 ? 2 : 0, quente ? 0 : 1]);
  }
  return {
    url: 'https://patrimoniobrasil.com.br/ak1/', visitas: 15200, largura: dispositivo === 'desktop' ? 1366 : 390, altura_doc: dispositivo === 'desktop' ? 5200 : 9800,
    pontos, amostra: false, elementos: [['button[data-cta="topo"]', 'Quero participar'], ['img.foto-especialista', '']],
    contagem: { cliques: 21400, raiva: 160, mortos: 1450, fixos: 900 },
    alcance: Array.from({ length: 21 }, (_, i) => Math.round(15200 * Math.max(0.2, 1 - i * 0.04))),
    top: [{ sel: 'button[data-cta="topo"]', txt: 'Quero participar', n: 2900, raiva: 41, morto: 0, fixo: false },
      { sel: 'div.janela-formulario', txt: '', n: 900, raiva: 0, morto: 0, fixo: true }],
    captura: null,
  };
}

export function demoLab(): Lab {
  const t = (nota: number, lcp: number) => ({
    medido_em: new Date().toISOString(), nota, notas: { desempenho: nota, acessibilidade: 88, praticas: 96, seo: 92 },
    lcp_ms: lcp, fcp_ms: Math.round(lcp * 0.55), tbt_ms: 310, si_ms: Math.round(lcp * 0.9), cls: 0.04,
    oportunidades: [{ id: 'render-blocking-resources', titulo: 'Elimine recursos que bloqueiam a renderização (demonstração)', ms: 1200 },
      { id: 'uses-optimized-images', titulo: 'Codifique as imagens de forma eficiente (demonstração)', ms: 640 }],
    erro: null,
  });
  const serie = (base: number) => Array.from({ length: 10 }, (_, i) => ({ quando: somaDias('2026-09-26', i) + 'T09:40:00Z', nota: base + (i % 3) * 2, lcp_ms: 3000 - i * 40 }));
  return {
    ligado: true, coleta: true,
    paginas: [
      { pagina_id: 11, nome: 'AK1', caminho: '/ak1/', estrategia: 'mobile', ultimo: t(54, 4100), anterior_nota: 58, serie: serie(52) },
      { pagina_id: 11, nome: 'AK1', caminho: '/ak1/', estrategia: 'desktop', ultimo: t(86, 1500), anterior_nota: 85, serie: serie(84) },
      { pagina_id: 12, nome: 'Obrigado', caminho: '/obrigado/', estrategia: 'mobile', ultimo: { ...t(0, 0), nota: null, lcp_ms: null, fcp_ms: null, si_ms: null, notas: null, oportunidades: [], erro: 'HTTP 429' }, anterior_nota: 71, serie: serie(70) },
    ],
  };
}

export function demoLeads(): LeadsPessoas {
  return {
    base: true, pode_abrir: true, leads_web: 1510, navegadores_lead: 1480, com_ref: 1320, pessoas: 1290, mql: 410, nao_mql: 650,
    lista: [
      { ref: 'pe_00000000000000000000000000demo01', pessoa_id: '00000000-0000-4000-8000-00000000de01', quando: new Date().toISOString(), mql: true, nao_mql: false },
      { ref: 'pe_00000000000000000000000000demo02', pessoa_id: '00000000-0000-4000-8000-00000000de02', quando: new Date().toISOString(), mql: false, nao_mql: true },
    ],
  };
}

export function demoConnect(de: string, ate: string): Connect {
  const v = demoVisao(de, ate).kpis.sessoes;
  return {
    trafego: true, cliques_link: true,
    campanhas: [
      { campanha: campanhaDemo(UTM_CAMPANHA_A).campanha, campanha_externa: campanhaDemo(UTM_CAMPANHA_A).campanha_id ?? '', plataforma: 'meta', pagina: 'ak1', gasto: 8200, impressoes: 410000,
        cliques_link: Math.round(v * 0.75), dias_com_gasto: diasEntre(de, ate) + 1, page_views: Math.round(v * 0.55), engajadas: Math.round(v * 0.3), leads: Math.round(v * 0.06),
        connect_rate: 0.733, conversao: 0.109 },
      { campanha: campanhaDemo(UTM_CAMPANHA_B).campanha, campanha_externa: campanhaDemo(UTM_CAMPANHA_B).campanha_id ?? '', plataforma: 'meta', pagina: null, gasto: 4100, impressoes: 260000,
        cliques_link: Math.round(v * 0.5), dias_com_gasto: diasEntre(de, ate) + 1, page_views: Math.round(v * 0.3), engajadas: Math.round(v * 0.15), leads: Math.round(v * 0.03),
        connect_rate: 0.6, conversao: 0.1 },
    ],
    sem_campanha: { page_views: Math.round(v * 0.04), campanhas: 1 },
    anuncios: demoOrigem(de, ate).anuncios.map((a) => ({ anuncio: a.anuncio, anuncio_id: a.anuncio_id, campanha: a.campanha, page_views: a.sessoes, engajadas: a.engajadas, leads: a.leads })),
  };
}
