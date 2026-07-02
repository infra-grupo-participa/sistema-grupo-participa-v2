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

/** Formata a data da entrevista (YYYY-MM-DD) por extenso, ancorada em America/Sao_Paulo. */
function fmtInterviewDate(iso: string): string {
  const dt = new Date(`${iso}T12:00:00-03:00`);
  if (Number.isNaN(dt.getTime())) return iso;
  const s = new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: '2-digit', month: 'long', timeZone: 'America/Sao_Paulo' }).format(dt);
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function TrackingCard({ data }: { data: Record<string, unknown> }) {
  const { activeIndex, rejected } = getClientTrackingState(data);
  const rastreio = String(data.codigo_rastreio ?? '');
  const token = String(data.token ?? '');
  const entrevistaData = String(data.entrevista_data ?? '').slice(0, 10);
  const entrevistaHora = String(data.entrevista_hora ?? '').slice(0, 5);
  const zoomLink = String(data.entrevista_link ?? data.meet_link ?? '');
  const agendarHref = `/agendar-entrevista${token ? `?token=${encodeURIComponent(token)}` : ''}`;
  const motivoRetorno = String(data.motivo_retorno ?? '');

  if (rejected) {
    // Antes o rejeitado caía na timeline normal e via "Documentação Aprovada" — progresso falso.
    return (
      <div className="sp-card">
        <div className="sp-card-head">
          <h1>Solicitação não aprovada</h1>
          <p>Sua solicitação de placa não pôde ser aprovada neste momento.</p>
        </div>
        <div className="sp-card-body">
          {motivoRetorno && <div className="sp-warn"><strong>Motivo:</strong> {motivoRetorno}</div>}
          <div className="sp-info">
            Se você acredita que houve um engano ou quer entender os critérios, fale com a nossa
            Secretaria — teremos prazer em orientar os próximos passos.
          </div>
        </div>
      </div>
    );
  }

  // Marco "Entrevista Realizada" ativo (index 2) = documentação aprovada, entrevista pendente.
  const inInterviewPhase = activeIndex === 2;
  const hasInterview = inInterviewPhase && Boolean(entrevistaData);

  const tlItems: TimelineEntry[] = CLIENT_TRACKING_STEPS.map((s, i) => ({
    title: s.title,
    body: s.note,
    tone: i < activeIndex ? 'green' : i === activeIndex ? 'accent' : 'base',
    done: i < activeIndex,
    icon: i < activeIndex ? undefined : String(i + 1),
  }));

  return (
    <div className="sp-card">
      {/* Texto escuro sobre âmbar (decisão D5.1 do DS): branco sobre --orange fica abaixo de AA (~1.9:1). */}
      <div className="sp-card-head" style={{ background: 'var(--orange)', color: 'var(--ink)' }}>
        <h1 style={{ color: 'var(--ink)' }}>Acompanhe sua solicitação</h1>
        <p style={{ color: 'rgba(15,23,42,.75)' /* hex-ok: --ink com 75% sobre âmbar */ }}>Sua solicitação está em andamento</p>
      </div>
      <div className="sp-card-body">
        {inInterviewPhase && !hasInterview && (
          <div className="sp-sched">
            <div className="sp-sched-title"><Icon name="check-circle" size={17} /> Documentação aprovada!</div>
            <p className="sp-sched-desc">Agora agende sua entrevista por videoconferência no melhor dia e horário para você.</p>
            <a className="sp-sched-cta" href={agendarHref}><Icon name="calendar-days" size={16} /> Agendar entrevista</a>
          </div>
        )}
        {hasInterview && (
          <div className="sp-sched sp-sched-set">
            <div className="sp-sched-title"><Icon name="calendar-days" size={17} /> Entrevista agendada</div>
            <p className="sp-sched-when">{fmtInterviewDate(entrevistaData)} às <strong>{entrevistaHora}</strong></p>
            <div className="sp-sched-actions">
              {zoomLink && <a className="sp-sched-cta" href={zoomLink} target="_blank" rel="noopener"><Icon name="link" size={15} /> Entrar na sala</a>}
              <a className="sp-sched-alt" href={agendarHref}>Reagendar</a>
            </div>
          </div>
        )}
        <Timeline items={tlItems} />
        {rastreio && (
          <div className="sp-info" style={{ marginTop: 16 }}>Código de rastreio: <strong>{rastreio}</strong></div>
        )}
      </div>
    </div>
  );
}
