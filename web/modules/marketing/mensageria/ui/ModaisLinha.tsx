'use client';

// Ações de uma linha do log: lançar retorno, arquivar (motivo obrigatório) e ver histórico.
import { useEffect, useState } from 'react';
import { Button, Input, Loading, Modal, Textarea } from '@/shared/ui/components';
import {
  camposAlterados, centavosParaCampo, dataHoraSP, fmtNum, inteiroDigitado, reaisParaCentavos,
  type Disparo, type ItemHistorico,
} from '../domain/mensageria';
import { arquivarDisparo, historico, lancarRetorno } from './mensageria-data';
import { Campo, Erro } from './pecas';

const resumo = (d: Disparo) => `${dataHoraSP(d.enviado_em)} · ${d.projeto} · ${d.publico_lista}`;

export function ModalRetorno({ d, onFechar, onSalvo }: { d: Disparo; onFechar: () => void; onSalvo: (msg: string) => void }) {
  const ini = (v: number | null) => (v == null ? '' : String(v));
  const [f, setF] = useState({
    entregues: ini(d.entregues), lidas: ini(d.lidas), cliques: ini(d.cliques), falhas: ini(d.falhas), custo: centavosParaCampo(d.custo_centavos),
  });
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = (k: keyof typeof f, v: string) => setF((x) => ({ ...x, [k]: v }));

  async function salvar() {
    // A função do banco recebe inteiros: o que não dá para ler como número fica aqui, com a mensagem do campo.
    const nums = { entregues: inteiroDigitado(f.entregues), lidas: inteiroDigitado(f.lidas), cliques: inteiroDigitado(f.cliques), falhas: inteiroDigitado(f.falhas) };
    const ruim = (Object.keys(nums) as (keyof typeof nums)[]).find((k) => nums[k] === undefined);
    if (ruim) { setErro(`${ruim[0].toUpperCase()}${ruim.slice(1)}: use número inteiro (ex.: 1.234), ou deixe vazio.`); return; }
    const custo = reaisParaCentavos(f.custo);
    if (custo === undefined) { setErro('Custo: use reais, como 1.234,56, ou deixe vazio.'); return; }
    setSalvando(true);
    const r = await lancarRetorno(d.id, {
      entregues: nums.entregues ?? null, lidas: nums.lidas ?? null, cliques: nums.cliques ?? null, falhas: nums.falhas ?? null, custo_centavos: custo,
    });
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title="Lançar retorno"
      width="max-w-xl"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button onClick={salvar} disabled={salvando}>{salvando ? 'Lançando…' : 'Lançar retorno'}</Button>
      </>}
    >
      <p className="text-sm text-[var(--fg)]">{resumo(d)}</p>
      <p className="mb-3 mt-1 text-sm text-[var(--fg-2)]">Tamanho da lista: {fmtNum(d.tamanho_lista)}. Vazio = não lançado. Use 0 só se foi zero.</p>
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-5">
        <Campo rotulo="Entregues"><Input value={f.entregues} onChange={(e) => set('entregues', e.target.value)} inputMode="numeric" /></Campo>
        <Campo rotulo="Lidas"><Input value={f.lidas} onChange={(e) => set('lidas', e.target.value)} inputMode="numeric" /></Campo>
        <Campo rotulo="Cliques"><Input value={f.cliques} onChange={(e) => set('cliques', e.target.value)} inputMode="numeric" /></Campo>
        <Campo rotulo="Falhas"><Input value={f.falhas} onChange={(e) => set('falhas', e.target.value)} inputMode="numeric" /></Campo>
        <Campo rotulo="Custo R$"><Input value={f.custo} onChange={(e) => set('custo', e.target.value)} inputMode="decimal" placeholder="96,00" /></Campo>
      </div>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

export function ModalArquivar({ d, onFechar, onSalvo }: { d: Disparo; onFechar: () => void; onSalvo: (msg: string) => void }) {
  const [motivo, setMotivo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  async function salvar() {
    setSalvando(true);
    const r = await arquivarDisparo(d.id, motivo);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title="Arquivar disparo"
      width="max-w-lg"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button variant="danger" onClick={salvar} disabled={salvando}>{salvando ? 'Arquivando…' : 'Arquivar'}</Button>
      </>}
    >
      <p className="text-sm text-[var(--fg)]">{resumo(d)}</p>
      <p className="mb-3 mt-1 text-sm text-[var(--fg-2)]">Sai da lista e dos totais. Fica guardado no histórico. Não dá para desfazer pela tela.</p>
      <Campo rotulo="Motivo" dica="obrigatório">
        <Textarea rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={500} autoFocus placeholder="ex.: lançado em dobro" />
      </Campo>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

const ROTULO_ACAO: Record<string, string> = { inserir: 'Criou', alterar: 'Alterou', arquivar: 'Arquivou', anonimizar: 'Anonimizou' };
const valor = (v: unknown) => (v == null ? 'vazio' : typeof v === 'object' ? JSON.stringify(v) : String(v));

export function ModalHistorico({ tabela, id, titulo, onFechar }: {
  tabela: 'disparos' | 'numeros' | 'ferramentas'; id: number; titulo: string; onFechar: () => void;
}) {
  const [itens, setItens] = useState<ItemHistorico[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    historico(tabela, id).then((r) => {
      if (!vivo) return;
      if (!r || !r.ok) { setErro(r?.msg ?? 'Não foi possível carregar o histórico (erro de rede ou sem acesso).'); return; }
      setItens(r.itens ?? []);
    });
    return () => { vivo = false; };
  }, [tabela, id]);

  return (
    <Modal onClose={onFechar} title={`Histórico · ${titulo}`} width="max-w-2xl" footer={<Button variant="ghost" onClick={onFechar}>Fechar</Button>}>
      {erro ? <Erro msg={erro} /> : !itens ? <Loading minHeight={120} /> : itens.length === 0 ? (
        <p className="text-sm text-[var(--fg-2)]">Sem registro de mudança.</p>
      ) : (
        <ol className="space-y-3">
          {itens.map((h) => {
            const mud = camposAlterados(h.antes, h.depois);
            const motivo = h.acao === 'arquivar' ? h.depois?.arquivado_motivo : h.acao === 'anonimizar' ? h.depois?.motivo : null;
            return (
              <li key={h.id} className="border-b border-[var(--border-faint)] pb-2 text-sm">
                <div className="text-[var(--fg)]">
                  <span className="font-semibold">{ROTULO_ACAO[h.acao] ?? h.acao}</span>
                  <span className="text-[var(--fg-2)]"> · {dataHoraSP(h.em)} · {h.por_nome ?? 'sem autor'}</span>
                </div>
                {motivo != null && <div className="text-[var(--fg-2)]">Motivo: {String(motivo)}</div>}
                {h.acao === 'alterar' && mud.length > 0 && (
                  <ul className="mt-1 space-y-0.5">
                    {mud.map((m) => (
                      <li key={m.campo} className="break-words text-[var(--fg-2)]">
                        <span className="font-mono text-[var(--fg)]">{m.campo}</span>: {valor(m.antes)} → {valor(m.depois)}
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            );
          })}
        </ol>
      )}
    </Modal>
  );
}
