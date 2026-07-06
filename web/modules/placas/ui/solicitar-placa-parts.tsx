'use client';

// Componentes de apresentação (folhas, sem estado do wizard) do formulário público de placa.

import { Button, CopyField, Timeline, type TimelineEntry } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { getClientTrackingState, CLIENT_TRACKING_STEPS } from '../domain/client-tracking';
import { buildGcalLink } from '../domain/agendamento';
import { eligibleNivelRank, ELIGIBLE_NIVEL_ORDER } from '../domain/form-progress';

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

export function SuccessCard({ kind, token, onRefazer, refazerBusy }: { kind: 'success' | 'cadastro'; token?: string; onRefazer?: () => void; refazerBusy?: boolean }) {
  const isCad = kind === 'cadastro';
  const passos = isCad
    ? [
        { t: 'Nível registrado', d: 'Seus dados e o seu nível atual já estão no nosso sistema.' },
        { t: 'Evoluiu de nível?', d: 'Quando alcançar a faixa Ouro ou superior, retome pelo mesmo link e siga para a placa.' },
        { t: 'Confirmação por e-mail', d: 'Enviamos um e-mail com o registro e o seu link pessoal de acesso.' },
      ]
    : [
        { t: 'Análise da documentação', d: 'Nossa equipe revisa o comprovante e a declaração enviados.' },
        { t: 'Avisos por e-mail', d: 'A cada etapa vencida você recebe um e-mail com o próximo passo.' },
        { t: 'Acompanhamento online', d: 'Acesse o andamento quando quiser pelo seu link pessoal.' },
      ];
  return (
    <div className="sp-card">
      {/* Texto escuro sobre âmbar (decisão D5.1 do DS). */}
      <div className="sp-card-head" style={{ background: 'var(--orange)', color: 'var(--ink)', textAlign: 'center' }}>
        <div className="sp-success-badge"><Icon name={isCad ? 'check-circle' : 'party'} size={26} /></div>
        <h1 style={{ color: 'var(--ink)' }}>{isCad ? 'Cadastro registrado com sucesso!' : 'Recebemos sua solicitação! 🎉'}</h1>
        <p style={{ color: 'rgba(15,23,42,.75)' /* hex-ok: --ink com 75% sobre âmbar */ }}>
          {isCad
            ? 'Seus dados e o seu nível atual foram registrados pela nossa equipe.'
            : 'Sua documentação entrou na fila de análise. Veja o que acontece agora:'}
        </p>
      </div>
      <div className="sp-card-body">
        <div className="sp-decl-flow" style={{ marginBottom: 16 }}>
          {passos.map((p, i) => (
            <div key={p.t} className="sp-decl-step">
              <span className="n">{i + 1}</span>
              <div><b>{p.t}</b><p>{p.d}</p></div>
            </div>
          ))}
        </div>
        {!isCad && token && (
          <a className="sp-btn-next" style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, textDecoration: 'none', marginBottom: 12 }} href={`/solicitar-placa?token=${encodeURIComponent(token)}`}>
            <Icon name="arrow-up-right" size={16} /> Acompanhar minha solicitação
          </a>
        )}
        {isCad && onRefazer && (
          <div className="sp-sched sp-sched-set" style={{ marginBottom: 12 }}>
            <div className="sp-sched-title"><Icon name="medal" size={17} /> Evoluiu de nível?</div>
            <p className="sp-sched-desc">
              Se você subiu de nível desde este cadastro, refaça a solicitação para atualizar o seu nível —
              e, ao alcançar Ouro ou acima, seguir para a emissão da placa. Seus dados já ficam preenchidos.
            </p>
            <button type="button" className="sp-sched-cta" disabled={refazerBusy} onClick={onRefazer} style={refazerBusy ? { opacity: 0.7, cursor: 'wait' } : undefined}>
              <Icon name="rotate" size={15} /> {refazerBusy ? 'Preparando…' : 'Refazer solicitação — evoluí de nível'}
            </button>
          </div>
        )}
        <div className="sp-hint" style={{ textAlign: 'center' }}>
          📬 Enviamos a confirmação para o seu e-mail — se não encontrar, confira o spam ou a aba Promoções.
        </div>
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

export function TrackingCard({ data, onRefazer, refazerBusy, error }: { data: Record<string, unknown>; onRefazer?: () => void; refazerBusy?: boolean; error?: string }) {
  const { activeIndex, rejected } = getClientTrackingState(data);
  const concluido = String(data.status ?? '') === 'concluido';
  // Só oferece refazer se houver nível elegível superior (topo = Diamante Vermelho não refaz).
  const nivelRank = eligibleNivelRank(String(data.nivel ?? ''));
  const podeRefazer = concluido && nivelRank >= 0 && nivelRank < ELIGIBLE_NIVEL_ORDER.length - 1;
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

  // Subtítulo vivo: diz o momento exato da jornada em vez do genérico "em andamento".
  const subtitulo =
    activeIndex >= 4 && rastreio ? 'Sua placa está a caminho — acompanhe pelo código de rastreio.'
    : activeIndex >= 4 ? 'Sua placa foi enviada!'
    : activeIndex === 3 ? 'Entrevista realizada — sua placa está em preparação.'
    : hasInterview ? 'Entrevista agendada — é só comparecer no horário marcado.'
    : activeIndex === 2 ? 'Documentação aprovada — agende sua entrevista.'
    : 'Sua documentação está em análise pela equipe.';

  return (
    <div className="sp-card">
      {/* Texto escuro sobre âmbar (decisão D5.1 do DS): branco sobre --orange fica abaixo de AA (~1.9:1). */}
      <div className="sp-card-head" style={{ background: 'var(--orange)', color: 'var(--ink)' }}>
        <h1 style={{ color: 'var(--ink)' }}>Acompanhe sua solicitação</h1>
        <p style={{ color: 'rgba(15,23,42,.75)' /* hex-ok: --ink com 75% sobre âmbar */ }}>{subtitulo}</p>
      </div>
      <div className="sp-card-body">
        {podeRefazer && onRefazer && (
          <div className="sp-sched sp-sched-set" style={{ marginBottom: 16 }}>
            <div className="sp-sched-title"><Icon name="medal" size={17} /> Subiu de nível?</div>
            <p className="sp-sched-desc">
              Sua placa deste nível já foi concluída. Se você evoluiu para um nível superior, refaça o
              processo para receber a placa do novo nível — seus dados de contato já ficam preenchidos.
            </p>
            <button type="button" className="sp-sched-cta" disabled={refazerBusy} onClick={onRefazer} style={refazerBusy ? { opacity: 0.7, cursor: 'wait' } : undefined}>
              <Icon name="rotate" size={15} /> {refazerBusy ? 'Preparando…' : 'Refazer processo — subi de nível'}
            </button>
            {error && <p className="sp-err" style={{ marginTop: 8 }}>{error}</p>}
          </div>
        )}
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
              <a className="sp-sched-alt" href={buildGcalLink('', entrevistaData, entrevistaHora, zoomLink || null)} target="_blank" rel="noopener"><Icon name="calendar" size={14} /> Adicionar ao Google Agenda</a>
              <a className="sp-sched-alt" href={agendarHref}>Reagendar</a>
            </div>
          </div>
        )}
        {/* Rastreio em destaque no topo (não escondido no fim da timeline): o aluno chega
            aqui pelo e-mail "placa a caminho" justamente atrás deste código. */}
        {rastreio && (
          <div style={{ marginBottom: 16 }}>
            <CopyField label="Código de rastreio" value={rastreio} />
            <p className="sp-hint" style={{ marginTop: 6 }}>
              Acompanhe a entrega no site dos <a href={`https://rastreamento.correios.com.br/app/index.php?objeto=${encodeURIComponent(rastreio)}`} target="_blank" rel="noopener">Correios</a>.
            </p>
          </div>
        )}
        <div style={{ marginTop: 4 }}>
          <div style={{ fontSize: 11, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em', color: 'var(--muted)', marginBottom: 10 }}>
            Jornada do processo
          </div>
          <Timeline items={tlItems} />
        </div>
      </div>
    </div>
  );
}
