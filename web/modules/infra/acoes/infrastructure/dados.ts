'use client';

import type { DashboardAtm } from '@/modules/infra/atm/domain/dashboard';
import {
  carregarAtmCanais,
  carregarAtmComparecimento,
  carregarAtmDisparosLista,
  carregarAtmResumo,
  carregarAtmSerie,
  type DisparoDetalheAtm,
  type Resultado,
} from '@/modules/infra/atm/infrastructure/atm-data';
import type { RegistroAcaoBlack } from '../domain/registro';

export type LinhaAcoes = Record<string, unknown>;
export type EstadoDadosAcoesBlack = {
  emPreparacao: boolean;
  resumo: Resultado<DashboardAtm>;
  serie: Resultado<LinhaAcoes[]>;
  canais: Resultado<LinhaAcoes[]>;
  disparos: Resultado<DisparoDetalheAtm[]>;
  comparecimento: Resultado<LinhaAcoes[]>;
};

const CHAVE_NAO_CADASTRADA = 'Dashboard ou identificador não encontrado neste evento.';
const MENSAGEM_EM_PREPARACAO = 'Dashboard em preparação. A etiqueta ainda não foi cadastrada no banco.';

function ocultarP0002<T>(resultado: Resultado<T>): Resultado<T> {
  return resultado.erro === CHAVE_NAO_CADASTRADA ? { ...resultado, erro: null } : resultado;
}

/** Usa as RPCs compartilhadas do ATM. Uma ação sem etiqueta nunca dispara consulta. */
export async function carregarDadosAcoesBlack(acao: RegistroAcaoBlack): Promise<EstadoDadosAcoesBlack | null> {
  if (acao.estado !== 'ativa' || !acao.etiqueta) return null;

  const [resumo, serie, canais, disparos, comparecimento] = await Promise.all([
    carregarAtmResumo(acao.etiqueta),
    carregarAtmSerie(acao.etiqueta),
    carregarAtmCanais(acao.etiqueta),
    carregarAtmDisparosLista(acao.etiqueta),
    carregarAtmComparecimento(acao.etiqueta),
  ]);
  const emPreparacao = [resumo, serie, canais, disparos, comparecimento].some((r) => r.erro === CHAVE_NAO_CADASTRADA);
  return {
    emPreparacao,
    resumo: ocultarP0002(resumo),
    serie: ocultarP0002(serie),
    canais: ocultarP0002(canais),
    disparos: ocultarP0002(disparos),
    comparecimento: ocultarP0002(comparecimento),
  };
}

export function mensagemEmPreparacao(): string {
  return MENSAGEM_EM_PREPARACAO;
}
