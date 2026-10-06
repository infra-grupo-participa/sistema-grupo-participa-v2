'use client';

// Preços por mensagem (20261005o), dentro da aba Ferramentas. Mantidos pela equipe (Jéssica).
// Preço não se edita nem se apaga: errou, anula com motivo e cadastra outro. O custo estimado dos disparos é calculado
// pelo banco com o preço vigente no dia do envio. Busca só quando a aba Ferramentas é aberta (useCargaVisivel).
import { useState } from 'react';
import { Button, DataTable, EmptyState, FilterSelect, Input, Loading, Modal, Td, Textarea, Th, Thead, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  BASES_COBRANCA, CANAIS, ROTULO_BASE, ROTULO_CANAL, ROTULO_TIPO, TIPOS, dataBR, dataHoraSP, fmtPrecoCentavos,
  precoReaisParaCentavos, rotuloBase, rotuloCanal, rotuloSituacaoPreco, situacaoPreco,
  type Ferramenta, type Preco, type Resultado, type TipoMensagem,
} from '../domain/mensageria';
import { anularPreco, listarPrecos, salvarPreco } from './mensageria-data';
import { Campo, Erro, ErrosDoBanco, thCls } from './pecas';
import { useCargaVisivel } from './useCargaVisivel';

const POR_BASE: Record<string, string> = { entregues: 'por entregue', tamanho_lista: 'por pessoa', mensalidade: '' };

function ModalNovoPreco({ ferramentas, onFechar, onSalvo }: { ferramentas: Ferramenta[]; onFechar: () => void; onSalvo: (msg: string) => void }) {
  // Sem valor assumido em campo de regra (canal, base, preço, vigência): o banco recusa o que faltar.
  const [f, setF] = useState({ ferramenta_id: '', canal: '', tipo: '', base: '', preco: '', vigente_desde: '', obs: '' });
  const [res, setRes] = useState<Resultado | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof typeof f>(k: K, v: string) => setF((x) => ({ ...x, [k]: v }));
  const comTipo = f.canal === 'whatsapp_api';
  const mensalidade = f.base === 'mensalidade';
  const centavos = mensalidade ? '0' : precoReaisParaCentavos(f.preco);

  async function salvar() {
    if (centavos === undefined) { setRes({ ok: false, msg: 'Preço: use reais, como 0,08 ou 0,065.' }); return; }
    setSalvando(true);
    const r = await salvarPreco({
      ferramenta_id: f.ferramenta_id, canal: f.canal, tipo: comTipo ? f.tipo || null : null, base_cobranca: f.base,
      preco_centavos: centavos ?? '', vigente_desde: f.vigente_desde, obs: f.obs.trim() || null,
    });
    setSalvando(false);
    if (!r.ok) { setRes(r); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title="Novo preço"
      width="max-w-xl"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Cadastrar preço'}</Button>
      </>}
    >
      <p className="mb-3 text-sm text-[var(--fg-2)]">
        Vale a partir da data escolhida. O preço anterior continua valendo para os disparos antes dela.
      </p>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Ferramenta">
          <FilterSelect value={f.ferramenta_id} onChange={(e) => set('ferramenta_id', e.target.value)}>
            <option value="">Escolha</option>
            {ferramentas.map((x) => <option key={x.id} value={x.id}>{x.nome}{x.ativa ? '' : ' (desativada)'}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Canal">
          <FilterSelect value={f.canal} onChange={(e) => { set('canal', e.target.value); if (e.target.value !== 'whatsapp_api') set('tipo', ''); }}>
            <option value="">Escolha</option>
            {CANAIS.map((c) => <option key={c} value={c}>{ROTULO_CANAL[c]}</option>)}
          </FilterSelect>
        </Campo>
        {comTipo ? (
          <Campo rotulo="Tipo" dica="só na API WhatsApp">
            <FilterSelect value={f.tipo} onChange={(e) => set('tipo', e.target.value)}>
              <option value="">Escolha</option>
              {TIPOS.map((t) => <option key={t} value={t}>{ROTULO_TIPO[t]}</option>)}
            </FilterSelect>
          </Campo>
        ) : <div className="hidden sm:block" />}
        <Campo rotulo="Como cobra">
          <FilterSelect value={f.base} onChange={(e) => set('base', e.target.value)}>
            <option value="">Escolha</option>
            {BASES_COBRANCA.map((b) => <option key={b} value={b}>{ROTULO_BASE[b]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Preço por mensagem R$" dica={mensalidade ? 'mensalidade: 0 por disparo' : 'ex.: 0,08'}>
          <Input
            value={mensalidade ? '0' : f.preco} onChange={(e) => set('preco', e.target.value)} disabled={mensalidade}
            inputMode="decimal" placeholder="0,08"
          />
          {!mensalidade && centavos && <span className="mt-1 block text-sm text-[var(--fg-2)]">= {fmtPrecoCentavos(centavos)} {POR_BASE[f.base] ?? ''}</span>}
        </Campo>
        <Campo rotulo="Vale a partir de"><Input type="date" value={f.vigente_desde} onChange={(e) => set('vigente_desde', e.target.value)} /></Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação" dica="opcional"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={500} /></Campo>
        </div>
      </div>
      {mensalidade && <p className="mt-2 text-sm text-[var(--fg-2)]">O valor mensal vai no cadastro da ferramenta (Custo mensal).</p>}
      <div className="mt-3">
        <Erro msg={res?.msg} />
        <ErrosDoBanco erros={res?.erros} />
      </div>
    </Modal>
  );
}

function descricaoPreco(p: Preco) {
  return `${p.ferramenta} · ${rotuloCanal(p.canal)}${p.tipo ? ` · ${ROTULO_TIPO[p.tipo as TipoMensagem] ?? p.tipo}` : ''} · desde ${dataBR(p.vigente_desde)}`;
}

function ModalAnularPreco({ p, onFechar, onSalvo }: { p: Preco; onFechar: () => void; onSalvo: (msg: string) => void }) {
  const [motivo, setMotivo] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  async function salvar() {
    setSalvando(true);
    const r = await anularPreco(p.id, motivo);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(r.msg);
  }

  return (
    <Modal
      onClose={onFechar}
      title="Anular preço"
      width="max-w-lg"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button variant="danger" onClick={salvar} disabled={salvando}>{salvando ? 'Anulando…' : 'Anular preço'}</Button>
      </>}
    >
      <p className="text-sm text-[var(--fg)]">{descricaoPreco(p)} · {fmtPrecoCentavos(p.preco_centavos)} {POR_BASE[p.base_cobranca] ?? ''}</p>
      <p className="mb-3 mt-1 text-sm text-[var(--fg-2)]">
        Deixa de valer. O custo estimado dos disparos que usavam este preço é refeito. Não dá para desfazer: se precisar, cadastre de novo.
      </p>
      <Campo rotulo="Motivo" dica="obrigatório">
        <Textarea rows={3} value={motivo} onChange={(e) => setMotivo(e.target.value)} maxLength={500} autoFocus placeholder="ex.: valor digitado errado" />
      </Campo>
      <div className="mt-3"><Erro msg={erro} /></div>
    </Modal>
  );
}

export function SecaoPrecos({ ferramentas, ativo, versao, onGravou }: {
  ferramentas: Ferramenta[]; ativo: boolean; versao: number; onGravou: (msg: string) => void;
}) {
  const { dados } = useCargaVisivel(listarPrecos, ativo, versao);
  const [modal, setModal] = useState<{ tipo: 'novo' } | { tipo: 'anular'; p: Preco } | null>(null);
  const salvo = (msg: string) => { setModal(null); onGravou(msg); };

  return (
    <section aria-label="Preços" className="space-y-3 pt-4">
      <h2 className="text-base font-semibold text-[var(--fg)]">Preços por mensagem</h2>
      <div className="flex flex-wrap items-center gap-2">
        <Button onClick={() => setModal({ tipo: 'novo' })}><Icon name="plus" size={16} /> Novo preço</Button>
        <span className="text-sm text-[var(--fg-2)]">Usados para estimar o custo quando o real não foi lançado. Preço não se edita: anule e cadastre outro.</span>
      </div>
      {dados === undefined ? <Loading minHeight={80} /> : dados === null ? (
        <Erro msg="Não foi possível carregar os preços (erro de rede ou sem acesso)." />
      ) : dados.precos.length === 0 ? <EmptyState title="Nenhum preço cadastrado" /> : (
        <DataTable minWidth={1100}>
          <Thead>
            {['Ferramenta', 'Canal', 'Tipo', 'Como cobra', 'Preço', 'Vale a partir de', 'Situação', 'Cadastrado por', 'Observação', 'Ações'].map((c) => <Th key={c} className={thCls}>{c}</Th>)}
          </Thead>
          <tbody>
            {dados.precos.map((p) => {
              const sit = situacaoPreco(p, dados.hoje);
              return (
                <Tr key={p.id} className={sit === 'anulado' || sit === 'substituido' ? 'opacity-60' : ''}>
                  <Td className="whitespace-nowrap font-semibold">{p.ferramenta}</Td>
                  <Td className="whitespace-nowrap">{rotuloCanal(p.canal)}</Td>
                  <Td>{p.tipo ? (ROTULO_TIPO[p.tipo as TipoMensagem] ?? p.tipo) : <span className="text-[var(--fg-2)]">—</span>}</Td>
                  <Td className="whitespace-nowrap">{rotuloBase(p.base_cobranca)}</Td>
                  <Td className="whitespace-nowrap tabular">{fmtPrecoCentavos(p.preco_centavos)}</Td>
                  <Td className="whitespace-nowrap tabular">{dataBR(p.vigente_desde)}</Td>
                  <Td>
                    <div className={`whitespace-nowrap ${sit === 'vigente' ? 'font-semibold' : ''}`}>{rotuloSituacaoPreco(p, dados.hoje)}</div>
                    {p.anulado_em && (
                      <div className="max-w-[260px] break-words text-sm text-[var(--fg-2)]">
                        {dataHoraSP(p.anulado_em)} · {p.anulado_por_nome ?? 'sem autor'} · {p.anulado_motivo}
                      </div>
                    )}
                  </Td>
                  <Td>
                    <div className="whitespace-nowrap">{p.criado_por_nome ?? 'carga inicial'}</div>
                    <div className="whitespace-nowrap text-sm text-[var(--fg-2)]">{dataHoraSP(p.criado_em)}</div>
                  </Td>
                  <Td className="max-w-[240px]"><span className="line-clamp-2 break-words">{p.obs ?? ''}</span></Td>
                  <Td>{p.anulado_em ? null : <Button variant="link" onClick={() => setModal({ tipo: 'anular', p })}>Anular</Button>}</Td>
                </Tr>
              );
            })}
          </tbody>
        </DataTable>
      )}
      {modal?.tipo === 'novo' && <ModalNovoPreco ferramentas={ferramentas} onFechar={() => setModal(null)} onSalvo={salvo} />}
      {modal?.tipo === 'anular' && <ModalAnularPreco p={modal.p} onFechar={() => setModal(null)} onSalvo={salvo} />}
    </section>
  );
}
