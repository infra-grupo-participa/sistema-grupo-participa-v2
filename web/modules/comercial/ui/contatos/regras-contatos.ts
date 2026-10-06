// Regras puras da base de contatos: busca e aviso de duplicidade. Sem React, testáveis.
import { chaveTelefone } from '../../domain/regras';
import type { Contato, Utm } from '../../domain/types';

// Duplicidade e busca moraram aqui; passaram para o domínio (usadas também pelo repositório). Reexportadas.
export { casaBusca, mapaDuplicados } from '../../domain/contatos';

/** Origem numa linha só: "instagram / cpc / ht33-meteorico". Sem UTM nenhuma: "direto". */
export function utmEmLinha(utm: Pick<Utm, 'source' | 'medium' | 'campaign'>): string {
  const partes = [utm.source, utm.medium, utm.campaign].filter((x): x is string => !!x && !!x.trim());
  return partes.length ? partes.join(' / ') : 'direto';
}

/** Resumo dos negócios abertos para a lista: "Holding Masters · Negociar" + quantos sobram. */
export function resumoAbertos(abertos: { produtoNome: string; etapaNome: string }[]): { texto: string; resto: number } | null {
  if (!abertos.length) return null;
  const [p] = abertos;
  return { texto: `${p.produtoNome} · ${p.etapaNome}`, resto: abertos.length - 1 };
}

export interface RascunhoContato {
  nome: string;
  telefone: string;
  email: string;
}

/** Validação do cadastro rápido: nome e pelo menos um canal (telefone com DDD ou e-mail válido). */
export function validarNovoContato(r: RascunhoContato): string | null {
  if (r.nome.trim().length < 2) return 'Informe o nome.';
  const digitos = r.telefone.replace(/\D/g, '');
  const email = r.email.trim();
  if (!digitos && !email) return 'Informe telefone ou e-mail.';
  if (digitos && digitos.length < 10) return 'Telefone incompleto: use DDD + número.';
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return 'E-mail inválido.';
  return null;
}

/**
 * Quem já existe com a mesma identidade antes de salvar: e-mail igual (mesma pessoa, bloqueia)
 * ou mesmo final de telefone (possível duplicado, pede confirmação).
 */
export function conflitosCadastro<T extends Pick<Contato, 'id' | 'email' | 'telefone'>>(
  r: Pick<RascunhoContato, 'telefone' | 'email'>, contatos: T[],
): { mesmoEmail: T[]; mesmoTelefone: T[] } {
  const email = r.email.trim().toLowerCase();
  const k = chaveTelefone(r.telefone);
  const mesmoEmail = email ? contatos.filter((c) => (c.email ?? '').trim().toLowerCase() === email) : [];
  const mesmoTelefone = k
    ? contatos.filter((c) => chaveTelefone(c.telefone) === k && !mesmoEmail.includes(c))
    : [];
  return { mesmoEmail, mesmoTelefone };
}

/**
 * Conflitos a partir da busca no servidor (a tela não tem mais a base inteira): quem a busca pelo e-mail achou é a
 * mesma pessoa (o banco casa o e-mail exato, mesmo que a tela o mostre mascarado); quem a busca pelo telefone achou
 * é possível duplicado. Somam-se os cadastrados só nesta tela (demonstração), pela regra local.
 */
export function conflitosDaBusca<T extends Pick<Contato, 'id' | 'email' | 'telefone'>>(
  r: Pick<RascunhoContato, 'telefone' | 'email'>, porEmail: T[], porTelefone: T[], locais: T[] = [],
): { mesmoEmail: T[]; mesmoTelefone: T[] } {
  const local = conflitosCadastro(r, locais);
  const unicos = (xs: T[]) => xs.filter((x, i) => xs.findIndex((y) => y.id === x.id) === i);
  const mesmoEmail = unicos([...porEmail, ...local.mesmoEmail]);
  const ids = new Set(mesmoEmail.map((c) => c.id));
  const mesmoTelefone = unicos([...porTelefone, ...local.mesmoTelefone]).filter((c) => !ids.has(c.id));
  return { mesmoEmail, mesmoTelefone };
}

/** Termos que valem a busca de conflito no servidor: e-mail completo e telefone com DDD (10+ dígitos). */
export function termosConflito(r: Pick<RascunhoContato, 'telefone' | 'email'>): { email: string | null; telefone: string | null } {
  const email = r.email.trim().toLowerCase();
  const digitos = r.telefone.replace(/\D/g, '');
  return {
    email: /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? email : null,
    telefone: digitos.length >= 10 ? digitos : null,
  };
}
