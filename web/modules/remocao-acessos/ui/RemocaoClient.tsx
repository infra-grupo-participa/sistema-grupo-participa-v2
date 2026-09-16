'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Badge, Button, DataTable, EmptyState, Loading, SectionCard, Tabs, Td, Th, Thead, Toast, Tr, useFlash,
} from '@/shared/ui/components';
import { fmtBRL, fmtDataHora } from '@/shared/ui/format';
import { SupabaseRemocaoRepository } from '../infrastructure/supabase-remocao.repository';
import { ABERTOS, filtrarCasos, ROTULO_STATUS, ROTULO_TIPO, situacaoPrazo, TOM_STATUS, type Filtro } from '../domain/caso';
import type { CasoFila, ItemCatalogo, MeuPapel } from '../domain/types';
import { CasoDrawer } from './CasoDrawer';

const repo = new SupabaseRemocaoRepository();

type Aba = 'fila' | 'responsaveis';

function Prazo({ c, agora }: { c: CasoFila; agora: Date }) {
  const s = situacaoPrazo(c, agora);
  if (s === 'encerrado') return <span className="text-[var(--fg-3)]">{c.concluido_em ? fmtDataHora(c.concluido_em) : 'sem prazo'}</span>;
  if (s === 'sem_prazo') return <span className="text-[var(--fg-3)]">sem prazo</span>;
  const tone = s === 'atrasado' ? 'danger' : s === 'vence_hoje' ? 'warning' : 'neutral';
  const txt = s === 'atrasado' ? 'Atrasado' : s === 'vence_hoje' ? 'Vence hoje' : 'No prazo';
  return (
    <span className="inline-flex flex-col gap-0.5">
      <Badge tone={tone}>{txt}</Badge>
      <span className="text-[11px] text-[var(--fg-3)] tabular">{fmtDataHora(c.prazo_em)}</span>
    </span>
  );
}

export function RemocaoClient() {
  const { toast, flash } = useFlash();
  const [aba, setAba] = useState<Aba>('fila');
  const [filtro, setFiltro] = useState<Filtro>('abertos');
  const [papel, setPapel] = useState<MeuPapel | null>(null);
  const [casos, setCasos] = useState<CasoFila[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [catalogo, setCatalogo] = useState<ItemCatalogo[] | null>(null);
  const [agora, setAgora] = useState(() => new Date());

  const buscar = useCallback(async () => {
    try {
      const [p, f] = await Promise.all([repo.meuPapel(), repo.fila()]);
      return { p, f, erro: null as string | null };
    } catch (e) {
      return { p: null, f: null, erro: e instanceof Error ? e.message : 'Não foi possível carregar os casos.' };
    }
  }, []);

  const aplicar = useCallback((r: Awaited<ReturnType<typeof buscar>>) => {
    if (r.erro) { setErro(r.erro); return; }
    setPapel(r.p);
    setCasos(r.f);
    setErro(null);
    setAgora(new Date());
  }, []);

  const carregar = useCallback(async () => aplicar(await buscar()), [aplicar, buscar]);

  useEffect(() => {
    let vivo = true;
    (async () => {
      const r = await buscar();
      if (!vivo) return;
      aplicar(r);
      // Quem tem item pendente e não faz triagem começa vendo só os dele.
      if (r.f?.some((c) => c.meus_pendentes > 0) && !r.p?.pode_triar) setFiltro('meus');
      // Link do Slack: /relatorios/remocoes?caso=<id> abre a ficha direto.
      const id = new URLSearchParams(window.location.search).get('caso');
      if (id) setAberto(id);
      if (window.location.hash === '#responsaveis') setAba('responsaveis');
    })();
    const t = setInterval(() => { buscar().then((r) => { if (vivo) aplicar(r); }); }, 60_000);
    return () => { vivo = false; clearInterval(t); };
  }, [aplicar, buscar]);

  useEffect(() => {
    if (aba !== 'responsaveis' || catalogo) return;
    let vivo = true;
    repo.responsaveis()
      .then((r) => { if (vivo) setCatalogo(r); })
      .catch(() => flash('Não foi possível carregar os responsáveis.'));
    return () => { vivo = false; };
  }, [aba, catalogo, flash]);

  const trocarAba = (k: string) => {
    const a = k as Aba;
    setAba(a);
    history.replaceState(null, '', a === 'fila' ? window.location.pathname : '#responsaveis');
  };

  const fecharCaso = () => {
    setAberto(null);
    if (window.location.search) history.replaceState(null, '', window.location.pathname + window.location.hash);
  };

  const contagem = useMemo(() => {
    const l = casos ?? [];
    return {
      abertos: filtrarCasos(l, 'abertos').length,
      meus: filtrarCasos(l, 'meus').length,
      alertas: filtrarCasos(l, 'alertas').length,
      encerrados: filtrarCasos(l, 'encerrados').length,
      todos: l.length,
      atrasados: l.filter((c) => situacaoPrazo(c, agora) === 'atrasado').length,
      triagem: l.filter((c) => c.status === 'aguardando_triagem').length,
    };
  }, [casos, agora]);

  const lista = useMemo(() => filtrarCasos(casos ?? [], filtro), [casos, filtro]);

  const FILTROS: { k: Filtro; l: string }[] = [
    { k: 'abertos', l: `Em aberto (${contagem.abertos})` },
    { k: 'meus', l: `Meus pendentes (${contagem.meus})` },
    { k: 'alertas', l: `Disputas (${contagem.alertas})` },
    { k: 'encerrados', l: `Encerrados (${contagem.encerrados})` },
    { k: 'todos', l: `Todos (${contagem.todos})` },
  ];

  return (
    <div>
      <div className="flex items-start justify-between gap-3 flex-wrap mb-1">
        <h1 className="text-2xl font-bold text-[var(--fg)]">
          Remoção de <span className="text-[var(--accent)]">Acessos</span>
        </h1>
        <Button variant="ghost" size="sm" onClick={carregar}>Atualizar</Button>
      </div>
      <p className="text-sm text-[var(--fg-3)] mb-4 max-w-[70ch]">
        Reembolso e chargeback do Holding Masters. Cada caso passa pela triagem e depois cada responsável marca o que removeu,
        para o titular e cada sócio. Prazo: 1 dia útil (9h às 18h, sem feriado).
        {papel && papel.meus_itens.length > 0 && <> Seus itens: <b className="text-[var(--fg-2)]">{papel.meus_itens.join(', ')}</b>.</>}
      </p>

      <div className="mb-4">
        <Tabs tabs={[{ k: 'fila', l: 'Casos' }, { k: 'responsaveis', l: 'Quem remove o quê' }]} active={aba} onChange={trocarAba} />
      </div>

      {aba === 'fila' && (
        <>
          <div className="flex flex-wrap gap-2 mb-3">
            <Badge tone={contagem.triagem ? 'warning' : 'neutral'}>{contagem.triagem} aguardando triagem</Badge>
            <Badge tone={contagem.atrasados ? 'danger' : 'neutral'}>{contagem.atrasados} atrasado(s)</Badge>
          </div>
          <div className="flex flex-wrap gap-1.5 mb-3" role="tablist">
            {FILTROS.map((f) => (
              <Button key={f.k} size="sm" variant={filtro === f.k ? 'subtle' : 'ghost'} onClick={() => setFiltro(f.k)} aria-pressed={filtro === f.k}>
                {f.l}
              </Button>
            ))}
          </div>

          {erro ? (
            <EmptyState title={erro} icon="alert" hint="Clique em Atualizar para tentar de novo." />
          ) : !casos ? (
            <Loading label="Carregando casos…" minHeight={200} />
          ) : !lista.length ? (
            <EmptyState
              title={filtro === 'meus' ? 'Nada pendente com você' : 'Nenhum caso aqui'}
              hint="Os casos nascem sozinhos quando a Hotmart registra reembolso, chargeback ou disputa do Holding Masters."
              icon="inbox"
            />
          ) : (
            <DataTable minWidth={880}>
              <Thead>
                <Th>Pessoa</Th>
                <Th>Tipo</Th>
                <Th>Situação</Th>
                <Th>Remoção</Th>
                <Th>Prazo</Th>
                <Th>Ocorreu em</Th>
                <Th>Valor</Th>
              </Thead>
              <tbody>
                {lista.map((c) => (
                  <Tr key={c.id} onClick={() => setAberto(c.id)}>
                    <Td>
                      <div className="font-semibold text-[var(--fg)] truncate max-w-[260px]">{c.nome || 'sem nome'}</div>
                      <div className="text-[11px] text-[var(--fg-3)] truncate max-w-[260px]">
                        {c.pessoas > 1 ? `titular + ${c.pessoas - 1} sócio(s)` : 'titular'}
                        {c.eh_programa && ' · Programa de Implementação'}
                      </div>
                      {c.teste && <div className="mt-1"><Badge tone="info">Teste</Badge></div>}
                    </Td>
                    <Td><Badge tone={c.tipo === 'disputa' ? 'info' : 'danger'}>{ROTULO_TIPO[c.tipo]}</Badge></Td>
                    <Td>
                      <span className="inline-flex flex-col gap-0.5">
                        <Badge tone={TOM_STATUS[c.status]}>{ROTULO_STATUS[c.status]}</Badge>
                        {c.status === 'aguardando_triagem' && c.recomendacao && (
                          <span className="text-[11px] text-[var(--fg-3)]">sugestão: {c.recomendacao}</span>
                        )}
                      </span>
                    </Td>
                    <Td className="tabular">
                      {c.itens_total ? (
                        <span className="inline-flex flex-col gap-0.5">
                          <span className="text-[var(--fg)]">{c.itens_feitos}/{c.itens_total}</span>
                          {c.meus_pendentes > 0 && <span className="text-[11px] text-[var(--accent)]">{c.meus_pendentes} com você</span>}
                        </span>
                      ) : <span className="text-[var(--fg-3)]">{ABERTOS.includes(c.status) ? 'após triagem' : 'não se aplica'}</span>}
                    </Td>
                    <Td><Prazo c={c} agora={agora} /></Td>
                    <Td className="tabular text-[var(--fg-2)]">{fmtDataHora(c.ocorrido_em)}</Td>
                    <Td className="tabular text-[var(--fg-2)]">{c.valor != null ? fmtBRL(c.valor) : 'sem valor'}</Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          )}
        </>
      )}

      {aba === 'responsaveis' && (
        <SectionCard
          title="Quem remove o quê"
          subtitle="Vale para o titular e para cada sócio. Só o responsável marca o próprio item; quem faz a triagem pode corrigir, e a correção fica registrada."
        >
          {!catalogo ? (
            <Loading label="Carregando…" minHeight={120} />
          ) : (
            <DataTable>
              <Thead>
                <Th>Item</Th>
                <Th>Responsável</Th>
                <Th>Quando entra</Th>
              </Thead>
              <tbody>
                {catalogo.filter((i) => i.ativo).map((i) => (
                  <Tr key={i.item}>
                    <Td className="font-semibold text-[var(--fg)]">{i.rotulo}</Td>
                    <Td>
                      <div className="text-[var(--fg)]">{i.responsavel || 'sem responsável'}</div>
                      {i.email && <div className="text-[11px] text-[var(--fg-3)]">{i.email}</div>}
                    </Td>
                    <Td className="text-[var(--fg-2)]">{i.so_programa ? 'Só se a pessoa é do Programa de Implementação' : 'Sempre'}</Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          )}
        </SectionCard>
      )}

      {aberto && (
        <CasoDrawer
          id={aberto}
          repo={repo}
          onClose={fecharCaso}
          onMudou={carregar}
          flash={flash}
        />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
