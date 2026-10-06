'use client';

// Cadastro rápido de contato: nome, telefone e e-mail. Antes de salvar confere a identidade do CRM
// (e-mail igual = mesma pessoa, bloqueia; mesmo final de telefone = possível duplicado, pede confirmação).
import { useMemo, useState } from 'react';
import { Button, Checkbox, Input, Modal } from '@/shared/ui/components';
import { fmtTelefone } from '../../domain/regras';
import type { Contato } from '../../domain/types';
import type { ComercialRepository, Resultado } from '../../application/ports';
import { avisarMudanca, repo } from '../repositorio';
import { Aviso, Campo, RodapeAcoes } from '../comum';
import { conflitosCadastro, validarNovoContato, type RascunhoContato } from './regras-contatos';

/** Escrita que o contrato ainda não tem. Quando `criarContato` entrar em ports.ts, este tipo some. */
type ComCadastro = ComercialRepository & {
  criarContato?: (c: RascunhoContato) => Promise<Resultado & { contatoId?: string }>;
};

export function ModalNovoContato({ contatos, nomeDe, onClose, onAbrirContato, onCriado }: {
  contatos: Contato[];
  nomeDe: (id: string | null) => string;
  onClose: () => void;
  onAbrirContato: (id: string) => void;
  /** `local`: a fonte ainda não grava contato; o cadastro vale só nesta tela. */
  onCriado: (r: { contatoId: string; local: Contato | null }) => void;
}) {
  const [r, setR] = useState<RascunhoContato>({ nome: '', telefone: '', email: '' });
  const [confirmaOutra, setConfirmaOutra] = useState(false);
  const [tentou, setTentou] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const invalido = validarNovoContato(r);
  const { mesmoEmail, mesmoTelefone } = useMemo(() => conflitosCadastro(r, contatos), [r, contatos]);
  const bloqueado = mesmoEmail.length > 0;
  const pedeConfirmacao = mesmoTelefone.length > 0 && !confirmaOutra;

  const mudar = (k: keyof RascunhoContato) => (e: React.ChangeEvent<HTMLInputElement>) => {
    setR((x) => ({ ...x, [k]: e.target.value }));
    setErro(null);
    if (k === 'telefone') setConfirmaOutra(false);
  };

  const salvar = async () => {
    setTentou(true);
    if (invalido || bloqueado || pedeConfirmacao) return;
    setSalvando(true);
    const fonte = repo as ComCadastro;
    if (fonte.criarContato) {
      const res = await fonte.criarContato({ nome: r.nome.trim(), telefone: r.telefone.trim(), email: r.email.trim() });
      setSalvando(false);
      if (!res.ok || !res.contatoId) { setErro(res.msg ?? 'Não foi possível salvar.'); return; }
      avisarMudanca();
      onCriado({ contatoId: res.contatoId, local: null });
      return;
    }
    // Demonstração: a fonte não grava contato. Mantém na tela para seguir o fluxo.
    const digitos = r.telefone.replace(/\D/g, '');
    const local: Contato = {
      id: `local-${Date.now()}`,
      nome: r.nome.trim(),
      email: r.email.trim() || null,
      telefone: digitos ? (digitos.length <= 11 ? `55${digitos}` : digitos) : null,
      cidade: null, uf: null, perfil: null, atuaComHolding: null, donoId: null, tags: [], utm: {},
      score: null, ehAluno: false, optOut: false, criadoEm: new Date().toISOString(),
    };
    setSalvando(false);
    onCriado({ contatoId: local.id, local });
  };

  const conflitos = bloqueado ? mesmoEmail : mesmoTelefone;

  return (
    <Modal
      onClose={onClose}
      title="Novo contato"
      footer={
        <RodapeAcoes
          secundario={<Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>}
          primario={(
            <Button size="sm" onClick={salvar} disabled={salvando || bloqueado}>
              {salvando ? 'Salvando…' : 'Salvar contato'}
            </Button>
          )}
        />
      }
    >
      <form
        className="space-y-4"
        onSubmit={(e) => { e.preventDefault(); salvar(); }}
        noValidate
      >
        <Campo rotulo="Nome">
          <Input autoFocus value={r.nome} onChange={mudar('nome')} autoComplete="off" />
        </Campo>
        <div className="grid gap-4 sm:grid-cols-2">
          <Campo rotulo="Telefone (com DDD)">
            <Input type="tel" inputMode="tel" value={r.telefone} onChange={mudar('telefone')} placeholder="(11) 98765-4321" autoComplete="off" />
          </Campo>
          <Campo rotulo="E-mail" dica="Telefone ou e-mail: pelo menos um.">
            <Input type="email" value={r.email} onChange={mudar('email')} autoComplete="off" />
          </Campo>
        </div>

        {conflitos.length > 0 && (
          <Aviso tom={bloqueado ? 'danger' : 'warning'} icone="alert">
            <span className="block font-medium text-[var(--fg)]">
              {bloqueado ? 'Esse e-mail já está no CRM: é a mesma pessoa.' : 'Possível duplicado: mesmo final de telefone.'}
            </span>
            <span className="mt-2 block space-y-1">
              {conflitos.map((c) => (
                <span key={c.id} className="flex flex-wrap items-center justify-between gap-2 text-xs text-[var(--fg-2)]">
                  <span className="min-w-0 truncate">{c.nome} · {fmtTelefone(c.telefone)} · {nomeDe(c.donoId)}</span>
                  <Button type="button" size="sm" variant="link" onClick={() => onAbrirContato(c.id)}>Abrir ficha</Button>
                </span>
              ))}
            </span>
            {!bloqueado && (
              <span className="mt-2 block">
                <Checkbox checked={confirmaOutra} onChange={setConfirmaOutra} label="É outra pessoa: cadastrar mesmo assim" />
              </span>
            )}
          </Aviso>
        )}

        {tentou && (invalido || pedeConfirmacao || erro) && (
          <p role="alert" className="text-xs text-[var(--red)]">
            {invalido ?? (pedeConfirmacao ? 'Confira o possível duplicado antes de salvar.' : erro)}
          </p>
        )}
        {/* Enter no formulário salva. */}
        <button type="submit" className="sr-only" tabIndex={-1} aria-hidden="true">Salvar</button>
      </form>
    </Modal>
  );
}
