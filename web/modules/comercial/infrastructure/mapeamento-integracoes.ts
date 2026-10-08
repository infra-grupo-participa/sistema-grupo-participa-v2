// crm_integracoes_status (migration 20261008180945) → PainelIntegracoes. Puro e testado.
// Formato fora do contrato = erro (a tela mostra "Não foi possível carregar"), nunca lista vazia que pareça "nada conectado".
import type {
  ErroIntegracao, FatosIntegracao, NumeroWhatsappVivo, PainelIntegracoes, StatusNumeroWhatsapp,
} from '../domain/integracoes-status';
import { FormatoInesperado } from './mapeamento-supabase';

type Obj = Record<string, unknown>;
const RPC = 'crm_integracoes_status';
const STATUS: readonly StatusNumeroWhatsapp[] = ['conectado', 'desconectado', 'aguardando_qr', 'banido'];
const s = (v: unknown) => (typeof v === 'string' ? v : '');
const sn = (v: unknown) => (typeof v === 'string' && v ? v : null);
const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);
const obj = (v: unknown): Obj => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Obj) : {});

function erro(v: unknown): ErroIntegracao | null {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return null;
  const o = v as Obj;
  const texto = sn(o.texto);
  return texto ? { texto, em: sn(o.em) } : null;
}

export function mapIntegracoesStatus(d: unknown): PainelIntegracoes {
  if (!d || typeof d !== 'object' || Array.isArray(d)) throw new FormatoInesperado(RPC, 'resposta não é objeto');
  const o = d as Obj;
  if (!Array.isArray(o.integracoes)) throw new FormatoInesperado(RPC, 'sem lista de integrações');
  if (!Array.isArray(o.numeros)) throw new FormatoInesperado(RPC, 'sem lista de números');
  const integracoes: FatosIntegracao[] = o.integracoes.map((x) => {
    const i = obj(x);
    if (!s(i.chave)) throw new FormatoInesperado(RPC, 'integração sem chave');
    return {
      chave: s(i.chave), ligada: i.ligada === true, configurada: i.configurada === true,
      ultimoEventoEm: sn(i.ultimoEventoEm), eventos24h: n(i.eventos24h), erroRecente: erro(i.erroRecente),
    };
  });
  const numeros: NumeroWhatsappVivo[] = o.numeros.map((x) => {
    const c = obj(x);
    if (!STATUS.includes(c.status as StatusNumeroWhatsapp)) throw new FormatoInesperado(RPC, `status de número desconhecido (${s(c.status)})`);
    return {
      id: s(c.id), nome: s(c.nome), provedor: c.provedor === 'evolution' ? 'evolution' : 'infobip',
      status: c.status as StatusNumeroWhatsapp, statusEm: sn(c.statusEm), statusMotivo: sn(c.statusMotivo), final: sn(c.final),
      ativo: c.ativo === true, principal: c.principal === true, recebe: c.recebe !== false, envia: c.envia !== false,
      ultimaMensagemEm: sn(c.ultimaMensagemEm), mensagens24h: n(c.mensagens24h), falhas24h: n(c.falhas24h),
    };
  });
  return { geradoEm: s(o.geradoEm) || new Date().toISOString(), integracoes, numeros };
}
