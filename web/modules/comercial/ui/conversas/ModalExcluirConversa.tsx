'use client';

// Gestor exclui uma conversa (ex.: mensagem de teste). Exclusão lógica no banco (crm_excluir_conversa) pelo servidor,
// que também apaga os arquivos dela no bucket crm-midia. Motivo obrigatório: fica no registro de alterações.
import { useState } from 'react';
import { Button, FilterSelect, Modal, Textarea } from '@/shared/ui/components';
import { fetchJson } from '@/shared/ui/fetch-json';
import { Icon } from '@/shared/ui/icons';
import { MOTIVO_MAX, avisoExclusao, erroMotivoExclusao, type ConversaExcluivel } from '../../domain/excluir-conversa';
import { Campo } from '../comum';

export function ModalExcluirConversa({ nome, conversas, canalInicial, contarMensagens, rotuloCanal, onClose, onFeito }: {
  nome: string;
  conversas: ConversaExcluivel[];
  /** Número aberto na tela (a resposta sai por ele): vem escolhido. */
  canalInicial: string | null;
  contarMensagens: (canalId: string | null) => number;
  rotuloCanal: (canalId: string | null) => string;
  onClose: () => void;
  onFeito: (msg: string) => void;
}) {
  const [id, setId] = useState(() => (conversas.find((c) => c.canalId === canalInicial) ?? conversas[0])?.id ?? '');
  const [motivo, setMotivo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const escolhida = conversas.find((c) => c.id === id) ?? null;
  const n = escolhida ? contarMensagens(escolhida.canalId) : 0;

  async function confirmar() {
    if (!escolhida) { setErro('Escolha a conversa.'); return; }
    const e = erroMotivoExclusao(motivo);
    if (e) { setErro(e); return; }
    setSalvando(true);
    const r = await fetchJson<{ ok?: boolean; msg?: string; error?: string; midiasPendentes?: number }>('/api/comercial/conversas/excluir', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ conversaId: escolhida.id, motivo: motivo.trim() }),
    });
    setSalvando(false);
    if (!r.ok || !r.json?.ok) {
      setErro(r.json?.error ?? r.json?.msg ?? (r.status === 0 ? 'Sem conexão. Tente de novo.' : 'Não foi possível excluir a conversa.'));
      return;
    }
    const pend = r.json.midiasPendentes ?? 0;
    onFeito((r.json.msg ?? 'Conversa excluída.') + (pend ? ` ${pend} arquivo(s) ficaram para limpeza posterior.` : ''));
  }

  return (
    <Modal
      onClose={onClose}
      title={`Excluir conversa · ${nome}`}
      width="max-w-md"
      footer={<>
        {erro && <p role="alert" className="min-w-0 text-xs text-[var(--red)]">{erro}</p>}
        <span className="flex-1" />
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button size="sm" variant="danger" disabled={salvando || !escolhida} onClick={confirmar}><Icon name="trash" size={13} /> Excluir</Button>
      </>}
    >
      <div className="space-y-3">
        <p className="text-sm leading-relaxed text-[var(--fg-2)]">{avisoExclusao(n)}</p>
        {conversas.length > 1 && (
          <Campo rotulo="Conversa do número">
            <FilterSelect value={id} onChange={(e) => { setId(e.target.value); setErro(null); }} className="w-full" aria-label="Conversa do número">
              {conversas.map((c) => <option key={c.id} value={c.id}>{rotuloCanal(c.canalId)} · {contarMensagens(c.canalId)} mensagens</option>)}
            </FilterSelect>
          </Campo>
        )}
        <Campo rotulo="Motivo" dica="Fica no registro de alterações. Ex.: mensagem de teste.">
          <Textarea rows={2} maxLength={MOTIVO_MAX} value={motivo} autoFocus onChange={(e) => { setMotivo(e.target.value); setErro(null); }} />
        </Campo>
      </div>
    </Modal>
  );
}
