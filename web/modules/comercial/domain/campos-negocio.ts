// Campos do negócio pelo Claude (MCP do Comercial). Domínio puro: sem Next, sem Supabase.
//
// 1. normalizarValorCampo: fala natural ("é contadora", "começando", "Holding Total", "Clínica Miami", "no pix") → a
//    chave que o banco guarda em crm.negocio.campos. Quem decide se a chave vale é o banco (crm.campo_def / crm.linha
//    ativa, em public.crm_mcp_preencher_campos); aqui só traduz. O que não reconhece segue como slug e o banco recusa
//    listando as opções válidas.
// 2. sugerirCampos: heurística simples e determinística (palavras-chave) sobre as mensagens do CLIENTE e as notas da
//    equipe. Devolve sugestões com o trecho que justifica cada uma. NÃO grava nada e não decide: o Claude do usuário
//    lê o trecho, propõe e só grava com comercial_preencher_campos depois do "sim" do usuário.

/** minúsculo, sem acento, espaços colapsados. */
export function normalizarTexto(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();
}

/** Slug no formato das chaves do banco (clinica_miami, socio_conjuge). */
export function slug(s: string): string {
  return normalizarTexto(s).replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
}

type Regra = { valor: string; re: RegExp };

/** Ordem importa: a primeira regra que casa vence. Texto já normalizado (sem acento, minúsculo). */
const REGRAS: Record<string, Regra[]> = {
  perfil_profissional: [
    { valor: 'advogado', re: /\b(advogad[oa]s?|adv|advocacia|oab|juridico|direito)\b/ },
    { valor: 'contador', re: /\b(contador(a|es|as)?|contabil(idade|ista)?|contabeis|crc)\b/ },
    { valor: 'outro', re: /\b(outr[oa]s?|nenhum|nao e (advogad|contad))/ },
  ],
  atua_com_holding: [
    { valor: 'nao', re: /^(nao|n|nunca|ainda nao|nao atua|nao faz|nao trabalha)\b/ },
    { valor: 'comecando', re: /\b(comecando|comecou|comecar|iniciando|inicio|iniciante|primeir[ao]s?)\b/ },
    { valor: 'sim', re: /^(sim|s|ja|atua|faz|trabalha)\b|\bja (atua|faz|trabalha|monta|estrutura)\b/ },
  ],
  produto_interesse: [
    { valor: 'ht', re: /^(ht|holding total)$|\bholding total\b/ },
    { valor: 'acelera', re: /\bacelera\b/ },
    { valor: 'hm', re: /^hm$|\bholding masters?\b|^masters?$/ },
    { valor: 'aurum', re: /\baurum\b/ },
    { valor: 'ethb', re: /\bethb\b/ },
    { valor: 'sv', re: /^sv$|\bsessao (de )?viabilidade\b|^viabilidade$/ },
    { valor: 'clinica_miami', re: /\bclinica\b|\bmiami\b|\bdiamante\b/ },
  ],
  objecao_principal: [
    { valor: 'socio_conjuge', re: /\b(socio|socia|conjuge|esposa|esposo|marido|mulher)\b/ },
    { valor: 'sem_cliente', re: /\b(sem cliente|nao tem cliente|nao tenho cliente|falta de cliente)/ },
    { valor: 'ja_sei', re: /\b(ja sei|ja conhece|ja conheco|ja sabe)\b/ },
    { valor: 'preco', re: /\b(preco|caro|valor|dinheiro|grana|parcela)\b/ },
    { valor: 'pensar', re: /\b(pensar|pensando)\b/ },
    { valor: 'momento', re: /\b(momento|agora nao|depois|mais pra frente|timing|tempo)\b/ },
    { valor: 'outra', re: /^outr[ao]s?$/ },
  ],
  forma_pagamento: [
    { valor: 'pix', re: /\bpix\b/ },
    { valor: 'boleto', re: /\bboleto\b/ },
    { valor: 'cartao', re: /\b(cartao|credito|debito)\b/ },
  ],
};

/** Campos com opções fechadas conhecidas (as do banco em 09/10/2026; o banco continua sendo quem valida). */
export const CAMPOS_CONHECIDOS = ['perfil_profissional', 'atua_com_holding', 'produto_interesse', 'origem', 'objecao_principal',
  'forma_pagamento'] as const;

/**
 * Valor dito pelo vendedor → valor gravável. '' ou null = limpar o campo. Campo de texto livre (origem) fica como
 * veio (aparado). Campo de opção: primeiro a chave exata ("comecando"), depois as regras; sem regra → slug.
 */
export function normalizarValorCampo(chave: string, valor: string | null): string {
  if (valor === null) return '';
  const bruto = valor.trim();
  if (!bruto) return '';
  const regras = REGRAS[chave];
  if (!regras) return bruto;
  const t = normalizarTexto(bruto).replace(/^(e|eh|ele e|ela e|sou|e um|e uma|um|uma|o|a|no|na|pelo|pela|via|com|de)\s+/, '');
  const s = slug(t);
  if (regras.some((r) => r.valor === s)) return s;
  for (const r of regras) if (r.re.test(t)) return r.valor;
  return s;
}

// ─── Sugestão a partir da conversa ──────────────────────────────────────────────────────────────────────────────────
export interface TextoLead {
  fonte: 'mensagem' | 'nota';
  /** Só mensagens do cliente entram (a equipe fala "advogados e contadores" no pitch). Notas são da equipe sobre o lead. */
  de?: 'cliente' | 'equipe';
  texto: string | null | undefined;
  em?: string | null;
}

export interface SugestaoCampo {
  campo: string;
  valor: string;
  /** Trecho literal (até ~160 caracteres) que justifica a sugestão. */
  trecho: string;
  fonte: 'mensagem' | 'nota';
  em: string | null;
}

/** Padrões de CONVERSA (mais restritos que os de normalização: precisam de contexto na frase). */
const PISTAS: { campo: string; valor: string; re: RegExp }[] = [
  { campo: 'perfil_profissional', valor: 'advogado', re: /\b(sou|sou um|sou uma|como|trabalho como|atuo como|e|eh) advogad[oa]\b|\boab\b|\badvocacia\b|\bmeu escritorio de advocacia\b|\badvogad[oa] (tributarista|empresarial|de familia|civilista|trabalhista)\b/ },
  { campo: 'perfil_profissional', valor: 'contador', re: /\b(sou|sou um|sou uma|como|trabalho como|atuo como|e|eh) contador(a)?\b|\bcrc\b|\bescritorio (de )?contabil(idade)?\b|\bminha contabilidade\b|\btenho (uma )?contabilidade\b/ },
  { campo: 'atua_com_holding', valor: 'sim', re: /\bja (faco|fiz|trabalho com|atuo com|monto|montei|estruturo|estruturei|fazemos|montamos) (algumas? |umas? |varias |as )?holdings?\b|\b(atuo|trabalho) com holdings?\b/ },
  { campo: 'atua_com_holding', valor: 'comecando', re: /\b(estou|to|ainda estou) comecando\b|\bcomecando (agora )?(com|em|na|nas) holdings?\b|\bquero comecar (a fazer |com |em )?holdings?\b|\bprimeira holding\b/ },
  { campo: 'atua_com_holding', valor: 'nao', re: /\b(nunca fiz|nunca montei|ainda nao fiz|ainda nao trabalho com|nao trabalho com|nao atuo com|nao faco) (nenhuma )?holdings?\b/ },
  { campo: 'produto_interesse', valor: 'ht', re: /\bholding total\b/ },
  { campo: 'produto_interesse', valor: 'hm', re: /\bholding masters?\b/ },
  { campo: 'produto_interesse', valor: 'acelera', re: /\bacelera holding\b/ },
  { campo: 'produto_interesse', valor: 'aurum', re: /\baurum\b/ },
  { campo: 'produto_interesse', valor: 'ethb', re: /\bethb\b/ },
  { campo: 'produto_interesse', valor: 'sv', re: /\bsessao de viabilidade\b/ },
  { campo: 'produto_interesse', valor: 'clinica_miami', re: /\bclinica (de )?(miami|internacional|diamante)\b/ },
  { campo: 'forma_pagamento', valor: 'pix', re: /\b(pagar|pago|pagamento|faco|fazer|mando|manda) (no |via |por |com |o |um )?pix\b|\bno pix\b/ },
  { campo: 'forma_pagamento', valor: 'boleto', re: /\b(pagar|pago|pagamento|gera|gerar|manda|mandar) (no |via |por |com |o |um )?boleto\b|\bno boleto\b/ },
  { campo: 'forma_pagamento', valor: 'cartao', re: /\b(pagar|pago|pagamento|passar|passo) (no |via |por |com |o )?cartao\b|\bno cartao\b|\bparcel(ar|ado|o) no cartao\b/ },
  { campo: 'objecao_principal', valor: 'socio_conjuge', re: /\b(falar|conversar|ver|alinhar|decidir) com (o |a |meu |minha )?(socio|socia|esposa|esposo|marido|mulher|conjuge)\b/ },
  { campo: 'objecao_principal', valor: 'preco', re: /\b(ta|esta|achei|muito|bem) caro\b|\bsem (dinheiro|grana)\b|\bnao (tenho|tem) (dinheiro|grana|como pagar)\b|\bfora do (meu )?orcamento\b/ },
  { campo: 'objecao_principal', valor: 'pensar', re: /\b(vou|preciso|deixa eu|quero) pensar\b/ },
  { campo: 'objecao_principal', valor: 'sem_cliente', re: /\bnao tenho cliente|\bsem clientes?\b|\bnao tenho para quem (vender|oferecer)\b/ },
  { campo: 'objecao_principal', valor: 'momento', re: /\bnao e (o )?(meu )?momento\b|\bagora nao (da|posso)\b|\bmais (pra|para) frente\b/ },
];

/**
 * Mapa de índice no texto normalizado → índice no original. normalize('NFD') + remoção de acento muda o comprimento;
 * para devolver o trecho ORIGINAL, normalizamos caractere a caractere.
 */
function normalizarComMapa(original: string): { t: string; mapa: number[] } {
  let t = '';
  const mapa: number[] = [];
  let espaco = false;
  for (let i = 0; i < original.length; i++) {
    const c = original[i].normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
    for (const ch of c) {
      if (/\s/.test(ch)) {
        if (espaco) continue;
        espaco = true;
        t += ' ';
      } else {
        espaco = false;
        t += ch;
      }
      mapa.push(i);
    }
  }
  return { t, mapa };
}

function trecho(original: string, mapa: number[], ini: number, fim: number): string {
  const a = Math.max(0, (mapa[ini] ?? 0) - 60);
  const b = Math.min(original.length, (mapa[Math.max(ini, fim - 1)] ?? original.length) + 61);
  const meio = original.slice(a, b).replace(/\s+/g, ' ').trim();
  return `${a > 0 ? '…' : ''}${meio}${b < original.length ? '…' : ''}`;
}

/**
 * Sugestões a partir das mensagens do cliente e das notas. Uma por campo+valor (a evidência mais recente). Quando o
 * mesmo campo recebe valores diferentes, todas voltam: o Claude mostra a dúvida ao usuário em vez de escolher.
 */
export function sugerirCampos(textos: readonly TextoLead[]): SugestaoCampo[] {
  const porChave = new Map<string, SugestaoCampo>();
  const ordenados = [...textos]
    .filter((x) => typeof x.texto === 'string' && x.texto.trim() && (x.fonte === 'nota' || x.de === 'cliente'))
    .sort((x, y) => (Date.parse(y.em ?? '') || 0) - (Date.parse(x.em ?? '') || 0));
  for (const x of ordenados) {
    const original = (x.texto as string).slice(0, 4000);
    const { t, mapa } = normalizarComMapa(original);
    for (const p of PISTAS) {
      const m = p.re.exec(t);
      if (!m) continue;
      const k = `${p.campo}=${p.valor}`;
      if (porChave.has(k)) continue;   // já tem evidência mais recente
      porChave.set(k, { campo: p.campo, valor: p.valor, trecho: trecho(original, mapa, m.index, m.index + m[0].length), fonte: x.fonte, em: x.em ?? null });
    }
  }
  const ordem = (c: string) => (CAMPOS_CONHECIDOS as readonly string[]).indexOf(c);
  return [...porChave.values()].sort((a, b) => ordem(a.campo) - ordem(b.campo));
}
