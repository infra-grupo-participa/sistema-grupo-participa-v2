// Marketing > Web > Melhorias: os ACHADOS AUTOMÁTICOS, portados do Radar do Luiz (pacote de 05/10/2026,
// sistemas/radar/_interface/src/lib/oportunidades.ts, compilado em sistemas/radar/rotina/regras.mjs). Mesmas regras e
// mesmos limiares; cada função cita a regra de origem. Os números vêm de public.mkt_web_melhorias (migration 20261005q),
// no mesmo formato do radar.api_oportunidades / radar.api_leitura.
// O que NÃO veio: a regra "publicacoes" (antes e depois de cada publicação): as publicações/deploys do FTP do Luiz não
// entram nesta fase (decisão do Victor). Os "provas" do Radar (links para gravações, sessões) viraram abas da Web;
// gravação não existe aqui.
// Domínio puro: sem React, sem Supabase.
import { compararComRegua, compararTaxas, maisFraco, apelidoSecao, type Nivel } from './analise';
import type { BaseMelhorias, LeituraMelhorias, PaginaMelhorias } from './tipos';

export type TipoAchado = 'dobra' | 'promessa' | 'botao' | 'secao' | 'formulario' | 'friccao' | 'velocidade' | 'mql_le' | 'botao_converte';

/** NOME_TIPO do oportunidades.ts */
export const NOME_TIPO: Record<TipoAchado, string> = {
  dobra: 'Primeira dobra', promessa: 'Promessa do anúncio', botao: 'Botão que ninguém vê', secao: 'Leitura por seção',
  formulario: 'Formulário', friccao: 'Fricção', velocidade: 'Velocidade', mql_le: 'O que o MQL lê', botao_converte: 'Qual botão converte',
};

/** aba da Web onde conferir o achado (no Radar, "provas") */
export type AbaWeb = 'paginas' | 'origem' | 'velocidade' | 'leitura' | 'problemas' | 'formulario' | 'calor';

export interface Achado {
  id: string; tipo: TipoAchado; pagina_id: number; confianca: Nivel; titulo: string; numeros: string; fazer: string;
  /** teto de leads por semana que o conserto pode trazer (0 nos aprendizados) */
  ganho: number; dica?: string; base?: string; ver: AbaWeb[];
}

export interface ResultadoAchados { oportunidades: Achado[]; aprendizados: Achado[]; paginas: number }

// ─── formato (formato.ts do Radar) ───────────────────────────────────────────────────────────────────────────────────
const taxa = (a: number, b: number) => (b ? a / b : 0);
const n = (v: unknown) => Number(v) || 0;
const fmtN = (v: number, casas = 0) => Number(v || 0).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas });
const pctDe = (fracao: number, casas = 1) => (fracao * 100).toLocaleString('pt-BR', { maximumFractionDigits: casas }) + '%';
const mediana = (v: number[]) => { const o = [...v].sort((a, b) => a - b); return o.length ? o[Math.floor((o.length - 1) / 2)] : 0; };

interface Ctx {
  pg: PaginaMelhorias; antes?: PaginaMelhorias; leitura?: LeituraMelhorias; nome: string; semanas: number; periodo: string; base: string;
}

const engajados = (r: { entradas: number; rejeicoes: number }) => Math.max(0, n(r.entradas) - n(r.rejeicoes));
/** taxa de lead de quem se engajou: o que uma entrada "recuperada" renderia */
const leadDoEngajado = (r: { entradas: number; rejeicoes: number; leads: number }) => taxa(n(r.leads), engajados(r));
const id = (c: Ctx, sufixo: string) => c.pg.pagina_id + '|' + sufixo;

// ─── dobra (oportunidades.ts: dobra) ─────────────────────────────────────────────────────────────────────────────────
// celular x desktop: 30+ entradas de cada lado, rejeição do celular 10 pontos acima e selo não fraco;
// rejeição que subiu contra o período anterior: 30+ entradas nos dois, 8 pontos acima e selo não fraco.
function dobra(c: Ctx): Achado[] {
  const out: Achado[] = [];
  const cel = c.pg.por_aparelho?.find((a) => a.dispositivo === 'mobile');
  const desk = c.pg.por_aparelho?.find((a) => a.dispositivo === 'desktop');
  if (cel && desk && n(cel.entradas) >= 30 && n(desk.entradas) >= 30) {
    const t = compararTaxas(n(desk.rejeicoes), n(desk.entradas), n(cel.rejeicoes), n(cel.entradas));
    if (t.b - t.a >= 0.1 && t.nivel !== 'fraco') out.push({
      id: id(c, 'dobra-celular'), tipo: 'dobra', pagina_id: c.pg.pagina_id, confianca: t.nivel, base: c.base,
      titulo: `No celular, a primeira dobra da ${c.nome} segura menos: ${pctDe(t.b, 0)} saem sem se engajar (no desktop, ${pctDe(t.a, 0)})`,
      numeros: `${fmtN(n(cel.rejeicoes))} de ${fmtN(n(cel.entradas))} entradas no celular contra ${fmtN(n(desk.rejeicoes))} de ${fmtN(n(desk.entradas))} no desktop, ${c.periodo}. Lead de quem entra: ${pctDe(taxa(n(cel.leads), n(cel.entradas)))} no celular e ${pctDe(taxa(n(desk.leads), n(desk.entradas)))} no desktop.`,
      fazer: 'Rever o topo no celular: título, imagem e quanto a página demora para aparecer. Uma mudança grande por vez, com a verba igual.',
      ganho: (n(cel.entradas) * (t.b - t.a) * leadDoEngajado(cel)) / c.semanas,
      ver: ['calor', 'leitura', 'paginas'],
    });
  }
  if (c.antes && n(c.antes.entradas) >= 30 && n(c.pg.entradas) >= 30) {
    const t = compararTaxas(n(c.antes.rejeicoes), n(c.antes.entradas), n(c.pg.rejeicoes), n(c.pg.entradas));
    if (t.b - t.a >= 0.08 && t.nivel !== 'fraco') out.push({
      id: id(c, 'dobra-subiu'), tipo: 'dobra', pagina_id: c.pg.pagina_id, confianca: t.nivel, base: c.base,
      titulo: `A rejeição da ${c.nome} subiu de ${pctDe(t.a, 0)} para ${pctDe(t.b, 0)}`,
      numeros: `${fmtN(n(c.pg.rejeicoes))} de ${fmtN(n(c.pg.entradas))} entradas saíram sem se engajar, ${c.periodo}; no período anterior, ${fmtN(n(c.antes.rejeicoes))} de ${fmtN(n(c.antes.entradas))}.`,
      fazer: 'Mudou o anúncio, o público ou a página? Confira as origens antes de mexer na página.',
      ganho: (n(c.pg.entradas) * (t.b - t.a) * taxa(n(c.pg.leads_entrada), Math.max(1, n(c.pg.entradas) - n(c.pg.rejeicoes)))) / c.semanas,
      ver: ['origem', 'paginas'],
    });
  }
  return out;
}

// ─── promessa (oportunidades.ts: promessa) ───────────────────────────────────────────────────────────────────────────
// por criativo (utm_content) ou campanha: 30+ entradas dele e das outras, rejeição 12 pontos acima das outras, não fraco.
function promessa(c: Ctx): Achado[] {
  const out: Achado[] = [];
  for (const cr of c.pg.por_criativo ?? []) {
    const e = n(cr.entradas);
    const restoE = n(c.pg.entradas) - e, restoR = n(c.pg.rejeicoes) - n(cr.rejeicoes), restoL = n(c.pg.leads_entrada) - n(cr.leads);
    if (e < 30 || restoE < 30 || (!cr.criativo && cr.campanha === '(sem campanha)')) continue;
    const t = compararTaxas(restoR, restoE, n(cr.rejeicoes), e);
    if (t.b - t.a < 0.12 || t.nivel === 'fraco') continue;
    const rotulo = cr.criativo || cr.campanha;
    out.push({
      id: id(c, 'promessa-' + cr.campanha + '-' + cr.criativo), tipo: 'promessa', pagina_id: c.pg.pagina_id, confianca: t.nivel, base: c.base,
      dica: cr.criativo ? `Código do anúncio (utm_content): ${cr.criativo}; campanha: ${cr.campanha}` : undefined,
      titulo: `A promessa do criativo “${rotulo}” não casa com a ${c.nome}: ${pctDe(t.b, 0)} saem sem se engajar (as outras entradas, ${pctDe(t.a, 0)})`,
      numeros: `${fmtN(n(cr.rejeicoes))} de ${fmtN(e)} entradas por esse criativo contra ${fmtN(restoR)} de ${fmtN(restoE)} das outras, ${c.periodo}. Lead: ${pctDe(taxa(n(cr.leads), e))} contra ${pctDe(taxa(restoL, restoE))}.`,
      fazer: 'Fazer o título da página repetir a promessa do anúncio, ou dar a esse criativo uma página dele. Se ele traz o público errado, o conserto é no anúncio.',
      ganho: (e * (t.b - t.a) * taxa(restoL, Math.max(1, restoE - restoR))) / c.semanas,
      ver: ['origem', 'paginas'],
    });
  }
  return out;
}

// ─── botao (oportunidades.ts: botao) ─────────────────────────────────────────────────────────────────────────────────
// 30+ páginas vistas no celular e menos de 60% chegam a ver o primeiro botão; selo contra a régua de 60%.
function botao(c: Ctx): Achado[] {
  const l = c.leitura;
  const cel = l?.primeiro_cta.find((x) => x.dispositivo === 'mobile');
  const primeiro = l ? [...l.ctas].sort((a, b) => a.ordem - b.ordem)[0] : undefined;
  if (!l || !cel || !primeiro || n(cel.medidas) < 30) return [];
  const viu = taxa(n(cel.viram), n(cel.medidas));
  if (viu >= 0.6) return [];
  const desk = l.primeiro_cta.find((x) => x.dispositivo === 'desktop');
  const semVer = n(cel.ficaram_sem_ver);
  const leadDeQuemVe = taxa(n(cel.leads_de_quem_viu), Math.max(1, n(cel.ficaram) - semVer));
  const regua = compararComRegua(n(cel.viram), n(cel.medidas), 0.6);
  return [{
    id: id(c, 'botao'), tipo: 'botao', pagina_id: c.pg.pagina_id, confianca: regua.nivel, base: c.base,
    titulo: `No celular, só ${pctDe(viu, 0)} chegam a ver o primeiro botão da ${c.nome} (“${primeiro.cta}”)`,
    numeros: `${fmtN(n(cel.viram))} de ${fmtN(n(cel.medidas))} páginas vistas no celular` +
      (desk && n(desk.medidas) >= 30 ? `; no desktop, ${fmtN(n(desk.viram))} de ${fmtN(n(desk.medidas))}` : '') +
      `, ${c.periodo}. Dos ${fmtN(n(cel.ficaram))} que ficaram 10 s ou mais, ${fmtN(semVer)} não viram o botão.`,
    fazer: 'Subir o botão para a primeira dobra do celular, ou repetir o botão antes do ponto em que a leitura cai. Quem não vê o botão não tem como clicar.',
    ganho: (semVer * leadDeQuemVe) / c.semanas,
    ver: ['calor', 'leitura'],
  }];
}

// ─── secao (oportunidades.ts: secao) ─────────────────────────────────────────────────────────────────────────────────
// 50+ medidas; pior passagem entre seções com 30+ chegando antes: perda >= 30% e 12 pontos acima da mediana das outras;
// 20+ que seguem e 20+ que param; quem segue vira lead mais; selo = o mais fraco entre a queda e a conversão.
function secao(c: Ctx): Achado[] {
  const l = c.leitura;
  if (!l || n(l.medidas) < 50) return [];
  const s = l.secoes.filter((x) => x.ordem < 999).sort((a, b) => a.ordem - b.ordem);
  const quedas: { i: number; q: number }[] = [];
  for (let i = 2; i < s.length; i++) {
    const antes = n(s[i - 1].chegaram);
    if (antes >= 30) quedas.push({ i, q: 1 - n(s[i].chegaram) / antes });
  }
  if (quedas.length < 2) return [];
  const pior = quedas.reduce((m, x) => (x.q > m.q ? x : m));
  const normal = mediana(quedas.filter((x) => x !== pior).map((x) => x.q));
  if (pior.q < 0.3 || pior.q - normal < 0.12) return [];
  const fica = s[pior.i - 1], segue = s[pior.i];
  const nSegue = n(segue.viram), nPara = n(fica.viram) - n(segue.viram);
  const lSegue = n(segue.viram_lead), lPara = n(fica.viram_lead) - n(segue.viram_lead);
  if (nSegue < 20 || nPara < 20 || lPara < 0 || lPara > nPara) return [];
  const conv = compararTaxas(lPara, nPara, lSegue, nSegue);
  if (conv.b <= conv.a) return [];
  const queda = compararComRegua(Math.round(n(fica.chegaram) * pior.q), n(fica.chegaram), normal);
  const nomeFica = apelidoSecao(fica.secao), nomeSegue = apelidoSecao(segue.secao);
  return [{
    id: id(c, 'secao-' + fica.secao), tipo: 'secao', pagina_id: c.pg.pagina_id, confianca: maisFraco(queda.nivel, conv.nivel), base: c.base,
    titulo: `A leitura da ${c.nome} morre depois de “${nomeFica}”: ${pctDe(pior.q, 0)} de quem chega nela não segue para “${nomeSegue}”`,
    numeros: `${fmtN(n(segue.chegaram))} de ${fmtN(n(fica.chegaram))} páginas vistas passam de “${nomeFica}” para “${nomeSegue}”, ${c.periodo}. Nas outras passagens da página, a perda fica em ${pctDe(normal, 0)}. Quem para ali vira lead em ${pctDe(conv.a)} das vezes; quem segue, em ${pctDe(conv.b)}.`,
    fazer: `Reescrever ou encurtar “${nomeFica}” e a ponte para “${nomeSegue}”. Prova e credibilidade nunca saem da página.`,
    ganho: Math.max(0, n(fica.chegaram) * (pior.q - normal) * (conv.b - conv.a)) / c.semanas,
    dica: `Nomes no código da página: “${fica.secao}” e “${segue.secao}” (o data-secao, o id ou a classe da <section>).`,
    ver: ['leitura', 'calor'],
  }];
}

// ─── formulario (oportunidades.ts: formulario + seloDoCampo) ─────────────────────────────────────────────────────────
// 30+ começaram; o campo onde mais param leva 10% ou mais de quem começa.
function seloDoCampo(campos: LeituraMelhorias['form']['campos'], pior: LeituraMelhorias['form']['campos'][number]): Nivel {
  const outros = campos.filter((x) => x !== pior);
  const base = (x: typeof pior) => n(x.tocaram ?? x.focaram);
  const t = compararTaxas(outros.reduce((s, x) => s + n(x.pararam), 0), outros.reduce((s, x) => s + base(x), 0), n(pior.pararam), base(pior));
  return t.b > t.a ? t.nivel : 'fraco';
}
function formulario(c: Ctx): Achado[] {
  const f = c.leitura?.form;
  if (!f || n(f.comecaram) < 30) return [];
  const comecaram = n(f.comecaram), enviaram = n(f.enviaram);
  const campos = [...f.campos].sort((a, b) => a.ordem - b.ordem);
  if (!campos.length) return [];
  const pior = campos.reduce((m, x) => (n(x.pararam) > n(m.pararam) ? x : m), campos[0]);
  if (n(pior.pararam) / comecaram < 0.1) return [];
  const enviaDepois = Math.min(1, taxa(enviaram, Math.max(1, n(pior.tocaram ?? pior.focaram) - n(pior.pararam))));
  const comErro = [...campos].sort((a, b) => n(b.com_erro) - n(a.com_erro))[0];
  return [{
    id: id(c, 'form-' + pior.campo), tipo: 'formulario', pagina_id: c.pg.pagina_id, confianca: seloDoCampo(campos, pior), base: c.base,
    titulo: `O formulário da ${c.nome} perde gente no campo “${pior.campo}”: ${fmtN(n(pior.pararam))} de ${fmtN(comecaram)} que começam param nele`,
    numeros: `Enviam ${fmtN(enviaram)} de ${fmtN(comecaram)} que começam a preencher (${pctDe(taxa(enviaram, comecaram), 0)}), ${c.periodo}.` +
      (comErro && n(comErro.com_erro) >= 5 ? ` O campo “${comErro.campo}” deu erro de validação em ${fmtN(n(comErro.com_erro))} preenchimentos.` : ''),
    fazer: `Tirar o campo “${pior.campo}”, deixá-lo opcional ou explicar por que ele é pedido. Campo sensível pede formulário em etapas: primeiro o fácil.`,
    ganho: (n(pior.pararam) * enviaDepois) / c.semanas,
    ver: ['formulario'],
  }];
}

// ─── friccao (oportunidades.ts: friccao) ─────────────────────────────────────────────────────────────────────────────
// 20+ visitas engajadas com fricção (raiva ou erro) e 30+ sem; quem não esbarra converte mais, selo não fraco.
function friccao(c: Ctx): Achado[] {
  const fr = c.pg.friccao;
  if (!fr || n(fr.com_friccao) < 20 || n(fr.sem_friccao) < 30) return [];
  const t = compararTaxas(n(fr.friccao_leads), n(fr.com_friccao), n(fr.sem_leads), n(fr.sem_friccao));
  if (t.b <= t.a || t.nivel === 'fraco') return [];
  return [{
    id: id(c, 'friccao'), tipo: 'friccao', pagina_id: c.pg.pagina_id, confianca: t.nivel, base: c.base,
    titulo: `Na ${c.nome}, quem esbarra em clique de raiva ou erro vira lead em ${pctDe(t.a, 0)} das vezes; quem não esbarra, em ${pctDe(t.b, 0)}`,
    numeros: `${fmtN(n(fr.friccao_leads))} de ${fmtN(n(fr.com_friccao))} visitas engajadas com fricção (${fmtN(n(fr.com_raiva))} com clique de raiva, ${fmtN(n(fr.com_erro))} com erro de JavaScript) contra ${fmtN(n(fr.sem_leads))} de ${fmtN(n(fr.sem_friccao))} sem, ${c.periodo}.`,
    fazer: 'Consertar primeiro o que mais custa lead, não o que mais aparece: veja em Cliques e erros qual elemento e qual erro.',
    ganho: (n(fr.com_friccao) * (t.b - t.a)) / c.semanas,
    ver: ['problemas', 'calor'],
  }];
}

// ─── velocidade (oportunidades.ts: velocidade) ───────────────────────────────────────────────────────────────────────
// entradas com LCP bom (até 2,5 s) x lentas: 30+ de cada, rejeição das lentas 8 pontos acima, não fraco.
function velocidade(c: Ctx): Achado[] {
  const lcp = c.pg.lcp ?? [];
  const bom = lcp.find((x) => x.faixa === 'bom');
  const lentas = lcp.filter((x) => x.faixa !== 'bom').reduce((t, x) => ({
    entradas: t.entradas + n(x.entradas), rejeicoes: t.rejeicoes + n(x.rejeicoes), leads: t.leads + n(x.leads),
  }), { entradas: 0, rejeicoes: 0, leads: 0 });
  if (!bom || n(bom.entradas) < 30 || lentas.entradas < 30) return [];
  const t = compararTaxas(n(bom.rejeicoes), n(bom.entradas), lentas.rejeicoes, lentas.entradas);
  if (t.b - t.a < 0.08 || t.nivel === 'fraco') return [];
  return [{
    id: id(c, 'velocidade'), tipo: 'velocidade', pagina_id: c.pg.pagina_id, confianca: t.nivel, base: c.base,
    titulo: `A lentidão custa atenção na ${c.nome}: quando a primeira dobra passa de 2,5 s, ${pctDe(t.b, 0)} saem sem se engajar (quando é rápida, ${pctDe(t.a, 0)})`,
    numeros: `${fmtN(lentas.rejeicoes)} de ${fmtN(lentas.entradas)} entradas lentas contra ${fmtN(n(bom.rejeicoes))} de ${fmtN(n(bom.entradas))} rápidas, ${c.periodo}. ${pctDe(taxa(lentas.entradas, lentas.entradas + n(bom.entradas)), 0)} das entradas medidas pegam a página lenta.`,
    fazer: 'Imagem do topo, fonte e scripts no carregamento costumam explicar. Veja o teste do Google na aba Velocidade e ataque o primeiro item da lista.',
    ganho: (lentas.entradas * (t.b - t.a) * leadDoEngajado(bom)) / c.semanas,
    ver: ['velocidade'],
  }];
}

// ─── aprendizados (oportunidades.ts: oQueOMqlLe, qualBotaoConverte) ──────────────────────────────────────────────────
// 15+ medidas de MQL e 15+ de lead que não qualificou; seção (fora a primeira) que o MQL vê 12 pontos mais.
function oQueOMqlLe(c: Ctx): Achado[] {
  const l = c.leitura;
  if (!l) return [];
  const mql = n(l.medidas_mql), resto = n(l.medidas_lead) - mql;
  if (mql < 15 || resto < 15) return [];
  const comp = l.secoes.filter((x) => x.ordem < 999).sort((a, b) => a.ordem - b.ordem).slice(1)
    .map((x) => ({ x, t: compararTaxas(n(x.viram_lead) - n(x.viram_mql), resto, n(x.viram_mql), mql) }))
    .filter((y) => y.t.b - y.t.a >= 0.12)
    .sort((a, b) => b.t.b - b.t.a - (a.t.b - a.t.a));
  const melhor = comp.find((y) => y.t.nivel !== 'fraco') || comp[0];
  if (!melhor) return [];
  return [{
    id: id(c, 'mql-' + melhor.x.secao), tipo: 'mql_le', pagina_id: c.pg.pagina_id, confianca: melhor.t.nivel, ganho: 0,
    dica: `Nome no código da página: “${melhor.x.secao}” (o data-secao, o id ou a classe da <section>).`,
    titulo: `Na ${c.nome}, o MQL lê “${apelidoSecao(melhor.x.secao)}”: ${pctDe(melhor.t.b, 0)} deles param nessa seção, contra ${pctDe(melhor.t.a, 0)} dos leads que não qualificam`,
    numeros: `${fmtN(n(melhor.x.viram_mql))} de ${fmtN(mql)} páginas vistas por quem virou MQL contra ${fmtN(n(melhor.x.viram_lead) - n(melhor.x.viram_mql))} de ${fmtN(resto)} por quem virou lead e não qualificou, ${c.periodo}.`,
    fazer: 'É a seção que separa quem qualifica: vale subir ela na página e levar a mesma ideia para o anúncio. A casa persegue MQL, não volume.',
    ver: ['leitura'],
  }];
}
// 10+ leads com clique em botão; régua de 70% para "decide cedo" (primeiro botão).
function qualBotaoConverte(c: Ctx): Achado[] {
  const l = c.leitura;
  const total = n(l?.leads_com_botao);
  if (!l || total < 10) return [];
  const b = [...l.ctas].filter((x) => n(x.leads) > 0).sort((x, y) => n(y.leads) - n(x.leads));
  if (b.length < 1) return [];
  const primeiro = [...l.ctas].sort((x, y) => x.ordem - y.ordem)[0];
  const fatia = taxa(n(primeiro?.leads), total);
  const regua = compararComRegua(n(primeiro?.leads), total, 0.7);
  return [{
    id: id(c, 'botoes'), tipo: 'botao_converte', pagina_id: c.pg.pagina_id, confianca: regua.nivel, ganho: 0,
    titulo: fatia >= 0.7
      ? `Na ${c.nome}, ${pctDe(fatia, 0)} dos leads clicam no primeiro botão: quem converte decide cedo`
      : `Na ${c.nome}, os botões depois do primeiro trazem ${pctDe(1 - fatia, 0)} dos leads: a página em camadas está trabalhando`,
    numeros: b.map((x) => `“${x.cta}”: ${fmtN(n(x.leads))} de ${fmtN(total)}`).join('; ') + ` leads com clique em botão, ${c.periodo}.`,
    fazer: fatia >= 0.7
      ? 'O topo carrega a decisão: teste título e botão do topo antes do resto. Os outros botões servem a quem precisa de prova.'
      : 'Manter prova e dúvidas antes dos botões do meio e do fim: é ali que o metódico decide.',
    ver: ['calor', 'leitura'],
  }];
}

/** a ordem da lista: os fracos vão para o fim; dentro de cada grupo, o maior ganho primeiro (ordemDosAchados) */
export const ordemDosAchados = (a: Achado, b: Achado) => Number(a.confianca === 'fraco') - Number(b.confianca === 'fraco') || b.ganho - a.ganho;

/** analisar() do oportunidades.ts: página de obrigado e página com menos de 20 visitas ficam fora */
export function analisar(atual: BaseMelhorias | null, antes: BaseMelhorias | null, periodo: string): ResultadoAchados {
  if (!atual) return { oportunidades: [], aprendizados: [], paginas: 0 };
  const oportunidades: Achado[] = [], aprendizados: Achado[] = [];
  let paginas = 0;
  for (const pg of atual.paginas) {
    if (pg.funcao === 'obrigado' || n(pg.sessoes) < 20) continue;
    paginas++;
    const comDado = n(pg.dias) || n(atual.dias);
    const diasBase = Math.max(1, comDado);
    const c: Ctx = {
      pg, antes: antes?.paginas.find((x) => x.pagina_id === pg.pagina_id), leitura: atual.leituras?.find((l) => l.pagina_id === pg.pagina_id),
      nome: pg.nome, semanas: diasBase / 7, periodo, base: `pelos ${fmtN(diasBase)} ${diasBase === 1 ? 'dia' : 'dias'} com visitas`,
    };
    oportunidades.push(...dobra(c), ...promessa(c), ...botao(c), ...secao(c), ...formulario(c), ...friccao(c), ...velocidade(c));
    aprendizados.push(...oQueOMqlLe(c), ...qualBotaoConverte(c));
  }
  oportunidades.sort(ordemDosAchados);
  return { oportunidades, aprendizados, paginas };
}

/** "até 3,2": o teto de leads por semana (com menos de 0,05, não dá para dizer) (textoGanho) */
export function textoGanho(g: number): string {
  if (g < 0.05) return '';
  return 'até ' + g.toLocaleString('pt-BR', { maximumFractionDigits: g < 10 ? 1 : 0 });
}
