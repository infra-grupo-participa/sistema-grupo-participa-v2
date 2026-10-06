'use client';

// Cartão de um vendedor na aba Equipe: resultado, eficiência, disciplina e alertas num bloco que cabe em
// qualquer largura (sem tabela larga). O detalhe completo abre na ficha (DetalheVendedor).
import { Button, Card } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { Pessoa } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import {
  diferencaPp, META_PRIMEIRO_CONTATO_MIN, variacaoPct, type IndicadoresVendedor, type ReferenciaTime, type Selo,
} from './performance';
import { INFO_EQUIPE } from './textos';
import { Delta, fmtMin, fmtNum, fmtPct, Indicador, SeloBadge, Sparkline } from './visuais';

const vsTime = (valor: React.ReactNode) => <span className="text-[11px] text-[var(--fg-3)]">time {valor}</span>;

export function CartaoVendedor({ nome, l, anterior, time: refTime, selos, tendencia, onAbrir }: {
  nome: string;
  l: IndicadoresVendedor;
  anterior: IndicadoresVendedor;
  time: ReferenciaTime;
  selos: Selo[];
  tendencia: { dia: string; valor: number }[];
  onAbrir: () => void;
}) {
  const alertas = selos.filter((s) => s.tipo === 'alerta');
  const destaques = selos.filter((s) => s.tipo === 'destaque');
  return (
    <Card className="flex flex-col p-4 min-w-0">
      <div className="flex items-start justify-between gap-2">
        <Pessoa
          nome={nome}
          sub={`${l.abertos} ${l.abertos === 1 ? 'negócio aberto' : 'negócios abertos'}`}
          onClick={onAbrir}
          rotuloAcao={`Abrir o detalhe de ${nome}`}
        />
        <Button size="sm" variant="ghost" onClick={onAbrir} aria-label={`Ver detalhe de ${nome}`}>
          Detalhe <Icon name="chevron-right" size={14} />
        </Button>
      </div>

      {(alertas.length > 0 || destaques.length > 0) && (
        <div className="mt-3 flex flex-wrap gap-1.5" aria-label="Selos">
          {[...alertas, ...destaques].map((s) => <SeloBadge key={s.k} selo={s} />)}
        </div>
      )}

      {/* Resultado: vendas e receita contra o período anterior; ticket e conversão contra o time. */}
      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 rounded-[var(--r-md)] border border-[var(--border-faint)] bg-[var(--surface-2)] p-3">
        <Indicador rotulo="Vendas" metrica="vendas" valor={l.vendas} sub={<Delta valor={variacaoPct(l.vendas, anterior.vendas)} rotulo="vs anterior" />} />
        <Indicador rotulo="Receita" metrica="receita" valor={fmtBRL(l.receita)} sub={<Delta valor={variacaoPct(l.receita, anterior.receita)} rotulo="vs anterior" />} />
        <Indicador rotulo="Ticket médio" info={INFO_EQUIPE.ticket} valor={fmtBRL(l.ticketMedio)} sub={vsTime(fmtBRL(refTime.ticketMedio))} />
        <Indicador
          rotulo="Conversão" metrica="conversao"
          valor={<>{fmtPct(l.conversao)}{l.encerrados > 0 && <span className="ml-1 text-[11px] font-normal text-[var(--fg-3)]">{l.ganhos} de {l.encerrados}</span>}</>}
          sub={<Delta valor={diferencaPp(l.conversao, refTime.conversao)} rotulo="vs time" pp />}
        />
      </dl>

      {/* Velocidade, esforço e disciplina. */}
      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-3 sm:grid-cols-3">
        <Indicador
          rotulo="1º contato" metrica="tempo_primeiro_contato" valor={fmtMin(l.tempoPrimeiroContatoMin)}
          alerta={l.tempoPrimeiroContatoMin != null && l.tempoPrimeiroContatoMin > META_PRIMEIRO_CONTATO_MIN}
          sub={vsTime(fmtMin(refTime.tempoPrimeiroContatoMin))}
        />
        <Indicador rotulo="Abordagens/dia" info={INFO_EQUIPE.abordagensDia} valor={fmtNum(l.abordagensDia)} sub={vsTime(fmtNum(refTime.abordagensDia))} />
        <Indicador
          rotulo="No prazo" info={INFO_EQUIPE.noPrazo} valor={fmtPct(l.noPrazo.pct)}
          alerta={l.noPrazo.pct != null && l.noPrazo.pct < 90}
          sub={vsTime(fmtPct(refTime.noPrazoPct))}
        />
        <Indicador rotulo="Carga" metrica="abertos" valor={l.abertos} sub={vsTime(fmtNum(refTime.abertos))} />
        <Indicador rotulo="Atrasadas" metrica="atrasadas" valor={l.atrasadas} alerta={l.atrasadas > 0} sub={vsTime(fmtNum(refTime.atrasadas))} />
        <Indicador rotulo="Sem próximo" metrica="sem_proximo" valor={l.semProximo} alerta={l.semProximo > 0} sub={vsTime(fmtNum(refTime.semProximo))} />
      </dl>

      <div className="mt-3 space-y-1.5 border-t border-[var(--border-faint)] pt-3 text-xs">
        <p className="flex flex-wrap items-center gap-x-1 text-[var(--fg-2)]">
          <span className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">Perdidos <InfoIndicador metrica="perdidos" /></span>
          <span className="font-semibold tabular text-[var(--fg)]">{l.perdidos}</span>
          {l.principalMotivo && <span className="min-w-0 truncate text-[var(--fg-3)]">· principal: {l.principalMotivo.rotulo} ({l.principalMotivo.quantidade})</span>}
        </p>
        <p className="flex flex-wrap items-center gap-x-1 text-[var(--fg-2)]">
          <span className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">Reembolso e condição especial <InfoIndicador texto={INFO_EQUIPE.qualidade} /></span>
          <span className="text-[var(--fg-3)]">entra com o backend</span>
        </p>
        <p className="flex flex-wrap items-center gap-x-1 text-[var(--fg-2)]">
          <span className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">Conversas sem resposta <InfoIndicador texto={INFO_EQUIPE.semResposta} /></span>
          <span className={`font-semibold tabular ${l.semResposta > 0 ? 'text-[var(--red)]' : 'text-[var(--fg)]'}`}>{l.semResposta}</span>
        </p>
      </div>

      <div className="mt-auto pt-3">
        <div className="flex items-center gap-0.5 text-[11px] text-[var(--fg-3)]">Receita por dia <InfoIndicador texto={INFO_EQUIPE.tendencia} /></div>
        <Sparkline pontos={tendencia} rotulo={`Receita por dia de ${nome}`} />
      </div>
    </Card>
  );
}
