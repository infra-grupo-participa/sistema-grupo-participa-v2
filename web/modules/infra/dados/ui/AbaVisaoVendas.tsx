import type { ReactNode } from 'react';
import { EmptyState } from '@/shared/ui/components';
import type { EstadoLeitura } from '../application/ultimo-dado';
import type { DiaPresencial, GrupoPendencia, PagamentoPresencial, PendenciaPresencial, PerfilCompradorPresencial, SerieVendasPresencial, VendaHoraPresencial } from '../domain/presencial';
import { SerieDiaria } from './viz/SerieDiaria';
import { GraficoPagamentos } from './viz/GraficoPagamentos';
import { RoscaCategorias } from './viz/RoscaCategorias';
import { GraficosSerieVendas, GraficoVendasHora } from './viz/GraficosTemporais';

function BlocoLeitura<T>({ estado, nome, children }: { estado: EstadoLeitura<T>; nome: string; children: (dados: T) => ReactNode }) {
  const dados = estado.resultado?.data ?? null;
  if (estado.carregando && dados === null) return <p>Carregando {nome}…</p>;
  return <div className="space-y-3">
    {estado.resultado?.erro && <p role="alert" className="text-sm text-[var(--fg-2)]">{estado.resultado.erro} {dados !== null && `Exibindo os últimos dados de ${nome}.`}</p>}
    {dados !== null ? children(dados) : !estado.resultado?.erro && <p role="alert">Não foi possível carregar {nome} agora.</p>}
  </div>;
}

function PerfilCompradores({ linhas }: { linhas: PerfilCompradorPresencial[] }) {
  if (!linhas.length) return <EmptyState title="Sem compradores para analisar" />;
  const fatias = (dimensao: 'turma' | 'instrucao') => {
    const valores = linhas.filter((l) => l.dimensao === dimensao).map((l) => ({ rotulo: l.valor, quantidade: l.compradores }));
    return valores.some((l) => l.rotulo === 'Não é aluno') ? valores : [...valores, { rotulo: 'Não é aluno', quantidade: 0 }];
  };
  const casamento = (valor: string) => linhas.find((l) => l.dimensao === 'casamento' && l.valor === valor)?.compradores ?? 0;
  return <div className="space-y-3"><div className="grid gap-3 lg:grid-cols-2"><RoscaCategorias titulo="Turma de quem comprou" fatias={fatias('turma')} /><RoscaCategorias titulo="Instrução" fatias={fatias('instrucao')} /></div>
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4"><h3 className="mb-2 text-sm font-semibold text-[var(--fg)]">Legenda do casamento com a base de alunos</h3><p className="text-sm text-[var(--fg-2)]">E-mail: {casamento('email').toLocaleString('pt-BR')} · Documento: {casamento('documento').toLocaleString('pt-BR')} · Telefone: {casamento('telefone').toLocaleString('pt-BR')} · Não é aluno: {casamento('nao_casou').toLocaleString('pt-BR')}</p></div>
  </div>;
}

function Pendencias({ linhas, abrir }: { linhas: PendenciaPresencial[]; abrir: (grupo: GrupoPendencia) => void }) {
  if (!linhas.length) return <EmptyState title="Sem dados de pendências" />;
  const total = (grupo: GrupoPendencia) => linhas.find((l) => l.grupo === grupo && l.categoria === 'total');
  const categoria = (grupo: GrupoPendencia, nome: string) => linhas.find((l) => l.grupo === grupo && l.categoria === nome)?.pessoas ?? 0;
  const canceladas = linhas.filter((l) => l.grupo === 'cancelada' && l.categoria !== 'total');
  return <div className="grid gap-3 lg:grid-cols-2">
    <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4"><h3 className="text-sm font-semibold text-[var(--fg)]">Boletos e Pix gerados e não pagos</h3><p className="mt-2 text-3xl font-bold tabular text-[var(--fg)]">{total('nao_pago')?.pessoas.toLocaleString('pt-BR') ?? 'sem dado'}</p><p className="mt-1 text-xs text-[var(--fg-2)]">Pessoas únicas sem outra transação paga</p><p className="mt-3 text-sm text-[var(--fg-2)]">Boleto: {categoria('nao_pago', 'boleto').toLocaleString('pt-BR')} · Pix: {categoria('nao_pago', 'pix').toLocaleString('pt-BR')}{categoria('nao_pago', 'outro') > 0 && ` · Outro: ${categoria('nao_pago', 'outro').toLocaleString('pt-BR')}`}</p><button type="button" onClick={() => abrir('nao_pago')} className="mt-4 rounded-[var(--r-md)] border border-[var(--accent-border)] px-3 py-2 text-sm font-medium text-[var(--accent)] hover:bg-[var(--accent-subtle)]">Ver pessoas</button></section>
    <section className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4"><h3 className="text-sm font-semibold text-[var(--fg)]">Compras canceladas</h3><p className="mt-2 text-3xl font-bold tabular text-[var(--fg)]">{total('cancelada')?.pessoas.toLocaleString('pt-BR') ?? 'sem dado'}</p><p className="mt-1 text-xs text-[var(--fg-2)]">Pessoas únicas sem outra transação paga. Categorias podem se sobrepor.</p><ul className="mt-3 space-y-1 text-sm text-[var(--fg-2)]">{canceladas.map((l) => <li key={l.categoria}>{l.categoria}: {l.pessoas.toLocaleString('pt-BR')}</li>)}</ul><button type="button" onClick={() => abrir('cancelada')} className="mt-4 rounded-[var(--r-md)] border border-[var(--accent-border)] px-3 py-2 text-sm font-medium text-[var(--accent)] hover:bg-[var(--accent-subtle)]">Ver pessoas</button></section>
  </div>;
}

export function AbaVisaoVendas({ dias, pagamentos, perfil, pendencias, serieVendas, porHora, abrirPendencias }: {
  dias: EstadoLeitura<DiaPresencial[]>;
  pagamentos: EstadoLeitura<PagamentoPresencial[]>;
  perfil: EstadoLeitura<PerfilCompradorPresencial[]>;
  pendencias: EstadoLeitura<PendenciaPresencial[]>;
  serieVendas: EstadoLeitura<SerieVendasPresencial[]>;
  porHora: EstadoLeitura<VendaHoraPresencial[]>;
  abrirPendencias: (grupo: GrupoPendencia) => void;
}) {
  return <div className="space-y-5">
    <BlocoLeitura estado={dias} nome="série diária">{(dados) => dados.length ? <div><h2 className="mb-1 text-base font-semibold text-[var(--fg)]">Pré-checkout, pedidos e vendas por dia</h2><p className="mb-3 text-sm text-[var(--fg-2)]">Pedidos são transações criadas na Hotmart, em qualquer status. Abandonos: sem fonte.</p><SerieDiaria dias={dados} /></div> : <EmptyState title="Sem dados na série diária" />}</BlocoLeitura>
    <BlocoLeitura estado={pagamentos} nome="formas de pagamento">{(dados) => <GraficoPagamentos linhas={dados} />}</BlocoLeitura>
    <BlocoLeitura estado={perfil} nome="perfil dos compradores">{(dados) => <PerfilCompradores linhas={dados} />}</BlocoLeitura>
    <BlocoLeitura estado={pendencias} nome="pendências">{(dados) => <Pendencias linhas={dados} abrir={abrirPendencias} />}</BlocoLeitura>
    <BlocoLeitura estado={serieVendas} nome="série de vendas">{(dados) => <GraficosSerieVendas linhas={dados} />}</BlocoLeitura>
    <BlocoLeitura estado={porHora} nome="vendas por hora">{(dados) => <GraficoVendasHora linhas={dados} />}</BlocoLeitura>
  </div>;
}
