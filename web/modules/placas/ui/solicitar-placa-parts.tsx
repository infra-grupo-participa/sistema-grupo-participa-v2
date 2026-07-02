'use client';

// Componentes de apresentação (folhas, sem estado do wizard) do formulário público de placa.

import { Button, Timeline, type TimelineEntry } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { getClientTrackingState, CLIENT_TRACKING_STEPS } from '../domain/client-tracking';

export function Wrap({ children }: { children: React.ReactNode }) {
  return (
    <div className="sp-wrap">
      <div className="sp-brand">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className="sp-brand-mark" src="/images/TimeHoldingBrasil.svg" alt="Time Holding Brasil" />
        <div className="sp-brand-sub">Solicitação de Placa — Time Holding Brasil</div>
      </div>
      {children}
    </div>
  );
}

export function Section({ title, subtitle, children }: { title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <>
      <div className="sp-card-head"><h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</div>
      <div className="sp-card-body">{children}</div>
    </>
  );
}

export function Field({ label, req, children }: { label: string; req?: boolean; children: React.ReactNode }) {
  return <div className="sp-field"><label>{label} {req && <span className="req">*</span>}</label>{children}</div>;
}

export function Nav({ onBack, onNext, nextLabel, backLabel = '← Voltar', onlyNext, busy }: { onBack?: () => void; onNext: () => void; nextLabel: string; backLabel?: string; onlyNext?: boolean; busy?: boolean }) {
  return (
    <div className="sp-nav">
      {!onlyNext && onBack ? <Button type="button" variant="ghost" onClick={onBack}>{backLabel}</Button> : <span />}
      <Button type="button" variant="primary" onClick={onNext} disabled={busy}>{busy ? 'Aguarde…' : nextLabel}</Button>
    </div>
  );
}

export function SuccessCard({ kind }: { kind: 'success' | 'cadastro' }) {
  const isCad = kind === 'cadastro';
  return (
    <div className="sp-card">
      <div className="sp-card-body sp-success">
        <div className="em"><Icon name={isCad ? 'check-circle' : 'party'} size={44} /></div>
        <h1 style={{ fontSize: 22, fontWeight: 800, marginTop: 8 }}>{isCad ? 'Cadastro registrado com sucesso!' : 'Recebemos sua solicitação!'}</h1>
        <p style={{ color: 'var(--muted)', marginTop: 8 }}>
          {isCad
            ? 'Registramos seus dados e o seu nível atual. Como este nível ainda não entra no fluxo da placa, nenhuma documentação adicional é necessária agora.'
            : 'Recebemos seus dados e vamos seguir com a análise da documentação. O acompanhamento fica resumido aos marcos principais do processo.'}
        </p>
      </div>
    </div>
  );
}

export function TrackingCard({ data }: { data: Record<string, unknown> }) {
  const { activeIndex } = getClientTrackingState(data);
  const rastreio = String(data.codigo_rastreio ?? '');
  const tlItems: TimelineEntry[] = CLIENT_TRACKING_STEPS.map((s, i) => ({
    title: s.title,
    body: s.note,
    tone: i < activeIndex ? 'green' : i === activeIndex ? 'accent' : 'base',
    done: i < activeIndex,
    icon: i < activeIndex ? undefined : String(i + 1),
  }));
  return (
    <div className="sp-card">
      <div className="sp-card-head" style={{ background: 'var(--orange)', color: '#fff' /* hex-ok: contraste branco sobre header âmbar da marca */ }}>
        <h1 style={{ color: '#fff' /* hex-ok: contraste branco sobre header âmbar */ }}>Acompanhe sua solicitação</h1>
        <p style={{ color: 'rgba(255,255,255,.85)' /* hex-ok: contraste branco sobre header âmbar */ }}>Sua solicitação está em andamento</p>
      </div>
      <div className="sp-card-body">
        <Timeline items={tlItems} />
        {rastreio && (
          <div className="sp-info" style={{ marginTop: 16 }}>Código de rastreio: <strong>{rastreio}</strong></div>
        )}
      </div>
    </div>
  );
}
