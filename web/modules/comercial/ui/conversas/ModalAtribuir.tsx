'use client';

// Gestor define o dono de uma conversa que caiu sem dono. Motivo obrigatório: fica na linha do tempo do contato.
import { useState } from 'react';
import { Button, FilterSelect, Modal, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Vendedor } from '../../domain/types';
import { Campo } from '../comum';
import { avisarMudanca, repo } from '../repositorio';

export function ModalAtribuir({ contatoId, nome, vendedores, onClose, onFeito }: {
  contatoId: string; nome: string; vendedores: Vendedor[];
  onClose: () => void; onFeito: (msg: string) => void;
}) {
  const opcoes = vendedores.filter((v) => v.ativo);
  const [donoId, setDonoId] = useState('');
  const [motivo, setMotivo] = useState('Conversa caiu sem dono na caixa.');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  async function confirmar() {
    if (!donoId) { setErro('Escolha o vendedor.'); return; }
    if (!motivo.trim()) { setErro('Escreva o motivo.'); return; }
    setSalvando(true);
    const r = await repo.atribuirContato(contatoId, donoId, motivo.trim());
    setSalvando(false);
    if (!r.ok) { setErro(r.msg ?? 'Não foi possível atribuir.'); return; }
    avisarMudanca();
    onFeito(r.msg ?? `Dono definido: ${vendedores.find((v) => v.id === donoId)?.nome ?? 'vendedor'}.`);
  }

  return (
    <Modal
      onClose={onClose}
      title={`Atribuir dono · ${nome}`}
      footer={<>
        {erro && <p role="alert" className="min-w-0 text-xs text-[var(--red)]">{erro}</p>}
        <span className="flex-1" />
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={salvando} onClick={confirmar}><Icon name="check" size={13} /> Atribuir</Button>
      </>}
    >
      <div className="space-y-3">
        <p className="text-xs leading-relaxed text-[var(--fg-3)]">
          O vendedor escolhido vira dono do contato e dos negócios abertos dele que estão sem dono. Só ele responde daqui em diante.
        </p>
        <Campo rotulo="Vendedor">
          <FilterSelect value={donoId} onChange={(e) => { setDonoId(e.target.value); setErro(null); }} className="w-full" aria-label="Vendedor">
            <option value="">Escolha…</option>
            {opcoes.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Motivo" dica="Fica registrado na linha do tempo do contato.">
          <Textarea rows={2} value={motivo} onChange={(e) => { setMotivo(e.target.value); setErro(null); }} />
        </Campo>
      </div>
    </Modal>
  );
}
