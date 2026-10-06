// Regras puras da base de contatos: busca e aviso de duplicidade. Sem React, testáveis.
import { chaveTelefone } from '../../domain/regras';
import type { Contato, Utm } from '../../domain/types';

/**
 * Possíveis duplicados: contatos que dividem os mesmos últimos 8 dígitos do telefone
 * (mesma pessoa que comprou com outro e-mail ou com/sem DDI). Devolve id → ids dos outros.
 */
export function mapaDuplicados(contatos: Pick<Contato, 'id' | 'telefone'>[]): Map<string, string[]> {
  const porChave = new Map<string, string[]>();
  for (const c of contatos) {
    const k = chaveTelefone(c.telefone);
    if (!k) continue;
    porChave.set(k, [...(porChave.get(k) ?? []), c.id]);
  }
  const mapa = new Map<string, string[]>();
  for (const ids of porChave.values()) {
    if (ids.length < 2) continue;
    for (const id of ids) mapa.set(id, ids.filter((x) => x !== id));
  }
  return mapa;
}

/** Busca por nome, e-mail ou telefone (aceita qualquer formatação e compara pelos últimos 8 dígitos). */
export function casaBusca(c: Pick<Contato, 'nome' | 'email' | 'telefone'>, termo: string): boolean {
  const q = termo.trim().toLowerCase();
  if (!q) return true;
  const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '');
  if (sem(`${c.nome} ${c.email ?? ''}`.toLowerCase()).includes(sem(q))) return true;
  const digitos = q.replace(/\D/g, '');
  if (digitos.length < 4) return false;
  const tel = String(c.telefone ?? '').replace(/\D/g, '');
  if (tel.includes(digitos)) return true;
  const k = chaveTelefone(digitos);
  return !!k && k === chaveTelefone(tel);
}

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
