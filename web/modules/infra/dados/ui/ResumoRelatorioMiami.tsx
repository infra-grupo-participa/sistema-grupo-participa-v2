'use client';

import { KpiCard, ProgressBar, SectionTitle } from '@/shared/ui/components';
import { agruparItens, inteiroDe, percentualDe, type BlocoKpi, type ItemKpi } from '../domain/relatorio-miami';
import { RoscaCategorias } from './viz/RoscaCategorias';

function CartaoKpi({ item }: { item: ItemKpi }) {
  const pct = percentualDe(item.valor);
  return <KpiCard
    label={item.rotulo}
    title={item.rotulo}
    value={item.valor ?? '—'}
    labelClassName="!whitespace-normal"
    hint={pct !== null ? <ProgressBar value={pct} ariaLabel={`${item.rotulo}: ${item.valor}`} /> : undefined}
  />;
}

function BlocoDeKpis({ bloco }: { bloco: BlocoKpi }) {
  const { soltos, grupos } = agruparItens(bloco.itens);
  return <section className="space-y-3" aria-label={bloco.titulo}>
    <SectionTitle>{bloco.titulo}</SectionTitle>
    {soltos.length > 0 && <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{soltos.map((item, i) => <CartaoKpi key={`${item.rotulo}-${i}`} item={item} />)}</div>}
    {grupos.map((grupo) => {
      // Rosca só quando todo o subgrupo é contagem inteira: a soma das fatias é o total do subgrupo.
      const contagens = grupo.itens.map((item) => ({ rotulo: item.rotulo, quantidade: inteiroDe(item.valor) }));
      const rosca = contagens.length >= 2 && contagens.every((c) => c.quantidade !== null);
      return <div key={grupo.titulo} className="space-y-2">
        <h3 className="text-sm font-semibold text-[var(--fg)]">{grupo.titulo}</h3>
        {rosca
          ? <div className="max-w-2xl"><RoscaCategorias titulo={grupo.titulo} fatias={contagens.map((c) => ({ rotulo: c.rotulo, quantidade: c.quantidade! }))} rotuloCentro="pessoas" /></div>
          : <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">{grupo.itens.map((item, i) => <CartaoKpi key={`${item.rotulo}-${i}`} item={item} />)}</div>}
      </div>;
    })}
  </section>;
}

/** Aba Relatório: os três blocos de indicadores da planilha, com rótulo e valor exatos. */
export function ResumoRelatorioMiami({ blocos }: { blocos: BlocoKpi[] }) {
  return <div className="space-y-6">{blocos.map((bloco) => <BlocoDeKpis key={bloco.titulo} bloco={bloco} />)}</div>;
}
