'use client';

// Registro do CRM: linha do tempo de toda manipulação (mover, editar, criar, trocar dono, perder, concluir…).
// Gestor vê tudo; vendedor vê o que fez + o que tocou os negócios dele (regra em registro.ts).
import { useMemo, useState } from 'react';
import { Button, FilterSelect, SearchInput } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { AcaoLog, EntidadeLog } from '../../domain/types';
import { Aviso, Carregando, Chip, EsqueletoLista, FaixaNumeros, NotaRodape, PaginaComercial, Segmentado, Vazio } from '../comum';
import type { TextoIndicador } from '../InfoIndicador';
import { useAgora } from '../repositorio';
import { NOTA_REGISTRO } from './HistoricoAlteracoes';
import { ItemLog } from './ItemLog';
import {
  ACAO, agruparPorDia, avisoLimite, chipsAtivos, ENTIDADE, FILTRO_INICIAL, filtrarLog, gerarCsv, inicioDoPeriodo, LIMITE_PAGINA, nomeArquivoCsv,
  numerosRegistro, PERIODOS, REGRA_VISIBILIDADE, type FiltroTela, type PeriodoLog,
} from './registro';
import { useRegistroVisivel } from './usar-registro';

const PAGINA = 150;

const INFO: Record<'alteracoes' | 'pessoas' | 'movidos' | 'perdas', TextoIndicador> = {
  alteracoes: {
    nome: 'Alterações no período',
    oQueE: 'Quantas manipulações do CRM foram registradas no período escolhido.',
    comoConta: 'Uma linha do registro = uma escrita (criar, editar, mover, trocar dono, perder, concluir, enviar, aprovar, vincular…). Conta só o que você pode ver.',
    paraQue: 'Ver o volume de trabalho no CRM e achar picos fora do normal.',
  },
  pessoas: {
    nome: 'Pessoas que alteraram',
    oQueE: 'Quantas pessoas diferentes fizeram alguma alteração no período.',
    comoConta: 'Autores distintos. O que o sistema fez (integração, rotina) não entra.',
    paraQue: 'Saber se o time inteiro está usando o CRM ou se alguém está fora.',
  },
  movidos: {
    nome: 'Negócios movidos',
    oQueE: 'Quantos negócios diferentes mudaram de etapa no período.',
    comoConta: 'Negócios distintos com pelo menos uma mudança de etapa; mover o mesmo negócio duas vezes conta uma.',
    paraQue: 'Ver se o funil anda. Clique para ver só as mudanças de etapa.',
  },
  perdas: {
    nome: 'Perdas registradas',
    oQueE: 'Quantas vezes um negócio foi marcado como perdido no período.',
    comoConta: 'Cada "marcou perdido" conta uma vez, com o motivo nos detalhes.',
    paraQue: 'Acompanhar perdas e conferir os motivos. Clique para ver só as perdas.',
  },
};

function baixarCsv(conteudo: string, nome: string) {
  const url = URL.createObjectURL(new Blob([conteudo], { type: 'text/csv;charset=utf-8' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = nome;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

export function RegistroClient() {
  const agora = useAgora(60_000);
  const [f, setF] = useState<FiltroTela>(FILTRO_INICIAL);
  const [mostrar, setMostrar] = useState(PAGINA);
  // Busca no repositório só pelo período; o resto filtra na tela.
  // O banco devolve em páginas (LIMITE_PAGINA) e já recortado pelo que a pessoa pode ver.
  const filtroRepo = useMemo(() => ({ desde: inicioDoPeriodo(f.periodo, new Date()) }), [f.periodo]);
  const reg = useRegistroVisivel(filtroRepo);
  const { vendedores, nomeDe, gestor, sessao } = reg;

  const trocar = <K extends keyof FiltroTela>(k: K, v: FiltroTela[K]) => { setF((x) => ({ ...x, [k]: v })); setMostrar(PAGINA); };

  // Números do período (só período + visibilidade: clicar num número não zera os outros).
  const doPeriodo = useMemo(() => (reg.dados ? filtrarLog(reg.dados, { ...FILTRO_INICIAL, periodo: f.periodo }, agora) : null), [reg.dados, f.periodo, agora]);
  const filtrados = useMemo(() => (reg.dados ? filtrarLog(reg.dados, f, agora) : null), [reg.dados, f, agora]);
  const nums = doPeriodo ? numerosRegistro(doPeriodo) : null;
  const chips = chipsAtivos(f, nomeDe);
  const alternarAcao = (a: AcaoLog) => trocar('acao', f.acao === a ? '' : a);

  const exportar = () => {
    if (filtrados?.length) baixarCsv(gerarCsv(filtrados, nomeDe), nomeArquivoCsv(agora));
  };

  return (
    <PaginaComercial
      titulo="Registro do CRM"
      subtitulo="Toda alteração feita no CRM: quem fez, o quê, em qual registro e quando."
      acoes={
        <Button size="sm" onClick={exportar} disabled={!filtrados?.length} title="Baixa o que está filtrado na tela">
          <Icon name="download" size={14} /> Exportar CSV
        </Button>
      }
      meta={nums ? (
        <FaixaNumeros
          rotulo="Números do registro"
          onLimpar={() => trocar('acao', '')}
          itens={[
            { rotulo: 'Alterações no período', valor: nums.alteracoes, info: INFO.alteracoes },
            { rotulo: 'Pessoas que alteraram', valor: nums.pessoas, info: INFO.pessoas },
            { rotulo: 'Negócios movidos', valor: nums.negociosMovidos, info: INFO.movidos, onClick: () => alternarAcao('moveu_etapa'), ativo: f.acao === 'moveu_etapa' },
            { rotulo: 'Perdas registradas', valor: nums.perdas, info: INFO.perdas, onClick: () => alternarAcao('marcou_perdido'), ativo: f.acao === 'marcou_perdido' },
          ]}
        />
      ) : null}
    >
      {sessao && (
        <Aviso icone="lock" className="mb-4">
          {gestor ? REGRA_VISIBILIDADE.gestor : REGRA_VISIBILIDADE.vendedor}
        </Aviso>
      )}

      <div className="mb-3 flex flex-wrap items-center gap-2">
        <Segmentado<PeriodoLog>
          rotulo="Período"
          valor={f.periodo}
          onChange={(v) => trocar('periodo', v)}
          opcoes={PERIODOS.map((p) => ({ valor: p.valor, rotulo: p.rotulo }))}
        />
        <FilterSelect aria-label="Pessoa" value={f.autor} onChange={(e) => trocar('autor', e.target.value)} className="!py-1.5 !text-xs min-w-[150px]">
          <option value="">Todas as pessoas</option>
          <option value="sistema">Sistema</option>
          {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
        </FilterSelect>
        <FilterSelect aria-label="Tipo de ação" value={f.acao} onChange={(e) => trocar('acao', e.target.value as AcaoLog | '')} className="!py-1.5 !text-xs min-w-[150px]">
          <option value="">Todas as ações</option>
          {(Object.keys(ACAO) as AcaoLog[]).map((a) => <option key={a} value={a}>{ACAO[a].verbo}</option>)}
        </FilterSelect>
        <FilterSelect aria-label="Entidade" value={f.entidade} onChange={(e) => trocar('entidade', e.target.value as EntidadeLog | '')} className="!py-1.5 !text-xs min-w-[150px]">
          <option value="">Todas as entidades</option>
          {(Object.keys(ENTIDADE) as EntidadeLog[]).map((k) => <option key={k} value={k}>{ENTIDADE[k]}</option>)}
        </FilterSelect>
        <div className="min-w-[200px] flex-1">
          <SearchInput
            value={f.busca}
            onChange={(e) => trocar('busca', e.target.value)}
            onLimpar={() => trocar('busca', '')}
            placeholder="Buscar no resumo (ex.: nome do contato)"
            aria-label="Buscar no resumo"
          />
        </div>
      </div>

      {reg.dados && avisoLimite(reg.dados.length, reg.temMais) && (
        <Aviso
          tom="info"
          className="mb-3"
          acao={(
            <Button size="sm" variant="ghost" onClick={() => void reg.carregarMais()} disabled={reg.carregandoMais}>
              {reg.carregandoMais ? 'Carregando…' : `Carregar as ${LIMITE_PAGINA} anteriores`}
            </Button>
          )}
        >
          {avisoLimite(reg.dados.length, reg.temMais)}
          {reg.erroMais && <span className="block text-xs text-[var(--red)]">{reg.erroMais}</span>}
        </Aviso>
      )}

      {chips.length > 0 && (
        <div className="mb-3 flex flex-wrap items-center gap-2" aria-label="Filtros ativos">
          {chips.map((c) => (
            <Chip key={c.chave} ativo onClick={() => trocar(c.chave, FILTRO_INICIAL[c.chave])} title="Remover filtro">
              {c.rotulo} <Icon name="x" size={12} />
            </Chip>
          ))}
          <button type="button" onClick={() => { setF({ ...FILTRO_INICIAL, periodo: f.periodo }); setMostrar(PAGINA); }} className="text-xs text-[var(--fg-2)] hover:text-[var(--fg)] hover:underline">
            Limpar filtros
          </button>
        </div>
      )}

      <Carregando dados={filtrados} erro={reg.erro} onTentar={reg.onTentar} esqueleto={<EsqueletoLista linhas={6} />}>
        {(logs) => {
          if (logs.length === 0) {
            return (
              <Vazio
                icone="clipboard"
                titulo={chips.length ? 'Nenhuma alteração com esses filtros' : 'Nenhuma alteração no período'}
                hint={chips.length ? 'Tire algum filtro ou aumente o período.' : 'Aumente o período para ver alterações mais antigas.'}
                acao={chips.length
                  ? <Button size="sm" variant="ghost" onClick={() => setF({ ...FILTRO_INICIAL, periodo: f.periodo })}>Limpar filtros</Button>
                  : f.periodo !== 'tudo' ? <Button size="sm" variant="ghost" onClick={() => trocar('periodo', 'tudo')}>Ver tudo</Button> : undefined}
              />
            );
          }
          const grupos = agruparPorDia(logs.slice(0, mostrar), agora);
          return (
            <div className="space-y-5">
              <p className="text-xs text-[var(--fg-3)]" aria-live="polite">
                {logs.length} {logs.length === 1 ? 'alteração' : 'alterações'}{logs.length > mostrar ? ` · mostrando ${mostrar}` : ''}
              </p>
              {grupos.map((g) => (
                <section key={g.dia} aria-label={g.titulo}>
                  <h2 className="mb-1.5 flex items-center justify-between text-xs font-semibold text-[var(--fg-2)]">
                    <span className="first-letter:uppercase">{g.titulo}</span>
                    <span className="tabular font-normal text-[var(--fg-3)]">{g.itens.length}</span>
                  </h2>
                  <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)]">
                    {g.itens.map((l) => <ItemLog key={l.id} l={l} nomeDe={nomeDe} />)}
                  </ul>
                </section>
              ))}
              {logs.length > mostrar && (
                <div className="flex justify-center">
                  <Button size="sm" variant="ghost" onClick={() => setMostrar((m) => m + PAGINA)}>
                    Mostrar mais {Math.min(PAGINA, logs.length - mostrar)}
                  </Button>
                </div>
              )}
            </div>
          );
        }}
      </Carregando>

      <NotaRodape className="mt-6">{NOTA_REGISTRO}</NotaRodape>
    </PaginaComercial>
  );
}
