'use client';

// Aba "Pacotes e checklist" da Central (migration 20261006a): o modelo de fases por tipo de lançamento (pacote da campanha,
// nasce vazio: o conteúdo não foi definido) e os itens manuais do checklist de montagem (por tipo de lançamento ou para
// todos). Editáveis aqui; o banco confere as listas.
import { useState } from 'react';
import { Badge, Button, DataTable, EmptyState, FilterSelect, Input, Modal, SectionCard, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_AVISO_CADASTRO, type ListasCadastro, type ModeloPacote } from '../domain/cadastro';
import type { ConfigTrafego, ItemChecklistConfig, Resposta } from '../domain/tipos';
import {
  apagarPacote, salvarItemChecklist, salvarPacote, type ItemChecklistForm, type PacoteForm,
} from '../infrastructure/trafego-data';

type Flash = (msg: string) => void;
const msg = (r: Resposta) => [r.msg, ...(r.avisos ?? []).map((a) => ROTULO_AVISO_CADASTRO[a] ?? a)].join(' ');

function Campo({ rotulo, dica, children }: { rotulo: string; dica?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">{rotulo}{dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}</span>
      {children}
    </label>
  );
}

function ModalPacote({ inicial, listas, config, onFechar, onSalvo }: {
  inicial: PacoteForm; listas: ListasCadastro; config: ConfigTrafego; onFechar: () => void; onSalvo: (m: string) => void;
}) {
  const [f, setF] = useState<PacoteForm>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const set = <K extends keyof PacoteForm>(k: K, v: PacoteForm[K]) => setF((x) => ({ ...x, [k]: v }));
  async function salvar() {
    if (!f.tipo_lancamento || !f.fase) { setErro('Escolha o tipo de lançamento e a fase.'); return; }
    const r = await salvarPacote(f);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(msg(r));
  }
  return (
    <Modal onClose={onFechar} title={f.id ? 'Editar fase do pacote' : 'Nova fase do pacote'} width="max-w-2xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar}>Salvar</Button>
    </>}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Tipo de lançamento">
          <FilterSelect value={f.tipo_lancamento} onChange={(e) => set('tipo_lancamento', e.target.value)}>
            <option value="">Escolha</option>
            {listas.tipos_lancamento.map((t) => <option key={t.codigo} value={t.codigo}>{t.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Fase">
          <FilterSelect value={f.fase} onChange={(e) => set('fase', e.target.value)}>
            <option value="">Escolha</option>
            {config.fases.map((x) => <option key={x.codigo} value={x.codigo}>{x.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="% da verba máxima" dica="opcional"><Input inputMode="decimal" value={f.pct_verba} onChange={(e) => set('pct_verba', e.target.value.replace(',', '.'))} /></Campo>
        <Campo rotulo="Duração (dias)" dica="opcional"><Input inputMode="numeric" value={f.dias} onChange={(e) => set('dias', e.target.value)} /></Campo>
        <Campo rotulo="Ordem"><Input inputMode="numeric" value={f.ordem} onChange={(e) => set('ordem', e.target.value)} /></Campo>
        <fieldset>
          <legend className="block text-xs font-medium text-[var(--fg-2)] mb-1">Objetivos esperados</legend>
          <div className="flex flex-wrap gap-3">
            {listas.objetivos.map((o) => (
              <label key={o} className="inline-flex items-center gap-1.5 text-sm text-[var(--fg-2)] cursor-pointer">
                <input type="checkbox" checked={f.objetivos.includes(o)}
                  onChange={() => set('objetivos', f.objetivos.includes(o) ? f.objetivos.filter((x) => x !== o) : [...f.objetivos, o])} />{o}
              </label>
            ))}
          </div>
        </fieldset>
        <div className="sm:col-span-2"><Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo></div>
      </div>
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

function ModalItem({ inicial, listas, onFechar, onSalvo }: { inicial: ItemChecklistForm; listas: ListasCadastro; onFechar: () => void; onSalvo: (m: string) => void }) {
  const [f, setF] = useState<ItemChecklistForm>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  async function salvar() {
    const r = await salvarItemChecklist(f);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }
  return (
    <Modal onClose={onFechar} title={f.id ? 'Editar item do checklist' : 'Novo item do checklist'} width="max-w-xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar}>Salvar</Button>
    </>}>
      <div className="grid gap-3">
        <Campo rotulo="O que precisa ficar pronto"><Input value={f.texto} onChange={(e) => setF({ ...f, texto: e.target.value })} maxLength={200} autoFocus /></Campo>
        <Campo rotulo="Vale para">
          <FilterSelect value={f.tipo_lancamento} onChange={(e) => setF({ ...f, tipo_lancamento: e.target.value })}>
            <option value="">Todos os tipos de lançamento</option>
            {listas.tipos_lancamento.map((t) => <option key={t.codigo} value={t.codigo}>{t.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Ordem"><Input inputMode="numeric" value={f.ordem} onChange={(e) => setF({ ...f, ordem: e.target.value })} /></Campo>
        <Toggle checked={f.ativo} onChange={(v) => setF({ ...f, ativo: v })} label="Ativo (desativar tira dos projetos sem apagar as marcas)" />
      </div>
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

export function PacoteChecklistPainel({ listas, config, flash, onMudou }: { listas: ListasCadastro | null; config: ConfigTrafego; flash: Flash; onMudou: () => void }) {
  const [pacote, setPacote] = useState<PacoteForm | null>(null);
  const [item, setItem] = useState<ItemChecklistForm | null>(null);
  if (!listas) {
    return <SectionCard><p role="alert" className="text-sm text-[var(--red)]">Indisponível (sem acesso, ou a migration 20261006a ainda não foi aplicada).</p></SectionCard>;
  }
  const nomeTipo = (c: string | null) => (c ? listas.tipos_lancamento.find((t) => t.codigo === c)?.nome ?? c : 'Todos');
  const nomeFase = (c: string) => config.fases.find((f) => f.codigo === c)?.nome ?? c;
  const salvo = (m: string) => { setPacote(null); setItem(null); flash(m); onMudou(); };
  const editarPacote = (m: ModeloPacote) => setPacote({ id: m.id, tipo_lancamento: m.tipo_lancamento, fase: m.fase, ordem: String(m.ordem),
    objetivos: [...m.objetivos], pct_verba: m.pct_verba == null ? '' : String(m.pct_verba), dias: m.dias == null ? '' : String(m.dias), obs: m.obs ?? '' });
  const editarItem = (i: ItemChecklistConfig) => setItem({ id: i.id, texto: i.texto, tipo_lancamento: i.tipo_lancamento ?? '', ordem: String(i.ordem), ativo: i.ativo });

  return (
    <div className="space-y-5">
      <SectionCard title="Pacote da campanha por tipo de lançamento"
        subtitle='As fases (e objetivos esperados, % da verba e duração) que o tipo de lançamento costuma ter. "Montar fases do pacote" na vida do projeto cria as que faltam. O conteúdo de cada pacote ainda não foi definido.'
        right={<Button size="sm" onClick={() => setPacote({ tipo_lancamento: '', fase: '', ordem: '1', objetivos: [], pct_verba: '', dias: '', obs: '' })}><Icon name="plus" size={14} /> Nova fase do pacote</Button>}>
        {listas.pacotes.length === 0 ? <EmptyState title="Nenhum pacote cadastrado" hint="O conteúdo de cada pacote está em aberto (pergunta ao Victor)." /> : (
          <DataTable minWidth={760}>
            <Thead><Th>Tipo de lançamento</Th><Th>Ordem</Th><Th>Fase</Th><Th>Objetivos</Th><Th>% da verba</Th><Th>Dias</Th><Th> </Th></Thead>
            <tbody>
              {listas.pacotes.map((m) => (
                <Tr key={m.id}>
                  <Td>{nomeTipo(m.tipo_lancamento)}</Td><Td>{m.ordem}</Td><Td>{nomeFase(m.fase)}</Td><Td>{m.objetivos.join(', ') || 'nenhum'}</Td>
                  <Td>{m.pct_verba ?? 'sem'}</Td><Td>{m.dias ?? 'sem'}</Td>
                  <Td><div className="flex gap-1">
                    <Button size="sm" variant="ghost" onClick={() => editarPacote(m)} aria-label="Editar"><Icon name="pencil" size={12} /></Button>
                    <Button size="sm" variant="danger" onClick={async () => { const r = await apagarPacote(m.id); flash(r.msg); if (r.ok) onMudou(); }} aria-label="Apagar"><Icon name="trash" size={12} /></Button>
                  </div></Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>

      <SectionCard title="Checklist de montagem: itens manuais"
        subtitle="O que o sistema não confere sozinho; na vida do projeto alguém marca quando fica pronto (guarda quem e quando). Os itens automáticos o banco confere."
        right={<Button size="sm" onClick={() => setItem({ texto: '', tipo_lancamento: '', ordem: '1', ativo: true })}><Icon name="plus" size={14} /> Novo item</Button>}>
        {listas.checklist_itens.length === 0 ? <EmptyState title="Nenhum item manual" /> : (
          <DataTable minWidth={640}>
            <Thead><Th>Item</Th><Th>Vale para</Th><Th>Ordem</Th><Th>Situação</Th><Th> </Th></Thead>
            <tbody>
              {listas.checklist_itens.map((i) => (
                <Tr key={i.id}>
                  <Td>{i.texto}</Td><Td>{nomeTipo(i.tipo_lancamento)}</Td><Td>{i.ordem}</Td>
                  <Td><Badge tone={i.ativo ? 'success' : 'neutral'}>{i.ativo ? 'Ativo' : 'Desativado'}</Badge></Td>
                  <Td><Button size="sm" variant="ghost" onClick={() => editarItem(i)} aria-label="Editar"><Icon name="pencil" size={12} /></Button></Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      </SectionCard>

      {pacote && <ModalPacote inicial={pacote} listas={listas} config={config} onFechar={() => setPacote(null)} onSalvo={salvo} />}
      {item && <ModalItem inicial={item} listas={listas} onFechar={() => setItem(null)} onSalvo={salvo} />}
    </div>
  );
}
