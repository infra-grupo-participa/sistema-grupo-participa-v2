'use client';

// "Listas para disparo" (topo da Mensageria, dado REAL; Fase 1, decisões do Victor de 13/10). Um cartão por lista com a
// contagem de agora (dados_black_listas_resumo, só números) e os botões Baixar CSV e Ver. A lista com dado pessoal vem de
// dados_black_lista (exige contato.ver), que grava no servidor quem viu ou baixou, qual lista, segmento, linhas e quando.
// CSV montado no navegador, como o "Fora do grupo" do CNHF (controle-de-eventos/client/src/views/ForaDoGrupo.vue): BOM,
// escape, telefone 55 + DDD + número; o telefone fora do padrão vai em arquivo à parte, com o motivo.
// Regras (dedup, sem teste, sem Turma Especial, segmentos) moram no banco: aqui não se recalcula quem entra.
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge, Button, SearchInput, SectionCard } from '@/shared/ui/components';
import {
  csvForaPadrao, csvPrincipal, DICA_SEGMENTO, filtrarBusca, grupoSaida, haQuanto, LISTAS, nomeArquivo, ROTULO_FONTE,
  ROTULO_SEGMENTO, ROTULO_SITUACAO, type PessoaLista, type PresetLista, type Segmento,
} from '../domain/listas';
import { lerLista, lerResumoListas, type ListaLida, type ResumoListas } from '../infrastructure/listas-supabase';
import { PainelLateral } from './GavetaLateral';
import { Chip } from './pecas';

const RELER_MS = 5 * 60_000;

function baixarArquivo(conteudo: string, nome: string) {
  const blob = new Blob([conteudo], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = nome;
  a.click();
  URL.revokeObjectURL(a.href);
}

export function BlocoListas({ chave, demo }: { chave: string; demo: boolean }) {
  const [resumo, setResumo] = useState<ResumoListas | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [agora, setAgora] = useState(() => new Date());
  const [ver, setVer] = useState<{ preset: PresetLista; segmento: Segmento } | null>(null);

  const aplicar = useCallback((r: Awaited<ReturnType<typeof lerResumoListas>>) => {
    setAgora(new Date());
    if (r.erro) setErro(r.erro); else { setErro(null); setResumo(r.data); }
  }, []);

  useEffect(() => {
    if (demo) return;
    let vivo = true;
    const ler = () => lerResumoListas(chave).then((r) => { if (vivo) aplicar(r); });
    void ler();
    const t = setInterval(() => { if (document.visibilityState === 'visible') void ler(); }, RELER_MS);
    const relogio = setInterval(() => setAgora(new Date()), 60_000);
    return () => { vivo = false; clearInterval(t); clearInterval(relogio); };
  }, [demo, chave, aplicar]);

  return (
    <SectionCard
      title="Listas para disparo"
      subtitle="Dado real, direto do banco. Toda lista: uma pessoa por linha (telefone ou e-mail), sem teste, sem a Turma Especial, telefone 55 + DDD + número."
      right={!demo && resumo ? <span className="text-xs text-[var(--fg-3)]">atualizado {haQuanto(resumo.geradoEm, agora)}</span> : null}
      className="border-[var(--accent)]/40"
    >
      {demo ? (
        <p className="text-sm text-[var(--fg-3)]">As listas só existem com dado real (fora do modo de demonstração).</p>
      ) : erro && !resumo ? (
        <p role="alert" className="text-sm text-[var(--red)]">{erro}</p>
      ) : !resumo ? (
        <p className="text-sm text-[var(--fg-3)]">Carregando as listas…</p>
      ) : (
        <>
          <p className="mb-3 text-xs text-[var(--fg-3)]">
            {resumo.turmaEspecial === 1 ? '1 pessoa removida' : `${resumo.turmaEspecial} pessoas removidas`} por ser da Turma Especial.
            {erro && <span role="alert" className="ml-2 text-[var(--red)]">{erro}</span>}
          </p>
          <div className="grid grid-cols-1 gap-3 lg:grid-cols-3">
            {LISTAS.map((p) => <CartaoLista key={p.id} chave={chave} preset={p} resumo={resumo} onVer={(s) => setVer({ preset: p, segmento: s })} />)}
          </div>
        </>
      )}
      {ver && <GavetaLista chave={chave} preset={ver.preset} segmentoInicial={ver.segmento} onClose={() => setVer(null)} />}
    </SectionCard>
  );
}

function CartaoLista({ chave, preset, resumo, onVer }: {
  chave: string; preset: PresetLista; resumo: ResumoListas; onVer: (s: Segmento) => void;
}) {
  const [segmento, setSegmento] = useState<Segmento>('geral');
  const [ocupado, setOcupado] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);
  const c = resumo.listas[`${preset.id}:${segmento}`] ?? { linhas: 0, foraPadrao: 0, semProfissao: 0 };

  const baixar = async (foraPadrao: boolean) => {
    setOcupado(true); setMsg(null);
    const r = await lerLista(chave, preset.id, segmento, 'baixar');
    setOcupado(false);
    if (r.erro || !r.data) { setMsg(r.erro ?? 'Não foi possível baixar.'); return; }
    const agora = new Date();
    if (foraPadrao) baixarArquivo(csvForaPadrao(r.data.foraPadrao), nomeArquivo(preset, segmento, agora, true));
    else baixarArquivo(csvPrincipal(preset, r.data.linhas), nomeArquivo(preset, segmento, agora));
    setMsg(`${foraPadrao ? r.data.foraPadrao.length : r.data.linhas.length} linhas baixadas.`);
  };

  return (
    <div className="flex min-w-0 flex-col gap-2 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
      <h3 className="text-sm font-bold text-[var(--fg)]">{preset.nome}</h3>
      <p className="text-xs text-[var(--fg-3)]">{preset.paraQue}</p>
      {preset.segmentos.length > 1 && (
        <div className="flex flex-wrap gap-1.5" role="group" aria-label="Segmento">
          {preset.segmentos.map((s) => (
            <Chip key={s} ativo={segmento === s} onClick={() => setSegmento(s)} title={DICA_SEGMENTO[s]}>
              {ROTULO_SEGMENTO[s]} <span className="tabular">{resumo.listas[`${preset.id}:${s}`]?.linhas ?? 0}</span>
            </Chip>
          ))}
        </div>
      )}
      <p className="text-2xl font-bold tabular text-[var(--fg)]">
        {c.linhas.toLocaleString('pt-BR')} <span className="text-sm font-normal text-[var(--fg-3)]">{c.linhas === 1 ? 'pessoa' : 'pessoas'}</span>
      </p>
      {segmento === 'outros' && c.semProfissao > 0 && (
        <p className="text-xs text-[var(--fg-3)]">{c.semProfissao} sem profissão (só entraram no grupo, sem formulário).</p>
      )}
      {preset.aviso && <p className="rounded-[var(--r-md)] bg-[var(--surface-3)] p-2 text-xs text-[var(--fg-2)]">{preset.aviso}</p>}
      <div className="mt-auto flex flex-wrap gap-2 pt-1">
        <Button size="sm" disabled={ocupado || c.linhas === 0} onClick={() => void baixar(false)}>Baixar CSV ({c.linhas})</Button>
        <Button size="sm" variant="ghost" onClick={() => onVer(segmento)}>Ver</Button>
      </div>
      {c.foraPadrao > 0 && (
        <p className="text-xs text-[var(--fg-3)]">
          {c.foraPadrao} com telefone fora do padrão ficam fora do CSV.{' '}
          <button type="button" className="text-[var(--accent)] underline-offset-4 hover:underline disabled:opacity-50" disabled={ocupado}
            onClick={() => void baixar(true)}>Baixar esses {c.foraPadrao}, com o motivo</button>
        </p>
      )}
      {msg && <p role="status" className="text-xs text-[var(--fg-2)]">{msg}</p>}
    </div>
  );
}

function GavetaLista({ chave, preset, segmentoInicial, onClose }: {
  chave: string; preset: PresetLista; segmentoInicial: Segmento; onClose: () => void;
}) {
  const [segmento, setSegmento] = useState<Segmento>(segmentoInicial);
  // Resultado guardado com a chave da leitura: trocar de segmento mostra "Carregando" sem zerar estado dentro do efeito.
  const [lido, setLido] = useState<{ k: string; data: ListaLida | null; erro: string | null } | null>(null);
  const [busca, setBusca] = useState('');
  const k = `${preset.id}:${segmento}`;
  const lida = lido?.k === k ? lido.data : null;
  const erro = lido?.k === k ? lido.erro : null;

  useEffect(() => {
    let vivo = true;
    void lerLista(chave, preset.id, segmento, 'ver').then((r) => { if (vivo) setLido({ k: `${preset.id}:${segmento}`, data: r.data, erro: r.erro }); });
    return () => { vivo = false; };
  }, [chave, preset.id, segmento]);

  const todas = useMemo(() => (lida ? [...lida.linhas, ...lida.foraPadrao] : []), [lida]);
  const vistas = useMemo(() => filtrarBusca(todas, busca), [todas, busca]);
  const LIMITE = 200;

  return (
    <PainelLateral aberta tipo="Lista para disparo" titulo={`${preset.nome}${segmento === 'geral' ? '' : ` · ${ROTULO_SEGMENTO[segmento]}`}`} onClose={onClose}>
      <div className="space-y-3">
        {preset.segmentos.length > 1 && (
          <div className="flex flex-wrap gap-1.5" role="group" aria-label="Segmento">
            {preset.segmentos.map((s) => <Chip key={s} ativo={segmento === s} onClick={() => setSegmento(s)} title={DICA_SEGMENTO[s]}>{ROTULO_SEGMENTO[s]}</Chip>)}
          </div>
        )}
        <SearchInput value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} placeholder="Buscar por nome, e-mail ou telefone" aria-label="Buscar na lista" />
        {erro && <p role="alert" className="text-sm text-[var(--red)]">{erro}</p>}
        {!lida && !erro && <p className="text-sm text-[var(--fg-3)]">Carregando…</p>}
        {lida && (
          <p className="text-xs text-[var(--fg-3)]">
            {lida.linhas.length} no CSV · {lida.foraPadrao.length} com telefone fora do padrão
            {busca && ` · ${vistas.length} na busca`}
          </p>
        )}
        <ul className="divide-y divide-[var(--border)]">
          {vistas.slice(0, LIMITE).map((p, i) => <LinhaPessoa key={i} p={p} sairam={preset.id === 'sairam_grupo'} />)}
        </ul>
        {vistas.length > LIMITE && <p className="text-xs text-[var(--fg-3)]">Mostrando {LIMITE} de {vistas.length}. Use a busca para achar alguém.</p>}
      </div>
    </PainelLateral>
  );
}

function LinhaPessoa({ p, sairam }: { p: PessoaLista; sairam: boolean }) {
  const fora = !p.telefone || p.motivo;
  return (
    <li className="py-2.5">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <span className="text-sm font-semibold text-[var(--fg)]">{p.nome ?? 'Sem nome (só no grupo)'}</span>
        <span className={`tabular text-xs ${fora ? 'text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>
          {fora ? `${p.telefoneComoVeio ?? 'sem telefone'} · ${p.motivo ?? 'fora do padrão'}` : p.telefone}
        </span>
      </div>
      {p.email && <p className="break-all text-xs text-[var(--fg-3)]">{p.email}</p>}
      <div className="mt-1 flex flex-wrap gap-1.5">
        <Badge tone="info">{ROTULO_SEGMENTO[p.segmento]}{p.semProfissao ? ' (sem profissão)' : ''}</Badge>
        <Badge tone={p.grupoBlack === 'no_grupo' ? 'success' : p.grupoBlack === 'saiu' ? 'warning' : 'neutral'}>Black: {ROTULO_SITUACAO[p.grupoBlack]}</Badge>
        {p.grupoConsultoria !== 'nunca' && <Badge tone={p.grupoConsultoria === 'saiu' ? 'warning' : 'success'}>Consultoria: {ROTULO_SITUACAO[p.grupoConsultoria]}</Badge>}
        {p.fontes.filter((f) => !f.startsWith('grupo_')).map((f) => <Badge key={f}>{ROTULO_FONTE[f] ?? f}</Badge>)}
      </div>
      {sairam && <p className="mt-1 text-xs text-[var(--fg-3)]">Saiu de: {grupoSaida(p)}</p>}
    </li>
  );
}
