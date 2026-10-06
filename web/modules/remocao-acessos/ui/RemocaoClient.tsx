'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge, Button, DataTable, EmptyState, Loading, SectionCard, Tabs, Td, Th, Thead, Toast, Tr, useFlash,
} from '@/shared/ui/components';
import { fmtBRL, fmtDataHora } from '@/shared/ui/format';
import { SupabaseRemocaoRepository } from '../infrastructure/supabase-remocao.repository';
import {
  ABERTOS, filtrarCasos, filtrarLinha, linhaDoCaso, linhaDoItem, meusItensDaLinha, ROTULO_LINHA, ROTULO_TIPO, rotuloDataCaso, rotuloStatus, situacaoPrazo, TOM_STATUS,
  type Filtro,
} from '../domain/caso';
import type { CasoFila, ItemCatalogo, Linha, MeuPapel } from '../domain/types';
import { CasoDrawer } from './CasoDrawer';

const repo = new SupabaseRemocaoRepository();

// 'fila' é a fila do Holding Masters (sem hash, como antes); '#acelera' e '#responsaveis' são as outras.
type Aba = 'fila' | 'acelera' | 'responsaveis';

const LINHA_DA_ABA: Partial<Record<Aba, Linha>> = { fila: 'hm', acelera: 'acelera' };
const ABA_DA_LINHA: Record<Linha, Aba> = { hm: 'fila', acelera: 'acelera' };
const HASH_DA_ABA: Record<Aba, string> = { fila: '', acelera: '#acelera', responsaveis: '#responsaveis' };

function abaDoHash(hash: string): Aba | null {
  if (hash === '#responsaveis') return 'responsaveis';
  if (hash === '#acelera') return 'acelera';
  return null;
}

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
  // Link do Slack com ?caso=: a aba segue a linha do caso, mesmo se a fila não carregou.
  const viaLink = useRef(false);

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
      // Todo mundo abre em "Em aberto": quem já fez a sua parte continua vendo o que falta dos outros.
      // Link do Slack: /relatorios/remocoes?caso=<id> (308 para /educacional/remocoes?caso=<id>) abre a ficha direto.
      const id = new URLSearchParams(window.location.search).get('caso');
      const doHash = abaDoHash(window.location.hash);
      if (doHash) setAba(doHash);
      if (id) {
        const doLink = r.f?.find((c) => c.id === id);
        if (doLink) setAba(ABA_DA_LINHA[linhaDoCaso(doLink)]);
        else viaLink.current = true;
        setAberto(id);
      }
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
    history.replaceState(null, '', HASH_DA_ABA[a] || window.location.pathname + window.location.search);
  };

  const casoCarregou = useCallback((l: Linha) => {
    if (!viaLink.current) return;
    viaLink.current = false;
    setAba(ABA_DA_LINHA[l]);
    history.replaceState(null, '', window.location.pathname + window.location.search + HASH_DA_ABA[ABA_DA_LINHA[l]]);
  }, []);

  const fecharCaso = () => {
    viaLink.current = false;
    setAberto(null);
    if (window.location.search) history.replaceState(null, '', window.location.pathname + window.location.hash);
  };

  const linha: Linha = LINHA_DA_ABA[aba] ?? 'hm';
  const daLinha = useMemo(() => filtrarLinha(casos ?? [], linha), [casos, linha]);
  const abertosPorLinha = useMemo(() => ({
    hm: filtrarCasos(casos ?? [], 'abertos', 'hm').length,
    acelera: filtrarCasos(casos ?? [], 'abertos', 'acelera').length,
  }), [casos]);

  const contagem = useMemo(() => {
    const l = daLinha;
    return {
      abertos: filtrarCasos(l, 'abertos').length,
      meus: filtrarCasos(l, 'meus').length,
      alertas: filtrarCasos(l, 'alertas').length,
      encerrados: filtrarCasos(l, 'encerrados').length,
      todos: l.length,
      atrasados: l.filter((c) => situacaoPrazo(c, agora) === 'atrasado').length,
      triagem: l.filter((c) => c.status === 'aguardando_triagem').length,
    };
  }, [daLinha, agora]);

  const lista = useMemo(() => filtrarCasos(daLinha, filtro), [daLinha, filtro]);
  const meusItens = meusItensDaLinha(papel?.meus_itens, linha);
  const ehAcelera = linha === 'acelera';

  const FILTROS: { k: Filtro; l: string }[] = [
    { k: 'abertos', l: `Em aberto (${contagem.abertos})` },
    { k: 'meus', l: `Meus pendentes (${contagem.meus})` },
    // No Acelera o alerta também é reembolso de quem ainda tem outra compra válida, não só disputa.
    { k: 'alertas', l: `${ehAcelera ? 'Alertas' : 'Disputas'} (${contagem.alertas})` },
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
        {aba === 'fila' && <>
          Reembolso e chargeback do Holding Masters, e sócio que saiu numa troca de sócio aprovada. Cada caso passa pela triagem e depois cada responsável marca o que removeu,
          para o titular e cada sócio. Prazo: 1 dia útil (9h às 18h, sem feriado).
        </>}
        {aba === 'acelera' && <>
          Reembolso e chargeback do Acelera Holding. Sem triagem e sem sócios: o caso já nasce com os itens de remoção, e cada responsável marca o que removeu.
          Disputa, e reembolso de quem ainda tem outra compra válida, ficam só como alerta. Os casos antigos importados não têm prazo. Nos casos importados a data é a da compra: o financeiro não guarda a data do reembolso.
        </>}
        {aba === 'responsaveis' && <>Quem marca cada item de remoção, por linha.</>}
        {aba !== 'responsaveis' && meusItens.length > 0 && <> Seus itens: <b className="text-[var(--fg-2)]">{meusItens.join(', ')}</b>.</>}
      </p>

      <div className="mb-4">
        <Tabs
          tabs={[
            { k: 'fila', l: ROTULO_LINHA.hm, n: abertosPorLinha.hm },
            { k: 'acelera', l: ROTULO_LINHA.acelera, n: abertosPorLinha.acelera },
            { k: 'responsaveis', l: 'Quem remove o quê' },
          ]}
          active={aba}
          onChange={trocarAba}
        />
      </div>

      {(aba === 'fila' || aba === 'acelera') && (
        <>
          <div className="flex flex-wrap gap-2 mb-3">
            {!ehAcelera && <Badge tone={contagem.triagem ? 'warning' : 'neutral'}>{contagem.triagem} aguardando triagem</Badge>}
            <Badge tone={contagem.atrasados ? 'danger' : 'neutral'}>{contagem.atrasados} atrasado(s)</Badge>
          </div>
          <div className="flex flex-wrap gap-1.5 mb-3" role="tablist">
            {FILTROS.map((f) => (
              <Button key={f.k} size="sm" variant={filtro === f.k ? 'subtle' : 'ghost'} onClick={() => setFiltro(f.k)} aria-pressed={filtro === f.k}>
                {f.l}
              </Button>
            ))}
          </div>

          {erro && casos && (
            // Falha na releitura não apaga a fila: segura a última lista, esmaece e diz de quando ela é.
            <div className="mb-3"><Badge tone="warning">{erro} Mostrando os dados de {fmtDataHora(agora)}.</Badge></div>
          )}
          {erro && !casos ? (
            <EmptyState title={erro} icon="alert" hint="Clique em Atualizar para tentar de novo." />
          ) : !casos ? (
            <Loading label="Carregando casos…" minHeight={200} />
          ) : !lista.length ? (
            <EmptyState
              title={filtro === 'meus' ? 'Nada pendente com você' : 'Nenhum caso aqui'}
              hint={ehAcelera
                ? 'Os casos nascem sozinhos quando a Hotmart registra reembolso, chargeback ou disputa do Acelera Holding.'
                : 'Os casos nascem sozinhos quando a Hotmart registra reembolso, chargeback ou disputa do Holding Masters, ou quando uma troca de sócio é aprovada.'}
              icon="inbox"
            />
          ) : (
            <div className={erro ? 'opacity-60' : undefined}>
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
                        {!ehAcelera && c.pessoas > 1 ? `titular + ${c.pessoas - 1} sócio(s)` : 'titular'}
                        {c.eh_programa && ' · Programa de Implementação'}
                      </div>
                      {c.teste && <div className="mt-1"><Badge tone="info">Teste</Badge></div>}
                    </Td>
                    <Td><Badge tone={c.tipo === 'disputa' ? 'info' : 'danger'}>{ROTULO_TIPO[c.tipo]}</Badge></Td>
                    <Td>
                      <span className="inline-flex flex-col gap-0.5">
                        <Badge tone={TOM_STATUS[c.status]}>{rotuloStatus(c)}</Badge>
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
                      ) : <span className="text-[var(--fg-3)]">{ABERTOS.includes(c.status) && !ehAcelera ? 'após triagem' : 'não se aplica'}</span>}
                    </Td>
                    <Td><Prazo c={c} agora={agora} /></Td>
                    <Td className="tabular text-[var(--fg-2)]">
                      {fmtDataHora(c.ocorrido_em)}
                      {c.origem === 'carga' && <span className="block text-[11px] text-[var(--fg-3)]">data da compra</span>}
                    </Td>
                    <Td className="tabular text-[var(--fg-2)]">{c.valor != null ? fmtBRL(c.valor) : 'sem valor'}</Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
            </div>
          )}
        </>
      )}

      {aba === 'responsaveis' && (
        !catalogo ? (
          <Loading label="Carregando…" minHeight={120} />
        ) : (
          <div className="flex flex-col gap-4">
            {(['hm', 'acelera'] as const).map((l) => {
              const itens = catalogo.filter((i) => i.ativo && linhaDoItem(i) === l);
              return (
                <SectionCard
                  key={l}
                  title={`Quem remove o quê · ${ROTULO_LINHA[l]}`}
                  subtitle={l === 'hm'
                    ? 'Vale para o titular e para cada sócio. Só o responsável marca o próprio item; quem faz a triagem pode corrigir, e a correção fica registrada.'
                    : 'Sem triagem e sem sócios. Só o responsável marca o próprio item.'}
                >
                  {!itens.length ? (
                    <p className="text-sm text-[var(--fg-3)]">Nenhum item cadastrado para esta linha.</p>
                  ) : (
                    <DataTable>
                      <Thead>
                        <Th>Item</Th>
                        <Th>Responsável</Th>
                        <Th>Quando entra</Th>
                      </Thead>
                      <tbody>
                        {itens.map((i) => (
                          <Tr key={i.item}>
                            <Td className="font-semibold text-[var(--fg)]">{i.rotulo}</Td>
                            <Td>
                              <div className="text-[var(--fg)]">{i.responsavel || 'sem responsável'}</div>
                              {i.email && <div className="text-[11px] text-[var(--fg-3)]">{i.email}</div>}
                            </Td>
                            <Td className="text-[var(--fg-2)]">{i.fluxo === 'ajuste' ? 'Quando não remove (mantém acesso antigo)' : i.so_programa ? 'Remoção, só se a pessoa é do Programa de Implementação' : 'Remoção'}</Td>
                          </Tr>
                        ))}
                      </tbody>
                    </DataTable>
                  )}
                </SectionCard>
              );
            })}
          </div>
        )
      )}

      {aberto && (
        <CasoDrawer
          id={aberto}
          repo={repo}
          onClose={fecharCaso}
          onMudou={carregar}
          onCarregou={casoCarregou}
          flash={flash}
        />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
