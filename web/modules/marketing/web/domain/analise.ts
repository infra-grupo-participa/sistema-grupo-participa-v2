// Marketing > Web: regras de análise portadas do Radar do Luiz (sistemas/radar/_interface/src/lib, pacote de
// 05/10/2026): estatistica.ts (teste de duas proporções e o selo forte/provável/fraco), funil.ts (a maior perda),
// secoes.ts (nome de gente para a seção), origens.ts (a origem em palavras) e a régua do Google para a velocidade.
// Domínio puro: sem React, sem Supabase.

// ─── Estatística (estatistica.ts) ────────────────────────────────────────────────────────────────────────────────────
/** forte = pode agir; provavel = vale testar; fraco = o número aponta, mas ainda pode ser acaso */
export type Nivel = 'forte' | 'provavel' | 'fraco';

export interface Comparacao { a: number; b: number; relativa: number; z: number; confiavel: boolean; poucas: boolean; nivel: Nivel }

/** forte: |z| >= 2,58 e 100+ do lado menor; provável: |z| >= 1,96 e 30+; fraco: o resto */
export function nivelDe(z: number, menorLado: number): Nivel {
  const az = Math.abs(z);
  if (az >= 2.58 && menorLado >= 100) return 'forte';
  if (az >= 1.96 && menorLado >= 30) return 'provavel';
  return 'fraco';
}

const FORCA: Record<Nivel, number> = { fraco: 0, provavel: 1, forte: 2 };
/** achado que depende de duas contas leva o selo da mais fraca */
export const maisFraco = (...n: Nivel[]): Nivel => n.reduce((m, x) => (FORCA[x] < FORCA[m] ? x : m), 'forte' as Nivel);

/** A diferença entre duas taxas (lead da página A x da B) é real ou ainda pode ser acaso? Teste de duas proporções. */
export function compararTaxas(sucessosA: number, totalA: number, sucessosB: number, totalB: number): Comparacao {
  const a = totalA ? sucessosA / totalA : 0;
  const b = totalB ? sucessosB / totalB : 0;
  const junto = totalA + totalB ? (sucessosA + sucessosB) / (totalA + totalB) : 0;
  const erro = Math.sqrt(junto * (1 - junto) * ((totalA ? 1 / totalA : 0) + (totalB ? 1 / totalB : 0)));
  const z = erro ? (b - a) / erro : 0;
  // regra de bolso: com menos de 30 sessões de um lado ou menos de 10 conversões somadas, nem vale ler
  const poucas = totalA < 30 || totalB < 30 || sucessosA + sucessosB < 10;
  return {
    a, b, z, poucas,
    relativa: a ? (b - a) / a : 0,
    confiavel: Math.abs(z) >= 1.96,
    nivel: poucas ? 'fraco' : nivelDe(z, Math.min(totalA, totalB)),
  };
}

/** Uma proporção contra uma régua fixa ("só 40% veem o botão", contra a régua de 60%): teste de uma proporção.
 *  z > 0 quando a proporção passa da régua; o selo não olha o lado (quem chama confere a direção). (estatistica.ts) */
export function compararComRegua(sucessos: number, total: number, regua: number): { p: number; z: number; nivel: Nivel } {
  const p = total ? sucessos / total : 0;
  const r = Math.min(0.99, Math.max(0.01, regua));
  const z = total ? (p - r) / Math.sqrt((r * (1 - r)) / total) : 0;
  return { p, z, nivel: nivelDe(z, total) };
}

export const ROTULO_NIVEL: Record<Nivel, string> = { forte: 'Diferença forte', provavel: 'Diferença provável', fraco: 'Pode ser acaso' };

// ─── Funil (funil.ts) ────────────────────────────────────────────────────────────────────────────────────────────────
/** qual passagem perde mais gente (índice da etapa de chegada), ou -1 */
export function maiorPerda(etapas: { sessoes: number }[]): number {
  let pior = -1;
  let menor = 2;
  etapas.forEach((e, i) => {
    if (i === 0 || !etapas[i - 1].sessoes) return;
    const p = e.sessoes / etapas[i - 1].sessoes;
    if (p < menor) { menor = p; pior = i; }
  });
  return pior;
}

// ─── Seções (secoes.ts) ──────────────────────────────────────────────────────────────────────────────────────────────
const CASA: Record<string, string> = {
  topo: 'Topo da página', hero: 'Topo da página', inicio: 'Topo da página', header: 'Topo da página', cabecalho: 'Topo da página', capa: 'Topo da página',
  dobra: 'Primeira dobra', 'primeira-dobra': 'Primeira dobra',
  padrao: 'O caminho padrão', caminho: 'O outro caminho', 'outro-caminho': 'O outro caminho', virada: 'A virada',
  filtro: 'Para quem é', 'para-quem': 'Para quem é', 'para-quem-e': 'Para quem é', publico: 'Para quem é',
  oque: 'O que é', 'o-que-e': 'O que é',
  especialistas: 'Os especialistas', especialista: 'A especialista', experts: 'Os especialistas',
  prova: 'Provas', provas: 'Provas', 'prova-social': 'Provas', depoimentos: 'Depoimentos', depoimento: 'Depoimentos', resultados: 'Resultados',
  faq: 'Perguntas frequentes', perguntas: 'Perguntas frequentes', duvidas: 'Perguntas frequentes',
  final: 'Chamada final', 'cta-final': 'Chamada final', fechamento: 'Chamada final', cta: 'Chamada para ação',
  oferta: 'A oferta', preco: 'A oferta', investimento: 'A oferta', bonus: 'Bônus', garantia: 'Garantia',
  sobre: 'Sobre', 'quem-somos': 'Sobre', autor: 'Quem conduz', mentor: 'Quem conduz', mentora: 'Quem conduz',
  agenda: 'Programação', programacao: 'Programação', cronograma: 'Programação',
  beneficios: 'Benefícios', vantagens: 'Benefícios', 'como-funciona': 'Como funciona', passos: 'Como funciona', metodo: 'O método',
  problema: 'O problema', dor: 'O problema', dores: 'O problema', solucao: 'A solução',
  inscricao: 'Formulário de inscrição', formulario: 'Formulário de inscrição', form: 'Formulário de inscrição', cadastro: 'Formulário de inscrição',
  video: 'Vídeo', numeros: 'Números', historia: 'A história', contato: 'Contato', rodape: 'Rodapé', footer: 'Rodapé',
};

const ACENTO: Record<string, string> = {
  nao: 'não', secao: 'seção', padrao: 'padrão', duvidas: 'dúvidas', bonus: 'bônus', beneficios: 'benefícios', inscricao: 'inscrição',
  video: 'vídeo', videos: 'vídeos', historia: 'história', preco: 'preço', precos: 'preços', solucao: 'solução', metodo: 'método',
  conteudo: 'conteúdo', publico: 'público', voce: 'você', familia: 'família', patrimonio: 'patrimônio', sucessao: 'sucessão',
  avaliacao: 'avaliação', apresentacao: 'apresentação', programacao: 'programação', transformacao: 'transformação', numeros: 'números',
  decisao: 'decisão', protecao: 'proteção', imoveis: 'imóveis', heranca: 'herança', inventario: 'inventário', oque: 'o que', proximos: 'próximos',
};

/** "padrao" → "O caminho padrão"; "como-funciona" → "Como funciona"; "sec-3" → "Seção 3" */
export function apelidoSecao(tecnico: string): string {
  const chave = tecnico.trim().toLowerCase().replace(/^[#.]/, '').replace(/[_\s]+/g, '-');
  if (CASA[chave]) return CASA[chave];
  const numero = chave.match(/^(?:s|sec|secao|section|bloco|block|parte)-?(\d{1,3})$/);
  if (numero) return 'Seção ' + Number(numero[1]);
  const palavras = chave.split('-').filter(Boolean).map((p) => ACENTO[p] || p);
  if (!palavras.length) return tecnico;
  const frase = palavras.join(' ');
  return frase.charAt(0).toUpperCase() + frase.slice(1);
}

// ─── Origem (origens.ts, sem os logos) ───────────────────────────────────────────────────────────────────────────────
const META = 'Meta Ads';
const ORIGENS: Record<string, { nome: string; rede?: string }> = {
  ig: { nome: 'Instagram', rede: META }, instagram: { nome: 'Instagram', rede: META },
  fb: { nome: 'Facebook', rede: META }, facebook: { nome: 'Facebook', rede: META },
  an: { nome: 'Audience Network', rede: META }, audience_network: { nome: 'Audience Network', rede: META },
  th: { nome: 'Threads', rede: META }, threads: { nome: 'Threads', rede: META },
  msg: { nome: 'Messenger', rede: META }, messenger: { nome: 'Messenger', rede: META }, meta: { nome: META },
  google: { nome: 'Google Ads' }, googleads: { nome: 'Google Ads' }, gads: { nome: 'Google Ads' }, adwords: { nome: 'Google Ads' },
  youtube: { nome: 'YouTube' }, yt: { nome: 'YouTube' },
  whatsapp: { nome: 'WhatsApp' }, wpp: { nome: 'WhatsApp' }, wa: { nome: 'WhatsApp' }, zap: { nome: 'WhatsApp' },
  tiktok: { nome: 'TikTok' }, email: { nome: 'E-mail' }, 'e-mail': { nome: 'E-mail' }, mail: { nome: 'E-mail' },
};

/** utm_source em palavras ("ig" → "Instagram · Meta Ads"); o que não conhece fica como chegou */
export function nomeOrigem(valor?: string | null): string {
  if (!valor || valor === '(direto)' || valor === '(nenhum)') return 'Direto, sem UTM';
  const o = ORIGENS[valor.trim().toLowerCase()];
  return o ? (o.rede ? `${o.nome} · ${o.rede}` : o.nome) : valor;
}

/** id do anúncio do Meta curto para rótulo: os números só mudam no meio, então fica o fim */
export const codigoCurto = (id: string) => (/^\d{13,}$/.test(id) ? '…' + id.slice(-9) : id);

// ─── Velocidade (a régua do Google, p75) ─────────────────────────────────────────────────────────────────────────────
export type Vital = 'lcp' | 'inp' | 'cls';
export type Faixa = 'bom' | 'melhorar' | 'ruim';
/** LCP bom até 2,5 s, ruim acima de 4 s; INP bom até 200 ms, ruim acima de 500 ms; CLS bom até 0,1, ruim acima de 0,25 */
export const REGUA: Record<Vital, [number, number]> = { lcp: [2500, 4000], inp: [200, 500], cls: [0.1, 0.25] };

export function faixaVital(v: Vital, valor: number | null | undefined): Faixa | null {
  if (valor == null || Number.isNaN(valor)) return null;
  const [bom, ruim] = REGUA[v];
  return valor <= bom ? 'bom' : valor <= ruim ? 'melhorar' : 'ruim';
}

export const ROTULO_FAIXA: Record<Faixa, string> = { bom: 'Bom', melhorar: 'Precisa melhorar', ruim: 'Ruim' };

// ─── Contas simples das telas ────────────────────────────────────────────────────────────────────────────────────────
export const taxa = (parte: number, total: number) => (total ? parte / total : 0);

/** 0,1234 → "12,3%"; sem total, "–" */
export const pct = (parte: number, total: number, casas = 1) =>
  total ? (parte / total * 100).toLocaleString('pt-BR', { maximumFractionDigits: casas }) + '%' : '–';

/** milissegundos em "8 s" ou "1 min 05 s" */
export function duracao(ms: number | null | undefined): string {
  const s = Math.round(Math.max(0, ms || 0) / 1000);
  return s < 60 ? s + ' s' : Math.floor(s / 60) + ' min ' + String(s % 60).padStart(2, '0') + ' s';
}

/** milissegundos de velocidade: "2,1 s" acima de 1 s, "180 ms" abaixo */
export function msVital(ms: number | null | undefined): string {
  if (ms == null) return '–';
  return ms >= 1000 ? (ms / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + ' s' : Math.round(ms) + ' ms';
}

export const num = (n: number | null | undefined) => Number(n || 0).toLocaleString('pt-BR');
