'use client';

// Aba Disparos: o log. "Falta lançar" (período inteiro) antes de tudo; totais e por canal vêm prontos do banco.
// Uma chamada (mkt_msg_disparos_listar) por mudança de filtro ou por gravação. Nada de polling.
import { useEffect, useState } from 'react';
import { Button, FilterSelect, Input, Loading } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import {
  CANAIS, DIAS_PADRAO, LIMITE_DIAS, ROTULO_CANAL, fmtCentavos, fmtNum, periodoPadrao, rotuloCanal,
  type Disparo, type Ferramenta, type ListaDisparos, type Totais, type TotalCanal,
} from '../domain/mensageria';
import { listarDisparos, type FiltroDisparos } from './mensageria-data';
import { ModalArquivar, ModalHistorico, ModalRetorno } from './ModaisLinha';
import { ModalDisparo } from './ModalDisparo';
import { ModalImportar } from './ModalImportar';
import type { Numero } from '../domain/mensageria';
import { Campo, Erro, FaltaLancar, NaoLancado, TabelaDisparos } from './pecas';

/**
 * Carrega a lista do período. Recarrega quando o filtro muda ou quando `versao` sobe (alguém gravou disparo)
 * — mas só se a aba estiver visível; escondida, guarda a versão e recarrega uma vez ao voltar.
 */
export function useListaDisparos(filtro: FiltroDisparos | null, versao: number, ativo: boolean) {
  const [vista, setVista] = useState(versao);
  // Ajuste durante o render (padrão React para "estado derivado da prop anterior"), não em efeito.
  if (ativo && versao !== vista) setVista(versao);
  const chave = filtro ? JSON.stringify(filtro) : null;
  const pedido = chave ? `${vista}|${chave}` : null;
  // Resultado guardado com o pedido que o gerou: pedido novo sem resposta ainda = carregando (undefined).
  const [res, setRes] = useState<{ pedido: string; r: ListaDisparos | null } | null>(null);
  useEffect(() => {
    if (!chave) return;
    let vivo = true;
    const p = `${vista}|${chave}`;
    listarDisparos(JSON.parse(chave) as FiltroDisparos).then((x) => { if (vivo) setRes({ pedido: p, r: x }); });
    return () => { vivo = false; };
  }, [chave, vista]);
  return res && res.pedido === pedido ? res.r : undefined;
}

function Quadro({ rotulo, valor, nota }: { rotulo: string; valor: React.ReactNode; nota?: React.ReactNode }) {
  return (
    <div className="min-w-0 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-2">
      <div className="text-sm text-[var(--fg-2)]">{rotulo}</div>
      <div className="text-lg font-bold tabular text-[var(--fg)]">{valor}</div>
      {nota && <div className="text-sm text-[var(--fg-2)]">{nota}</div>}
    </div>
  );
}

/** Números do período: disparos, custo e um quadro por canal. Tudo do período inteiro (não só das 500 linhas). */
export function QuadrosDoPeriodo({ totais, porCanal }: { totais: Totais; porCanal: TotalCanal[] }) {
  const custo = fmtCentavos(totais.custo_centavos);
  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">
      <Quadro rotulo="Disparos" valor={fmtNum(totais.qtd)} nota={totais.tamanho != null ? `${fmtNum(totais.tamanho)} pessoas` : undefined} />
      <Quadro
        rotulo="Custo R$"
        valor={custo ?? <NaoLancado />}
        nota={totais.sem_custo > 0 && custo ? `fora ${fmtNum(totais.sem_custo)} sem custo` : undefined}
      />
      {porCanal.map((c) => (
        <Quadro
          key={c.canal}
          rotulo={rotuloCanal(c.canal)}
          valor={fmtNum(c.qtd)}
          nota={fmtCentavos(c.custo_centavos) ?? 'sem custo lançado'}
        />
      ))}
    </div>
  );
}

type Modal =
  | { tipo: 'registrar' } | { tipo: 'importar' } | { tipo: 'editar'; d: Disparo } | { tipo: 'retorno'; d: Disparo }
  | { tipo: 'arquivar'; d: Disparo } | { tipo: 'historico'; d: Disparo };

export function AbaDisparos({ hoje, nomeUsuario, projetos, ferramentas, numeros, ativo, versao, onGravou }: {
  hoje: string; nomeUsuario: string; projetos: Projeto[]; ferramentas: Ferramenta[]; numeros: Numero[];
  ativo: boolean; versao: number; onGravou: (msg: string) => void;
}) {
  const [filtro, setFiltro] = useState<FiltroDisparos>(() => ({ ...periodoPadrao(hoje), projeto: null, canal: null, ferramenta: null }));
  const [modal, setModal] = useState<Modal | null>(null);
  const r = useListaDisparos(filtro.de && filtro.ate ? filtro : null, versao, ativo);
  const set = <K extends keyof FiltroDisparos>(k: K, v: FiltroDisparos[K]) => setFiltro((f) => ({ ...f, [k]: v }));
  const gravou = (msg: string) => { setModal(null); onGravou(msg); };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        <Button onClick={() => setModal({ tipo: 'registrar' })}><Icon name="plus" size={16} /> Registrar disparo</Button>
        <Button variant="ghost" onClick={() => setModal({ tipo: 'importar' })}><Icon name="file" size={16} /> Importar planilha</Button>
      </div>

      {r === undefined ? <Loading minHeight={120} /> : r === null ? (
        <Erro msg="Não foi possível carregar os disparos (erro de rede ou sem acesso)." />
      ) : !r.ok ? null : <FaltaLancar totais={r.totais} />}

      <div className="grid grid-cols-2 gap-2 sm:grid-cols-5" aria-label="Filtros">
        <Campo rotulo="De"><Input type="date" value={filtro.de} max={filtro.ate || undefined} onChange={(e) => set('de', e.target.value)} /></Campo>
        <Campo rotulo="Até"><Input type="date" value={filtro.ate} min={filtro.de || undefined} onChange={(e) => set('ate', e.target.value)} /></Campo>
        <Campo rotulo="Projeto">
          <FilterSelect value={filtro.projeto ?? ''} onChange={(e) => set('projeto', e.target.value || null)}>
            <option value="">Todos</option>
            {projetos.map((p) => <option key={p.id} value={p.sigla}>{p.sigla}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Canal">
          <FilterSelect value={filtro.canal ?? ''} onChange={(e) => set('canal', e.target.value || null)}>
            <option value="">Todos</option>
            {CANAIS.map((c) => <option key={c} value={c}>{ROTULO_CANAL[c]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Ferramenta">
          <FilterSelect value={filtro.ferramenta ?? ''} onChange={(e) => set('ferramenta', e.target.value ? Number(e.target.value) : null)}>
            <option value="">Todas</option>
            {ferramentas.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
          </FilterSelect>
        </Campo>
      </div>
      <p className="text-sm text-[var(--fg-2)]">Período de até {LIMITE_DIAS} dias. Padrão: últimos {DIAS_PADRAO} dias.</p>

      {r && !r.ok && <Erro msg={r.msg} />}
      {r && r.ok && (
        <>
          <QuadrosDoPeriodo totais={r.totais} porCanal={r.por_canal} />
          {r.truncado && (
            <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow-border)] px-3 py-2 text-sm text-[var(--fg)]">
              Este período tem mais de {fmtNum(r.limite)} disparos. A tabela mostra os {fmtNum(r.limite)} mais recentes; os números acima contam todos. Encurte o período para ver o resto.
            </p>
          )}
          <TabelaDisparos
            linhas={r.linhas}
            acoes={(d) => (
              <div className="grid grid-cols-[auto_auto] justify-start gap-x-3 gap-y-1">
                <Button variant="link" onClick={() => setModal({ tipo: 'retorno', d })}>Lançar retorno</Button>
                <Button variant="link" onClick={() => setModal({ tipo: 'editar', d })}>Editar</Button>
                <Button variant="link" onClick={() => setModal({ tipo: 'historico', d })}>Ver histórico</Button>
                <Button variant="link" onClick={() => setModal({ tipo: 'arquivar', d })}>Arquivar</Button>
              </div>
            )}
          />
        </>
      )}

      {modal?.tipo === 'registrar' && (
        <ModalDisparo inicial={null} hoje={hoje} nomeUsuario={nomeUsuario} projetos={projetos} ferramentas={ferramentas} numeros={numeros} onFechar={() => setModal(null)} onSalvo={gravou} />
      )}
      {modal?.tipo === 'editar' && (
        <ModalDisparo inicial={modal.d} hoje={hoje} nomeUsuario={nomeUsuario} projetos={projetos} ferramentas={ferramentas} numeros={numeros} onFechar={() => setModal(null)} onSalvo={gravou} />
      )}
      {modal?.tipo === 'importar' && <ModalImportar onFechar={() => setModal(null)} onImportado={gravou} />}
      {modal?.tipo === 'retorno' && <ModalRetorno d={modal.d} onFechar={() => setModal(null)} onSalvo={gravou} />}
      {modal?.tipo === 'arquivar' && <ModalArquivar d={modal.d} onFechar={() => setModal(null)} onSalvo={gravou} />}
      {modal?.tipo === 'historico' && (
        <ModalHistorico tabela="disparos" id={modal.d.id} titulo={`disparo de ${modal.d.projeto}`} onFechar={() => setModal(null)} />
      )}
    </div>
  );
}
