'use client';

// Resumo do dia ("o que está pegando fogo"), no topo da Central do Tráfego. Lê public.trafego_alertas (migration
// 20261005r). Os limiares vêm da tabela mkt_trafego.alerta_regras; a tela só mostra.
import { useEffect, useState } from 'react';
import { Badge, SectionCard } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { textoAlerta, textoRegra } from '../domain/alertas';
import type { ColetaInfo, ResumoDia as Resumo } from '../domain/tipos';
import { carregarAlertas } from '../infrastructure/trafego-data';
import { dataBR } from './formato';

const ROTULO_FONTE: Record<string, string> = { meta: 'Meta Ads', clickup: 'ClickUp', google: 'Google Ads' };

function quando(c: ColetaInfo | undefined): string {
  if (!c) return 'desligada (nunca rodou)';
  const d = new Date(c.em);
  const h = d.toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
  return c.ok ? `última ${h}` : `falhou em ${h}${c.erro ? ` (${c.erro})` : ''}`;
}

export function ResumoDia({ versao, onAbrir }: { versao: number; onAbrir: (id: number) => void }) {
  const [r, setR] = useState<Resumo | null | undefined>(undefined);

  useEffect(() => {
    let vivo = true;
    carregarAlertas().then((x) => { if (vivo) setR(x); });
    return () => { vivo = false; };
  }, [versao]);

  if (r === undefined) return null;
  return <ResumoDiaVista r={r} onAbrir={onAbrir} />;
}

/** O bloco em si (sem carregar), para testar a renderização. */
export function ResumoDiaVista({ r, onAbrir }: { r: Resumo | null; onAbrir: (id: number) => void }) {
  const [regras, setRegras] = useState(false);
  if (r === null) {
    return (
      <SectionCard title="Resumo do dia">
        <p className="text-sm text-[var(--fg-3)]">Indisponível (sem acesso, ou a migration 20261005r ainda não foi aplicada).</p>
      </SectionCard>
    );
  }

  const altas = r.alertas.filter((a) => a.gravidade === 'alta').length;
  return (
    <SectionCard
      title={<span className="inline-flex items-center gap-2"><Icon name="alert" size={16} /> Resumo do dia: o que está pegando fogo</span>}
      subtitle={`Sobre ontem (${dataBR(r.dia)}), ${r.projetos_avaliados} projeto(s) avaliado(s). Projetos desativados, em planejamento, inativos ou encerrados ficam fora.`}
      right={<div className="flex gap-2">
        {altas > 0 && <Badge tone="danger">{altas} alta(s)</Badge>}
        {r.alertas.length - altas > 0 && <Badge tone="warning">{r.alertas.length - altas} média(s)</Badge>}
      </div>}
    >
      {r.alertas.length === 0 ? (
        <p className="text-sm text-[var(--fg-2)]">Nada pegando fogo ontem pelas regras ligadas.</p>
      ) : (
        <ul className="divide-y divide-[var(--border)]">
          {r.alertas.map((a, i) => (
            <li key={`${a.regra}-${a.projeto_id}-${a.detalhe.fase ?? ''}-${i}`} className="flex flex-wrap items-start gap-x-3 gap-y-1 py-2">
              <Badge tone={a.gravidade === 'alta' ? 'danger' : 'warning'}>{a.nome}</Badge>
              {a.projeto_id != null ? (
                <button type="button" onClick={() => onAbrir(a.projeto_id!)} className="font-mono text-sm font-semibold text-[var(--accent)] hover:underline" title={a.projeto_nome ?? ''}>
                  {a.sigla}
                </button>
              ) : <span className="text-sm text-[var(--fg-3)]">Sem projeto</span>}
              <span className="text-sm text-[var(--fg-2)]">{textoAlerta(a)}</span>
            </li>
          ))}
        </ul>
      )}
      <div className="mt-3 space-y-1 text-xs text-[var(--fg-3)]">
        {r.sem_coleta && <p>Ainda não há gasto coletado: verba diária, ritmo das fases, % da verba e CPL não têm como disparar.</p>}
        {!r.base_pessoas && <p>Sem a base de pessoas (migration 20261005o): meta de leads e CPL não são avaliados.</p>}
        <p>Coletas: {(['meta', 'clickup'] as const).map((f) => `${ROTULO_FONTE[f]} ${quando(r.coletas[f])}`).join(' · ')}.</p>
        <button type="button" className="underline" onClick={() => setRegras((v) => !v)} aria-expanded={regras}>
          {regras ? 'Esconder as regras' : 'Ver as regras e os limiares'}
        </button>
        {regras && (
          <ul className="list-disc pl-5">
            {r.regras.map((g) => <li key={g.codigo}><b>{textoRegra(g)}</b>: {g.descricao}</li>)}
            <li>Os limiares mudam por SQL na tabela mkt_trafego.alerta_regras (admin/dev).</li>
          </ul>
        )}
      </div>
    </SectionCard>
  );
}
