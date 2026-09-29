'use client';

// Escritório › Funil (z92, 30/09/2026): Sessão de Viabilidade → Croqui → Holding Familiar, uma linha por evento do
// setor escritório e, abaixo, os 3 baldes fora de evento. Clique na linha = quem são as pessoas (1 RPC por linha, 1×).
// A tela só exibe: atribuição, entrada, conversão, mediana e máscara de telefone vêm prontas do SQL.
// Texto que o comprador digitou (nome, e-mail, cidade) só entra por JSX — nunca dangerouslySetInnerHTML.
import { useEffect, useState } from 'react';
import { DataTable, Drawer, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { EtapaEscritorio, LinhaFunilEscritorio, PessoaFunilEscritorio } from '../../domain/escritorio-funil';
import { celulaCsv } from '../../domain/hotmart';
import { totalizarFunilEscritorio, type CacheEscritorioFunil } from '../../application/carregar-escritorio-funil';
import { Erro } from '../hotmart/comum';

const ROTULO_BALDE: Record<string, string> = {
  perene: 'Sessão sem evento',
  croqui: 'Entrou direto no Croqui (sem Sessão)',
  direto_hf: 'Entrou direto na Holding Familiar',
};
const ROTULO_ETAPA: Record<EtapaEscritorio, string> = { sessao: 'Sessão', croqui: 'Croqui', hf: 'Holding Familiar' };
const ROTULO_ORIGEM: Record<string, string> = { oferta: 'oferta do evento', janela: 'datas do evento', perene: 'sem evento' };

const rotuloLinha = (l: LinhaFunilEscritorio) => (l.tipo === 'evento' ? l.nome : ROTULO_BALDE[l.tipo] ?? l.nome);
const num = (n: number) => n.toLocaleString('pt-BR');
const pct = (p: number | null) => (p == null ? '—' : `${p.toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`);
const dias = (d: number | null) => (d == null ? '—' : d.toLocaleString('pt-BR', { maximumFractionDigits: 1 }));
const periodo = (l: LinhaFunilEscritorio) =>
  !l.inicio ? null : l.fim && l.fim !== l.inicio ? `${fmtData(l.inicio)} a ${fmtData(l.fim)}` : fmtData(l.inicio);

const NUM = 'tabular text-right whitespace-nowrap';
const COLUNAS = 7;

export function FunilEscritorio({ cache }: { cache: CacheEscritorioFunil }) {
  const [res, setRes] = useState<{ dados: LinhaFunilEscritorio[] | null; erro: string | null } | null>(null);
  const [tentativa, setTentativa] = useState(0);
  const [aberta, setAberta] = useState<LinhaFunilEscritorio | null>(null);

  useEffect(() => {
    if (cache.funilLido()) return;
    let vivo = true;
    cache.funil().then(
      (d) => { if (vivo) setRes({ dados: d, erro: null }); },
      (e: unknown) => { if (vivo) setRes({ dados: null, erro: e instanceof Error ? e.message : 'Não foi possível carregar o funil do escritório.' }); },
    );
    return () => { vivo = false; };
  }, [cache, tentativa]);

  const dados = cache.funilLido() ?? res?.dados ?? null;
  if (!dados && res?.erro) {
    return (
      <div className="space-y-2">
        <Erro msg={res.erro} />
        <button type="button" onClick={() => { setRes(null); setTentativa((t) => t + 1); }}
          className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)]">
          Tentar de novo
        </button>
      </div>
    );
  }
  if (!dados) return <Loading label="Carregando o funil do escritório…" minHeight={240} />;

  const eventos = dados.filter((l) => l.tipo === 'evento');
  const baldes = dados.filter((l) => l.tipo !== 'evento');
  const total = totalizarFunilEscritorio(dados);
  const oculto = dados.some((l) => !l.escritorio_visivel);

  return (
    <div className="space-y-3">
      {oculto && (
        <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)] px-3 py-2 text-xs text-[var(--fg-2)]">
          As vendas da conta Hotmart do escritório (2025 em diante) ainda estão sendo carregadas: os eventos desse período
          aparecem sem esses números.
        </p>
      )}

      <DataTable minWidth={980}>
        <Thead>
          <Th>Evento</Th>
          <Th className="text-right">Sessões</Th>
          <Th className="text-right">Pessoas</Th>
          <Th className="text-right">→ Croqui</Th>
          <Th className="text-right">→ Holding Familiar</Th>
          <Th className="text-right">Dias Sessão → Croqui</Th>
          <Th className="text-right">Dias Croqui → HF</Th>
        </Thead>
        <tbody>
          {eventos.map((l) => <LinhaFunil key={l.evento_id} l={l} onAbrir={setAberta} />)}
          {baldes.length > 0 && (
            <tr className="border-t border-[var(--border)] bg-[var(--surface-3)]">
              <td colSpan={COLUNAS} className="px-3 py-1.5 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Fora de evento</td>
            </tr>
          )}
          {baldes.map((l) => <LinhaFunil key={l.evento_id} l={l} onAbrir={setAberta} />)}
        </tbody>
        <tfoot>
          <tr className="border-t-2 border-[var(--border-strong)] font-semibold text-[var(--fg)]">
            <td className="px-3 py-2.5">Total</td>
            <td className={`px-3 py-2.5 ${NUM}`}>{num(total.sessoes_vendas)}</td>
            <td className={`px-3 py-2.5 ${NUM}`}>{num(total.pessoas)}</td>
            <td className={`px-3 py-2.5 ${NUM}`}>{num(total.croqui_pessoas)} <span className="font-normal text-[var(--fg-3)]">{pct(total.croqui_pct)}</span></td>
            <td className={`px-3 py-2.5 ${NUM}`}>{num(total.hf_pessoas)} <span className="font-normal text-[var(--fg-3)]">{pct(total.hf_pct)}</span></td>
            <td className={`px-3 py-2.5 ${NUM} text-[var(--fg-4)]`}>—</td>
            <td className={`px-3 py-2.5 ${NUM} text-[var(--fg-4)]`}>—</td>
          </tr>
        </tfoot>
      </DataTable>

      {aberta && <PessoasDaLinha key={aberta.evento_id} cache={cache} linha={aberta} onClose={() => setAberta(null)} />}
    </div>
  );
}

function LinhaFunil({ l, onAbrir }: { l: LinhaFunilEscritorio; onAbrir: (l: LinhaFunilEscritorio) => void }) {
  const p = periodo(l);
  return (
    <Tr onClick={() => onAbrir(l)}>
      <Td>
        {/* Botão para teclado/leitor de tela; o clique sobe para a linha (um só onAbrir). */}
        <button type="button" className="text-left font-medium text-[var(--fg)] underline-offset-2 hover:underline">{rotuloLinha(l)}</button>
        {p && <div className="text-[10px] text-[var(--fg-3)]">{p}</div>}
      </Td>
      <Td className={NUM}>{num(l.sessoes_vendas)}</Td>
      <Td className={NUM}>{num(l.pessoas)}</Td>
      <Td className={NUM}>{num(l.croqui_pessoas)} <span className="text-[11px] text-[var(--fg-3)]">{pct(l.croqui_pct)}</span></Td>
      <Td className={NUM}>{num(l.hf_pessoas)} <span className="text-[11px] text-[var(--fg-3)]">{pct(l.hf_pct)}</span></Td>
      <Td className={NUM}>{dias(l.mediana_dias_sessao_croqui)}</Td>
      <Td className={NUM}>{dias(l.mediana_dias_croqui_hf)}</Td>
    </Tr>
  );
}

function PessoasDaLinha({ cache, linha, onClose }: { cache: CacheEscritorioFunil; linha: LinhaFunilEscritorio; onClose: () => void }) {
  const id = linha.evento_id;
  const [res, setRes] = useState<{ dados: PessoaFunilEscritorio[] | null; erro: string | null } | null>(null);
  useEffect(() => {
    if (cache.pessoasLidas(id)) return;
    let vivo = true;
    cache.pessoas(id).then(
      (d) => { if (vivo) setRes({ dados: d, erro: null }); },
      (e: unknown) => { if (vivo) setRes({ dados: null, erro: e instanceof Error ? e.message : 'Não foi possível carregar as pessoas.' }); },
    );
    return () => { vivo = false; };
  }, [cache, id]);
  const dados = cache.pessoasLidas(id) ?? res?.dados ?? null;
  const p = periodo(linha);

  return (
    <Drawer onClose={onClose} width="max-w-6xl" title={rotuloLinha(linha)}
      subtitle={`${p ? `${p} · ` : ''}${num(linha.pessoas)} pessoas · ${num(linha.croqui_pessoas)} Croqui · ${num(linha.hf_pessoas)} Holding Familiar`}>
      <div className="space-y-3">
        <div className="flex items-center">
          <button type="button" disabled={!dados?.length} onClick={() => exportar(linha, dados ?? [])}
            className="ml-auto rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-2)] disabled:opacity-50">
            Baixar lista ({dados?.length ?? 0})
          </button>
        </div>
        {res?.erro ? <Erro msg={res.erro} /> : !dados ? <Loading label="Carregando pessoas…" minHeight={120} /> : !dados.length ? (
          <p className="text-xs text-[var(--fg-3)]">Nenhuma pessoa nesta linha.</p>
        ) : (
          <DataTable minWidth={1040}>
            <Thead>
              <Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Cidade/UF</Th><Th>Etapa</Th>
              <Th>Sessão</Th><Th>Croqui</Th><Th>Holding Familiar</Th>
            </Thead>
            <tbody>
              {dados.map((x) => (
                <Tr key={x.email}>
                  <Td className="font-medium text-[var(--fg)]">{x.nome ?? '—'}</Td>
                  <Td className="text-[11px] text-[var(--fg-2)]">{x.email}</Td>
                  <Td className="tabular text-[11px]">{x.telefone ?? '—'}</Td>
                  <Td className="text-[11px]">{cidadeUf(x) ?? '—'}</Td>
                  <Td className="text-[11px]">
                    {ROTULO_ETAPA[x.etapa_alcancada] ?? x.etapa_alcancada}
                    {x.entrada !== 'sessao' && <span className="block text-[10px] text-[var(--fg-3)]">entrou no {ROTULO_ETAPA[x.entrada] ?? x.entrada}</span>}
                  </Td>
                  <Td className="tabular text-[11px]">
                    <Etapa em={x.sessao_em} valor={x.sessao_valor} />
                    {x.sessao_evento_origem && <span className="block text-[10px] text-[var(--fg-3)]">{ROTULO_ORIGEM[x.sessao_evento_origem] ?? x.sessao_evento_origem}</span>}
                  </Td>
                  <Td className="tabular text-[11px]">
                    <Etapa em={x.croqui_em} valor={x.croqui_valor} />
                    {x.dias_sessao_croqui != null && <span className="block text-[10px] text-[var(--fg-3)]">{x.dias_sessao_croqui} dias depois</span>}
                  </Td>
                  <Td className="tabular text-[11px]">
                    <Etapa em={x.hf_em} valor={x.hf_valor} />
                    {x.dias_croqui_hf != null && <span className="block text-[10px] text-[var(--fg-3)]">{x.dias_croqui_hf} dias após o Croqui</span>}
                  </Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </div>
    </Drawer>
  );
}

function Etapa({ em, valor }: { em: string | null; valor: number | null }) {
  if (!em) return <span className="text-[var(--fg-4)]">—</span>;
  return <>{fmtData(em)}<span className="block">{fmtBRL(valor)}</span></>;
}

function cidadeUf(x: PessoaFunilEscritorio): string | null {
  if (x.cidade && x.uf) return `${x.cidade}/${x.uf}`;
  return x.cidade ?? x.uf ?? null;
}

function exportar(l: LinhaFunilEscritorio, linhas: PessoaFunilEscritorio[]) {
  const v = (n: number | null) => (n == null ? '' : n.toFixed(2).replace('.', ','));
  const col: [string, (p: PessoaFunilEscritorio) => unknown][] = [
    ['Nome', (p) => p.nome], ['E-mail', (p) => p.email], ['Telefone', (p) => p.telefone], ['Cidade', (p) => p.cidade], ['UF', (p) => p.uf],
    ['Entrada', (p) => ROTULO_ETAPA[p.entrada] ?? p.entrada], ['Etapa alcançada', (p) => ROTULO_ETAPA[p.etapa_alcancada] ?? p.etapa_alcancada],
    ['Contas Hotmart', (p) => p.contas],
    ['Sessão em', (p) => p.sessao_em], ['Sessão valor', (p) => v(p.sessao_valor)], ['Sessão no evento por', (p) => p.sessao_evento_origem],
    ['Croqui em', (p) => p.croqui_em], ['Croqui valor', (p) => v(p.croqui_valor)], ['Dias Sessão→Croqui', (p) => p.dias_sessao_croqui],
    ['HF em', (p) => p.hf_em], ['HF valor', (p) => v(p.hf_valor)], ['Dias Croqui→HF', (p) => p.dias_croqui_hf],
  ];
  // celulaCsv neutraliza fórmula (=, +, -, @) e aspas: o nome e a cidade vêm do que o comprador digitou.
  const txt = [col.map(([n]) => n).join(';'), ...linhas.map((p) => col.map(([, g]) => celulaCsv(g(p))).join(';'))].join('\n');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + txt], { type: 'text/csv;charset=utf-8' }));
  a.download = `funil-escritorio-${l.inicio ?? l.tipo}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}
