// Formatação da Central do Tráfego. Valor nulo = "sem dado" (sem fonte ainda), nunca zero nem traço.
export const SEM_DADO = 'sem dado';

export const reais = (n: number | null | undefined) =>
  n == null ? SEM_DADO : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });

export const centavos = (n: number | null | undefined) =>
  n == null ? SEM_DADO : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 2 });

export const pct = (n: number | null | undefined, casas = 1) =>
  n == null ? SEM_DADO : `${Number(n).toLocaleString('pt-BR', { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;

export const inteiro = (n: number | null | undefined) => (n == null ? SEM_DADO : Number(n).toLocaleString('pt-BR'));

export const dataBR = (ymd: string | null | undefined) => (ymd ? ymd.slice(0, 10).split('-').reverse().join('/') : SEM_DADO);
