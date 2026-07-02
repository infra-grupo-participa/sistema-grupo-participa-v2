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

export function Stepper({ step, total, names }: { step: number; total: number; names: string[] }) {
  const inset = 100 / total / 2;
  const pct = total > 1 ? ((step - 1) / (total - 1)) * 100 : 0;
  return (
    <div className="sp-stepper">
      <div className="sp-stepper-track">
        <div className="sp-stepper-line" style={{ left: `${inset}%`, right: `${inset}%` }}>
          <span style={{ width: `${pct}%` }} />
        </div>
        {Array.from({ length: total }, (_, i) => {
          const n = i + 1;
          const state = n < step ? 'done' : n === step ? 'current' : 'todo';
          return (
            <div key={n} className="sp-node" data-state={state}>
              <div className="sp-node-dot">{n < step ? <Icon name="check" size={13} strokeWidth={3} /> : n}</div>
              <div className="sp-node-name">{names[n]}</div>
            </div>
          );
        })}
      </div>
      <div className="sp-stepper-current">Etapa {step} de {total} · <strong>{names[step]}</strong></div>
    </div>
  );
}

export function Banner({ tone, title, children, onClose }: { tone: 'info' | 'warn'; title: string; children?: React.ReactNode; onClose?: () => void }) {
  return (
    <div className={`sp-banner sp-banner-${tone}`} role="status">
      <div className="sp-banner-head">
        <span className="sp-banner-title">{title}</span>
        {onClose && <button type="button" className="sp-banner-x" aria-label="Fechar" onClick={onClose}>×</button>}
      </div>
      {children && <div className="sp-banner-body">{children}</div>}
    </div>
  );
}

export function Section({ icon, title, subtitle, children }: { icon?: string; title: string; subtitle?: string; children: React.ReactNode }) {
  return (
    <>
      <div className="sp-card-head">
        <div className="sp-head-row">
          {icon && <span className="sp-head-icon"><Icon name={icon} size={20} /></span>}
          <div><h1>{title}</h1>{subtitle && <p>{subtitle}</p>}</div>
        </div>
      </div>
      <div className="sp-card-body">{children}</div>
    </>
  );
}

export function Field({ icon, label, req, children }: { icon?: string; label: string; req?: boolean; children: React.ReactNode }) {
  return (
    <div className="sp-field">
      <label>
        {icon && <Icon name={icon} size={14} className="sp-field-ic" />}
        <span>{label}</span>
        {req && <span className="req">*</span>}
      </label>
      {children}
    </div>
  );
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
