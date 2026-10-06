'use client';

// Propriedades do widget selecionado. Cada mudança vai direto para a grade (prévia ao vivo) e para a pilha
// de desfazer; digitar o título conta como um passo só.
import { Button, FilterSelect, Input } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { METRICAS, ROTULO_AGRUPAR, ROTULO_PERIODO, ROTULO_VISUAL } from '../../domain/metricas';
import type { Funil, MetricaKey, PeriodoWidget, Vendedor, VisualWidget } from '../../domain/types';
import { Campo, NotaRodape, Segmentado } from '../comum';
import { FOTOGRAFIA } from '../inicio/metricas-painel';
import { agrupamentosPermitidos, validarWidget, visuaisPermitidos } from '../inicio/painel-edicao';
import { GRUPOS_BIBLIOTECA, type Altura, type Largura, type WidgetDash } from './layout';

const PERIODOS: PeriodoWidget[] = ['hoje', '7d', '30d', 'mes'];

export function PainelPropriedades({ w, funis, vendedores, gestor, onMudar, onFecharPasso, onFechar }: {
  w: WidgetDash | null;
  funis: Funil[];
  vendedores: Vendedor[];
  /** Só o gestor filtra por vendedor; o vendedor sempre vê os próprios números. */
  gestor: boolean;
  /** `chave` agrupa mudanças seguidas num passo só de desfazer. */
  onMudar: (p: Partial<WidgetDash>, chave?: string) => void;
  onFecharPasso: () => void;
  onFechar: () => void;
}) {
  if (!w) {
    return (
      <aside aria-label="Propriedades" className="min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
        <p className="text-sm font-semibold text-[var(--fg)]">Propriedades</p>
        <p className="mt-1 text-xs leading-relaxed text-[var(--fg-3)]">Clique num widget da grade para mudar título, métrica, visual, período e filtros.</p>
        <ul className="mt-3 space-y-1.5 text-[11px] leading-relaxed text-[var(--fg-3)]">
          <li><span className="font-semibold text-[var(--fg-2)]">Arrastar</span>: reordena; a barra mostra onde cai.</li>
          <li><span className="font-semibold text-[var(--fg-2)]">Borda direita</span>: puxe para mudar a largura.</li>
          <li><span className="font-semibold text-[var(--fg-2)]">Teclado</span>: com o widget em foco, setas movem, Enter edita, Delete remove.</li>
          <li><span className="font-semibold text-[var(--fg-2)]">Ctrl+Z / Ctrl+Shift+Z</span>: desfazer e refazer.</li>
        </ul>
      </aside>
    );
  }

  const def = METRICAS[w.metrica];
  const erro = validarWidget(w);
  const fotografia = FOTOGRAFIA.has(w.metrica);
  const agrupamentos = agrupamentosPermitidos(w.metrica, w.visual);
  const id = (s: string) => `${s}:${w.id}`;

  return (
    <aside aria-label={`Propriedades de ${w.titulo || 'widget'}`} className="min-w-0 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 space-y-3">
      <div className="flex items-center justify-between gap-2">
        <p className="text-sm font-semibold text-[var(--fg)]">Propriedades</p>
        <button type="button" onClick={onFechar} aria-label="Fechar propriedades"
          className="grid place-items-center w-7 h-7 rounded-[var(--r-sm)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
          <Icon name="x" size={14} />
        </button>
      </div>

      <Campo rotulo="Título" dica={erro ? <span className="text-[var(--red)]">{erro}</span> : undefined}>
        <Input value={w.titulo} maxLength={60} placeholder={def.nome} onBlur={onFecharPasso}
          onChange={(e) => onMudar({ titulo: e.target.value }, id('titulo'))} />
      </Campo>

      <Campo rotulo="Métrica">
        <FilterSelect value={w.metrica} onChange={(e) => {
          const m = e.target.value as MetricaKey;
          // Título ainda era o nome da métrica antiga: acompanha a nova.
          onMudar({ metrica: m, ...(w.titulo.trim() === def.nome || !w.titulo.trim() ? { titulo: METRICAS[m].nome } : {}) });
        }}>
          {GRUPOS_BIBLIOTECA.map((g) => (
            <optgroup key={g.key} label={g.rotulo}>
              {g.metricas.map((k) => <option key={k} value={k}>{METRICAS[k].nome}</option>)}
            </optgroup>
          ))}
        </FilterSelect>
      </Campo>
      <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3 text-xs leading-relaxed">
        <p className="text-[var(--fg-2)]">{def.oQueE}</p>
        <p className="mt-1.5 text-[var(--fg-3)]"><span className="font-semibold text-[var(--fg-2)]">Como conta: </span>{def.comoConta}</p>
        {def.meta && <p className="mt-1.5 text-[var(--fg-3)]"><span className="font-semibold text-[var(--fg-2)]">Meta: </span>{def.meta}</p>}
      </div>

      <Campo rotulo="Visual">
        <Segmentado<VisualWidget>
          rotulo="Visual do widget" valor={w.visual} onChange={(v) => onMudar({ visual: v })} className="flex-wrap"
          opcoes={visuaisPermitidos(w.metrica).map((v) => ({ valor: v, rotulo: ROTULO_VISUAL[v] }))}
        />
      </Campo>

      <Campo rotulo="Período" dica={fotografia ? 'Fotografia do momento: o período não muda este número.' : 'Comparado com o período anterior de mesmo tamanho.'}>
        <Segmentado<PeriodoWidget>
          rotulo="Período" valor={w.periodo} onChange={(v) => onMudar({ periodo: v })} className="flex-wrap"
          opcoes={PERIODOS.map((p) => ({ valor: p, rotulo: ROTULO_PERIODO[p] }))}
        />
      </Campo>

      <Campo rotulo="Agrupar" dica={agrupamentos.length <= 1 ? 'Este visual mostra um número só.' : undefined}>
        <FilterSelect value={w.agrupar} disabled={agrupamentos.length <= 1}
          onChange={(e) => onMudar({ agrupar: e.target.value as WidgetDash['agrupar'] })}>
          {agrupamentos.map((a) => <option key={a} value={a}>{ROTULO_AGRUPAR[a]}</option>)}
        </FilterSelect>
      </Campo>

      <Campo rotulo="Funil" extra={<span className="text-[var(--fg-3)]">opcional</span>}>
        <FilterSelect value={w.funilId ?? ''} onChange={(e) => onMudar({ funilId: e.target.value || null })}>
          <option value="">Todos os funis</option>
          {funis.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
        </FilterSelect>
      </Campo>

      <Campo rotulo="Vendedor" extra={<span className="text-[var(--fg-3)]">opcional</span>}
        dica={gestor ? undefined : 'Você vê sempre os seus números; o filtro vale para o gestor.'}>
        <FilterSelect value={w.vendedorId ?? ''} disabled={!gestor} onChange={(e) => onMudar({ vendedorId: e.target.value || null })}>
          <option value="">Time inteiro</option>
          {vendedores.filter((v) => v.ativo || v.id === w.vendedorId).map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
        </FilterSelect>
      </Campo>

      <div className="grid grid-cols-1 gap-3">
        <Campo rotulo="Largura">
          <Segmentado<'1' | '2' | '3' | '4'>
            rotulo="Largura em quartos da linha" valor={String(w.largura) as '1'}
            onChange={(v) => onMudar({ largura: Number(v) as Largura })}
            opcoes={(['1', '2', '3', '4'] as const).map((l) => ({ valor: l, rotulo: `${l}/4`, title: `${l} de 4 quartos da linha` }))}
          />
        </Campo>
        <Campo rotulo="Altura">
          <Segmentado<Altura>
            rotulo="Altura do widget" valor={w.altura ?? 'normal'} onChange={(v) => onMudar({ altura: v })}
            opcoes={[{ valor: 'normal', rotulo: 'Normal' }, { valor: 'alta', rotulo: 'Alta' }]}
          />
        </Campo>
      </div>

      <NotaRodape>A grade ao lado já mostra o resultado com os dados de agora.</NotaRodape>
      <Button size="sm" variant="ghost" className="w-full" onClick={onFechar}>Pronto</Button>
    </aside>
  );
}
