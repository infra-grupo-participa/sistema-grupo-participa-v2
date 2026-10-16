'use client';

import { useState } from 'react';
import { DataTable, EmptyState, SectionTitle, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { barrasDeColuna, ehVazio, type BlocoTabela } from '../domain/relatorio-miami';
import { ModalLinhaRelatorio } from './ModalLinhaRelatorio';
import { BarrasHorizontais } from './viz/BarrasHorizontais';

// Cabeçalhos exatos da tabela "Presença por evento" (contrato §2.12.1). Uma barra por evento; evento com "—" fica fora da barra (não é zero).
const COLUNAS_GRAFICO = ['Diamante: total estimado', 'Time: total estimado', 'Total geral estimado (Diamante + Time)'];

export function PresencaMiami({ presenca, camisas }: { presenca: BlocoTabela; camisas: BlocoTabela }) {
  const [aberta, setAberta] = useState<number | null>(null);
  const graficos = COLUNAS_GRAFICO.map((titulo) => ({ titulo, dados: barrasDeColuna(presenca, titulo) })).filter((g) => g.dados !== null);
  const linhaAberta = aberta === null ? undefined : presenca.linhas[aberta];
  const mobile = [1, presenca.colunas.length - 1].filter((k, i, a) => k > 0 && k < presenca.colunas.length && a.indexOf(k) === i);
  const ultimaLinhaCamisas = camisas.linhas.length - 1;

  return <div className="space-y-6">
    <section className="space-y-3" aria-label={presenca.titulo}>
      <SectionTitle>{presenca.titulo}</SectionTitle>
      {!presenca.linhas.length ? <EmptyState title="Nenhum evento na planilha" /> : <>
        {graficos.length > 0 && <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {graficos.map((g) => <div key={g.titulo} className="min-w-0">
            <BarrasHorizontais titulo={g.titulo} barras={g.dados!.barras} onSelect={(valor) => setAberta(Number(valor))} />
            {g.dados!.semDado > 0 && <p className="mt-1 px-1 text-[11px] text-[var(--fg-3)]">{g.dados!.semDado.toLocaleString('pt-BR')} evento(s) sem dado na planilha</p>}
          </div>)}
        </div>}
        <ul className="space-y-2 sm:hidden" aria-label={presenca.titulo}>
          {presenca.linhas.map((l, i) => <li key={i}><button type="button" onClick={() => setAberta(i)} className="block w-full rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-left shadow-[var(--shadow-xs)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
            <span className="block break-words text-sm font-semibold text-[var(--fg)]">{l[0] || '—'}</span>
            {mobile.map((k) => <span key={k} className="mt-1 block text-xs text-[var(--fg-2)]"><span className="text-[var(--fg-3)]">{presenca.colunas[k]}: </span>{l[k].trim() === '' ? '—' : l[k]}</span>)}
          </button></li>)}
        </ul>
        <div className="hidden sm:block">
          <DataTable minWidth={Math.max(720, presenca.colunas.length * 130)}>
            <Thead>{presenca.colunas.map((c, k) => <Th key={c} className={k >= 2 ? 'text-right' : ''}><span title={c}>{c}</span></Th>)}</Thead>
            <tbody>{presenca.linhas.map((l, i) => <Tr key={i} onClick={() => setAberta(i)}>
              {l.map((v, k) => {
                const texto = v.trim() === '' ? '—' : v;
                return <Td key={k} className={`${k >= 2 ? 'text-right tabular' : ''} ${ehVazio(v) ? 'text-[var(--fg-3)]' : ''}`}>
                  {k === 0 ? <button type="button" onClick={(e) => { e.stopPropagation(); setAberta(i); }} className="text-left font-medium text-[var(--fg)] hover:underline focus-visible:outline-2 focus-visible:outline-[var(--accent)]">{texto}</button> : texto}
                </Td>;
              })}
            </Tr>)}</tbody>
          </DataTable>
        </div>
      </>}
    </section>

    <section className="space-y-3" aria-label={camisas.titulo}>
      <SectionTitle>{camisas.titulo}</SectionTitle>
      {!camisas.linhas.length ? <EmptyState title="Nenhuma resposta de camisa na planilha" /> : <div className="max-w-xl">
        <DataTable>
          <Thead>{camisas.colunas.map((c, k) => <Th key={c} className={k >= 1 ? 'text-right' : ''}>{c}</Th>)}</Thead>
          <tbody>{camisas.linhas.map((l, i) => <Tr key={i} className={i === ultimaLinhaCamisas && l[0].trim().toLocaleLowerCase('pt-BR') === 'total' ? 'font-semibold' : ''}>
            {l.map((v, k) => <Td key={k} className={k >= 1 ? 'text-right tabular' : 'text-[var(--fg)]'}>{v.trim() === '' ? '—' : v}</Td>)}
          </Tr>)}</tbody>
        </DataTable>
      </div>}
    </section>

    {linhaAberta && <ModalLinhaRelatorio titulo={presenca.titulo} colunas={presenca.colunas} celulas={linhaAberta} onClose={() => setAberta(null)} />}
  </div>;
}
