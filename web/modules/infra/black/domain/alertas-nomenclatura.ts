import type { Campanha, Conjunto, LinhaPerfil, TrafegoBlack } from './tipos';
import { linhaDaCampanha, linhaDoConjunto, noDoConjunto } from './linha-black';

export interface AlertaNomenclatura {
  chave: string;
  nome: string;
  tipo: 'Campanha' | 'Conjunto' | 'Anúncio' | 'UTM';
  regras: string[];
  ocorrencias: number;
}

const ETIQUETA = 'black-friday-2026-10';
/**
 * Padrão do Caio (guia de 15/10/2026): GESTOR | PROJETO | FASE | FRENTE | ... | CHAVE. FRENTE e OTIMIZAÇÃO são opcionais e
 * a posição muda, então cada campo é lido pelo VALOR, sem acento e em maiúsculas. Os dois formatos valem: com ou sem
 * C1/C2/C3 logo depois de BF26. A etapa só sai de campo exato, nunca de texto solto.
 */
const FASES = new Set(['ANTECIPACAO', 'AQUECIMENTO', 'CAPTACAO', 'DISTRIBUICAO', 'REMARKETING', 'CARRINHO']);
const MINIMO_CAMPOS = 3; // GESTOR, PROJETO e FASE
const GESTORES = new Set(['CF', 'RS', 'EF']);
/** Conjunto que ainda tem o nome antigo (a temperatura no começo) continua válido: o coletor não renomeia conjunto parado. */
const TEMPERATURAS = new Set(['PQ', 'PF', 'MIX', 'ADV']);
/** Iscas e a consultoria: o guia põe CONSULTORIA ao lado das 3 iscas de página. */
const ISCAS = ['CHECKUP', 'FUTUROMETRO', 'FLUXOGRAMA', 'CONSULTORIA'] as const;
/** Peças do C1 que o anúncio deve citar no nome. Os reels da distribuição levam a legenda do post: o guia manda usar o ID. */
const PECAS_C1 = ['TEASER', 'MANIFESTO'];
const normalizar = (s: string) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleUpperCase('pt-BR');
const camposBrutos = (s: string) => s.split('|').map((x) => x.trim()).filter(Boolean);
const temIsca = (s: string) => ISCAS.find((isca) => normalizar(s).includes(isca)) ?? null;

function regrasCampanha(c: Campanha): string[] {
  const r: string[] = [];
  const p = camposBrutos(c.nome);
  const n = p.map(normalizar);
  if (p[p.length - 1] !== ETIQUETA) r.push('R1');
  if (p.length < MINIMO_CAMPOS) r.push('R2');
  if (!GESTORES.has(n[0] ?? '')) r.push('R3');
  if (!n.includes('BF26')) r.push('R4');
  if (!n.some((x) => FASES.has(x))) r.push('R5');
  if (linhaDaCampanha(c) === null) r.push('R6');
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
  const eIsca = (l: string | null) => l === 'iscas' || l === 'consultoria' || l === 'c2';
  const iscaDoConjunto = (cj: Conjunto) => cj.iscaBanco ? temIsca(cj.iscaBanco) : temIsca(cj.nome);
  for (const c of trafego.campanhas) adicionar('Campanha', c.nome, regrasCampanha(c));
  for (const cj of trafego.conjuntos) {
    const campanha = campanhas.get(cj.campanhaId);
    const primeira = cj.nome.split(/[ |_-]+/).find(Boolean)?.toLocaleUpperCase('pt-BR') ?? '';
    // R8: o banco não reconheceu a peça ou etapa do conjunto e o nome também não segue o padrão antigo (PQ, PF, MIX, ADV).
    if (noDoConjunto(cj, campanha) === null && !TEMPERATURAS.has(primeira)) adicionar('Conjunto', cj.nome, ['R8']);
    if (eIsca(linhaDoConjunto(cj, campanha)) && !iscaDoConjunto(cj)) adicionar('Conjunto', cj.nome, ['R12']);
  }
  for (const ad of trafego.anuncios) {
    const cj = conjuntos.get(ad.conjuntoId);
    const campanha = cj ? campanhas.get(cj.campanhaId) : undefined;
    const nome = normalizar(ad.nome);
    const regras: string[] = [];
    const no = cj ? noDoConjunto(cj, campanha) : null;
    if ((no === 'teaser' || no === 'manifesto') && !PECAS_C1.some((x) => nome.includes(x))) regras.push('R9');
    if (cj && eIsca(linhaDoConjunto(cj, campanha))) {
      const iscaAd = temIsca(ad.nome); const iscaConjunto = iscaDoConjunto(cj);
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
