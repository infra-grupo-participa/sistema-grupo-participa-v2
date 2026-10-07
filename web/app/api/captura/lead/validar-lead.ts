// Validação do corpo de POST /api/captura/lead (docs/captura-de-lead.md). Regra pura: sem Next, sem Supabase.
// Mensagens de erro citam só o NOME do campo, nunca o valor (LGPD).

export const CHAVE_EVENTO_RE = /^[a-z0-9]+(-[a-z0-9]+)*$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
export const TIPOS = ['lead', 'pre_checkout'] as const;
const UTMS = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term'] as const;

type Campo = { erro: string } | { valor: string | null };

/** Texto opcional: ausente/vazio = null; não-string ou acima do teto = erro com o NOME do campo (nunca o valor). */
function texto(c: Record<string, unknown>, nome: string, max: number): Campo {
  const v = c[nome];
  if (v === undefined || v === null) return { valor: null };
  if (typeof v !== 'string') return { erro: `${nome}: deve ser texto.` };
  const t = v.replace(/[\u0000-\u001f\u007f]+/g, ' ').trim();
  if (!t) return { valor: null };
  if (t.length > max) return { erro: `${nome}: até ${max} caracteres.` };
  return { valor: t };
}

/** Página de origem sem ?query e #fragmento (a query pode carregar e-mail ou telefone). */
function semQuery(v: string): string {
  return v.split('#')[0].split('?')[0].trim();
}

export type Lead = {
  chave_evento: string;
  evento: (typeof TIPOS)[number];
  nome: string | null;
  email: string | null;
  telefone: string | null;
  sck: string | null;
  xcod: string | null;
  pagina: string | null;
  teste: boolean;
} & Partial<Record<(typeof UTMS)[number], string>>;

/** Valida o corpo. Mensagens citam só o nome do campo. */
export function validarLead(corpo: unknown): { ok: true; lead: Lead } | { ok: false; erro: string } {
  if (!corpo || typeof corpo !== 'object' || Array.isArray(corpo)) return { ok: false, erro: 'Corpo deve ser um objeto JSON.' };
  const c = corpo as Record<string, unknown>;

  const chave = texto(c, 'chave_evento', 80);
  if ('erro' in chave) return { ok: false, erro: chave.erro };
  if (!chave.valor || !CHAVE_EVENTO_RE.test(chave.valor)) {
    return { ok: false, erro: 'chave_evento: obrigatória, minúscula com hífen (ex.: clinica-miami-2026-12).' };
  }

  const tipo = c.tipo;
  if (typeof tipo !== 'string' || !(TIPOS as readonly string[]).includes(tipo)) {
    return { ok: false, erro: `tipo: obrigatório, um de ${TIPOS.join(', ')}.` };
  }

  const nome = texto(c, 'nome', 160);
  if ('erro' in nome) return { ok: false, erro: nome.erro };
  if (nome.valor !== null && nome.valor.length < 2) return { ok: false, erro: 'nome: mínimo de 2 caracteres.' };

  const email = texto(c, 'email', 254);
  if ('erro' in email) return { ok: false, erro: email.erro };
  const emailNorm = email.valor ? email.valor.toLowerCase() : null;
  if (emailNorm && !EMAIL_RE.test(emailNorm)) return { ok: false, erro: 'email: formato inválido.' };

  const tel = texto(c, 'telefone', 30);
  if ('erro' in tel) return { ok: false, erro: tel.erro };
  const telDigitos = tel.valor ? tel.valor.replace(/\D+/g, '') : '';
  if (tel.valor && (telDigitos.length < 10 || telDigitos.length > 13)) {
    return { ok: false, erro: 'telefone: 10 a 13 dígitos (ex.: 55 + DDD + número).' };
  }
  if (!emailNorm && !telDigitos) return { ok: false, erro: 'Informe email ou telefone.' };

  const lead: Lead = {
    chave_evento: chave.valor,
    evento: tipo as Lead['evento'],
    nome: nome.valor,
    email: emailNorm,
    telefone: telDigitos || null,
    sck: null,
    xcod: null,
    pagina: null,
    teste: false,
  };

  for (const u of UTMS) {
    const r = texto(c, u, 300);
    if ('erro' in r) return { ok: false, erro: r.erro };
    if (r.valor) lead[u] = r.valor;
  }
  for (const [nomeCampo, max] of [['sck', 200], ['xcod', 200]] as const) {
    const r = texto(c, nomeCampo, max);
    if ('erro' in r) return { ok: false, erro: r.erro };
    lead[nomeCampo] = r.valor;
  }
  const pag = texto(c, 'pagina_origem', 300);
  if ('erro' in pag) return { ok: false, erro: pag.erro };
  lead.pagina = pag.valor ? semQuery(pag.valor) || null : null;

  if (c.teste !== undefined && typeof c.teste !== 'boolean') return { ok: false, erro: 'teste: deve ser true ou false.' };
  lead.teste = c.teste === true;
  return { ok: true, lead };
}
