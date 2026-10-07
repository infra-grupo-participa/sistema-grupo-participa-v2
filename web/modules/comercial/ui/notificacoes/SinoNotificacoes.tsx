'use client';

// Sino do Comercial: lista das notificações de quem está na sessão + aviso no desktop (Notification API do
// navegador). Busca a cada 30 s; o que for novo e passar nas preferências (gatilho ligado, fora do silêncio)
// vira notificação do sistema operacional. Clicar leva para o negócio/conversa.
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import type { GatilhoNotificacao } from '../../domain/types';
import { avisarMudanca, repo, useAtualizacaoPeriodica, useDados } from '../repositorio';
import { AvisosNaTela, mostrarAvisoNaTela } from './avisos-na-tela';
import { deveAvisarNaTela, deveAvisarNoDesktop } from './regras-notificacao';

const ICONE: Record<GatilhoNotificacao, string> = {
  lead_novo: 'user', lead_respondeu: 'message', prazo_estourado: 'clock', venda_aprovada: 'check-circle',
  ficha_para_aprovar: 'send', atividade_vencendo: 'calendar',
};
const CHAVE_AVISADAS = 'gp_comercial_notif_avisadas';

/** Permissão de notificação do navegador ('unsupported' quando não existe a API). */
export function permissaoDesktop(): NotificationPermission | 'unsupported' {
  if (typeof window === 'undefined' || !('Notification' in window)) return 'unsupported';
  return Notification.permission;
}

export async function pedirPermissaoDesktop(): Promise<NotificationPermission | 'unsupported'> {
  if (permissaoDesktop() === 'unsupported') return 'unsupported';
  return Notification.requestPermission();
}

export function SinoNotificacoes() {
  const router = useRouter();
  const [aberto, setAberto] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const { dados: notificacoes, recarregar } = useDados(() => repo.notificacoes());
  const { dados: prefs } = useDados(() => repo.preferenciasNotificacao());
  const naoLidas = (notificacoes ?? []).filter((n) => !n.lida);

  // Busca periódica (pausa com a aba oculta; ao voltar busca na hora).
  useAtualizacaoPeriodica(recarregar, 'sino');

  // Aviso do que é novo (não repete o que já avisou nesta sessão do navegador). Na 1ª carga só marca como
  // visto, para não despejar o acumulado. Com permissão: aviso do sistema operacional; sem: aviso na tela.
  useEffect(() => {
    if (!notificacoes || !prefs) return;
    let avisadas: string[] | null = null;
    try { const bruto = sessionStorage.getItem(CHAVE_AVISADAS); avisadas = bruto ? JSON.parse(bruto) : null; } catch { /* sem storage */ }
    const agora = new Date();
    const primeira = avisadas === null;
    const novas = primeira ? [] : notificacoes.filter((n) => !n.lida && !avisadas!.includes(n.id));
    const doSistema = permissaoDesktop() === 'granted';
    for (const n of novas.slice(0, 3)) {
      if (doSistema && deveAvisarNoDesktop(prefs, n.gatilho, agora)) {
        const aviso = new Notification(n.titulo, { body: n.corpo, tag: n.id });
        aviso.onclick = () => { window.focus(); router.push(n.href); aviso.close(); };
      } else if (deveAvisarNaTela(prefs, n.gatilho, agora)) {
        mostrarAvisoNaTela({ id: n.id, titulo: n.titulo, corpo: n.corpo, href: n.href });
      }
    }
    avisadas ??= [];
    try { sessionStorage.setItem(CHAVE_AVISADAS, JSON.stringify([...avisadas, ...notificacoes.map((n) => n.id)].slice(-300))); } catch { /* sem storage */ }
  }, [notificacoes, prefs, router]);

  useEffect(() => {
    if (!aberto) return;
    const fora = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setAberto(false); };
    const esc = (e: KeyboardEvent) => { if (e.key === 'Escape') setAberto(false); };
    document.addEventListener('mousedown', fora);
    document.addEventListener('keydown', esc);
    return () => { document.removeEventListener('mousedown', fora); document.removeEventListener('keydown', esc); };
  }, [aberto]);

  return (
    <div ref={ref} className="relative">
      <AvisosNaTela />
      <button
        type="button"
        aria-label={`Notificações${naoLidas.length ? `: ${naoLidas.length} não lidas` : ''}`}
        aria-expanded={aberto}
        onClick={() => setAberto((a) => !a)}
        className="relative grid place-items-center w-9 h-9 rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
      >
        <BellGlyph />
        {naoLidas.length > 0 && (
          <span className="absolute -top-1 -right-1 min-w-[18px] h-[18px] px-1 grid place-items-center rounded-[var(--r-pill)] bg-[var(--red)] text-[11px] font-semibold tabular text-white">
            {naoLidas.length > 9 ? '9+' : naoLidas.length}
          </span>
        )}
      </button>
      {aberto && (
        <div role="dialog" aria-label="Notificações" className="gp-pop-in origin-top-right absolute right-0 z-40 mt-1.5 w-[min(360px,calc(100vw-32px))] rounded-[var(--r-lg)] border border-[var(--border-strong)] bg-[var(--surface-2)] shadow-[var(--highlight-surface),var(--shadow-lg)]">
          <div className="flex items-center justify-between gap-2 px-3 py-2 border-b border-[var(--border)]">
            <span className="text-sm font-semibold text-[var(--fg)]">Notificações</span>
            <span className="flex items-center gap-3">
              {naoLidas.length > 0 && (
                <button type="button" className="text-xs text-[var(--fg-2)] hover:text-[var(--fg)]" onClick={async () => { await repo.marcarNotificacoesLidas(); avisarMudanca(); }}>
                  Marcar todas como lidas
                </button>
              )}
              <Link href="/comercial/configuracoes#notificacoes" className="text-xs text-[var(--fg-2)] hover:text-[var(--fg)]" onClick={() => setAberto(false)}>Preferências</Link>
            </span>
          </div>
          {permissaoDesktop() === 'default' && (
            <button type="button" onClick={async () => { await pedirPermissaoDesktop(); avisarMudanca(); }}
              className="w-full flex items-center gap-2 px-3 py-2 text-left text-xs text-[var(--fg-2)] border-b border-[var(--border-faint)] hover:bg-[var(--surface-3)]">
              <Icon name="alert" size={13} /> Ativar avisos no desktop deste computador
            </button>
          )}
          <ul className="max-h-[60vh] overflow-y-auto">
            {(notificacoes ?? []).length === 0 && <li className="px-3 py-8 text-center text-sm text-[var(--fg-3)]">Nada por aqui. Tudo em dia.</li>}
            {(notificacoes ?? []).slice(0, 30).map((n) => (
              <li key={n.id}>
                <Link
                  href={n.href}
                  onClick={async () => { setAberto(false); await repo.marcarNotificacoesLidas([n.id]); avisarMudanca(); }}
                  className={`flex items-start gap-2.5 px-3 py-2.5 border-b border-[var(--border-faint)] last:border-0 hover:bg-[var(--surface-3)] ${n.lida ? 'opacity-60' : ''}`}
                >
                  <span className={`mt-0.5 grid place-items-center w-7 h-7 shrink-0 rounded-full ${n.gatilho === 'prazo_estourado' ? 'bg-[var(--red-subtle)] text-[var(--red)]' : n.gatilho === 'venda_aprovada' ? 'text-[var(--green)] bg-[var(--surface-3)]' : 'bg-[var(--surface-3)] text-[var(--fg-2)]'}`}>
                    <Icon name={ICONE[n.gatilho]} size={14} />
                  </span>
                  <span className="min-w-0 flex-1">
                    <span className="block text-[13px] font-medium text-[var(--fg)] truncate">{n.titulo}</span>
                    <span className="block text-xs text-[var(--fg-3)] truncate">{n.corpo}</span>
                  </span>
                  <span className="shrink-0 text-[11px] text-[var(--fg-3)]">{fmtRelativo(n.em).label}</span>
                  {!n.lida && <span className="mt-1.5 w-2 h-2 shrink-0 rounded-full bg-[var(--accent)]" aria-label="não lida" />}
                </Link>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

function BellGlyph() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
      <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
    </svg>
  );
}
