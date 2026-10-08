'use client';

// Botão de anexar (clipe) da caixa de Conversas: imagem (JPG/PNG/WebP até 5 MB) ou PDF (até 16 MB), com pré-visualização
// e legenda. Só aparece com a janela de 24 h aberta (fora dela só sai template). O banco valida tudo de novo.
import { useEffect, useRef, useState } from 'react';
import { Button, Modal, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { LIMITE_LEGENDA, fmtTamanho, validarAnexo, type AnexoValido } from '../../domain/midia';
import { avisarMudanca, repo } from '../repositorio';
import { criarTravaEnvio } from './regras-conversas';

const ACEITA = 'image/jpeg,image/png,image/webp,application/pdf';

export function BotaoAnexar({ contatoId, nomeContato, desabilitado, flash }: {
  contatoId: string; nomeContato: string; desabilitado?: boolean; flash: (m: string) => void;
}) {
  const campo = useRef<HTMLInputElement>(null);
  const [arquivo, setArquivo] = useState<{ file: File; info: AnexoValido; previa: string | null } | null>(null);
  // URL local (blob:) da pré-visualização: criada na escolha, liberada ao fechar ou ao sair da tela
  const previaAtual = useRef<string | null>(null);
  useEffect(() => () => { if (previaAtual.current) URL.revokeObjectURL(previaAtual.current); }, []);

  const fechar = () => {
    if (previaAtual.current) URL.revokeObjectURL(previaAtual.current);
    previaAtual.current = null;
    setArquivo(null);
  };

  const escolher = (f: File | undefined) => {
    if (campo.current) campo.current.value = '';   // permite escolher o mesmo arquivo de novo
    if (!f) return;
    const v = validarAnexo(f);
    if (!v.ok) { flash(v.msg); return; }
    if (previaAtual.current) URL.revokeObjectURL(previaAtual.current);
    previaAtual.current = v.tipo === 'imagem' ? URL.createObjectURL(f) : null;
    setArquivo({ file: f, info: v, previa: previaAtual.current });
  };

  return (
    <>
      <input ref={campo} type="file" accept={ACEITA} className="hidden" onChange={(e) => escolher(e.target.files?.[0])} tabIndex={-1} aria-hidden="true" />
      <Button
        variant="ghost"
        size="md"
        className="!px-3"
        disabled={desabilitado}
        onClick={() => campo.current?.click()}
        aria-label="Anexar imagem ou PDF"
        title="Anexar imagem ou PDF"
      >
        <Icon name="paperclip" size={15} />
      </Button>
      {arquivo && (
        <ModalAnexo
          contatoId={contatoId}
          nomeContato={nomeContato}
          file={arquivo.file}
          info={arquivo.info}
          previa={arquivo.previa}
          flash={flash}
          onFechar={fechar}
        />
      )}
    </>
  );
}

function ModalAnexo({ contatoId, nomeContato, file, info, previa, flash, onFechar }: {
  contatoId: string; nomeContato: string; file: File; info: AnexoValido; previa: string | null; flash: (m: string) => void; onFechar: () => void;
}) {
  const [legenda, setLegenda] = useState('');
  const [enviando, setEnviando] = useState(false);
  // Trava síncrona contra duplo clique + chave de idempotência do banco (mesmo arquivo e legenda = mesma mensagem).
  const trava = useRef(criarTravaEnvio());

  const enviar = async () => {
    const chave = trava.current.comecar(`${file.name}|${file.size}|${file.lastModified}|${legenda}`);
    if (!chave) return;
    setEnviando(true);
    let r: Awaited<ReturnType<typeof repo.enviarAnexo>>;
    try { r = await repo.enviarAnexo(contatoId, file, legenda, chave); } catch { r = { ok: false, msg: 'Não foi possível enviar o arquivo.' }; }
    trava.current.terminar(r.ok);
    setEnviando(false);
    if (!r.ok) { flash(r.msg ?? 'Não foi possível enviar o arquivo.'); return; }
    flash(r.msg ?? 'Arquivo na fila de envio.');
    avisarMudanca();
    onFechar();
  };

  const longa = legenda.length > LIMITE_LEGENDA;
  return (
    <Modal
      onClose={() => { if (!enviando) onFechar(); }}
      title={`Enviar ${info.tipo === 'imagem' ? 'imagem' : 'PDF'} para ${nomeContato}`}
      width="max-w-lg"
      footer={(
        <>
          <Button variant="ghost" size="sm" onClick={onFechar} disabled={enviando}>Cancelar</Button>
          <Button size="sm" onClick={enviar} disabled={enviando || longa}>
            <Icon name="send" size={14} /> {enviando ? 'Enviando…' : 'Enviar'}
          </Button>
        </>
      )}
    >
      <div className="space-y-3">
        {info.tipo === 'imagem' ? (
          previa && (
            <div className="grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] p-2">
              {/* eslint-disable-next-line @next/next/no-img-element -- pré-visualização local (blob:) */}
              <img src={previa} alt={`Prévia de ${info.nome}`} className="block max-h-[45vh] w-auto max-w-full rounded-[var(--r-sm)]" />
            </div>
          )
        ) : (
          <div className="flex items-center gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2">
            <Icon name="file" size={22} className="shrink-0 text-[var(--fg-3)]" />
            <div className="min-w-0">
              <div className="truncate text-sm font-medium text-[var(--fg)]" title={info.nome}>{info.nome}</div>
              <div className="text-[11px] text-[var(--fg-3)] tabular">PDF · {fmtTamanho(file.size)}</div>
            </div>
          </div>
        )}
        {info.tipo === 'imagem' && <p className="text-[11px] text-[var(--fg-3)] tabular">{info.nome} · {fmtTamanho(file.size)}</p>}
        <div>
          <Textarea
            rows={3}
            value={legenda}
            onChange={(e) => setLegenda(e.target.value)}
            placeholder="Legenda (opcional, sem emoji)"
            aria-label="Legenda"
            className="!resize-none"
          />
          <div className={`mt-1 text-right text-[11px] tabular ${longa ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>
            {legenda.length.toLocaleString('pt-BR')}/{LIMITE_LEGENDA.toLocaleString('pt-BR')}
          </div>
        </div>
      </div>
    </Modal>
  );
}
