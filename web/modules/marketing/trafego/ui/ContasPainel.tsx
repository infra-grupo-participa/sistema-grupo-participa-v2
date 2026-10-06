'use client';

// Cadastro das contas de anúncio (gerenciador Meta, conta Google Ads). A coleta (etapa 2) só aceita campanha de conta
// cadastrada aqui.
import { useEffect, useState } from 'react';
import {
  Badge, Button, DataTable, EmptyState, FilterSelect, Input, Loading, Modal, SectionCard, Td, Th, Thead, Toggle, Tr,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { DONOS, ROTULO_DONO, type ConfigTrafego, type Conta, type Dono } from '../domain/tipos';
import { listarContas, salvarConta, type ContaForm } from '../infrastructure/trafego-data';
import { SEM_DADO } from './formato';

const VAZIA: ContaForm = { plataforma: 'meta', conta_externa: '', nome: '', dono: 'grupo', cliente: '', moeda: 'BRL', ativa: true, obs: '' };

function ModalConta({ inicial, config, onFechar, onSalvo }: { inicial: ContaForm; config: ConfigTrafego; onFechar: () => void; onSalvo: (m: string) => void }) {
  const [f, setF] = useState<ContaForm>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof ContaForm>(k: K, v: ContaForm[K]) => setF((x) => ({ ...x, [k]: v }));

  async function salvar() {
    if (!f.conta_externa.trim()) { setErro('Informe o id da conta na plataforma.'); return; }
    if (f.nome.trim().length < 2) { setErro('Informe o nome da conta.'); return; }
    setSalvando(true);
    const r = await salvarConta(f);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  const campo = (rotulo: string, filho: React.ReactNode, dica?: string) => (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">{rotulo}{dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}</span>
      {filho}
    </label>
  );

  return (
    <Modal onClose={onFechar} title={f.id ? 'Editar conta de anúncio' : 'Nova conta de anúncio'} width="max-w-2xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
    </>}>
      <div className="grid gap-3 sm:grid-cols-2">
        {campo('Plataforma', (
          <FilterSelect value={f.plataforma} onChange={(e) => set('plataforma', e.target.value)}>
            {config.plataformas.map((p) => <option key={p.codigo} value={p.codigo}>{p.nome}</option>)}
          </FilterSelect>
        ))}
        {campo('Id da conta na plataforma', <Input value={f.conta_externa} onChange={(e) => set('conta_externa', e.target.value)} maxLength={44} />,
          f.plataforma === 'google' ? 'ex.: 123-456-7890' : 'com ou sem act_')}
        {campo('Nome', <Input value={f.nome} onChange={(e) => set('nome', e.target.value)} maxLength={120} />, 'como aparece no gerenciador')}
        {campo('De quem é', (
          <FilterSelect value={f.dono} onChange={(e) => set('dono', e.target.value as Dono)}>
            {DONOS.map((d) => <option key={d} value={d}>{ROTULO_DONO[d]}</option>)}
          </FilterSelect>
        ))}
        {f.dono !== 'grupo' && campo('Cliente', <Input value={f.cliente} onChange={(e) => set('cliente', e.target.value)} maxLength={120} />, 'nome do Diamante ou aluno Aurum')}
        {campo('Moeda', <Input value={f.moeda} onChange={(e) => set('moeda', e.target.value.toUpperCase())} maxLength={3} />, 'BRL')}
        <div className="sm:col-span-2">{campo('Observação', <Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} />)}</div>
        <Toggle checked={f.ativa} onChange={(v) => set('ativa', v)} label="Ativa" />
      </div>
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

export function ContasPainel({ config, flash, onMudou }: { config: ConfigTrafego; flash: (m: string) => void; onMudou: () => void }) {
  const [contas, setContas] = useState<Conta[] | null | undefined>(undefined);
  const [edit, setEdit] = useState<ContaForm | null>(null);
  const [versao, setVersao] = useState(0);

  useEffect(() => {
    let vivo = true;
    listarContas().then((c) => { if (vivo) setContas(c); });
    return () => { vivo = false; };
  }, [versao]);

  if (contas === undefined) return <Loading />;
  const plataforma = (c: string) => config.plataformas.find((p) => p.codigo === c)?.nome ?? c;

  return (
    <SectionCard
      title="Contas de anúncio"
      subtitle="A coleta Meta/Google (próxima etapa) só traz campanha de conta cadastrada aqui."
      right={<Button size="sm" onClick={() => setEdit({ ...VAZIA })}><Icon name="plus" size={14} /> Nova conta</Button>}
    >
      {!contas ? <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar as contas.</p>
        : contas.length === 0 ? <EmptyState title="Nenhuma conta cadastrada" /> : (
          <DataTable minWidth={820}>
            <Thead><Th>Plataforma</Th><Th>Id</Th><Th>Nome</Th><Th>De quem é</Th><Th>Cliente</Th><Th>Moeda</Th><Th>Campanhas</Th><Th>Situação</Th></Thead>
            <tbody>
              {contas.map((c) => (
                <Tr key={c.id} onClick={() => setEdit({
                  id: c.id, plataforma: c.plataforma, conta_externa: c.conta_externa, nome: c.nome, dono: c.dono, cliente: c.cliente ?? '',
                  moeda: c.moeda, ativa: c.ativa, obs: c.obs ?? '',
                })}>
                  <Td>{plataforma(c.plataforma)}</Td>
                  <Td><span className="font-mono text-xs">{c.conta_externa}</span></Td>
                  <Td>{c.nome}</Td>
                  <Td>{ROTULO_DONO[c.dono] ?? c.dono}</Td>
                  <Td>{c.cliente ?? (c.dono === 'grupo' ? '' : SEM_DADO)}</Td>
                  <Td>{c.moeda}</Td>
                  <Td>{c.campanhas}</Td>
                  <Td><Badge tone={c.ativa ? 'success' : 'neutral'}>{c.ativa ? 'Ativa' : 'Inativa'}</Badge></Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
      {edit && <ModalConta inicial={edit} config={config} onFechar={() => setEdit(null)} onSalvo={(m) => { setEdit(null); flash(m); setVersao((v) => v + 1); onMudou(); }} />}
    </SectionCard>
  );
}
