'use client';

// Conversa flutuante no Funil (dock no canto inferior direito): o botão de conversa do card e do NegocioDrawer abre a
// conversa sem sair do funil. Uma conversa por vez; minimizar/maximizar, fechar e "abrir na tela de Conversas".
// No celular vira tela cheia. Reaproveita o PainelConversa da tela de Conversas (mesmas regras, mesmo realtime
// crm:caixa + busca periódica). Fora do Funil não há provedor: o botão segue indo para /comercial/conversas.
import Link from 'next/link';
import { useCallback, useMemo, useState } from 'react';
import { Card, Spinner } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Negocio } from '../../domain/types';
import { EstadoErro, Vazio, useEquipe } from '../comum';
import { ModalAtividade, NegocioDrawer } from '../NegocioDrawer';
import { avisarMudanca, recarregarSino, repo, useAgora, useAtualizacaoPeriodica, useContatosPorIds, useDados } from '../repositorio';
import { PainelConversa } from './PainelConversa';

import { DockContexto } from './dock-contexto';

const BTN = 'w-8 h-8 grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]';

export function DockConversaProvider({ negocios, flash, children }: { negocios: Negocio[] | null; flash: (s: string) => void; children: React.ReactNode }) {
  const [contatoId, setContatoId] = useState<string | null>(null);
  const [minimizado, setMinimizado] = useState(false);
  const [grande, setGrande] = useState(false);
  const abrir = useCallback((id: string) => { setContatoId(id); setMinimizado(false); }, []);
  const api = useMemo(() => ({ abrir }), [abrir]);
  return (
    <DockContexto.Provider value={api}>
      {children}
      {contatoId && (
        <DockConversa
          key={contatoId}
          contatoId={contatoId}
          negocios={negocios}
          minimizado={minimizado}
          grande={grande}
          flash={flash}
          onMinimizar={() => setMinimizado((v) => !v)}
          onGrande={() => setGrande((v) => !v)}
          onFechar={() => setContatoId(null)}
        />
      )}
    </DockContexto.Provider>
  );
}

function DockConversa({ contatoId, negocios, minimizado, grande, flash, onMinimizar, onGrande, onFechar }: {
  contatoId: string; negocios: Negocio[] | null; minimizado: boolean; grande: boolean; flash: (s: string) => void;
  onMinimizar: () => void; onGrande: () => void; onFechar: () => void;
}) {
  const agora = useAgora();
  const { sessao, nomeDe, gestor } = useEquipe();
  const rContato = useContatosPorIds([contatoId]);
  const rConversas = useDados(() => repo.conversas());
  // Status, janela e número da conversa mudam com mensagem nova: a lista acompanha enquanto o dock está aberto.
  useAtualizacaoPeriodica(rConversas.recarregar, 'listaConversas', !minimizado);
  const rTemplates = useDados(() => repo.templates());
  const rCanais = useDados(() => repo.canais());
  const [negocioAberto, setNegocioAberto] = useState<string | null>(null);
  const [agendar, setAgendar] = useState<Negocio | null>(null);

  const contato = rContato.dados?.find((c) => c.id === contatoId) ?? null;
  const conversa = rConversas.dados?.find((c) => c.contatoId === contatoId) ?? null;
  const doContato = (negocios ?? []).filter((n) => n.contatoId === contatoId);
  const abertos = doContato.filter((n) => n.status === 'aberto').sort((a, b) => b.criadoEm.localeCompare(a.criadoEm));
  const erro = rContato.erro ?? rConversas.erro ?? rTemplates.erro ?? rCanais.erro;
  const pronto = !!contato && !!rConversas.dados && !!rTemplates.dados && !!rCanais.dados && !!sessao;
  const href = `/comercial/conversas?contato=${encodeURIComponent(contatoId)}`;

  const extras = (
    <>
      <Link href={href} aria-label="Abrir na tela de Conversas" title="Abrir na tela de Conversas" className={BTN}><Icon name="arrow-up-right" size={15} /></Link>
      <button type="button" onClick={onGrande} aria-label={grande ? 'Diminuir' : 'Aumentar'} title={grande ? 'Diminuir' : 'Aumentar'} className={`hidden sm:grid ${BTN}`}>
        <Icon name={grande ? 'minimize' : 'maximize'} size={15} />
      </button>
      <button type="button" onClick={onMinimizar} aria-label="Minimizar" title="Minimizar" className={BTN}><Icon name="chevron-down" size={15} /></button>
      <button type="button" onClick={onFechar} aria-label="Fechar conversa" title="Fechar" className={BTN}><Icon name="x" size={15} /></button>
    </>
  );

  if (minimizado) {
    return (
      <div className="fixed bottom-4 right-4 z-[1000] flex items-center gap-2 rounded-[var(--r-pill)] border border-[var(--border-strong)] bg-[var(--surface-2)] pl-3 pr-1 py-1 shadow-[var(--shadow-overlay)]" role="region" aria-label="Conversa minimizada">
        <Icon name="message" size={14} className="text-[var(--fg-3)]" />
        <button type="button" onClick={onMinimizar} className="max-w-[200px] truncate text-sm font-medium text-[var(--fg)]" title="Abrir conversa">
          {contato?.nome ?? 'Conversa'}{conversa && conversa.naoLidas > 0 ? ` (${conversa.naoLidas})` : ''}
        </button>
        <button type="button" onClick={onMinimizar} aria-label="Maximizar" title="Maximizar" className="w-7 h-7 grid place-items-center rounded-full text-[var(--fg-2)] hover:bg-[var(--surface-3)]"><Icon name="chevron-up" size={14} /></button>
        <button type="button" onClick={onFechar} aria-label="Fechar conversa" title="Fechar" className="w-7 h-7 grid place-items-center rounded-full text-[var(--fg-2)] hover:bg-[var(--surface-3)]"><Icon name="x" size={14} /></button>
      </div>
    );
  }

  return (
    <>
      <div
        role="dialog"
        aria-label={`Conversa com ${contato?.nome ?? 'contato'}`}
        className={`fixed z-[1000] inset-0 sm:inset-auto sm:bottom-4 sm:right-4 sm:rounded-[var(--r-lg)] shadow-[var(--shadow-overlay)] bg-[var(--surface-1)] ${
          grande ? 'sm:w-[min(760px,calc(100vw-2rem))] sm:h-[min(820px,calc(100dvh-2rem))]' : 'sm:w-[420px] sm:h-[min(600px,calc(100dvh-2rem))]'
        }`}
      >
        {pronto ? (
          <PainelConversa
            contato={contato}
            conversa={conversa}
            negocio={abertos[0] ?? null}
            negociosDoContato={doContato}
            templates={rTemplates.dados!}
            canais={rCanais.dados!.canais}
            painelCanais={rCanais.dados!}
            sessao={sessao!}
            gestor={gestor}
            nomeDe={nomeDe}
            agora={agora}
            flash={flash}
            onAbrirNegocio={setNegocioAberto}
            onAgendar={setAgendar}
            onExcluida={(msg) => { flash(msg); onFechar(); recarregarSino(); }}
            extrasCabecalho={extras}
            compacto={!grande}
          />
        ) : (
          <Card className="h-full flex flex-col">
            <div className="flex justify-end gap-2 p-2 border-b border-[var(--border)]">{extras}</div>
            <div className="flex-1 grid place-items-center text-[var(--fg-3)]">
              {erro ? <EstadoErro mensagem={erro} onTentar={() => { void rContato.recarregar(); void rConversas.recarregar(); }} />
                : rContato.dados && !contato ? <Vazio titulo="Você não tem acesso a este lead. Peça ao dono ou a um gestor." icone="lock" />
                : <span className="inline-flex items-center gap-3 text-sm"><Spinner size={20} /> Abrindo conversa…</span>}
            </div>
          </Card>
        )}
      </div>
      {agendar && (
        <ModalAtividade
          onClose={() => setAgendar(null)}
          onConfirmar={async (tipo, titulo, venceEm) => {
            const r = await repo.criarAtividade({ negocioId: agendar.id, contatoId: agendar.contatoId, tipo, titulo, venceEm });
            if (!r.ok) { flash(r.msg ?? 'Não foi possível agendar.'); return; }
            flash(r.msg ?? 'Próximo passo agendado.');
            setAgendar(null);
            avisarMudanca();
          }}
        />
      )}
      {negocioAberto && <NegocioDrawer negocioId={negocioAberto} onClose={() => setNegocioAberto(null)} flash={flash} />}
    </>
  );
}
