// Inicial do avatar: primeira letra (ou dígito) do nome. Nome vazio, só pontuação ou marcador como "(sem nome)":
// null — o avatar mostra o ícone de pessoa, nunca "(" ou "?".
export function inicialAvatar(nome: string | null | undefined): string | null {
  const n = String(nome ?? '').trim();
  if (!n || /^\(.*\)$/.test(n)) return null;
  const m = n.match(/[\p{L}\p{N}]/u);
  return m ? m[0].toLocaleUpperCase('pt-BR') : null;
}
