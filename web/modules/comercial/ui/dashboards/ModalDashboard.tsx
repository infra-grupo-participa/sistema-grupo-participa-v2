'use client';

// Novo dashboard (nome, descrição, compartilhar, começar de um modelo) e renomear (sem modelo).
import { useState } from 'react';
import { Button, Input, Modal, Toggle } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { Campo } from '../comum';
import { MODELOS, type ModeloKey } from './layout';

export interface FormDashboard {
  nome: string;
  descricao: string;
  compartilhado: boolean;
  modelo: ModeloKey | null;
}

export function ModalDashboard({ modo, inicial, salvando, onCancelar, onSalvar }: {
  modo: 'novo' | 'renomear';
  inicial: FormDashboard;
  salvando: boolean;
  onCancelar: () => void;
  onSalvar: (f: FormDashboard) => void;
}) {
  const [f, setF] = useState<FormDashboard>(inicial);
  const [tentou, setTentou] = useState(false);
  const erro = !f.nome.trim() ? 'Dê um nome ao dashboard.' : f.nome.trim().length > 60 ? 'Nome com no máximo 60 caracteres.' : null;

  const escolherModelo = (k: ModeloKey | null) => setF((x) => {
    // Nome ainda vazio ou igual ao de outro modelo: acompanha o modelo escolhido.
    const nomeDeModelo = !x.nome.trim() || MODELOS.some((m) => m.nome === x.nome.trim());
    const m = MODELOS.find((y) => y.key === k);
    return { ...x, modelo: k, nome: nomeDeModelo ? m?.nome ?? '' : x.nome, descricao: nomeDeModelo && m ? m.descricao : x.descricao };
  });

  const confirmar = () => {
    setTentou(true);
    if (!erro) onSalvar({ ...f, nome: f.nome.trim(), descricao: f.descricao.trim() });
  };

  return (
    <Modal
      onClose={onCancelar}
      title={modo === 'novo' ? 'Novo dashboard' : 'Renomear dashboard'}
      width={modo === 'novo' ? 'max-w-2xl' : 'max-w-md'}
      footer={<>
        <Button size="sm" variant="ghost" onClick={onCancelar}>Cancelar</Button>
        <Button size="sm" onClick={confirmar} disabled={salvando}>
          {salvando ? 'Salvando…' : modo === 'novo' ? (f.modelo ? 'Criar com o modelo' : 'Criar e montar') : 'Salvar'}
        </Button>
      </>}
    >
      <form className="space-y-4" onSubmit={(e) => { e.preventDefault(); confirmar(); }}>
        {modo === 'novo' && (
          <fieldset>
            <legend className="mb-2 text-xs font-medium text-[var(--fg-2)]">Começar de</legend>
            <div role="radiogroup" aria-label="Começar de" className="grid gap-2 sm:grid-cols-2">
              <OpcaoModelo ativo={f.modelo == null} icone="plus" nome="Em branco" descricao="Grade vazia: você arrasta as métricas que quiser."
                onClick={() => escolherModelo(null)} />
              {MODELOS.map((m) => (
                <OpcaoModelo key={m.key} ativo={f.modelo === m.key} icone={m.icone} nome={m.nome} descricao={m.descricao}
                  onClick={() => escolherModelo(m.key)} />
              ))}
            </div>
          </fieldset>
        )}
        <Campo rotulo="Nome" dica={tentou && erro ? <span className="text-[var(--red)]">{erro}</span> : undefined}>
          <Input value={f.nome} maxLength={60} autoFocus placeholder="Ex.: Semana do time" onChange={(e) => setF((x) => ({ ...x, nome: e.target.value }))} />
        </Campo>
        <Campo rotulo="Descrição" extra={<span className="text-[var(--fg-3)]">opcional</span>}>
          <Input value={f.descricao} maxLength={160} placeholder="Para que serve este dashboard" onChange={(e) => setF((x) => ({ ...x, descricao: e.target.value }))} />
        </Campo>
        <div className="flex items-start justify-between gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
          <div className="min-w-0">
            <p className="text-sm font-medium text-[var(--fg)]">Compartilhar com o time</p>
            <p className="text-[11px] leading-relaxed text-[var(--fg-3)]">Todo mundo do Comercial vê. Só você e o gestor editam.</p>
          </div>
          <Toggle checked={f.compartilhado} onChange={(v) => setF((x) => ({ ...x, compartilhado: v }))} label="Compartilhar" />
        </div>
        <button type="submit" hidden aria-hidden tabIndex={-1} />
      </form>
    </Modal>
  );
}

function OpcaoModelo({ ativo, icone, nome, descricao, onClick }: { ativo: boolean; icone: string; nome: string; descricao: string; onClick: () => void }) {
  return (
    <button
      type="button" role="radio" aria-checked={ativo} onClick={onClick}
      className={`flex items-start gap-2.5 rounded-[var(--r-md)] border p-3 text-left transition-colors ${
        ativo ? 'border-[var(--border-accent)] bg-[var(--surface-3)]' : 'border-[var(--border)] hover:bg-[var(--surface-3)]'
      }`}
    >
      <span className="grid w-7 h-7 shrink-0 place-items-center rounded-[var(--r-sm)] bg-[var(--surface-3)] text-[var(--fg-2)]"><Icon name={icone} size={14} /></span>
      <span className="min-w-0">
        <span className="block text-sm font-semibold text-[var(--fg)]">{nome}</span>
        <span className="block text-[11px] leading-relaxed text-[var(--fg-3)]">{descricao}</span>
      </span>
    </button>
  );
}
