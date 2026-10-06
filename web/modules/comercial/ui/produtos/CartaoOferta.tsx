'use client';

// Cartão de uma oferta da Hotmart: o que veio da sincronização (código, preço, modo, link) só para ler;
// o que é do comercial (vigente, condição, validade, uso) o gestor edita aqui.
import { useState } from 'react';
import { Badge, Button, Input, Toggle } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData, fmtRelativo } from '@/shared/ui/format';
import type { OfertaHotmart } from '../../domain/types';
import { BotaoCopiar, Campo } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { avisarMudanca, repo } from '../repositorio';
import { INFO_TRANSACOES } from './textos';
import { ofertaAlterada, ofertaVencida, paraSalvar, rascunhoOferta, rotuloModo, validarOferta } from './produtos';

const BTN_ICONE = 'inline-grid place-items-center w-8 h-8 rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors';

/** Abre o checkout da Hotmart em outra aba. */
export function BotaoAbrirLink({ href }: { href: string }) {
  return (
    <a href={href} target="_blank" rel="noopener noreferrer" className={BTN_ICONE} aria-label="Abrir checkout na Hotmart" title="Abrir checkout na Hotmart">
      <Icon name="arrow-up-right" size={14} />
    </a>
  );
}

export function CartaoOferta({ oferta: o, produtoNoComercial, gestor, hojeISO, destaque, flash }: {
  oferta: OfertaHotmart; produtoNoComercial: boolean; gestor: boolean; hojeISO: string; destaque: boolean; flash: (m: string) => void;
}) {
  const [r, setR] = useState(() => rascunhoOferta(o));
  const [salvando, setSalvando] = useState(false);
  const [tentou, setTentou] = useState(false);
  const alterada = ofertaAlterada(r, o);
  const erro = validarOferta(r, produtoNoComercial, hojeISO);
  const vencida = ofertaVencida(o, hojeISO);
  const valendo = o.vigente && produtoNoComercial && !vencida;
  const ultima = fmtRelativo(o.ultimaVendaEm);

  async function salvar() {
    setTentou(true);
    if (erro) return;
    setSalvando(true);
    const res = await repo.salvarOferta(paraSalvar(r));
    setSalvando(false);
    if (res.ok) { flash(res.msg ?? 'Oferta salva.'); setTentou(false); avisarMudanca(); } else flash(res.msg ?? 'Não foi possível salvar.');
  }

  const borda = destaque ? 'border-[var(--border-accent)]' : valendo ? 'border-[var(--green-border)]' : 'border-[var(--border)]';

  return (
    <li id={`oferta-${o.codigo}`} className={`rounded-[var(--r-lg)] border bg-[var(--surface-2)] p-3 ${borda}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="flex flex-wrap items-center gap-1.5">
            <code className="text-sm font-semibold text-[var(--fg)] tabular break-all">{o.codigo}</code>
            {valendo && <Badge tone="success">Vigente</Badge>}
            {vencida && <Badge tone="danger">Vencida em {fmtData(o.validaAte)}</Badge>}
            {o.principal && <Badge>Principal</Badge>}
            {destaque && <Badge tone="accent">Do link colado</Badge>}
          </div>
          <p className="mt-0.5 text-xs text-[var(--fg-3)] truncate">{o.nomeHotmart ?? 'Sem nome na Hotmart'}</p>
        </div>
        <div className="flex items-center gap-1.5 shrink-0">
          <BotaoCopiar texto={o.codigo} rotulo="Copiar código da oferta" onCopiado={flash} />
          <BotaoCopiar texto={o.linkCheckout} rotulo="Copiar link de checkout" onCopiado={flash} />
          <BotaoAbrirLink href={o.linkCheckout} />
        </div>
      </div>

      <dl className="mt-2 grid grid-cols-2 sm:grid-cols-4 gap-x-3 gap-y-1 text-xs">
        <div><dt className="text-[var(--fg-3)]">Preço</dt><dd className="font-semibold text-[var(--fg)] tabular">{fmtBRL(o.preco)}</dd></div>
        <div><dt className="text-[var(--fg-3)]">Pagamento</dt><dd className="text-[var(--fg-2)]">{rotuloModo(o.modo)}</dd></div>
        <div><dt className="inline-flex items-center gap-0.5 text-[var(--fg-3)]">Transações <InfoIndicador texto={INFO_TRANSACOES} /></dt><dd className="text-[var(--fg-2)] tabular">{o.transacoes.toLocaleString('pt-BR')}</dd></div>
        <div><dt className="text-[var(--fg-3)]">Última venda</dt><dd className="text-[var(--fg-2)]" title={ultima.title}>{o.ultimaVendaEm ? ultima.label : 'nunca'}</dd></div>
      </dl>

      {gestor ? (
        <div className="mt-3 border-t border-[var(--border-faint)] pt-3 space-y-3">
          <div className={`flex flex-wrap items-center justify-between gap-2 rounded-[var(--r-md)] px-2 py-1.5 ${r.vigente ? 'bg-[var(--green-subtle)]' : 'bg-[var(--surface-3)]'}`}>
            <Toggle
              checked={r.vigente}
              onChange={(v) => setR({ ...r, vigente: v })}
              disabled={!produtoNoComercial && !r.vigente}
              label={r.vigente ? 'Vigente: o vendedor pode oferecer' : 'Não vigente: o vendedor não oferece'}
            />
            {!produtoNoComercial && <span className="text-[11px] text-[var(--fg-3)]">Vincule o produto para marcar vigente.</span>}
          </div>
          <div className="grid gap-3 sm:grid-cols-2">
            <Campo rotulo="Condição" extra={r.vigente ? 'obrigatória' : undefined} dica="O que o vendedor fala: parcelas, entrada, desconto." className="sm:col-span-2">
              <Input value={r.condicao} onChange={(e) => setR({ ...r, condicao: e.target.value })} placeholder="Ex.: 12x de R$ 1.461 no cartão" maxLength={200} />
            </Campo>
            <Campo rotulo="Válida até" dica="Vazio = sem data para acabar.">
              <Input type="date" value={r.validaAte} onChange={(e) => setR({ ...r, validaAte: e.target.value })} />
            </Campo>
            <Campo rotulo="Uso" dica="Para que serve esta oferta.">
              <Input value={r.uso} onChange={(e) => setR({ ...r, uso: e.target.value })} placeholder="Ex.: carrinho Imersão SET26" maxLength={120} />
            </Campo>
          </div>
          {tentou && erro && <p role="alert" className="text-xs text-[var(--red)]">{erro}</p>}
          {alterada && (
            <div className="flex justify-end gap-2">
              <Button size="sm" variant="ghost" onClick={() => { setR(rascunhoOferta(o)); setTentou(false); }}>Descartar</Button>
              <Button size="sm" variant="subtle" onClick={salvar} disabled={salvando}>
                <Icon name="check" size={14} /> {salvando ? 'Salvando…' : 'Salvar oferta'}
              </Button>
            </div>
          )}
        </div>
      ) : (
        (o.condicao || o.validaAte || o.uso) && (
          <dl className="mt-3 border-t border-[var(--border-faint)] pt-2 space-y-1 text-xs">
            {o.condicao && <div className="flex gap-2"><dt className="text-[var(--fg-3)] w-20 shrink-0">Condição</dt><dd className="text-[var(--fg)]">{o.condicao}</dd></div>}
            {o.validaAte && <div className="flex gap-2"><dt className="text-[var(--fg-3)] w-20 shrink-0">Válida até</dt><dd className="text-[var(--fg-2)]">{fmtData(o.validaAte)}</dd></div>}
            {o.uso && <div className="flex gap-2"><dt className="text-[var(--fg-3)] w-20 shrink-0">Uso</dt><dd className="text-[var(--fg-2)]">{o.uso}</dd></div>}
          </dl>
        )
      )}
    </li>
  );
}
