// Aba Escritório · Contratos (z93). Cache criado no FinanceiroClient (useState), como o do Funil: a aba desmonta a cada
// troca de aba, então o cache não pode morar nela.
//
// Consultas: os PAGAMENTOS HF da Hotmart (fn_fin_contratos_hf_pagamentos(false): a fila de conferência sai deles por
// filtro local, e o status da sincronização vem em toda linha — com p_so_fila=true, fila vazia esconderia um erro de
// sincronização) são a sonda: 1 chamada na 1ª vez que a aba Escritório abre, e decide se a sub-aba Contratos aparece:
// função ausente no banco (z93 não aplicada) = sub-aba escondida, sem erro na tela. A GRADE (fn_fin_contratos_hf_mensal) só na 1ª vez que a sub-aba Contratos abre. Voltar não consulta de novo.
// O STATUS da sincronização (fn_fin_contratos_hf_sync_status, 1 linha) só na 1ª vez que a sub-aba abre — não muda com
// escrita da tela (só o cron :25 grava), então invalidar() não o esquece.
// Depois de gravar: invalidar() e a tela pede grade e pagamentos de novo (2 chamadas). Falha não fica guardada.
import { RecursoAusenteError, type FinanceiroRepository, type ImportacaoInformados } from './ports';
import type { LinhaMensalContratoHF, PagamentoContratoHF, SyncStatusContratosHF } from '../domain/contratos-hf';
import { nomesDiferentesDaFicha, normalizarNome } from '../domain/contratos-hf';
import {
  entradaDoFormulario, TIPO_CONTRATO, type FormInformado, type InformadoEntrada,
} from '../domain/recebimentos-informados';

type RepoContratos = Pick<FinanceiroRepository, 'loadContratosHfMensal' | 'loadContratosHfPagamentos' | 'loadContratosHfSyncStatus'>;

/** desconhecida = a sonda ainda não respondeu; nao = a z93 não está no banco (a sub-aba some). */
export type DisponibilidadeContratos = 'desconhecida' | 'sim' | 'nao';

export interface CacheContratosHF {
  disponibilidade(): DisponibilidadeContratos;
  /** 1 chamada (os pagamentos) na 1ª vez; depois devolve o que já sabe. Nunca rejeita. */
  sondar(): Promise<DisponibilidadeContratos>;
  gradeLida(): LinhaMensalContratoHF[] | undefined;
  grade(): Promise<LinhaMensalContratoHF[]>;
  pagamentosLidos(): PagamentoContratoHF[] | undefined;
  pagamentos(): Promise<PagamentoContratoHF[]>;
  syncLido(): SyncStatusContratosHF | undefined;
  sync(): Promise<SyncStatusContratosHF>;
  /** Depois de uma escrita: esquece grade e pagamentos (a próxima leitura consulta). Resposta em voo não é guardada. */
  invalidar(): void;
}

/** Uma promessa por vez; erro não fica guardado; limpar() descarta o valor e ignora a resposta que ainda estava em voo. */
function memo<V>(carregar: () => Promise<V>) {
  let pronto: { v: V } | null = null;
  let voo: Promise<V> | null = null;
  let geracao = 0;
  return {
    lido: () => pronto?.v,
    obter(): Promise<V> {
      if (pronto) return Promise.resolve(pronto.v);
      if (voo) return voo;
      const g = geracao;
      const p = carregar().then(
        (v) => { if (g === geracao) { pronto = { v }; voo = null; } return v; },
        (e: unknown) => { if (g === geracao) voo = null; throw e; },
      );
      voo = p;
      return p;
    },
    limpar() { geracao += 1; pronto = null; voo = null; },
  };
}

export function criarCacheContratosHF(repo: RepoContratos): CacheContratosHF {
  let disp: DisponibilidadeContratos = 'desconhecida';
  const marcar = (e: unknown) => { if (e instanceof RecursoAusenteError) disp = 'nao'; };
  const grade = memo(() => repo.loadContratosHfMensal(null, null).catch((e: unknown) => { marcar(e); throw e; }));
  const pags = memo(() => repo.loadContratosHfPagamentos(false).then(
    (v) => { disp = 'sim'; return v; },
    (e: unknown) => { marcar(e); throw e; },
  ));
  const sync = memo(() => repo.loadContratosHfSyncStatus());
  let sonda: Promise<DisponibilidadeContratos> | null = null;
  return {
    disponibilidade: () => disp,
    sondar() {
      if (disp !== 'desconhecida') return Promise.resolve(disp);
      // Erro que não é "função ausente" (rede, permissão): a sub-aba aparece e mostra o erro com "tentar de novo".
      sonda ??= pags.obter().then(() => disp, () => {
        sonda = null;
        if (disp === 'desconhecida') disp = 'sim';
        return disp;
      });
      return sonda;
    },
    gradeLida: () => grade.lido(),
    grade: () => grade.obter(),
    pagamentosLidos: () => pags.lido(),
    pagamentos: () => pags.obter(),
    syncLido: () => sync.lido(),
    sync: () => sync.obter(),
    invalidar() { grade.limpar(); pags.limpar(); },
  };
}

/**
 * Pergunta à tela se grava mesmo assim: os nomes enviados não são o da ficha. O banco grava a parcela com o nome da ficha
 * e guarda o enviado em observacao ("cliente informado na colagem: X") — a confirmação é da tela. true = seguir.
 */
export type ConfirmarNomes = (nomes: string[]) => Promise<boolean>;

/**
 * "Colar da planilha" dentro da ficha: reusa ColarDaPlanilha (Informados.tsx) com um repo que liga cada linha A ESTE
 * contrato (contrato_id). Antes de enviar (já na conferência, que manda o texto ao banco): linha que não é contrato
 * Holding Familiar é recusada; nome diferente do da ficha pede confirmação explícita (uma vez por nome).
 */
export function repoColagemNoContrato(
  repo: Pick<FinanceiroRepository, 'importarInformados'>, contratoId: string, nomeFicha: string | null, confirmar: ConfirmarNomes,
): Pick<FinanceiroRepository, 'importarInformados'> {
  const confirmados = new Set<string>();
  return {
    async importarInformados(linhas: InformadoEntrada[], simular: boolean): Promise<ImportacaoInformados> {
      if (linhas.some((l) => l.tipo !== TIPO_CONTRATO)) {
        return { ok: false, msg: 'Aqui só entram parcelas de contrato Holding Familiar (planilha Contratos Soluções).', linhas: [] };
      }
      const novos = nomesDiferentesDaFicha(linhas.map((l) => l.cliente), nomeFicha).filter((n) => !confirmados.has(normalizarNome(n)));
      if (novos.length) {
        if (!(await confirmar(novos))) return { ok: false, msg: 'Nada foi enviado: o nome da planilha não é o desta ficha.', linhas: [] };
        for (const n of novos) confirmados.add(normalizarNome(n));
      }
      return repo.importarInformados(linhas.map((l) => ({ ...l, contrato_id: contratoId })), simular);
    },
  };
}

/** Nova parcela na ficha: o formulário de Informados (FormularioInformado) + contrato_id. Tipo é sempre contrato HF. */
export function entradaNovaParcela(
  f: FormInformado, contratoId: string, podeVerDoc: boolean,
): { entrada: InformadoEntrada | null; erros: string[] } {
  const r = entradaDoFormulario({ ...f, tipo: TIPO_CONTRATO }, null, podeVerDoc);
  return r.entrada ? { entrada: { ...r.entrada, contrato_id: contratoId }, erros: r.erros } : r;
}
