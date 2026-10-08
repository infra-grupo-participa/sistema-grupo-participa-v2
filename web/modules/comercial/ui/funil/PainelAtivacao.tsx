'use client';

// Faixa da Ativação acima do kanban: data do evento, carga do dia contra o teto da Meta, aviso de colisão com a
// régua da Mensageria, roteiros dos três toques (copiar com um clique) e, para o gestor, configurar e encerrar.
// Em projeto criado antes da Ativação, o gestor vê o botão para acrescentar o funil.
import { useState } from 'react';
import { Button, Checkbox, ConfirmDialog, Input, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  avisoCarga, avisoMensageria, datasDoEvento, nivelCarga, preencherRoteiro, ROTEIROS_ATIVACAO, TETO_CONVERSAS_NOVAS,
  validarAtivacao, type EdicaoAtivacao, type PainelAtivacao, type ProjetoAtivacao,
} from '../../domain/ativacao';
import type { Funil } from '../../domain/types';
import { Aviso, Campo } from '../comum';
import { avisarMudanca, repo } from '../repositorio';

export function PainelAtivacao({ funil, painel, gestor, verTudo = gestor, eu, nomeDe, onFlash, onAbrirFunil }: {
  funil: Funil;
  painel: PainelAtivacao;
  gestor: boolean;
  /** Vê a carga do time inteiro (gestor e leitor). */
  verTudo?: boolean;
  eu: string | null;
  nomeDe: (id: string | null) => string;
  onFlash: (msg: string) => void;
  onAbrirFunil: (id: string) => void;
}) {
  const p = painel.projetos.find((x) => x.funilId === funil.id);
  const [roteiros, setRoteiros] = useState(false);
  const [editando, setEditando] = useState(false);
  const [encerrando, setEncerrando] = useState(false);

  // Funil de um projeto sem a Ativação: o gestor acrescenta.
  if (!p) {
    if (!gestor || !funil.projeto || !painel.semAtivacao.includes(funil.projeto)) return null;
    const acrescentar = async () => {
      const r = await repo.garantirAtivacao(funil.projeto!);
      onFlash(r.msg ?? (r.ok ? 'Ativação criada.' : 'Não foi possível criar a Ativação.'));
      if (r.ok) { avisarMudanca(); if (r.funilId) onAbrirFunil(r.funilId); }
    };
    return (
      <Aviso tom="info" icone="user-check" acao={<Button size="sm" onClick={acrescentar}><Icon name="plus" size={13} /> Acrescentar a Ativação</Button>}>
        Este projeto ainda não tem o funil de Ativação (a primeira jornada do lead: toque 1 na hora, ligação na sexta, link no privado).
      </Aviso>
    );
  }

  const minhaCarga = painel.carga.find((c) => c.vendedorId === eu);
  const avisos = [
    nivelCarga(painel.totalNovasHoje) !== 'ok' ? avisoCarga({ novasHoje: painel.totalNovasHoje }, 'O número oficial') : null,
    ...(verTudo ? painel.carga.map((c) => avisoCarga(c, nomeDe(c.vendedorId))) : [minhaCarga ? avisoCarga(minhaCarga, 'Você') : null]),
    avisoMensageria(p),
  ].filter((x): x is string => !!x);
  const datas = datasDoEvento(p.eventoInicio, p.eventoFim);
  const partes = [
    datas ? `Evento ${datas}${p.eventoHora ? ` às ${p.eventoHora}` : ''}${p.datasDoMarketing ? ' (Marketing)' : ''}` : 'Sem data do evento: só o toque 1 é agendado',
    p.fimAtivacao ? `ativação até ${datasDoEvento(p.fimAtivacao, null)}${p.carrinhoFim ? ' (carrinho)' : ''}` : null,
    `${p.entradasHoje} entrada(s) hoje`,
    p.mqls ? `${p.mqls} MQL` : null,
    `conversas novas hoje: ${painel.totalNovasHoje} (teto ${TETO_CONVERSAS_NOVAS.maximo} por número)`,
    p.encerradoEm ? 'encerrada' : !p.ligado || !painel.ligada ? 'entrada automática desligada' : null,
  ].filter(Boolean);

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 py-2">
        <Icon name="user-check" size={15} className="shrink-0 text-[var(--fg-3)]" />
        <span className="min-w-0 flex-1 text-sm text-[var(--fg-2)]">{partes.join(' · ')}</span>
        <Button size="sm" variant="ghost" onClick={() => setRoteiros(true)}><Icon name="message" size={13} /> Roteiros</Button>
        {gestor && !p.encerradoEm && (
          <>
            <Button size="sm" variant="ghost" onClick={() => setEditando(true)}><Icon name="settings" size={13} /> Configurar</Button>
            <Button size="sm" variant="ghost" onClick={() => setEncerrando(true)}>Encerrar</Button>
          </>
        )}
      </div>
      {avisos.map((a) => <Aviso key={a} tom="warning" alerta>{a}</Aviso>)}

      {roteiros && <ModalRoteiros projeto={p} vendedor={nomeDe(eu)} onClose={() => setRoteiros(false)} onFlash={onFlash} />}
      {editando && <ModalConfigAtivacao projeto={p} onClose={() => setEditando(false)} onSalvo={(msg) => { setEditando(false); onFlash(msg); avisarMudanca(); }} />}
      {encerrando && (
        <ConfirmDialog
          open
          title="Encerrar a ativação?"
          message={`Quem ainda está aberto em ${p.nome} vira perdido "Evento encerrado sem compra" e entra na fila de recuperação com o mesmo dono. O cron faz isso sozinho no dia seguinte ao fechamento do carrinho (sem ele, ao fim do evento).`}
          confirmLabel="Encerrar"
          onCancel={() => setEncerrando(false)}
          onConfirm={async () => {
            const r = await repo.encerrarAtivacao(p.projeto);
            setEncerrando(false);
            onFlash(r.msg ?? (r.ok ? 'Ativação encerrada.' : 'Não foi possível encerrar.'));
            if (r.ok) avisarMudanca();
          }}
        />
      )}
    </div>
  );
}

function ModalRoteiros({ projeto, vendedor, onClose, onFlash }: { projeto: ProjetoAtivacao; vendedor: string; onClose: () => void; onFlash: (m: string) => void }) {
  const [especialista, setEspecialista] = useState('');
  const [temas, setTemas] = useState('');
  const vars = { vendedor, especialista, temas, datas: datasDoEvento(projeto.eventoInicio, projeto.eventoFim) };
  const copiar = async (t: string) => {
    try { await navigator.clipboard.writeText(t); onFlash('Mensagem copiada. Envie pelo número oficial.'); } catch { onFlash('Não deu para copiar: selecione o texto.'); }
  };
  return (
    <Modal onClose={onClose} title="Roteiros da Ativação" width="max-w-2xl">
      <div className="space-y-4 p-5">
        <p className="text-xs text-[var(--fg-3)]">
          Sempre do número oficial do comercial, o mesmo vendedor do começo ao fim. Sem resposta em 24 h depois da ligação: desapegar. Nunca mencionar replay.
          O [nome] fica para você completar na conversa.
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Especialista"><Input value={especialista} placeholder="Ex.: Prof. Marcio" onChange={(e) => setEspecialista(e.target.value)} /></Campo>
          <Campo rotulo="Temas do dia"><Input value={temas} placeholder="Ex.: ITCMD, inventário e a holding" onChange={(e) => setTemas(e.target.value)} /></Campo>
        </div>
        <ul className="space-y-3">
          {ROTEIROS_ATIVACAO.map((r) => {
            const texto = preencherRoteiro(r.texto, vars);
            return (
              <li key={r.id} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
                <div className="mb-1.5 flex items-center justify-between gap-2">
                  <span className="text-sm font-medium text-[var(--fg)]">{r.titulo}</span>
                  <Button size="sm" variant="ghost" onClick={() => copiar(texto)}><Icon name="copy" size={13} /> Copiar</Button>
                </div>
                <p className="whitespace-pre-line text-sm text-[var(--fg-2)]">{texto}</p>
              </li>
            );
          })}
        </ul>
      </div>
    </Modal>
  );
}

function ModalConfigAtivacao({ projeto, onClose, onSalvo }: { projeto: ProjetoAtivacao; onClose: () => void; onSalvo: (msg: string) => void }) {
  const [e, setE] = useState<EdicaoAtivacao>({
    projeto: projeto.projeto, eventoInicio: projeto.eventoInicio, eventoFim: projeto.eventoFim, eventoHora: projeto.eventoHora,
    carrinhoFim: projeto.carrinhoFim, hotmartOferta: projeto.hotmartOferta, ligado: projeto.ligado,
  });
  const [oferta, setOferta] = useState(projeto.hotmartOferta.join(', '));
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const edicao: EdicaoAtivacao = { ...e, hotmartOferta: oferta.split(/[\s,;]+/).map((x) => x.trim()).filter(Boolean) };
  const problema = validarAtivacao(edicao);
  const salvar = async () => {
    if (problema) return;
    setSalvando(true);
    const r = await repo.salvarAtivacao(edicao);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg ?? 'Não foi possível salvar.'); return; }
    onSalvo(r.msg ?? 'Ativação salva.');
  };
  const data = (v: string) => (v ? v : null);
  return (
    <Modal
      onClose={onClose}
      title={`Ativação · ${projeto.nome}`}
      footer={(
        <div className="flex items-center justify-end gap-2">
          {(erro || problema) && <span className="mr-auto text-xs text-[var(--red)]">{erro ?? problema}</span>}
          <Button variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button onClick={salvar} disabled={!!problema || salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
        </div>
      )}
    >
      <div className="space-y-4 p-5">
        <div className="grid gap-3 sm:grid-cols-3">
          <Campo rotulo="Início do evento"><Input type="date" value={e.eventoInicio ?? ''} onChange={(ev) => setE({ ...e, eventoInicio: data(ev.target.value) })} /></Campo>
          <Campo rotulo="Fim do evento"><Input type="date" value={e.eventoFim ?? ''} onChange={(ev) => setE({ ...e, eventoFim: data(ev.target.value) })} /></Campo>
          <Campo rotulo="Hora (Brasília)" dica="O link no privado vence 1 h antes."><Input type="time" value={e.eventoHora ?? ''} onChange={(ev) => setE({ ...e, eventoHora: data(ev.target.value) })} /></Campo>
        </div>
        <Campo rotulo="Fechamento do carrinho" dica="A Ativação acaba no dia seguinte. Vazio: no dia seguinte ao fim do evento.">
          <Input type="date" value={e.carrinhoFim ?? ''} onChange={(ev) => setE({ ...e, carrinhoFim: data(ev.target.value) })} />
        </Campo>
        {projeto.datasDoMarketing && (
          <p className="text-xs text-[var(--fg-3)]">As datas do evento vêm do cadastro do Marketing e valem sobre as daqui (que ficam só de reserva).</p>
        )}
        <Campo rotulo="Produtos da oferta (Hotmart)" dica="Número do produto. Compra aprovada de um deles fecha o negócio de ativação como “Comprou”, com o mesmo dono.">
          <Input value={oferta} placeholder="Ex.: 5064314" onChange={(ev) => setOferta(ev.target.value)} />
        </Campo>
        <Checkbox checked={e.ligado} onChange={(v) => setE({ ...e, ligado: v })} label="Entrada automática ligada para este projeto" />
        <p className="text-xs text-[var(--fg-3)]">
          De onde vêm as entradas (lista ou tag do ActiveCampaign, ingresso da Hotmart, pesquisa, UTM) é a catalogação de origem do projeto, não esta tela.
          Mudou a data? Os toques 2 e 3 em aberto são reagendados; o que já foi feito fica.
        </p>
      </div>
    </Modal>
  );
}
