'use client';

// Marketing > Web > Melhorias > Comparar: duas páginas no mesmo período (ex.: AK1 x BL2) ou a mesma página (ou o
// projeto inteiro) em dois períodos. Veredito pelo teste de duas proporções (taxa de lead sobre as visitas que viram a
// página, como o Comparar.tsx do Radar do Luiz), depois os números lado a lado, por aparelho e por origem.
import { useState } from 'react';
import { Badge, Button, DataTable, FilterSelect, Input, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { compararTaxas, duracao, msVital, nomeOrigem, num, pct, ROTULO_NIVEL } from '../domain/analise';
import { diaCurto, somaDias, validarPeriodo, type Periodo } from '../domain/periodo';
import { APARELHO, type Comparacao2, type LadoComparar } from '../domain/tipos';
import type { PaginaWeb } from '../infrastructure/web-data';
import { TOM_NIVEL } from './paineis-fase2';

export interface EscolhaLado { pagina: number | null; de: string; ate: string; nome: string | null }

const nomeLado = (l: LadoComparar) => `${l.nome ?? 'Projeto inteiro'} · ${diaCurto(l.de)} a ${diaCurto(l.ate)}`;

export function VereditoComparar({ r }: { r: Comparacao2 }) {
  const { a, b } = r;
  const lead = compararTaxas(a.leads, a.visitas, b.leads, b.visitas);
  const mql = compararTaxas(a.mql, a.visitas, b.mql, b.visitas);
  const empate = Math.abs(lead.b - lead.a) < 0.002;
  const ganhaB = lead.b > lead.a;
  const quanto = ganhaB ? lead.relativa : lead.b ? (lead.a - lead.b) / lead.b : 0;
  const linhas: [string, (l: LadoComparar) => string][] = [
    ['Visitas que viram', (l) => num(l.visitas)],
    ['Taxa de lead', (l) => pct(l.leads, l.visitas)],
    ['Taxa de MQL', (l) => pct(l.mql, l.visitas)],
    ['Entradas', (l) => num(l.entradas)],
    ['Rejeição de quem entrou', (l) => pct(l.rejeicoes, l.entradas)],
    ['Rolagem média', (l) => `${l.rolagem_media}%`],
    ['Tempo médio', (l) => duracao(l.visivel_ms_medio)],
    ['LCP p75', (l) => msVital(l.lcp_p75)],
    ['Dias com visita', (l) => num(l.dias)],
  ];
  const chaves = (k: 'por_aparelho' | 'por_origem') => [...new Set([...a[k], ...b[k]].map((x) => x.chave))];
  const cruz = (k: 'por_aparelho' | 'por_origem', rotulo: (c: string) => string) => (
    <DataTable minWidth={520}>
      <Thead><Th>{k === 'por_aparelho' ? 'Aparelho' : 'Origem'}</Th><Th>A</Th><Th>B</Th><Th>Selo</Th></Thead>
      <tbody>{chaves(k).map((c) => {
        const x = a[k].find((y) => y.chave === c), y = b[k].find((z) => z.chave === c);
        const t = compararTaxas(x?.leads ?? 0, x?.visitas ?? 0, y?.leads ?? 0, y?.visitas ?? 0);
        return (
          <Tr key={c}><Td>{rotulo(c)}</Td><Td>{pct(x?.leads ?? 0, x?.visitas ?? 0)} <span className="text-[11px] text-[var(--fg-3)]">({num(x?.visitas)})</span></Td>
            <Td>{pct(y?.leads ?? 0, y?.visitas ?? 0)} <span className="text-[11px] text-[var(--fg-3)]">({num(y?.visitas)})</span></Td>
            <Td><Badge tone={TOM_NIVEL[t.nivel]}>{ROTULO_NIVEL[t.nivel]}</Badge></Td></Tr>
        );
      })}</tbody>
    </DataTable>
  );
  return (
    <div className="space-y-4">
      <SectionCard title="Veredito">
        <p className="text-lg font-semibold text-[var(--fg)]">
          {!a.visitas || !b.visitas ? 'Um dos lados não tem visita: nada a comparar.'
            : empate ? 'Os dois lados convertem praticamente igual.'
            : `${ganhaB ? nomeLado(b) : nomeLado(a)} converte ${(Math.abs(quanto) * 100).toLocaleString('pt-BR', { maximumFractionDigits: 0 })}% mais.`}
        </p>
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          Lead: <Badge tone={TOM_NIVEL[lead.nivel]}>{ROTULO_NIVEL[lead.nivel]}</Badge>{' '}
          MQL: <Badge tone={TOM_NIVEL[mql.nivel]}>{ROTULO_NIVEL[mql.nivel]}</Badge>
          {lead.poucas && <span className="ml-2 text-xs text-[var(--fg-3)]">Poucos números: com menos de 30 visitas de um lado ou 10 leads somados, ainda pode ser acaso.</span>}
        </p>
      </SectionCard>
      <SectionCard title="Lado a lado">
        <DataTable minWidth={620}>
          <Thead><Th>&nbsp;</Th><Th>A: {nomeLado(a)}</Th><Th>B: {nomeLado(b)}</Th></Thead>
          <tbody>{linhas.map(([rot, f]) => <Tr key={rot}><Td>{rot}</Td><Td>{f(a)}</Td><Td>{f(b)}</Td></Tr>)}</tbody>
        </DataTable>
      </SectionCard>
      <div className="grid gap-4 lg:grid-cols-2">
        <SectionCard title="Taxa de lead por aparelho">{cruz('por_aparelho', (c) => APARELHO[c] ?? c)}</SectionCard>
        <SectionCard title="Taxa de lead por origem">{cruz('por_origem', nomeOrigem)}</SectionCard>
      </div>
    </div>
  );
}

function Lado({ rotulo, v, onChange, paginas }: { rotulo: string; v: EscolhaLado; onChange: (x: EscolhaLado) => void; paginas: PaginaWeb[] }) {
  return (
    <div className="flex flex-wrap items-end gap-2">
      <span className="w-6 pb-2 text-sm font-semibold">{rotulo}</span>
      <label className="block">
        <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Página</span>
        <FilterSelect value={v.pagina ?? ''} aria-label={`Página ${rotulo}`}
          onChange={(e) => { const id = e.target.value ? Number(e.target.value) : null; onChange({ ...v, pagina: id, nome: paginas.find((p) => p.id === id)?.nome ?? null }); }}>
          <option value="">Projeto inteiro</option>
          {paginas.map((p) => <option key={p.id} value={p.id}>{p.nome} ({p.caminho})</option>)}
        </FilterSelect>
      </label>
      <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">De</span>
        <Input type="date" value={v.de} onChange={(e) => onChange({ ...v, de: e.target.value })} /></label>
      <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Até</span>
        <Input type="date" value={v.ate} onChange={(e) => onChange({ ...v, ate: e.target.value })} /></label>
    </div>
  );
}

export function Comparar({ paginas, periodo, carregar }: {
  paginas: PaginaWeb[]; periodo: Periodo; carregar: (a: EscolhaLado, b: EscolhaLado) => Promise<Comparacao2 | null>;
}) {
  const capturas = paginas.filter((p) => p.funcao === 'captura');
  const p1 = capturas[0] ?? paginas[0], p2 = capturas[1] ?? paginas[1];
  const [a, setA] = useState<EscolhaLado>({ pagina: p1?.id ?? null, nome: p1?.nome ?? null, ...periodo });
  const [b, setB] = useState<EscolhaLado>(p2 ? { pagina: p2.id, nome: p2.nome, ...periodo }
    : { pagina: p1?.id ?? null, nome: p1?.nome ?? null, de: somaDias(periodo.de, -7), ate: somaDias(periodo.ate, -7) });
  const [r, setR] = useState<Comparacao2 | null | undefined>(undefined);
  const [ocupado, setOcupado] = useState(false);
  const erro = validarPeriodo(a) ?? validarPeriodo(b);
  async function comparar() {
    setOcupado(true);
    setR(await carregar(a, b));
    setOcupado(false);
  }
  return (
    <div className="space-y-4">
      <SectionCard title="Comparar" subtitle="Duas páginas no mesmo período, ou a mesma página (ou o projeto inteiro) em dois períodos.">
        <div className="space-y-3">
          <Lado rotulo="A" v={a} onChange={setA} paginas={paginas} />
          <Lado rotulo="B" v={b} onChange={setB} paginas={paginas} />
          <div className="flex items-center gap-3">
            <Button size="sm" onClick={comparar} disabled={ocupado || !!erro}>{ocupado ? 'Comparando…' : 'Comparar'}</Button>
            {erro && <span role="alert" className="text-sm text-[var(--red)]">{erro}</span>}
          </div>
        </div>
      </SectionCard>
      {r === null && <p role="alert" className="text-sm text-[var(--red)]">Não foi possível comparar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.</p>}
      {r && <VereditoComparar r={r} />}
    </div>
  );
}
