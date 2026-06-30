'use client';

import { useEffect, useMemo, useState } from 'react';
import './solicitar-placa.css';
import { placaGet } from './placa-api';
import { agendaConfirm, agendaHold } from './agenda-api';
import { buildSlotStart, isSlotSelectable, rescheduleBlockReason } from '../domain/agendamento';
import { Badge, Button, EmptyState, Loading } from '@/shared/ui/components';

type View = 'loading' | 'calendar' | 'confirming' | 'success' | 'no-slots' | 'no-session' | 'done' | 'error';

interface Slot {
  slot_data: string;
  hora: string;
}

function fmtDate(iso: string): string {
  const d = buildSlotStart(iso, '12:00');
  if (!d) return iso;
  return new Intl.DateTimeFormat('pt-BR', { weekday: 'long', day: '2-digit', month: 'long', timeZone: 'America/Sao_Paulo' }).format(d);
}

export function AgendarEntrevistaClient({ initialToken }: { initialToken: string }) {
  const [view, setView] = useState<View>('loading');
  const [token, setToken] = useState(initialToken);
  const [sol, setSol] = useState<Record<string, unknown> | null>(null);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [booked, setBooked] = useState<Set<string>>(new Set());
  const [picked, setPicked] = useState<Slot | null>(null);
  const [result, setResult] = useState<{ zoom_link?: string | null; gcal_link?: string } | null>(null);
  const [err, setErr] = useState('');

  useEffect(() => {
    (async () => {
      const r = await placaGet(initialToken, true);
      if (!r?.ok || !r.solicitacao) {
        setView('no-session');
        return;
      }
      const s = r.solicitacao as Record<string, unknown>;
      setSol(s);
      setToken(String(s.token ?? initialToken));
      setBooked(new Set((r.booked_slots ?? []).map((b) => `${b.entrevista_data}|${b.entrevista_hora.slice(0, 5)}`)));
      setSlots((r.horarios ?? []).map((h) => ({ slot_data: String(h.slot_data), hora: String(h.hora).slice(0, 5) })));

      // Entrevista finalizada → não pode reagendar.
      const block = rescheduleBlockReason(s, new Date());
      if (block === 'entrevista_finalizada') {
        setView('done');
        return;
      }
      setView('calendar');
    })();
  }, [initialToken]);

  // Slots selecionáveis: ativos, futuros (>2h) e não ocupados, agrupados por data.
  const byDate = useMemo(() => {
    const now = new Date();
    const map = new Map<string, string[]>();
    for (const s of slots) {
      const start = buildSlotStart(s.slot_data, s.hora);
      if (!start || !isSlotSelectable(start, now)) continue;
      if (booked.has(`${s.slot_data}|${s.hora}`)) continue;
      if (!map.has(s.slot_data)) map.set(s.slot_data, []);
      map.get(s.slot_data)!.push(s.hora);
    }
    for (const arr of map.values()) arr.sort();
    return Array.from(map.entries()).sort((a, b) => a[0].localeCompare(b[0]));
  }, [slots, booked]);

  // "Sem horários" é derivado no render (não em efeito) para evitar cascata de estado.
  const noSlots = view === 'calendar' && byDate.length === 0;

  async function confirmar() {
    if (!picked || !token) return;
    setErr('');
    setView('confirming');
    const hold = await agendaHold(token, picked.slot_data, picked.hora);
    if (!hold.ok) {
      setErr(hold.error || 'Horário indisponível.');
      setView('calendar');
      return;
    }
    const res = await agendaConfirm(token, picked.slot_data, picked.hora);
    if (!res.ok) {
      setErr(res.error || 'Não foi possível confirmar.');
      setView('calendar');
      return;
    }
    setResult({ zoom_link: res.zoom_link, gcal_link: res.gcal_link });
    setView('success');
  }

  return (
    <div className="sp-wrap">
      <div className="sp-brand">
        <div className="sp-brand-logo">GP</div>
        <div>
          <div className="sp-brand-name">Grupo Participa</div>
          <div className="sp-brand-sub">Agendamento de Entrevista</div>
        </div>
      </div>
      {view === 'loading' && (
        <Card>
          <div className="sp-card-body"><Loading label="Carregando horários…" minHeight={160} /></div>
        </Card>
      )}

      {view === 'no-session' && (
        <Card>
          <Head title="Sessão não encontrada" subtitle="" orange />
          <div className="sp-card-body">
            <EmptyState
              icon="🔒"
              title="Não localizamos sua solicitação"
              hint="Acesse pelo link enviado por e-mail."
            />
          </div>
        </Card>
      )}

      {view === 'done' && (
        <Card>
          <Head title="Entrevista já concluída" subtitle="" orange />
          <div className="sp-card-body">
            <EmptyState
              icon="✓"
              title="Não é possível reagendar"
              hint="Sua entrevista já foi concluída. Acompanhe o andamento na página de acompanhamento."
            />
          </div>
        </Card>
      )}

      {(view === 'no-slots' || noSlots) && (
        <Card>
          <Head title="Sem horários disponíveis" subtitle="" orange />
          <div className="sp-card-body">
            <EmptyState
              icon="🗓️"
              title="Nenhum horário aberto no momento"
              hint="Não há horários abertos para entrevista. Tente novamente mais tarde."
            />
          </div>
        </Card>
      )}

      {((view === 'calendar' && !noSlots) || view === 'confirming') && (
        <Card>
          <Head title="Agende sua entrevista" subtitle="Escolha o melhor dia e horário (videoconferência)." orange />
          <div className="sp-card-body">
            {String((sol?.entrevista_data ?? '')) && (
              <div className="sp-info">Você já tem uma entrevista marcada. Escolher um novo horário irá substituí-la.</div>
            )}
            {err && <p className="sp-err">{err}</p>}
            {byDate.map(([date, horas]) => (
              <div key={date} style={{ marginBottom: 16 }}>
                <div style={{ fontWeight: 700, fontSize: 14, textTransform: 'capitalize', marginBottom: 8, display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span>{fmtDate(date)}</span>
                  <Badge tone="neutral">{horas.length} horário{horas.length > 1 ? 's' : ''}</Badge>
                </div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {horas.map((h) => {
                    const selected = picked?.slot_data === date && picked?.hora === h;
                    return (
                      <SlotButton
                        key={h}
                        hora={h}
                        selected={selected}
                        onClick={() => setPicked({ slot_data: date, hora: h })}
                      />
                    );
                  })}
                </div>
              </div>
            ))}
            <div className="sp-nav">
              <span />
              <Button
                type="button"
                variant="primary"
                disabled={!picked || view === 'confirming'}
                onClick={confirmar}
              >
                {view === 'confirming' ? 'Confirmando…' : picked ? `Confirmar ${fmtDate(picked.slot_data)} às ${picked.hora}` : 'Selecione um horário'}
              </Button>
            </div>
          </div>
        </Card>
      )}

      {view === 'success' && (
        <Card>
          <Head title="Entrevista confirmada! 🎉" subtitle="" orange />
          <div className="sp-card-body">
            <div style={{ marginBottom: 16 }}>
              <Badge tone="success" dot>Agendamento confirmado</Badge>
            </div>
            <p style={{ color: 'var(--muted)', marginBottom: 16 }}>Sua entrevista foi agendada com sucesso. Você receberá os detalhes por e-mail.</p>
            {result?.zoom_link ? (
              <LinkButton href={result.zoom_link} variant="primary" style={{ marginBottom: 10 }}>
                Abrir sala (Zoom)
              </LinkButton>
            ) : (
              <div className="sp-warn">O link da reunião será enviado em breve por e-mail.</div>
            )}
            {result?.gcal_link && (
              <div>
                <LinkButton href={result.gcal_link} variant="ghost">
                  Salvar na agenda Google
                </LinkButton>
              </div>
            )}
          </div>
        </Card>
      )}
    </div>
  );
}

function Card({ children }: { children: React.ReactNode }) {
  return <div className="sp-card">{children}</div>;
}

// Chip de horário (seleção de slot). Co-localizado: o Button do catálogo é dark-theme
// (text-black sobre âmbar) e quebraria o tema claro deste fluxo público; reaproveita
// o estilo `sp-radio` do fluxo, cujos tokens (--orange/--orange-soft) são escopados em
// .sp-wrap e mapeiam para o âmbar da marca (ver gaps_catalogo).
function SlotButton({ hora, selected, onClick }: { hora: string; selected: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={selected}
      className="sp-radio"
      style={{
        width: 'auto',
        margin: 0,
        padding: '10px 16px',
        borderColor: selected ? 'var(--orange)' : undefined,
        background: selected ? 'var(--orange-soft)' : undefined,
        fontWeight: 700,
      }}
    >
      {hora}
    </button>
  );
}

// Variante <a> do Button do catálogo (o Button é button-only) — mesma linguagem visual via tokens.
// Co-localizado pois não há LinkButton no catálogo congelado (ver gaps_catalogo).
const LINK_BTN_VARIANTS: Record<'primary' | 'ghost', string> = {
  primary: 'bg-[var(--accent)] text-black hover:brightness-110 border border-transparent',
  ghost: 'bg-transparent text-[var(--fg-2)] border border-[var(--border)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]',
};
function LinkButton({ href, variant = 'primary', children, style }: {
  href: string; variant?: 'primary' | 'ghost'; children: React.ReactNode; style?: React.CSSProperties;
}) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noopener"
      style={style}
      className={`inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] px-4 py-2 text-sm font-semibold no-underline transition-[filter,background,border-color,color] duration-150 ${LINK_BTN_VARIANTS[variant]}`}
    >
      {children}
    </a>
  );
}
function Head({ title, subtitle, orange }: { title: string; subtitle?: string; orange?: boolean }) {
  return (
    <div className="sp-card-head" style={orange ? { background: 'var(--orange)', color: '#fff' /* hex-ok: texto branco sobre âmbar (contraste no header da marca) */ } : undefined}>
      <h1 style={orange ? { color: '#fff' /* hex-ok: contraste branco no header âmbar */ } : undefined}>{title}</h1>
      {subtitle && <p style={orange ? { color: 'rgba(255,255,255,.85)' /* hex-ok: subtítulo branco translúcido no header âmbar */ } : undefined}>{subtitle}</p>}
    </div>
  );
}
