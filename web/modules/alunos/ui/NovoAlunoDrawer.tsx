'use client';

import { useCallback } from 'react';
import type { Aluno360 } from '../domain/aluno-360';
import type { Turma } from './alunos-data';
import { AlunoForm } from './AlunoForm';
import { Drawer } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';

/** Cadastro manual de aluno na base THB — mesma ficha da edição, em branco. */
export function NovoAlunoDrawer({ turmas, alunos, onClose, onCreated }: {
  turmas: Turma[];
  /** Base já carregada — usada só para avisar de e-mail duplicado antes do INSERT. */
  alunos: Aluno360[];
  onClose: () => void;
  onCreated: (msg: string, novoId?: string) => void;
}) {
  const emailJaCadastrado = useCallback(
    (email: string) => {
      const e = email.trim().toLowerCase();
      const hit = alunos.find((a) => (a.email || '').trim().toLowerCase() === e);
      return hit ? hit.nome || hit.email || 'aluno sem nome' : null;
    },
    [alunos],
  );

  return (
    <Drawer
      onClose={onClose}
      title="Novo aluno"
      subtitle="Cadastro manual na base THB"
      avatar={<span className="grid place-items-center w-10 h-10 rounded-full bg-[var(--accent-subtle)] text-[var(--accent)]"><Icon name="plus" size={18} /></span>}
      width="max-w-5xl"
    >
      <AlunoForm a={null} turmas={turmas} emailJaCadastrado={emailJaCadastrado} onSaved={onCreated} />
    </Drawer>
  );
}
