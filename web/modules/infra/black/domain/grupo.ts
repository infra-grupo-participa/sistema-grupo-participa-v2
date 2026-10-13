// Cards de MQL e de ingresso no grupo de WhatsApp (contrato da B, dados_black_grupo) e o recorte que a tela manda
// ao servidor (p_recorte). As contas de pessoa única e de ingresso são do servidor; aqui só a razão, soma sobre
// soma do mesmo período e do mesmo recorte. Divisão por zero ou por null = Sem dado, nunca zero.
import { taxa, type Taxa } from './metricas';
import {
  ROTULO_FUNIL,
  type FiltroCanal, type FiltroFunil, type GrupoResumoBlack, type Isca, type Porta, type Recorte, type RecorteGrupo,
  type SegmentoGrupo, type TrafegoBlack, type Valor,
} from './tipos';

/** Rótulo dos cards quando há recorte: a conta passa a ser cruzada (dos leads do recorte, quem está no grupo). */
export const ROTULO_CRUZADO = 'dos leads deste nó, quantos estão no grupo';

/**
 * Recorte pronto para o servidor, ou o motivo de não haver (o card mostra Sem dado com o motivo).
 * `descricao` = o que o card mostra do recorte (nome exato do item escolhido); ausente sem recorte.
 */
export type RecorteServidor = { ok: true; recorte: RecorteGrupo | null; descricao?: string } | { ok: false; motivo: string };

const PORTA_DO_FUNIL: Record<'consultoria' | 'iscas' | 'c3', Porta> = { consultoria: 'consultoria', iscas: 'isca', c3: 'inscricao_direta' };

/**
 * Nó ou filtro da tela -> p_recorte. Prioridade do mais fino para o mais grosso: anúncio, conjunto, campanha
 * (sempre o id do Meta, o que vem depois do | na utm; o id interno de mkt_trafego não serve), isca, porta e funil.
 * Sem nada escolhido = null (conta simples, sem cruzar). O grupo não tem recorte por canal: com canal escolhido,
 * não há número (devolver o total seria mostrar um número de outro recorte).
 */
export function recorteGrupoDe(n: {
  funil: FiltroFunil; canal: FiltroCanal; porta?: Porta | null; isca?: Isca | null;
  campanhaMeta?: string | null; conjuntoMeta?: string | null; anuncioMeta?: string | null;
}): RecorteServidor {
  if (n.canal !== 'todos') return { ok: false, motivo: 'O grupo não se divide por canal: o servidor não tem esse recorte.' };
  if (n.anuncioMeta) return { ok: true, recorte: { tipo: 'anuncio', valor: n.anuncioMeta } };
  if (n.conjuntoMeta) return { ok: true, recorte: { tipo: 'conjunto', valor: n.conjuntoMeta } };
  if (n.campanhaMeta) return { ok: true, recorte: { tipo: 'campanha', valor: n.campanhaMeta } };
  if (n.isca) return { ok: true, recorte: { tipo: 'isca', valor: n.isca } };
  if (n.porta) return { ok: true, recorte: { tipo: 'porta', valor: n.porta } };
  if (n.funil === 'todos') return { ok: true, recorte: null };
  if (n.funil === 'c1') return { ok: false, motivo: 'O C1 é distribuição: não gera cadastro nem entrada no grupo.' };
  return { ok: true, recorte: { tipo: 'porta', valor: PORTA_DO_FUNIL[n.funil] } };
}

type TrafegoIds = Pick<TrafegoBlack, 'campanhas' | 'conjuntos' | 'anuncios' | 'paginas'>;

/**
 * Recorte da tela inteira -> p_recorte. O item escolhido em Criativos (anúncio, conjunto, campanha, página) vence o
 * funil, do mais fino para o mais grosso. O servidor só entende o id do Meta: o anúncio traz o dele
 * (anuncio_externa); campanha e conjunto só quando dados_black_trafego devolver campanha_externa / conjunto_externa.
 * Sem o id do Meta, Sem dado com o motivo: nunca o número do funil no lugar (seria outro recorte) e nunca o id
 * deduzido pelos leads.
 */
export function recorteDaTela(r: Pick<Recorte, 'funil' | 'canal' | 'criativos'>, t: TrafegoIds | null): RecorteServidor {
  const base = { funil: r.funil, canal: r.canal };
  if (r.canal !== 'todos') return recorteGrupoDe(base);
  const f = r.criativos;
  const com = (x: RecorteServidor, descricao: string): RecorteServidor => (x.ok ? { ...x, descricao } : x);
  if ((f.anuncio || f.conjunto || f.campanha || f.pagina) && !t) {
    return { ok: false, motivo: 'Aguardando o tráfego para achar o id do Meta do item escolhido.' };
  }
  if (t && f.anuncio) {
    const a = t.anuncios.find((x) => x.id === f.anuncio);
    if (!a) return { ok: false, motivo: 'O anúncio escolhido não está no tráfego do período.' };
    // O criativo é o conjunto de anúncios de mesmo nome (um por conjunto). Com conjunto ou campanha escolhidos sobra
    // um só; sem eles, o servidor (um id do Meta por recorte) não consegue somar vários anúncios.
    const irmaos = t.anuncios.filter((x) => x.nome === a.nome
      && (!f.conjunto || x.conjuntoId === f.conjunto)
      && (!f.campanha || t.conjuntos.find((c) => c.id === x.conjuntoId)?.campanhaId === f.campanha));
    const alvos = irmaos.length > 0 ? irmaos : [a];
    if (alvos.some((x) => !x.idExterno)) return { ok: false, motivo: `O anúncio "${a.nome}" não tem o id do Meta no tráfego.` };
    if (alvos.length > 1) {
      return { ok: false, motivo: `O criativo "${a.nome}" roda em ${alvos.length} anúncios do Meta e o servidor do grupo só aceita um por vez. Escolha também um conjunto.` };
    }
    return com(recorteGrupoDe({ ...base, anuncioMeta: alvos[0].idExterno }), `Anúncio: ${a.nome}`);
  }
  if (t && f.conjunto) {
    const j = t.conjuntos.find((x) => x.id === f.conjunto);
    if (!j) return { ok: false, motivo: 'O conjunto escolhido não está no tráfego do período.' };
    if (!j.idExterno) return { ok: false, motivo: `O tráfego ainda não devolve o id do Meta do conjunto "${j.nome}" (conjunto_externa).` };
    return com(recorteGrupoDe({ ...base, conjuntoMeta: j.idExterno }), `Conjunto: ${j.nome}`);
  }
  if (t && f.campanha) {
    const c = t.campanhas.find((x) => x.id === f.campanha);
    if (!c) return { ok: false, motivo: 'A campanha escolhida não está no tráfego do período.' };
    if (!c.idExterno) return { ok: false, motivo: `O tráfego ainda não devolve o id do Meta da campanha "${c.nome}" (campanha_externa).` };
    return com(recorteGrupoDe({ ...base, campanhaMeta: c.idExterno }), `Campanha: ${c.nome}`);
  }
  if (t && f.pagina) {
    const p = t.paginas.find((x) => x.id === f.pagina);
    if (!p) return { ok: false, motivo: 'A página escolhida não está no tráfego do período.' };
    if (p.isca) return com(recorteGrupoDe({ ...base, isca: p.isca }), `Página: ${p.rotulo}`);
    if (p.porta) return com(recorteGrupoDe({ ...base, porta: p.porta }), `Página: ${p.rotulo}`);
    return { ok: false, motivo: `A página "${p.rotulo}" não tem porta nem isca: o servidor não tem esse recorte.` };
  }
  const x = recorteGrupoDe(base);
  return r.funil === 'todos' ? x : com(x, `Funil: ${ROTULO_FUNIL[r.funil]}`);
}

/** Chave estável do recorte (para a releitura do bloco do grupo). */
export const chaveRecorte = (r: RecorteGrupo | null) => (r ? `${r.tipo}:${r.valor}` : 'sem-recorte');

/** % MQL = leads.mql ÷ leads.unicos (pessoas únicas do período e do recorte, sem teste). */
export function cardMql(g: GrupoResumoBlack): { total: Valor; taxa: Taxa } {
  return { total: g.leads.mql, taxa: taxa(g.leads.mql, g.leads.unicos) };
}

/**
 * Únicos de um segmento. Um grupo só no segmento: o número dele. Nenhum: Sem dado. Mais de um: Sem dado, porque
 * somar contaria duas vezes quem está nos dois (a união por pessoa é conta do servidor).
 */
function unicosDoSegmento(g: GrupoResumoBlack, segmento: SegmentoGrupo, cruzado: boolean): { valor: Valor; nota: string | null } {
  const doSegmento = g.grupos.filter((x) => x.segmento === segmento);
  if (doSegmento.length === 0) return { valor: null, nota: 'Nenhum grupo deste segmento na fonte.' };
  if (doSegmento.length > 1) return { valor: null, nota: `${doSegmento.length} grupos neste segmento: a soma contaria a mesma pessoa duas vezes.` };
  return { valor: cruzado ? doSegmento[0].unicosCruzados : doSegmento[0].unicos, nota: null };
}

export interface LinhaGrupo { segmento: SegmentoGrupo; rotulo: string; taxa: Taxa }
export interface CardsGrupo { geral: Taxa; linhas: LinhaGrupo[]; cruzado: boolean }

/**
 * Ingresso no grupo. Geral = únicos nos grupos de MQL ÷ leads MQL. Advogados = grupo do advogado ÷ (advogado +
 * estudante de Direito); Contadores = grupo do contador ÷ contadores; Outros = grupo de outros ÷ não MQL.
 * Com recorte, o numerador é o cruzado (dos leads do recorte, quantos estão no grupo).
 */
export function cardsGrupo(g: GrupoResumoBlack): CardsGrupo {
  const cruzado = g.recorte !== null;
  const nota = cruzado ? `Cruzado: ${ROTULO_CRUZADO}.` : null;
  const linha = (segmento: SegmentoGrupo, rotulo: string, den: Valor): LinhaGrupo => {
    const u = unicosDoSegmento(g, segmento, cruzado);
    return { segmento, rotulo, taxa: taxa(u.valor, den, u.nota ?? nota) };
  };
  return {
    cruzado,
    geral: taxa(cruzado ? g.unicosCruzadosMql : g.unicosGruposMql, g.leads.mql, nota),
    linhas: [
      linha('advogado', 'Advogados', g.leads.advogadoMaisEstudante),
      linha('contador', 'Contadores', g.leads.contador),
      linha('outros', 'Outros (não MQL)', g.leads.naoMql),
    ],
  };
}

/** Resposta vazia (Sem dado em tudo), para quando o bloco ainda não foi lido ou a fonte não existe. */
export function grupoSemDado(recorte: RecorteGrupo | null = null): GrupoResumoBlack {
  return {
    periodo: { de: null, ate: null }, recorte, grupos: [],
    unicosGruposMql: null, unicosGruposTotal: null, unicosCruzadosMql: null,
    leads: { unicos: null, mql: null, advogado: null, estudanteDireito: null, advogadoMaisEstudante: null, contador: null, outros: null, semProfissao: null, naoMql: null },
    atualizado: { ultimoEventoWebhook: null, ultimaFoto: null },
  };
}
