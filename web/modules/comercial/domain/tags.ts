// Tags do contato (crm_tags_contato, migration 20261008222038). Regras puras, espelho de crm.tag_normalizar:
// minúsculo, sem acento, tudo que não é letra/número vira hífen, sem hífen nas pontas, até 40 caracteres.
// O banco decide de novo (normaliza, D6, leitor, máximo de 30).

export const MAX_TAGS_CONTATO = 30;
export const MAX_TAG = 40;

/** "Quente Ágora!" → "quente-agora". null = não sobra letra nem número. */
export function normalizarTag(t: string | null | undefined): string | null {
  const s = String(t ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, MAX_TAG)
    .replace(/-+$/g, '');
  return s || null;
}

/** Separa o que a pessoa digitou ("vip, quente; ht 30") em tags normalizadas, sem repetir. */
export function tagsDoTexto(texto: string): string[] {
  const out: string[] = [];
  for (const parte of texto.split(/[,;\n]/)) {
    const n = normalizarTag(parte);
    if (n && !out.includes(n)) out.push(n);
  }
  return out;
}

/** Prévia do resultado (mesma conta do banco): tira pela forma normalizada, adiciona só o que falta. */
export function aplicarTags(atuais: string[], adicionar: string[], remover: string[]): { tags: string[]; erro: string | null } {
  const rem = new Set(remover.map(normalizarTag).filter((x): x is string => !!x));
  const add = [...new Set(adicionar.map(normalizarTag).filter((x): x is string => !!x))];
  if (add.some((a) => rem.has(a))) return { tags: atuais, erro: 'A mesma tag não pode ser adicionada e removida juntas.' };
  const ficam = atuais.filter((t) => !rem.has(normalizarTag(t) ?? ''));
  const novas = add.filter((a) => !ficam.some((t) => normalizarTag(t) === a)).sort();
  const tags = [...ficam, ...novas];
  if (tags.length > MAX_TAGS_CONTATO) return { tags: atuais, erro: `Máximo de ${MAX_TAGS_CONTATO} tags por contato (ficaria com ${tags.length}). Remova alguma antes.` };
  return { tags, erro: null };
}
