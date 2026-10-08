'use client';

// Aba #integracoes: painel real da Hotmart (gestor/leitor), números de WhatsApp e um card por sistema com o status VIVO
// (crm_integracoes_status), o último evento, os eventos das 24 h e o texto do que entra, sai e o risco.
// Atualiza sozinho (useAtualizacaoPeriodica 'integracoes': 15 s, 30 s com o aviso do banco; aba oculta = pausa).
import { useCallback } from 'react';
import { Badge, Button, Card } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import {
  haQuanto, numerosDo, ROTULO_ESTADO, ROTULO_NUMERO, situacaoIntegracao, TOM_ESTADO, TOM_NUMERO,
  type FatosIntegracao, type NumeroWhatsappVivo, type PainelIntegracoes,
} from '../../domain/integracoes-status';
import { Aviso, Carregando, EsqueletoLista } from '../comum';
import { MODO_DEMONSTRACAO, repo, useAgora, useAtualizacaoPeriodica, useDados } from '../repositorio';
import { INTEGRACOES, type Integracao } from './integracoes';
import { PainelHotmart } from './PainelHotmart';

interface Leitura {
  p: PainelIntegracoes;
  /** Relógio do navegador na chegada da resposta: "atualizado há Xs" e o "agora" do servidor sem depender do relógio local. */
  recebidoEm: number;
}

const ROTULO_PROVEDOR = { infobip: 'Oficial (Infobip)', evolution: 'QR (Evolution)' } as const;

export function AbaIntegracoes({ gestor, verTudo = gestor, leitor = false, flash }: {
  gestor: boolean; verTudo?: boolean; leitor?: boolean; flash: (m: string) => void;
}) {
  const carregar = useCallback(async (): Promise<Leitura> => ({ p: await repo.integracoesStatus(), recebidoEm: Date.now() }), []);
  const r = useDados(carregar, []);
  useAtualizacaoPeriodica(r.recarregar, 'integracoes');
  const relogio = useAgora(1_000);

  return (
    <div className="space-y-4">
      {/* O leitor vê o painel; reprocessar continua só do gestor (podeReprocessar). */}
      {verTudo && <PainelHotmart gestor={gestor} flash={flash} />}
      {MODO_DEMONSTRACAO && (
        <Aviso tom="neutral" icone="lock">
          {`Modo demonstração: nenhuma integração está ligada${gestor ? ' e os números da Hotmart acima são fictícios' : ''}.`}
        </Aviso>
      )}
      <Carregando dados={r.dados} erro={r.erro} onTentar={() => void r.recarregar()} esqueleto={<EsqueletoLista linhas={4} avatar={false} />}>
        {({ p, recebidoEm }) => {
          // "Agora" na régua do servidor: geradoEm + o tempo que passou no navegador desde a resposta.
          const agora = new Date(new Date(p.geradoEm).getTime() + Math.max(0, relogio.getTime() - recebidoEm));
          const fatos = new Map(p.integracoes.map((f) => [f.chave, f]));
          const conectadas = INTEGRACOES.filter((i) => situacaoIntegracao(i.chave, fatos.get(i.chave), agora, p.numeros).estado === 'conectada').length;
          return (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[var(--fg-2)]">
                <span className="inline-flex items-center gap-1.5 font-medium text-[var(--fg)]">
                  <Icon name="refresh" size={13} /> Status ao vivo
                </span>
                <span>{conectadas} de {INTEGRACOES.length} conectadas</span>
                <span className="text-[var(--fg-3)]" title={fmtDataHora(p.geradoEm)}>
                  · atualizado {haQuanto(new Date(recebidoEm).toISOString(), relogio)}
                </span>
                <Button size="sm" variant="ghost" onClick={() => void r.recarregar()}>Atualizar agora</Button>
              </div>
              {r.erro && (
                <Aviso tom="warning" icone="alert">Não foi possível atualizar agora ({r.erro}). Mostrando a última leitura.</Aviso>
              )}
              <CardNumeros numeros={p.numeros} agora={agora} gerenciar={!leitor} />
              <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                {INTEGRACOES.map((i) => (
                  <CardIntegracao key={i.chave} i={i} f={fatos.get(i.chave)} numeros={p.numeros} agora={agora} />
                ))}
              </div>
            </div>
          );
        }}
      </Carregando>
    </div>
  );
}

function CardNumeros({ numeros, agora, gerenciar }: { numeros: NumeroWhatsappVivo[]; agora: Date; gerenciar: boolean }) {
  return (
    <Card className="p-4 flex flex-col gap-3 min-w-0">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="flex items-center gap-3 min-w-0">
          <span className="w-8 h-8 shrink-0 grid place-items-center rounded-[var(--r-md)] bg-[var(--surface-3)] text-[var(--fg-2)]"><Icon name="phone" size={16} /></span>
          <div className="min-w-0">
            <h3 className="text-base font-semibold text-[var(--fg)] leading-tight">Números de WhatsApp</h3>
            <div className="text-xs text-[var(--fg-3)]">
              {numeros.filter((n) => n.ativo && n.status === 'conectado').length} de {numeros.length} conectados
            </div>
          </div>
        </div>
        {gerenciar && (
          <a href="#numeros" className="inline-flex items-center gap-1 text-xs font-medium text-[var(--accent)] hover:underline">
            Gerenciar números <Icon name="link" size={12} />
          </a>
        )}
      </div>
      {numeros.length === 0 ? (
        <p className="text-xs text-[var(--fg-3)]">Nenhum número cadastrado.</p>
      ) : (
        <ul className="divide-y divide-[var(--border-faint)]">
          {numeros.map((n) => (
            <li key={n.id} className="flex flex-wrap items-center justify-between gap-x-4 gap-y-1 py-2 text-xs">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span className="font-medium text-[var(--fg)]">{n.nome}</span>
                  {n.final && <span className="tabular text-[var(--fg-3)]">•••• {n.final}</span>}
                  {n.principal && <Badge tone="accent">Principal</Badge>}
                  {!n.ativo && <Badge>Inativo</Badge>}
                </div>
                <div className="text-[var(--fg-3)]">
                  {ROTULO_PROVEDOR[n.provedor]}
                  {!n.recebe && ' · não recebe'}
                  {!n.envia && ' · não envia'}
                  {n.statusMotivo && n.status !== 'conectado' && ` · ${n.statusMotivo}`}
                </div>
              </div>
              <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-[var(--fg-2)]">
                <span title={n.ultimaMensagemEm ? fmtDataHora(n.ultimaMensagemEm) : undefined}>
                  Última mensagem {haQuanto(n.ultimaMensagemEm, agora)}
                </span>
                <span className="tabular">{n.mensagens24h.toLocaleString('pt-BR')} nas 24 h</span>
                {n.falhas24h > 0 && <Badge tone="danger">{n.falhas24h.toLocaleString('pt-BR')} com falha</Badge>}
                <Badge tone={TOM_NUMERO[n.status]}>{ROTULO_NUMERO[n.status]}</Badge>
              </div>
            </li>
          ))}
        </ul>
      )}
    </Card>
  );
}

function CardIntegracao({ i, f, numeros, agora }: { i: Integracao; f: FatosIntegracao | undefined; numeros: NumeroWhatsappVivo[]; agora: Date }) {
  const s = situacaoIntegracao(i.chave, f, agora, numeros);
  const doProvedor = i.chave === 'infobip' || i.chave === 'evolution' ? numerosDo(i.chave, numeros) : [];
  return (
    <Card className={`p-4 flex flex-col gap-3 min-w-0 ${i.ferramentas ? 'md:col-span-2 xl:col-span-3' : ''}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-3 min-w-0">
          <span className="w-8 h-8 shrink-0 grid place-items-center rounded-[var(--r-md)] bg-[var(--surface-3)] text-[var(--fg-2)]"><Icon name={i.icone} size={16} /></span>
          <div className="min-w-0">
            <h3 className="text-base font-semibold text-[var(--fg)] leading-tight">{i.nome}</h3>
            <div className="text-xs text-[var(--fg-3)]">{i.papel}</div>
          </div>
        </div>
        <span className="shrink-0"><Badge tone={TOM_ESTADO[s.estado]}>{ROTULO_ESTADO[s.estado]}</Badge></span>
      </div>

      {f && (
        <div className="flex flex-wrap gap-x-3 gap-y-1 text-xs text-[var(--fg-2)]">
          <span title={f.ultimoEventoEm ? fmtDataHora(f.ultimoEventoEm) : undefined}>Último evento {haQuanto(f.ultimoEventoEm, agora)}</span>
          <span className="tabular">{f.eventos24h.toLocaleString('pt-BR')} nas 24 h</span>
          {doProvedor.length > 0 && (
            <span>{doProvedor.filter((n) => n.ativo && n.status === 'conectado').length} de {doProvedor.length} número(s) conectado(s)</span>
          )}
        </div>
      )}
      {s.motivo && s.estado !== 'em_breve' && <p className="text-xs text-[var(--fg-3)]">{s.motivo}</p>}
      {f?.erroRecente && (
        <p role="status" className="flex items-start gap-1.5 text-xs text-[var(--red)]" title={f.erroRecente.em ? fmtDataHora(f.erroRecente.em) : undefined}>
          <Icon name="alert" size={13} className="mt-0.5 shrink-0" />
          <span>{f.erroRecente.texto}{f.erroRecente.em ? ` (${haQuanto(f.erroRecente.em, agora)})` : ''}</span>
        </p>
      )}

      <dl className={`gap-x-6 gap-y-2 text-xs ${i.ferramentas ? 'grid md:grid-cols-2' : 'space-y-2'}`}>
        <div><dt className="font-medium text-[var(--fg-3)]">O que entra</dt><dd className="text-[var(--fg-2)] leading-relaxed">{i.entra}</dd></div>
        <div><dt className="font-medium text-[var(--fg-3)]">O que sai</dt><dd className="text-[var(--fg-2)] leading-relaxed">{i.sai}</dd></div>
      </dl>
      {i.ferramentas && (
        <div>
          <div className="mb-1.5 text-xs font-medium text-[var(--fg-3)]">Ferramentas que o servidor MCP expõe</div>
          <ul className="grid gap-x-6 gap-y-1.5 sm:grid-cols-2 xl:grid-cols-3">
            {i.ferramentas.map((t) => (
              <li key={t.nome} className="min-w-0 text-xs">
                <code className="text-[var(--fg)]">{t.nome}</code>
                <span className="block text-[var(--fg-2)] leading-relaxed">{t.descricao}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      <p className="mt-auto flex items-start gap-1.5 border-t border-[var(--border-faint)] pt-3 text-xs text-[var(--fg-3)] leading-relaxed">
        <Icon name="alert" size={13} className="mt-0.5 shrink-0" />
        <span><span className="sr-only">Risco: </span>{i.risco}</span>
      </p>
    </Card>
  );
}
