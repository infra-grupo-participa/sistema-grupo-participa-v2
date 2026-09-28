'use client';

// Peças da ficha reorganizada (pedido do João, 27/09: "quando a gente clica no perfil do aluno, entender melhor o que
// está acontecendo… o histórico financeiro está muito desorganizado").
//  * EmUmaOlhada — os 4 números que respondem a situação da pessoa, lado a lado, no topo do Resumo.
//  * PagamentosFicha — UMA lista com todos os pagamentos (Hotmart + board), cada um marcado se está no board.
import { useMemo, useState } from 'react';
import { Badge, EmptyState, Loading } from '@/shared/ui/components';
import type { Tone } from '@/shared/ui/components/Badge';
import { Icon } from '@/shared/ui/icons';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import type { ContaReceber, Lancamento } from '../domain/types';
import { ROTULO_GRUPO, rotuloCategorias, rotuloMetodo, type BoardHotmart, type TransacaoHotmart } from '../domain/hotmart';
import { explicarDivergencia, temDadoHotmart } from '../domain/board-hotmart';
import { foraDoCard, linhaAtrasoMensalidade, type ResumoAssinaturaCard } from '../domain/assinatura-hm';
import { juntarPagamentos, resumirPagamentos, type PagamentoFicha } from '../domain/pagamentos-ficha';
import { Chip, Erro, useCarga } from './hotmart/comum';

export function Bloco({ rotulo, valor, detalhe, tom = 'neutro' }: {
  rotulo: string; valor: string; detalhe?: string | null; tom?: 'neutro' | 'verde' | 'amarelo' | 'vermelho';
}) {
  const cor = { neutro: 'text-[var(--fg)]', verde: 'text-[var(--green)]', amarelo: 'text-[var(--yellow)]', vermelho: 'text-[var(--red)]' }[tom];
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2.5">
      <div className="text-[10px] font-medium uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className={`tabular text-base font-bold leading-tight ${cor}`}>{valor}</div>
      {detalhe && <div className="mt-0.5 text-[11px] leading-snug text-[var(--fg-3)]">{detalhe}</div>}
    </div>
  );
}

/** A situação em 4 números: o que o board registra, o que a Hotmart recebeu, o que está devendo lá e o que existe
 *  fora do card (assinatura/outros). Uma frase embaixo quando board e Hotmart não batem. */
export function EmUmaOlhada({ conta, hm, carregando, assinatura = null }: {
  conta: ContaReceber; hm: BoardHotmart | null; carregando: boolean;
  /** Bloco Assinatura HM já resolvido (z52): entra no "fora deste card" e no atraso — nunca soma no "devendo". */
  assinatura?: ResumoAssinaturaCard | null;
}) {
  const tem = temDadoHotmart(hm);
  // Mensalidade do HM antigo entra aqui também no card Aurum (o board só a traz na linha HM), sem somar duas vezes.
  const { n: nOutros, valor: outros } = tem ? foraDoCard(hm, assinatura) : { n: 0, valor: 0 };
  const explicacao = tem ? explicarDivergencia(hm, fmtBRLc) : null;
  const atrasoMensalidade = tem ? linhaAtrasoMensalidade(assinatura, fmtBRLc) : null;
  return (
    <section>
      <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Em uma olhada</div>
      <div className="grid grid-cols-2 gap-2">
        <Bloco rotulo="Pago segundo o board" valor={fmtBRLc(conta.total_pago_bruto)}
          detalhe={conta.pacote ? `de ${fmtBRLc(conta.pacote)} do pacote` : 'sem pacote definido'} />
        <Bloco rotulo="Recebido na Hotmart" tom="verde"
          valor={carregando ? '…' : tem ? fmtBRLc(hm.pago_bruto) : '—'}
          detalhe={carregando ? null : tem ? `${hm.vendas_pagas} venda${hm.vendas_pagas === 1 ? '' : 's'} deste contrato · líquido ${fmtBRLc(hm.liquido)}` : 'pessoa não encontrada na Hotmart'} />
        <Bloco rotulo="Devendo na Hotmart" tom={tem && hm.parcelas_devidas > 0 ? 'vermelho' : 'neutro'}
          valor={carregando ? '…' : tem ? (hm.parcelas_devidas > 0 ? fmtBRLc(hm.valor_devido) : 'Nada') : '—'}
          detalhe={tem && hm.parcelas_devidas > 0 ? `${hm.parcelas_devidas} parcela${hm.parcelas_devidas === 1 ? '' : 's'} em atraso` : 'parcelas em dia'} />
        <Bloco rotulo="Fora deste card" valor={carregando ? '…' : tem && nOutros > 0 ? fmtBRLc(outros) : 'Nada'}
          detalhe={tem && nOutros > 0 ? `${nOutros} pagamento${nOutros === 1 ? '' : 's'} (renovação, assinatura, outras ofertas)` : 'sem outros pagamentos'} />
      </div>
      {atrasoMensalidade && (
        <p className="mt-1.5 text-[11px] font-semibold text-[var(--red)]">
          Assinatura HM: {atrasoMensalidade} <span className="font-normal text-[var(--fg-3)]">(últimos 120 dias; fora do devendo do Programa)</span>
        </p>
      )}
      {explicacao ? (
        <div className="mt-2 flex items-start gap-1.5 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-2 text-xs text-[var(--fg-2)]">
          <Icon name="alert" size={13} className="mt-0.5 shrink-0 text-[var(--yellow)]" />
          <span><strong className="font-semibold">Board e Hotmart não batem:</strong> {explicacao}</span>
        </div>
      ) : tem && hm.diverge === false ? (
        <p className="mt-1.5 flex items-center gap-1 text-[11px] text-[var(--fg-3)]"><Icon name="check-circle" size={12} className="text-[var(--green)]" /> Board e Hotmart batem.</p>
      ) : null}
    </section>
  );
}

const TOM_GRUPO: Record<TransacaoHotmart['grupo'], Tone> = {
  pago: 'success', estornado: 'danger', atrasado: 'danger', em_aberto: 'warning', recusado: 'neutral', expirado: 'neutral', outro: 'neutral',
};
const FONTE: Record<PagamentoFicha['fonte'], { rotulo: string; titulo: string; classe: string }> = {
  hotmart_e_board: { rotulo: 'no board', titulo: 'Está na Hotmart e lançado no board', classe: 'text-[var(--green)]' },
  so_hotmart: { rotulo: 'só na Hotmart', titulo: 'Pago na Hotmart e não lançado neste card (renovação, outra oferta ou webhook perdido)', classe: 'text-[var(--yellow)]' },
  so_board: { rotulo: 'só no board', titulo: 'Lançado à mão no board, sem venda na Hotmart (Pix, acordo)', classe: 'text-[var(--fg-3)]' },
};
type Filtro = 'todos' | 'pagos' | 'fora' | 'nao_pagos';

/** Todos os pagamentos da pessoa, uma linha cada, do mais novo ao mais antigo. */
export function PagamentosFicha({ conta, repo, board }: { conta: ContaReceber; repo: FinanceiroRepository; board: Lancamento[] }) {
  const { dados, erro } = useCarga<TransacaoHotmart[]>(
    () => (conta.email ? repo.loadHotmartExtrato(conta.email) : Promise.resolve([])), [conta.email]);
  const [filtro, setFiltro] = useState<Filtro>('todos');
  const lista = useMemo(() => juntarPagamentos(board, dados ?? []), [board, dados]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando pagamentos…" minHeight={120} />;
  const r = resumirPagamentos(lista);
  const vis = lista.filter((p) =>
    filtro === 'pagos' ? p.grupo === 'pago'
      : filtro === 'fora' ? p.grupo === 'pago' && p.fonte === 'so_hotmart'
      : filtro === 'nao_pagos' ? p.grupo !== 'pago' && p.grupo !== 'estornado'
      : true);

  return (
    <section>
      <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Todos os pagamentos</div>
      <div className="mb-2 grid grid-cols-3 gap-2">
        <Bloco rotulo="Pago" tom="verde" valor={fmtBRLc(r.valorPago)} detalhe={`${r.pagos} pagamento${r.pagos === 1 ? '' : 's'}`} />
        <Bloco rotulo="Fora do board" tom={r.foraDoBoard ? 'amarelo' : 'neutro'} valor={r.foraDoBoard ? fmtBRLc(r.valorForaDoBoard) : 'Nada'}
          detalhe={r.foraDoBoard ? `${r.foraDoBoard} pago${r.foraDoBoard === 1 ? '' : 's'} só na Hotmart` : 'tudo lançado'} />
        <Bloco rotulo="Não pagos" valor={String(r.tentativas)} detalhe={r.estornos ? `${r.estornos} reembolso${r.estornos === 1 ? '' : 's'}` : 'tentativas, boletos, recusas'} />
      </div>
      <div className="mb-2 flex flex-wrap gap-1.5">
        <Chip ativo={filtro === 'todos'} onClick={() => setFiltro('todos')}>Todos · {lista.length}</Chip>
        <Chip ativo={filtro === 'pagos'} onClick={() => setFiltro('pagos')} tom="success">Pagos · {r.pagos}</Chip>
        <Chip ativo={filtro === 'fora'} onClick={() => setFiltro('fora')} tom="warning">Fora do board · {r.foraDoBoard}</Chip>
        <Chip ativo={filtro === 'nao_pagos'} onClick={() => setFiltro('nao_pagos')}>Não pagos · {r.tentativas}</Chip>
      </div>
      {!vis.length ? <EmptyState title="Nada neste filtro" icon="receipt" /> : (
        <ul className="divide-y divide-[var(--border)] rounded-[var(--r-lg)] border border-[var(--border)]">
          {vis.map((p) => (
            <li key={p.chave} className="px-3 py-2">
              <div className="flex items-baseline justify-between gap-3">
                <span className="min-w-0 text-sm text-[var(--fg)]">
                  <span className="tabular">{p.data ? fmtData(p.data) : '—'}</span>
                  {' · '}<span className="font-medium">{p.categoriaBoard ? rotuloCategorias(p.categoriaBoard) : p.produto ?? '—'}</span>
                </span>
                <span className={`shrink-0 tabular text-sm font-semibold ${p.grupo === 'pago' ? 'text-[var(--fg)]' : 'text-[var(--fg-3)] line-through decoration-[var(--fg-4)]'}`}>
                  {fmtBRLc(p.valor)}
                </span>
              </div>
              <div className="mt-0.5 flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-[var(--fg-3)]">
                <Badge tone={TOM_GRUPO[p.grupo]}>{ROTULO_GRUPO[p.grupo]}</Badge>
                {p.grupo === 'pago' && <span className={`font-semibold ${FONTE[p.fonte].classe}`} title={FONTE[p.fonte].titulo}>{FONTE[p.fonte].rotulo}</span>}
                <span>{rotuloMetodo(p.metodo)}{p.parcelas && p.parcelas > 1 ? ` · ${p.parcelas}x` : ''}{p.recorrencia ? ` · parcela ${p.recorrencia}` : ''}</span>
                {(p.produto || p.oferta) && <span className="truncate">{p.categoriaBoard && p.produto ? `${p.produto} · ` : ''}{p.oferta ?? ''}</span>}
                {p.liquido != null && p.grupo === 'pago' && <span className="tabular">líquido {fmtBRLc(p.liquido)}</span>}
              </div>
              {p.obs && <div className="mt-0.5 text-[11px] italic text-[var(--fg-3)]">{p.obs}</div>}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
