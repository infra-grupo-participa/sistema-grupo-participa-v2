'use client';

// Aba "Serviço Diamante" do financeiro (27/09/2026). Board próprio: por Diamante, quais serviços contratou, quais
// estão em dia, quais estão devendo — separando quem já pagou alguma vez de quem só tentou. Fonte: espelho da Hotmart
// (produto 1462643, uma oferta por serviço) via fn_fin_diamante_servicos. Só leitura.
import { useMemo, useState } from 'react';
import { Loading, NivelBadge, SearchInput } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../application/ports';
import {
  agruparPorDiamante, ehNivelDiamante, ORDEM_SITUACAO_SERVICO, resumirDiamantes,
  ROTULO_SITUACAO_SERVICO, rotuloServico, type DiamanteCliente, type LinhaServicoDiamante, type SituacaoServico,
} from '../domain/servico-diamante';
import { Erro, useCarga } from './hotmart/comum';

const COR: Record<SituacaoServico, string> = {
  devendo: 'var(--red)', em_dia: 'var(--green)', parou_devendo: 'var(--accent)', encerrado: 'var(--fg-4)', nunca_pagou: 'var(--yellow)',
};

const semAcento = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();

export function ServicoDiamante({ repo }: { repo: FinanceiroRepository }) {
  const { dados, erro } = useCarga<LinhaServicoDiamante[]>(() => repo.loadServicoDiamante(), []);
  const [servico, setServico] = useState<string | null>(null);
  const [situacao, setSituacao] = useState<SituacaoServico | null>(null);
  const [foraNivel, setForaNivel] = useState(false);
  const [verNuncaPagaram, setVerNuncaPagaram] = useState(false);
  const [busca, setBusca] = useState('');
  const [aberto, setAberto] = useState<string | null>(null);

  const clientes = useMemo(() => agruparPorDiamante(dados ?? []), [dados]);
  const resumo = useMemo(() => resumirDiamantes(clientes), [clientes]);

  const visiveis = useMemo(() => {
    const q = semAcento(busca.trim());
    return clientes.filter((c) => {
      if (c.jaPagou === verNuncaPagaram) return false;
      if (foraNivel && (!(c.situacao === 'em_dia' || c.situacao === 'devendo') || ehNivelDiamante(c.nivel))) return false;
      if (servico && !c.servicos.some((s) => s.servico === servico && (s.pagamentos > 0 || s.devendo_n > 0 || verNuncaPagaram))) return false;
      if (situacao) {
        const alvo = servico ? c.servicos.filter((s) => s.servico === servico) : c.servicos;
        if (!alvo.some((s) => s.situacao === situacao)) return false;
      }
      if (q && !semAcento([c.nome, ...c.emails].join(' ')).includes(q)) return false;
      return true;
    });
  }, [clientes, busca, servico, situacao, foraNivel, verNuncaPagaram]);

  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando serviços Diamante…" minHeight={260} />;

  const contagemSituacao = (s: SituacaoServico) => clientes.filter((c) => c.jaPagou && c.situacao === s).length;

  return (
    <div className="space-y-4">
      {/* Faixa de números: o que pede ação primeiro */}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
        <Tile rotulo="Diamantes que já pagaram" valor={String(resumo.jaPagaram)}
          detalhe={`${fmtBRL(resumo.totalPago)} pagos desde o início`} />
        <Tile rotulo="Em dia" valor={String(resumo.emDia)} cor="var(--green)"
          detalhe={`${fmtBRL(resumo.mensalidadeAtiva)}/mês em mensalidades`}
          ativo={situacao === 'em_dia'} onClick={() => setSituacao(situacao === 'em_dia' ? null : 'em_dia')} />
        <Tile rotulo="Devendo" valor={String(resumo.devendo)} cor="var(--red)"
          detalhe={`${fmtBRL(resumo.devendoValor)} em aberto`}
          ativo={situacao === 'devendo'} onClick={() => setSituacao(situacao === 'devendo' ? null : 'devendo')} />
        <Tile rotulo="Pararam devendo" valor={String(resumo.pararamDevendo)} cor={resumo.pararamDevendo ? 'var(--accent)' : undefined}
          detalhe={`${fmtBRL(resumo.antigoValor)} em dívida antiga (+120 dias)`}
          ativo={situacao === 'parou_devendo'} onClick={() => setSituacao(situacao === 'parou_devendo' ? null : 'parou_devendo')} />
        <Tile rotulo="Pararam sem dever" valor={String(resumo.pararam)}
          detalhe="cancelaram ou pausaram"
          ativo={situacao === 'encerrado'} onClick={() => setSituacao(situacao === 'encerrado' ? null : 'encerrado')} />
        <Tile rotulo="Ativos fora do nível Diamante" valor={String(resumo.foraDoDiamante)} cor={resumo.foraDoDiamante ? 'var(--yellow)' : undefined}
          detalhe="nível no cadastro não é Diamante"
          ativo={foraNivel} onClick={() => setForaNivel(!foraNivel)} />
      </div>

      {/* Um bloco por serviço: contrataram · em dia · devendo */}
      <div className="rounded-[var(--r-lg)] border border-[var(--cyan)]/40 bg-[var(--surface-1)] p-3">
        <div className="mb-2 flex items-center justify-between gap-2">
          <span className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Por serviço</span>
          {servico && <button type="button" onClick={() => setServico(null)} className="text-[11px] text-[var(--fg-3)] hover:text-[var(--fg)]">todos os serviços</button>}
        </div>
        <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-4">
          {resumo.servicos.map((s) => (
            <button key={s.chave} type="button" aria-pressed={servico === s.chave}
              onClick={() => setServico(servico === s.chave ? null : s.chave)}
              className={`rounded-[var(--r-md)] border px-3 py-2 text-left transition-colors ${servico === s.chave ? 'border-[var(--cyan)] bg-[var(--surface-2)]' : 'border-[var(--border)] hover:bg-[var(--surface-2)]'}`}>
              <div className="text-xs font-semibold text-[var(--fg)]">{rotuloServico(s.chave)}</div>
              <div className="mt-1 flex flex-wrap gap-x-3 text-[11px] tabular text-[var(--fg-3)]">
                <span>{s.contrataram} contrataram</span>
                <span className="text-[var(--green)]">{s.emDia} em dia</span>
                <span className={s.devendo ? 'text-[var(--red)]' : ''}>{s.devendo} devendo{s.devendo ? ` · ${fmtBRL(s.devendoValor)}` : ''}</span>
              </div>
              {s.mensalidadeAtiva > 0 && <div className="mt-0.5 text-[10px] tabular text-[var(--fg-4)]">{fmtBRL(s.mensalidadeAtiva)}/mês ativos</div>}
            </button>
          ))}
        </div>
      </div>

      {/* Filtros */}
      <div className="flex flex-wrap items-center gap-2">
        <div className="w-full sm:w-72">
          <SearchInput value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} placeholder="Buscar por nome ou e-mail" aria-label="Buscar Diamante" />
        </div>
        {!verNuncaPagaram && ORDEM_SITUACAO_SERVICO.filter((s) => s !== 'nunca_pagou').map((s) => (
          <button key={s} type="button" aria-pressed={situacao === s} onClick={() => setSituacao(situacao === s ? null : s)}
            className={`inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border px-2.5 py-1 text-xs ${situacao === s ? 'border-[var(--accent)] bg-[var(--accent-subtle)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
            <span className="h-2 w-2 rounded-full" style={{ background: COR[s] }} aria-hidden />
            {ROTULO_SITUACAO_SERVICO[s]} <span className="tabular text-[var(--fg-4)]">{contagemSituacao(s)}</span>
          </button>
        ))}
        <button type="button" aria-pressed={verNuncaPagaram} onClick={() => { setVerNuncaPagaram(!verNuncaPagaram); setSituacao(null); setForaNivel(false); }}
          className={`ml-auto rounded-[var(--r-md)] border px-3 py-1.5 text-xs font-semibold ${verNuncaPagaram ? 'border-[var(--yellow)] text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
          {verNuncaPagaram ? '← Voltar para quem já pagou' : `Tentaram e nunca pagaram (${resumo.nuncaPagaram})`}
        </button>
      </div>

      <div className="text-[11px] text-[var(--fg-3)]">
        {visiveis.length} {verNuncaPagaram ? 'nunca pagaram' : 'Diamantes'}
        {servico ? ` · ${rotuloServico(servico)}` : ''}{situacao ? ` · ${ROTULO_SITUACAO_SERVICO[situacao]}` : ''}
      </div>

      {!visiveis.length ? (
        <p className="rounded-[var(--r-lg)] border border-dashed border-[var(--border)] p-6 text-center text-sm text-[var(--fg-3)]">Ninguém neste recorte.</p>
      ) : (
        <ul className="grid gap-3 xl:grid-cols-2" aria-label="Diamantes">
          {visiveis.map((c) => (
            <li key={c.pessoa_chave}>
              <CardDiamante c={c} servicoFoco={servico} aberto={aberto === c.pessoa_chave}
                onToggle={() => setAberto(aberto === c.pessoa_chave ? null : c.pessoa_chave)} />
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Tile({ rotulo, valor, detalhe, cor, ativo, onClick }: {
  rotulo: string; valor: string; detalhe: string; cor?: string; ativo?: boolean; onClick?: () => void;
}) {
  const corpo = (
    <>
      <div className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{rotulo}</div>
      <div className="tabular mt-0.5 text-2xl font-bold" style={{ color: cor ?? 'var(--fg)' }}>{valor}</div>
      <div className="mt-0.5 text-[11px] tabular text-[var(--fg-3)]">{detalhe}</div>
    </>
  );
  const base = 'rounded-[var(--r-lg)] border bg-[var(--surface-1)] px-4 py-3 text-left';
  if (!onClick) return <div className={`${base} border-[var(--border)]`}>{corpo}</div>;
  return (
    <button type="button" aria-pressed={!!ativo} onClick={onClick}
      className={`${base} transition-colors hover:bg-[var(--surface-2)] ${ativo ? 'border-[var(--accent)]' : 'border-[var(--border)]'}`}>
      {corpo}
    </button>
  );
}

function CardDiamante({ c, servicoFoco, aberto, onToggle }: {
  c: DiamanteCliente; servicoFoco: string | null; aberto: boolean; onToggle: () => void;
}) {
  const cor = COR[c.situacao];
  const servicos = c.servicos.filter((s) => s.pagamentos > 0 || s.devendo_n > 0 || s.antigo_n > 0 || !c.jaPagou);
  return (
    <div className="h-full rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)]" style={{ borderLeft: `3px solid ${cor}` }}>
      <button type="button" onClick={onToggle} aria-expanded={aberto} className="w-full px-4 py-3 text-left hover:bg-[var(--surface-2)]">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <span className="truncate text-sm font-semibold text-[var(--fg)]">{c.nome}</span>
              {c.nivel ? <NivelBadge nivel={c.nivel} /> : <span className="text-[10px] text-[var(--fg-4)]">sem nível no cadastro</span>}
              {c.nivel && !ehNivelDiamante(c.nivel) && c.situacao !== 'encerrado' && c.jaPagou && (
                <span className="rounded-[var(--r-sm)] border border-[var(--yellow)] px-1.5 text-[10px] text-[var(--fg-2)]">fora do nível Diamante</span>
              )}
            </div>
            <div className="mt-0.5 truncate text-[11px] text-[var(--fg-3)]">
              {c.email ?? '—'}{c.telefone ? ` · ${c.telefone}` : ''}
            </div>
          </div>
          <div className="shrink-0 text-right">
            <div className="text-[11px] font-semibold" style={{ color: cor }}>{ROTULO_SITUACAO_SERVICO[c.situacao]}</div>
            {c.devendoValor + c.antigoValor > 0
              ? <div className="tabular text-sm font-bold text-[var(--red)]">{fmtBRL(c.devendoValor + c.antigoValor)}</div>
              : c.mensalidadeAtiva > 0
                ? <div className="tabular text-sm font-bold text-[var(--fg)]">{fmtBRL(c.mensalidadeAtiva)}<span className="text-[10px] font-normal text-[var(--fg-3)]">/mês</span></div>
                : <div className="tabular text-[11px] text-[var(--fg-3)]">{c.ultimaPaga ? `último ${fmtData(c.ultimaPaga)}` : 'nenhum pagamento'}</div>}
          </div>
        </div>
        <div className="mt-2 flex flex-wrap gap-1.5">
          {servicos.map((s) => (
            <span key={s.servico}
              className={`inline-flex items-center gap-1.5 rounded-[var(--r-sm)] border px-2 py-0.5 text-[11px] ${servicoFoco === s.servico ? 'border-[var(--cyan)]' : 'border-[var(--border)]'} bg-[var(--surface-2)] text-[var(--fg-2)]`}
              title={`${rotuloServico(s.servico)}: ${ROTULO_SITUACAO_SERVICO[s.situacao]}`}>
              <span className="h-1.5 w-1.5 rounded-full" style={{ background: COR[s.situacao] }} aria-hidden />
              {rotuloServico(s.servico)}
              {s.devendo_n + s.antigo_n > 0 && <span className="tabular text-[var(--red)]">{s.devendo_n + s.antigo_n}×</span>}
            </span>
          ))}
        </div>
      </button>
      {aberto && (
        <div className="border-t border-[var(--border)] px-4 py-3">
          <table className="w-full text-[11px]">
            <thead>
              <tr className="text-left text-[var(--fg-3)]">
                <th className="pb-1 font-semibold">Serviço</th><th className="pb-1 font-semibold">Situação</th>
                <th className="pb-1 font-semibold">Mensalidade</th><th className="pb-1 font-semibold">Pagou</th>
                <th className="pb-1 font-semibold">Devendo</th>
              </tr>
            </thead>
            <tbody>
              {servicos.map((s) => {
                return (
                  <tr key={s.servico} className="border-t border-[var(--border)] align-top">
                    <td className="py-1.5 pr-2 font-medium text-[var(--fg)]">
                      {rotuloServico(s.servico)}
                      {s.desconhecida && <span className="block text-[10px] text-[var(--fg-4)]">{(s.ofertas ?? []).join(', ')}</span>}
                    </td>
                    <td className="py-1.5 pr-2" style={{ color: COR[s.situacao] }}>{ROTULO_SITUACAO_SERVICO[s.situacao]}</td>
                    <td className="py-1.5 pr-2 tabular">{s.mensalidade ? fmtBRL(Number(s.mensalidade)) : '—'}</td>
                    <td className="py-1.5 pr-2 tabular text-[var(--fg-2)]">
                      {s.pagamentos ? <>{s.pagamentos}× · {fmtBRL(Number(s.total_pago))}<span className="block text-[10px] text-[var(--fg-4)]">{fmtData(s.primeira_paga!)} a {fmtData(s.ultima_paga!)}</span></> : '—'}
                    </td>
                    <td className="py-1.5 tabular">
                      {s.devendo_n ? (
                        <span className="block text-[var(--red)]">{s.devendo_n}× · {fmtBRL(Number(s.devendo_valor))}
                          <span className="block text-[10px] text-[var(--fg-3)]">desde {fmtData(s.devendo_desde!)}</span>
                        </span>
                      ) : null}
                      {s.antigo_n ? (
                        <span className="block text-[var(--fg-2)]">{s.antigo_n}× · {fmtBRL(Number(s.antigo_valor))}
                          <span className="block text-[10px] text-[var(--fg-3)]">antiga, desde {fmtData(s.antigo_desde!)}</span>
                        </span>
                      ) : null}
                      {!s.devendo_n && !s.antigo_n && '—'}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {c.emails.length > 1 && <p className="mt-2 text-[10px] text-[var(--fg-4)]">E-mails: {c.emails.join(', ')}</p>}
        </div>
      )}
    </div>
  );
}
