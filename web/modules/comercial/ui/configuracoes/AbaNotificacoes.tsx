'use client';

// Aba #notificacoes: preferências de quem está logado (cada pessoa edita só as suas).
// Aviso no desktop depende de duas chaves: a preferência aqui e a permissão do navegador neste computador.
import { useState, useSyncExternalStore } from 'react';
import { Button, Card, Input, Loading, SectionCard, Toggle } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { GatilhoNotificacao, PreferenciasNotificacao } from '../../domain/types';
import { Campo, Carregando, NotaRodape } from '../comum';
import { pedirPermissaoDesktop, permissaoDesktop } from '../notificacoes/SinoNotificacoes';
import { ROTULO_GATILHO, emSilencio } from '../notificacoes/regras-notificacao';
import { avisarMudanca, repo, useAgora, useDados } from '../repositorio';
import {
  alternarGatilho, definirSilencio, estadoPermissao, preferenciasIguais, textoSilencio, validarPreferencias, type PermissaoNavegador,
} from './preferencias';

const GATILHOS = Object.keys(ROTULO_GATILHO) as GatilhoNotificacao[];

// A permissão do navegador não avisa quando muda: quem pede avisa os ouvintes.
const ouvintesPermissao = new Set<() => void>();
function usePermissao(): [PermissaoNavegador, () => void] {
  const p = useSyncExternalStore(
    (cb) => { ouvintesPermissao.add(cb); return () => { ouvintesPermissao.delete(cb); }; },
    permissaoDesktop,
    () => 'unsupported' as PermissaoNavegador,
  );
  return [p, () => ouvintesPermissao.forEach((f) => f())];
}

export function AbaNotificacoes({ flash }: { flash: (m: string) => void }) {
  const r = useDados(() => repo.preferenciasNotificacao());
  return (
    <Carregando dados={r.dados} erro={r.erro} onTentar={() => { void r.recarregar(); }} esqueleto={<Loading minHeight={160} />}>
      {/* key: quando o salvo muda, o rascunho recomeça dele. */}
      {(salvo) => <Preferencias key={JSON.stringify(salvo)} salvo={salvo} flash={flash} />}
    </Carregando>
  );
}

function Preferencias({ salvo, flash }: { salvo: PreferenciasNotificacao; flash: (m: string) => void }) {
  const [p, setP] = useState(salvo);
  const [salvando, setSalvando] = useState(false);
  const [permissao, avisarPermissao] = usePermissao();
  const agora = useAgora();
  const est = estadoPermissao(permissao);
  const erro = validarPreferencias(p);
  const alterada = !preferenciasIguais(p, salvo);
  const silencioLigado = p.silencioInicio != null || p.silencioFim != null;
  const silenciosoAgora = !erro && emSilencio(p, agora);

  async function pedir() {
    const res = await pedirPermissaoDesktop();
    avisarPermissao();
    flash(res === 'granted' ? 'Avisos permitidos neste computador.' : res === 'denied' ? 'O navegador bloqueou os avisos.' : 'Permissão não concedida.');
  }

  function testar() {
    if (!est.liberada) { flash(est.explicacao); return; }
    try {
      const n = new Notification('Comercial: notificação de teste', { body: 'Se você está lendo isto, os avisos no desktop funcionam neste computador.', tag: 'gp-comercial-teste' });
      n.onclick = () => { window.focus(); n.close(); };
      flash('Notificação de teste enviada.');
    } catch {
      flash('O navegador não deixou mostrar o aviso. Confira as notificações do sistema operacional.');
    }
  }

  async function salvar() {
    if (erro) return;
    setSalvando(true);
    const res = await repo.salvarPreferenciasNotificacao(p);
    setSalvando(false);
    if (res.ok) { flash('Preferências salvas.'); avisarMudanca(); } else flash(res.msg ?? 'Não foi possível salvar.');
  }

  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-2">
        <SectionCard title="Aviso no desktop" subtitle="Notificação do sistema operacional, mesmo com a aba em segundo plano.">
          <div className="space-y-4">
            <Toggle checked={p.desktop} onChange={(desktop) => setP({ ...p, desktop })} label={p.desktop ? 'Ligado para mim' : 'Desligado: só no sino'} />
            <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-3 space-y-2">
              <div className="flex flex-wrap items-center gap-2 text-sm">
                <Icon name={est.liberada ? 'check-circle' : 'lock'} size={14} className={est.liberada ? 'text-[var(--green)]' : 'text-[var(--fg-3)]'} />
                <span className="font-medium text-[var(--fg)]">Neste navegador: {est.rotulo}</span>
              </div>
              <p className="text-xs text-[var(--fg-2)] leading-relaxed">{est.explicacao}</p>
              <div className="flex flex-wrap gap-2 pt-1">
                {est.podePedir && <Button size="sm" variant="ghost" onClick={() => { void pedir(); }}>Permitir neste computador</Button>}
                <Button size="sm" variant="ghost" onClick={testar}><Icon name="send" size={14} /> Enviar notificação de teste</Button>
              </div>
            </div>
            {p.desktop && !est.liberada && (
              <NotaRodape>Enquanto o navegador não permitir, os avisos ficam só no sino.</NotaRodape>
            )}
          </div>
        </SectionCard>

        <SectionCard title="Horário de silêncio" subtitle="Fora do expediente o aviso não pula na tela; a notificação continua no sino.">
          <div className="space-y-4">
            <Toggle checked={silencioLigado} onChange={(v) => setP(definirSilencio(p, v))} label={silencioLigado ? `Silêncio: ${textoSilencio(p)}` : 'Sem silêncio'} />
            {silencioLigado && (
              <div className="grid gap-3 grid-cols-2 max-w-sm">
                <Campo rotulo="Começa às">
                  <Input type="time" value={p.silencioInicio ?? ''} onChange={(e) => setP({ ...p, silencioInicio: e.target.value || null })} />
                </Campo>
                <Campo rotulo="Termina às">
                  <Input type="time" value={p.silencioFim ?? ''} onChange={(e) => setP({ ...p, silencioFim: e.target.value || null })} />
                </Campo>
              </div>
            )}
            {erro ? <p className="text-xs text-[var(--red)]">{erro}</p> : silencioLigado && (
              <NotaRodape>{silenciosoAgora ? 'Agora está no horário de silêncio.' : 'Agora os avisos estão liberados.'} Pode virar a noite (ex.: 20:00 às 08:00).</NotaRodape>
            )}
          </div>
        </SectionCard>
      </div>

      <SectionCard title="O que me avisa" subtitle="Vale para o aviso no desktop. O sino sempre mostra tudo.">
        <ul className="grid gap-x-6 gap-y-3 md:grid-cols-2">
          {GATILHOS.map((g) => (
            <li key={g}>
              <Toggle checked={!!p.gatilhos[g]} onChange={(v) => setP(alternarGatilho(p, g, v))} label={ROTULO_GATILHO[g]} />
            </li>
          ))}
        </ul>
      </SectionCard>

      {alterada && (
        <Card className="sticky bottom-0 flex flex-wrap items-center gap-2 px-4 py-3">
          <span className="text-xs text-[var(--fg-3)]">Alteração não salva</span>
          <span className="flex-1" />
          <Button size="sm" variant="ghost" disabled={salvando} onClick={() => setP(salvo)}>Desfazer</Button>
          <Button size="sm" disabled={!!erro || salvando} onClick={() => { void salvar(); }}><Icon name="check" size={14} /> {salvando ? 'Salvando…' : 'Salvar'}</Button>
        </Card>
      )}
    </div>
  );
}
