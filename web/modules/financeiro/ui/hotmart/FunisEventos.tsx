'use client';

// Funis (eventos) — Faturamento › Funis (28/09/2026). Macro: por setor (educação × escritório) e categoria, quanto
// entrou, quantas pessoas pagaram, média por evento. Micro: cada evento com ingresso + oferta, a conferência com o
// número registrado na época e, ao clicar, quem pagou.
import { Fragment, useMemo, useState } from 'react';
import { DataTable, Drawer, Loading, SearchInput, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import {
  diferencaPct, resumirPorCategoria, rotuloCategoriaFunil, valorParaConferencia, vendasParaConferencia,
  type CompradorFunil, type Funil, type Setor,
} from '../../domain/funis';
import { celulaCsv } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';
import { Trajetoria } from '../Trajetoria';

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

export function FunisEventos({ repo }: { repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<Funil[]>(() => repo.loadFunis(), []);
  const [setor, setSetor] = useState<Setor>('educacao');
  const [categoria, setCategoria] = useState<string | null>(null);
  const [ano, setAno] = useState<string | null>(null);
  const [aberto, setAberto] = useState<Funil | null>(null);

  const doSetor = useMemo(() => (dados ?? []).filter((f) => f.setor === setor), [dados, setor]);
  const anos = useMemo(() => [...new Set(doSetor.map((f) => f.inicio.slice(0, 4)))].sort().reverse(), [doSetor]);
  const recorte = useMemo(() => doSetor.filter((f) => (!ano || f.inicio.startsWith(ano))), [doSetor, ano]);
  const categorias = useMemo(() => resumirPorCategoria(recorte), [recorte]);
  const lista = useMemo(() => recorte.filter((f) => !categoria || f.categoria === categoria), [recorte, categoria]);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando funis…" minHeight={240} />;

  const totBruto = recorte.reduce((s, f) => s + f.bruto, 0);
  const totLiq = recorte.reduce((s, f) => s + f.liquido, 0);
  const totPessoas = recorte.reduce((s, f) => s + f.compradores, 0);
  // O aviso de conta desconectada segue o dado (conta_ausente vem de fin.hotmart_contas.visivel_funis, z89/z90), não o
  // setor: a conta do escritório está ligada desde 29/09 e 0 de 16 eventos vêm ausentes (medido 30/09).
  const escritorioSemConta = setor === 'escritorio' && doSetor.some((f) => f.conta_ausente);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]" role="group" aria-label="Setor">
          {(['educacao', 'escritorio'] as Setor[]).map((s) => (
            <button key={s} type="button" aria-pressed={setor === s} onClick={() => { setSetor(s); setCategoria(null); setAno(null); }}
              className={`px-3 py-1.5 text-xs font-semibold ${setor === s ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
              {s === 'educacao' ? 'Educação' : 'Escritório'}
            </button>
          ))}
        </div>
        <Chip ativo={!ano} onClick={() => setAno(null)}>Todos os anos</Chip>
        {anos.map((a) => <Chip key={a} ativo={ano === a} onClick={() => setAno(ano === a ? null : a)}>{a}</Chip>)}
      </div>

      {escritorioSemConta && (
        <p className="rounded-[var(--r-md)] border border-[var(--yellow)] px-3 py-2 text-xs text-[var(--fg-2)]">
          De 2021 a 2024 a Sessão de Viabilidade e o Croqui foram vendidos nesta conta, e os números estão aqui. De 2025 em diante as
          vendas do escritório estão na conta Hotmart <strong>mcsmarciosa@gmail.com</strong>, que ainda não está conectada: esses
          seminários mostram só o que foi registrado na época.
        </p>
      )}
      {setor === 'escritorio' && (
        <p className="text-xs text-[var(--fg-2)]">
          <a href="#escritorio" className="font-semibold text-[var(--accent)] underline underline-offset-2">
            Funil Sessão → Croqui → Holding Familiar por evento: aba Escritório
          </a>
        </p>
      )}

      <div className="grid gap-3 sm:grid-cols-3">
        <Numero rotulo="Faturamento (bruto vendido)" valor={fmtBRL(totBruto)} sub={`líquido ${fmtBRL(totLiq)}`} />
        <Numero rotulo="Pessoas que pagaram" valor={totPessoas.toLocaleString('pt-BR')} sub="somando os eventos (a mesma pessoa pode estar em mais de um)" />
        <Numero rotulo="Eventos" valor={String(recorte.length)} sub={`média de ${fmtBRL(recorte.length ? totBruto / recorte.length : 0)} por evento`} />
      </div>

      <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
        <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Por tipo de funil</div>
        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          {categorias.map((c) => (
            <button key={c.categoria} type="button" aria-pressed={categoria === c.categoria}
              onClick={() => setCategoria(categoria === c.categoria ? null : c.categoria)}
              className={`rounded-[var(--r-md)] border px-3 py-2 text-left ${categoria === c.categoria ? 'border-[var(--accent)] bg-[var(--surface-2)]' : 'border-[var(--border)] hover:bg-[var(--surface-2)]'}`}>
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-xs font-semibold text-[var(--fg)]">{rotuloCategoriaFunil(c.categoria)}</span>
                <span className="tabular text-xs font-bold text-[var(--fg)]">{fmtBRL(c.bruto)}</span>
              </div>
              <div className="mt-0.5 flex flex-wrap gap-x-3 text-[11px] tabular text-[var(--fg-3)]">
                <span>{c.eventos} evento{c.eventos === 1 ? '' : 's'}</span>
                <span>{c.compradores} pessoas</span>
                <span>média {fmtBRL(c.mediaPorEvento)}</span>
              </div>
            </button>
          ))}
        </div>
      </div>

      <DataTable minWidth={1100}>
        <Thead>
          <Th>Evento</Th><Th>Ingressos</Th><Th>Oferta (vendas · pessoas)</Th><Th>Estornos</Th>
          <Th>Faturamento</Th><Th>Líquido</Th><Th>Registrado na época</Th>
        </Thead>
        <tbody>
          {lista.map((f) => {
            const dv = diferencaPct(vendasParaConferencia(f), f.ref_vendas);
            const dvl = diferencaPct(valorParaConferencia(f), f.ref_valor);
            return (
              <Tr key={f.evento_id} className="cursor-pointer hover:bg-[var(--surface-2)]" onClick={() => setAberto(f)}>
                <Td>
                  <div className="font-medium text-[var(--fg)]">{f.nome}</div>
                  <div className="text-[10px] text-[var(--fg-3)]">
                    {rotuloCategoriaFunil(f.categoria)} · {fmtData(f.inicio)}{f.fim !== f.inicio ? ` a ${fmtData(f.fim)}` : ''} · vendas até {fmtData(f.venda_ate)}
                  </div>
                </Td>
                <Td className="tabular">{f.ingressos ? <>{f.ingressos}<span className="block text-[10px] text-[var(--fg-3)]">{fmtBRL(f.ingressos_bruto)}</span></> : '—'}</Td>
                <Td className="tabular">{f.oferta_vendas ? <>{f.oferta_vendas} · {f.oferta_compradores}<span className="block text-[10px] text-[var(--fg-3)]">{fmtBRL(f.oferta_bruto)}</span></> : '—'}</Td>
                <Td className="tabular">{f.oferta_estornos ? <span className="text-[var(--red)]">{f.oferta_estornos}</span> : '—'}</Td>
                <Td className="tabular font-semibold">{f.conta_ausente ? <span className="text-[var(--fg-4)]">conta não conectada</span> : fmtBRL(f.bruto)}</Td>
                <Td className="tabular text-[var(--green)]">{f.conta_ausente ? '—' : fmtBRL(f.liquido)}</Td>
                <Td className="tabular text-[11px]">
                  {f.ref_vendas == null && f.ref_valor == null ? <span className="text-[var(--fg-4)]">—</span> : (
                    <>
                      {f.ref_vendas != null && <span className="block">{f.ref_vendas} vendas{dv != null && !f.conta_ausente ? <Dif pct={dv} /> : null}</span>}
                      {f.ref_valor != null && <span className="block">{fmtBRL(f.ref_valor)}{dvl != null && !f.conta_ausente ? <Dif pct={dvl} /> : null}</span>}
                    </>
                  )}
                </Td>
              </Tr>
            );
          })}
        </tbody>
      </DataTable>

      {aberto && <FichaFunil repo={repo} f={aberto} onClose={() => setAberto(null)} />}
    </div>
  );
}

function Chip({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button type="button" aria-pressed={ativo} onClick={onClick}
      className={`rounded-[var(--r-pill)] border px-2.5 py-1 text-xs ${ativo ? 'border-[var(--accent)] bg-[var(--accent-subtle)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
      {children}
    </button>
  );
}

function Numero({ rotulo, valor, sub }: { rotulo: string; valor: string; sub: string }) {
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] px-4 py-3">
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular mt-0.5 text-2xl font-bold text-[var(--fg)]">{valor}</div>
      <div className="text-[11px] text-[var(--fg-3)]">{sub}</div>
    </div>
  );
}

function Dif({ pct }: { pct: number }) {
  const ok = Math.abs(pct) <= 3;
  return (
    <span className={`ml-1 ${ok ? 'text-[var(--green)]' : 'text-[var(--yellow)]'}`} title="diferença do sistema (Hotmart) contra o registrado na época">
      {ok ? '✓' : `${pct > 0 ? '+' : ''}${pct.toFixed(0)}%`}
    </span>
  );
}

function FichaFunil({ repo, f, onClose }: { repo: FinanceiroRepository; f: Funil; onClose: () => void }) {
  const { dados, erro } = useCarga<CompradorFunil[]>(() => repo.loadFunilCompradores(f.evento_id), [f.evento_id]);
  const [busca, setBusca] = useState('');
  const [aberta, setAberta] = useState<string | null>(null);
  const q = semAcento(busca.trim());
  const linhas = (dados ?? []).filter((c) => !q || semAcento(`${c.nome ?? ''} ${c.email ?? ''}`).includes(q));
  return (
    <Drawer onClose={onClose} title={f.nome}
      subtitle={`${fmtData(f.inicio)} a ${fmtData(f.fim)} · vendas de ${fmtData(f.carrinho_inicio ?? f.inicio)} a ${fmtData(f.venda_ate)} · ingresso desde ${fmtData(f.ingresso_de)}`}>
      <div className="space-y-3">
        <div className="grid gap-2 sm:grid-cols-4">
          <Mini rotulo="Ingressos" valor={`${f.ingressos} · ${fmtBRL(f.ingressos_bruto)}`} />
          <Mini rotulo="Oferta" valor={`${f.oferta_vendas} · ${fmtBRL(f.oferta_bruto)}`} />
          <Mini rotulo="Estornos" valor={String(f.oferta_estornos)} />
          <Mini rotulo="Líquido" valor={fmtBRL(f.liquido)} />
        </div>
        {(f.ref_fonte || f.observacao) && (
          <p className="text-[11px] text-[var(--fg-3)]">{f.ref_fonte ? <>Registrado na época: {f.ref_fonte}. </> : null}{f.observacao ?? ''}</p>
        )}
        <div className="flex flex-wrap items-center gap-2">
          <div className="w-full sm:w-64"><SearchInput value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} placeholder="Buscar nome ou e-mail" aria-label="Buscar comprador" /></div>
          <button type="button" disabled={!dados?.length} onClick={() => exportar(f, dados ?? [])}
            className="ml-auto rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)] disabled:opacity-50">
            Baixar lista ({dados?.length ?? 0})
          </button>
        </div>
        {erro ? <Erro msg={erro} /> : !dados ? <Loading label="Carregando compradores…" minHeight={120} /> : !linhas.length ? (
          <p className="text-xs text-[var(--fg-3)]">{f.conta_ausente ? 'Conta do escritório ainda não conectada.' : 'Nenhuma venda nesta janela.'}</p>
        ) : (
          <DataTable minWidth={760}>
            <Thead><Th>Pessoa</Th><Th>Comprou</Th><Th>Dia</Th><Th>Valor</Th><Th>Situação</Th></Thead>
            <tbody>
              {linhas.map((c, i) => (
                <Fragment key={`${c.email}-${c.dia}-${i}`}>
                <Tr>
                  <Td>
                    <button type="button" onClick={() => setAberta(aberta === `${c.email}-${i}` ? null : `${c.email}-${i}`)}
                      aria-expanded={aberta === `${c.email}-${i}`} className="text-left font-medium text-[var(--fg)] underline-offset-2 hover:underline" title="Ver a trajetória desta pessoa">
                      {c.nome ?? '—'}
                    </button>
                    <div className="text-[10px] text-[var(--fg-3)]">{c.email}{c.telefone ? ` · ${c.telefone}` : ''}</div>
                  </Td>
                  <Td className="text-[11px]">{c.papel === 'ingresso' ? 'Ingresso' : 'Oferta'} · {c.produto}<span className="block text-[10px] text-[var(--fg-4)]">{c.oferta}{c.parcelas && c.parcelas > 1 ? ` · ${c.parcelas}x` : ''}</span></Td>
                  <Td className="tabular text-[11px]">{c.dia ? fmtData(c.dia) : '—'}</Td>
                  <Td className="tabular">{fmtBRL(c.valor)}</Td>
                  <Td className={c.situacao === 'pago' ? 'text-[var(--green)]' : 'text-[var(--red)]'}>{c.situacao === 'pago' ? 'Pago' : 'Estornado'}</Td>
                </Tr>
                {aberta === `${c.email}-${i}` && (
                  <tr><td colSpan={5} className="bg-[var(--surface-2)] px-3 py-3"><Trajetoria repo={repo} email={c.email} /></td></tr>
                )}
                </Fragment>
              ))}
            </tbody>
          </DataTable>
        )}
      </div>
    </Drawer>
  );
}

function Mini({ rotulo, valor }: { rotulo: string; valor: string }) {
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
      <div className="text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular text-sm font-bold text-[var(--fg)]">{valor}</div>
    </div>
  );
}

function exportar(f: Funil, linhas: CompradorFunil[]) {
  const col: [string, (c: CompradorFunil) => unknown][] = [
    ['Nome', (c) => c.nome], ['E-mail', (c) => c.email], ['Telefone', (c) => c.telefone], ['Papel', (c) => c.papel],
    ['Produto', (c) => c.produto], ['Oferta', (c) => c.oferta], ['Dia', (c) => c.dia], ['Parcelas', (c) => c.parcelas],
    ['Valor', (c) => c.valor.toFixed(2).replace('.', ',')], ['Líquido', (c) => c.liquido.toFixed(2).replace('.', ',')], ['Situação', (c) => c.situacao],
  ];
  const txt = [col.map(([n]) => n).join(';'), ...linhas.map((c) => col.map(([, g]) => celulaCsv(g(c))).join(';'))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + txt], { type: 'text/csv;charset=utf-8' }));
  a.download = `funil-${f.categoria}-${f.inicio}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}
