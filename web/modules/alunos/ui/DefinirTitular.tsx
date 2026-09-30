'use client';

// "Definir quem é o titular" — resolve par de sócios, cadeia, sócio sem titular e vínculo sem marcação pela
// fn_aluno_definir_titular (o banco valida e grava o histórico). Só aparece para quem edita a base e só quando
// a conciliação trouxe item de vínculo para este aluno.
import { useId, useMemo, useState } from 'react';
import { Button } from '@/shared/ui/components';
import type { Aluno360 } from '../domain/aluno-360';
import { rotuloTipo, type ItemConciliacao } from '../domain/conciliacao';
import { definirTitular } from './conciliacao-data';

const chave = (v: string | null | undefined) =>
  (v || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\s+/g, ' ').trim();

type Escolha = { tipo: 'titular'; id: string } | { tipo: 'socio_de'; id: string } | null;

export function DefinirTitular({ a, alunos, itens, onFeito }: {
  a: Aluno360;
  alunos: Aluno360[];
  /** Itens de vínculo em aberto deste aluno (já filtrados por quem chama). */
  itens: ItemConciliacao[];
  onFeito: (msg: string) => void;
}) {
  const uid = useId();
  const [aberto, setAberto] = useState(false);
  const [escolha, setEscolha] = useState<Escolha>(null);
  const [busca, setBusca] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const porId = useMemo(() => new Map(alunos.map((x) => [x.id, x])), [alunos]);
  const par = itens.find((i) => i.tipo === 'socio_par_mutuo' && i.ref_aluno_id);
  const outro = par?.ref_aluno_id ? porId.get(par.ref_aluno_id) ?? null : null;
  // O banco manda sugestao_titular = 'este' (o aluno_id do item) | 'outro' (ref_aluno_id); vira id aqui.
  const sug = par?.detalhe.sugestao_titular;
  const sugestao = sug === 'este' ? par?.aluno_id ?? null : sug === 'outro' ? par?.ref_aluno_id ?? null : null;

  // Titular possível: outro aluno da base, sem titular próprio e não marcado como sócio.
  const candidatos = useMemo(() => {
    const k = chave(busca);
    if (k.length < 2) return [];
    return alunos
      .filter((x) => x.id !== a.id && !x.socio_de_aluno_id && !x.eh_socio && chave(x.nome).includes(k))
      .slice(0, 8);
  }, [alunos, busca, a.id]);

  const confirmar = async () => {
    if (!escolha) return;
    setSalvando(true);
    setErro(null);
    let r;
    if (par && outro && escolha.tipo === 'titular') {
      // Par A↔B: o titular solta o vínculo primeiro; depois o outro lado vira sócio dele.
      const titular = escolha.id;
      const socio = titular === a.id ? outro.id : a.id;
      r = await definirTitular(titular, null);
      if (r.ok) {
        r = await definirTitular(socio, titular);
        if (!r.ok) r = { ok: false as const, erro: `O titular foi definido, mas o outro lado não foi ligado: ${r.erro}` };
      }
    } else {
      r = await definirTitular(a.id, escolha.tipo === 'titular' ? null : escolha.id);
    }
    setSalvando(false);
    if (!r.ok) { setErro(r.erro); return; }
    setAberto(false);
    onFeito('Vínculo de sócio atualizado.');
  };

  if (!aberto) {
    return (
      <div className="py-1.5 border-b border-[var(--border-faint)] flex items-center justify-between gap-3">
        <span className="text-xs text-[var(--yellow)]">{itens.map((i) => rotuloTipo(i.tipo)).join(' · ')}</span>
        <Button size="sm" variant="ghost" onClick={() => setAberto(true)}>Definir quem é o titular</Button>
      </div>
    );
  }

  const opcao = (id: string, valor: Escolha, rotulo: React.ReactNode) => (
    <label key={id} className="flex items-center gap-2 py-1 text-sm text-[var(--fg)] cursor-pointer">
      <input
        type="radio"
        name={`${uid}-titular`}
        checked={!!escolha && !!valor && escolha.tipo === valor.tipo && escolha.id === valor.id}
        onChange={() => setEscolha(valor)}
        className="accent-[var(--accent)]"
      />
      {rotulo}
    </label>
  );

  return (
    <fieldset className="my-2 p-2 border border-[var(--border)] rounded-[var(--r-md)]">
      <legend className="px-1 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Definir quem é o titular</legend>
      {par && outro ? (
        <>
          {opcao('eu', { tipo: 'titular', id: a.id }, <>{a.nome || 'Esta pessoa'} é o titular{sugestao === a.id && <span className="text-xs text-[var(--fg-3)]"> (sugerido)</span>}</>)}
          {opcao('outro', { tipo: 'titular', id: outro.id }, <>{outro.nome || 'O outro cadastro'} é o titular{sugestao === outro.id && <span className="text-xs text-[var(--fg-3)]"> (sugerido)</span>}</>)}
          <p className="text-[11px] text-[var(--fg-3)] mt-1">O outro passa a ser sócio de quem for escolhido.</p>
        </>
      ) : (
        <>
          {opcao('eu', { tipo: 'titular', id: a.id }, 'Esta pessoa é titular')}
          <label htmlFor={`${uid}-busca`} className="block text-xs text-[var(--fg-3)] mt-2 mb-1">Ou é sócia de:</label>
          <input
            id={`${uid}-busca`}
            type="search"
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            placeholder="Digite o nome do titular"
            className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg)] px-3 py-1.5 text-sm focus:border-[var(--border-accent)]"
          />
          {busca.trim().length >= 2 && !candidatos.length && <p className="text-xs text-[var(--fg-3)] mt-1">Nenhum titular com esse nome na base.</p>}
          {candidatos.map((c) => opcao(c.id, { tipo: 'socio_de', id: c.id }, <>{c.nome || 'Sem nome'}{c.turma_codigo && <span className="text-xs text-[var(--fg-3)]"> · {c.turma_codigo}</span>}</>))}
        </>
      )}
      {erro && <p className="text-xs text-[var(--red)] mt-1" role="alert">{erro}</p>}
      <div className="flex justify-end gap-2 mt-2">
        <Button size="sm" variant="ghost" onClick={() => { setAberto(false); setErro(null); }} disabled={salvando}>Cancelar</Button>
        <Button size="sm" onClick={confirmar} disabled={!escolha || salvando}>{salvando ? 'Salvando…' : 'Confirmar'}</Button>
      </div>
    </fieldset>
  );
}
