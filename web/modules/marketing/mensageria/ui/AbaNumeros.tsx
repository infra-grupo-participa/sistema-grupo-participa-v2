'use client';

// Aba Números: consumo de hoje (soma do log, feita pelo banco), status, finalidade, ferramenta e responsável.
// Cadastrar, editar e arquivar via mkt_msg_numero_salvar. A faixa 30–50/dia é só aviso de tela.
import { useState } from 'react';
import { Button, DataTable, FilterSelect, Input, Modal, ProgressBar, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import {
  CAPACIDADE_MAX, CAPACIDADE_MIN, FINALIDADES, ROTULO_FINALIDADE, ROTULO_STATUS_NUMERO, STATUS_NUMERO,
  capacidadeForaDaFaixa, dataBR, fmtNum, partesSP,
  type Ferramenta, type Finalidade, type Numero, type Resultado, type StatusNumero,
} from '../domain/mensageria';
import { salvarNumero, type NumeroForm } from './mensageria-data';
import { BotaoLink, Campo, Erro, ErroCarga, Selo, Vazio, botaoTopo, corAlerta, thCls, type TomSelo } from './pecas';

const TOM_STATUS: Record<StatusNumero, TomSelo> = { ativo: 'ok', aquecendo: 'aviso', restrito: 'alerta', disponivel: 'neutro' };

type Form = { id?: number; numero: string; projeto: string; frente: string; responsavel: string; finalidade: string; ferramenta_id: string; capacidade_dia: string; status: string; arquivado: boolean };

const paraForm = (n: Numero | null): Form => n ? {
  id: n.id, numero: n.numero, projeto: n.projeto ?? '', frente: n.frente ?? '', responsavel: n.responsavel, finalidade: n.finalidade,
  ferramenta_id: n.ferramenta_id == null ? '' : String(n.ferramenta_id), capacidade_dia: n.capacidade_dia == null ? '' : String(n.capacidade_dia),
  status: n.status, arquivado: !!n.arquivado_em,
} : { numero: '+55 ', projeto: '', frente: '', responsavel: '', finalidade: 'mensageria', ferramenta_id: '', capacidade_dia: '', status: 'aquecendo', arquivado: false };

const paraBanco = (f: Form): NumeroForm => ({
  ...(f.id ? { id: f.id } : {}),
  numero: f.numero, projeto: f.projeto || null, frente: f.frente || null, responsavel: f.responsavel, finalidade: f.finalidade,
  ferramenta_id: f.ferramenta_id || null, capacidade_dia: f.capacidade_dia.trim() || null, status: f.status, arquivado: f.arquivado,
});

function ModalNumero({ inicial, projetos, ferramentas, onFechar, onSalvo }: {
  inicial: Numero | null; projetos: Projeto[]; ferramentas: Ferramenta[]; onFechar: () => void; onSalvo: (msg: string) => void;
}) {
  const [f, setF] = useState<Form>(() => paraForm(inicial));
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((x) => ({ ...x, [k]: v }));
  const cap = /^\d+$/.test(f.capacidade_dia.trim()) ? Number(f.capacidade_dia) : null;

  async function salvar() {
    setSalvando(true);
    const r = await salvarNumero(paraBanco(f));
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title={inicial ? `Editar ${inicial.numero}` : 'Cadastrar número'}
      width="max-w-2xl"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : inicial ? 'Salvar' : 'Cadastrar'}</Button>
      </>}
    >
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Número" dica="com + e país">
          <Input value={f.numero} onChange={(e) => set('numero', e.target.value)} placeholder="+55 11 99999-0000" inputMode="tel" />
        </Campo>
        <Campo rotulo="Responsável"><Input value={f.responsavel} onChange={(e) => set('responsavel', e.target.value)} maxLength={80} /></Campo>
        <Campo rotulo="Projeto" dica="se for de um projeto">
          <FilterSelect value={f.projeto} onChange={(e) => set('projeto', e.target.value)}>
            <option value="">Nenhum</option>
            {projetos.map((p) => <option key={p.id} value={p.sigla}>{p.sigla} · {p.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Frente" dica="opcional"><Input value={f.frente} onChange={(e) => set('frente', e.target.value)} maxLength={60} /></Campo>
        <Campo rotulo="Finalidade">
          <FilterSelect value={f.finalidade} onChange={(e) => set('finalidade', e.target.value)}>
            {FINALIDADES.map((x) => <option key={x} value={x}>{ROTULO_FINALIDADE[x]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Status">
          <FilterSelect value={f.status} onChange={(e) => set('status', e.target.value)}>
            {STATUS_NUMERO.map((x) => <option key={x} value={x}>{ROTULO_STATUS_NUMERO[x]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Ferramenta" dica="opcional">
          <FilterSelect value={f.ferramenta_id} onChange={(e) => set('ferramenta_id', e.target.value)}>
            <option value="">Nenhuma</option>
            {ferramentas.map((x) => <option key={x.id} value={x.id}>{x.nome}{x.ativa ? '' : ' (desativada)'}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Capacidade por dia" dica={`recomendado ${CAPACIDADE_MIN} a ${CAPACIDADE_MAX}`}>
          <Input value={f.capacidade_dia} onChange={(e) => set('capacidade_dia', e.target.value)} inputMode="numeric" />
        </Campo>
        {capacidadeForaDaFaixa(cap) && (
          <p className="text-sm text-[var(--fg)] sm:col-span-2">Atenção: fora da faixa recomendada de {CAPACIDADE_MIN} a {CAPACIDADE_MAX} por dia.</p>
        )}
        {inicial && <Toggle checked={f.arquivado} onChange={(v) => set('arquivado', v)} label="Arquivado" />}
      </div>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

function Consumo({ n }: { n: Numero }) {
  if (n.capacidade_dia == null) {
    return <span className="text-sm"><span className="tabular">{fmtNum(n.consumo_hoje)}</span> <span className="text-[var(--fg-2)]">· sem capacidade definida</span></span>;
  }
  return (
    <div className="min-w-[160px]">
      <div className={`text-sm tabular ${n.acima_da_capacidade ? `font-semibold ${corAlerta}` : 'text-[var(--fg)]'}`}>
        {fmtNum(n.consumo_hoje)} de {fmtNum(n.capacidade_dia)}{n.acima_da_capacidade && ' · acima da capacidade'}
      </div>
      <ProgressBar
        value={(n.consumo_hoje / n.capacidade_dia) * 100}
        tone={n.acima_da_capacidade ? 'red' : 'accent'}
        ariaLabel={`${n.consumo_hoje} de ${n.capacidade_dia} hoje`}
        valueNow={n.consumo_hoje}
        valueMax={n.capacidade_dia}
      />
    </div>
  );
}

export function AbaNumeros({ numeros, falhou, projetos, ferramentas, onGravou }: {
  numeros: Numero[]; falhou: boolean; projetos: Projeto[]; ferramentas: Ferramenta[]; onGravou: (msg: string) => void;
}) {
  const [editar, setEditar] = useState<Numero | null | 'novo'>(null);
  const [arquivar, setArquivar] = useState<Numero | null>(null);
  const [erroArq, setErroArq] = useState<string | null>(null);
  const salvo = (msg: string) => { setEditar(null); onGravou(msg); };

  async function confirmarArquivo(n: Numero) {
    const r: Resultado = await salvarNumero(paraBanco({ ...paraForm(n), arquivado: !n.arquivado_em }));
    setArquivar(null);
    if (!r.ok) { setErroArq(r.msg); return; }
    setErroArq(null);
    onGravou(r.msg);
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-2">
        <Button className={botaoTopo} onClick={() => setEditar('novo')}><Icon name="plus" size={16} /> Cadastrar número</Button>
        <span className="text-sm text-[var(--fg-2)]">Consumo de hoje = soma das listas dos disparos de hoje deste número, no log.</span>
      </div>
      {falhou && <ErroCarga oque="os números" />}
      <Erro msg={erroArq} />
      {!falhou && (numeros.length === 0 ? <Vazio titulo="Nenhum número cadastrado" dica='Clique em "Cadastrar número" para incluir o primeiro.' /> : (
        <DataTable minWidth={1200}>
          <Thead>
            {['Número', 'Projeto / frente', 'Consumo hoje', 'Capacidade', 'Status', 'Finalidade', 'Ferramenta', 'Responsável', 'Ações'].map((c) => <Th key={c} className={thCls}>{c}</Th>)}
          </Thead>
          <tbody>
            {numeros.map((n) => (
              <Tr key={n.id}>
                <Td className="whitespace-nowrap font-mono">{n.numero}{n.arquivado_em && <div className="font-sans"><Selo tom="apagado">arquivado</Selo></div>}</Td>
                <Td>{[n.projeto, n.frente].filter(Boolean).join(' · ') || <span className="text-[var(--fg-2)]">—</span>}</Td>
                <Td><Consumo n={n} /></Td>
                <Td className="whitespace-nowrap">
                  {n.capacidade_dia == null ? <span className="text-[var(--fg-2)]">não definida</span> : <span className="tabular">{fmtNum(n.capacidade_dia)}/dia</span>}
                  {capacidadeForaDaFaixa(n.capacidade_dia) && <div><Selo tom="aviso">fora de {CAPACIDADE_MIN}–{CAPACIDADE_MAX}</Selo></div>}
                </Td>
                <Td className="whitespace-nowrap">
                  <Selo tom={TOM_STATUS[n.status as StatusNumero] ?? 'neutro'}>{ROTULO_STATUS_NUMERO[n.status as StatusNumero] ?? n.status}</Selo>
                  <div className="text-sm text-[var(--fg-2)]">desde {dataBR(partesSP(n.status_desde).data)}</div>
                </Td>
                <Td>{ROTULO_FINALIDADE[n.finalidade as Finalidade] ?? n.finalidade}</Td>
                <Td>{n.ferramenta ?? <span className="text-[var(--fg-2)]">—</span>}</Td>
                <Td>{n.responsavel}</Td>
                <Td className="whitespace-nowrap">
                  <div className="flex gap-4">
                    <BotaoLink onClick={() => setEditar(n)} aria-label={`Editar ${n.numero}`}>Editar</BotaoLink>
                    <BotaoLink onClick={() => setArquivar(n)} aria-label={`${n.arquivado_em ? 'Desarquivar' : 'Arquivar'} ${n.numero}`}>{n.arquivado_em ? 'Desarquivar' : 'Arquivar'}</BotaoLink>
                  </div>
                </Td>
              </Tr>
            ))}
          </tbody>
        </DataTable>
      ))}

      {editar && (
        <ModalNumero inicial={editar === 'novo' ? null : editar} projetos={projetos} ferramentas={ferramentas} onFechar={() => setEditar(null)} onSalvo={salvo} />
      )}
      {arquivar && (
        <Modal
          onClose={() => setArquivar(null)}
          title={arquivar.arquivado_em ? 'Desarquivar número' : 'Arquivar número'}
          width="max-w-md"
          footer={<>
            <Button variant="ghost" onClick={() => setArquivar(null)}>Cancelar</Button>
            <Button variant={arquivar.arquivado_em ? 'primary' : 'danger'} onClick={() => void confirmarArquivo(arquivar)}>
              {arquivar.arquivado_em ? 'Desarquivar' : 'Arquivar'}
            </Button>
          </>}
        >
          <p className="text-sm text-[var(--fg)]">
            {arquivar.arquivado_em
              ? `${arquivar.numero} volta a aparecer para novos disparos.`
              : `${arquivar.numero} deixa de aparecer para novos disparos. Os disparos antigos continuam no log.`}
          </p>
        </Modal>
      )}
    </div>
  );
}
