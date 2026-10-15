import type { Campanha, LinhaPerfil, TrafegoBlack } from './tipos';

export interface AlertaNomenclatura {
  chave: string;
  nome: string;
  tipo: 'Campanha' | 'Conjunto' | 'Anúncio' | 'UTM';
  regras: string[];
  ocorrencias: number;
}

const ETIQUETA = 'black-friday-2026-10';
const OBJETIVOS = new Set(['LEADS', 'VENDAS', 'REMARKETING', 'LEMBRETE', 'DISTRIBUIÇÃO', 'CARRINHO', 'AQUECIMENTO']);
const GESTORES = new Set(['CF', 'RS', 'EF']);
const TEMPERATURAS = new Set(['PQ', 'PF', 'MIX', 'ADV']);
const ISCAS = ['CHECKUP', 'FUTUROMETRO', 'FLUXOGRAMA'] as const;
const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleUpperCase('pt-BR');
const campos = (s: string) => s.split(' | ').map((x) => x.trim());
const temIsca = (s: string) => ISCAS.find((isca) => normalizar(s).includes(isca)) ?? null;

function regrasCampanha(c: Campanha): string[] {
  const r: string[] = [];
  const p = campos(c.nome);
  if (p[p.length - 1] !== ETIQUETA) r.push('R1');
  if (p.length !== 5 && p.length !== 6) r.push('R2');
  if (!GESTORES.has(p[0] ?? '')) r.push('R3');
  if (p[1] !== 'BF26') r.push('R4');
  if (!OBJETIVOS.has(p[2] ?? '')) r.push('R5');
  if (c.etapa == null) r.push('R6');
  if (c.conflito === true) r.push('R7');
  return r;
}

/** Regras de nomenclatura sobre o catálogo e perfil já carregados. Sem fixture de números ou nomes. */
export function alertasNomenclatura(trafego: TrafegoBlack, perfil: readonly LinhaPerfil[]): AlertaNomenclatura[] {
  const saida: AlertaNomenclatura[] = [];
  const adicionar = (tipo: AlertaNomenclatura['tipo'], nome: string, regras: string[], ocorrencias = 1) => {
    if (!regras.length) return;
    const chave = `${tipo}:${nome}`;
    const existente = saida.find((x) => x.chave === chave);
    if (existente) {
      existente.regras = [...new Set([...existente.regras, ...regras])];
      existente.ocorrencias = Math.max(existente.ocorrencias, ocorrencias);
    } else saida.push({ chave, nome, tipo, regras, ocorrencias });
  };
  const campanhas = new Map(trafego.campanhas.map((c) => [c.id, c]));
  const conjuntos = new Map(trafego.conjuntos.map((c) => [c.id, c]));
  for (const c of trafego.campanhas) adicionar('Campanha', c.nome, regrasCampanha(c));
  for (const cj of trafego.conjuntos) {
    const primeira = cj.nome.split(/[ |_-]+/).find(Boolean)?.toLocaleUpperCase('pt-BR') ?? '';
    adicionar('Conjunto', cj.nome, TEMPERATURAS.has(primeira) ? [] : ['R8']);
    const campanha = campanhas.get(cj.campanhaId);
    if (campanha?.etapa === 'C2' && campanha.subtipo === 'ISCA') {
      const iscaConjunto = temIsca(cj.nome);
      if (!iscaConjunto) adicionar('Conjunto', cj.nome, ['R12']);
    }
  }
  for (const ad of trafego.anuncios) {
    const cj = conjuntos.get(ad.conjuntoId);
    const campanha = cj ? campanhas.get(cj.campanhaId) : undefined;
    const nome = normalizar(ad.nome);
    const regras: string[] = [];
    if (campanha?.etapa === 'C1' && !['TEASER', 'MANIFESTO', 'REELS'].some((x) => nome.includes(x))) regras.push('R9');
    if (campanha?.etapa === 'C2' && campanha.subtipo === 'ISCA') {
      const iscaAd = temIsca(ad.nome); const iscaConjunto = cj ? temIsca(cj.nome) : null;
      if (!iscaAd) regras.push('R10');
      if (iscaAd && iscaConjunto && iscaAd !== iscaConjunto) regras.push('R11');
    }
    adicionar('Anúncio', ad.nome, regras);
  }
  const utm = new Map<string, number>(); let semUtm = 0;
  for (const l of perfil) {
    if (l.aCorrigir?.includes('utm_campaign_fora_do_padrao')) {
      const v = l.utmCampaign ?? '';
      utm.set(v, (utm.get(v) ?? 0) + 1);
    }
    if (l.aCorrigir?.includes('sem_utm')) semUtm += 1;
  }
  for (const [nome, ocorrencias] of utm) adicionar('UTM', nome || '(vazio)', ['U1'], ocorrencias);
  if (semUtm) adicionar('UTM', 'Sem UTM', ['U2'], semUtm);
  return saida;
}
