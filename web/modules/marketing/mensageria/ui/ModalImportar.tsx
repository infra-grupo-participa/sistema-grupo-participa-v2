'use client';

// Importar planilha. O TS só separa colunas (lerPlanilha) e manda para mkt_msg_importar:
// 1º com p_confirmar=false (o banco valida e lista erros e duplicatas); depois "Importar" grava tudo ou nada.
import { useMemo, useState } from 'react';
import { Button, Checkbox, DataTable, Modal, Td, Textarea, Th, Thead, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { COLUNAS_PLANILHA, FORMATO_COLUNA, fmtNum, lerPlanilha, modeloCsv, type ResultadoImportacao } from '../domain/mensageria';
import { importar } from './mensageria-data';
import { Erro, thCls } from './pecas';

function baixarModelo() {
  const url = URL.createObjectURL(new Blob([modeloCsv()], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = 'modelo-disparos.csv';
  a.click();
  URL.revokeObjectURL(url);
}

/** O Excel costuma salvar CSV em Windows-1252: se não for UTF-8 válido, lê assim (senão os acentos quebram). */
async function lerArquivo(arq: File): Promise<string> {
  const buf = await arq.arrayBuffer();
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(buf);
  } catch {
    return new TextDecoder('windows-1252').decode(buf);
  }
}

const ERRO_REDE = 'Não foi possível falar com o banco (erro de rede ou sem acesso). Tente de novo.';

export function ModalImportar({ onFechar, onImportado }: { onFechar: () => void; onImportado: (msg: string) => void }) {
  const [texto, setTexto] = useState('');
  const [arquivo, setArquivo] = useState<string | null>(null);
  const [previa, setPrevia] = useState<ResultadoImportacao | null>(null);
  const [aceitarDup, setAceitarDup] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState<'conferir' | 'importar' | null>(null);

  const lida = useMemo(() => (texto.trim() ? lerPlanilha(texto) : null), [texto]);

  function trocarTexto(t: string, nome: string | null) {
    setTexto(t);
    setArquivo(nome);
    setPrevia(null);
    setAceitarDup(false);
    setErro(null);
  }

  async function conferir() {
    if (!lida) return;
    if (lida.faltando.length > 0) { setErro(`Faltam colunas no cabeçalho: ${lida.faltando.join(', ')}. Baixe o modelo.`); return; }
    if (lida.linhas.length === 0) { setErro('Nenhuma linha abaixo do cabeçalho.'); return; }
    setOcupado('conferir');
    const r = await importar(lida.linhas, false, arquivo, false);
    setOcupado(null);
    setAceitarDup(false);
    if (!r) { setErro(ERRO_REDE); return; }
    setErro(null);
    setPrevia(r);
  }

  async function gravar() {
    if (!lida) return;
    setOcupado('importar');
    const r = await importar(lida.linhas, true, arquivo, aceitarDup);
    setOcupado(null);
    if (!r) { setErro(ERRO_REDE); return; }
    if (!r.ok) { setPrevia(r); setErro(r.msg); return; }
    onImportado(r.msg);
  }

  // O banco aponta a posição no array (1 = 1ª linha de dados); a tela mostra a linha do arquivo.
  const naPlanilha = (pos: number) => lida?.linhaNoArquivo[pos - 1] ?? pos + 1;
  const dupBanco = previa?.duplicadas_banco ?? [];
  const dupLote = previa?.duplicadas_lote ?? [];
  const temDup = dupBanco.length > 0 || dupLote.length > 0;
  const errosTotal = previa ? (previa.erros_total ?? previa.erros.length) : 0;
  const podeImportar = !!previa && errosTotal === 0 && previa.validas > 0 && (!temDup || aceitarDup) && !ocupado;

  return (
    <Modal
      onClose={onFechar}
      title="Importar planilha"
      width="max-w-4xl"
      footer={<>
        <Button variant="ghost" onClick={onFechar}>Cancelar</Button>
        <Button variant="subtle" onClick={conferir} disabled={!lida || !!ocupado}>{ocupado === 'conferir' ? 'Conferindo…' : 'Conferir planilha'}</Button>
        <Button onClick={gravar} disabled={!podeImportar}>{ocupado === 'importar' ? 'Importando…' : 'Importar'}</Button>
      </>}
    >
      <ol className="mb-3 list-decimal space-y-1 pl-5 text-sm text-[var(--fg-2)]">
        <li>Baixe o modelo (só o cabeçalho) e preencha uma linha por disparo, no formato abaixo. Não mude o cabeçalho.</li>
        <li>Cole aqui ou escolha o arquivo (.csv).</li>
        <li>Clique em Conferir planilha. Nada é gravado nessa hora.</li>
        <li>Sem erro, clique em Importar. Grava tudo ou nada.</li>
      </ol>
      <details className="mb-3 text-sm">
        <summary className="cursor-pointer font-medium text-[var(--fg)]">Formato de cada coluna</summary>
        <dl className="mt-2 grid gap-x-4 gap-y-1 sm:grid-cols-2">
          {COLUNAS_PLANILHA.map((c) => (
            <div key={c} className="flex gap-2">
              <dt className="shrink-0 font-mono text-[var(--fg)]">{c}</dt>
              <dd className="text-[var(--fg-2)]">{FORMATO_COLUNA[c]}</dd>
            </div>
          ))}
        </dl>
      </details>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <Button variant="ghost" onClick={baixarModelo}><Icon name="download" size={16} /> Baixar modelo</Button>
        <label className="inline-flex cursor-pointer items-center gap-2 rounded-[var(--r-md)] border border-[var(--border)] px-4 py-2 text-sm font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          <Icon name="file" size={16} /> Escolher arquivo
          <input
            type="file"
            accept=".csv,.txt,text/csv,text/plain"
            className="sr-only"
            onChange={async (e) => {
              const arq = e.target.files?.[0];
              if (arq) trocarTexto(await lerArquivo(arq), arq.name);
              e.target.value = '';
            }}
          />
        </label>
        {arquivo && <span className="text-sm text-[var(--fg-2)]">{arquivo}</span>}
      </div>
      <Textarea
        aria-label="Planilha colada"
        rows={6}
        value={texto}
        onChange={(e) => trocarTexto(e.target.value, null)}
        placeholder="Cole aqui as linhas da planilha, com o cabeçalho."
        className="font-mono"
      />
      {lida && (
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          {fmtNum(lida.linhas.length)} linha(s) de dados.
          {lida.sobrando.length > 0 && ` Colunas ignoradas: ${lida.sobrando.join(', ')}.`}
        </p>
      )}

      <div className="mt-3 space-y-3">
        <Erro msg={erro} />
        {previa && !erro && <p className={`text-sm ${previa.ok ? 'text-[var(--fg)]' : 'text-[var(--red)]'}`}>{previa.msg}</p>}

        {previa && previa.erros.length > 0 && (
          <div>
            <p className="mb-1 text-sm font-semibold text-[var(--fg)]">
              Erros ({fmtNum(errosTotal)}{errosTotal > previa.erros.length ? `, mostrando ${previa.erros.length}` : ''})
            </p>
            <div className="max-h-64 overflow-y-auto">
              <DataTable minWidth={520}>
                <Thead><Th className={thCls}>Linha</Th><Th className={thCls}>Coluna</Th><Th className={thCls}>O que corrigir</Th></Thead>
                <tbody>
                  {previa.erros.map((e, i) => (
                    <Tr key={i}>
                      <Td className="tabular">{naPlanilha(e.linha)}</Td>
                      <Td><span className="font-mono">{e.campo}</span></Td>
                      <Td>{e.msg}</Td>
                    </Tr>
                  ))}
                </tbody>
              </DataTable>
            </div>
          </div>
        )}

        {previa && temDup && (
          <div className="rounded-[var(--r-md)] border border-[var(--yellow-border)] p-3 text-sm">
            <p className="font-semibold text-[var(--fg)]">Possível duplicata (mesma data e hora, projeto, canal e lista)</p>
            {dupBanco.length > 0 && <p className="mt-1 text-[var(--fg-2)]">Já estão no registro: linhas {dupBanco.map(naPlanilha).join(', ')}.</p>}
            {dupLote.length > 0 && <p className="mt-1 text-[var(--fg-2)]">Repetidas na própria planilha: linhas {dupLote.map(naPlanilha).join(', ')}.</p>}
            <div className="mt-2">
              <Checkbox checked={aceitarDup} onChange={setAceitarDup} label={<span className="text-sm text-[var(--fg)]">Gravar mesmo assim as duplicadas</span>} />
            </div>
          </div>
        )}
      </div>
    </Modal>
  );
}
