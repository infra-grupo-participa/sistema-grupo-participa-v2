import { EmptyState } from '@/shared/ui/components';
import type { DisparoDetalheAtm, Resultado } from '../infrastructure/atm-data';

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const canalRotulo: Record<NonNullable<DisparoDetalheAtm['canal']>, string> = {
  whatsapp_api: 'API', email: 'E-mail', sms: 'SMS', ligacao: 'Ligação', grupo: 'Grupo',
};

function dataHora(value: string | null): string {
  return value ? new Date(value).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }) : 'Sem data';
}

function numero(value: number | null): string {
  return value === null ? 'Sem dado' : inteiro.format(value);
}

function percentual(numerador: number | null, denominador: number | null): string {
  if (numerador === null || denominador === null || denominador <= 0) return 'Sem dado';
  return `${((numerador / denominador) * 100).toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`;
}

function custoPorEntregue(custoCentavos: number | null, entregues: number | null): string {
  if (custoCentavos === null || entregues === null || entregues <= 0) return 'Sem dado';
  return moeda.format((custoCentavos / 100) / entregues);
}

function BarraTaxa({ label, quantidade, base }: { label: string; quantidade: number | null; base: number | null }) {
  const taxa = quantidade !== null && base !== null && base > 0 ? (quantidade / base) * 100 : null;
  const largura = taxa === null ? 0 : Math.max(0, Math.min(100, taxa));
  return <div className="rounded-[var(--r-md)] bg-[var(--surface-2)] p-3">
    <div className="flex flex-wrap justify-between gap-1 text-xs"><span className="text-[var(--fg-2)]">{label} · cálculo</span><strong className="text-[var(--fg)]">{taxa === null ? 'Sem dado' : `${taxa.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`}</strong></div>
    <div role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100} aria-valuenow={taxa === null ? undefined : largura} className="mt-2 h-2 overflow-hidden rounded-full bg-[var(--surface-3)]">
      <div className="h-full rounded-full bg-[var(--accent)]" style={{ width: `${largura}%` }} />
    </div>
    <p className="mt-1 text-xs text-[var(--fg-3)]">{quantidade === null ? 'Sem dado' : inteiro.format(quantidade)} de {base === null ? 'sem dado' : inteiro.format(base)}</p>
  </div>;
}

function linkHttp(url: string | null): string | null {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    return parsed.protocol === 'https:' || parsed.protocol === 'http:' ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function Dado({ label, value, calculado = false }: { label: string; value: string; calculado?: boolean }) {
  return <div className="min-w-0 rounded-[var(--r-md)] bg-[var(--surface-2)] p-3">
    <dt className="text-xs text-[var(--fg-3)]">{label}{calculado && <span className="ml-1 text-[var(--accent)]">· cálculo</span>}</dt>
    <dd className="mt-1 break-words text-sm font-medium text-[var(--fg)]">{value}</dd>
  </div>;
}

export function DisparosDetalhe({
  result,
  canal,
}: {
  result: Resultado<DisparoDetalheAtm[]>;
  canal: string;
}) {
  const rows = result.data.filter((row) => row.canal === canal);
  const canalAtual = canalRotulo[canal as keyof typeof canalRotulo] ?? 'Sem dado';

  return <div className="mt-5 border-t border-[var(--border)] pt-5">
    <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h3 className="font-semibold text-[var(--fg)]">Disparos registrados</h3>
        <p className="mt-1 text-xs text-[var(--fg-3)]">Canal selecionado: {canalAtual}. Data e hora em Brasília. Taxas e custo por entregue são cálculos da tela. Use Atualizar para reler os registros.</p>
      </div>
    </div>

    {result.erro && <p role="status" className="mt-3 text-sm text-[var(--yellow)]">{result.erro}</p>}
    {result.semDado ? <div className="mt-3"><EmptyState title="Detalhe de disparos indisponível" hint="sem dado ainda" /></div> : rows.length === 0 ? <div className="mt-3"><EmptyState title={result.data.length === 0 ? 'Nenhum disparo no período' : 'Nenhum disparo neste canal'} hint={result.data.length === 0 ? 'sem dado ainda' : undefined} /></div> :
      <div className="mt-3 space-y-2">
        {rows.map((row, index) => {
          const link = linkHttp(row.copyLink);
          const key = row.id === null ? `${row.dataHora ?? 'sem-data'}-${index}` : String(row.id);
          return <details key={key} className="group rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)]">
            <summary className="cursor-pointer list-none p-3 marker:hidden focus-visible:outline focus-visible:outline-2 focus-visible:outline-[var(--accent)] sm:p-4">
              <div className="flex flex-wrap items-start justify-between gap-2">
                <div className="min-w-0 flex-1">
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded-full border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)]">{row.canal ? canalRotulo[row.canal] : 'Canal sem dado'}</span>
                    {row.tipo && <span className="text-xs text-[var(--fg-3)]">{row.tipo}</span>}
                    <time className="text-xs text-[var(--fg-3)]">{dataHora(row.dataHora)}</time>
                  </div>
                  <p className="mt-2 break-words font-medium text-[var(--fg)]">{row.campanha ?? 'Campanha sem dado'}</p>
                </div>
                <span className="text-xs text-[var(--accent)] group-open:hidden">Ver detalhes</span>
                <span className="hidden text-xs text-[var(--accent)] group-open:inline">Recolher</span>
              </div>
              <div className="mt-3 grid grid-cols-2 gap-2 text-xs sm:grid-cols-4">
                <span>Enviados: <strong>{numero(row.enviados)}</strong></span>
                <span>Entregues: <strong>{numero(row.entregues)}</strong></span>
                <span>Custo: <strong>{row.canalPago === false ? 'Sem custo por disparo' : row.custoCentavos === null ? 'Sem dado' : moeda.format(row.custoCentavos / 100)}</strong></span>
                <span>Entrega: <strong>{percentual(row.entregues, row.enviados)}</strong></span>
              </div>
            </summary>
            <div className="border-t border-[var(--border)] p-3 sm:p-4">
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
                <BarraTaxa label="Entregues sobre enviados" quantidade={row.entregues} base={row.enviados} />
                <BarraTaxa label="Lidas sobre entregues" quantidade={row.lidas} base={row.entregues} />
                <BarraTaxa label="Cliques sobre entregues" quantidade={row.cliques} base={row.entregues} />
                <BarraTaxa label="Falhas sobre enviados" quantidade={row.falhas} base={row.enviados} />
              </div>
              <dl className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
                <Dado label="Enviados" value={numero(row.enviados)} />
                <Dado label="Entregues" value={numero(row.entregues)} />
                <Dado label="Lidas" value={numero(row.lidas)} />
                <Dado label="Cliques" value={numero(row.cliques)} />
                <Dado label="Falhas" value={numero(row.falhas)} />
                <Dado label="Entrega sobre enviados" value={percentual(row.entregues, row.enviados)} calculado />
                <Dado label="Leitura sobre entregues" value={percentual(row.lidas, row.entregues)} calculado />
                <Dado label="Cliques sobre entregues" value={percentual(row.cliques, row.entregues)} calculado />
                <Dado label="Custo" value={row.canalPago === false ? 'Sem custo por disparo' : row.custoCentavos === null ? 'Sem dado' : moeda.format(row.custoCentavos / 100)} />
                {row.canalPago !== false && <Dado label="Custo por entregue" value={custoPorEntregue(row.custoCentavos, row.entregues)} calculado />}
                <Dado label="Ferramenta" value={row.ferramenta ?? 'Sem dado'} />
                <Dado label="Número remetente" value={row.numero ?? 'Sem dado'} />
                <Dado label="Lista de público" value={row.publicoLista ?? 'Sem dado'} />
                <Dado label="Origem do público" value={row.publicoOrigem ?? 'Sem dado'} />
                <Dado label="Origem do registro" value={row.origem ?? 'Sem dado'} />
                <Dado label="Enviado em" value={dataHora(row.enviadoEm)} />
                <Dado label="Retorno atualizado em" value={dataHora(row.retornoEm)} />
              </dl>
              <div className="mt-3 rounded-[var(--r-md)] border border-[var(--border)] p-3">
                <h4 className="text-xs font-semibold text-[var(--fg-2)]">Conteúdo</h4>
                {row.copyTexto !== null ? <p className="mt-2 whitespace-pre-wrap break-words text-sm text-[var(--fg)]">{row.copyTexto || 'Sem dado'}</p> : link ? <a aria-label="Abrir link do disparo" className="mt-2 block break-all text-sm text-[var(--accent)] underline" href={link} target="_blank" rel="noreferrer">{row.copyLink}</a> : <p className="mt-2 text-sm text-[var(--fg-3)]">Sem dado</p>}
              </div>
            </div>
          </details>;
        })}
      </div>}
  </div>;
}
