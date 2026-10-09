// Link do sistema colado no Claude ("resume este link: …"). Domínio puro: só extrai o id, com validação estrita.
// Aceita: https://grupoparticipa.app.br/comercial/<tela>?contato=<uuid> ou ?negocio=<uuid> (e http(s)://localhost
// para o dev). Qualquer outro domínio, sem /comercial, com usuário/senha na URL ou sem UUID válido é recusado.
// Quem decide se a pessoa pode ver o lead é o banco (public.crm_mcp_lead).

export type LinkCrm = { ok: true; tipo: 'contato' | 'negocio'; id: string } | { ok: false; msg: string };

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HOSTS_PRODUCAO = new Set(['grupoparticipa.app.br', 'www.grupoparticipa.app.br']);
const HOSTS_LOCAIS = new Set(['localhost', '127.0.0.1']);
const INVALIDO = 'Link inválido: cole um link do CRM (grupoparticipa.app.br/comercial/…?contato=… ou ?negocio=…).';

export function lerLinkCrm(entrada: unknown): LinkCrm {
  if (typeof entrada !== 'string') return { ok: false, msg: INVALIDO };
  const bruto = entrada.trim().replace(/^<|>$/g, '');
  if (!bruto || bruto.length > 500) return { ok: false, msg: INVALIDO };
  let u: URL;
  try {
    u = new URL(/^[a-z][a-z0-9+.-]*:\/\//i.test(bruto) ? bruto : `https://${bruto}`);
  } catch {
    return { ok: false, msg: INVALIDO };
  }
  const host = u.hostname.toLowerCase();
  const local = HOSTS_LOCAIS.has(host);
  if (!(HOSTS_PRODUCAO.has(host) && u.protocol === 'https:' && !u.port) && !(local && (u.protocol === 'http:' || u.protocol === 'https:'))) {
    return { ok: false, msg: 'Só abro links do sistema (grupoparticipa.app.br).' };
  }
  if (u.username || u.password) return { ok: false, msg: INVALIDO };
  if (!/^\/comercial(\/|$)/.test(u.pathname)) return { ok: false, msg: INVALIDO };

  for (const tipo of ['negocio', 'contato'] as const) {
    const valores = u.searchParams.getAll(tipo);
    if (valores.length === 0) continue;
    if (valores.length > 1 || !UUID.test(valores[0].trim())) return { ok: false, msg: `O ${tipo === 'negocio' ? 'negócio' : 'contato'} do link não é um id válido.` };
    return { ok: true, tipo, id: valores[0].trim().toLowerCase() };
  }
  return { ok: false, msg: INVALIDO };
}
