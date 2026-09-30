// Modelo e regras puras da LinhaDoTempo (sem React) — testáveis no vitest em ambiente node.
import type { ReactNode } from 'react';
import type { Tone } from '@/shared/ui/components';

export interface BadgeLinhaDoTempo {
  rotulo: string;
  tom?: Tone;
}

/** Cor do marcador na linha vertical. Cor só onde significa algo (alerta, positivo). */
export type TomMarcador = 'neutral' | 'accent' | 'success' | 'warning' | 'danger';

export interface ItemLinhaDoTempo {
  id: string;
  /** 'YYYY-MM-DD' — exibido em pt-BR. */
  dia: string;
  titulo: ReactNode;
  /** Bloco abaixo do título (texto ou lista). */
  detalhe?: ReactNode;
  /** Linha pequena e discreta (ex.: a regra que gerou o registro, para a equipe conferir). Também vira tooltip. */
  nota?: string | null;
  dimensao?: string;
  badges?: BadgeLinhaDoTempo[];
  /** Já formatado. Ausente/null = nada é mostrado. */
  valor?: ReactNode;
  tom?: TomMarcador;
}

export interface DimensaoLinhaDoTempo {
  chave: string;
  rotulo: string;
}

export interface ChipDimensao {
  chave: string | null; // null = "Todas"
  rotulo: string;
  total: number;
}

/** Chips de filtro: "Todas" + uma por dimensão, na ordem recebida, com a contagem de itens. */
export function chipsDeDimensao(itens: Pick<ItemLinhaDoTempo, 'dimensao'>[], dimensoes: DimensaoLinhaDoTempo[]): ChipDimensao[] {
  const conta = new Map<string, number>();
  for (const it of itens) if (it.dimensao) conta.set(it.dimensao, (conta.get(it.dimensao) ?? 0) + 1);
  return [
    { chave: null, rotulo: 'Todas', total: itens.length },
    ...dimensoes.map((d) => ({ chave: d.chave, rotulo: d.rotulo, total: conta.get(d.chave) ?? 0 })),
  ];
}

/** Filtro no cliente. `ativa` null = todas. Preserva a ordem recebida. */
export function filtrarPorDimensao<T extends Pick<ItemLinhaDoTempo, 'dimensao'>>(itens: T[], ativa: string | null): T[] {
  return ativa == null ? itens : itens.filter((it) => it.dimensao === ativa);
}
