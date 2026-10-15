'use client';

// Ações do master na aba Lives: cadastrar uma live, importar o CSV do Studio (lido no navegador, só o
// liveViewership_*.csv do .zip) e remover uma live. Cada escrita mostra antes o que vai acontecer.
import { useState } from 'react';
import { Button, ConfirmDialog, FilterSelect, Input, Modal } from '@/shared/ui/components';
import type { FonteDadosBlack } from '../../application/ports';
import { duracaoTexto, idDoYoutube, minutoDe, porData, ROTULO_TIPO_LIVE, TIPOS_LIVE, type Live, type PreviaImportacao, type TipoLive } from '../../domain/lives';
import { lerCsvStudio, tituloCombina, tituloDoNomeInterno, type LeituraStudio } from '../../domain/lives-studio';
import { lerZipStudio } from '../../infrastructure/zip-studio';
import { dataCurta, horaDe, numeroDe, quando, tituloDe } from './formatos';

const ROTULO = 'grid gap-1 text-xs font-semibold text-[var(--fg-2)]';
const ERRO = 'rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] p-2 text-sm text-[var(--red)]';

/** "2026-11-03T20:00" (campo da tela, horário de Brasília) para ISO com fuso. O Brasil não tem horário de verão desde 2019. */
export const dataLocalParaIso = (v: string) => (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(v) ? `${v}:00-03:00` : null);

export function ModalCadastrar({ fonte, chave, onClose, onFeito }: { fonte: FonteDadosBlack; chave: string; onClose: () => void; onFeito: (msg: string) => void }) {
  const [entrada, setEntrada] = useState('');
  const [tipo, setTipo] = useState<TipoLive>('consultoria');
  const [data, setData] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const id = idDoYoutube(entrada);
  const iso = dataLocalParaIso(data);
  const pronto = id !== null && iso !== null && !salvando;

  const salvar = async () => {
    if (!id || !iso) return;
    setSalvando(true); setErro(null);
    try {
      const r = await fonte.cadastrarLive(chave, id, tipo, iso);
      if (r.erro) setErro(r.erro); else onFeito('Live cadastrada. Ela aparece no cronograma.');
    } catch { setErro('Não foi possível cadastrar a live agora.'); }
    setSalvando(false);
  };

  return (
    <Modal onClose={onClose} title="Cadastrar live" width="max-w-md"
      footer={<><Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button><Button size="sm" onClick={salvar} disabled={!pronto}>{salvando ? 'Cadastrando…' : 'Cadastrar'}</Button></>}>
      <div className="space-y-3">
        <label className={ROTULO}>Link ou ID do vídeo no YouTube
          <Input value={entrada} onChange={(e) => setEntrada(e.target.value)} placeholder="https://www.youtube.com/watch?v=..." autoComplete="off" />
          <span className="font-normal text-[var(--fg-3)]">{entrada.trim() === '' ? 'Cole o link da live ou só o ID de 11 caracteres.' : id ? 'ID reconhecido.' : 'Não consegui achar um ID de vídeo nesse texto.'}</span>
        </label>
        <label className={ROTULO}>Tipo
          <FilterSelect value={tipo} onChange={(e) => setTipo(e.target.value as TipoLive)}>
            {TIPOS_LIVE.map((t) => <option key={t} value={t}>{ROTULO_TIPO_LIVE[t]}</option>)}
          </FilterSelect>
        </label>
        <label className={ROTULO}>Data e hora previstas (horário de Brasília)
          <Input type="datetime-local" value={data} onChange={(e) => setData(e.target.value)} />
        </label>
        {erro && <p role="alert" className={ERRO}>{erro}</p>}
      </div>
    </Modal>
  );
}

type Etapa = { passo: 'escolher' } | { passo: 'lido'; nome: string; titulo: string | null; leitura: LeituraStudio; combina: boolean | null } | { passo: 'previa'; previa: PreviaImportacao; leitura: LeituraStudio } | { passo: 'gravado'; previa: PreviaImportacao };

export function ModalImportar({ fonte, chave, lives, inicial, onClose, onFeito }: {
  fonte: FonteDadosBlack; chave: string; lives: Live[]; inicial: Live | null; onClose: () => void; onFeito: (msg: string) => void;
}) {
  const candidatas = lives.filter((l) => l.situacao === 'realizada' || l.situacao === 'ao_vivo').sort((a, b) => porData(b, a));
  const [videoId, setVideoId] = useState(inicial?.videoId ?? candidatas[0]?.videoId ?? '');
  const [etapa, setEtapa] = useState<Etapa>({ passo: 'escolher' });
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const live = lives.find((l) => l.videoId === videoId) ?? null;

  const escolherArquivo = async (arquivo: File | undefined) => {
    setErro(null); setEtapa({ passo: 'escolher' });
    if (!arquivo) return;
    setOcupado(true);
    try {
      const z = await lerZipStudio(await arquivo.arrayBuffer());
      if (!z.ok) { setErro(z.erro); return; }
      const leitura = lerCsvStudio(z.lido.csv);
      const titulo = tituloDoNomeInterno(z.lido.nomeInterno);
      setEtapa({ passo: 'lido', nome: arquivo.name, titulo, leitura, combina: tituloCombina(titulo, live?.titulo ?? null) });
    } catch { setErro('Não foi possível ler esse arquivo.'); } finally { setOcupado(false); }
  };

  const gerarPrevia = async () => {
    if (etapa.passo !== 'lido' || !live) return;
    setOcupado(true); setErro(null);
    try {
      const r = await fonte.importarLive(chave, live.videoId, etapa.leitura.linhas, false);
      if (r.erro || !r.data) setErro(r.erro ?? 'A prévia não voltou.'); else setEtapa({ passo: 'previa', previa: r.data, leitura: etapa.leitura });
    } catch { setErro('Não foi possível gerar a prévia agora.'); } finally { setOcupado(false); }
  };

  const gravar = async () => {
    if (etapa.passo !== 'previa' || !live) return;
    setOcupado(true); setErro(null);
    try {
      const r = await fonte.importarLive(chave, live.videoId, etapa.leitura.linhas, true);
      if (r.erro || !r.data) setErro(r.erro ?? 'A gravação não voltou.');
      else if (r.data.gravado === false) setErro('O banco não gravou nada: os minutos já eram exatamente estes, ou mudaram desde a prévia. Atualize e confira.');
      else { setEtapa({ passo: 'gravado', previa: r.data }); onFeito(`CSV do Studio gravado em ${tituloDe(live)}.`); }
    } catch { setErro('Não foi possível gravar agora.'); } finally { setOcupado(false); }
  };

  const bloqueado = etapa.passo === 'lido' && (etapa.leitura.erros.length > 0 || etapa.combina === false);
  const resumo = etapa.passo === 'lido' ? etapa.leitura.resumo : null;

  return (
    <Modal onClose={onClose} title="Importar o CSV do Studio" width="max-w-xl"
      footer={etapa.passo === 'gravado'
        ? <Button size="sm" onClick={onClose}>Fechar</Button>
        : <>
            <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
            {etapa.passo === 'lido' && <Button size="sm" onClick={gerarPrevia} disabled={bloqueado || ocupado || !live}>{ocupado ? 'Conferindo…' : 'Ver prévia'}</Button>}
            {etapa.passo === 'previa' && <Button size="sm" onClick={gravar} disabled={ocupado || etapa.previa.alteradas === 0}>{ocupado ? 'Gravando…' : 'Gravar'}</Button>}
          </>}>
      <div className="space-y-3 text-sm">
        <label className={ROTULO}>Live que vai receber os minutos
          <FilterSelect value={videoId} onChange={(e) => { setVideoId(e.target.value); setEtapa({ passo: 'escolher' }); setErro(null); }} disabled={ocupado}>
            {candidatas.map((l) => <option key={l.videoId} value={l.videoId}>{`${dataCurta(l.dataPrevista)} ${horaDe(l.dataPrevista)} · ${ROTULO_TIPO_LIVE[l.tipo]} · ${tituloDe(l)}`}</option>)}
          </FilterSelect>
        </label>
        <label className={ROTULO}>Arquivo .zip baixado do YouTube Studio
          <input type="file" accept=".zip,application/zip" disabled={ocupado || !live} onChange={(e) => { void escolherArquivo(e.target.files?.[0]); e.target.value = ''; }}
            className="min-h-11 w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-2 text-sm font-normal text-[var(--fg)]" />
          <span className="font-normal text-[var(--fg-3)]">Só o arquivo liveViewership_*.csv de dentro do zip é lido, aqui no navegador. Nada mais sai do seu computador.</span>
        </label>

        {etapa.passo === 'lido' && (
          <div className="space-y-2 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
            <p className="break-words text-[var(--fg-2)]">Arquivo: <strong className="text-[var(--fg)]">{etapa.nome}</strong></p>
            <p className="break-words text-[var(--fg-2)]">Título dentro do arquivo: <strong className="text-[var(--fg)]">{etapa.titulo ?? 'Sem dado'}</strong></p>
            {etapa.combina === false && <p role="alert" className={ERRO}>O título do arquivo não bate com o da live escolhida ({tituloDe(live ?? { titulo: null })}). Confira se é o arquivo certo antes de importar.</p>}
            {etapa.combina === null && <p role="note" className="text-[var(--yellow)]">O título desta live ainda não está na API, então não consegui conferir se o arquivo é dela. Confirme você mesmo.</p>}
            {etapa.leitura.erros.map((e) => <p key={e} role="alert" className={ERRO}>{e}</p>)}
            {etapa.leitura.avisos.map((a) => <p key={a} className="text-xs text-[var(--fg-3)]">{a}</p>)}
            {resumo && (
              <dl className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                {[['Minutos', numeroDe(resumo.linhas)], ['Pico', `${numeroDe(resumo.pico)} (min ${minutoDe(resumo.picoSeg)})`], ['Duração', duracaoTexto(resumo.duracaoSeg)], ['Chat', numeroDe(resumo.chat)]].map(([r, v]) => (
                  <div key={r}><dt className="text-[11px] font-semibold uppercase text-[var(--fg-3)]">{r}</dt><dd className="tabular font-bold text-[var(--fg)]">{v}</dd></div>
                ))}
              </dl>
            )}
          </div>
        )}

        {etapa.passo === 'previa' && (
          <div className="space-y-1 rounded-[var(--r-md)] border border-[var(--border-accent)] bg-[var(--surface-1)] p-3" role="status">
            <p className="font-semibold text-[var(--fg)]">O banco vai receber {numeroDe(etapa.previa.linhas)} minutos, com pico de {numeroDe(etapa.previa.pico)}{etapa.previa.picoSeg !== null ? ` no min ${minutoDe(etapa.previa.picoSeg)}` : ''} e duração {duracaoTexto(etapa.previa.duracaoSeg)}.</p>
            <p className="text-[var(--fg-2)]">{etapa.previa.alteradas === 0 && etapa.previa.existentes !== null && etapa.previa.existentes > 0
              ? 'Estes minutos já estão no banco, idênticos ao arquivo: gravar não mudaria nada.'
              : etapa.previa.existentes !== null && etapa.previa.existentes > 0
              ? `Já existem ${numeroDe(etapa.previa.existentes)} minutos do Studio nesta live${etapa.previa.alteradas !== null ? `; ${numeroDe(etapa.previa.alteradas)} mudam com este arquivo` : ''}. Gravar substitui esses minutos.`
              : 'Esta live ainda não tem minutos do Studio: nada será substituído.'}</p>
          </div>
        )}

        {etapa.passo === 'gravado' && (
          <p role="status" className="rounded-[var(--r-md)] border border-[var(--green)]/40 bg-[var(--surface-1)] p-3 font-semibold text-[var(--green)]">
            Gravado: {numeroDe(etapa.previa.linhas)} minutos, pico de {numeroDe(etapa.previa.pico)}{etapa.previa.alteradas !== null ? ` · ${numeroDe(etapa.previa.alteradas)} alterados` : ''}.
          </p>
        )}
        {erro && <p role="alert" className={ERRO}>{erro}</p>}
      </div>
    </Modal>
  );
}

export function ModalRemover({ fonte, chave, lives, onClose, onFeito }: { fonte: FonteDadosBlack; chave: string; lives: Live[]; onClose: () => void; onFeito: (msg: string) => void }) {
  const ordenadas = [...lives].sort(porData);
  const [videoId, setVideoId] = useState(ordenadas[0]?.videoId ?? '');
  const [confirmar, setConfirmar] = useState(false);
  const [ocupado, setOcupado] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const live = lives.find((l) => l.videoId === videoId) ?? null;

  const remover = async () => {
    if (!live) return;
    setOcupado(true); setErro(null);
    try {
      const r = await fonte.removerLive(chave, live.videoId);
      if (r.erro) { setErro(r.erro); setConfirmar(false); } else onFeito('Live removida do cronograma.');
    } catch { setErro('Não foi possível remover agora.'); setConfirmar(false); } finally { setOcupado(false); }
  };

  return (
    <>
      <Modal onClose={onClose} title="Remover live" width="max-w-md"
        footer={<><Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button><Button variant="danger" size="sm" onClick={() => setConfirmar(true)} disabled={!live || ocupado}>Remover</Button></>}>
        <div className="space-y-3 text-sm">
          <label className={ROTULO}>Live
            <FilterSelect value={videoId} onChange={(e) => setVideoId(e.target.value)}>
              {ordenadas.map((l) => <option key={l.videoId} value={l.videoId}>{`${dataCurta(l.dataPrevista)} ${horaDe(l.dataPrevista)} · ${ROTULO_TIPO_LIVE[l.tipo]} · ${tituloDe(l)}`}</option>)}
            </FilterSelect>
          </label>
          <p className="text-[var(--fg-3)]">Tira a live do cronograma. Use para cadastro errado.</p>
          {erro && <p role="alert" className={ERRO}>{erro}</p>}
        </div>
      </Modal>
      <ConfirmDialog open={confirmar} danger title="Remover esta live?" confirmLabel="Remover" onCancel={() => setConfirmar(false)} onConfirm={remover}
        message={live ? `${quando(live.dataPrevista)} · ${tituloDe(live)}. Ela sai do cronograma. Os dados já guardados dela (minutos, chat e comentários) continuam no banco, só deixam de aparecer aqui.` : ''} />
    </>
  );
}
