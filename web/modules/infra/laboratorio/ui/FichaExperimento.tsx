'use client';

// Ficha de um experimento: editar (com as travas), mudar status, registrar leitura (níveis 2 e 3) e revisar (nível 1).
import { useEffect, useMemo, useState } from 'react';
import { Badge, Button, Card, Drawer, Input, SectionTitle, Skeleton, Textarea } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import { classificar, ROTULO_RESULTADO } from '../domain/estatistica';
import { NIVEIS, rotuloArea, STATUS, type Experimento, type Pessoa, type Res } from '../domain/types';
import { labRepo } from '../infrastructure/repositorio';
import { amostraChegou, calcularLeitura, CamposLeitura, ResultadoLeitura, Rotulo, TOM_RESULTADO, type EntradaLeitura } from './Calculadora';
import { FormFicha, paraSalvar, type Rascunho } from './FormFicha';

export function FichaExperimento({ id, equipe, onClose, onMudou, flash }: {
  id: string; equipe: Pessoa[]; onClose: () => void; onMudou: () => void; flash: (m: string) => void;
}) {
  const [e, setE] = useState<Experimento | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [rasc, setRasc] = useState<Rascunho>({});
  const [ocupado, setOcupado] = useState(false);
  const [ent, setEnt] = useState<EntradaLeitura>({ aN: '', aX: '', bN: '', bX: '' });
  const [medicaoOk, setMedicaoOk] = useState(true);
  const [nota, setNota] = useState('');
  const [concluir, setConcluir] = useState(false);
  const [fizemos, setFizemos] = useState('');
  const [aprendemos, setAprendemos] = useState('');
  const [bateu, setBateu] = useState<'sim' | 'nao' | 'nao_sabe' | ''>('');
  const [motivoCancelar, setMotivoCancelar] = useState('');

  const carregar = async () => {
    try {
      const x = await labRepo.obter(id);
      setE(x);
      setRasc(x ?? {});
      setErro(x ? null : 'Experimento não encontrado.');
    } catch (err) { setErro(err instanceof Error ? err.message : 'Não foi possível carregar.'); }
  };
  // eslint-disable-next-line react-hooks/set-state-in-effect, react-hooks/exhaustive-deps -- carga ao abrir a ficha
  useEffect(() => { void carregar(); }, [id]);

  const tipo = e?.metrica_tipo ?? 'taxa';
  const leitura = useMemo(() => (e && e.nivel > 1 ? calcularLeitura(tipo, ent) : null), [e, tipo, ent]);
  const classif = leitura && e ? classificar(leitura, { regua: e.regua, amostraChegou: amostraChegou(tipo, ent, e.amostra_minima), medicaoOk }) : null;

  const agir = async (p: Promise<Res>) => {
    setOcupado(true);
    const r = await p;
    setOcupado(false);
    flash(r.msg);
    if (r.ok) { await carregar(); onMudou(); }
    return r.ok;
  };

  if (!e) {
    return (
      <Drawer onClose={onClose} title={erro ? 'Experimento' : <Skeleton w={200} h={16} />}>
        {erro ? <p className="text-sm text-[var(--red)]">{erro}</p> : <div className="space-y-2"><Skeleton h={60} /><Skeleton h={60} /></div>}
      </Drawer>
    );
  }

  const editavel = e.pode_editar && ['rascunho', 'no_ar', 'em_leitura'].includes(e.status);
  const travado = e.status !== 'rascunho';
  const st = STATUS[e.status];
  const salvar = () => agir(labRepo.salvar(paraSalvar({ ...rasc, id: e.id, nivel: e.nivel })));

  return (
    <Drawer
      onClose={onClose}
      width="max-w-4xl"
      title={e.titulo}
      subtitle={`${rotuloArea(e.area)} · Nível ${e.nivel}: ${NIVEIS[e.nivel].nome} · criado por ${e.criado_por_nome ?? '—'} em ${fmtData(e.criado_em)}`}
      badges={<>
        <Badge tone={st.tom} dot>{st.l}</Badge>
        {e.resultado && <Badge tone={TOM_RESULTADO[e.resultado]}>{ROTULO_RESULTADO[e.resultado]}</Badge>}
        {e.revisao_bateu && <Badge tone={e.revisao_bateu === 'sim' ? 'success' : e.revisao_bateu === 'nao' ? 'danger' : 'neutral'}>Previsão {e.revisao_bateu === 'sim' ? 'bateu' : e.revisao_bateu === 'nao' ? 'não bateu' : 'sem como saber'}</Badge>}
      </>}
      footer={editavel ? (
        <div className="flex w-full flex-wrap items-center justify-between gap-2">
          <div className="flex gap-2">
            {e.status === 'rascunho' && <Button variant="danger" size="sm" disabled={ocupado} onClick={async () => { if (await agir(labRepo.excluir(e.id))) onClose(); }}>Excluir rascunho</Button>}
            {e.status === 'no_ar' && (e.n_leituras ?? e.leituras?.length ?? 0) === 0 && <Button variant="ghost" size="sm" disabled={ocupado} onClick={() => agir(labRepo.status(e.id, 'rascunho'))}>Voltar para rascunho</Button>}
          </div>
          <div className="flex gap-2">
            <Button variant="ghost" size="sm" disabled={ocupado} onClick={salvar}>Salvar ficha</Button>
            {e.status === 'rascunho' && <Button size="sm" disabled={ocupado} onClick={async () => { if (await agir(labRepo.salvar(paraSalvar({ ...rasc, id: e.id, nivel: e.nivel })))) await agir(labRepo.status(e.id, 'no_ar')); }}>{e.nivel === 1 ? 'Registrar decisão' : 'Pôr no ar'}</Button>}
          </div>
        </div>
      ) : undefined}
    >
      <div className="space-y-6">
        {e.mudancas.length > 0 && (
          <Card className="space-y-1 p-4">
            <SectionTitle>Mudanças no meio do teste</SectionTitle>
            {e.mudancas.map((m, i) => <p key={i} className="text-xs text-[var(--fg-2)]">{fmtData(m.em)}: {m.campos.join(', ')}. Motivo: {m.motivo}</p>)}
          </Card>
        )}

        {e.nivel === 1 && e.status === 'no_ar' && e.pode_editar && (
          <Card className="space-y-3 p-4">
            <SectionTitle>Revisão</SectionTitle>
            <p className="text-sm text-[var(--fg-2)]">Previsão: {e.previsao ?? '—'}</p>
            <div className="flex flex-wrap gap-2">
              {([['sim', 'Bateu'], ['nao', 'Não bateu'], ['nao_sabe', 'Não dá para saber']] as const).map(([k, l]) => (
                <Button key={k} size="sm" variant={bateu === k ? 'primary' : 'ghost'} onClick={() => setBateu(k)}>{l}</Button>
              ))}
            </div>
            <label className="block space-y-1"><Rotulo>O que aprendemos</Rotulo><Textarea rows={2} value={aprendemos} onChange={(x) => setAprendemos(x.target.value)} /></label>
            <Button size="sm" disabled={ocupado || !bateu} onClick={() => bateu && agir(labRepo.revisar(e.id, bateu, aprendemos))}>Registrar revisão</Button>
          </Card>
        )}

        {e.nivel > 1 && ['no_ar', 'em_leitura'].includes(e.status) && e.pode_editar && (
          <Card className="space-y-4 p-4">
            <SectionTitle>Registrar leitura</SectionTitle>
            <ol className="list-decimal space-y-0.5 pl-5 text-xs text-[var(--fg-3)]">
              <li>A amostra chegou? {e.amostra_minima ? `(mínimo de ${e.amostra_minima.toLocaleString('pt-BR')} por grupo)` : ''}</li>
              <li>A medição e o contexto estão ok?</li>
              <li>Qual o tamanho da diferença?</li>
              <li>Qual a confiança? 95% ou mais é comprovado; 90 a 95% provável; abaixo de 90% é ruído.</li>
              <li>Confere no degrau de cima (venda, presença, qualidade)?</li>
            </ol>
            {e.metrica_tipo ? <CamposLeitura tipo={tipo} valor={ent} onChange={setEnt} /> : <p className="text-xs text-[var(--fg-3)]">Escolha o tipo de métrica na ficha para ler com números.</p>}
            <label className="flex items-center gap-2 text-sm text-[var(--fg-2)]"><input type="checkbox" checked={medicaoOk} onChange={(x) => setMedicaoOk(x.target.checked)} /> Medição e contexto ok (sem dado quebrado, feriado ou mudança no meio)</label>
            {e.metrica_tipo && <ResultadoLeitura tipo={tipo} leitura={leitura} classif={classif} />}
            <label className="block space-y-1"><Rotulo>Nota da leitura</Rotulo><Textarea rows={2} value={nota} onChange={(x) => setNota(x.target.value)} /></label>
            <label className="flex items-center gap-2 text-sm text-[var(--fg)]"><input type="checkbox" checked={concluir} onChange={(x) => setConcluir(x.target.checked)} /> Esta é a leitura final (concluir no log)</label>
            {concluir && (
              <div className="grid gap-3 sm:grid-cols-2">
                <label className="block space-y-1"><Rotulo>O que fizemos</Rotulo><Textarea rows={2} value={fizemos} onChange={(x) => setFizemos(x.target.value)} /></label>
                <label className="block space-y-1"><Rotulo>O que aprendemos</Rotulo><Textarea rows={2} value={aprendemos} onChange={(x) => setAprendemos(x.target.value)} /></label>
              </div>
            )}
            <Button size="sm" disabled={ocupado || (concluir && !classif)} onClick={() => agir(labRepo.registrarLeitura({
              experimento_id: e.id, a_n: ent.aN, a_x: ent.aX, b_n: ent.bN, b_x: ent.bX, medicao_ok: medicaoOk, nota,
              classificacao: classif?.resultado ?? null,
              calculo: leitura ? { ...leitura, quem: classif?.quem ?? null, explicacao: classif?.explicacao ?? null, tipo } : {},
              concluir, o_que_fizemos: fizemos, aprendizado: aprendemos,
            }))}>{concluir ? 'Registrar e concluir' : 'Registrar leitura'}</Button>
          </Card>
        )}

        {(e.leituras?.length ?? 0) > 0 && (
          <Card className="space-y-2 p-4">
            <SectionTitle>Leituras</SectionTitle>
            {e.leituras!.map((l) => (
              <div key={l.id} className="flex flex-wrap items-center gap-2 border-t border-[var(--border)] pt-2 text-xs text-[var(--fg-2)] first:border-0 first:pt-0">
                <span className="font-semibold text-[var(--fg)]">{fmtData(l.em)}</span>
                {l.classificacao && <Badge tone={TOM_RESULTADO[l.classificacao]}>{ROTULO_RESULTADO[l.classificacao]}</Badge>}
                <span>A {l.a_x ?? '—'}/{l.a_n ?? '—'} · B {l.b_x ?? '—'}/{l.b_n ?? '—'}</span>
                {typeof l.calculo?.confianca === 'number' && <span>confiança {((l.calculo.confianca as number) * 100).toFixed(1).replace('.', ',')}%</span>}
                {!l.medicao_ok && <Badge tone="warning">medição com problema</Badge>}
                {l.nota && <span className="w-full text-[var(--fg-3)]">{l.nota}</span>}
                <span className="text-[var(--fg-3)]">por {l.lido_por_nome ?? '—'}</span>
              </div>
            ))}
          </Card>
        )}

        {(e.o_que_fizemos || e.aprendizado) && (
          <Card className="space-y-1 p-4">
            <SectionTitle>Fechamento</SectionTitle>
            {e.o_que_fizemos && <p className="text-sm text-[var(--fg-2)]"><strong className="text-[var(--fg)]">O que fizemos:</strong> {e.o_que_fizemos}</p>}
            {e.aprendizado && <p className="whitespace-pre-line text-sm text-[var(--fg-2)]"><strong className="text-[var(--fg)]">O que aprendemos:</strong> {e.aprendizado}</p>}
          </Card>
        )}

        <div>
          <SectionTitle>Ficha</SectionTitle>
          {!e.pode_editar && <p className="mb-3 text-xs text-[var(--fg-3)]">Só quem criou, os responsáveis ou um admin editam esta ficha.</p>}
          <FormFicha valor={rasc} onChange={setRasc} nivel={e.nivel} equipe={equipe} travado={travado} somenteLeitura={!editavel} />
        </div>

        {editavel && e.status !== 'rascunho' && (
          <Card className="space-y-2 p-4">
            <SectionTitle>Cancelar</SectionTitle>
            <p className="text-xs text-[var(--fg-3)]">O que foi ao ar não se apaga: cancelado fica no log, com o motivo.</p>
            <div className="flex flex-wrap gap-2">
              <Input placeholder="Por que cancelar?" value={motivoCancelar} onChange={(x) => setMotivoCancelar(x.target.value)} className="!max-w-md" />
              <Button variant="danger" size="sm" disabled={ocupado || !motivoCancelar.trim()} onClick={() => agir(labRepo.status(e.id, 'cancelado', motivoCancelar))}>Cancelar experimento</Button>
            </div>
          </Card>
        )}
      </div>
    </Drawer>
  );
}
