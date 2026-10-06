'use client';

// Aba Integrações (20261005o): saúde de cada sistema que manda disparos sozinho (mkt_msg_integracoes_saude).
// Só leitura. Busca na 1ª vez que a aba é aberta e quando a pessoa clica "Atualizar"; trocar de aba não refaz consulta.
// Tempos ("há 2 h") contados pelo relógio do banco (`agora` da resposta), não pelo do computador.
// Um quadro por sistema; os que pedem atenção (atrasada, aguardando) vêm primeiro, desligados por último.
import { useState } from 'react';
import { Button, Loading } from '@/shared/ui/components';
import {
  ROTULO_SITUACAO_FONTE, dataBR, dataHoraSP, fmtDuracao, fmtNum, haQuanto, rotuloStatusExecucao, situacaoFonte,
  type FonteSaude, type SituacaoFonte,
} from '../domain/mensageria';
import { saudeIntegracoes } from './mensageria-data';
import { ErroCarga, Faixa, Selo, Vazio, botaoTopo, corAlerta, type TomSelo } from './pecas';
import { useCargaVisivel } from './useCargaVisivel';

const TOM_SITUACAO: Record<SituacaoFonte, TomSelo> = { em_dia: 'ok', atrasada: 'alerta', aguardando: 'aviso', desligada: 'apagado' };
const ORDEM_SITUACAO: Record<SituacaoFonte, number> = { atrasada: 0, aguardando: 1, em_dia: 2, desligada: 3 };

const maiuscula = (t: string) => t.charAt(0).toUpperCase() + t.slice(1);

function Numero7d({ rotulo, v, destaque }: { rotulo: string; v: number; destaque?: boolean }) {
  return (
    <div className="flex min-w-0 flex-col justify-between gap-0.5">
      <dt className="text-sm leading-tight text-[var(--fg-2)]">{rotulo}</dt>
      <dd className={`text-xl font-bold tabular ${destaque && v > 0 ? 'text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>{fmtNum(v)}</dd>
    </div>
  );
}

function QuadroFonte({ f, agora }: { f: FonteSaude; agora: string }) {
  const s = situacaoFonte(f);
  const ultimaOk = haQuanto(f.ultima_ok_em, agora);
  const rc = f.ultima_reconciliacao;
  const idTitulo = `mensageria-fonte-${f.chave}`;
  return (
    <li className="flex min-w-0 flex-col gap-2 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <h3 id={idTitulo} className="text-base font-semibold text-[var(--fg)]">{f.nome}</h3>
          {f.ferramenta && f.ferramenta !== f.nome && <div className="text-sm text-[var(--fg-2)]">{f.ferramenta}</div>}
        </div>
        <Selo tom={TOM_SITUACAO[s]}>{ROTULO_SITUACAO_FONTE[s]}</Selo>
      </div>

      <div>
        <p className="text-base text-[var(--fg)]">
          Última atualização:{' '}
          {ultimaOk
            ? <span className="font-semibold" title={dataHoraSP(f.ultima_ok_em)}>{ultimaOk}</span>
            : <span className="text-[var(--fg-2)]">nenhuma ainda</span>}
        </p>
        <p className="text-sm text-[var(--fg-2)]">
          Esperado a cada {fmtDuracao(f.intervalo_minutos)}
          {f.ultima_execucao_em && (
            <> · última tentativa <span title={dataHoraSP(f.ultima_execucao_em)}>{haQuanto(f.ultima_execucao_em, agora)}</span>, {rotuloStatusExecucao(f.ultima_execucao_status)}</>
          )}
        </p>
        {f.atrasada && f.atraso_minutos != null && (
          <p className={`text-sm font-semibold ${corAlerta}`}>{maiuscula(`sem atualização há ${fmtDuracao(f.atraso_minutos)}`)}</p>
        )}
        {!f.chave_no_vault && <p className={`text-sm font-semibold ${corAlerta}`}>Chave de acesso não criada</p>}
        <p className="text-sm text-[var(--fg-2)]">
          Conferência diária:{' '}
          {rc
            ? <span className="text-[var(--fg)]">{dataBR(rc.dia)} · {rc.faltantes_total > 0 ? `faltaram ${fmtNum(rc.faltantes_total)}` : 'nada faltando'}</span>
            : 'nenhuma ainda'}
        </p>
      </div>

      {/* mt-auto: o bloco de números desce ao pé do quadro, e os números ficam na mesma altura nos quadros da linha. */}
      <div className="mt-auto border-t border-[var(--border)] pt-2">
        <div className="mb-1 text-sm font-semibold uppercase tracking-wide text-[var(--fg-2)]">Últimos 7 dias</div>
        <dl className="grid grid-cols-2 gap-x-3 gap-y-2 sm:grid-cols-4">
          <Numero7d rotulo="Envios" v={f.execucoes_7d} />
          <Numero7d rotulo="Itens recusados" v={f.recusas_7d} destaque />
          <Numero7d rotulo="Com diferença" v={f.inconsistentes_7d} destaque />
          <Numero7d rotulo="Barrados" v={f.negadas_7d} />
        </dl>
      </div>
    </li>
  );
}

export function AbaIntegracoes({ ativo }: { ativo: boolean }) {
  const [versao, setVersao] = useState(0);
  const { dados, atualizando } = useCargaVisivel(saudeIntegracoes, ativo, versao);
  const fontes = dados ? [...dados.fontes].sort((a, b) => ORDEM_SITUACAO[situacaoFonte(a)] - ORDEM_SITUACAO[situacaoFonte(b)]) : [];

  return (
    <div className="space-y-3">
      <Faixa>
        Sistemas que mandam os disparos sozinhos. Atrasada = passou do dobro do tempo esperado sem atualizar. Ligar e desligar é com a equipe técnica.
      </Faixa>
      <div className="flex flex-wrap items-center gap-2">
        <Button className={botaoTopo} variant="ghost" onClick={() => setVersao((v) => v + 1)} disabled={atualizando}>{atualizando ? 'Atualizando…' : 'Atualizar'}</Button>
        {dados && <span className="text-sm text-[var(--fg-2)]">Conferido em {dataHoraSP(dados.agora)}</span>}
      </div>
      {dados === undefined ? <Loading minHeight={120} /> : dados === null ? (
        <ErroCarga oque="as integrações" />
      ) : fontes.length === 0 ? <Vazio titulo="Nenhuma integração cadastrada" dica="Peça à equipe técnica para ligar a primeira." /> : (
        <ul aria-label="Integrações" className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {fontes.map((f) => <QuadroFonte key={f.chave} f={f} agora={dados.agora} />)}
        </ul>
      )}
    </div>
  );
}
