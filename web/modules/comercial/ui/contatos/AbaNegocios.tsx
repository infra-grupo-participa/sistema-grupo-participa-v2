'use client';

// Aba "Negócios" da ficha: TODOS os negócios da pessoa (abertos e encerrados), em cartões. Clique abre a ficha do negócio.
import { Badge, SectionTitle } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { rotuloMotivo } from '../../domain/catalogo';
import type { Funil, MotivoPerdaConfig, Negocio } from '../../domain/types';
import { ProdutoTag, SlaTag, Vazio } from '../comum';
import { ordenarNegocios } from './ficha-contato';

export function AbaNegocios({ negocios, funis, motivos, agora, nomeDe, onAbrir, acaoVazio }: {
  negocios: Negocio[];
  funis: Funil[];
  motivos: MotivoPerdaConfig[];
  agora: Date;
  nomeDe: (id: string | null) => string;
  onAbrir: (id: string) => void;
  /** Botão "Novo negócio" do estado vazio (some quando a pessoa não pode receber negócio). */
  acaoVazio?: React.ReactNode;
}) {
  if (!negocios.length) {
    return (
      <Vazio
        titulo="Nenhum negócio"
        hint="Se não está no CRM, não existe: abra um negócio antes de conversar."
        icone="briefcase"
        acao={acaoVazio}
      />
    );
  }
  const ordenados = ordenarNegocios(negocios);
  const abertos = ordenados.filter((n) => n.status === 'aberto');
  const encerrados = ordenados.filter((n) => n.status !== 'aberto');
  const nomeFunil = (id: string) => funis.find((f) => f.id === id)?.nome ?? 'Funil arquivado';
  const item = (n: Negocio) => (
    <CartaoNegocio key={n.id} n={n} funil={nomeFunil(n.funilId)} motivos={motivos} agora={agora} nomeDe={nomeDe} onAbrir={() => onAbrir(n.id)} />
  );

  return (
    <div className="space-y-5">
      {abertos.length > 0 && (
        <section>
          <SectionTitle right={<span className="text-[11px] text-[var(--fg-3)] tabular">{abertos.length}</span>}>Abertos</SectionTitle>
          <ul className="space-y-2">{abertos.map(item)}</ul>
        </section>
      )}
      {encerrados.length > 0 && (
        <section>
          <SectionTitle right={<span className="text-[11px] text-[var(--fg-3)] tabular">{encerrados.length}</span>}>Encerrados</SectionTitle>
          <ul className="space-y-2">{encerrados.map(item)}</ul>
        </section>
      )}
    </div>
  );
}

function CartaoNegocio({ n, funil, motivos, agora, nomeDe, onAbrir }: {
  n: Negocio; funil: string; motivos: MotivoPerdaConfig[]; agora: Date; nomeDe: (id: string | null) => string; onAbrir: () => void;
}) {
  const datas = [`Criado ${fmtData(n.criadoEm)}`, n.fechadoEm ? `${n.status === 'ganho' ? 'Ganho' : 'Encerrado'} ${fmtData(n.fechadoEm)}` : null]
    .filter(Boolean).join(' · ');
  return (
    <li>
      <button
        type="button"
        onClick={onAbrir}
        className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2.5 text-left transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]"
      >
        <div className="flex items-start justify-between gap-3">
          <span className="flex min-w-0 flex-wrap items-center gap-1.5">
            <ProdutoTag k={n.produto} />
            <span className="truncate text-sm text-[var(--fg)]">{funil}</span>
            {n.status === 'aberto' && <SlaTag n={n} agora={agora} />}
            {n.status === 'ganho' && <Badge tone="success">Ganho</Badge>}
            {n.status === 'perdido' && <Badge tone="neutral">Perdido</Badge>}
          </span>
          <span className="shrink-0 text-sm font-semibold tabular text-[var(--fg)]">{fmtBRL(n.valor)}</span>
        </div>
        <div className="mt-1 truncate text-xs text-[var(--fg-2)]">
          {n.etapaNome} · {nomeDe(n.donoId)}
        </div>
        <div className="mt-0.5 truncate text-xs text-[var(--fg-3)] tabular">
          {datas}
          {n.status === 'perdido' && n.motivoPerda && ` · Motivo: ${rotuloMotivo(n.motivoPerda, motivos)}`}
        </div>
      </button>
    </li>
  );
}
