// Edição manual do contato pela ficha (crm_editar_contato, migration 20261008182832). Regras puras: rascunho a partir
// do contato, validação (a mesma do banco) e o que mudou (só isso vai para a RPC). Sem React, testáveis.
import type { AtuaComHolding, Contato, PerfilProfissional } from './types';

/** Texto que o banco devolve quando a pessoa não tem nome em lugar nenhum (crm.contatos_itens). */
export const NOME_VAZIO = '(sem nome)';

/** Contato sem nome: o atalho "Adicionar nome" aparece. */
export function semNome(nome: string | null | undefined): boolean {
  const n = (nome ?? '').trim();
  return !n || n === NOME_VAZIO;
}

export interface RascunhoEdicao {
  nome: string;
  email: string;
  telefone: string;
  cidade: string;
  uf: string;
  perfil: PerfilProfissional | '';
  atuaComHolding: AtuaComHolding | '';
  empresa: string;
  observacao: string;
}

/** Valor mascarado (contato de outro dono): não serve de ponto de partida nem de comparação. */
const mascarado = (v: string | null | undefined) => !!v && v.includes('*');

/** Rascunho inicial do formulário: o que a ficha mostra hoje (sem "(sem nome)" e sem valor mascarado). */
export function rascunhoDe(c: Pick<Contato, 'nome' | 'email' | 'telefone' | 'cidade' | 'uf' | 'perfil' | 'atuaComHolding' | 'empresa' | 'observacao'>): RascunhoEdicao {
  return {
    nome: semNome(c.nome) ? '' : c.nome.trim(),
    email: c.email && !mascarado(c.email) ? c.email : '',
    telefone: c.telefone && !mascarado(c.telefone) ? c.telefone : '',
    cidade: c.cidade ?? '',
    uf: c.uf ?? '',
    perfil: c.perfil ?? '',
    atuaComHolding: c.atuaComHolding ?? '',
    empresa: c.empresa ?? '',
    observacao: c.observacao ?? '',
  };
}

export const LIMITES_EDICAO = { nome: 160, cidade: 120, empresa: 160, observacao: 1000 } as const;

/** Espelho da validação do banco. null = pode salvar. */
export function validarEdicao(r: RascunhoEdicao): string | null {
  const nome = r.nome.trim();
  if (nome.length < 2) return 'Informe o nome.';
  if (nome.length > LIMITES_EDICAO.nome) return 'Nome longo demais (até 160 caracteres).';
  const email = r.email.trim();
  if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return 'E-mail inválido.';
  const digitos = r.telefone.replace(/\D/g, '');
  if (r.telefone.trim() && (digitos.length < 10 || digitos.length > 13)) return 'Telefone inválido: use DDD + número.';
  if (r.cidade.trim().length > LIMITES_EDICAO.cidade) return 'Cidade longa demais (até 120 caracteres).';
  const uf = r.uf.trim();
  if (uf && !/^[A-Za-z]{2}$/.test(uf)) return 'UF inválida: use a sigla (ex.: SP).';
  if (r.empresa.trim().length > LIMITES_EDICAO.empresa) return 'Empresa longa demais (até 160 caracteres).';
  if (r.observacao.trim().length > LIMITES_EDICAO.observacao) return 'Observação longa demais (até 1.000 caracteres).';
  return null;
}

/** Chaves que a RPC aceita (p_dados). */
export type CampoEdicao = 'nome' | 'email' | 'telefone' | 'cidade' | 'uf' | 'perfil' | 'atuaComHolding' | 'empresa' | 'observacao';

const soDigitos = (v: string) => v.replace(/\D/g, '');

/**
 * Só o que mudou em relação ao rascunho inicial (a RPC mexe só nas chaves presentes). Telefone compara por dígitos;
 * e-mail sem caixa; UF em maiúsculas. Vazio vai como '' (o banco volta ao dado da base central).
 */
export function mudancasEdicao(inicial: RascunhoEdicao, r: RascunhoEdicao): Partial<Record<CampoEdicao, string>> {
  const out: Partial<Record<CampoEdicao, string>> = {};
  const txt = (k: 'nome' | 'cidade' | 'empresa' | 'observacao') => {
    if (r[k].trim() !== inicial[k].trim()) out[k] = r[k].trim();
  };
  txt('nome');
  if (r.email.trim().toLowerCase() !== inicial.email.trim().toLowerCase()) out.email = r.email.trim();
  if (soDigitos(r.telefone) !== soDigitos(inicial.telefone)) out.telefone = r.telefone.trim();
  txt('cidade');
  if (r.uf.trim().toUpperCase() !== inicial.uf.trim().toUpperCase()) out.uf = r.uf.trim().toUpperCase();
  if (r.perfil !== inicial.perfil) out.perfil = r.perfil;
  if (r.atuaComHolding !== inicial.atuaComHolding) out.atuaComHolding = r.atuaComHolding;
  txt('empresa');
  txt('observacao');
  return out;
}
