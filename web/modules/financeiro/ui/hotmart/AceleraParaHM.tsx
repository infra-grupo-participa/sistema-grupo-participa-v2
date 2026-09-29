'use client';

// Relatório "Acelera → HM" — quem comprou o Acelera Holding e quanto disso
// migrou para o HM depois. O furo conhecido é "subiu mas não tem card no
// board" (perdemos o rastro da cobrança) — por isso o número tem destaque.
import { useState } from 'react';
import { DataTable, EmptyState, KpiCard, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import { celulaCsv, type AceleraParaHM as LinhaAceleraParaHM } from '../../domain/hotmart';
import { Chip, Erro, useCarga } from './comum';
import { BotaoExportarPdf } from '@/shared/ui/pdf/BotaoExportarPdf';
import { chamadasProtocoloFinanceiro } from '../pdf/protocolo';
import { NIVEIS_RELATORIO, rascunhoAcelera, recorteAcelera } from '../pdf/documentos';

type Filtro = 'subiram' | 'sem_card' | 'ja_eram' | 'nao_subiram' | null;

export function AceleraParaHM({ repo }: { repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<LinhaAceleraParaHM[]>(() => repo.loadAceleraParaHM(), []);
  const [filtro, setFiltro] = useState<Filtro>(null);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando quem subiu do Acelera para o HM…" minHeight={200} />;

  const subiram = dados.filter((p) => p.subiu);
  const jaEramHm = dados.filter((p) => p.ja_era_hm).length;
  const semCard = subiram.filter((p) => !p.tem_card).length;
  // Só quem subiu: pagamento de quem já era HM (mensalidade, saldo antigo) não é conversão do Acelera.
  const totalHmDepois = subiram.reduce((s, p) => s + Number(p.hm_pago_depois ?? 0), 0);
  const comDias = subiram.filter((p) => p.dias_ate_subir != null);
  const mediaDias = comDias.length ? comDias.reduce((s, p) => s + Number(p.dias_ate_subir), 0) / comDias.length : null;

  const lista = dados.filter((p) => {
    if (filtro === 'subiram') return p.subiu;
    if (filtro === 'sem_card') return p.subiu && !p.tem_card;
    if (filtro === 'ja_eram') return p.ja_era_hm;
    if (filtro === 'nao_subiram') return !p.subiu;
    return true;
  });

  return (
    <div className="space-y-4">
      <div className="grid grid-cols-2 lg:grid-cols-3 gap-2.5">
        <KpiCard label="Compradores do Acelera" value={String(dados.length)} bar="accent" />
        <KpiCard label="Subiram para o HM" value={String(subiram.length)} bar="green" />
        <KpiCard label="Já eram HM antes" value={String(jaEramHm)} bar="gray" />
        <KpiCard label="Pago no HM por quem subiu" value={fmtBRLc(totalHmDepois)} bar="purple" />
        <KpiCard label="Média de dias até subir" value={mediaDias != null ? `${mediaDias.toFixed(0)} dias` : '—'} bar="accent" />
        <KpiCard
          label="Subiram sem card no board" value={String(semCard)} bar="red"
          hint="Furo conhecido: pagou HM, sem card para cobrar" title="Pessoas que pagaram HM depois do Acelera mas não têm card no board — a cobrança perde o rastro."
        />
      </div>

      <div className="flex flex-wrap gap-1.5">
        <Chip ativo={filtro == null} onClick={() => setFiltro(null)}>Todos · {dados.length}</Chip>
        <Chip ativo={filtro === 'subiram'} onClick={() => setFiltro('subiram')} tom="success">Subiram · {subiram.length}</Chip>
        <Chip ativo={filtro === 'sem_card'} onClick={() => setFiltro('sem_card')} tom="danger">Subiram sem card · {semCard}</Chip>
        <Chip ativo={filtro === 'ja_eram'} onClick={() => setFiltro('ja_eram')} tom="info">Já eram HM · {jaEramHm}</Chip>
        <Chip ativo={filtro === 'nao_subiram'} onClick={() => setFiltro('nao_subiram')}>Não subiram · {dados.length - subiram.length}</Chip>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <button
          type="button" onClick={() => exportarAceleraParaHmCsv(lista)}
          className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]"
        >
          Exportar CSV ({lista.length})
        </button>
        <BotaoExportarPdf
          montar={() => rascunhoAcelera(lista, recorteAcelera(filtro))}
          niveis={NIVEIS_RELATORIO.acelera}
          chamadas={chamadasProtocoloFinanceiro()}
        />
        <span className="text-xs text-[var(--fg-3)] tabular">{lista.length} pessoa(s)</span>
      </div>

      {!lista.length ? <EmptyState title="Ninguém neste recorte" /> : (
        <DataTable minWidth={980}>
          <Thead>
            <Th>Pessoa</Th><Th>1ª compra Acelera</Th><Th>Pago Acelera</Th><Th>Subiu?</Th><Th>Pago no HM depois</Th><Th>Card no board</Th>
          </Thead>
          <tbody>
            {lista.map((p) => (
              <Tr key={p.pessoa_chave}>
                <Td>
                  <div className="font-medium text-[var(--fg)]">{p.nome ?? '—'}</div>
                  <div className="text-[11px] text-[var(--fg-3)] break-all">{p.email ?? '—'}</div>
                </Td>
                <Td className="text-[11px]">
                  <div className="text-[var(--fg-2)]">{fmtData(p.primeira_acelera)}</div>
                  {p.acelera_funil && <div className="text-[var(--fg-3)]">{p.acelera_funil}</div>}
                </Td>
                <Td className="tabular">{fmtBRLc(p.acelera_pago)}</Td>
                <Td className="text-[11px]">
                  {p.subiu ? (
                    <>
                      <div className="text-[var(--green)] font-medium">{fmtData(p.primeira_hm_depois)}</div>
                      {p.dias_ate_subir != null && <div className="text-[var(--fg-3)]">{p.dias_ate_subir} dia(s) depois</div>}
                    </>
                  ) : p.ja_era_hm ? (
                    <span className="text-[var(--fg-3)]">Já era HM antes</span>
                  ) : (
                    <span className="text-[var(--fg-4)]">Não subiu</span>
                  )}
                </Td>
                <Td className="tabular">
                  {fmtBRLc(p.hm_pago_depois)}
                  {p.hm_caminho && <div className="text-[11px] text-[var(--fg-3)]">{p.hm_caminho}</div>}
                </Td>
                <Td>
                  {p.tem_card ? 'Sim' : (
                    <span className={p.subiu ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-4)]'}>Não</span>
                  )}
                </Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}
    </div>
  );
}

/** CSV da lista filtrada (separador ; para abrir direto no Excel em pt-BR). */
function exportarAceleraParaHmCsv(lista: LinhaAceleraParaHM[]) {
  const col: [string, (p: LinhaAceleraParaHM) => unknown][] = [
    ['Nome', (p) => p.nome], ['E-mail', (p) => p.email],
    ['1ª compra Acelera', (p) => p.primeira_acelera], ['Pago Acelera', (p) => Number(p.acelera_pago)],
    ['Funil Acelera', (p) => p.acelera_funil], ['Já era HM antes', (p) => (p.ja_era_hm ? 'sim' : 'não')],
    ['Subiu', (p) => (p.subiu ? 'sim' : 'não')], ['1ª compra HM depois', (p) => p.primeira_hm_depois],
    ['Dias até subir', (p) => p.dias_ate_subir], ['Pago no HM depois', (p) => Number(p.hm_pago_depois)],
    ['Caminho HM', (p) => p.hm_caminho], ['Card no board', (p) => (p.tem_card ? 'sim' : 'não')],
  ];
  const linhas = [col.map(([c]) => c).join(';'), ...lista.map((p) => col.map(([, f]) => celulaCsv(f(p))).join(';'))];
  const blob = new Blob(['﻿' + linhas.join('\n')], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `acelera-para-hm-${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(a.href);
}
