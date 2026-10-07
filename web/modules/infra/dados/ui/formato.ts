import { numero, type Numerico } from '../domain/presencial';

export const SEM_DADO = 'sem dado';
export const inteiro = (n: Numerico | undefined) => numero(n) === null ? SEM_DADO : numero(n)!.toLocaleString('pt-BR');
export const reais = (n: Numerico | undefined) => numero(n) === null ? SEM_DADO : numero(n)!.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
export const centavos = (n: Numerico | undefined) => numero(n) === null ? 'não lançado' : reais(numero(n)! / 100);
export const percentual = (n: Numerico | undefined) => numero(n) === null ? SEM_DADO : `${numero(n)!.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}%`;
export const dataBR = (valor: string | null | undefined) => valor ? valor.slice(0, 10).split('-').reverse().join('/') : SEM_DADO;
export const dataHoraBR = (valor: string | null | undefined) => valor ? new Date(valor).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : SEM_DADO;
