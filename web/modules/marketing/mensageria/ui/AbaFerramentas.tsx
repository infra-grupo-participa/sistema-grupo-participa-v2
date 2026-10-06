'use client';

// Aba Ferramentas: API (Sim / Em breve / Não, registro manual), custo mensal, responsável e se está ativa.
// Ferramenta não se apaga: desativa (ativa=false). Gravação via mkt_msg_ferramenta_salvar.
// Abaixo, a seção Preços (20261005o), que só busca quando esta aba é aberta.
import { useState } from 'react';
import { Button, DataTable, FilterSelect, Input, Modal, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  API_FERRAMENTA, ROTULO_API, centavosParaCampo, reaisParaCentavos,
  type ApiFerramenta, type Ferramenta,
} from '../domain/mensageria';
import { salvarFerramenta } from './mensageria-data';
import { BotaoLink, Campo, Custo, Erro, ErroCarga, Selo, Vazio, botaoTopo, tdNum, thCls, thNum } from './pecas';
import { SecaoPrecos } from './SecaoPrecos';

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

export function AbaFerramentas({ ferramentas, falhou, onGravou, ativo, versaoPrecos, onGravouPreco }: {
  ferramentas: Ferramenta[]; falhou: boolean; onGravou: (msg: string) => void;
  ativo: boolean; versaoPrecos: number; onGravouPreco: (msg: string) => void;
}) {
  const [editar, setEditar] = useState<Ferramenta | null | 'nova'>(null);
  const salvo = (msg: string) => { setEditar(null); onGravou(msg); };

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button className={botaoTopo} onClick={() => setEditar('nova')}><Icon name="plus" size={16} /> Cadastrar ferramenta</Button>
        <span className="text-sm text-[var(--fg-2)]">Ferramenta não se apaga. Para tirar de uso, desative.</span>
      </div>
      {falhou && <ErroCarga oque="as ferramentas" />}
      {!falhou && (ferramentas.length === 0 ? <Vazio titulo="Nenhuma ferramenta cadastrada" dica='Clique em "Cadastrar ferramenta" para incluir a primeira.' /> : (
        <DataTable minWidth={860}>
          <Thead>
            {['Ferramenta', 'API', 'Custo mensal', 'Responsável', 'Situação', 'Observação', 'Ações'].map((c) => <Th key={c} className={c === 'Custo mensal' ? thNum : thCls}>{c}</Th>)}
          </Thead>
          <tbody>
            {ferramentas.map((x) => (
              <Tr key={x.id}>
                <Td className="whitespace-nowrap font-semibold">{x.nome}</Td>
                <Td className="whitespace-nowrap">{ROTULO_API[x.api as ApiFerramenta] ?? x.api}</Td>
                <Td className={tdNum}><Custo c={x.custo_mensal_centavos} /></Td>
                <Td>{x.responsavel ?? <span className="text-[var(--fg-2)]">—</span>}</Td>
                <Td>{x.ativa ? <Selo tom="ok">Ativa</Selo> : <Selo tom="apagado">Desativada</Selo>}</Td>
                <Td className="max-w-[280px]"><span className="line-clamp-2 break-words text-[var(--fg-2)]">{x.obs ?? ''}</span></Td>
                <Td><BotaoLink onClick={() => setEditar(x)} aria-label={`Editar ${x.nome}`}>Editar</BotaoLink></Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      ))}
      {editar && <ModalFerramenta inicial={editar === 'nova' ? null : editar} onFechar={() => setEditar(null)} onSalvo={salvo} />}
      <SecaoPrecos ferramentas={ferramentas} ativo={ativo} versao={versaoPrecos} onGravou={onGravouPreco} />
    </div>
  );
}
