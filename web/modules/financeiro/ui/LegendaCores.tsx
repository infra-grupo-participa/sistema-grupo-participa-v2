'use client';

// Dicionário de cor do board — não resumo do recorte. As 4 cores aparecem
// sempre, mesmo se o filtro ativo só tiver 2; senão a legenda ensinaria
// errado ("essa cor não existe" quando na verdade só não está no recorte).
// A 5ª entrada (neutro) só aparece quando existe card `neutro` NO BOARD
// inteiro — ela não é uma 5ª cor de negócio, é o alarme de status
// desconhecido vindo do banco (drift schema↔front), então só deve existir
// na tela quando o alarme está de fato aceso.
//
// Renderizada com o MESMO Badge da ficha (FichaDrawer) — a legenda não pode
// divergir por construção, porque não decide cor: importa de ui/cor.ts.
import { Badge } from '@/shared/ui/components';
import { ROTULO_COR, type CorStatus } from '../domain/cor-status';
import { TONE_BADGE } from './cor';

const CORES_BASE: CorStatus[] = ['verde', 'azul', 'amarelo', 'vermelho'];

export function LegendaCores({ existeNeutro }: { existeNeutro: boolean }) {
  const cores = existeNeutro ? [...CORES_BASE, 'neutro' as CorStatus] : CORES_BASE;
  return (
    <div className="mb-3 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[11px] text-[var(--fg-3)]">
      {cores.map((c) => (
        <Badge key={c} tone={TONE_BADGE[c]}>{ROTULO_COR[c]}</Badge>
      ))}
      <span className="text-[var(--fg-4)]">
        Card com brilho e borda = precisa de ação. Vermelho apagado = encerrado, não perseguir.
      </span>
    </div>
  );
}
