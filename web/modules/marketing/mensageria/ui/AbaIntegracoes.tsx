'use client';

// Aba Integrações (20261005o): saúde de cada sistema que manda disparos sozinho (mkt_msg_integracoes_saude).
// Só leitura. Busca na 1ª vez que a aba é aberta e quando a pessoa clica "Atualizar"; trocar de aba não refaz consulta.
// Tempos ("há 2 h") contados pelo relógio do banco (`agora` da resposta), não pelo do computador.
import { useState } from 'react';
import { Button, DataTable, EmptyState, Loading, Td, Th, Thead, Tr } from '@/shared/ui/components';
import {
  ROTULO_SITUACAO_FONTE, dataBR, dataHoraSP, fmtDuracao, fmtNum, haQuanto, rotuloStatusExecucao, situacaoFonte,
  type FonteSaude,
} from '../domain/mensageria';
import { saudeIntegracoes } from './mensageria-data';
import { Erro, thCls } from './pecas';
import { useCargaVisivel } from './useCargaVisivel';

function Situacao({ f }: { f: FonteSaude }) {
  const s = situacaoFonte(f);
  const alerta = s === 'atrasada';
  return (
    <span className={`whitespace-nowrap ${alerta ? 'font-semibold text-[var(--red)]' : s === 'desligada' ? 'text-[var(--fg-2)]' : 'text-[var(--fg)]'}`}>
      {ROTULO_SITUACAO_FONTE[s]}
    </span>
  );
}

function Linha({ f, agora }: { f: FonteSaude; agora: string }) {
  const ultimaOk = haQuanto(f.ultima_ok_em, agora);
  const rc = f.ultima_reconciliacao;
  return (
    <Tr className={f.ativa ? '' : 'opacity-60'}>
      <Td>
        <div className="whitespace-nowrap font-semibold">{f.nome}</div>
        {f.ferramenta && f.ferramenta !== f.nome && <div className="whitespace-nowrap text-sm text-[var(--fg-2)]">{f.ferramenta}</div>}
      </Td>
      <Td>
        <Situacao f={f} />
        {f.atrasada && f.atraso_minutos != null && (
          <div className="text-sm text-[var(--fg-2)]">sem atualização há {fmtDuracao(f.atraso_minutos)}</div>
        )}
        {!f.chave_no_vault && <div className="text-sm text-[var(--red)]">Chave de acesso não criada</div>}
      </Td>
      <Td>
        {ultimaOk
          ? <span className="whitespace-nowrap" title={dataHoraSP(f.ultima_ok_em)}>{ultimaOk.charAt(0).toUpperCase() + ultimaOk.slice(1)}</span>
          : <span className="text-[var(--fg-2)]">Nenhuma ainda</span>}
      </Td>
      <Td className="whitespace-nowrap">a cada {fmtDuracao(f.intervalo_minutos)}</Td>
      <Td>
        {f.ultima_execucao_em ? (
          <>
            <div className="whitespace-nowrap" title={dataHoraSP(f.ultima_execucao_em)}>{haQuanto(f.ultima_execucao_em, agora)}</div>
            <div className="whitespace-nowrap text-sm text-[var(--fg-2)]">{rotuloStatusExecucao(f.ultima_execucao_status)}</div>
          </>
        ) : <span className="text-[var(--fg-2)]">—</span>}
      </Td>
      <Td className="tabular">{fmtNum(f.execucoes_7d)}</Td>
      <Td className={`tabular ${f.recusas_7d > 0 ? 'font-semibold' : ''}`}>{fmtNum(f.recusas_7d)}</Td>
      <Td className={`tabular ${f.inconsistentes_7d > 0 ? 'font-semibold' : ''}`}>{fmtNum(f.inconsistentes_7d)}</Td>
      <Td className="tabular">{fmtNum(f.negadas_7d)}</Td>
      <Td>
        {rc ? (
          <span className="whitespace-nowrap">
            {dataBR(rc.dia)} · {rc.faltantes_total > 0 ? `faltaram ${fmtNum(rc.faltantes_total)}` : 'nada faltando'}
          </span>
        ) : <span className="text-[var(--fg-2)]">—</span>}
      </Td>
    </Tr>
  );
}

export function AbaIntegracoes({ ativo }: { ativo: boolean }) {
  const [versao, setVersao] = useState(0);
  const { dados, atualizando } = useCargaVisivel(saudeIntegracoes, ativo, versao);

  return (
    <div className="space-y-3">
      <p role="note" className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2 text-sm text-[var(--fg)]">
        Sistemas que mandam os disparos sozinhos. Atrasada = passou do dobro do tempo esperado sem atualizar. Ligar e desligar é com a equipe técnica.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <Button variant="ghost" onClick={() => setVersao((v) => v + 1)} disabled={atualizando}>{atualizando ? 'Atualizando…' : 'Atualizar'}</Button>
        {dados && <span className="text-sm text-[var(--fg-2)]">Conferido em {dataHoraSP(dados.agora)}</span>}
      </div>
      {dados === undefined ? <Loading minHeight={120} /> : dados === null ? (
        <Erro msg="Não foi possível carregar as integrações (erro de rede ou sem acesso)." />
      ) : dados.fontes.length === 0 ? <EmptyState title="Nenhuma integração cadastrada" /> : (
        <DataTable minWidth={1200}>
          <Thead>
            {['Sistema', 'Situação', 'Última atualização', 'Esperado', 'Última tentativa', 'Envios 7 dias', 'Itens recusados 7 dias', 'Com diferença 7 dias', 'Barrados 7 dias', 'Conferência diária'].map((c) => <Th key={c} className={thCls}>{c}</Th>)}
          </Thead>
          <tbody>
            {dados.fontes.map((f) => <Linha key={f.chave} f={f} agora={dados.agora} />)}
          </tbody>
        </DataTable>
      )}
    </div>
  );
}
