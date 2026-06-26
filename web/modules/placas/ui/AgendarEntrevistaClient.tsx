'use client';

import { useEffect, useMemo, useState } from 'react';
import './solicitar-placa.css';
import { placaGet } from './placa-api';
import { agendaConfirm, agendaHold } from './agenda-api';
import { buildSlotStart, isSlotSelectable, rescheduleBlockReason } from '../domain/agendamento';

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
      {view === 'loading' && <Card><div className="sp-card-body">Carregando horários…</div></Card>}

      {view === 'no-session' && (
        <Card>
          <Head title="Sessão não encontrada" subtitle="" orange />
          <div className="sp-card-body"><p style={{ color: '#6b7280' }}>Não localizamos sua solicitação. Acesse pelo link enviado por e-mail.</p></div>
        </Card>
      )}

      {view === 'done' && (
        <Card>
          <Head title="Entrevista já concluída" subtitle="" orange />
          <div className="sp-card-body"><p style={{ color: '#6b7280' }}>Não é possível reagendar porque sua entrevista já foi concluída. Acompanhe o andamento na página de acompanhamento.</p></div>
        </Card>
      )}

      {(view === 'no-slots' || noSlots) && (
        <Card>
          <Head title="Sem horários disponíveis" subtitle="" orange />
          <div className="sp-card-body"><p style={{ color: '#6b7280' }}>No momento não há horários abertos para entrevista. Tente novamente mais tarde.</p></div>
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
                <div style={{ fontWeight: 700, fontSize: 14, textTransform: 'capitalize', marginBottom: 8 }}>{fmtDate(date)}</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                  {horas.map((h) => {
                    const selected = picked?.slot_data === date && picked?.hora === h;
                    return (
                      <button
                        key={h}
                        type="button"
                        onClick={() => setPicked({ slot_data: date, hora: h })}
                        className="sp-radio"
                        style={{ width: 'auto', margin: 0, padding: '10px 16px', borderColor: selected ? '#f29725' : undefined, background: selected ? 'rgba(242,151,37,.1)' : undefined, fontWeight: 700 }}
                      >
                        {h}
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
            <div className="sp-nav">
              <span />
              <button type="button" className="sp-btn-next" disabled={!picked || view === 'confirming'} onClick={confirmar}>
                {view === 'confirming' ? 'Confirmando…' : picked ? `Confirmar ${fmtDate(picked.slot_data)} às ${picked.hora}` : 'Selecione um horário'}
              </button>
            </div>
          </div>
        </Card>
      )}

      {view === 'success' && (
        <Card>
          <Head title="Entrevista confirmada! 🎉" subtitle="" orange />
          <div className="sp-card-body">
            <p style={{ color: '#374151', marginBottom: 16 }}>Sua entrevista foi agendada com sucesso. Você receberá os detalhes por e-mail.</p>
            {result?.zoom_link ? (
              <a href={result.zoom_link} target="_blank" rel="noopener" className="sp-btn-next" style={{ display: 'inline-block', textDecoration: 'none', marginBottom: 10 }}>Abrir sala (Zoom)</a>
            ) : (
              <div className="sp-warn">O link da reunião será enviado em breve por e-mail.</div>
            )}
            {result?.gcal_link && (
              <div><a href={result.gcal_link} target="_blank" rel="noopener" className="sp-btn-back" style={{ display: 'inline-block', textDecoration: 'none' }}>Salvar na agenda Google</a></div>
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
function Head({ title, subtitle, orange }: { title: string; subtitle?: string; orange?: boolean }) {
  return (
    <div className="sp-card-head" style={orange ? { background: '#f29725', color: '#fff' } : undefined}>
      <h1 style={orange ? { color: '#fff' } : undefined}>{title}</h1>
      {subtitle && <p style={orange ? { color: 'rgba(255,255,255,.85)' } : undefined}>{subtitle}</p>}
    </div>
  );
}
