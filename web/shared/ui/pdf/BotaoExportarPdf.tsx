'use client';

// "Exportar PDF" + seletor de nível de dado pessoal (quando o relatório aceita mais de um).
// Trava enquanto gera: duplo clique = dois protocolos consumidos à toa. A trava é um ref
// (síncrono) além do estado — o estado só re-renderiza depois do 2º clique já ter entrado.
//
// Nenhuma lib de PDF é importada aqui: gerar-pdf.ts carrega @react-pdf no clique, num
// Web Worker. Enquanto desenha, a linha ao lado do botão mostra a etapa e a folha
// ("Montando folha 120 de 660 · 34 s") — a tela segue respondendo.
//
// Lista acima de LINHAS_MAX_NO_PDF: o 1º clique só avisa ("Esta lista tem N linhas…") e o
// botão vira "Gerar PDF com os totais"; o 2º clique gera. Sem modal: uma linha de texto.
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { NivelPii, RascunhoRelatorio } from './modelo';
import { ROTULO_NIVEL } from './modelo';
import { NIVEIS_PII, contarLinhasDetalhe, excedeLimiteDoPdf } from './nivel';
import type { ChamadasProtocolo, ProgressoPdf } from './gerar-pdf';

export function textoProgresso(p: ProgressoPdf): string {
  switch (p.etapa) {
    case 'preparando': return 'Carregando o gerador de PDF…';
    case 'emitindo': return 'Emitindo protocolo…';
    case 'montando': return `Montando folha ${p.folha.toLocaleString('pt-BR')} de ${p.folhas.toLocaleString('pt-BR')}`;
    case 'numerando': return `Numerando folhas · ${Math.floor((100 * p.feito) / Math.max(p.total, 1))}%`;
    case 'gravando': return `Gravando ${p.folhas.toLocaleString('pt-BR')} folhas…`;
    case 'selando': return 'Selando protocolo…';
  }
}

export function BotaoExportarPdf({
  montar, niveis, chamadas, desabilitado, rotulo = 'Exportar PDF',
}: {
  /** Monta o rascunho da lista JÁ FILTRADA da tela — chamado só no clique. */
  montar: () => RascunhoRelatorio;
  /** Níveis aceitos pelo relatório. Um só (ex.: "Mesma pessoa?") = sem seletor. */
  niveis: NivelPii[];
  /** null = protocolo ainda não ligado ao banco: botão travado, nunca gera sem protocolo. */
  chamadas: ChamadasProtocolo | null;
  desabilitado?: boolean;
  /** Texto do botão em repouso. Padrão "Exportar PDF". */
  rotulo?: string;
}) {
  const oferecidos = NIVEIS_PII.filter((n) => niveis.includes(n));
  const [nivel, setNivel] = useState<NivelPii>(oferecidos[0] ?? 'completo');
  const [gerando, setGerando] = useState(false);
  const [aviso, setAviso] = useState<{ ok: boolean; texto: string } | null>(null);
  const [progresso, setProgresso] = useState<ProgressoPdf | null>(null);
  const [segundos, setSegundos] = useState(0);
  /** Linhas da lista já avisadas acima do limite; o próximo clique com a mesma contagem gera. */
  const [avisadas, setAvisadas] = useState<{ linhas: number; temPlanilha: boolean } | null>(null);
  const trava = useRef(false);

  // Relógio da geração: mostra que a tela está viva mesmo na etapa sem contagem de folha.
  useEffect(() => {
    if (!gerando) return;
    const inicio = Date.now();
    const id = setInterval(() => setSegundos(Math.floor((Date.now() - inicio) / 1000)), 1000);
    return () => clearInterval(id);
  }, [gerando]);

  const exportar = async () => {
    if (trava.current || !chamadas) return;
    const rascunho = montar();
    const linhas = contarLinhasDetalhe(rascunho);
    if (excedeLimiteDoPdf(linhas, nivel) && avisadas?.linhas !== linhas) {
      setAviso(null);
      setAvisadas({ linhas, temPlanilha: !!rascunho.temPlanilha });
      return;
    }
    setAvisadas(null);
    trava.current = true;
    setGerando(true);
    setSegundos(0);
    setAviso(null);
    try {
      const { gerarPdfComProtocolo } = await import('./gerar-pdf');
      const { protocolo } = await gerarPdfComProtocolo(rascunho, nivel, chamadas, setProgresso);
      setAviso({ ok: true, texto: `PDF emitido · Protocolo ${protocolo}` });
    } catch (e) {
      setAviso({ ok: false, texto: e instanceof Error ? e.message : 'Não foi possível gerar o PDF.' });
    } finally {
      trava.current = false;
      setGerando(false);
      setProgresso(null);
    }
  };

  return (
    <span className="inline-flex flex-wrap items-center gap-2">
      {oferecidos.length > 1 && (
        <select
          aria-label="Dados pessoais no PDF" value={nivel} disabled={gerando}
          onChange={(e) => { setNivel(e.target.value as NivelPii); setAvisadas(null); }}
          className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface)] px-2 py-1.5 text-xs text-[var(--fg-2)]"
        >
          {oferecidos.map((n) => <option key={n} value={n}>{ROTULO_NIVEL[n]}</option>)}
        </select>
      )}
      <Button
        variant="ghost" size="sm" onClick={exportar}
        disabled={gerando || desabilitado || !chamadas}
        aria-busy={gerando}
        title={!chamadas ? 'Protocolo de emissão ainda não ligado ao banco.' : undefined}
      >
        <Icon name="file" size={14} /> {gerando ? 'Gerando PDF…' : avisadas ? 'Gerar PDF com os totais' : rotulo}
      </Button>
      {avisadas && !gerando && (
        <span role="status" className="text-xs text-[var(--fg-2)]">
          Esta lista tem {avisadas.linhas.toLocaleString('pt-BR')} linhas. O PDF trará os totais; para a lista completa,
          {avisadas.temPlanilha ? ' filtre ou use a planilha.' : ' filtre a lista.'}
        </span>
      )}
      {gerando && progresso && (
        <span className="text-xs tabular-nums text-[var(--fg-3)]">{textoProgresso(progresso)}{segundos ? ` · ${segundos} s` : ''}</span>
      )}
      {aviso && (
        <span role="status" className={`text-xs ${aviso.ok ? 'text-[var(--fg-3)]' : 'text-[var(--red)]'}`}>{aviso.texto}</span>
      )}
    </span>
  );
}
