// Helpers compartilhados entre as visões do painel admin de placas.
// Formatadores vivem em shared/ui/format — aqui só o contrato de ação e re-exports.

/** Executa uma ação de dados, exibe toast com o resultado e recarrega a lista. */
export type Act = (fn: () => Promise<{ ok: boolean; msg?: string } | boolean>) => Promise<void>;

export { fmtBRL, fmtDataExtenso, fmtRelativo } from '@/shared/ui/format';
