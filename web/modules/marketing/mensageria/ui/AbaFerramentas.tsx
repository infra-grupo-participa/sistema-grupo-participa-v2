'use client';

// Aba Ferramentas: API (Sim / Em breve / Não, registro manual), custo mensal, responsável e se está ativa.
// Ferramenta não se apaga: desativa (ativa=false). Gravação via mkt_msg_ferramenta_salvar.
import { useState } from 'react';
import { Button, DataTable, EmptyState, FilterSelect, Input, Modal, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  API_FERRAMENTA, ROTULO_API, centavosParaCampo, reaisParaCentavos,
  type ApiFerramenta, type Ferramenta,
} from '../domain/mensageria';
import { salvarFerramenta } from './mensageria-data';
import { Campo, Custo, Erro, thCls } from './pecas';

function ModalFerramenta({ inicial, onFechar, onSalvo }: { inicial: Ferramenta | null; onFechar: () => void; onSalvo: (msg: string) => void }) {
  const [f, setF] = useState(() => ({
    nome: inicial?.nome ?? '', api: inicial?.api ?? 'nao', custo: centavosParaCampo(inicial?.custo_mensal_centavos),
    responsavel: inicial?.responsavel ?? '', ativa: inicial?.ativa ?? true, obs: inicial?.obs ?? '',
  }));
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF((x) => ({ ...x, [k]: v }));

  async function salvar() {
    const c = reaisParaCentavos(f.custo);
    setSalvando(true);
    const r = await salvarFerramenta({
      ...(inicial ? { id: inicial.id } : {}),
      nome: f.nome, api: f.api, custo_mensal_centavos: c === undefined ? f.custo.trim() : c,
      responsavel: f.responsavel || null, ativa: f.ativa, obs: f.obs || null,
    });
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title={inicial ? `Editar ${inicial.nome}` : 'Cadastrar ferramenta'}
      width="max-w-xl"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : inicial ? 'Salvar' : 'Cadastrar'}</Button>
      </>}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Nome"><Input value={f.nome} onChange={(e) => set('nome', e.target.value)} maxLength={60} /></Campo>
        <Campo rotulo="Tem API?">
          <FilterSelect value={f.api} onChange={(e) => set('api', e.target.value)}>
            {API_FERRAMENTA.map((a) => <option key={a} value={a}>{ROTULO_API[a]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Custo mensal R$" dica="vazio = não lançado">
          <Input value={f.custo} onChange={(e) => set('custo', e.target.value)} inputMode="decimal" placeholder="ex.: 297,00" />
        </Campo>
        <Campo rotulo="Responsável"><Input value={f.responsavel} onChange={(e) => set('responsavel', e.target.value)} maxLength={80} /></Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo>
        </div>
        <Toggle checked={f.ativa} onChange={(v) => set('ativa', v)} label="Ativa (aparece para novos disparos)" />
      </div>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

export function AbaFerramentas({ ferramentas, falhou, onGravou }: { ferramentas: Ferramenta[]; falhou: boolean; onGravou: (msg: string) => void }) {
  const [editar, setEditar] = useState<Ferramenta | null | 'nova'>(null);
  const salvo = (msg: string) => { setEditar(null); onGravou(msg); };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button onClick={() => setEditar('nova')}><Icon name="plus" size={16} /> Cadastrar ferramenta</Button>
        <span className="text-sm text-[var(--fg-2)]">Ferramenta não se apaga. Para tirar de uso, desative.</span>
      </div>
      {falhou && <Erro msg="Não foi possível carregar as ferramentas (erro de rede ou sem acesso)." />}
      {!falhou && (ferramentas.length === 0 ? <EmptyState title="Nenhuma ferramenta cadastrada" /> : (
        <DataTable minWidth={860}>
          <Thead>
            {['Ferramenta', 'API', 'Custo mensal', 'Responsável', 'Situação', 'Observação', 'Ações'].map((c) => <Th key={c} className={thCls}>{c}</Th>)}
          </Thead>
          <tbody>
            {ferramentas.map((x) => (
              <Tr key={x.id} className={x.ativa ? '' : 'opacity-60'}>
                <Td className="whitespace-nowrap font-semibold">{x.nome}</Td>
                <Td className="whitespace-nowrap">{ROTULO_API[x.api as ApiFerramenta] ?? x.api}</Td>
                <Td><Custo c={x.custo_mensal_centavos} /></Td>
                <Td>{x.responsavel ?? <span className="text-[var(--fg-2)]">—</span>}</Td>
                <Td>{x.ativa ? 'Ativa' : 'Desativada'}</Td>
                <Td className="max-w-[280px]"><span className="line-clamp-2 break-words">{x.obs ?? ''}</span></Td>
                <Td><Button variant="link" onClick={() => setEditar(x)}>Editar</Button></Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      ))}
      {editar && <ModalFerramenta inicial={editar === 'nova' ? null : editar} onFechar={() => setEditar(null)} onSalvo={salvo} />}
    </div>
  );
}
