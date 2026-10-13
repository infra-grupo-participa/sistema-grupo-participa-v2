'use client';

// Calculadora de amostra e de leitura (seções 6A, 7 e 8). Usada avulsa e dentro da ficha.
import { useMemo, useState } from 'react';
import { Badge, Card, FilterSelect, Input } from '@/shared/ui/components';
import {
  amostraCusto, amostraTaxa, classificar, lerCusto, lerTaxa, pct, ROTULO_RESULTADO, sensibilidade, type Classificacao, type Leitura, type Resultado,
} from '../domain/estatistica';
import type { MetricaTipo } from '../domain/types';

export const TOM_RESULTADO: Record<Resultado, 'success' | 'info' | 'neutral' | 'warning'> = {
  vencedor: 'success', provavel: 'info', empate: 'neutral', inconclusivo: 'warning',
};

/** Número digitado em português: "1.450" = mil quatrocentos e cinquenta; "11,9" ou "11.9" = onze vírgula nove. */
export const num = (s: string) => {
  const t = String(s).trim();
  if (!t) return NaN;
  const limpo = t.includes(',') ? t.replace(/\./g, '').replace(',', '.') : /^\d{1,3}(\.\d{3})+$/.test(t) ? t.replace(/\./g, '') : t;
  const v = Number(limpo);
  return Number.isFinite(v) ? v : NaN;
};

export function Rotulo({ children, dica }: { children: React.ReactNode; dica?: string }) {
  return (
    <span className="block text-xs font-semibold text-[var(--fg-2)]">
      {children}
      {dica && <span className="block font-normal text-[var(--fg-3)]">{dica}</span>}
    </span>
  );
}

/** Quantos casos por grupo + a tabela de sensibilidade (a "balança" da 6A). */
export function PainelAmostra({ tipo, taxaBase, regua }: { tipo: MetricaTipo; taxaBase: number | null; regua: number | null }) {
  const n = tipo === 'taxa' ? (taxaBase && regua ? amostraTaxa(taxaBase, regua) : NaN) : regua ? amostraCusto(regua) : NaN;
  const sens = Number.isFinite(n) ? sensibilidade(tipo, n, taxaBase) : [];
  if (!Number.isFinite(n)) {
    return <p className="text-xs text-[var(--fg-3)]">{tipo === 'taxa' ? 'Informe a taxa de hoje e a menor diferença que importa.' : 'Informe a menor diferença que importa.'}</p>;
  }
  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-baseline gap-2">
        <span className="text-2xl font-bold tabular-nums text-[var(--fg)]">{n.toLocaleString('pt-BR')}</span>
        <span className="text-sm text-[var(--fg-2)]">{tipo === 'taxa' ? 'casos em cada grupo' : 'resultados (leads, MQL, vendas) em cada grupo'}</span>
      </div>
      <p className="text-xs text-[var(--fg-3)]">Com 95% de confiança e 80% de chance de enxergar a diferença, se ela existir. Cortar a régua pela metade pede uns 4 vezes mais casos.</p>
      <div className="overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]">
        <table className="w-full text-xs">
          <thead className="bg-[var(--surface-2)]"><tr><th className="px-3 py-1.5 text-left">Se a diferença real for…</th><th className="px-3 py-1.5 text-right">Chance de o teste mostrar</th></tr></thead>
          <tbody>
            {sens.map((s) => (
              <tr key={s.efeito} className={`border-t border-[var(--border)] ${regua && Math.abs(s.efeito - regua) < 1e-9 ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>
                <td className="px-3 py-1.5">{pct(s.efeito)}{regua && Math.abs(s.efeito - regua) < 1e-9 ? ' (a régua)' : ''}</td>
                <td className="px-3 py-1.5 text-right tabular-nums">{Number.isFinite(s.chance) ? `${Math.round(s.chance * 100)}%` : '—'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export interface EntradaLeitura { aN: string; aX: string; bN: string; bX: string }

export function calcularLeitura(tipo: MetricaTipo, e: EntradaLeitura): Leitura | null {
  const [aN, aX, bN, bX] = [num(e.aN), num(e.aX), num(e.bN), num(e.bX)];
  return tipo === 'taxa' ? lerTaxa(aN, aX, bN, bX) : lerCusto(aN, aX, bN, bX);
}

export function amostraChegou(tipo: MetricaTipo, e: EntradaLeitura, minima: number | null): boolean {
  if (!minima) return true;
  const a = tipo === 'taxa' ? num(e.aN) : num(e.aX);
  const b = tipo === 'taxa' ? num(e.bN) : num(e.bX);
  return a >= minima && b >= minima;
}

export function CamposLeitura({ tipo, valor, onChange }: { tipo: MetricaTipo; valor: EntradaLeitura; onChange: (v: EntradaLeitura) => void }) {
  const campos: [keyof EntradaLeitura, string][] = tipo === 'taxa'
    ? [['aN', 'A (atual): casos'], ['aX', 'A: sucessos'], ['bN', 'B (nova): casos'], ['bX', 'B: sucessos']]
    : [['aN', 'A (atual): gasto (R$)'], ['aX', 'A: resultados'], ['bN', 'B (nova): gasto (R$)'], ['bX', 'B: resultados']];
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
      {campos.map(([k, l]) => (
        <label key={k} className="space-y-1">
          <Rotulo>{l}</Rotulo>
          <Input inputMode="decimal" value={valor[k]} onChange={(e) => onChange({ ...valor, [k]: e.target.value })} />
        </label>
      ))}
    </div>
  );
}

export function ResultadoLeitura({ tipo, leitura, classif }: { tipo: MetricaTipo; leitura: Leitura | null; classif: Classificacao | null }) {
  if (!leitura || !classif) return <p className="text-xs text-[var(--fg-3)]">Preencha os quatro números para ver o resultado.</p>;
  const d = leitura.detalhe;
  return (
    <Card className="space-y-2 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <Badge tone={TOM_RESULTADO[classif.resultado]} dot>{ROTULO_RESULTADO[classif.resultado]}{classif.quem ? ` · ${classif.quem}` : ''}</Badge>
        <span className="text-xs text-[var(--fg-3)]">Confiança {(leitura.confianca * 100).toFixed(1).replace('.', ',')}% · chance de B ser melhor {(leitura.probBMelhor * 100).toFixed(0)}%</span>
      </div>
      <p className="text-sm text-[var(--fg)]">{classif.explicacao}</p>
      <p className="text-xs text-[var(--fg-2)]">
        {tipo === 'taxa'
          ? <>Taxa A {pct(d.taxaA, 2).replace('+', '')} · taxa B {pct(d.taxaB, 2).replace('+', '')} · diferença {pct(leitura.beneficio, 1)} (de {pct(leitura.ic[0], 1)} a {pct(leitura.ic[1], 1)}, intervalo de 95%)</>
          : <>Custo por resultado A R$ {d.custoA.toFixed(2).replace('.', ',')} · B R$ {d.custoB.toFixed(2).replace('.', ',')} · B rende {pct(leitura.beneficio, 1)} por real (de {pct(leitura.ic[0], 1)} a {pct(leitura.ic[1], 1)})</>}
      </p>
    </Card>
  );
}

/** Calculadora avulsa (aba Calculadora). */
export function CalculadoraAvulsa() {
  const [tipo, setTipo] = useState<MetricaTipo>('taxa');
  const [taxa, setTaxa] = useState('10');
  const [regua, setRegua] = useState('30');
  const [minima, setMinima] = useState('');
  const [ent, setEnt] = useState<EntradaLeitura>({ aN: '', aX: '', bN: '', bX: '' });
  const [medicaoOk, setMedicaoOk] = useState(true);
  const t = num(taxa) / 100;
  const r = num(regua) / 100;
  const leitura = useMemo(() => calcularLeitura(tipo, ent), [tipo, ent]);
  const classif = leitura ? classificar(leitura, { regua: Number.isFinite(r) ? r : null, amostraChegou: amostraChegou(tipo, ent, num(minima) || null), medicaoOk }) : null;
  return (
    <div className="grid gap-4 lg:grid-cols-2">
      <Card className="space-y-4 p-5">
        <h3 className="text-base font-semibold text-[var(--fg)]">Quantos casos eu preciso?</h3>
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <label className="space-y-1"><Rotulo>Tipo de métrica</Rotulo>
            <FilterSelect value={tipo} onChange={(e) => setTipo(e.target.value as MetricaTipo)}><option value="taxa">Taxa (conversão, resposta…)</option><option value="custo">Custo (por lead, MQL, venda)</option></FilterSelect>
          </label>
          {tipo === 'taxa' && <label className="space-y-1"><Rotulo>Taxa de hoje (%)</Rotulo><Input inputMode="decimal" value={taxa} onChange={(e) => setTaxa(e.target.value)} /></label>}
          <label className="space-y-1"><Rotulo>Menor diferença que importa (%)</Rotulo><Input inputMode="decimal" value={regua} onChange={(e) => setRegua(e.target.value)} /></label>
        </div>
        <PainelAmostra tipo={tipo} taxaBase={Number.isFinite(t) ? t : null} regua={Number.isFinite(r) ? r : null} />
      </Card>
      <Card className="space-y-4 p-5">
        <h3 className="text-base font-semibold text-[var(--fg)]">Como ler o resultado</h3>
        <CamposLeitura tipo={tipo} valor={ent} onChange={setEnt} />
        <div className="flex flex-wrap items-center gap-4">
          <label className="space-y-1"><Rotulo>Amostra mínima por grupo (opcional)</Rotulo><Input inputMode="numeric" value={minima} onChange={(e) => setMinima(e.target.value)} className="!w-40" /></label>
          <label className="flex items-center gap-2 text-sm text-[var(--fg-2)]"><input type="checkbox" checked={medicaoOk} onChange={(e) => setMedicaoOk(e.target.checked)} /> Medição e contexto ok</label>
        </div>
        <ResultadoLeitura tipo={tipo} leitura={leitura} classif={classif} />
      </Card>
    </div>
  );
}
