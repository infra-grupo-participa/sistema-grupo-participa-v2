// Regras puras do cadastro de motivos de perda (aba #motivos). Os 9 de fábrica vêm do playbook e só mudam
// nota e ativo; os personalizados o gestor cria, edita e desativa. Nada se apaga: perdido antigo mantém o motivo.
import { chaveMotivo } from '../../domain/catalogo';
import type { MotivoPerdaConfig } from '../../domain/types';

export interface RascunhoMotivo {
  label: string;
  nota: string;
  reativa: boolean;
  bloqueia: boolean;
  alertaGestor: boolean;
}

export const LIMITE_NOME_MOTIVO = 60;

/** Rascunho do modal: vazio para motivo novo, cópia do salvo para edição. */
export function rascunhoMotivo(m?: MotivoPerdaConfig | null): RascunhoMotivo {
  return {
    label: m?.label ?? '',
    nota: m?.nota ?? '',
    reativa: m?.reativa ?? false,
    bloqueia: m?.bloqueia ?? false,
    alertaGestor: m?.alertaGestor ?? false,
  };
}

const normal = (s: string) => s.trim().toLowerCase();

export type ValidacaoMotivo = { ok: true; motivo: MotivoPerdaConfig } | { ok: false; erro: string };

/**
 * Monta o motivo a salvar. `editando` null = motivo novo (chave sai do nome por `chaveMotivo`).
 * De fábrica: só a nota muda aqui (ativo muda pelo botão da lista).
 */
export function validarMotivo(r: RascunhoMotivo, cadastro: MotivoPerdaConfig[], editando: MotivoPerdaConfig | null): ValidacaoMotivo {
  const nota = r.nota.trim() || null;
  if (editando?.sistema) return { ok: true, motivo: { ...editando, nota } };

  const label = r.label.trim().replace(/\s+/g, ' ');
  if (label.length < 3) return { ok: false, erro: 'Dê um nome ao motivo (pelo menos 3 letras).' };
  if (label.length > LIMITE_NOME_MOTIVO) return { ok: false, erro: `Nome com até ${LIMITE_NOME_MOTIVO} caracteres.` };
  if (r.reativa && r.bloqueia) return { ok: false, erro: 'Quem vai para a lista de bloqueio não volta para reativação: escolha um dos dois.' };

  const key = editando?.key ?? chaveMotivo(label);
  if (!key) return { ok: false, erro: 'Use letras ou números no nome.' };
  const outros = cadastro.filter((m) => m.key !== editando?.key);
  if (outros.some((m) => normal(m.label) === normal(label))) return { ok: false, erro: 'Já existe um motivo com esse nome.' };
  if (!editando && cadastro.some((m) => m.key === key)) return { ok: false, erro: 'Já existe um motivo parecido com esse nome.' };

  return {
    ok: true,
    motivo: {
      key, label, nota,
      reativa: r.reativa, bloqueia: r.bloqueia, alertaGestor: r.alertaGestor,
      sistema: false, ativo: editando?.ativo ?? true,
    },
  };
}

/** Chave que o motivo novo vai ganhar (prévia no modal). */
export function previaChave(label: string): string {
  return chaveMotivo(label.trim());
}

export function alternarAtivo(m: MotivoPerdaConfig): MotivoPerdaConfig {
  return { ...m, ativo: !m.ativo };
}

/** Ativos antes dos desativados; dentro de cada grupo, os de fábrica (ordem do playbook) e depois os personalizados por nome. */
export function ordenarMotivos(lista: MotivoPerdaConfig[]): MotivoPerdaConfig[] {
  return lista
    .map((m, i) => ({ m, i }))
    .sort((a, b) => {
      if (a.m.ativo !== b.m.ativo) return a.m.ativo ? -1 : 1;
      if (a.m.sistema !== b.m.sistema) return a.m.sistema ? -1 : 1;
      if (a.m.sistema) return a.i - b.i;
      return a.m.label.localeCompare(b.m.label, 'pt-BR');
    })
    .map((x) => x.m);
}

export interface ResumoMotivos {
  ativos: number;
  personalizados: number;
  desativados: number;
}

export function resumoMotivos(lista: MotivoPerdaConfig[]): ResumoMotivos {
  return {
    ativos: lista.filter((m) => m.ativo).length,
    personalizados: lista.filter((m) => !m.sistema).length,
    desativados: lista.filter((m) => !m.ativo).length,
  };
}
