'use client';

// Aba Disparos: o log. "Falta lançar" (período inteiro) antes de tudo; totais e por canal vêm prontos do banco.
// Uma chamada (mkt_msg_disparos_listar) por mudança de filtro ou por gravação. Nada de polling.
import { useEffect, useState } from 'react';
import { Button, FilterSelect, Input, Loading } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import {
  CANAIS, DIAS_PADRAO, LIMITE_DIAS, ROTULO_CANAL, dataHoraSP, fmtCentavos, fmtNum, linhaDaApi, periodoPadrao, resumoCusto, rotuloCanal,
  rotuloPendencia,
  type Disparo, type Ferramenta, type ListaDisparos, type Pendencia, type Totais, type TotalCanal,
} from '../domain/mensageria';
import { listarDisparos, type FiltroDisparos } from './mensageria-data';
import { ModalArquivar, ModalHistorico, ModalRetorno } from './ModaisLinha';
import { ModalDisparo } from './ModalDisparo';
import { ModalImportar } from './ModalImportar';
import type { Numero } from '../domain/mensageria';
import { BotaoLink, Campo, Erro, ErroCarga, FaltaLancar, Faixa, NaoLancado, Quadro, TabelaDisparos, TituloBloco, botaoTopo } from './pecas';

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

/**
 * "R$ 1.200,00 estimado em 4 disparos" (só quando há estimado no período). Quando o estimado é o total inteiro,
 * "todo estimado" em vez de repetir o mesmo valor do número grande.
 */
function notaEstimado(estimado: number | null, total: number | null, qtd?: number) {
  if (estimado == null || estimado <= 0) return null;
  const quanto = estimado === total ? 'todo estimado' : `${fmtCentavos(estimado)} estimado`;
  return `${quanto}${qtd ? ` em ${fmtNum(qtd)} disparo(s)` : ''}`;
}

/**
 * Números do período: disparos, custo total (real + estimado, com o estimado separado) e um quadro por canal.
 * Tudo do período inteiro (não só das 500 linhas).
 */
export function QuadrosDoPeriodo({ totais, porCanal }: { totais: Totais; porCanal: TotalCanal[] }) {
  const { total, estimado } = resumoCusto(totais);
  const custo = fmtCentavos(total);
  const notas = [
    notaEstimado(estimado, total, totais.com_estimativa),
    totais.sem_custo > 0 && custo ? `fora ${fmtNum(totais.sem_custo)} sem custo` : null,
  ].filter(Boolean);
  return (
    <section aria-labelledby="mensageria-no-periodo">
    <TituloBloco id="mensageria-no-periodo" extra="período inteiro, mesmo além das linhas da tabela">No período</TituloBloco>
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-[repeat(auto-fill,minmax(11rem,1fr))]">
      <Quadro rotulo="Disparos" valor={fmtNum(totais.qtd)} nota={totais.tamanho != null ? `${fmtNum(totais.tamanho)} pessoas` : undefined} />
      <Quadro
        rotulo="Custo total"
        valor={custo ?? <NaoLancado />}
        nota={notas.length ? notas.map((n) => <div key={n as string}>{n}</div>) : undefined}
      />
      {porCanal.map((c) => {
        const rc = resumoCusto(c);
        return (
          <Quadro
            key={c.canal}
            rotulo={rotuloCanal(c.canal)}
            valor={fmtNum(c.qtd)}
            nota={<>
              <div>{fmtCentavos(rc.total) ?? 'sem custo lançado'}</div>
              {rc.total != null && notaEstimado(rc.estimado, rc.total) && <div>{notaEstimado(rc.estimado, rc.total)}</div>}
            </>}
          />
        );
      })}
    </div>
    </section>
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
  // Filtro de tela por pendência (clique em "Falta lançar"). Vale só sobre as linhas carregadas.
  const [pend, setPend] = useState<Pendencia | null>(null);
  const r = useListaDisparos(filtro.de && filtro.ate ? filtro : null, versao, ativo);
  const set = <K extends keyof FiltroDisparos>(k: K, v: FiltroDisparos[K]) => setFiltro((f) => ({ ...f, [k]: v }));
  const linhas = r && r.ok ? (pend ? r.linhas.filter((d) => d.pendencias.includes(pend)) : r.linhas) : [];
  const gravou = (msg: string) => { setModal(null); onGravou(msg); };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-2">
        <Button className={botaoTopo} onClick={() => setModal({ tipo: 'registrar' })}><Icon name="plus" size={16} /> Registrar disparo</Button>
        <Button className={botaoTopo} variant="ghost" onClick={() => setModal({ tipo: 'importar' })}><Icon name="file" size={16} /> Importar planilha</Button>
      </div>

      {r === undefined ? <Loading minHeight={120} /> : r === null ? (
        <ErroCarga oque="os disparos" />
      ) : !r.ok ? null : <FaltaLancar totais={r.totais} escolhida={pend} onEscolher={setPend} />}

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
            <Faixa tom="aviso">
              Este período tem mais de {fmtNum(r.limite)} disparos. A tabela mostra os {fmtNum(r.limite)} mais recentes; os números acima contam todos. Encurte o período para ver o resto.
            </Faixa>
          )}
          {pend && (
            <Faixa tom="filtro">
              <span>Mostrando só: <strong>{rotuloPendencia(pend)}</strong> · {fmtNum(linhas.length)} de {fmtNum(r.linhas.length)} linha(s) da tabela
              {r.truncado && ' (a tabela tem só os mais recentes; encurte o período para ver todas)'}</span>
              <BotaoLink onClick={() => setPend(null)}>Mostrar todas</BotaoLink>
            </Faixa>
          )}
          <TabelaDisparos
            linhas={linhas}
            vazio={pend ? 'Nenhuma linha da tabela com essa pendência' : undefined}
            dicaVazio={pend ? 'Clique em "Mostrar todas" para voltar à lista inteira.' : 'Mude as datas acima ou clique em "Registrar disparo".'}
            onClassificar={(d) => setModal({ tipo: 'editar', d })}
            acoes={(d) => {
              const quando = dataHoraSP(d.enviado_em);
              return (
                <div className="grid grid-cols-1 items-center justify-start justify-items-start gap-x-4 sm:grid-cols-[auto_auto]">
                  {linhaDaApi(d)
                    ? <span className="text-sm text-[var(--fg-2)]" title="O retorno vem da integração">Retorno automático</span>
                    : <BotaoLink onClick={() => setModal({ tipo: 'retorno', d })} aria-label={`Lançar retorno do disparo de ${quando}`}>Lançar retorno</BotaoLink>}
                  <BotaoLink onClick={() => setModal({ tipo: 'editar', d })} aria-label={`Editar o disparo de ${quando}`}>Editar</BotaoLink>
                  <BotaoLink onClick={() => setModal({ tipo: 'historico', d })} aria-label={`Ver histórico do disparo de ${quando}`}>Ver histórico</BotaoLink>
                  <BotaoLink onClick={() => setModal({ tipo: 'arquivar', d })} aria-label={`Arquivar o disparo de ${quando}`}>Arquivar</BotaoLink>
                </div>
              );
            }}
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
        <ModalHistorico tabela="disparos" id={modal.d.id} titulo={`disparo de ${modal.d.projeto ?? 'sem projeto'}`} onFechar={() => setModal(null)} />
      )}
    </div>
  );
}
