'use client';

import { useMemo, useState } from 'react';
import { DataTable, EmptyState, SearchInput, Td, Th, Thead, Toggle, Toolbar, Tr } from '@/shared/ui/components';
import { buscar, contarPorValor, ehVazio, indexar, ordenar, valoresCategoricos, type BlocoTabela, type LinhaIndexada } from '../domain/relatorio-miami';
import { ModalLinhaRelatorio } from './ModalLinhaRelatorio';
import { BarrasHorizontais } from './viz/BarrasHorizontais';

/** Colunas com e-mail e telefone. Com `contato_visivel` falso (nível de acesso futuro) somem da tabela e do detalhe. */
export const COLUNAS_CONTATO = ['E-mail', 'Telefone (WhatsApp)', 'Telefone'];

const SEM_OCULTAS: string[] = [];
type Ordem = { coluna: number; dir: 'asc' | 'desc' };

export function TabelaRelatorioMiami({ bloco, colunasPadrao, graficos = [], colunasMobile, contatoVisivel }: {
  bloco: BlocoTabela;
  /** Cabeçalhos exatos mostrados na tabela; as demais colunas ficam no detalhe e em "Todas as colunas". Sem isso, todas aparecem. */
  colunasPadrao?: string[];
  /** Cabeçalhos exatos das colunas que ganham barras (só entram se tiverem poucos valores distintos). */
  graficos?: string[];
  colunasMobile?: string[];
  contatoVisivel: boolean;
}) {
  const [busca, setBusca] = useState('');
  const [ordem, setOrdem] = useState<Ordem | null>(null);
  const [filtros, setFiltros] = useState<Record<number, string>>({});
  const [todas, setTodas] = useState(false);
  const [aberta, setAberta] = useState<number | null>(null);

  const ocultas = contatoVisivel ? SEM_OCULTAS : COLUNAS_CONTATO;
  const permitidas = useMemo(() => bloco.colunas.map((_, i) => i).filter((i) => !ocultas.includes(bloco.colunas[i])), [bloco.colunas, ocultas]);
  const indicesTabela = useMemo(() => {
    if (todas || !colunasPadrao) return permitidas;
    const escolhidas = colunasPadrao.map((nome) => bloco.colunas.indexOf(nome)).filter((i) => i >= 0 && permitidas.includes(i));
    return escolhidas.length ? escolhidas : permitidas;
  }, [todas, colunasPadrao, bloco.colunas, permitidas]);
  const podeAlternarColunas = (!!colunasPadrao && indicesTabela.length !== permitidas.length) || todas;

  const base = useMemo(() => indexar(bloco.linhas), [bloco.linhas]);
  const buscadas = useMemo(() => buscar(base, busca), [base, busca]);
  const filtradas = useMemo(() => buscadas.filter((l) => Object.entries(filtros).every(([c, v]) => l.celulas[Number(c)] === v)), [buscadas, filtros]);
  const visiveis = useMemo(() => ordem ? ordenar(filtradas, ordem.coluna, ordem.dir) : filtradas, [filtradas, ordem]);

  const graficosElegiveis = useMemo(() => graficos
    .map((titulo) => ({ titulo, coluna: bloco.colunas.indexOf(titulo) }))
    .filter((g) => g.coluna >= 0 && !ocultas.includes(g.titulo))
    .map((g) => ({ ...g, valores: valoresCategoricos(bloco.linhas, g.coluna) }))
    .filter((g): g is { titulo: string; coluna: number; valores: string[] } => g.valores !== null),
  [graficos, bloco.colunas, bloco.linhas, ocultas]);

  const alternarFiltro = (coluna: number, valor: string) => setFiltros((atual) => {
    const proximo = { ...atual };
    if (proximo[coluna] === valor) delete proximo[coluna]; else proximo[coluna] = valor;
    return proximo;
  });
  const alternarOrdem = (coluna: number) => setOrdem((atual) => !atual || atual.coluna !== coluna ? { coluna, dir: 'asc' } : atual.dir === 'asc' ? { coluna, dir: 'desc' } : null);
  const nomesMobile = (colunasMobile ?? indicesTabela.slice(1, 4).map((i) => bloco.colunas[i])).filter((n) => bloco.colunas.includes(n) && !ocultas.includes(n));
  const filtrosAtivos = Object.entries(filtros);
  const abertaLinha: LinhaIndexada | undefined = aberta === null ? undefined : base.find((l) => l.i === aberta);

  if (!bloco.linhas.length) return <EmptyState title="Esta tabela está vazia na planilha" hint="Quando a planilha tiver linhas, elas aparecem aqui na próxima leitura." />;

  return <div className="space-y-4">
    {graficosElegiveis.length > 0 && <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
      {graficosElegiveis.map((g) => {
        const outrosFiltros = Object.entries(filtros).filter(([c]) => Number(c) !== g.coluna);
        const linhasDoGrafico = buscadas.filter((l) => outrosFiltros.every(([c, v]) => l.celulas[Number(c)] === v));
        const { barras, semValor } = contarPorValor(linhasDoGrafico, g.coluna, g.valores);
        return <div key={g.titulo} className="min-w-0">
          <BarrasHorizontais titulo={g.titulo} barras={barras} selecionado={filtros[g.coluna]} onSelect={(valor) => alternarFiltro(g.coluna, valor)} />
          {semValor > 0 && <p className="mt-1 px-1 text-[11px] text-[var(--fg-3)]">{semValor.toLocaleString('pt-BR')} sem valor na planilha</p>}
        </div>;
      })}
    </div>}

    <Toolbar>
      <SearchInput aria-label={`Buscar em ${bloco.titulo}`} placeholder="Buscar em qualquer coluna" value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} />
      {podeAlternarColunas && <Toggle checked={todas} onChange={setTodas} label="Todas as colunas" />}
      <span className="ml-auto text-xs tabular text-[var(--fg-3)]" role="status">{visiveis.length.toLocaleString('pt-BR')} de {base.length.toLocaleString('pt-BR')} linhas</span>
    </Toolbar>
    {filtrosAtivos.length > 0 && <div className="flex flex-wrap gap-2">
      {filtrosAtivos.map(([c, v]) => <button key={c} type="button" onClick={() => alternarFiltro(Number(c), v)} className="max-w-full truncate rounded-full border border-[var(--accent)] px-3 py-1 text-xs text-[var(--accent)]" title={`${bloco.colunas[Number(c)]}: ${v}`}>{bloco.colunas[Number(c)]}: {v} ×</button>)}
      <button type="button" onClick={() => setFiltros({})} className="rounded-full px-3 py-1 text-xs text-[var(--fg-2)] underline">Limpar filtros</button>
    </div>}

    {visiveis.length === 0 ? <EmptyState title="Nenhuma linha para a busca e os filtros atuais" /> : <>
      <ul className="space-y-2 sm:hidden" aria-label={bloco.titulo}>
        {visiveis.map((l) => <li key={l.i}><button type="button" onClick={() => setAberta(l.i)} className="block w-full rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-left shadow-[var(--shadow-xs)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]">
          <span className="block break-words text-sm font-semibold text-[var(--fg)]">{l.celulas[0] || '—'}</span>
          {nomesMobile.map((nome) => { const v = l.celulas[bloco.colunas.indexOf(nome)] ?? ''; return <span key={nome} className="mt-1 block text-xs text-[var(--fg-2)]"><span className="text-[var(--fg-3)]">{nome}: </span>{v.trim() === '' ? '—' : v}</span>; })}
        </button></li>)}
      </ul>
      <div className="hidden sm:block">
        <DataTable minWidth={Math.max(720, indicesTabela.length * 150)} className="[&>div]:max-h-[70vh]">
          <Thead>{indicesTabela.map((i) => <Th key={i} sortable active={ordem?.coluna === i} dir={ordem?.dir} onClick={() => alternarOrdem(i)}><span title={bloco.colunas[i]}>{bloco.colunas[i]}</span></Th>)}</Thead>
          <tbody>{visiveis.map((l) => <Tr key={l.i} onClick={() => setAberta(l.i)}>
            {indicesTabela.map((i, pos) => {
              const v = l.celulas[i] ?? '';
              const texto = v.trim() === '' ? '—' : v;
              return <Td key={i} className={ehVazio(v) ? 'text-[var(--fg-3)]' : ''}>
                {pos === 0 ? <button type="button" onClick={(e) => { e.stopPropagation(); setAberta(l.i); }} className="block max-w-[18rem] truncate text-left font-medium text-[var(--fg)] hover:underline focus-visible:outline-2 focus-visible:outline-[var(--accent)]" title={texto}>{texto}</button>
                  : <span className="block max-w-[16rem] truncate" title={texto}>{texto}</span>}
              </Td>;
            })}
          </Tr>)}</tbody>
        </DataTable>
      </div>
    </>}
    {abertaLinha && <ModalLinhaRelatorio titulo={bloco.titulo} colunas={bloco.colunas} celulas={abertaLinha.celulas} ocultar={ocultas} onClose={() => setAberta(null)} />}
  </div>;
}
