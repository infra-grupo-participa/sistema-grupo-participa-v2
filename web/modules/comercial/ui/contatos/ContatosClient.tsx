'use client';

// Base de pessoas do CRM. Regra do playbook: se não está no CRM, não existe; antes de falar com alguém,
// busque pelo telefone (tem dono, não é seu). Sem dono é meta zero; opt-out fica visível para ninguém abordar.
// Sem rolagem horizontal: em tela larga, 5 colunas enxutas; em tela estreita, cartões. O detalhe mora na ficha.
import { useMemo, useState } from 'react';
import {
  Button, FilterSelect, MultiSelect, SearchInput, Skeleton, Toast, Toggle, Toolbar, useFlash,
} from '@/shared/ui/components';
import { fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { produto, ROTULO_PERFIL } from '../../domain/catalogo';
import { fmtTelefone } from '../../domain/regras';
import type { Contato, Negocio, PerfilProfissional, PontoJornada } from '../../domain/types';
import { Campo, EsqueletoLista, EstadoErro, FaixaNumeros, PaginaComercial, Pessoa, Vazio, useEquipe, useParamUrl } from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { repo, useDados } from '../repositorio';
import { ContatoDrawer } from './ContatoDrawer';
import { indiceContatos, type IndiceContato } from './ficha-contato';
import { ModalNovoContato } from './ModalNovoContato';
import { DonoLinha, FlagsContato, PopoverFiltros } from './pecas';
import { casaBusca, mapaDuplicados, resumoAbertos } from './regras-contatos';

type Coluna = 'nome' | 'dono' | 'negocios' | 'lancamentos' | 'ultima';
const PAGINA = 100;
/** Mesmo molde de colunas no cabeçalho e nas linhas (só em tela larga). Proporcionais: nunca passam do contêiner. */
const GRADE = 'grid grid-cols-[minmax(0,1.6fr)_minmax(0,1fr)_minmax(0,1.3fr)_minmax(0,0.8fr)_minmax(0,1fr)] items-center gap-3 px-3';

const INFO: Record<'total' | 'semDono' | 'optOut' | 'alunos' | 'lancamentos', TextoIndicador> = {
  total: {
    nome: 'Contatos',
    oQueE: 'Pessoas únicas na base do CRM.',
    comoConta: 'Uma pessoa por identidade: e-mail OU últimos 8 dígitos do telefone. Possíveis duplicados ainda contam separados até a mescla.',
  },
  semDono: {
    nome: 'Contatos sem dono',
    oQueE: 'Pessoas da base sem vendedor responsável.',
    comoConta: 'Contato com dono vazio, inclusive quem pediu para não receber contato.',
    paraQue: 'Contato sem dono vira abordagem dupla. O gestor distribui na hora.',
    meta: 'Zero.',
  },
  optOut: {
    nome: 'Opt-out (não querem contato)',
    oQueE: 'Pessoas que pediram para não receber contato.',
    comoConta: 'Contato marcado com opt-out. Ficam na lista de bloqueio: fora de disparos, abordagens e negócio novo.',
    paraQue: 'Respeitar o pedido protege o número oficial de bloqueio e a marca.',
  },
  alunos: {
    nome: 'Já são alunos',
    oQueE: 'Pessoas da base que já compraram algum produto da casa.',
    comoConta: 'Contato marcado como aluno (compra aprovada sincronizada da Hotmart).',
    paraQue: 'Aluno recebe oferta de próximo passo (ascensão), nunca a oferta de entrada de novo.',
  },
  lancamentos: {
    nome: 'Lançamentos',
    oQueE: 'Em quantos lançamentos ou captações diferentes a pessoa já entrou.',
    comoConta: 'Chaves de lançamento distintas na jornada da pessoa.',
  },
};

export function ContatosClient() {
  const { vendedores, nomeDe } = useEquipe();
  const { toast, flash } = useFlash(5000);
  const cs = useDados(() => repo.contatos());
  const ns = useDados(() => repo.negocios());

  const [busca, setBusca] = useState('');
  const [dono, setDono] = useState<string>('todos');
  const [perfil, setPerfil] = useState<PerfilProfissional | 'sem' | 'todos'>('todos');
  const [uf, setUf] = useState('todas');
  const [tagsSel, setTagsSel] = useState<string[]>([]);
  const [soOptOut, setSoOptOut] = useState(false);
  const [soAlunos, setSoAlunos] = useState(false);
  const [ordem, setOrdem] = useState<{ col: Coluna; dir: 'asc' | 'desc' }>({ col: 'ultima', dir: 'desc' });
  const [limite, setLimite] = useState(PAGINA);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  // Contatos cadastrados nesta tela enquanto a fonte não grava contato (demonstração).
  const [locais, setLocais] = useState<Contato[]>([]);
  const paramContato = useParamUrl('contato');
  const contatoAberto = aberto ?? paramContato;

  const lista = useMemo(() => [...locais, ...(cs.dados ?? [])], [cs.dados, locais]);
  const duplicados = useMemo(() => mapaDuplicados(lista), [lista]);
  const abertosPorContato = useMemo(() => {
    const m = new Map<string, Negocio[]>();
    (ns.dados ?? []).filter((n) => n.status === 'aberto').forEach((n) => m.set(n.contatoId, [...(m.get(n.contatoId) ?? []), n]));
    return m;
  }, [ns.dados]);

  // Jornada de cada pessoa para "Lançamentos" e "Última interação". Com o backend, isto vira uma visão agregada
  // (uma consulta só); aqui são consultas paralelas à fonte de demonstração.
  const ids = useMemo(() => (cs.dados ?? []).map((c) => c.id), [cs.dados]);
  const js = useDados(
    async () => new Map<string, PontoJornada[]>(await Promise.all(ids.map(async (id) => [id, await repo.jornada(id)] as const))),
    [ids],
  );
  const indice = useMemo(() => indiceContatos(js.dados ?? new Map(), ns.dados ?? []), [js.dados, ns.dados]);
  const jornadaPronta = !!js.dados;

  const ufs = useMemo(() => [...new Set(lista.map((c) => c.uf).filter((x): x is string => !!x))].sort(), [lista]);
  const tags = useMemo(() => [...new Set(lista.flatMap((c) => c.tags))].sort((a, b) => a.localeCompare(b, 'pt-BR')), [lista]);

  const filtrados = useMemo(() => {
    const res = lista.filter((c) => {
      if (dono === 'sem_dono' ? !!c.donoId : dono !== 'todos' && c.donoId !== dono) return false;
      if (perfil === 'sem' ? !!c.perfil : perfil !== 'todos' && c.perfil !== perfil) return false;
      if (uf !== 'todas' && c.uf !== uf) return false;
      if (tagsSel.length && !tagsSel.some((t) => c.tags.includes(t))) return false;
      if (soOptOut && !c.optOut) return false;
      if (soAlunos && !c.ehAluno) return false;
      return casaBusca(c, busca);
    });
    const valor = (c: Contato): string | number => {
      switch (ordem.col) {
        case 'nome': return c.nome.toLowerCase();
        case 'dono': return c.donoId ? nomeDe(c.donoId) : '';
        case 'negocios': return abertosPorContato.get(c.id)?.length ?? 0;
        case 'lancamentos': return indice.get(c.id)?.lancamentos ?? 0;
        case 'ultima': return indice.get(c.id)?.ultimaEm ?? '';
      }
    };
    const sinal = ordem.dir === 'asc' ? 1 : -1;
    return res.sort((a, b) => {
      const va = valor(a), vb = valor(b);
      const cmp = typeof va === 'number' && typeof vb === 'number' ? va - vb : String(va).localeCompare(String(vb), 'pt-BR');
      return cmp * sinal || a.nome.localeCompare(b.nome, 'pt-BR');
    });
  }, [lista, dono, perfil, uf, tagsSel, soOptOut, soAlunos, busca, ordem, nomeDe, abertosPorContato, indice]);

  const numeros = {
    total: lista.length,
    semDono: lista.filter((c) => !c.donoId).length,
    optOut: lista.filter((c) => c.optOut).length,
    alunos: lista.filter((c) => c.ehAluno).length,
  };

  const ordenar = (col: Coluna) => setOrdem((o) => ({ col, dir: o.col === col && o.dir === 'asc' ? 'desc' : 'asc' }));
  // Filtros escondidos no popover (o contador do botão mostra quantos estão valendo).
  const noPopover = [perfil !== 'todos', uf !== 'todas', tagsSel.length > 0, soOptOut, soAlunos].filter(Boolean).length;
  const filtrosAtivos = !!busca || dono !== 'todos' || noPopover > 0;
  const limpar = () => {
    setBusca(''); setDono('todos'); setPerfil('todos'); setUf('todas'); setTagsSel([]); setSoOptOut(false); setSoAlunos(false);
    setLimite(PAGINA);
  };
  const abrir = (id: string) => setAberto(id);
  const carregando = !cs.dados || !ns.dados;
  const erro = cs.erro ?? ns.erro;

  const botaoNovo = (
    <Button size="sm" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Novo contato</Button>
  );

  return (
    <PaginaComercial
      titulo="Contatos"
      subtitulo="Base única de pessoas do CRM. Antes de abordar, busque pelo nome ou final do telefone."
      acoes={botaoNovo}
      meta={carregando ? undefined : (
        <FaixaNumeros
          itens={[
            { rotulo: 'Contatos', valor: numeros.total.toLocaleString('pt-BR'), info: INFO.total },
            {
              rotulo: 'Sem dono', valor: numeros.semDono.toLocaleString('pt-BR'), alerta: numeros.semDono > 0, ativo: dono === 'sem_dono',
              title: 'Meta: zero. Todo lead tem um dono só.', info: INFO.semDono,
              onClick: () => { setDono((d) => (d === 'sem_dono' ? 'todos' : 'sem_dono')); setLimite(PAGINA); },
            },
            {
              rotulo: 'Não querem contato', valor: numeros.optOut.toLocaleString('pt-BR'), ativo: soOptOut,
              title: 'Opt-out: lista de bloqueio, fora de disparos e abordagens.', info: INFO.optOut,
              onClick: () => { setSoOptOut((v) => !v); setLimite(PAGINA); },
            },
            {
              rotulo: 'Já são alunos', valor: numeros.alunos.toLocaleString('pt-BR'), ativo: soAlunos, info: INFO.alunos,
              onClick: () => { setSoAlunos((v) => !v); setLimite(PAGINA); },
            },
          ]}
        />
      )}
    >
      <div className="space-y-4">
        {erro && carregando ? (
          <EstadoErro mensagem={erro} onTentar={() => { cs.recarregar(); ns.recarregar(); }} />
        ) : (
          <>
            <Toolbar>
              <SearchInput
                placeholder="Nome, e-mail ou final do telefone"
                aria-label="Buscar contato"
                value={busca}
                onChange={(e) => { setBusca(e.target.value); setLimite(PAGINA); }}
                onLimpar={() => setBusca('')}
                className="w-full"
              />
              <div className="flex w-full items-center gap-2 sm:w-auto">
                <FilterSelect value={dono} onChange={(e) => { setDono(e.target.value); setLimite(PAGINA); }} aria-label="Dono" className="min-w-0 flex-1 sm:flex-none">
                  <option value="todos">Todos os donos</option>
                  <option value="sem_dono">Sem dono</option>
                  {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
                </FilterSelect>
                <PopoverFiltros ativos={noPopover}>
                  <Campo rotulo="Perfil">
                    <FilterSelect value={perfil} onChange={(e) => setPerfil(e.target.value as typeof perfil)}>
                      <option value="todos">Todos os perfis</option>
                      {(Object.keys(ROTULO_PERFIL) as PerfilProfissional[]).map((p) => <option key={p} value={p}>{ROTULO_PERFIL[p]}</option>)}
                      <option value="sem">Sem perfil</option>
                    </FilterSelect>
                  </Campo>
                  <Campo rotulo="UF">
                    <FilterSelect value={uf} onChange={(e) => setUf(e.target.value)}>
                      <option value="todas">Todas as UFs</option>
                      {ufs.map((u) => <option key={u} value={u}>{u}</option>)}
                    </FilterSelect>
                  </Campo>
                  <Campo rotulo="Tags">
                    <MultiSelect
                      values={tagsSel}
                      onChange={(v) => { setTagsSel(v); setLimite(PAGINA); }}
                      placeholder="Todas as tags"
                      options={tags.map((t) => ({ value: t, label: t }))}
                    />
                  </Campo>
                  <div className="flex flex-col gap-3">
                    <Toggle checked={soOptOut} onChange={setSoOptOut} label="Só quem não quer contato" />
                    <Toggle checked={soAlunos} onChange={setSoAlunos} label="Só quem já é aluno" />
                  </div>
                </PopoverFiltros>
              </div>
              <div className="ml-auto flex items-center gap-2">
                <span className="text-xs text-[var(--fg-3)] tabular" aria-live="polite">
                  {carregando ? 'Carregando…' : `${filtrados.length.toLocaleString('pt-BR')} de ${lista.length.toLocaleString('pt-BR')}`}
                </span>
                {filtrosAtivos && <Button size="sm" variant="ghost" onClick={limpar}>Limpar</Button>}
              </div>
            </Toolbar>

            {carregando ? (
              <EsqueletoLista linhas={8} />
            ) : filtrados.length === 0 ? (
              lista.length === 0 ? (
                <Vazio
                  titulo="Nenhum contato no CRM"
                  hint="Se a pessoa não está no CRM, ela não existe para o Comercial: cadastre antes de conversar."
                  icone="contact"
                  acao={<Button size="sm" variant="ghost" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Novo contato</Button>}
                />
              ) : (
                <Vazio
                  titulo="Nenhum contato encontrado"
                  hint="Confira a busca ou os filtros. Se a pessoa não está no CRM, cadastre antes de conversar."
                  icone="contact"
                  acao={<>
                    {filtrosAtivos && <Button size="sm" variant="ghost" onClick={limpar}>Limpar filtros</Button>}
                    <Button size="sm" variant="ghost" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Novo contato</Button>
                  </>}
                />
              )
            ) : (
              <>
                {/* Telas largas: colunas enxutas que cabem, sem rolagem horizontal. */}
                <div className="hidden overflow-visible rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] lg:block">
                  <Cabecalho ordem={ordem} onOrdenar={ordenar} />
                  <ul aria-label="Contatos">
                    {filtrados.slice(0, limite).map((c) => (
                      <LinhaContato
                        key={c.id}
                        c={c}
                        abertos={abertosPorContato.get(c.id) ?? []}
                        indice={indice.get(c.id)}
                        jornadaPronta={jornadaPronta}
                        duplicado={duplicados.has(c.id)}
                        nomeDe={nomeDe}
                        onAbrir={() => abrir(c.id)}
                      />
                    ))}
                  </ul>
                </div>
                {/* Telas estreitas: cartões empilhados. */}
                <ul className="space-y-2 lg:hidden" aria-label="Contatos">
                  {filtrados.slice(0, limite).map((c) => (
                    <CartaoContato
                      key={c.id}
                      c={c}
                      abertos={abertosPorContato.get(c.id) ?? []}
                      indice={indice.get(c.id)}
                      duplicado={duplicados.has(c.id)}
                      nomeDe={nomeDe}
                      onAbrir={() => abrir(c.id)}
                    />
                  ))}
                </ul>
                {filtrados.length > limite && (
                  <div className="text-center">
                    <Button size="sm" variant="ghost" onClick={() => setLimite((l) => l + PAGINA)}>
                      Mostrar mais ({(filtrados.length - limite).toLocaleString('pt-BR')} restantes)
                    </Button>
                  </div>
                )}
              </>
            )}
          </>
        )}
      </div>

      {novo && (
        <ModalNovoContato
          contatos={lista}
          nomeDe={nomeDe}
          onClose={() => setNovo(false)}
          onAbrirContato={(id) => { setNovo(false); abrir(id); }}
          onCriado={({ contatoId, local }) => {
            setNovo(false);
            if (local) {
              setLocais((l) => [local, ...l]);
              flash('Contato cadastrado nesta tela. Na demonstração ele não grava: some ao recarregar.');
            } else {
              flash('Contato cadastrado.');
            }
            abrir(contatoId);
          }}
        />
      )}

      {contatoAberto && (
        <ContatoDrawer
          key={contatoAberto}
          contatoId={contatoAberto}
          contatoReserva={locais.find((c) => c.id === contatoAberto)}
          onAbrirContato={abrir}
          onClose={() => {
            setAberto(null);
            if (paramContato) window.history.replaceState(null, '', window.location.pathname + window.location.hash);
          }}
        />
      )}
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

function Cabecalho({ ordem, onOrdenar }: {
  ordem: { col: Coluna; dir: 'asc' | 'desc' }; onOrdenar: (col: Coluna) => void;
}) {
  const col = (k: Coluna, rotulo: string, info?: TextoIndicador, direita = false) => {
    const ativo = ordem.col === k;
    return (
      <div className={`flex min-w-0 items-center gap-0.5 ${direita ? 'justify-end' : ''}`}>
        <button
          type="button"
          onClick={() => onOrdenar(k)}
          aria-label={`Ordenar por ${rotulo}${ativo ? (ordem.dir === 'asc' ? ' (crescente)' : ' (decrescente)') : ''}`}
          className={`inline-flex min-w-0 items-center gap-1 text-[11px] font-semibold uppercase tracking-wide hover:text-[var(--fg)] ${ativo ? 'text-[var(--fg)]' : ''}`}
        >
          <span className="truncate">{rotulo}</span>
          <span className="inline-flex w-3 shrink-0 text-[var(--accent)]">
            {ativo ? <Icon name={ordem.dir === 'asc' ? 'arrow-up' : 'arrow-down'} size={12} /> : null}
          </span>
        </button>
        {info && <InfoIndicador texto={info} />}
      </div>
    );
  };
  return (
    <div className={`${GRADE} rounded-t-[var(--r-lg)] border-b border-[var(--border)] bg-[var(--surface-3)] py-2 text-[var(--fg-3)]`}>
      {col('nome', 'Pessoa')}
      {col('dono', 'Dono')}
      {col('negocios', 'Negócios abertos')}
      {col('lancamentos', 'Lançamentos', INFO.lancamentos, true)}
      {col('ultima', 'Última interação')}
    </div>
  );
}

function NegociosAbertos({ abertos }: { abertos: Negocio[] }) {
  const r = resumoAbertos(abertos.map((n) => ({ produtoNome: produto(n.produto).nome, etapaNome: n.etapaNome })));
  if (!r) return <span className="text-sm text-[var(--fg-3)]">—</span>;
  const todos = abertos.map((n) => `${produto(n.produto).nome} · ${n.etapaNome}`).join('\n');
  return (
    <span className="flex min-w-0 items-center gap-1.5 text-sm" title={todos}>
      <span className="truncate text-[var(--fg-2)]">{r.texto}</span>
      {r.resto > 0 && <span className="shrink-0 text-xs text-[var(--fg-3)] tabular">+{r.resto}</span>}
    </span>
  );
}

// Última interação: o mais recente entre o último ponto da jornada e a última interação dos negócios.
function UltimaInteracao({ em }: { em: string | null | undefined }) {
  const r = fmtRelativo(em);
  return <span className="block truncate text-sm tabular text-[var(--fg-2)]" title={r.title || undefined}>{r.label}</span>;
}

function LinhaContato({ c, abertos, indice, jornadaPronta, duplicado, nomeDe, onAbrir }: {
  c: Contato; abertos: Negocio[]; indice: IndiceContato | undefined; jornadaPronta: boolean; duplicado: boolean;
  nomeDe: (id: string | null) => string; onAbrir: () => void;
}) {
  return (
    // O nome (Pessoa) é o alvo de teclado; o clique na linha inteira é atalho de mouse.
    <li
      onClick={onAbrir}
      className={`${GRADE} cursor-pointer border-t border-[var(--border-faint)] py-2.5 transition-colors first:border-t-0 hover:bg-[var(--surface-3)]`}
    >
      <div className="min-w-0" title={c.email ?? 'sem e-mail'}>
        <Pessoa
          nome={c.nome}
          sub={<span className="tabular">{c.telefone ? fmtTelefone(c.telefone) : (c.email ?? 'sem telefone')}</span>}
          flags={<FlagsContato duplicado={duplicado} optOut={c.optOut} aluno={c.ehAluno} />}
          onClick={onAbrir}
          rotuloAcao={`Abrir ficha de ${c.nome}`}
        />
      </div>
      <DonoLinha c={c} nomeDe={nomeDe} />
      <NegociosAbertos abertos={abertos} />
      <span className="text-right text-sm tabular text-[var(--fg)]">
        {jornadaPronta ? (indice?.lancamentos ?? 0) : <Skeleton w={20} h={12} className="ml-auto" />}
      </span>
      <UltimaInteracao em={indice?.ultimaEm} />
    </li>
  );
}

function CartaoContato({ c, abertos, indice, duplicado, nomeDe, onAbrir }: {
  c: Contato; abertos: Negocio[]; indice: IndiceContato | undefined; duplicado: boolean;
  nomeDe: (id: string | null) => string; onAbrir: () => void;
}) {
  const lancs = indice?.lancamentos ?? 0;
  const ultima = fmtRelativo(indice?.ultimaEm);
  return (
    <li>
      <button
        type="button"
        onClick={onAbrir}
        className="w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-3 text-left transition-colors hover:bg-[var(--surface-3)]"
      >
        <div className="flex min-w-0 items-center justify-between gap-3">
          <span className="flex min-w-0 items-center gap-1.5">
            <span className="truncate text-sm font-medium text-[var(--fg)]">{c.nome}</span>
            <span className="inline-flex shrink-0 items-center gap-1"><FlagsContato duplicado={duplicado} optOut={c.optOut} aluno={c.ehAluno} /></span>
          </span>
          <DonoLinha c={c} nomeDe={nomeDe} className="max-w-[40%] shrink-0 text-right" />
        </div>
        <div className="mt-1 flex min-w-0 items-center justify-between gap-3 text-xs text-[var(--fg-3)]">
          <span className="truncate tabular">{c.telefone ? fmtTelefone(c.telefone) : (c.email ?? 'sem telefone')}</span>
          <span className="min-w-0 max-w-[55%] truncate text-right">
            {abertos.length
              ? `${produto(abertos[0].produto).nome} · ${abertos[0].etapaNome}${abertos.length > 1 ? ` +${abertos.length - 1}` : ''}`
              : 'Sem negócio aberto'}
          </span>
        </div>
        <div className="mt-1 truncate text-xs text-[var(--fg-3)] tabular">
          {lancs} lançamento{lancs === 1 ? '' : 's'} · última interação {ultima.label}
        </div>
      </button>
    </li>
  );
}
