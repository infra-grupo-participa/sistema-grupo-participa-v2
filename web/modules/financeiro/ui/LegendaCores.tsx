'use client';

// Dicionário de cor do board — não resumo do recorte. As 4 cores aparecem
// sempre, mesmo se o filtro ativo só tiver 2; senão a legenda ensinaria
// errado ("essa cor não existe" quando na verdade só não está no recorte).
// A 5ª entrada (neutro) só aparece quando existe card `neutro` NO BOARD
// inteiro — ela não é uma 5ª cor de negócio, é o alarme de status
// desconhecido vindo do banco (drift schema↔front), então só deve existir
// na tela quando o alarme está de fato aceso.
//
// Redesign 2026-08-27 (N2, junto do reforço de cor dos cards): trocado Badge
// (chip neutro, ponto de 6px) por uma amostra que usa os MESMOS .gp-card--*
// (globals.css) do card real — faixa lateral + fundo levemente lavado. A
// legenda que ENSINA o mosaico precisa se PARECER com o mosaico. Continua
// importando só de ui/cor.ts (CLASSE_CARD) — nenhum mapa de cor novo nasce
// aqui, mesma regra que já valia para o Badge.
import { ROTULO_COR, type CorStatus } from '../domain/cor-status';
import { CLASSE_CARD } from './cor';

const CORES_BASE: CorStatus[] = ['verde', 'azul', 'amarelo', 'vermelho'];

export function LegendaCores({ existeNeutro }: { existeNeutro: boolean }) {
  const cores = existeNeutro ? [...CORES_BASE, 'neutro' as CorStatus] : CORES_BASE;
  return (
    <div className="mb-3 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[11px] text-[var(--fg-3)]">
      {cores.map((c) => (
        <span key={c} className="inline-flex items-center gap-1.5">
          <span
            className={`gp-card ${CLASSE_CARD[c]} gp-card--u0 inline-block h-3.5 w-5 shrink-0 rounded-[var(--r-sm)]`}
            aria-hidden
          />
          <span>{ROTULO_COR[c]}</span>
        </span>
      ))}
      {/* Ajustada para continuar verdadeira depois do redesign: a faixa
          lateral agora carrega o STATUS (a cor em si), halo/borda/dot
          carregam a URGÊNCIA (o quanto precisa de ação). Antes só existia
          halo+borda; agora a faixa cheia é o próprio sinal de identidade, daí
          "faixa cheia" substituir "brilho e borda" na frase. */}
      <span className="text-[var(--fg-4)]">
        Faixa lateral = status. Halo, borda e dot = precisa de ação. Vermelho com faixa recuada = encerrado, não perseguir.
      </span>
    </div>
  );
}
