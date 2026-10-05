'use client';

// Revisão de identidade: quando o sistema não tem certeza se é a mesma pessoa, ele NÃO junta sozinho. Uma pessoa decide:
// "é a mesma que…" (junta os registros, nada se perde) ou "são diferentes".
import { useEffect, useState } from 'react';
import { Badge, Button, EmptyState, Loading, SectionCard } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { ROTULO_MOTIVO } from '../domain/identidade';
import { ROTULO_SITUACAO, type RevisaoPendente } from '../domain/pessoas';
import { decidirRevisao, listarRevisoes } from '../infrastructure/comercial-data';

export function RevisaoPainel({ versao, podeEditar, onAbrirPessoa, flash, onMudou }: {
  versao: number; podeEditar: boolean; onAbrirPessoa: (id: string) => void; flash: (m: string) => void; onMudou: () => void;
}) {
  const [res, setRes] = useState<{ v: number; lista: RevisaoPendente[] | null } | null>(null);
  const [ocupado, setOcupado] = useState(false);

  useEffect(() => {
    let vivo = true;
    listarRevisoes().then((l) => { if (vivo) setRes({ v: versao, lista: l }); });
    return () => { vivo = false; };
  }, [versao]);

  async function decidir(id: number, decisao: 'mesma' | 'diferente', alvo: string | null) {
    setOcupado(true);
    const r = await decidirRevisao(id, decisao, alvo);
    setOcupado(false);
    flash(r.msg);
    if (r.ok) onMudou();
  }

  if (!res || res.v !== versao) return <Loading />;
  if (res.lista == null) return <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (erro de rede ou sem acesso).</p>;
  if (res.lista.length === 0) return <SectionCard><EmptyState title="Nada para revisar" hint="Quando um cadastro puder ser alguém que já existe, ele aparece aqui." icon="check" /></SectionCard>;

  return (
    <div className="space-y-3">
      {res.lista.map((r) => (
        <SectionCard key={r.id}
          title={<span className="flex flex-wrap items-center gap-2">{ROTULO_MOTIVO[r.motivo] ?? r.motivo} <Badge tone="warning">{fmtDataHora(r.criado_em)}</Badge></span>}
          subtitle="Pode ser a mesma pessoa. Abra as fichas para comparar antes de decidir.">
          <div className="grid gap-3 md:grid-cols-2 text-sm">
            <div className="rounded-[var(--r-md)] border border-[var(--border)] p-3">
              <div className="text-xs text-[var(--fg-3)] mb-1">Cadastro novo</div>
              <button type="button" className="font-semibold text-[var(--accent)] hover:underline" onClick={() => onAbrirPessoa(r.pessoa.id)}>
                {r.pessoa.nome ?? 'Sem nome'}
              </button>
              <div className="mt-1 flex gap-1">
                {r.pessoa.eh_aluno && <Badge tone="info">Aluno {r.pessoa.turma ?? ''}</Badge>}
                <Badge>{ROTULO_SITUACAO[r.pessoa.situacao]}</Badge>
              </div>
            </div>
            <div className="space-y-2">
              {r.candidatos.map((c) => (
                <div key={c.id} className="rounded-[var(--r-md)] border border-[var(--border)] p-3 flex items-center justify-between gap-2">
                  <div>
                    <div className="text-xs text-[var(--fg-3)]">Pode ser</div>
                    <button type="button" className="font-semibold text-[var(--accent)] hover:underline" onClick={() => onAbrirPessoa(c.id)}>{c.nome ?? 'Sem nome'}</button>
                    {c.eh_aluno && <span className="ml-2"><Badge tone="info">Aluno {c.turma ?? ''}</Badge></span>}
                  </div>
                  {podeEditar && <Button size="sm" variant="subtle" disabled={ocupado} onClick={() => decidir(r.id, 'mesma', c.id)}>É a mesma</Button>}
                </div>
              ))}
              {podeEditar && <div className="flex justify-end"><Button size="sm" variant="ghost" disabled={ocupado} onClick={() => decidir(r.id, 'diferente', null)}>São pessoas diferentes</Button></div>}
            </div>
          </div>
        </SectionCard>
      ))}
    </div>
  );
}
