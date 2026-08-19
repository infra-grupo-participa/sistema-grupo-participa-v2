'use client';

// Mapa de ofertas de cobrança do saldo. `categoria` é read-only (legado que
// mente para 3 ofertas — nunca editar); `papel` é o único campo editável.
// fn_fin_oferta_salvar pode não estar aplicada em produção ainda — a UI fica
// pronta e o erro de rede aparece visível no toast (nunca falha em silêncio).
import { useState } from 'react';
import { Badge, Button, DataTable, EmptyState, Loading, SectionCard, Td, Th, Thead, Tr, useFlash, Toast } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL } from '@/shared/ui/format';
import type { Oferta } from '../domain/types';
import type { FinanceiroRepository } from '../application/ports';

export function Ofertas({ ofertas, loading, repo, canEdit, onSalvo }: {
  ofertas: Oferta[];
  loading: boolean;
  repo: FinanceiroRepository;
  canEdit: boolean;
  onSalvo: () => void;
}) {
  const { toast, flash } = useFlash();
  const [editando, setEditando] = useState<string | null>(null);
  const [papel, setPapel] = useState('');
  const [salvando, setSalvando] = useState(false);

  const salvar = async (codigo: string) => {
    setSalvando(true);
    try {
      const r = await repo.salvarOfertaPapel(codigo, papel.trim());
      flash(r.msg || (r.ok ? 'Feito!' : 'Falhou.'));
      if (r.ok) { setEditando(null); onSalvo(); }
    } catch {
      flash('Não foi possível salvar (erro de rede).');
    } finally {
      setSalvando(false);
    }
  };

  return (
    <SectionCard
      title="Ofertas de cobrança do saldo"
      subtitle="Ofertas Hotmart usadas para cobrar o saldo do pacote. Copie o link da oferta combinada e envie ao aluno."
    >
      {loading ? (
        <Loading label="Carregando ofertas…" minHeight={160} />
      ) : !ofertas.length ? (
        <EmptyState title="Nenhuma oferta cadastrada" icon="banknote" />
      ) : (
        <DataTable>
          <Thead>
            <Th>Código</Th>
            <Th>Valor</Th>
            <Th>Tipo</Th>
            <Th>Usos</Th>
            <Th>Link</Th>
            <Th>Papel</Th>
          </Thead>
          <tbody>
            {ofertas.map((o) => (
              <Tr key={o.codigo}>
                <Td>
                  <span className="font-semibold text-[var(--fg)] tabular">{o.codigo}</span>
                  {!o.ativo && <span className="ml-2 align-middle inline-flex"><Badge tone="danger">Inativa</Badge></span>}
                </Td>
                <Td className="tabular text-[var(--fg)]">{fmtBRL(o.valor)}</Td>
                <Td><Badge tone={o.recorrente ? 'info' : 'neutral'}>{o.recorrente ? 'Recorrente' : 'À vista'}</Badge></Td>
                <Td className="tabular text-[var(--fg-2)]">{o.usos}</Td>
                <Td>
                  {o.link ? (
                    <Button size="sm" variant="ghost" onClick={() => { navigator.clipboard?.writeText(o.link); flash('Link copiado.'); }}>
                      <Icon name="copy" size={13} /> Copiar link
                    </Button>
                  ) : '—'}
                </Td>
                <Td>
                  {editando === o.codigo ? (
                    <div className="flex items-center gap-1.5">
                      <input
                        autoFocus
                        value={papel}
                        onChange={(e) => setPapel(e.target.value)}
                        placeholder="papel da oferta"
                        className="w-32 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]"
                      />
                      <Button size="sm" onClick={() => salvar(o.codigo)} disabled={salvando}>Salvar</Button>
                      <Button size="sm" variant="ghost" onClick={() => setEditando(null)}>Cancelar</Button>
                    </div>
                  ) : (
                    <div className="flex items-center gap-1.5">
                      <span className="text-[var(--fg-2)]">{o.papel ?? '—'}</span>
                      {canEdit && (
                        <Button size="sm" variant="ghost" onClick={() => { setEditando(o.codigo); setPapel(o.papel ?? ''); }} title="fn_fin_oferta_salvar pode ainda não existir em produção">
                          <Icon name="pencil" size={12} />
                        </Button>
                      )}
                    </div>
                  )}
                </Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      )}
      <Toast>{toast}</Toast>
    </SectionCard>
  );
}
