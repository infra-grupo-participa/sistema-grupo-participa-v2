'use client';

// Laboratório de decisões e testes (Infra › Laboratório). Especificação: docs/projetos/laboratorio/.
import { useEffect, useMemo, useState } from 'react';
import { Badge, Button, Card, EmptyState, FilterSelect, Modal, SearchInput, Skeleton, Tabs, Textarea, Toast, Toolbar, useFlash } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { precisaTestar, ROTULO_RESULTADO, sugerirNivel } from '../domain/estatistica';
import { logCsv, painel } from '../domain/painel';
import { PLAYBOOK_MD } from '../domain/playbook-md';
import { AREAS, NIVEIS, rotuloArea, STATUS, type Experimento, type Nivel, type Pessoa, type Status } from '../domain/types';
import { labRepo } from '../infrastructure/repositorio';
import { CalculadoraAvulsa, Rotulo, TOM_RESULTADO } from './Calculadora';
import { FichaExperimento } from './FichaExperimento';
import { FormFicha, paraSalvar, type Rascunho } from './FormFicha';
import { Markdown } from './Markdown';

type Aba = 'inicio' | 'log' | 'calculadora' | 'como';

export function LaboratorioClient() {
  const [aba, setAba] = useState<Aba>('inicio');
  const [lista, setLista] = useState<Experimento[] | null>(null);
  const [equipe, setEquipe] = useState<Pessoa[]>([]);
  const [erro, setErro] = useState<string | null>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  const { toast, flash } = useFlash(4000);

  const carregar = async () => {
    try {
      const [l, eq] = await Promise.all([labRepo.listar(), labRepo.equipe()]);
      setLista(l);
      setEquipe(eq);
      setErro(null);
    } catch (e) { setErro(e instanceof Error ? e.message : 'Não foi possível carregar.'); }
  };
  // eslint-disable-next-line react-hooks/set-state-in-effect -- carga inicial vinda da RPC
  useEffect(() => { void carregar(); }, []);

  return (
    <div className="max-w-6xl space-y-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra</div>
          <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Laboratório de decisões e testes</h1>
          <p className="mt-1 max-w-2xl text-sm text-[var(--fg-2)]">Antes de decidir, escreva o que você espera. Depois, confira se aconteceu. Sempre do mesmo jeito.</p>
        </div>
        <Button onClick={() => setNovo(true)}><Icon name="plus" size={16} /> Nova decisão ou teste</Button>
      </div>

      <Tabs idBase="lab" label="Laboratório" active={aba} onChange={(k) => setAba(k as Aba)} tabs={[
        { k: 'inicio', l: 'Início' }, { k: 'log', l: 'Log', n: lista?.length }, { k: 'calculadora', l: 'Calculadora' }, { k: 'como', l: 'Como funciona' },
      ]} />

      {erro && <Card className="p-4 text-sm text-[var(--red)]">{erro} <Button variant="link" onClick={() => void carregar()}>Tentar de novo</Button></Card>}
      {!erro && !lista && aba !== 'calculadora' && aba !== 'como' && <div className="space-y-3"><Skeleton h={80} /><Skeleton h={200} /></div>}

      {lista && aba === 'inicio' && <Inicio lista={lista} abrir={setAberto} />}
      {lista && aba === 'log' && <Log lista={lista} abrir={setAberto} />}
      {aba === 'calculadora' && <CalculadoraAvulsa />}
      {aba === 'como' && <Card className="p-6"><Markdown texto={PLAYBOOK_MD} /></Card>}

      {novo && <Assistente equipe={equipe} onClose={() => setNovo(false)} flash={flash} onCriado={(id) => { setNovo(false); void carregar(); setAberto(id); }} />}
      {aberto && <FichaExperimento id={aberto} equipe={equipe} flash={flash} onClose={() => setAberto(null)} onMudou={() => void carregar()} />}
      {toast && <Toast>{toast}</Toast>}
    </div>
  );
}

function Linha({ e, abrir, destaque }: { e: Experimento; abrir: (id: string) => void; destaque?: React.ReactNode }) {
  const st = STATUS[e.status];
  return (
    <button type="button" onClick={() => abrir(e.id)} className="flex w-full flex-wrap items-center gap-x-3 gap-y-1 border-t border-[var(--border)] px-4 py-3 text-left transition-colors first:border-0 hover:bg-[var(--surface-3)]">
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold text-[var(--fg)]">{e.titulo}</span>
        <span className="block truncate text-xs text-[var(--fg-3)]">{rotuloArea(e.area)} · Nível {e.nivel} · {e.hipotese ?? 'sem hipótese ainda'}</span>
      </span>
      {destaque}
      {e.resultado ? <Badge tone={TOM_RESULTADO[e.resultado]}>{ROTULO_RESULTADO[e.resultado]}</Badge> : <Badge tone={st.tom} dot>{st.l}</Badge>}
    </button>
  );
}

function Inicio({ lista, abrir }: { lista: Experimento[]; abrir: (id: string) => void }) {
  const p = useMemo(() => painel(lista), [lista]);
  const kpi = (l: string, v: React.ReactNode, d?: string) => (
    <Card className="p-4"><div className="text-xs text-[var(--fg-3)]">{l}</div><div className="mt-1 text-2xl font-bold tabular-nums text-[var(--fg)]">{v}</div>{d && <div className="text-xs text-[var(--fg-3)]">{d}</div>}</Card>
  );
  const data = (e: Experimento) => {
    const d = e.nivel === 1 ? e.revisao_em : e.leitura_em;
    return d ? <span className={`text-xs ${p.vencida(e) ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>{e.nivel === 1 ? 'revisar' : 'ler'} em {fmtData(d)}</span> : null;
  };
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {kpi('No ar agora', p.ativos.length, 'decisões e testes rodando')}
        {kpi('Leituras e revisões', p.leiturasVencendo.length + p.revisoesPendentes.length, 'vencidas ou nos próximos 2 dias')}
        {kpi('Acerto das apostas (nível 1)', p.taxaAcerto == null ? '—' : `${Math.round(p.taxaAcerto * 100)}%`, `${p.revisados} revisões`)}
        {kpi('Vencedores', `${p.vencedores} de ${p.concluidos}`, 'testes concluídos (níveis 2 e 3)')}
      </div>
      <Card className="overflow-hidden">
        <div className="px-4 pt-4 text-sm font-semibold text-[var(--fg)]">Para ler ou revisar</div>
        {p.leiturasVencendo.length + p.revisoesPendentes.length === 0
          ? <div className="p-4"><EmptyState title="Nada vencendo" hint="Olhe todo dia, mas decida só na data marcada." icon="check" /></div>
          : <div className="mt-2">{[...p.leiturasVencendo, ...p.revisoesPendentes].map((e) => <Linha key={e.id} e={e} abrir={abrir} destaque={data(e)} />)}</div>}
      </Card>
      <Card className="overflow-hidden">
        <div className="px-4 pt-4 text-sm font-semibold text-[var(--fg)]">No ar</div>
        {p.ativos.length === 0
          ? <div className="p-4"><EmptyState title="Nenhum teste no ar" hint="Comece por “Nova decisão ou teste”." icon="target" /></div>
          : <div className="mt-2">{p.ativos.map((e) => <Linha key={e.id} e={e} abrir={abrir} destaque={data(e)} />)}</div>}
      </Card>
      {p.rascunhos.length > 0 && (
        <Card className="overflow-hidden">
          <div className="px-4 pt-4 text-sm font-semibold text-[var(--fg)]">Rascunhos</div>
          <div className="mt-2">{p.rascunhos.map((e) => <Linha key={e.id} e={e} abrir={abrir} />)}</div>
        </Card>
      )}
      <Card className="p-4 text-sm text-[var(--fg-2)]">
        <strong className="text-[var(--fg)]">Resumo de bolso.</strong> Escreva antes · compare no mesmo período, com sorteio sempre que der · uma mudança de cada vez · escolha a régua antes · calcule a amostra · não mexa no meio e não pare no dia bonito · 95% é comprovado, 90–95% provável, abaixo de 90% é ruído · inconclusivo não é igual · registre no log, inclusive o que deu errado.
      </Card>
    </div>
  );
}

function Log({ lista, abrir }: { lista: Experimento[]; abrir: (id: string) => void }) {
  const [busca, setBusca] = useState('');
  const [area, setArea] = useState('');
  const [nivel, setNivel] = useState('');
  const [status, setStatus] = useState('');
  const filtrados = lista.filter((e) =>
    (!area || e.area === area) && (!nivel || String(e.nivel) === nivel) && (!status || e.status === status) &&
    (!busca || `${e.titulo} ${e.hipotese ?? ''} ${e.aprendizado ?? ''}`.toLowerCase().includes(busca.toLowerCase())));
  const baixar = () => {
    const blob = new Blob(['﻿' + logCsv(filtrados)], { type: 'text/csv;charset=utf-8' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'log-de-decisoes-e-testes.csv';
    a.click();
    URL.revokeObjectURL(a.href);
  };
  return (
    <div className="space-y-4">
      <Toolbar>
        <SearchInput placeholder="Buscar no log" value={busca} onChange={(e) => setBusca(e.target.value)} className="!w-64" />
        <FilterSelect value={area} onChange={(e) => setArea(e.target.value)}><option value="">Todas as áreas</option>{AREAS.map((a) => <option key={a.k} value={a.k}>{a.l}</option>)}</FilterSelect>
        <FilterSelect value={nivel} onChange={(e) => setNivel(e.target.value)}><option value="">Todos os níveis</option>{[1, 2, 3].map((n) => <option key={n} value={n}>Nível {n}</option>)}</FilterSelect>
        <FilterSelect value={status} onChange={(e) => setStatus(e.target.value)}><option value="">Todos os status</option>{(Object.keys(STATUS) as Status[]).map((s) => <option key={s} value={s}>{STATUS[s].l}</option>)}</FilterSelect>
        <Button variant="ghost" size="sm" onClick={baixar} disabled={!filtrados.length}><Icon name="download" size={14} /> Exportar CSV</Button>
      </Toolbar>
      <Card className="overflow-x-auto">
        {filtrados.length === 0 ? <div className="p-4"><EmptyState title="Nada no log com esses filtros" /></div> : (
          <table className="w-full min-w-[900px] text-sm">
            <thead className="bg-[var(--surface-2)] text-left text-xs text-[var(--fg-3)]">
              <tr>{['Criado', 'Área', 'Nível', 'Decisão ou teste', 'Hipótese', 'Leitura em', 'Resultado', 'Confiança', 'O que aprendemos'].map((h) => <th key={h} className="px-3 py-2 font-semibold">{h}</th>)}</tr>
            </thead>
            <tbody>
              {filtrados.map((e) => (
                <tr key={e.id} onClick={() => abrir(e.id)} className="cursor-pointer border-t border-[var(--border)] align-top hover:bg-[var(--surface-3)]">
                  <td className="px-3 py-2 text-xs text-[var(--fg-3)]">{fmtData(e.criado_em)}</td>
                  <td className="px-3 py-2 text-xs">{rotuloArea(e.area)}</td>
                  <td className="px-3 py-2 text-xs">{e.nivel}</td>
                  <td className="px-3 py-2 font-medium text-[var(--fg)]">{e.titulo}</td>
                  <td className="px-3 py-2 text-xs text-[var(--fg-2)]">{e.hipotese}</td>
                  <td className="px-3 py-2 text-xs">{fmtData(e.nivel === 1 ? e.revisao_em : e.leitura_em)}</td>
                  <td className="px-3 py-2">{e.resultado ? <Badge tone={TOM_RESULTADO[e.resultado]}>{ROTULO_RESULTADO[e.resultado]}</Badge> : e.revisao_bateu ? <Badge>{e.revisao_bateu === 'sim' ? 'Bateu' : e.revisao_bateu === 'nao' ? 'Não bateu' : 'Sem como saber'}</Badge> : <Badge tone={STATUS[e.status].tom} dot>{STATUS[e.status].l}</Badge>}</td>
                  <td className="px-3 py-2 text-xs tabular-nums">{e.confianca != null ? `${(e.confianca * 100).toFixed(1).replace('.', ',')}%` : ''}</td>
                  <td className="px-3 py-2 text-xs text-[var(--fg-2)]">{e.aprendizado}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </Card>
    </div>
  );
}

/** Assistente: as perguntas da seção 3 sugerem o nível; a pergunta de controle (seção 10) vem antes de qualquer teste. */
function Assistente({ equipe, onClose, onCriado, flash }: { equipe: Pessoa[]; onClose: () => void; onCriado: (id: string) => void; flash: (m: string) => void }) {
  const [passo, setPasso] = useState<1 | 2>(1);
  const [pequena, setPequena] = useState<boolean | null>(null);
  const [volume, setVolume] = useState<boolean | null>(null);
  const [nivel, setNivel] = useState<Nivel | null>(null);
  const [rasc, setRasc] = useState<Rascunho>({ area: 'outro', titulo: '' });
  const [ocupado, setOcupado] = useState(false);
  const sugerido = pequena == null ? null : pequena ? 1 : volume == null ? null : sugerirNivel({ pequenaEReversivel: pequena, temVolumeESorteio: volume });
  const nv = (nivel ?? sugerido) as Nivel | null;
  const naoPrecisa = !!(rasc.controle_a?.trim() && rasc.controle_b?.trim()) && !precisaTestar(rasc.controle_a ?? '', rasc.controle_b ?? '');

  const sim = (v: boolean | null, set: (b: boolean) => void) => (
    <div className="flex gap-2">
      <Button size="sm" variant={v === true ? 'primary' : 'ghost'} onClick={() => set(true)}>Sim</Button>
      <Button size="sm" variant={v === false ? 'primary' : 'ghost'} onClick={() => set(false)}>Não</Button>
    </div>
  );

  const salvar = async (porNoAr: boolean) => {
    if (!nv) return;
    if (!rasc.titulo?.trim()) { flash('Dê um nome à decisão ou teste.'); return; }
    setOcupado(true);
    const r = await labRepo.salvar(paraSalvar({ ...rasc, nivel: nv }));
    if (r.ok && r.id && porNoAr) {
      const s = await labRepo.status(r.id, 'no_ar');
      flash(s.msg);
    } else flash(r.msg);
    setOcupado(false);
    if (r.ok && r.id) onCriado(r.id);
  };

  return (
    <Modal onClose={onClose} title="Nova decisão ou teste" width="max-w-3xl" footer={passo === 1 ? (
      <div className="flex w-full justify-end gap-2">
        <Button variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button disabled={!nv} onClick={() => setPasso(2)}>Preencher a ficha</Button>
      </div>
    ) : (
      <div className="flex w-full flex-wrap justify-between gap-2">
        <Button variant="ghost" onClick={() => setPasso(1)}>Voltar</Button>
        <div className="flex gap-2">
          <Button variant="ghost" disabled={ocupado} onClick={() => salvar(false)}>Salvar rascunho</Button>
          <Button disabled={ocupado} onClick={() => salvar(true)}>{nv === 1 ? 'Registrar decisão' : 'Salvar e pôr no ar'}</Button>
        </div>
      </div>
    )}>
      {passo === 1 ? (
        <div className="space-y-5">
          <Card className="space-y-3 p-4">
            <Rotulo dica="Quanto custa errar (dinheiro, tempo, imagem, pessoas)? Dá para voltar atrás amanhã sem custo?">1. A decisão é pequena e fácil de desfazer?</Rotulo>
            {sim(pequena, (b) => { setPequena(b); setNivel(null); })}
            {pequena === false && <>
              <Rotulo dica="Muitos casos (visitas, leads, mensagens) e dá para sortear quem recebe a versão nova?">2. Tenho volume e consigo sortear quem recebe a mudança?</Rotulo>
              {sim(volume, (b) => { setVolume(b); setNivel(null); })}
            </>}
          </Card>
          <Card className="space-y-3 p-4">
            <Rotulo dica="Seção 10. Se as duas respostas forem iguais, não precisa testar.">Pergunta de controle</Rotulo>
            <div className="grid gap-3 sm:grid-cols-2">
              <label className="block space-y-1"><Rotulo>Se o resultado vier A, fazemos o quê?</Rotulo><Textarea rows={2} value={rasc.controle_a ?? ''} onChange={(e) => setRasc({ ...rasc, controle_a: e.target.value })} /></label>
              <label className="block space-y-1"><Rotulo>E se vier B?</Rotulo><Textarea rows={2} value={rasc.controle_b ?? ''} onChange={(e) => setRasc({ ...rasc, controle_b: e.target.value })} /></label>
            </div>
            {naoPrecisa && <p className="text-sm text-[var(--yellow)]">As duas respostas são iguais: não precisa testar. Se quiser, registre como decisão (nível 1) e siga em frente.</p>}
          </Card>
          {sugerido && (
            <Card className="space-y-3 p-4">
              <div className="text-sm text-[var(--fg)]">Nível sugerido: <strong>{sugerido}. {NIVEIS[sugerido].nome}</strong></div>
              <p className="text-xs text-[var(--fg-3)]">Na dúvida entre dois níveis, use o mais simples que ainda responde à pergunta.</p>
              <div className="grid gap-2 sm:grid-cols-3">
                {([1, 2, 3] as Nivel[]).map((n) => (
                  <button key={n} type="button" onClick={() => setNivel(n)} className={`rounded-[var(--r-md)] border p-3 text-left text-xs transition-colors ${nv === n ? 'border-[var(--accent)] bg-[var(--accent-subtle)]' : 'border-[var(--border)] hover:bg-[var(--surface-3)]'}`}>
                    <span className="block text-sm font-semibold text-[var(--fg)]">{n}. {NIVEIS[n].nome}</span>
                    <span className="text-[var(--fg-2)]">{NIVEIS[n].quando}</span>
                  </button>
                ))}
              </div>
            </Card>
          )}
        </div>
      ) : nv && (
        <div className="space-y-4">
          <p className="text-sm text-[var(--fg-2)]">Nível {nv}: {NIVEIS[nv].nome}. {nv === 3 ? 'As sete regras: ficha antes, uma variável, sorteio e mesmo período, amostra calculada, duração mínima, não mexer no meio, conferir a medição antes de ligar.' : nv === 2 ? 'Compare dois grupos parecidos no mesmo período e olhe a diferença das diferenças.' : 'Escreva a previsão com número e a data de revisão.'}</p>
          <FormFicha valor={rasc} onChange={setRasc} nivel={nv} equipe={equipe} travado={false} />
        </div>
      )}
    </Modal>
  );
}
