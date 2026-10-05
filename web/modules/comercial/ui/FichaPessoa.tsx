'use client';

// Ficha da pessoa: dados (do aluno/comprador quando existe, senão o que a pessoa informou), origem, histórico (eventos
// próprios + compras lidas da Hotmart pela referência), negócios do CRM e dúvidas de identidade. Nada aqui é cópia
// do aluno: o banco lê thb_alunos, compradores e compras na hora. Abrir a ficha fica registrado (pessoas.acessos).
import { useEffect, useState } from 'react';
import { AvatarInicial, Badge, Button, Drawer, EmptyState, Loading, Row, SectionTitle } from '@/shared/ui/components';
import { fmtBRL, fmtData, fmtDataHora } from '@/shared/ui/format';
import type { ConfigCrm } from '../domain/crm';
import { ROTULO_MOTIVO } from '../domain/identidade';
import { linhaDoTempo, ROTULO_IDENTIFICADOR, ROTULO_SITUACAO, type Ficha } from '../domain/pessoas';
import { carregarFicha } from '../infrastructure/comercial-data';
import { NovoNegocioModal } from './CrmPainel';

export function FichaPessoa({ id, config, versao, onFechar, flash, onMudou }: {
  id: string; config: ConfigCrm; versao: number; onFechar: () => void; flash: (m: string) => void; onMudou: () => void;
}) {
  const [res, setRes] = useState<{ chave: string; f: Ficha | null } | null>(null);
  const [novo, setNovo] = useState(false);
  const chave = `${id}|${versao}`;

  useEffect(() => {
    let vivo = true;
    carregarFicha(id).then((f) => { if (vivo) setRes({ chave, f }); });
    return () => { vivo = false; };
  }, [id, chave]);

  const f = res?.chave === chave ? res.f : undefined;
  const p = f?.pessoa;

  return (
    <Drawer
      onClose={onFechar}
      title={p?.nome ?? (f === undefined ? 'Carregando…' : 'Sem nome')}
      subtitle={p ? `Na base desde ${fmtData(p.criado_em)} · referência ${p.ref}` : undefined}
      avatar={<AvatarInicial nome={p?.nome} />}
      badges={f ? (
        <>
          {f.aluno && <Badge tone="info">Aluno{f.aluno.turma ? ` ${f.aluno.turma}` : ''}{f.aluno.cancelado ? ' (cancelado)' : ''}</Badge>}
          {f.comprador_id && <Badge>Comprador Hotmart</Badge>}
          {p && p.situacao !== 'ativa' && <Badge tone="warning">{ROTULO_SITUACAO[p.situacao]}</Badge>}
          {p?.teste && <Badge>Teste</Badge>}
        </>
      ) : undefined}
      actions={f && f.permissoes.pode_editar ? <Button size="sm" onClick={() => setNovo(true)}>Novo negócio</Button> : undefined}
      width="max-w-4xl"
    >
      {f === undefined ? <Loading /> : f === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível abrir a ficha (sem acesso, pessoa não encontrada, ou a migration 20261005o ainda não foi aplicada).</p>
      ) : (
        <div className="space-y-6 text-sm">
          {p?.mesclada_de && <p className="text-xs text-[var(--fg-3)]">Este registro foi juntado a esta pessoa (revisão de identidade).</p>}

          <section>
            <SectionTitle>Dados</SectionTitle>
            <Row k="E-mail" v={p?.email} />
            <Row k="Telefone" v={p?.telefone} />
            <Row k="Documento" v={p?.documento} />
            <p className="mt-1 text-xs text-[var(--fg-3)]">
              {f.aluno ? 'Lidos da Central de Alunos (fonte da matrícula).' : f.comprador_id ? 'Lidos do comprador da Hotmart.' : 'Informados pela pessoa (formulário ou cadastro).'}
              {!f.permissoes.pode_ver_doc && ' Documento mascarado: você não tem permissão para ver o CPF completo.'}
              {!f.permissoes.pode_ver_contato && ' E-mail e telefone mascarados pela sua permissão.'}
            </p>
            {f.identificadores.length > 0 && (
              <div className="mt-2">
                <div className="text-xs text-[var(--fg-3)] mb-1">Outros dados informados por ela</div>
                <ul className="space-y-0.5">
                  {f.identificadores.map((i, k) => (
                    <li key={k} className="text-xs text-[var(--fg-2)]">{ROTULO_IDENTIFICADOR[i.tipo] ?? i.tipo}: {i.valor} <span className="text-[var(--fg-3)]">({i.origem}, {fmtData(i.criado_em)})</span></li>
                  ))}
                </ul>
              </div>
            )}
          </section>

          {f.revisoes.length > 0 && (
            <section>
              <SectionTitle>Dúvida de identidade</SectionTitle>
              <ul className="space-y-1">
                {f.revisoes.map((r) => <li key={r.id}><Badge tone="warning">{ROTULO_MOTIVO[r.motivo] ?? r.motivo}</Badge> <span className="text-xs text-[var(--fg-3)]">desde {fmtDataHora(r.criado_em)}, resolver na aba Revisão de identidade</span></li>)}
              </ul>
            </section>
          )}

          <section>
            <SectionTitle>Negócios no CRM ({f.negocios.length})</SectionTitle>
            {f.negocios.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Nenhum.</p> : (
              <ul className="divide-y divide-[var(--border-faint)]">
                {f.negocios.map((n) => (
                  <li key={n.id} className="py-1.5 flex flex-wrap items-center gap-2">
                    <Badge>{n.pipeline}</Badge>
                    <Badge tone={n.status === 'ganho' ? 'success' : n.status === 'perdido' ? 'danger' : 'accent'}>{n.etapa}</Badge>
                    {n.projeto && <Badge>{n.projeto}</Badge>}
                    <span className="text-xs text-[var(--fg-2)]">{n.responsavel ?? 'Sem responsável'}</span>
                    {n.status === 'aberto' && n.proximo_passo && <span className="text-xs text-[var(--fg-3)]">· {n.proximo_passo}{n.proximo_passo_em ? ` (${fmtData(n.proximo_passo_em + 'T12:00:00')})` : ''}</span>}
                    {n.status === 'perdido' && n.motivo_perda && <span className="text-xs text-[var(--fg-3)]">· {n.motivo_perda}</span>}
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <SectionTitle>Origem ({f.origens.length})</SectionTitle>
            {f.origens.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Sem origem registrada (não entrou por formulário).</p> : (
              <ul className="space-y-2">
                {f.origens.map((o) => (
                  <li key={o.id} className="rounded-[var(--r-md)] border border-[var(--border)] p-2.5">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-xs text-[var(--fg-3)]">{fmtDataHora(o.quando)}</span>
                      {o.projeto && <Badge>{o.projeto}</Badge>}
                      {o.de_anuncio && <Badge tone="info">De anúncio</Badge>}
                      {o.campanha_padrao === false && <Badge tone="warning">Campanha fora do padrão</Badge>}
                    </div>
                    {o.pagina && <div className="mt-1 text-xs">Página: {o.pagina}</div>}
                    {o.campanha && <div className="mt-0.5 text-xs break-words">Campanha: {o.campanha}</div>}
                    {(o.utm_source || o.utm_medium || o.utm_campaign || o.utm_content || o.utm_term) && (
                      <div className="mt-0.5 text-xs text-[var(--fg-2)] break-words">
                        {[['source', o.utm_source], ['medium', o.utm_medium], ['campaign', o.utm_campaign], ['content', o.utm_content], ['term', o.utm_term]]
                          .filter(([, v]) => v).map(([k, v]) => `utm_${k}=${v}`).join(' · ')}
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <SectionTitle>Histórico</SectionTitle>
            {linhaDoTempo(f).length === 0 ? <EmptyState title="Sem histórico" /> : (
              <ul className="space-y-1">
                {linhaDoTempo(f).map((l, k) => (
                  <li key={k} className="text-xs">
                    <span className="text-[var(--fg-3)]">{fmtDataHora(l.quando)}</span> · <span className="font-medium text-[var(--fg)]">{l.titulo}</span>
                    {l.detalhe && <span className="text-[var(--fg-2)]"> · {l.detalhe}</span>}
                  </li>
                ))}
              </ul>
            )}
          </section>

          <section>
            <SectionTitle>Compras na Hotmart ({f.compras.length})</SectionTitle>
            {f.compras.length === 0 ? <p className="text-xs text-[var(--fg-3)]">{f.comprador_id ? 'Nenhuma compra.' : 'Não é compradora (ou o comprador ainda não foi ligado).'}</p> : (
              <ul className="space-y-0.5">
                {f.compras.map((c) => (
                  <li key={c.id} className="text-xs text-[var(--fg-2)]">
                    {c.data ? fmtData(c.data) : '—'} · {c.produto ?? '—'} · {c.status ?? '—'}{c.preco != null ? ` · ${fmtBRL(c.preco)}` : ''}
                  </li>
                ))}
              </ul>
            )}
            <p className="mt-1 text-xs text-[var(--fg-3)]">Lidas de public.compras (a Hotmart manda no dinheiro); nada é copiado para cá.</p>
          </section>
        </div>
      )}
      {novo && p && (
        <NovoNegocioModal config={config} pipelineId={config.pipelines[0]?.id ?? 0} projeto={null} pessoa={{ id: p.id, nome: p.nome }}
          onFechar={() => setNovo(false)} flash={flash} onMudou={onMudou} />
      )}
    </Drawer>
  );
}
