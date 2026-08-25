// Busca textual do board — função pura, sem I/O e sem React.
//
// Mora no domínio (e não dentro do componente) pela mesma razão que
// prazo.ts/totais.ts: é regra testável de "o que casa com o que o operador
// digitou", e o board não é o único lugar que vai querer filtrar por nome.
//
// ── ESCOPO: só o que o card já mostra ─────────────────────────────────────
// Campos buscáveis: NOME e VENDEDOR. Nada além disso.
//
// 🔑 `email`, `telefone` e `documento` ficam DE FORA de propósito. O card os
// esconde por decisão de LGPD registrada em CardBoard.tsx ("E-mail continua
// fora do card — LGPD + ruído") e eles só aparecem na ficha, sob permissão
// (canVerDoc). Uma busca que casasse por e-mail devolveria o dado pela porta
// dos fundos: bastaria digitar um domínio para varrer a carteira inteira, sem
// passar por nenhum guard. Buscar só o que já está na tela mantém a busca com
// exatamente o mesmo alcance que os olhos de quem está olhando o board.

/** Normaliza para comparação: minúsculas, sem acento e sem espaço duplicado.
 *
 *  Acento é obrigatório aqui — a base é de nomes brasileiros e ninguém digita
 *  "Conceição" com cedilha na pressa de achar um card. Sem isso, "conceicao"
 *  não acharia "Conceição" e a busca pareceria quebrada. */
export function normalizar(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}

/** O que a busca varre em uma conta. Ver nota de LGPD no topo do arquivo. */
export interface AlvoBusca {
  nome: string | null;
  vendedor: string | null;
}

/**
 * Casa quando TODOS os termos digitados aparecem em algum campo buscável.
 *
 * Multi-termo (AND, não frase literal) porque a ordem em que o operador digita
 * não é a ordem do cadastro: "silva maria" precisa achar "Maria da Silva", e
 * "maria joao" precisa achar a Maria cujo vendedor é o João — buscar a string
 * inteira como frase falharia nos dois casos.
 *
 * Consulta vazia (ou só espaço) casa com TUDO: "não filtrei" nunca pode virar
 * "nada encontrado" — mesma disciplina de `saldo_a_pagar` null em totais.ts,
 * onde ausência de valor não colapsa em zero.
 */
export function casaBusca(alvo: AlvoBusca, consulta: string): boolean {
  const termos = normalizar(consulta).split(' ').filter(Boolean);
  if (!termos.length) return true;

  const feno = normalizar([alvo.nome ?? '', alvo.vendedor ?? ''].join(' '));
  return termos.every((t) => feno.includes(t));
}
