'use client';

// Base de pessoas do CRM. Regra do playbook: se não está no CRM, não existe; antes de falar com alguém,
// busque pelo telefone (tem dono, não é seu). Sem dono é meta zero; opt-out fica visível para ninguém abordar.
// Sem rolagem horizontal: em tela larga, 5 colunas enxutas; em tela estreita, cartões. O detalhe mora na ficha.
// Paginada no servidor (crm_contatos_pagina + crm_contatos_resumo, migration 20261006m): a tela não baixa a base
// inteira nem a lista de negócios. Sem a migration aplicada, o repositório cai no caminho antigo sozinho.
import { useEffect, useState } from 'react';
import {
  Button, FilterSelect, MultiSelect, SearchInput, Toast, Toggle, Toolbar, useFlash,
} from '@/shared/ui/components';
import { fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { produto, ROTULO_PERFIL } from '../../domain/catalogo';
import { CANAIS_ENTRADA, ROTULO_CANAL, nomeProjeto, type CanalEntrada } from '../../domain/catalogacao';
import { fmtTelefone } from '../../domain/regras';
import {
  linhasContatos, passaFiltro, type ContatoLinha, type FiltroContatos, type NegocioAbertoLinha,
} from '../../domain/contatos';
import type { Contato, PerfilProfissional } from '../../domain/types';
import { Campo, EsqueletoLista, EstadoErro, FaixaNumeros, PaginaComercial, Pessoa, Vazio, useEquipe, useParamUrl } from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { repo, useDados } from '../repositorio';
import { ContatoDrawer } from './ContatoDrawer';
import { ModalNovoContato } from './ModalNovoContato';
import { DonoLinha, FlagsContato, OrigemLinha, PopoverFiltros } from './pecas';
import { resumoAbertos } from './regras-contatos';

type Coluna = 'nome' | 'dono' | 'negocios' | 'lancamentos' | 'ultima';
// Página do servidor (crm_contatos_pagina, migration 20261006m): filtro, ordem e contagem no banco.
const PAGINA = 50;
/** Mesmo molde de colunas no cabeçalho e nas linhas (só em tela larga). Proporcionais: nunca passam do contêiner. */
const GRADE = 'grid grid-cols-[minmax(0,1.6fr)_minmax(0,1.2fr)_minmax(0,1fr)_minmax(0,1.3fr)_minmax(0,0.7fr)_minmax(0,1fr)] items-center gap-3 px-3';

const INFO: Record<'total' | 'semDono' | 'optOut' | 'alunos' | 'lancamentos' | 'ultima' | 'origem' | 'semProjeto', TextoIndicador> = {
  origem: {
    nome: 'Origem',
    oQueE: 'Por onde a pessoa entrou na base e de qual projeto (lançamento, seminário, evento) ela veio.',
    comoConta: 'Canal = a evidência mais antiga da pessoa: compra na Hotmart, negócio importado da Clint, evento do ActiveCampaign; sem evidência, quem cadastrou (manual, WhatsApp). Projeto = a primeira evidência que uma regra de catalogação liga a um projeto (lista ou tag do AC, oferta da Hotmart, funil, utm_campaign).',
    paraQue: 'Saber de onde vem cada contato e quanto cada projeto trouxe. O gestor ajusta as regras em Configurações › Catalogação.',
  },
  semProjeto: {
    nome: 'Sem projeto',
    oQueE: 'Contatos que nenhuma regra ligou a um projeto.',
    comoConta: 'Inclui quem só comprou um produto (ex.: ingresso do HT fora de edição cadastrada), quem chegou pelo AC sem lista nem tag e listas ou funis ainda sem regra.',
    paraQue: 'O gestor classifica os valores sem regra em Configurações › Catalogação.',
  },
  ultima: {
    nome: 'Última interação',
    oQueE: 'O registro mais recente da pessoa com a casa.',
    comoConta: 'O mais recente entre inscrições, MQL, compras e checkouts da Hotmart, eventos de integração, negócios (criação, mudanças e última conversa), atividades concluídas e notas, calculado no banco. A ficha mostra a jornada completa, que também casa listas, grupos e pesquisas pelo e-mail ou telefone.',
  },
  total: {
    nome: 'Contatos',
    oQueE: 'Pessoas únicas na base do CRM.',
    comoConta: 'Uma pessoa por identidade: e-mail OU DDD + últimos 8 dígitos do telefone. Possíveis duplicados ainda contam separados até a mescla.',
  },
  semDono: {
    nome: 'Contatos sem dono',
    oQueE: 'Pessoas da base sem vendedor responsável.',
    comoConta: 'Contato com dono vazio, inclusive quem pediu para não receber contato. Para o vendedor, a lista traz só os sem dono com negócio aberto; quem só comprou na Hotmart aparece na busca.',
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
    comoConta: 'Chaves de lançamento distintas na jornada da pessoa (inscrições, MQL e funis dos negócios), calculadas no banco para a página inteira. O detalhe de cada lançamento fica na ficha (aba Jornada).',
  },
};

export function ContatosClient() {
  const { vendedores, nomeDe } = useEquipe();
  const { toast, flash } = useFlash(5000);

  const [busca, setBusca] = useState('');
  const [dono, setDono] = useState<string>('todos');
  const [perfil, setPerfil] = useState<PerfilProfissional | 'sem' | 'todos'>('todos');
  const [uf, setUf] = useState('todas');
  const [tagsSel, setTagsSel] = useState<string[]>([]);
  const [soOptOut, setSoOptOut] = useState(false);
  const [soAlunos, setSoAlunos] = useState(false);
  const [canal, setCanal] = useState<CanalEntrada | 'todos'>('todos');
  const [projeto, setProjeto] = useState<string>('todos');
  const [ordem, setOrdem] = useState<{ col: Coluna; dir: 'asc' | 'desc' }>({ col: 'ultima', dir: 'desc' });
  const [pagina, setPagina] = useState(0);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  // Contatos cadastrados nesta tela enquanto a fonte não grava contato (demonstração).
  const [locais, setLocais] = useState<Contato[]>([]);
  const paramContato = useParamUrl('contato');
  const contatoAberto = aberto ?? paramContato;

  // Busca no servidor: 400 ms depois da última tecla; abaixo de 3 letras não filtra (o servidor exige 3).
  const [termo, setTermo] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setTermo(busca.trim().length >= 3 ? busca.trim() : ''), 400);
    return () => clearTimeout(t);
  }, [busca]);

  // Filtro, ordem e página vão ao banco (crm_contatos_pagina): a tela recebe só a página, com lançamentos,
  // última interação e negócios abertos já calculados em lote. Nada de lista inteira nem histórico por pessoa.
  const filtro: FiltroContatos = {
    busca: termo || undefined, dono, perfil, uf, tags: tagsSel, optOut: soOptOut, soAlunos, canal, projeto,
    ordem: ordem.col, dir: ordem.dir, limite: PAGINA, offset: pagina * PAGINA,
  };
  const pg = useDados(() => repo.contatosPagina(filtro), [filtro]);
  const rs = useDados(() => repo.contatosResumo());

  // Os cadastrados nesta tela (demonstração) aparecem no topo da 1ª página, se passarem nos filtros.
  const locaisVisiveis = pagina === 0 && locais.length
    ? linhasContatos(locais, []).filter((c) => passaFiltro(c, { ...filtro, busca: busca.trim() || undefined }))
    : [];
  const itens: ContatoLinha[] = [...locaisVisiveis, ...(pg.dados?.itens ?? [])];
  const total = (pg.dados?.total ?? 0) + locaisVisiveis.length;
  const paginas = Math.max(1, Math.ceil((pg.dados?.total ?? 0) / PAGINA));

  const numeros = rs.dados
    ? { ...rs.dados, total: rs.dados.total + locais.length, semDono: rs.dados.semDono + locais.filter((c) => !c.donoId).length }
    : null;

  const ordenar = (col: Coluna) => {
    setOrdem((o) => ({ col, dir: o.col === col && o.dir === 'asc' ? 'desc' : 'asc' }));
    setPagina(0);
  };
  // Filtros escondidos no popover (o contador do botão mostra quantos estão valendo).
  const noPopover = [perfil !== 'todos', uf !== 'todas', tagsSel.length > 0, soOptOut, soAlunos, canal !== 'todos', projeto !== 'todos'].filter(Boolean).length;
  const filtrosAtivos = !!busca || dono !== 'todos' || noPopover > 0;
  const limpar = () => {
    setBusca(''); setDono('todos'); setPerfil('todos'); setUf('todas'); setTagsSel([]); setSoOptOut(false); setSoAlunos(false);
    setCanal('todos'); setProjeto('todos');
    setPagina(0);
  };
  const abrir = (id: string) => setAberto(id);
  const carregando = !pg.dados;
  const erro = pg.erro;
  const buscaCurta = busca.trim().length > 0 && busca.trim().length < 3;

  const botaoNovo = (
    <Button size="sm" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Novo contato</Button>
  );

  return (
    <PaginaComercial
      titulo="Contatos"
      subtitulo="Base única de pessoas do CRM. Antes de abordar, busque pelo nome ou final do telefone."
      acoes={botaoNovo}
      meta={!numeros ? undefined : (
        <FaixaNumeros
          itens={[
            { rotulo: 'Contatos', valor: numeros.total.toLocaleString('pt-BR'), info: INFO.total },
            {
              rotulo: 'Sem dono', valor: numeros.semDono.toLocaleString('pt-BR'), alerta: numeros.semDono > 0, ativo: dono === 'sem_dono',
              title: 'Meta: zero. Todo lead tem um dono só.', info: INFO.semDono,
              onClick: () => { setDono((d) => (d === 'sem_dono' ? 'todos' : 'sem_dono')); setPagina(0); },
            },
            {
              rotulo: 'Não querem contato', valor: numeros.optOut.toLocaleString('pt-BR'), ativo: soOptOut,
              title: 'Opt-out: lista de bloqueio, fora de disparos e abordagens.', info: INFO.optOut,
              onClick: () => { setSoOptOut((v) => !v); setPagina(0); },
            },
            {
              rotulo: 'Já são alunos', valor: numeros.alunos.toLocaleString('pt-BR'), ativo: soAlunos, info: INFO.alunos,
              onClick: () => { setSoAlunos((v) => !v); setPagina(0); },
            },
            ...(numeros.semProjeto === undefined ? [] : [{
              rotulo: 'Sem projeto', valor: numeros.semProjeto.toLocaleString('pt-BR'), ativo: projeto === 'sem', info: INFO.semProjeto,
              title: 'Contatos que nenhuma regra ligou a um projeto.',
              onClick: () => { setProjeto((p) => (p === 'sem' ? 'todos' : 'sem')); setPagina(0); },
            }]),
          ]}
        />
      )}
    >
      <div className="space-y-4">
        {erro && carregando ? (
          <EstadoErro mensagem={erro} onTentar={() => { pg.recarregar(); rs.recarregar(); }} />
        ) : (
          <>
            <Toolbar>
              <SearchInput
                placeholder="Nome, e-mail ou final do telefone"
                aria-label="Buscar contato"
                value={busca}
                onChange={(e) => { setBusca(e.target.value); setPagina(0); }}
                onLimpar={() => { setBusca(''); setPagina(0); }}
                className="w-full"
              />
              <div className="flex w-full items-center gap-2 sm:w-auto">
                <FilterSelect value={dono} onChange={(e) => { setDono(e.target.value); setPagina(0); }} aria-label="Dono" className="min-w-0 flex-1 sm:flex-none">
                  <option value="todos">Todos os donos</option>
                  <option value="sem_dono">Sem dono</option>
                  {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
                </FilterSelect>
                <PopoverFiltros ativos={noPopover}>
                  <Campo rotulo="Perfil">
                    <FilterSelect value={perfil} onChange={(e) => { setPerfil(e.target.value as typeof perfil); setPagina(0); }}>
                      <option value="todos">Todos os perfis</option>
                      {(Object.keys(ROTULO_PERFIL) as PerfilProfissional[]).map((p) => <option key={p} value={p}>{ROTULO_PERFIL[p]}</option>)}
                      <option value="sem">Sem perfil</option>
                    </FilterSelect>
                  </Campo>
                  <Campo rotulo="UF">
                    <FilterSelect value={uf} onChange={(e) => { setUf(e.target.value); setPagina(0); }}>
                      <option value="todas">Todas as UFs</option>
                      {(rs.dados?.ufs ?? []).map((u) => <option key={u} value={u}>{u}</option>)}
                    </FilterSelect>
                  </Campo>
                  <Campo rotulo="Tags">
                    <MultiSelect
                      values={tagsSel}
                      onChange={(v) => { setTagsSel(v); setPagina(0); }}
                      placeholder="Todas as tags"
                      options={(rs.dados?.tags ?? []).map((t) => ({ value: t, label: t }))}
                    />
                  </Campo>
                  <Campo rotulo="Canal de entrada">
                    <FilterSelect value={canal} onChange={(e) => { setCanal(e.target.value as typeof canal); setPagina(0); }}>
                      <option value="todos">Todos os canais</option>
                      {(rs.dados?.canais?.map((x) => x.canal) ?? CANAIS_ENTRADA).map((k) => (
                        <option key={k} value={k}>
                          {ROTULO_CANAL[k]}{rs.dados?.canais ? ` (${(rs.dados.canais.find((x) => x.canal === k)?.total ?? 0).toLocaleString('pt-BR')})` : ''}
                        </option>
                      ))}
                    </FilterSelect>
                  </Campo>
                  <Campo rotulo="Projeto">
                    <FilterSelect value={projeto} onChange={(e) => { setProjeto(e.target.value); setPagina(0); }}>
                      <option value="todos">Todos os projetos</option>
                      <option value="sem">Sem projeto{rs.dados?.semProjeto !== undefined ? ` (${rs.dados.semProjeto.toLocaleString('pt-BR')})` : ''}</option>
                      {(rs.dados?.projetos ?? []).map((p) => (
                        <option key={p.chave} value={p.chave}>{nomeProjeto(p.chave, p.nome)} ({p.total.toLocaleString('pt-BR')})</option>
                      ))}
                    </FilterSelect>
                  </Campo>
                  <div className="flex flex-col gap-3">
                    <Toggle checked={soOptOut} onChange={(v) => { setSoOptOut(v); setPagina(0); }} label="Só quem não quer contato" />
                    <Toggle checked={soAlunos} onChange={(v) => { setSoAlunos(v); setPagina(0); }} label="Só quem já é aluno" />
                  </div>
                </PopoverFiltros>
              </div>
              <div className="ml-auto flex items-center gap-2">
                <span className="text-xs text-[var(--fg-3)] tabular" aria-live="polite">
                  {carregando ? 'Carregando…' : buscaCurta ? 'Busca a partir de 3 letras' : `${total.toLocaleString('pt-BR')} contato${total === 1 ? '' : 's'}`}
                </span>
                {filtrosAtivos && <Button size="sm" variant="ghost" onClick={limpar}>Limpar</Button>}
              </div>
            </Toolbar>

            {carregando ? (
              <EsqueletoLista linhas={8} />
            ) : itens.length === 0 ? (
              !filtrosAtivos ? (
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
                    <Button size="sm" variant="ghost" onClick={limpar}>Limpar filtros</Button>
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
                    {itens.map((c) => (
                      <LinhaContato key={c.id} c={c} nomeDe={nomeDe} onAbrir={() => abrir(c.id)} />
                    ))}
                  </ul>
                </div>
                {/* Telas estreitas: cartões empilhados. */}
                <ul className="space-y-2 lg:hidden" aria-label="Contatos">
                  {itens.map((c) => (
                    <CartaoContato key={c.id} c={c} nomeDe={nomeDe} onAbrir={() => abrir(c.id)} />
                  ))}
                </ul>
                {paginas > 1 && (
                  <nav aria-label="Páginas de contatos" className="flex items-center justify-center gap-3">
                    <Button size="sm" variant="ghost" disabled={pagina === 0} onClick={() => setPagina((p) => Math.max(0, p - 1))}>
                      <Icon name="chevron-left" size={14} /> Anterior
                    </Button>
                    <span className="text-xs text-[var(--fg-3)] tabular">
                      {(pagina * PAGINA + 1).toLocaleString('pt-BR')}–{Math.min((pagina + 1) * PAGINA, pg.dados?.total ?? 0).toLocaleString('pt-BR')} de {(pg.dados?.total ?? 0).toLocaleString('pt-BR')}
                    </span>
                    <Button size="sm" variant="ghost" disabled={pagina + 1 >= paginas} onClick={() => setPagina((p) => p + 1)}>
                      Próxima <Icon name="chevron-right" size={14} />
                    </Button>
                  </nav>
                )}
              </>
            )}
          </>
        )}
      </div>

      {novo && (
        <ModalNovoContato
          contatosLocais={locais}
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
          contatoReserva={locais.find((c) => c.id === contatoAberto) ?? itens.find((c) => c.id === contatoAberto)}
          reservaDaBusca={!locais.some((c) => c.id === contatoAberto)}
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
  const col = (k: Coluna, rotulo: string, info?: TextoIndicador, direita = false, ordenavel = true) => {
    const ativo = ordem.col === k;
    if (!ordenavel) {
      return (
        <div className={`flex min-w-0 items-center gap-0.5 ${direita ? 'justify-end' : ''}`}>
          <span className="truncate text-[11px] font-semibold uppercase tracking-wide">{rotulo}</span>
          {info && <InfoIndicador texto={info} />}
        </div>
      );
    }
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
      {col('nome', 'Origem', INFO.origem, false, false)}
      {col('dono', 'Dono')}
      {col('negocios', 'Negócios abertos')}
      {col('lancamentos', 'Lançamentos', INFO.lancamentos, true)}
      {col('ultima', 'Última interação', INFO.ultima)}
    </div>
  );
}

function NegociosAbertos({ abertos }: { abertos: NegocioAbertoLinha[] }) {
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

// Última interação: a mais recente, calculada no banco para a página (a jornada completa fica na ficha).
function UltimaInteracao({ em }: { em: string | null | undefined }) {
  const r = fmtRelativo(em);
  return <span className="block truncate text-sm tabular text-[var(--fg-2)]" title={r.title || undefined}>{r.label}</span>;
}

// O aviso de possível duplicado fica na ficha (o banco compara o telefone inteiro); a lista paginada não tem a base
// toda para comparar.
function LinhaContato({ c, nomeDe, onAbrir }: {
  c: ContatoLinha; nomeDe: (id: string | null) => string; onAbrir: () => void;
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
          flags={<FlagsContato duplicado={false} optOut={c.optOut} aluno={c.ehAluno} />}
          onClick={onAbrir}
          rotuloAcao={`Abrir ficha de ${c.nome}`}
        />
      </div>
      <OrigemLinha origem={c.origem} />
      <DonoLinha c={c} nomeDe={nomeDe} />
      <NegociosAbertos abertos={c.abertos} />
      <span className="text-right text-sm tabular text-[var(--fg-2)]">{c.lancamentos ? c.lancamentos.toLocaleString('pt-BR') : '—'}</span>
      <UltimaInteracao em={c.ultimaInteracaoEm} />
    </li>
  );
}

function CartaoContato({ c, nomeDe, onAbrir }: {
  c: ContatoLinha; nomeDe: (id: string | null) => string; onAbrir: () => void;
}) {
  const ultima = fmtRelativo(c.ultimaInteracaoEm);
  const abertos = c.abertos;
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
            <span className="inline-flex shrink-0 items-center gap-1"><FlagsContato duplicado={false} optOut={c.optOut} aluno={c.ehAluno} /></span>
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
        {c.origem && <OrigemLinha origem={c.origem} compacta className="mt-1" />}
        <div className="mt-1 truncate text-xs text-[var(--fg-3)] tabular">
          Última interação {ultima.label}{c.lancamentos ? ` · ${c.lancamentos} lançamento${c.lancamentos > 1 ? 's' : ''}` : ''}
        </div>
      </button>
    </li>
  );
}
