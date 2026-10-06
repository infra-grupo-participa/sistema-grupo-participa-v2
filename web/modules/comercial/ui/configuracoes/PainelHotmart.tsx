'use client';

// Painel da integração Hotmart (F3) para o gestor: ligada ou não, o que foi processado no período, os erros com
// "Reprocessar" e as ofertas vendidas fora do catálogo. Lê `crm_hotmart_painel`; sem acesso, mostra o erro (nunca zero).
import { useState } from 'react';
import { Badge, Button, SectionCard } from '@/shared/ui/components';
import { fmtDataHora, fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import type { ErroHotmart } from '../../domain/types';
import { Aviso, Carregando, EsqueletoLista, FaixaNumeros, NotaRodape, Segmentado } from '../comum';
import { avisarMudanca, repo, useDados } from '../repositorio';
import {
  PERIODOS_HOTMART, podeReprocessar, resumoHotmart, rotuloClasseHotmart, textoErroHotmart,
} from './regras-integracoes';

export function PainelHotmart({ gestor, flash }: { gestor: boolean; flash: (m: string) => void }) {
  const [dias, setDias] = useState<number>(7);
  const r = useDados(() => repo.hotmartPainel(dias), [dias]);
  const [refazendo, setRefazendo] = useState<string | null>(null);

  async function reprocessar(e: ErroHotmart) {
    setRefazendo(e.chave);
    const res = await repo.reprocessarHotmart(e.chave);
    setRefazendo(null);
    flash(res.ok ? `Evento reprocessado${res.msg ? `: ${res.msg}` : '.'}` : res.msg ?? 'Não foi possível reprocessar.');
    if (res.ok) { avisarMudanca(); void r.recarregar(); }
  }

  return (
    <SectionCard
      title={<span className="inline-flex items-center gap-2"><Icon name="wallet" size={16} /> Hotmart</span>}
      subtitle="Compra, checkout e reembolso que chegam da Hotmart e viram negócio. Só o gestor vê."
      right={(
        <Segmentado
          rotulo="Período"
          valor={String(dias)}
          onChange={(v) => setDias(Number(v))}
          opcoes={PERIODOS_HOTMART.map((d) => ({ valor: String(d), rotulo: d === 1 ? '24 h' : `${d} dias` }))}
        />
      )}
    >
      <Carregando dados={r.dados} erro={r.erro} onTentar={() => void r.recarregar()} esqueleto={<EsqueletoLista linhas={3} avatar={false} />}>
        {(p) => {
          const res = resumoHotmart(p);
          const reprocessa = podeReprocessar(p, gestor);
          return (
            <div className="space-y-4">
              <div className="flex flex-wrap items-center gap-2 text-xs text-[var(--fg-2)]">
                <Badge tone={p.hotmartLigado ? 'success' : 'neutral'}>{p.hotmartLigado ? 'Ligada' : 'Desligada'}</Badge>
                <Badge tone={p.slackLigado ? 'success' : 'neutral'}>Avisos no Slack {p.slackLigado ? 'ligados' : 'desligados'}</Badge>
                <span title={p.ultimoProcessadoEm ? fmtDataHora(p.ultimoProcessadoEm) : undefined}>
                  Último evento processado: {p.ultimoProcessadoEm ? fmtRelativo(p.ultimoProcessadoEm).label : 'nenhum'}
                </span>
                {p.desde && <span className="text-[var(--fg-3)]">· lendo desde {fmtDataHora(p.desde)}</span>}
              </div>

              {!p.hotmartLigado && (
                <Aviso tom="neutral" icone="lock">
                  Integração desligada: nenhum evento novo vira negócio e o reprocessamento fica parado. Quem liga é o
                  responsável pelo sistema, depois do ok do gestor.
                </Aviso>
              )}

              <FaixaNumeros
                rotulo={`Eventos dos últimos ${dias === 1 ? '24 h' : `${dias} dias`}`}
                itens={[
                  { rotulo: 'Processados', valor: res.total.toLocaleString('pt-BR') },
                  { rotulo: 'Negócios criados', valor: res.negocios.toLocaleString('pt-BR') },
                  { rotulo: 'Ganhos fechados', valor: res.ganhos.toLocaleString('pt-BR') },
                  { rotulo: 'Com erro', valor: res.erros.toLocaleString('pt-BR'), alerta: res.erros > 0 },
                ]}
              />

              {res.porResultado.length > 0 && (
                <div>
                  <div className="mb-1.5 text-xs font-medium text-[var(--fg-3)]">O que aconteceu com cada evento</div>
                  <ul className="flex flex-wrap gap-1.5">
                    {res.porResultado.map((x) => (
                      <li key={x.resultado} className="inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-3)] px-2.5 py-1 text-xs text-[var(--fg-2)]">
                        {x.rotulo} <span className="font-semibold tabular text-[var(--fg)]">{x.n.toLocaleString('pt-BR')}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <div>
                <div className="mb-1.5 text-xs font-medium text-[var(--fg-3)]">Erros ({p.erros.length}{p.erros.length === 50 ? ', os 50 mais recentes' : ''})</div>
                {p.erros.length === 0 ? (
                  <p className="text-xs text-[var(--fg-3)]">Nenhum erro no período.</p>
                ) : (
                  // Lista que quebra em tela estreita (sem tabela com rolagem).
                  <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)]">
                    {p.erros.map((e) => (
                      <li key={e.chave} className="flex flex-wrap items-center gap-x-3 gap-y-1.5 px-3 py-2">
                        <div className="min-w-0 flex-1 basis-[240px]">
                          <div className="text-sm text-[var(--fg)] break-words">{textoErroHotmart(e.resultado)}</div>
                          <div className="text-xs text-[var(--fg-3)]">
                            {rotuloClasseHotmart(e.classe)} · {fmtDataHora(e.em)} · {e.tentativas} {e.tentativas === 1 ? 'tentativa' : 'tentativas'}
                            <span className="block truncate font-mono text-[11px]" title={e.chave}>{e.chave}</span>
                          </div>
                        </div>
                        <Button
                          size="sm" variant="ghost"
                          disabled={!reprocessa || refazendo !== null}
                          title={reprocessa ? 'Refaz este evento com a regra atual' : 'Só com a integração ligada'}
                          onClick={() => reprocessar(e)}
                        >
                          <Icon name="refresh" size={14} /> {refazendo === e.chave ? 'Reprocessando…' : 'Reprocessar'}
                        </Button>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {p.ofertasOrfas.length > 0 && (
                <Aviso tom="warning" titulo={`${p.ofertasOrfas.length} ${p.ofertasOrfas.length === 1 ? 'oferta vendida fora' : 'ofertas vendidas fora'} do catálogo`}>
                  {p.ofertasOrfas.join(', ')}. Cadastre em Produtos para o negócio cair no funil certo.
                </Aviso>
              )}

              <NotaRodape>
                Avisos no Slack no período: {p.slack.enviados} enviados, {p.slack.pendentes} na fila, {p.slack.descartados} descartados.
                Venda aprovada e lead novo também chegam pelo sininho.
              </NotaRodape>
            </div>
          );
        }}
      </Carregando>
    </SectionCard>
  );
}
