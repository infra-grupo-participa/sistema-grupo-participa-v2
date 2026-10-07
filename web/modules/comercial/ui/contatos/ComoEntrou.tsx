'use client';

// "Como entrou" (aba Dados da ficha): canal de entrada, quando, projeto e por que (regra que ligou), mais o que cada
// fonte registrou (produto/oferta da Hotmart, lista/tag do AC, funil da Clint). Catalogação de origem, 20261007141044.
// O gestor pode fixar o projeto à mão (vale sobre as regras) ou devolver o contato às regras.
import { useState } from 'react';
import { Button, Input, Row, SectionTitle, Skeleton } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import {
  CHAVE_PROJETO, ROTULO_CAMPO_REGRA, ROTULO_CANAL, ROTULO_MOTIVO, ROTULO_OPERADOR, linhasComoEntrou, nomeProjeto,
} from '../../domain/catalogacao';
import { Aviso } from '../comum';
import { avisarMudanca, repo, useDados } from '../repositorio';

export function ComoEntrou({ contatoId }: { contatoId: string }) {
  // embrulho: dados null = carregando; { v: null } = contato sem origem registrada
  const o = useDados(async () => ({ v: await repo.origemContato(contatoId) }), [contatoId]);
  const [editando, setEditando] = useState(false);
  const [chave, setChave] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const projetos = useDados(async () => (editando ? (await repo.catalogo()).projetos : null), [editando]);

  async function salvar(valor: string | null) {
    const p = valor?.trim().toLowerCase() || null;
    if (p && !CHAVE_PROJETO.test(p)) { setErro('Chave inválida: minúsculas, números e hífen (ex.: seminario-conjunto-2026-11).'); return; }
    setSalvando(true);
    const res = await repo.definirProjetoContato(contatoId, p);
    setSalvando(false);
    if (!res.ok) { setErro(res.msg ?? 'Não foi possível salvar.'); return; }
    setEditando(false); setErro(null);
    await o.recarregar();
    avisarMudanca();
  }

  if (o.erro && !o.dados) return null;   // bloco opcional: se falhar, a ficha segue sem ele
  if (!o.dados) {
    return <section aria-busy="true"><SectionTitle>Como entrou</SectionTitle><Skeleton h={14} w="70%" /></section>;
  }
  if (!o.dados.v) return null;
  const d = o.dados.v;
  const linhas = linhasComoEntrou(d);
  const projeto = d.projeto ? nomeProjeto(d.projeto, d.projetoNome) : null;
  return (
    <section>
      <SectionTitle
        right={d.podeDefinir && !editando ? (
          <Button size="sm" variant="link" onClick={() => { setEditando(true); setChave(d.projeto ?? ''); setErro(null); }}>
            {d.manual ? 'trocar projeto' : 'definir projeto'}
          </Button>
        ) : undefined}
      >
        Como entrou
      </SectionTitle>
      <Row k="Canal" v={ROTULO_CANAL[d.canal]} />
      <Row k="Quando" v={<span className="tabular">{d.entrouEm ? fmtData(d.entrouEm) : '—'}</span>} />
      <Row
        k="MQL"
        v={d.mqlDesde
          ? <span>desde <span className="tabular">{fmtData(d.mqlDesde)}</span>{d.mqlProjeto ? ` · ${nomeProjeto(d.mqlProjeto, d.mqlProjetoNome)}` : ''}</span>
          : <span className="text-[var(--fg-3)]">Não</span>}
      />
      <Row
        k="Projeto"
        v={projeto
          ? <span>{projeto} <code className="text-xs text-[var(--fg-3)]">{d.projeto}</code></span>
          : <span className="text-[var(--fg-3)]">{d.linha ? `${d.linha.toUpperCase()}, sem projeto` : 'Sem projeto'}</span>}
      />
      <p className="mt-1 text-xs text-[var(--fg-3)]">
        {d.regra
          ? `${ROTULO_MOTIVO[d.motivo]}: ${ROTULO_CAMPO_REGRA[d.regra.campo]} ${ROTULO_OPERADOR[d.regra.operador]} "${d.regra.padrao}".`
          : `${ROTULO_MOTIVO[d.motivo]}.`}
      </p>
      {linhas.length > 0 && (
        <ul className="mt-2 space-y-1">
          {linhas.map((l) => (
            <li key={l.fonte} className="flex min-w-0 items-baseline justify-between gap-3 text-sm">
              <span className="min-w-0 break-words text-[var(--fg-2)]"><span className="text-[var(--fg-3)]">{l.fonte}:</span> {l.texto}</span>
              {l.em && <span className="shrink-0 text-xs tabular text-[var(--fg-3)]">{fmtData(l.em)}</span>}
            </li>
          ))}
        </ul>
      )}
      {editando && (
        <div className="mt-3 space-y-2">
          <Input
            list={`projetos-${contatoId}`}
            value={chave}
            onChange={(e) => { setChave(e.target.value); setErro(null); }}
            placeholder="chave do projeto (ex.: seminario-conjunto-2026-11)"
            aria-label="Chave do projeto"
            autoFocus
          />
          <datalist id={`projetos-${contatoId}`}>
            {(projetos.dados ?? []).map((p) => <option key={p.chave} value={p.chave}>{nomeProjeto(p.chave, p.nome)}</option>)}
          </datalist>
          {erro && <Aviso tom="danger" alerta>{erro}</Aviso>}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" disabled={salvando} onClick={() => { void salvar(chave); }}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
            {d.manual && <Button size="sm" variant="ghost" disabled={salvando} onClick={() => { void salvar(null); }}>Voltar às regras</Button>}
            <Button size="sm" variant="ghost" disabled={salvando} onClick={() => setEditando(false)}>Cancelar</Button>
          </div>
        </div>
      )}
    </section>
  );
}
