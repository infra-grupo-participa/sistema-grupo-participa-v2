'use client';

// Aba "Pedidos de alteração" da Central, para o aprovador (pa_aprovadores): antes/depois, conflito,
// aprovar (com ajuste opcional) ou recusar (com motivo). Aprovar aplica na hora no banco (pa_decidir).
import { useCallback, useEffect, useState } from 'react';
import {
  Badge, Button, Checkbox, EmptyState, Input, Loading, Modal, SectionCard, Textarea, Toast, useFlash,
} from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import {
  ROTULO_TIPO,
  campoAceitaAjusteTexto,
  rotuloCampo,
  type PedidoLinha,
} from '../domain/pedidos-alteracao';
import { decidirPedido, filaPedidos, marcarAplicado } from './pedidos-alteracao-data';
import { AlunoDistincao, Rotulo, StatusPedido } from './pedidos-alteracao-ui';

const ROTULO_ACAO: Record<string, string> = {
  criado: 'Pedido criado',
  aplicado: 'Aprovado e aplicado',
  aprovado: 'Aprovado',
  recusado: 'Recusado',
  erro: 'Erro ao aplicar',
  caso_remocao_aberto: 'Caso de Remoção de Acessos aberto',
  marcado_aplicado: 'Marcado como aplicado',
};

function Linha({ k, children }: { k: string; children: React.ReactNode }) {
  return (
    <div className="grid grid-cols-[110px_1fr] gap-2 py-1 text-sm">
      <span className="text-xs text-[var(--fg-3)] pt-0.5">{k}</span>
      <span className="text-[var(--fg)] break-words min-w-0">{children}</span>
    </div>
  );
}

function CartaoPedido({ p, onAprovar, onRecusar, onMarcar }: {
  p: PedidoLinha; onAprovar: () => void; onRecusar: () => void; onMarcar: () => void;
}) {
  const [verHist, setVerHist] = useState(false);
  const aberto = p.status === 'pendente' || p.status === 'erro';
  return (
    <div className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4 space-y-2">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm font-semibold text-[var(--fg)]">Pedido nº {p.id}</span>
          <Badge>{ROTULO_TIPO[p.tipo]}</Badge>
          <StatusPedido p={p} />
          {p.conflito && aberto && <Badge tone="danger">Conflito</Badge>}
        </div>
        <span className="text-xs text-[var(--fg-3)]">
          {p.solicitado_por_nome ?? 'sem nome'} · {fmtDataHora(p.solicitado_em)}
        </span>
      </div>

      {p.aluno ? <AlunoDistincao a={p.aluno} /> : <span className="text-sm text-[var(--fg)]">{p.aluno_nome}</span>}

      {p.tipo === 'alterar_dado' && (
        <div className="rounded-[var(--r-md)] border border-[var(--border-faint)] px-3 py-1">
          <Linha k="Campo">{rotuloCampo(p.campo)}</Linha>
          <Linha k="Antes (no pedido)">{p.de ?? '(vazio)'}</Linha>
          <Linha k="Depois"><strong>{p.para ?? '(vazio)'}</strong></Linha>
          {p.conflito && aberto && (
            <Linha k="Hoje na base"><span className="text-[var(--red)]">{p.agora ?? '(vazio)'}: mudou desde o pedido</span></Linha>
          )}
        </div>
      )}
      {p.tipo === 'trocar_socio' && (
        <div className="rounded-[var(--r-md)] border border-[var(--border-faint)] px-3 py-1">
          <Linha k="Titular">{p.aluno_nome}</Linha>
          <Linha k="Sai">
            {p.socio_sai_nome}
            {aberto && p.socio_sai_vinculado === false && <span className="block text-[var(--red)]">Já não está vinculado a este titular.</span>}
          </Linha>
          <Linha k="Entra">
            {p.socio_entra_nome}
            {p.socio_entra_novo && (
              <span className="block text-xs text-[var(--fg-3)]">
                Pessoa nova: {[p.socio_entra_novo.email, p.socio_entra_novo.telefone, p.socio_entra_novo.documento].filter(Boolean).join(' · ')}
              </span>
            )}
          </Linha>
          <p className="text-xs text-[var(--fg-3)] py-1">Ao aprovar: quem sai perde o vínculo e ganha um caso em Remoção de Acessos; quem entra recebe a instrução e o vencimento do titular.</p>
        </div>
      )}
      {p.tipo === 'outro' && (
        <div className="rounded-[var(--r-md)] border border-[var(--border-faint)] px-3 py-1">
          <Linha k="Pedido">{p.descricao}</Linha>
        </div>
      )}

      <Linha k="Motivo">{p.motivo}</Linha>
      {p.evidencia && (
        <Linha k="Evidência">
          <a href={p.evidencia} target="_blank" rel="noopener noreferrer" className="text-[var(--accent)] hover:underline break-all">{p.evidencia}</a>
        </Linha>
      )}
      {p.erro_msg && <Linha k="Erro"><span className="text-[var(--red)]">{p.erro_msg}</span></Linha>}
      {p.motivo_recusa && <Linha k="Recusa">{p.motivo_recusa}</Linha>}
      {p.decidido_em && <Linha k="Decidido">{p.decidido_por_nome} · {fmtDataHora(p.decidido_em)}{p.conflito_confirmado ? ' · conflito confirmado' : ''}</Linha>}
      {p.ra_caso_id && (
        <Linha k="Remoção">
          <a href={`/relatorios/remocoes?caso=${p.ra_caso_id}`} className="text-[var(--accent)] hover:underline">Abrir o caso de remoção do sócio que saiu</a>
        </Linha>
      )}

      <div className="flex flex-wrap items-center justify-between gap-2 pt-1">
        <button type="button" onClick={() => setVerHist((v) => !v)} className="text-xs text-[var(--fg-3)] hover:text-[var(--fg)]">
          {verHist ? 'Esconder histórico' : 'Ver histórico'}
        </button>
        <div className="flex gap-2">
          {aberto && <Button variant="danger" size="sm" onClick={onRecusar}>Recusar</Button>}
          {aberto && <Button size="sm" onClick={onAprovar}>Aprovar</Button>}
          {p.status === 'aprovado' && p.tipo === 'outro' && <Button size="sm" variant="subtle" onClick={onMarcar}>Marcar como aplicado</Button>}
        </div>
      </div>
      {verHist && (
        <ul className="text-xs text-[var(--fg-2)] space-y-0.5 border-t border-[var(--border-faint)] pt-2">
          {(p.historico ?? []).map((h, i) => (
            <li key={i}>{fmtDataHora(h.em)} · {ROTULO_ACAO[h.acao] ?? h.acao}{h.por ? ` · ${h.por}` : ''}</li>
          ))}
        </ul>
      )}
    </div>
  );
}

export function PedidosAprovacao({ onCountChange }: { onCountChange?: (n: number) => void }) {
  const { toast, flash } = useFlash(4000);
  const [todos, setTodos] = useState(false);
  const [pedidos, setPedidos] = useState<PedidoLinha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aprovando, setAprovando] = useState<PedidoLinha | null>(null);
  const [recusando, setRecusando] = useState<PedidoLinha | null>(null);
  const [marcando, setMarcando] = useState<PedidoLinha | null>(null);
  const [ajuste, setAjuste] = useState('');
  const [confirmaConflito, setConfirmaConflito] = useState(false);
  const [conflitoAgora, setConflitoAgora] = useState<string | null>(null);
  const [texto, setTexto] = useState('');
  const [busy, setBusy] = useState(false);

  const carregar = useCallback(async (t: boolean) => {
    try {
      const l = await filaPedidos(t);
      setPedidos(l);
      setErro(null);
      onCountChange?.(l.filter((x) => x.status === 'pendente' || x.status === 'erro').length);
    } catch (e) {
      setErro(e instanceof Error ? e.message : 'Não foi possível carregar os pedidos.');
    }
  }, [onCountChange]);

  useEffect(() => {
    let vivo = true;
    filaPedidos(todos)
      .then((l) => { if (!vivo) return; setPedidos(l); setErro(null); onCountChange?.(l.filter((x) => x.status === 'pendente' || x.status === 'erro').length); })
      .catch((e) => { if (vivo) setErro(e.message); });
    return () => { vivo = false; };
  }, [todos, onCountChange]);

  const abrirAprovar = (p: PedidoLinha) => {
    setAprovando(p); setAjuste(''); setConfirmaConflito(false); setConflitoAgora(p.conflito ? p.agora ?? '(vazio)' : null);
  };

  async function aprovar() {
    if (!aprovando) return;
    setBusy(true);
    const r = await decidirPedido(aprovando.id, 'aprovar', {
      valorAjustado: ajuste.trim() ? ajuste.trim() : undefined,
      confirmarConflito: confirmaConflito,
    });
    setBusy(false);
    if (r.conflito) { setConflitoAgora(r.agora ?? '(vazio)'); flash(r.msg); return; }
    flash(r.msg);
    if (!r.ok) return;
    setAprovando(null);
    carregar(todos);
  }

  async function recusar() {
    if (!recusando) return;
    if (texto.trim().length < 3) { flash('Informe o motivo da recusa.'); return; }
    setBusy(true);
    const r = await decidirPedido(recusando.id, 'recusar', { motivoRecusa: texto.trim() });
    setBusy(false);
    flash(r.msg);
    if (!r.ok) return;
    setRecusando(null); setTexto('');
    carregar(todos);
  }

  async function marcar() {
    if (!marcando) return;
    setBusy(true);
    const r = await marcarAplicado(marcando.id, texto.trim());
    setBusy(false);
    flash(r.msg);
    if (!r.ok) return;
    setMarcando(null); setTexto('');
    carregar(todos);
  }

  return (
    <div className="space-y-4">
      <SectionCard
        title="Pedidos de alteração de cadastro"
        subtitle="Aprovar aplica na base na hora, com registro no histórico do aluno. A planilha da Central é atualizada depois (status de planilha)."
        right={(
          <div className="flex gap-2">
            <Button size="sm" variant={todos ? 'ghost' : 'subtle'} onClick={() => setTodos(false)}>Em aberto</Button>
            <Button size="sm" variant={todos ? 'subtle' : 'ghost'} onClick={() => setTodos(true)}>Últimos 90 dias</Button>
            <Button size="sm" variant="ghost" onClick={() => carregar(todos)}>Atualizar</Button>
          </div>
        )}
      >
        {erro ? <EmptyState title={erro} /> : !pedidos ? <Loading /> : pedidos.length === 0 ? (
          <EmptyState title="Nenhum pedido em aberto." hint="Quem tem a permissão de pedir envia pela tela Pedidos de alteração." />
        ) : (
          <div className="space-y-3">
            {pedidos.map((p) => (
              <CartaoPedido key={p.id} p={p}
                onAprovar={() => abrirAprovar(p)}
                onRecusar={() => { setRecusando(p); setTexto(''); }}
                onMarcar={() => { setMarcando(p); setTexto(''); }} />
            ))}
          </div>
        )}
      </SectionCard>

      {aprovando && (
        <Modal onClose={() => setAprovando(null)} title={`Aprovar pedido nº ${aprovando.id}`}
          footer={<>
            <Button variant="ghost" onClick={() => setAprovando(null)}>Cancelar</Button>
            <Button onClick={aprovar} disabled={busy || (conflitoAgora !== null && !confirmaConflito)}>
              {busy ? 'Aplicando…' : 'Aprovar e aplicar'}
            </Button>
          </>}>
          <div className="space-y-3 text-sm">
            {aprovando.tipo === 'alterar_dado' && (
              <p className="text-[var(--fg-2)]">{rotuloCampo(aprovando.campo)}: {aprovando.de ?? '(vazio)'} → <strong>{aprovando.para ?? '(vazio)'}</strong></p>
            )}
            {aprovando.tipo === 'trocar_socio' && (
              <p className="text-[var(--fg-2)]">Titular {aprovando.aluno_nome}: sai {aprovando.socio_sai_nome}, entra {aprovando.socio_entra_nome}. Abre caso em Remoção de Acessos para quem sai.</p>
            )}
            {aprovando.tipo === 'outro' && (
              <p className="text-[var(--fg-2)]">Pedido livre: aprovar só registra a decisão. Você faz a alteração e depois marca como aplicado.</p>
            )}
            {aprovando.tipo === 'alterar_dado' && campoAceitaAjusteTexto(aprovando.campo) && (
              <label className="block">
                <Rotulo dica="opcional">Ajustar o valor antes de aplicar</Rotulo>
                <Input value={ajuste} onChange={(e) => setAjuste(e.target.value)} placeholder={aprovando.para ?? ''} />
              </label>
            )}
            {conflitoAgora !== null && (
              <div className="rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-3 py-2 space-y-2">
                <p className="text-[var(--fg)]">
                  {aprovando.tipo === 'alterar_dado'
                    ? <>O valor mudou desde o pedido. Hoje na base: <strong>{conflitoAgora}</strong>.</>
                    : <>O vínculo mudou desde o pedido: {conflitoAgora}</>}
                </p>
                <Checkbox checked={confirmaConflito} onChange={setConfirmaConflito} label="Conferi e quero aplicar mesmo assim" />
              </div>
            )}
          </div>
        </Modal>
      )}

      {recusando && (
        <Modal onClose={() => setRecusando(null)} title={`Recusar pedido nº ${recusando.id}`}
          footer={<>
            <Button variant="ghost" onClick={() => setRecusando(null)}>Cancelar</Button>
            <Button variant="danger" onClick={recusar} disabled={busy || texto.trim().length < 3}>Recusar</Button>
          </>}>
          <label className="block">
            <Rotulo>Motivo da recusa (quem pediu vai ver)</Rotulo>
            <Textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} />
          </label>
        </Modal>
      )}

      {marcando && (
        <Modal onClose={() => setMarcando(null)} title={`Marcar pedido nº ${marcando.id} como aplicado`}
          footer={<>
            <Button variant="ghost" onClick={() => setMarcando(null)}>Cancelar</Button>
            <Button onClick={marcar} disabled={busy}>Marcar como aplicado</Button>
          </>}>
          <label className="block">
            <Rotulo dica="opcional">O que foi feito</Rotulo>
            <Textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={3} />
          </label>
        </Modal>
      )}

      <Toast>{toast}</Toast>
    </div>
  );
}
