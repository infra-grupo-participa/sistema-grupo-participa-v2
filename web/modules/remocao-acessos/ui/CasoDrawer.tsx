'use client';

import { useCallback, useEffect, useState } from 'react';
import { Badge, Button, Drawer, Loading, Row, SectionCard, Textarea, Toggle } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';
import { ROTULO_STATUS, ROTULO_TIPO, TOM_STATUS } from '../domain/caso';
import type { CasoDetalhe, ItemCaso, SituacaoItem } from '../domain/types';
import type { SupabaseRemocaoRepository } from '../infrastructure/supabase-remocao.repository';

const ROTULO_ACAO: Record<string, string> = {
  aberto: 'Caso aberto pela Hotmart',
  triagem: 'Triagem',
  item: 'Item marcado',
  concluido: 'Caso concluído',
  reaberto: 'Caso reaberto',
};

function descreverEvento(acao: string, d: Record<string, unknown>): string {
  if (acao === 'triagem') {
    const decisao = d.decisao === 'manter' ? 'mantém o acesso antigo' : 'remover acessos';
    return d.obs ? `${decisao} · ${String(d.obs)}` : decisao;
  }
  if (acao === 'item') {
    const sit = d.situacao === 'feito' ? 'feito' : d.situacao === 'nao_se_aplica' ? 'não se aplica' : 'voltou a pendente';
    return `${String(d.item)}: ${sit}${d.correcao ? ' (correção)' : ''}${d.obs ? ` · ${String(d.obs)}` : ''}`;
  }
  if (acao === 'aberto') return `${String(d.status_compra ?? '')} ${d.evento ? `(${String(d.evento)})` : ''}`.trim();
  return '';
}

function LinhaItem({ it, ocupado, onMarcar }: {
  it: ItemCaso;
  ocupado: boolean;
  onMarcar: (it: ItemCaso, s: SituacaoItem) => void;
}) {
  const feito = it.situacao !== 'pendente';
  return (
    <div className="flex items-center justify-between gap-3 py-2 border-t border-[var(--border-faint)] first:border-t-0">
      <div className="min-w-0">
        <div className={`text-sm ${feito ? 'text-[var(--fg-2)]' : 'text-[var(--fg)] font-medium'}`}>
          {it.situacao === 'feito' && <span className="text-[var(--green)] mr-1.5 inline-flex align-[-2px]"><Icon name="check-circle" size={14} /></span>}
          {it.rotulo}
        </div>
        <div className="text-[11px] text-[var(--fg-3)]">
          {it.responsavel || 'sem responsável'}
          {feito && it.marcado_por && <> · {it.situacao === 'feito' ? 'feito' : 'não se aplica'} por {it.marcado_por} em {fmtDataHora(it.marcado_em)}</>}
          {it.corrigido && <> · <span className="text-[var(--yellow)]">correção</span></>}
          {it.obs && <> · {it.obs}</>}
        </div>
      </div>
      {it.pode_marcar && (
        <div className="flex gap-1.5 shrink-0">
          {feito ? (
            <Button size="sm" variant="ghost" disabled={ocupado} onClick={() => onMarcar(it, 'pendente')}>Desfazer</Button>
          ) : (
            <>
              <Button size="sm" variant="ghost" disabled={ocupado} onClick={() => onMarcar(it, 'nao_se_aplica')}>Não tinha</Button>
              <Button size="sm" variant="success" disabled={ocupado} onClick={() => onMarcar(it, 'feito')}>Removido</Button>
            </>
          )}
        </div>
      )}
    </div>
  );
}

export function CasoDrawer({ id, repo, onClose, onMudou, flash }: {
  id: string;
  repo: SupabaseRemocaoRepository;
  onClose: () => void;
  onMudou: () => void;
  flash: (m: string) => void;
}) {
  const [d, setD] = useState<CasoDetalhe | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [obs, setObs] = useState('');
  const [programa, setPrograma] = useState(false);

  const buscar = useCallback(async (): Promise<{ d: CasoDetalhe | null; erro: string | null }> => {
    try {
      const r = await repo.caso(id);
      if (!r || !r.caso) return { d: null, erro: 'Caso não encontrado ou sem acesso.' };
      return { d: r, erro: null };
    } catch (e) {
      return { d: null, erro: e instanceof Error ? e.message : 'Não foi possível abrir o caso.' };
    }
  }, [id, repo]);

  const aplicar = useCallback((r: { d: CasoDetalhe | null; erro: string | null }) => {
    if (r.erro || !r.d) { setErro(r.erro); return; }
    setD(r.d);
    setPrograma(r.d.caso.eh_programa);
    setErro(null);
  }, []);

  const carregar = useCallback(async () => aplicar(await buscar()), [aplicar, buscar]);

  useEffect(() => {
    let vivo = true;
    buscar().then((r) => { if (vivo) aplicar(r); });
    return () => { vivo = false; };
  }, [aplicar, buscar]);

  const triar = async (decisao: 'manter' | 'remover') => {
    if (decisao === 'manter' && !obs.trim()) { flash('Escreva por que o acesso antigo continua (ex.: HM válido até 31/12/2026).'); return; }
    setOcupado(true);
    const r = await repo.triar(id, decisao, obs.trim(), programa);
    setOcupado(false);
    flash(r.msg);
    if (r.ok) { setObs(''); await carregar(); onMudou(); }
  };

  const marcar = async (it: ItemCaso, s: SituacaoItem) => {
    setOcupado(true);
    const r = await repo.marcarItem(it.id, s, null);
    setOcupado(false);
    if (!r.ok) flash(r.msg);
    await carregar();
    onMudou();
  };

  const c = d?.caso;
  const sug = c?.sugestao;

  return (
    <Drawer
      onClose={onClose}
      title={c ? c.nome || 'sem nome' : 'Caso'}
      subtitle={c ? `${c.email ?? 'sem e-mail'} · ${c.hotmart_transaction}` : undefined}
      badges={c && (
        <>
          <Badge tone={c.tipo === 'disputa' ? 'info' : 'danger'}>{ROTULO_TIPO[c.tipo]}</Badge>
          <Badge tone={TOM_STATUS[c.status]}>{ROTULO_STATUS[c.status]}</Badge>
          {c.eh_programa && <Badge tone="accent">Programa de Implementação</Badge>}
        </>
      )}
    >
      {erro ? (
        <p className="text-sm text-[var(--red)]">{erro}</p>
      ) : !d || !c ? (
        <Loading label="Abrindo caso…" minHeight={200} />
      ) : (
        <div className="flex flex-col gap-4">
          <SectionCard title="Compra">
            <Row k="Produto" v={c.produto_nome || 'sem dado'} />
            <Row k="Oferta" v={c.oferta_codigo || 'sem dado'} />
            <Row k="Valor" v={c.valor != null ? fmtBRL(c.valor) : 'sem valor'} />
            <Row k="Ocorreu em" v={fmtDataHora(c.ocorrido_em)} />
            <Row k="Prazo" v={c.prazo_em ? fmtDataHora(c.prazo_em) : 'sem prazo'} />
            <Row k="Documento" v={c.documento || 'sem dado'} />
            <Row k="Telefone" v={c.telefone || 'sem dado'} />
          </SectionCard>

          {c.status === 'alerta' && (
            <SectionCard title="Disputa aberta" subtitle="Ainda não é reembolso nem chargeback. Nada a remover por enquanto: se a disputa virar chargeback, o caso de remoção nasce sozinho." >
              <span />
            </SectionCard>
          )}

          {c.tipo !== 'disputa' && sug && (
            <SectionCard
              title={`Sugestão: ${sug.recomendacao === 'verificar' ? 'verificar acesso antigo' : 'remover acessos'}`}
              subtitle={sug.motivo}
            >
              {sug.aluno ? (
                <>
                  <Row k="Instrução na base" v={sug.aluno.instrucao || 'sem dado'} />
                  <Row k="Turma" v={sug.aluno.turma || 'sem dado'} />
                  <Row k="Status na Central" v={sug.aluno.status_central || 'sem dado'} />
                  <Row k="Expiração atual" v={sug.aluno.data_expiracao ? fmtData(sug.aluno.data_expiracao) : 'sem dado'} />
                  <Row k="Entrou no THB em" v={sug.aluno.data_entrada_thb ? fmtData(sug.aluno.data_entrada_thb) : 'sem dado'} />
                </>
              ) : (
                <p className="text-sm text-[var(--fg-2)]">Não está na base de alunos.</p>
              )}
              {!!sug.compras_anteriores?.length && (
                <div className="mt-3">
                  <div className="text-xs font-semibold text-[var(--fg-2)] mb-1">Outras compras que dão acesso</div>
                  {sug.compras_anteriores.map((p) => (
                    <div key={p.transacao} className="text-xs text-[var(--fg-2)] tabular">
                      {p.data ? fmtData(p.data) : 'sem data'} · {p.produto} · {p.oferta} · {p.valor != null ? fmtBRL(p.valor) : 'sem valor'} · {p.status}
                    </div>
                  ))}
                </div>
              )}
              {!!sug.historico_expiracao?.length && (
                <div className="mt-3">
                  <div className="text-xs font-semibold text-[var(--fg-2)] mb-1">Mudanças recentes na expiração</div>
                  {sug.historico_expiracao.map((h, i) => (
                    <div key={i} className="text-xs text-[var(--fg-2)] tabular">
                      {fmtDataHora(h.em)} · {h.de || 'vazio'} → {h.para || 'vazio'} · {h.origem || 'sem origem'}
                    </div>
                  ))}
                </div>
              )}
              {sug.aviso && <p className="text-[11px] text-[var(--fg-3)] mt-3">{sug.aviso}</p>}
            </SectionCard>
          )}

          {c.status === 'aguardando_triagem' && (
            <SectionCard
              title="Triagem"
              subtitle={d.pode_triar ? 'Confira o acesso antigo antes de decidir. Mantendo, atualize a Central com o vencimento e a instrução antigos.' : 'Aguardando a triagem. Os itens de remoção aparecem aqui quando ela for feita.'}
            >
              {d.pode_triar ? (
                <div className="flex flex-col gap-3">
                  <Toggle checked={programa} onChange={setPrograma} label="Participa do Programa de Implementação (inclui o sistema do programa)" />
                  <Textarea id="ra-obs-triagem" placeholder="Observação (obrigatória para manter o acesso)" value={obs} onChange={(e) => setObs(e.target.value)} />
                  <div className="flex flex-wrap gap-2">
                    <Button variant="ghost" disabled={ocupado} onClick={() => triar('manter')}>Mantém acesso antigo</Button>
                    <Button variant="primary" disabled={ocupado} onClick={() => triar('remover')}>Remover acessos</Button>
                  </div>
                </div>
              ) : <span />}
            </SectionCard>
          )}

          {c.status === 'mantem_acesso' && (
            <SectionCard title="Mantém o acesso antigo" subtitle={`${c.triado_por_nome ?? ''} em ${fmtDataHora(c.triado_em)}`}>
              <p className="text-sm text-[var(--fg-2)]">{c.decisao_obs || 'sem observação'}</p>
            </SectionCard>
          )}

          {d.pessoas.some((p) => p.itens.length > 0) && d.pessoas.map((p) => (
            <SectionCard
              key={p.id}
              title={`${p.nome || 'sem nome'} · ${p.papel === 'titular' ? 'titular' : 'sócio'}`}
              subtitle={`${p.email || 'sem e-mail'} · ${p.itens.filter((i) => i.situacao !== 'pendente').length}/${p.itens.length} feitos`}
            >
              {p.itens.map((it) => <LinhaItem key={it.id} it={it} ocupado={ocupado} onMarcar={marcar} />)}
            </SectionCard>
          ))}

          <SectionCard title="Histórico">
            {d.historico.map((h, i) => (
              <div key={i} className="text-xs py-1 border-t border-[var(--border-faint)] first:border-t-0">
                <span className="text-[var(--fg-3)] tabular">{fmtDataHora(h.em)}</span>{' '}
                <span className="text-[var(--fg)] font-medium">{ROTULO_ACAO[h.acao] ?? h.acao}</span>
                {h.por && <span className="text-[var(--fg-2)]"> · {h.por}</span>}
                {descreverEvento(h.acao, h.detalhe) && <span className="text-[var(--fg-2)]"> · {descreverEvento(h.acao, h.detalhe)}</span>}
              </div>
            ))}
          </SectionCard>
        </div>
      )}
    </Drawer>
  );
}
