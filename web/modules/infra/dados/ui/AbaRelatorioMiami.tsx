'use client';

import { useEffect, useState } from 'react';
import { EmptyState, Loading } from '@/shared/ui/components';
import type { EstadoRelatorioMiami } from '../application/relatorio-miami-estado';
import { idadeCurta, type ConteudoRelatorioMiami } from '../domain/relatorio-miami';
import { dataHoraBR } from './formato';
import { PresencaMiami } from './PresencaMiami';
import { ResumoRelatorioMiami } from './ResumoRelatorioMiami';
import { TabelaRelatorioMiami } from './TabelaRelatorioMiami';

export type SecaoRelatorioMiami = 'relatorio' | 'diamantes' | 'compradores' | 'presenca';
/** Abas que leem a cópia da planilha. A ordem e os nomes são os do pedido do Victor (card 17tya50h3b8). */
export const abasRelatorioMiami: { k: SecaoRelatorioMiami; l: string }[] = [
  { k: 'relatorio', l: 'Relatório' }, { k: 'diamantes', l: 'Diamantes' }, { k: 'compradores', l: 'Compradores' }, { k: 'presenca', l: 'Presença por evento' },
];
export const ehSecaoRelatorioMiami = (aba: string): aba is SecaoRelatorioMiami => abasRelatorioMiami.some((a) => a.k === aba);

// Cabeçalhos exatos do contrato (§2.12.1). Colunas fora da lista continuam no detalhe da linha e em "Todas as colunas".
const DIAMANTES_PADRAO = ['Nome (Lista Diamantes)', 'Status', 'Grupo', 'Situação para os eventos nos EUA', 'Chegada em Miami', 'Retorno', 'Aeroporto', 'Hospedagem', 'Acompanhado(a)', 'Enviado em'];
const DIAMANTES_GRAFICOS = ['Status', 'Grupo', 'Situação para os eventos nos EUA', 'Aeroporto', 'Hospedagem', 'Acompanhado(a)'];
const COMPRADORES_PADRAO = ['Nome (compra)', 'Instrução (Central)', 'Turma (Central)', 'Formulário', 'Chegada', 'Saída', 'Aeroporto', 'Acompanhantes na viagem', 'Hospedagem'];
const COMPRADORES_GRAFICOS = ['Instrução (Central)', 'Turma (Central)', 'Formulário', 'Espaço de instrução (formulário)', 'Aeroporto', 'Hospedagem'];

function useAgora(passoMs = 30_000): number {
  const [agora, setAgora] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setAgora(Date.now()), passoMs);
    return () => clearInterval(t);
  }, [passoMs]);
  return agora;
}

const faixa = 'rounded-[var(--r-md)] border px-3 py-2 text-xs';

function FaixaStatus({ estado, conteudo, agora }: { estado: EstadoRelatorioMiami; conteudo: ConteudoRelatorioMiami; agora: number }) {
  const idade = idadeCurta(estado.lidoEm, agora);
  return <div className="space-y-2">
    <p className="text-xs text-[var(--fg-2)]" role="status">
      Cópia da aba “{conteudo.aba}” da planilha{estado.lidoEm ? <> · lida em {dataHoraBR(estado.lidoEm)}{idade ? ` (${idade})` : ''}</> : null}
    </p>
    {estado.erroLeitor && <p role="status" className={`${faixa} border-[var(--yellow-border)] bg-[var(--yellow-subtle)] text-[var(--fg)]`}>
      A última leitura da planilha falhou (código: {estado.erroLeitor}). Exibindo a cópia{estado.lidoEm ? ` de ${dataHoraBR(estado.lidoEm)}` : ' anterior'}.
    </p>}
    {estado.erroTela && <p role="status" className={`${faixa} border-[var(--yellow-border)] bg-[var(--yellow-subtle)] text-[var(--fg)]`}>
      {estado.erroTela} Exibindo a última cópia carregada.
    </p>}
    {conteudo.avisos.map((aviso) => <p key={aviso.codigo} role="status" className={`${faixa} border-[var(--info-border)] bg-[var(--info-subtle)] text-[var(--fg)]`}>{aviso.texto}</p>)}
  </div>;
}

export function AbaRelatorioMiami({ secao, estado }: { secao: SecaoRelatorioMiami; estado: EstadoRelatorioMiami }) {
  const agora = useAgora();
  const c = estado.conteudo;
  if (!c) {
    if (estado.carregando) return <div className="pt-4"><Loading label="Carregando o relatório da planilha…" minHeight={160} /></div>;
    if (estado.semCopia) return <div className="pt-4"><EmptyState title="O relatório da planilha ainda não está no banco" hint={estado.erroLeitor ? `A leitura da planilha falhou (código: ${estado.erroLeitor}).` : 'Quando a primeira leitura da planilha der certo, ele aparece aqui.'} /></div>;
    return <p role="alert" className="pt-4 text-sm text-[var(--fg-2)]">{estado.erroTela ?? 'Não foi possível carregar agora.'}</p>;
  }
  const defasada = !!estado.erroLeitor || !!estado.erroTela;
  const b = c.blocos;
  return <div className="space-y-5 pt-4">
    <FaixaStatus estado={estado} conteudo={c} agora={agora} />
    <div className={`space-y-5 transition-opacity ${defasada ? 'opacity-70' : ''}`}>
      {secao === 'relatorio' && <ResumoRelatorioMiami blocos={[b.dados_iniciais, b.time_formulario, b.participacao]} />}
      {secao === 'diamantes' && <section className="space-y-3" aria-label={b.diamantes.titulo}>
        <h2 className="text-lg font-semibold text-[var(--fg)]">{b.diamantes.titulo}</h2>
        <TabelaRelatorioMiami key="diamantes" bloco={b.diamantes} colunasPadrao={DIAMANTES_PADRAO} graficos={DIAMANTES_GRAFICOS} contatoVisivel={estado.contatoVisivel} />
      </section>}
      {secao === 'compradores' && <section className="space-y-3" aria-label={b.compradores.titulo}>
        <h2 className="text-lg font-semibold text-[var(--fg)]">{b.compradores.titulo}</h2>
        <TabelaRelatorioMiami key="compradores" bloco={b.compradores} colunasPadrao={COMPRADORES_PADRAO} graficos={COMPRADORES_GRAFICOS} contatoVisivel={estado.contatoVisivel} />
      </section>}
      {secao === 'presenca' && <PresencaMiami presenca={b.presenca} camisas={b.camisas} />}
    </div>
  </div>;
}
