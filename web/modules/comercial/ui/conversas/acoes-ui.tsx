'use client';

// Modais das ações da conversa (migration 20261009153515): editar e apagar mensagem, agendar mensagem, nota.
// Regras em domain/acoes-mensagem.ts e domain/agendamento.ts; o banco confere de novo e manda.
import { useMemo, useRef, useState } from 'react';
import { Button, FilterSelect, Input, Modal, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { amanha9h, emUmaHora, motivoNaoAgendar, paraInputLocal } from '../../domain/agendamento';
import { rotuloCanal, type CanalWhatsapp } from '../../domain/canais-whatsapp';
import { rotuloProvedor } from '../../domain/nova-conversa';
import type { Contato, Mensagem, Template } from '../../domain/types';
import { Campo, Chip, NotaRodape } from '../comum';
import { avisarMudanca, repo } from '../repositorio';
import { LIMITE_EDITAR_MIN } from '../../domain/acoes-mensagem';
import { criarTravaEnvio, preencherTemplate, primeiroNome } from './regras-conversas';

/** Editar mensagem enviada (só QR, até 15 min). */
export function ModalEditarMensagem({ m, onClose, flash }: { m: Mensagem; onClose: () => void; flash: (s: string) => void }) {
  const [texto, setTexto] = useState(m.texto);
  const [salvando, setSalvando] = useState(false);
  const mudou = texto.trim() !== m.texto.trim() && !!texto.trim();
  const salvar = async () => {
    if (!mudou || salvando) return;
    setSalvando(true);
    const r = await repo.editarMensagem(m.id, texto.trim());
    setSalvando(false);
    flash(r.ok ? r.msg ?? 'Edição a caminho do WhatsApp.' : r.msg ?? 'Não foi possível editar.');
    if (r.ok) { avisarMudanca(); onClose(); }
  };
  return (
    <Modal
      onClose={onClose}
      title="Editar mensagem"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!mudou || salvando} onClick={salvar}>Salvar edição</Button>
      </>}
    >
      <Campo rotulo="Texto">
        <Textarea rows={4} autoFocus value={texto} onChange={(e) => setTexto(e.target.value)} aria-label="Texto da mensagem" />
      </Campo>
      <NotaRodape>O WhatsApp deixa editar até {LIMITE_EDITAR_MIN} minutos depois do envio. O contato vê &quot;editada&quot;.</NotaRodape>
    </Modal>
  );
}

/** Apagar para todos (só QR, até 2 dias). */
export function ModalApagarMensagem({ m, onClose, flash }: { m: Mensagem; onClose: () => void; flash: (s: string) => void }) {
  const [apagando, setApagando] = useState(false);
  const apagar = async () => {
    if (apagando) return;
    setApagando(true);
    const r = await repo.apagarMensagem(m.id);
    setApagando(false);
    flash(r.ok ? r.msg ?? 'Apagando para todos.' : r.msg ?? 'Não foi possível apagar.');
    if (r.ok) { avisarMudanca(); onClose(); }
  };
  return (
    <Modal
      onClose={onClose}
      title="Apagar para todos?"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button variant="danger" size="sm" disabled={apagando} onClick={apagar}>Apagar para todos</Button>
      </>}
    >
      <p className="text-sm text-[var(--fg-2)]">
        A mensagem some do WhatsApp do contato e fica como &quot;Mensagem apagada&quot; aqui. Não tem como desfazer.
      </p>
      <blockquote className="mt-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)] whitespace-pre-wrap break-words">
        {m.texto}
      </blockquote>
    </Modal>
  );
}

/** Nota interna rápida (mesmo fluxo da linha do tempo do negócio: crm_adicionar_nota). */
export function ModalNota({ contatoId, negocioId, onClose, flash }: { contatoId: string; negocioId: string | null; onClose: () => void; flash: (s: string) => void }) {
  const [nota, setNota] = useState('');
  const [salvando, setSalvando] = useState(false);
  const salvar = async () => {
    if (!nota.trim() || salvando) return;
    setSalvando(true);
    const r = await repo.adicionarNota(contatoId, negocioId, nota.trim());
    setSalvando(false);
    flash(r.ok ? r.msg ?? 'Nota registrada.' : r.msg ?? 'Não foi possível registrar.');
    if (r.ok) { avisarMudanca(); onClose(); }
  };
  return (
    <Modal
      onClose={onClose}
      title="Adicionar nota"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!nota.trim() || salvando} onClick={salvar}>Registrar</Button>
      </>}
    >
      <Textarea aria-label="Nota interna" rows={3} autoFocus placeholder="Nota interna (objeção, combinado, contexto)…" value={nota} onChange={(e) => setNota(e.target.value)} />
      <NotaRodape>A nota é interna: o contato não vê.</NotaRodape>
    </Modal>
  );
}

/**
 * Agendar mensagem: entra na fila do envio com a hora marcada. No oficial, texto livre só se a janela de 24 h ainda
 * estiver aberta na hora; senão, template aprovado. A fila revalida tudo na hora e avisa o dono se falhar.
 */
export function ModalAgendarMensagem({ contato, canais, canalInicial, janelaAteEm, templates, remetente, agora, onClose, flash }: {
  contato: Contato; canais: CanalWhatsapp[]; canalInicial: string | null; janelaAteEm: string | null; templates: Template[];
  remetente: string; agora: Date; onClose: () => void; flash: (s: string) => void;
}) {
  const [canalId, setCanalId] = useState(canalInicial ?? canais[0]?.id ?? '');
  const canal = canais.find((c) => c.id === canalId) ?? null;
  const oficial = canal?.provedor !== 'evolution';
  const aprovados = useMemo(() => templates.filter((t) => t.aprovado), [templates]);
  const [modo, setModo] = useState<'texto' | 'template'>('texto');
  const [templateId, setTemplateId] = useState(aprovados[0]?.id ?? '');
  const [texto, setTexto] = useState('');
  const [quando, setQuando] = useState(() => paraInputLocal(emUmaHora(agora)));
  const [salvando, setSalvando] = useState(false);
  const trava = useRef(criarTravaEnvio());
  const comTemplate = oficial && modo === 'template';
  const tpl = comTemplate ? aprovados.find((t) => t.id === templateId) ?? null : null;
  const previa = tpl ? preencherTemplate(tpl.texto, { nome: primeiroNome(contato.nome), vendedor: primeiroNome(remetente) }) : null;
  const data = quando ? new Date(quando) : null;
  const motivo = motivoNaoAgendar({ texto, quando: data, agora: new Date(), oficial, comTemplate, janelaAteEm: oficial ? janelaAteEm : null })
    ?? (comTemplate && (!tpl || (previa?.faltando.length ?? 0) > 0) ? 'Escolha um template sem variável faltando.' : null);

  const salvar = async () => {
    if (motivo || !data) return;
    const chave = trava.current.comecar(`${canalId}|${templateId}|${texto}|${quando}`);
    if (!chave) return;
    setSalvando(true);
    const r = await repo.agendarMensagem({
      contatoId: contato.id, texto: comTemplate ? '' : texto.trim(), enviarEm: data.toISOString(), canalId: canalId || null,
      templateId: comTemplate ? templateId : null, chave,
    });
    trava.current.terminar(r.ok);
    setSalvando(false);
    flash(r.ok ? r.msg ?? 'Mensagem agendada.' : r.msg ?? 'Não foi possível agendar.');
    if (r.ok) { avisarMudanca(); onClose(); }
  };

  return (
    <Modal
      onClose={onClose}
      title="Agendar mensagem"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!!motivo || salvando} onClick={salvar} title={motivo ?? undefined}><Icon name="clock" size={14} /> Agendar</Button>
      </>}
    >
      <div className="space-y-4">
        {canais.length > 1 && (
          <Campo rotulo="Número">
            <FilterSelect value={canalId} onChange={(e) => setCanalId(e.target.value)} aria-label="Número de envio" className="w-full">
              {canais.map((c) => <option key={c.id} value={c.id}>{rotuloCanal(c)} ({rotuloProvedor(c)})</option>)}
            </FilterSelect>
          </Campo>
        )}
        {oficial && (
          <div className="flex flex-wrap gap-1.5" role="group" aria-label="Conteúdo">
            <Chip ativo={modo === 'texto'} onClick={() => setModo('texto')}>Texto livre</Chip>
            <Chip ativo={modo === 'template'} onClick={() => setModo('template')}>Template aprovado</Chip>
          </div>
        )}
        {comTemplate ? (
          <Campo rotulo="Template">
            <FilterSelect value={templateId} onChange={(e) => setTemplateId(e.target.value)} aria-label="Template" className="w-full">
              {aprovados.map((t) => <option key={t.id} value={t.id}>{t.nome}</option>)}
            </FilterSelect>
            {previa && <p className="mt-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm whitespace-pre-wrap">{previa.texto}</p>}
          </Campo>
        ) : (
          <Campo rotulo="Mensagem">
            <Textarea rows={3} autoFocus value={texto} onChange={(e) => setTexto(e.target.value)} placeholder={`Mensagem para ${primeiroNome(contato.nome) || 'o lead'} (sem emoji)`} aria-label="Mensagem agendada" />
          </Campo>
        )}
        <Campo rotulo="Quando">
          <Input type="datetime-local" value={quando} onChange={(e) => setQuando(e.target.value)} aria-label="Data e hora do envio" />
          <div className="mt-2 flex flex-wrap gap-1.5">
            <Chip ativo={false} onClick={() => setQuando(paraInputLocal(emUmaHora(new Date())))}>Em 1h</Chip>
            <Chip ativo={false} onClick={() => setQuando(paraInputLocal(amanha9h(new Date())))}>Amanhã 9h</Chip>
          </div>
        </Campo>
        {motivo && <p className="text-xs text-[var(--fg-2)]" role="status">{motivo}</p>}
        <NotaRodape>
          Sai pela fila do CRM na hora marcada{oficial ? ', se a janela de 24 h ainda estiver aberta (template sai sempre)' : ''}. Se não sair, você é avisado no sino. Dá para cancelar antes.
        </NotaRodape>
      </div>
    </Modal>
  );
}
