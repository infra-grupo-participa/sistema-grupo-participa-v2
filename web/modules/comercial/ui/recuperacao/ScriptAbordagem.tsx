'use client';

// Painel do script de abordagem: variante → mensagem pronta para copiar → roteiro de resposta.
// Regras da 1ª mensagem e cuidados de WhatsApp ficam recolhidos (consulta, não leitura diária).
import { useState } from 'react';
import { Button, SectionCard, SectionTitle } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { SinalRecuperacao } from '../../domain/types';
import { Chip } from '../comum';
import {
  CUIDADOS_WHATSAPP, montarMensagem, REGRAS_PRIMEIRA_MENSAGEM, ROTEIRO_RESPOSTAS, VARIANTES, varianteDoSinal, type VarianteKey,
} from './script';

export function ScriptAbordagem({ lead, vendedor, evento, ofertaVigente, onFechar }: {
  lead: { id: string; nome: string; sinais: SinalRecuperacao[] } | null;
  vendedor: string;
  evento: string;
  ofertaVigente: string | null;
  onFechar: () => void;
}) {
  const sugerida = lead ? varianteDoSinal(lead.sinais) : 'base';
  // Escolha manual vale só para o lead em que foi feita; trocou de lead, volta para a sugerida.
  const [escolha, setEscolha] = useState<{ lead: string | null; v: VarianteKey } | null>(null);
  const variante = escolha && escolha.lead === (lead?.id ?? null) ? escolha.v : sugerida;
  const [copiado, setCopiado] = useState(false);
  const texto = montarMensagem(variante, lead?.nome ?? '{Nome}', vendedor, evento);
  const nota = VARIANTES.find((v) => v.key === variante)?.nota;

  async function copiar() {
    try {
      await navigator.clipboard.writeText(texto);
      setCopiado(true);
      setTimeout(() => setCopiado(false), 2000);
    } catch { /* clipboard indisponível: o texto continua selecionável */ }
  }

  return (
    <SectionCard
      title={<span className="inline-flex items-center gap-2"><Icon name="message" size={15} className="text-[var(--fg-3)]" /> Script de abordagem</span>}
      subtitle={lead ? `Para ${lead.nome}` : 'Use "Script" numa linha da fila para preencher o nome.'}
      right={
        <button
          type="button"
          onClick={onFechar}
          aria-label="Fechar script"
          className="w-8 h-8 shrink-0 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)] transition-colors"
        >
          <Icon name="x" size={14} />
        </button>
      }
    >
      <div className="space-y-5 text-sm">
        <section>
          <SectionTitle>Variante</SectionTitle>
          <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Variante por sinal">
            {VARIANTES.map((v) => (
              <Chip key={v.key} ativo={variante === v.key} onClick={() => setEscolha({ lead: lead?.id ?? null, v: v.key })}>
                {v.rotulo}{v.key === sugerida && lead ? ' · sugerida' : ''}
              </Chip>
            ))}
          </div>
        </section>

        <section>
          <SectionTitle>Mensagem</SectionTitle>
          <pre className="whitespace-pre-wrap break-words rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3 font-sans text-[13px] leading-relaxed text-[var(--fg)] select-all">{texto}</pre>
          {nota && (
            <p className="mt-2 flex items-start gap-1.5 text-xs text-[var(--fg-2)]">
              <Icon name="alert" size={13} className="mt-0.5 shrink-0 text-[var(--yellow)]" />{nota}
            </p>
          )}
          <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
            <span className="text-[11px] text-[var(--fg-3)]">Troca só o segundo parágrafo; o resto fica igual.</span>
            <Button size="sm" onClick={copiar}>
              <Icon name={copiado ? 'check' : 'copy'} size={13} /> {copiado ? 'Copiado!' : 'Copiar mensagem'}
            </Button>
          </div>
          <span className="sr-only" aria-live="polite">{copiado ? 'Mensagem copiada.' : ''}</span>
        </section>

        <section>
          <SectionTitle>Quando a pessoa responder</SectionTitle>
          {ofertaVigente && (
            <p className="mb-2 text-xs text-[var(--fg-2)]">
              <span className="text-[var(--fg-3)]">Oferta vigente:</span> <span className="font-medium text-[var(--fg)]">{ofertaVigente}</span>
            </p>
          )}
          <dl className="divide-y divide-[var(--border-faint)]">
            {ROTEIRO_RESPOSTAS.map((r) => (
              <div key={r.gatilho} className="py-2 first:pt-0">
                <dt className="text-xs font-semibold text-[var(--fg)]">{r.gatilho}</dt>
                <dd className="mt-0.5 text-[13px] text-[var(--fg-2)]">{r.resposta}</dd>
                {r.nota && <dd className="mt-0.5 text-[11px] text-[var(--fg-3)]">{r.nota}</dd>}
              </div>
            ))}
          </dl>
        </section>

        <div className="space-y-1 border-t border-[var(--border-faint)] pt-3">
          <Recolhido titulo="Regras da primeira mensagem">
            <ul className="space-y-1.5">
              {REGRAS_PRIMEIRA_MENSAGEM.map((r) => (
                <li key={r.titulo} className="flex gap-2 text-[13px]">
                  <Icon name="check" size={13} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
                  <span><strong className="font-medium text-[var(--fg)]">{r.titulo}.</strong> <span className="text-[var(--fg-2)]">{r.texto}</span></span>
                </li>
              ))}
            </ul>
          </Recolhido>
          <Recolhido titulo="Cuidados de WhatsApp">
            <ul className="space-y-1 text-[13px] text-[var(--fg-2)]">
              {CUIDADOS_WHATSAPP.map((c) => (
                <li key={c} className="flex gap-2"><Icon name="alert" size={13} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />{c}</li>
              ))}
            </ul>
          </Recolhido>
        </div>
      </div>
    </SectionCard>
  );
}

function Recolhido({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <details className="group">
      <summary className="flex min-h-8 cursor-pointer list-none items-center gap-1.5 rounded-[var(--r-sm)] text-xs font-medium text-[var(--fg-2)] hover:text-[var(--fg)] [&::-webkit-details-marker]:hidden">
        <Icon name="chevron-right" size={13} className="text-[var(--fg-3)] transition-transform group-open:rotate-90" />
        {titulo}
      </summary>
      <div className="pb-2 pl-5 pt-1">{children}</div>
    </details>
  );
}
