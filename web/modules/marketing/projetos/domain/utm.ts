// UTM no padrão oficial do gp-operacoes (departamentos/dados/areas/infraestrutura/processos/padronizar-utm-dos-links.md,
// confirmado pelo Victor em 06/10/2026). Domínio puro: sem Next, sem Supabase.
//
//   Meta:   utm_source=metaads, utm_campaign = campanha nome|id, utm_medium = conjunto nome|id,
//           utm_content = o anúncio (criativo) nome|id, utm_term = posicionamento
//   Google: só id (não existe macro de nome)
//   ex.: utm_campaign=RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|120211234
//
// O nome da campanha também tem " | " dentro, então o id é o que vem DEPOIS DA ÚLTIMA "|", e só se for número.
// Sem "|": número = id, senão nome (formato antigo, dado histórico). O sistema cruza pelo id; nome só como reserva.
//
// A MESMA regra existe no banco (mkt.utm_separar e mkt_web.origem_ids, migration 20261005n). Mudou aqui, muda lá.

export interface UtmSeparado {
  /** A parte do nome, sem o id (aparada). Nula quando só veio id. */
  nome: string | null;
  /** O id (só dígitos). Nulo quando só veio nome. */
  id: string | null;
}

const SO_NUMERO = /^[0-9]+$/;

export function separarUtm(texto: string | null | undefined): UtmSeparado {
  const v = (texto ?? '').trim();
  if (v === '') return { nome: null, id: null };
  const corte = v.lastIndexOf('|');
  if (corte >= 0) {
    const fim = v.slice(corte + 1).trim();
    if (SO_NUMERO.test(fim)) return { nome: v.slice(0, corte).trim() || null, id: fim };
    return { nome: v, id: null };
  }
  return SO_NUMERO.test(v) ? { nome: null, id: v } : { nome: v, id: null };
}

export interface OrigemUtm {
  utm_source?: string | null; utm_medium?: string | null; utm_campaign?: string | null; utm_content?: string | null;
  campaign_id?: string | null; adset_id?: string | null; ad_id?: string | null;
}

export interface OrigemIds {
  campanha_id: string | null; campanha_nome: string | null;
  conjunto_id: string | null;
  anuncio_id: string | null; anuncio_nome: string | null;
}

const preenchido = (s: string | null | undefined) => (s ?? '').trim() || null;

/** Os ids da origem de uma visita (igual mkt_web.origem_ids): o parâmetro explícito da URL vale primeiro; senão o id
 *  do UTM. O conjunto sai do utm_medium só com utm_source=metaads. */
export function origemIds(o: OrigemUtm): OrigemIds {
  const c = separarUtm(o.utm_campaign), m = separarUtm(o.utm_medium), a = separarUtm(o.utm_content);
  const meta = (o.utm_source ?? '').trim().toLowerCase() === 'metaads';
  return {
    campanha_id: preenchido(o.campaign_id) ?? c.id, campanha_nome: c.nome,
    conjunto_id: preenchido(o.adset_id) ?? (meta ? m.id : null),
    anuncio_id: preenchido(o.ad_id) ?? a.id, anuncio_nome: a.nome,
  };
}

/** Rótulo curto para tela: o nome; só id = o id; os dois = "nome · id". */
export function rotuloUtm(nome: string | null | undefined, id: string | null | undefined): string {
  if (nome && id) return `${nome} · ${id}`;
  return nome || id || '–';
}
