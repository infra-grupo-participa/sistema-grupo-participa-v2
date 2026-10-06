'use client';

// Registrar ou editar um disparo (mkt_msg_disparo_salvar). O banco valida tudo; o erro dele aparece como veio.
import { useState } from 'react';
import { Button, FilterSelect, Input, Modal, Textarea } from '@/shared/ui/components';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import {
  CANAIS, ROTULO_CANAL, ROTULO_TIPO, TIPOS, centavosParaCampo, dataBR, inteiroDigitado, partesSP, reaisParaCentavos,
  type Disparo, type Ferramenta, type Numero, type Resultado,
} from '../domain/mensageria';
import { salvarDisparo } from './mensageria-data';
import { Campo, Erro, ErrosDoBanco } from './pecas';

type Form = {
  data: string; hora: string; projeto: string; canal: string; tipo: string; ferramenta_id: string; numero_id: string;
  copy_texto: string; copy_link: string; publico_lista: string; publico_origem: string; tamanho_lista: string;
  entregues: string; lidas: string; cliques: string; falhas: string; custo: string; disparado_por: string;
};

const s = (v: number | string | null | undefined) => (v == null ? '' : String(v));

function formInicial(d: Disparo | null, hoje: string, nomeUsuario: string): Form {
  if (!d) {
    return {
      data: hoje, hora: '', projeto: '', canal: 'whatsapp_api', tipo: '', ferramenta_id: '', numero_id: '', copy_texto: '',
      copy_link: '', publico_lista: '', publico_origem: '', tamanho_lista: '', entregues: '', lidas: '', cliques: '',
      falhas: '', custo: '', disparado_por: nomeUsuario,
    };
  }
  const { data, hora } = partesSP(d.enviado_em);
  return {
    data, hora, projeto: d.projeto, canal: d.canal, tipo: s(d.tipo), ferramenta_id: s(d.ferramenta_id), numero_id: s(d.numero_id),
    copy_texto: s(d.copy_texto), copy_link: s(d.copy_link), publico_lista: d.publico_lista, publico_origem: s(d.publico_origem),
    tamanho_lista: s(d.tamanho_lista), entregues: s(d.entregues), lidas: s(d.lidas), cliques: s(d.cliques), falhas: s(d.falhas),
    custo: centavosParaCampo(d.custo_centavos), disparado_por: d.disparado_por,
  };
}

/** Número legível vai como número; vazio como null; o resto vai cru e o banco devolve a mensagem certa. */
const inteiroOuCru = (v: string) => { const n = inteiroDigitado(v); return n === undefined ? v.trim() : n; };

export function ModalDisparo({ inicial, hoje, nomeUsuario, projetos, ferramentas, numeros, onFechar, onSalvo }: {
  inicial: Disparo | null; hoje: string; nomeUsuario: string; projetos: Projeto[]; ferramentas: Ferramenta[]; numeros: Numero[];
  onFechar: () => void; onSalvo: (msg: string) => void;
}) {
  const [f, setF] = useState<Form>(() => formInicial(inicial, hoje, nomeUsuario));
  const [res, setRes] = useState<Resultado | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof Form>(k: K, v: Form[K]) => setF((x) => ({ ...x, [k]: v }));
  const comTipo = f.canal === 'whatsapp_api';

  const ferrOpcoes = ferramentas.filter((x) => x.ativa || String(x.id) === f.ferramenta_id);
  const numOpcoes = numeros.filter((x) => !x.arquivado_em || String(x.id) === f.numero_id);

  async function salvar() {
    const custo = reaisParaCentavos(f.custo);
    setSalvando(true);
    const r = await salvarDisparo({
      ...(inicial ? { id: inicial.id } : {}),
      enviado_em: f.data && f.hora ? `${f.data}T${f.hora}` : '',
      projeto: f.projeto,
      canal: f.canal,
      tipo: comTipo ? f.tipo || null : null,
      ferramenta_id: f.ferramenta_id,
      numero_id: f.numero_id || null,
      copy_texto: f.copy_texto || null,
      copy_link: f.copy_link.trim() || null,
      publico_lista: f.publico_lista,
      publico_origem: f.publico_origem || null,
      tamanho_lista: inteiroOuCru(f.tamanho_lista),
      entregues: inteiroOuCru(f.entregues),
      lidas: inteiroOuCru(f.lidas),
      cliques: inteiroOuCru(f.cliques),
      falhas: inteiroOuCru(f.falhas),
      custo_centavos: custo === undefined ? f.custo.trim() : custo,
      disparado_por: f.disparado_por,
    });
    setSalvando(false);
    if (!r.ok) { setRes(r); return; }
    onSalvo(r.msg);
  }

  const num = (k: keyof Form, rotulo: string, dica?: string) => (
    <Campo rotulo={rotulo} dica={dica}>
      <Input value={f[k]} onChange={(e) => set(k, e.target.value)} inputMode="numeric" />
    </Campo>
  );

  return (
    <Modal
      onClose={onFechar}
      title={inicial ? `Editar disparo de ${dataBR(partesSP(inicial.enviado_em).data)}` : 'Registrar disparo'}
      width="max-w-3xl"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : inicial ? 'Salvar' : 'Registrar'}</Button>
      </>}
    >
      <p className="mb-3 text-sm text-[var(--fg-2)]">Não sabe ainda? Deixe vazio. Vazio = não lançado. Use 0 só se foi zero.</p>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="grid grid-cols-2 gap-3">
          <Campo rotulo="Data do envio"><Input type="date" value={f.data} onChange={(e) => set('data', e.target.value)} /></Campo>
          <Campo rotulo="Hora"><Input type="time" value={f.hora} onChange={(e) => set('hora', e.target.value)} /></Campo>
        </div>
        <Campo rotulo="Projeto">
          <FilterSelect value={f.projeto} onChange={(e) => set('projeto', e.target.value)}>
            <option value="">Escolha</option>
            {projetos.map((p) => <option key={p.id} value={p.sigla}>{p.sigla} · {p.nome}{p.ativo ? '' : ' (inativo)'}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Canal">
          <FilterSelect value={f.canal} onChange={(e) => { set('canal', e.target.value); if (e.target.value !== 'whatsapp_api') set('tipo', ''); }}>
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
        <Campo rotulo="Ferramenta">
          <FilterSelect value={f.ferramenta_id} onChange={(e) => set('ferramenta_id', e.target.value)}>
            <option value="">Escolha</option>
            {ferrOpcoes.map((x) => <option key={x.id} value={x.id}>{x.nome}{x.ativa ? '' : ' (desativada)'}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Número" dica="se houver">
          <FilterSelect value={f.numero_id} onChange={(e) => set('numero_id', e.target.value)}>
            <option value="">Nenhum</option>
            {numOpcoes.map((n) => <option key={n.id} value={n.id}>{n.numero}{n.projeto ? ` · ${n.projeto}` : ''}{n.arquivado_em ? ' (arquivado)' : ''}</option>)}
          </FilterSelect>
        </Campo>

        <div className="sm:col-span-2">
          <Campo rotulo="Copy: texto curto" dica="preencha o texto, o link, ou os dois">
            <Textarea rows={2} value={f.copy_texto} onChange={(e) => set('copy_texto', e.target.value)} maxLength={4000} />
          </Campo>
        </div>
        <div className="sm:col-span-2">
          <Campo rotulo="Copy: link">
            <Input type="url" value={f.copy_link} onChange={(e) => set('copy_link', e.target.value)} placeholder="https://" maxLength={2000} />
          </Campo>
        </div>

        <Campo rotulo="Lista" dica="para quem foi"><Input value={f.publico_lista} onChange={(e) => set('publico_lista', e.target.value)} placeholder="ex.: Inscritos PB26" maxLength={200} /></Campo>
        <Campo rotulo="Origem da lista"><Input value={f.publico_origem} onChange={(e) => set('publico_origem', e.target.value)} placeholder="ex.: Página ak1" maxLength={200} /></Campo>

        <div className="grid grid-cols-2 gap-3 sm:col-span-2 sm:grid-cols-6">
          {num('tamanho_lista', 'Tamanho')}
          {num('entregues', 'Entregues')}
          {num('lidas', 'Lidas')}
          {num('cliques', 'Cliques')}
          {num('falhas', 'Falhas')}
          <Campo rotulo="Custo R$">
            <Input value={f.custo} onChange={(e) => set('custo', e.target.value)} inputMode="decimal" placeholder="ex.: 96,00" />
          </Campo>
        </div>

        <Campo rotulo="Quem disparou"><Input value={f.disparado_por} onChange={(e) => set('disparado_por', e.target.value)} maxLength={80} /></Campo>
      </div>
      <div className="mt-3">
        <Erro msg={res?.msg} />
        <ErrosDoBanco erros={res?.erros} />
      </div>
    </Modal>
  );
}
