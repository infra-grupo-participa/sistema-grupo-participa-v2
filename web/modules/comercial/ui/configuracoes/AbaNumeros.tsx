'use client';

// Aba #numeros: números de WhatsApp do CRM (migration 20261008152212). O oficial (Infobip, API) e os conectados por QR
// Code (Evolution API). O gestor conecta (nome → QR que se atualiza sozinho → conectado) e desconecta. A chave da
// Evolution fica só no servidor: a tela chama /api/comercial/canais. Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
import { useEffect, useRef, useState } from 'react';
import { Badge, Button, ConfirmDialog, Input, Modal, SectionCard } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import {
  QR_INTERVALO_MS, QR_MAX_TENTATIVAS, ROTULO_STATUS_CANAL, TOM_STATUS_CANAL, rotuloCanal, validarNomeCanal, type CanalWhatsapp,
} from '../../domain/canais-whatsapp';
import { Aviso, Campo, Carregando, EsqueletoLista, NotaRodape } from '../comum';
import { avisarMudanca, repo, useDados } from '../repositorio';

type RespostaEstado = { ok?: boolean; status?: string; qr?: string | null; final?: string | null; canalId?: string; error?: string };

async function chamar(url: string, init?: RequestInit): Promise<RespostaEstado> {
  try {
    const r = await fetch(url, { ...init, headers: { 'Content-Type': 'application/json' }, cache: 'no-store' });
    const d = (await r.json().catch(() => ({}))) as RespostaEstado;
    return r.ok ? d : { ok: false, error: d.error ?? `Erro ${r.status}` };
  } catch {
    return { ok: false, error: 'Sem conexão com o servidor.' };
  }
}

export function AbaNumeros({ gestor, nomeDe, flash }: { gestor: boolean; nomeDe: (id: string | null) => string; flash: (m: string) => void }) {
  const r = useDados(() => repo.canais());
  const [conectando, setConectando] = useState<{ canalId: string | null; nome: string } | null>(null);
  const [desconectar, setDesconectar] = useState<CanalWhatsapp | null>(null);

  async function confirmarDesconexao(c: CanalWhatsapp) {
    setDesconectar(null);
    const d = await chamar(`/api/comercial/canais/${c.id}`, { method: 'POST', body: JSON.stringify({ acao: 'desconectar' }) });
    if (d.ok) { flash(`"${c.nome}" desconectado do CRM.`); avisarMudanca(); } else flash(d.error ?? 'Não foi possível desconectar.');
    void r.recarregar();
  }

  async function atualizarEventos(c: CanalWhatsapp) {
    const d = await chamar(`/api/comercial/canais/${c.id}`, { method: 'POST', body: JSON.stringify({ acao: 'webhook' }) });
    flash(d.ok ? `Eventos de "${c.nome}" atualizados (edição e exclusão de mensagem).` : d.error ?? 'Não foi possível atualizar.');
  }

  return (
    <div className="space-y-4">
      <Aviso tom="warning" icone="alert" titulo="Número conectado por QR é WhatsApp comum, não a API oficial">
        Use para conversar 1 a 1. Nada de disparo em massa por ele: o CRM bloqueia disparo e templates nesses números e limita
        o volume por minuto e por hora para evitar banimento. O número continua funcionando no celular e na Clint (o WhatsApp
        aceita até 4 aparelhos) até ser desligado de lá.
      </Aviso>

      <SectionCard
        title="Números de WhatsApp"
        subtitle="Cada conversa fica ligada ao número em que chegou. A resposta sai pelo mesmo número."
        right={gestor ? (
          <Button size="sm" onClick={() => setConectando({ canalId: null, nome: '' })}><Icon name="plus" size={14} /> Conectar número</Button>
        ) : undefined}
      >
        <Carregando dados={r.dados} erro={r.erro} onTentar={() => void r.recarregar()} esqueleto={<EsqueletoLista linhas={2} avatar={false} />}>
          {(p) => (
            <>
              {!p.evolutionLigado && p.canais.some((c) => c.provedor === 'evolution') && (
                <Aviso tom="neutral" icone="lock" className="mb-3">
                  WhatsApp por QR desligado no CRM: as mensagens recebidas ficam guardadas e entram quando ligar; nada sai por esses números.
                </Aviso>
              )}
              <ul className="divide-y divide-[var(--border-faint)]">
                {p.canais.map((c) => (
                  <li key={c.id} className="py-3 flex flex-wrap items-center gap-3">
                    <Icon name={c.provedor === 'infobip' ? 'phone' : 'message'} size={16} className="text-[var(--fg-3)] shrink-0" />
                    <div className="min-w-0 flex-1">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="text-sm font-semibold text-[var(--fg)] truncate">{rotuloCanal(c)}</span>
                        <Badge tone={TOM_STATUS_CANAL[c.status]}>{ROTULO_STATUS_CANAL[c.status]}</Badge>
                        {c.provedor === 'infobip' ? <Badge>API oficial</Badge> : <Badge>QR Code</Badge>}
                        {c.padrao && <Badge>Disparos e templates</Badge>}
                      </div>
                      <div className="text-xs text-[var(--fg-3)] mt-0.5">
                        {c.statusMotivo ?? (c.conectadoEm ? `Conectado em ${fmtDataHora(c.conectadoEm)}` : c.provedor === 'infobip' ? 'Configurado na Infobip.' : 'Ainda não leu o QR.')}
                        {c.donoId ? ` · Dono: ${nomeDe(c.donoId)}` : ''}
                        {!c.envia ? ' · Não envia pelo CRM' : ''}{!c.recebe ? ' · Não recebe no CRM' : ''}
                      </div>
                    </div>
                    {gestor && c.provedor === 'evolution' && (
                      <div className="flex gap-2 shrink-0">
                        {c.status !== 'conectado' && (
                          <Button size="sm" variant="subtle" onClick={() => setConectando({ canalId: c.id, nome: c.nome })}>
                            <Icon name="refresh" size={13} /> Gerar QR
                          </Button>
                        )}
                        {c.status === 'conectado' && (
                          <Button size="sm" variant="ghost" onClick={() => atualizarEventos(c)} title="Reaplica o webhook com os eventos atuais (não desconecta)">
                            <Icon name="refresh" size={13} /> Atualizar eventos
                          </Button>
                        )}
                        {c.status === 'conectado' && (
                          <Button size="sm" variant="ghost" onClick={() => setDesconectar(c)}>Desconectar</Button>
                        )}
                      </div>
                    )}
                  </li>
                ))}
              </ul>
              <NotaRodape className="mt-3">
                Limites anti-ban por número conectado por QR: {p.limiteMinuto} mensagens por minuto, {p.limiteHora} por hora e
                {' '}{p.novosHora} primeiros contatos por hora (quem nunca escreveu naquele número). Sem janela de 24 h e sem template.
              </NotaRodape>
            </>
          )}
        </Carregando>
      </SectionCard>

      {conectando && (
        <ModalConectar
          inicial={conectando}
          onFechar={(mudou) => { setConectando(null); if (mudou) { avisarMudanca(); void r.recarregar(); } }}
        />
      )}
      <ConfirmDialog
        open={!!desconectar}
        title="Desconectar número?"
        message={<>O CRM para de receber e enviar por <strong>{desconectar?.nome}</strong>. O número continua no celular e na Clint. Para voltar, gere um QR novo.</>}
        confirmLabel="Desconectar"
        danger
        onCancel={() => setDesconectar(null)}
        onConfirm={() => desconectar && void confirmarDesconexao(desconectar)}
      />
    </div>
  );
}

/** Nome → QR (atualiza a cada 3 s até conectar) → conectado. */
function ModalConectar({ inicial, onFechar }: { inicial: { canalId: string | null; nome: string }; onFechar: (mudou: boolean) => void }) {
  const [nome, setNome] = useState(inicial.nome);
  const [canalId, setCanalId] = useState<string | null>(inicial.canalId);
  const [qr, setQr] = useState<string | null>(null);
  const [status, setStatus] = useState<string>(inicial.canalId ? 'pedindo' : 'nome');
  const [final, setFinal] = useState<string | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const tentativas = useRef(0);
  const mudou = useRef(false);

  // Reconectar um número existente: pede instância + QR novo uma vez ao abrir.
  useEffect(() => {
    if (!inicial.canalId) return;
    let vivo = true;
    void chamar(`/api/comercial/canais/${inicial.canalId}`, { method: 'POST', body: JSON.stringify({ acao: 'conectar' }) }).then((d) => {
      if (!vivo) return;
      if (!d.ok) { setErro(d.error ?? 'Não foi possível gerar o QR.'); setStatus('erro'); return; }
      mudou.current = true;
      setQr(d.qr ?? null); setStatus(d.status ?? 'aguardando_qr'); setFinal(d.final ?? null);
    });
    return () => { vivo = false; };
  }, [inicial.canalId]);

  // Enquanto espera a leitura, pergunta o estado a cada 3 s (o QR muda sozinho); para em ~5 min.
  useEffect(() => {
    if (!canalId || status !== 'aguardando_qr') return;
    const t = setInterval(async () => {
      tentativas.current += 1;
      if (tentativas.current > QR_MAX_TENTATIVAS) { setStatus('expirou'); return; }
      const d = await chamar(`/api/comercial/canais/${canalId}`);
      if (!d.ok) { setErro(d.error ?? 'Falha ao consultar.'); return; }
      setErro(null);
      if (d.status === 'conectado') { setStatus('conectado'); setFinal(d.final ?? null); setQr(null); mudou.current = true; return; }
      if (d.qr) setQr(d.qr);
      if (d.status && d.status !== 'aguardando_qr') setStatus(d.status);
    }, QR_INTERVALO_MS);
    return () => clearInterval(t);
  }, [canalId, status]);

  async function criar() {
    const invalido = validarNomeCanal(nome);
    if (invalido) { setErro(invalido); return; }
    setOcupado(true); setErro(null);
    const d = await chamar('/api/comercial/canais', { method: 'POST', body: JSON.stringify({ nome: nome.trim() }) });
    setOcupado(false);
    if (!d.ok || !d.canalId) { setErro(d.error ?? 'Não foi possível criar.'); return; }
    mudou.current = true;
    setCanalId(d.canalId); setQr(d.qr ?? null); setStatus('aguardando_qr');
  }

  const fechar = () => onFechar(mudou.current);
  return (
    <Modal
      onClose={fechar}
      title={status === 'conectado' ? 'Número conectado' : 'Conectar número de WhatsApp'}
      footer={status === 'nome' ? (
        <>
          <Button variant="ghost" size="sm" onClick={fechar}>Cancelar</Button>
          <Button size="sm" disabled={ocupado} onClick={() => void criar()}>{ocupado ? 'Criando…' : 'Gerar QR Code'}</Button>
        </>
      ) : <Button size="sm" variant={status === 'conectado' ? 'primary' : 'ghost'} onClick={fechar}>{status === 'conectado' ? 'Pronto' : 'Fechar'}</Button>}
    >
      {status === 'nome' && (
        <div className="space-y-3">
          <Campo rotulo="Nome do número" dica='Como a equipe reconhece o número. Ex.: "Clint 4276".'>
            <Input value={nome} onChange={(e) => setNome(e.target.value)} maxLength={80} autoFocus placeholder="Clint 4276" />
          </Campo>
          <p className="text-xs text-[var(--fg-3)]">
            Depois, abra o WhatsApp do celular desse número → Aparelhos conectados → Conectar aparelho, e aponte para o QR.
          </p>
        </div>
      )}
      {(status === 'aguardando_qr' || status === 'pedindo') && (
        <div className="flex flex-col items-center gap-3 text-center">
          {qr ? (
            // eslint-disable-next-line @next/next/no-img-element -- data URL do QR (não passa pelo otimizador)
            <img src={qr} alt="QR Code para conectar o WhatsApp" width={264} height={264} className="rounded-[var(--r-md)] bg-[var(--surface-1)] p-2" />
          ) : (
            <div className="w-[264px] h-[264px] grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-xs text-[var(--fg-3)]">Gerando QR…</div>
          )}
          <p className="text-sm text-[var(--fg-2)]">
            No celular: <strong>WhatsApp → Aparelhos conectados → Conectar aparelho</strong>. O QR se atualiza sozinho.
          </p>
        </div>
      )}
      {status === 'conectado' && (
        <div className="flex items-center gap-3">
          <Icon name="check" size={20} className="text-[var(--green)]" />
          <p className="text-sm text-[var(--fg-2)]">
            Conectado{final ? ` (final ${final})` : ''}. As conversas desse número já entram no CRM. Ele continua no celular e na Clint.
          </p>
        </div>
      )}
      {(status === 'expirou' || status === 'desconectado' || status === 'banido' || status === 'erro') && (
        <p className="text-sm text-[var(--fg-2)]">
          {status === 'banido' ? 'O WhatsApp bloqueou este número.' : status === 'expirou' ? 'O QR expirou sem leitura.' : 'Não conectou.'}
          {' '}Feche e use “Gerar QR” para tentar de novo.
        </p>
      )}
      {erro && <p role="alert" className="mt-3 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}
