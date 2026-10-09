'use client';

// "Ligar" (versão leve): mostra nome e número antes de discar; "Ligar" abre tel: (o celular disca; no Mac, FaceTime/
// iPhone) e "Ligar pelo WhatsApp" abre wa.me (a ligação de voz é feita no app). Ao discar, cria a atividade "Ligação"
// (pendente de resultado) e pergunta o resultado: Atendeu / Não atendeu / Caixa postal → conclui a atividade.
// Sem permissão de escrita no contato, só os links (nada é registrado). Telefonia integrada: próxima etapa.
import { useState } from 'react';
import { Button, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { linkTel, linkWhatsapp, RESULTADOS_LIGACAO, tituloLigacao } from '../domain/ligacao';
import { fmtTelefone } from '../domain/regras';
import { Chip, NotaRodape } from './comum';
import { avisarMudanca, repo } from './repositorio';

type Alvo = { contatoId: string; nome: string; telefone: string | null; negocioId?: string | null };

export function BotaoLigar({ alvo, podeRegistrar, flash, compacto = false, className = '' }: {
  alvo: Alvo; podeRegistrar: boolean; flash: (s: string) => void; compacto?: boolean; className?: string;
}) {
  const [aberto, setAberto] = useState(false);
  const semNumero = !linkTel(alvo.telefone);
  return (
    <>
      <Button
        size="sm"
        variant="ghost"
        className={className}
        disabled={semNumero}
        onClick={() => setAberto(true)}
        aria-label="Ligar"
        title={semNumero ? 'Contato sem telefone' : `Ligar para ${fmtTelefone(alvo.telefone)}`}
      >
        <Icon name="phone" size={14} />{!compacto && <span>Ligar</span>}
      </Button>
      {aberto && <ModalLigar alvo={alvo} podeRegistrar={podeRegistrar} flash={flash} onClose={() => setAberto(false)} />}
    </>
  );
}

export function ModalLigar({ alvo, podeRegistrar, flash, onClose }: { alvo: Alvo; podeRegistrar: boolean; flash: (s: string) => void; onClose: () => void }) {
  const tel = linkTel(alvo.telefone);
  const wa = linkWhatsapp(alvo.telefone);
  const [atividadeId, setAtividadeId] = useState<string | null>(null);
  const [discou, setDiscou] = useState(false);
  const [res, setRes] = useState('');
  const [salvando, setSalvando] = useState(false);

  // Registra a ligação (pendente de resultado) ao discar; o link abre normalmente.
  const registrar = (via: 'telefone' | 'whatsapp') => {
    setDiscou(true);
    if (!podeRegistrar || atividadeId) return;
    void repo.criarAtividade({
      negocioId: alvo.negocioId ?? null, contatoId: alvo.contatoId, tipo: 'ligacao', titulo: tituloLigacao(alvo.nome, via),
      venceEm: new Date().toISOString(),
    }).then((r) => {
      if (r.ok && r.atividadeId) { setAtividadeId(r.atividadeId); avisarMudanca(); } else if (!r.ok) flash(r.msg ?? 'Não foi possível registrar a ligação.');
    });
  };

  const concluir = async () => {
    if (!atividadeId || !res || salvando) return;
    setSalvando(true);
    const r = await repo.concluirAtividade(atividadeId, res);
    setSalvando(false);
    flash(r.ok ? 'Ligação registrada.' : r.msg ?? 'Não foi possível registrar.');
    if (r.ok) { avisarMudanca(); onClose(); }
  };

  return (
    <Modal
      onClose={onClose}
      title={discou ? 'Como foi a ligação?' : 'Ligar'}
      width="max-w-md"
      footer={discou && atividadeId ? <>
        <Button variant="ghost" size="sm" onClick={onClose}>Depois</Button>
        <Button size="sm" disabled={!res || salvando} onClick={concluir}>Registrar resultado</Button>
      </> : <Button variant="ghost" size="sm" onClick={onClose}>{discou ? 'Fechar' : 'Cancelar'}</Button>}
    >
      <div className="space-y-4">
        <div>
          <div className="text-base font-semibold text-[var(--fg)]">{alvo.nome}</div>
          <div className="text-sm tabular text-[var(--fg-2)]">{fmtTelefone(alvo.telefone)}</div>
        </div>
        <div className="flex flex-wrap gap-2">
          {tel && (
            <a href={tel} onClick={() => registrar('telefone')}
               className="inline-flex items-center gap-2 rounded-[var(--r-md)] bg-[var(--accent)] px-3 py-2 text-sm font-semibold text-black hover:brightness-110">
              <Icon name="phone" size={15} /> Ligar
            </a>
          )}
          {wa && (
            <a href={wa} target="_blank" rel="noopener noreferrer" onClick={() => registrar('whatsapp')}
               className="inline-flex items-center gap-2 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2 text-sm font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
              <Icon name="message" size={15} /> Ligar pelo WhatsApp
            </a>
          )}
        </div>
        {discou && atividadeId && (
          <div>
            <span className="mb-1 block text-xs font-medium text-[var(--fg-2)]" id="lig-res">Resultado</span>
            <div className="flex flex-wrap gap-1.5" role="group" aria-labelledby="lig-res">
              {RESULTADOS_LIGACAO.map((r) => <Chip key={r} ativo={res === r} onClick={() => setRes(res === r ? '' : r)}>{r}</Chip>)}
            </div>
          </div>
        )}
        <NotaRodape>
          {podeRegistrar
            ? 'Ao discar, a ligação entra no histórico como atividade; o resultado fecha a atividade. "Depois" deixa ela pendente.'
            : 'Você só acompanha este contato: a ligação não é registrada no CRM.'}
          {' '}No celular disca direto; no Mac abre o FaceTime/iPhone. A ligação de voz do WhatsApp é feita pelo app.
        </NotaRodape>
      </div>
    </Modal>
  );
}
