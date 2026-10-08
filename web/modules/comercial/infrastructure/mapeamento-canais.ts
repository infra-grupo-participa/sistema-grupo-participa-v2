// crm_canais (migration 20261008152212) → PainelCanais. Puro e testado. Formato fora do contrato = erro, nunca "vazio".
import type { CanalWhatsapp, PainelCanais, StatusCanal } from '../domain/canais-whatsapp';
import { FormatoInesperado } from './mapeamento-supabase';

type Obj = Record<string, unknown>;
const STATUS: readonly StatusCanal[] = ['desconectado', 'aguardando_qr', 'conectado', 'banido'];
const s = (v: unknown) => (typeof v === 'string' ? v : '');
const sn = (v: unknown) => (typeof v === 'string' && v ? v : null);
const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

export function mapCanais(d: unknown): PainelCanais {
  if (!d || typeof d !== 'object' || Array.isArray(d)) throw new FormatoInesperado('crm_canais', 'resposta não é objeto');
  const o = d as Obj;
  if (!Array.isArray(o.canais)) throw new FormatoInesperado('crm_canais', 'sem lista de canais');
  const canais: CanalWhatsapp[] = o.canais.map((x) => {
    const c = (x && typeof x === 'object' ? x : {}) as Obj;
    if (!STATUS.includes(c.status as StatusCanal)) throw new FormatoInesperado('crm_canais', `status desconhecido (${s(c.status)})`);
    return {
      id: s(c.id), provedor: c.provedor === 'evolution' ? 'evolution' : 'infobip', nome: s(c.nome), final: sn(c.final),
      status: c.status as StatusCanal, statusEm: sn(c.statusEm), statusMotivo: sn(c.statusMotivo), conectadoEm: sn(c.conectadoEm),
      recebe: c.recebe !== false, envia: c.envia !== false, donoId: sn(c.donoId), padrao: c.padrao === true,
    };
  });
  return {
    evolutionLigado: o.evolutionLigado === true, envioLigado: o.envioLigado === true,
    limiteMinuto: n(o.limiteMinuto), limiteHora: n(o.limiteHora), novosHora: n(o.novosHora), canais,
  };
}
