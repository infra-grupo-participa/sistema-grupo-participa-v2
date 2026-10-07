'use client';

// Aba #catalogacao: de onde vêm os contatos e de qual projeto (migration 20261007141044). As regras (projeto e MQL) são da
// área de Dados (Victor Hugo): só Dados/admin/dev editam. O gestor comercial vê tudo, reaplica aos sem projeto e
// classifica contato a contato na ficha. Projeto só da lista de gp-operacoes/projetos.
// Nada se apaga: desativar tira a regra do cálculo. Depois de mexer, "Reaplicar" recataloga os contatos sem projeto.
import { useState } from 'react';
import { Badge, Button, Card, Checkbox, FilterSelect, Input, Modal, SectionTitle, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  DICA_CAMPO_REGRA, ORDEM_CAMPOS, ROTULO_CAMPO_REGRA, ROTULO_CANAL, ROTULO_OPERADOR, fraseRegra, nomeProjeto, rascunhoRegra,
  validarRegra,
  type CampoRegra, type OperadorRegra, type TipoRegra, type PainelCatalogo, type PendenciaCatalogo, type RascunhoRegra, type RegraCatalogo,
} from '../../domain/catalogacao';
import { Aviso, Campo, Carregando, EsqueletoLista, FaixaNumeros, NotaRodape, Vazio } from '../comum';
import { avisarMudanca, repo, useDados } from '../repositorio';

const PENDENCIAS_VISIVEIS = 30;

export function AbaCatalogacao({ flash }: { gestor?: boolean; flash: (m: string) => void }) {
  const r = useDados(() => repo.catalogo());
  // undefined = modal fechado; objeto = rascunho (nova ou edição)
  const [editando, setEditando] = useState<Partial<RegraCatalogo> | undefined>(undefined);
  const [reaplicando, setReaplicando] = useState(false);
  const [todasPend, setTodasPend] = useState(false);
  const [verInativas, setVerInativas] = useState(false);

  async function reaplicar() {
    setReaplicando(true);
    const res = await repo.reaplicarCatalogo(false);
    setReaplicando(false);
    flash(res.msg ?? (res.ok ? 'Regras reaplicadas.' : 'Não foi possível reaplicar.'));
    if (res.ok) { await r.recarregar(); avisarMudanca(); }
  }

  async function alternar(regra: RegraCatalogo) {
    const res = await repo.salvarRegraCatalogo({ ...regra, ativo: !regra.ativo });
    flash(res.ok ? (regra.ativo ? 'Regra desativada. Reaplique para recatalogar.' : 'Regra reativada. Reaplique para recatalogar.') : res.msg ?? 'Não foi possível salvar.');
    if (res.ok) await r.recarregar();
  }

  return (
    <div className="space-y-6">
      <Carregando dados={r.dados} erro={r.erro} onTentar={() => { void r.recarregar(); }} esqueleto={<EsqueletoLista linhas={6} avatar={false} />}>
        {(p: PainelCatalogo) => {
          const podeEditar = p.podeEditar;
          const podeReaplicar = p.podeClassificar;
          const regras = p.regras.filter((x) => verInativas || x.ativo);
          const pend = todasPend ? p.pendencias : p.pendencias.slice(0, PENDENCIAS_VISIVEIS);
          const pct = (n: number) => (p.resumo.total ? ` (${Math.round((100 * n) / p.resumo.total)}%)` : '');
          return (
            <>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <FaixaNumeros itens={[
                  { rotulo: 'Contatos', valor: p.resumo.total.toLocaleString('pt-BR'),
                    info: { nome: 'Contatos catalogados', oQueE: 'Contatos do CRM com origem registrada (canal, quando, projeto).' } },
                  { rotulo: 'Com projeto', valor: `${p.resumo.comProjeto.toLocaleString('pt-BR')}${pct(p.resumo.comProjeto)}`,
                    info: { nome: 'Com projeto', oQueE: 'Uma regra (ou a UTM, o funil, o gestor) ligou o contato a um projeto.' } },
                  { rotulo: 'MQL', valor: p.resumo.mql.toLocaleString('pt-BR'),
                    info: { nome: 'MQL', oQueE: 'Contatos com tag ou lista que uma regra de MQL do projeto marca (ex.: tag "PB MQL").', comoConta: 'A primeira evidência que casa uma regra tipo MQL. "PB NAO MQL" não conta.' } },
                  { rotulo: 'Produto, sem projeto', valor: p.resumo.produtoSemProjeto.toLocaleString('pt-BR'),
                    info: { nome: 'Produto, sem projeto', oQueE: 'Comprou ou está num funil de produto (HT, HM, Acelera…), mas nada diz de qual edição ou lançamento.', paraQue: 'Criar regra por oferta com janela de datas, ou cadastrar o projeto que falta.' } },
                  { rotulo: 'Sem nada', valor: p.resumo.semNada.toLocaleString('pt-BR'), alerta: p.resumo.semNada > 0,
                    info: { nome: 'Sem nada', oQueE: 'Nem projeto nem produto: em geral lead do ActiveCampaign que chegou sem lista nem tag (atualização de contato).' } },
                ]} />
                {(podeEditar || podeReaplicar) && (
                  <div className="flex flex-wrap gap-2">
                    {podeReaplicar && (
                      <Button size="sm" variant="ghost" disabled={reaplicando} onClick={() => { void reaplicar(); }}>
                        <Icon name="refresh" size={14} /> {reaplicando ? 'Reaplicando…' : 'Reaplicar aos sem projeto'}
                      </Button>
                    )}
                    {podeEditar && <Button size="sm" onClick={() => setEditando({})}><Icon name="plus" size={14} /> Nova regra</Button>}
                  </div>
                )}
              </div>

              <Aviso tom="neutral" icone={podeEditar ? 'users' : 'lock'} titulo="Regras da área de Dados (Victor Hugo)">
                Quem cria, edita e desativa as regras de projeto e de MQL é a área de Dados. O projeto vem sempre da lista de
                gp-operacoes/projetos: valor que não é de projeto fica &ldquo;sem projeto&rdquo; até o Dados cadastrar.
                {podeEditar ? '' : ' Você vê em leitura: peça ao Victor. Contato a contato, o gestor define o projeto na ficha (Como entrou).'}
              </Aviso>

              <section className="grid gap-4 md:grid-cols-2">
                <Card className="p-3">
                  <SectionTitle>Por canal de entrada</SectionTitle>
                  <ul className="divide-y divide-[var(--border-faint)]">
                    {p.resumo.porCanal.map((c) => (
                      <li key={c.canal} className="flex items-center justify-between gap-3 py-1.5 text-sm">
                        <span className="text-[var(--fg-2)]">{ROTULO_CANAL[c.canal]}</span>
                        <span className="tabular text-[var(--fg)]">
                          {c.total.toLocaleString('pt-BR')} <span className="text-xs text-[var(--fg-3)]">· {c.comProjeto.toLocaleString('pt-BR')} com projeto</span>
                        </span>
                      </li>
                    ))}
                  </ul>
                </Card>
                <Card className="p-3">
                  <SectionTitle>Por projeto</SectionTitle>
                  <ul className="divide-y divide-[var(--border-faint)]">
                    {p.projetos.filter((x) => x.contatos > 0).sort((a, b) => b.contatos - a.contatos).map((x) => (
                      <li key={x.chave} className="flex items-center justify-between gap-3 py-1.5 text-sm" title={x.chave}>
                        <span className="min-w-0 truncate text-[var(--fg-2)]">{nomeProjeto(x.chave, x.nome)}</span>
                        <span className="tabular text-[var(--fg)]">{x.contatos.toLocaleString('pt-BR')}</span>
                      </li>
                    ))}
                    {p.resumo.semProjetoPorLinha.map((l) => (
                      <li key={`sem-${l.linha}`} className="flex items-center justify-between gap-3 py-1.5 text-sm">
                        <span className="text-[var(--fg-3)]">Sem projeto{l.linha !== '-' ? ` · ${l.linha.toUpperCase()}` : ''}</span>
                        <span className="tabular text-[var(--fg-3)]">{l.total.toLocaleString('pt-BR')}</span>
                      </li>
                    ))}
                  </ul>
                </Card>
              </section>

              <section>
                <SectionTitle right={<span className="text-[11px] text-[var(--fg-3)] tabular">{p.pendencias.length}</span>}>
                  Sem regra: o que falta classificar
                </SectionTitle>
                <p className="mb-2 text-xs text-[var(--fg-3)]">
                  Valores vistos nos contatos sem projeto que nenhuma regra cobre, do mais frequente para o menos.
                  {podeEditar ? ' “Classificar” abre a regra já preenchida.' : ' Para classificar um valor, peça ao Victor (Dados).'}
                </p>
                {pend.length ? (
                  <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)]">
                    {pend.map((x) => (
                      <LinhaPendencia key={`${x.campo}|${x.valor}`} x={x} podeEditar={podeEditar}
                        onClassificar={() => setEditando({ campo: x.campo, operador: 'igual', padrao: x.valor })} />
                    ))}
                  </ul>
                ) : (
                  <Card><Vazio titulo="Nada pendente" hint="Todo valor visto nos contatos já tem regra." icone="check" /></Card>
                )}
                {p.pendencias.length > PENDENCIAS_VISIVEIS && (
                  <Button size="sm" variant="link" className="mt-1" onClick={() => setTodasPend((v) => !v)}>
                    {todasPend ? 'mostrar menos' : `ver todas (${p.pendencias.length})`}
                  </Button>
                )}
              </section>

              <section>
                <SectionTitle
                  right={(
                    <Checkbox checked={verInativas} onChange={setVerInativas} label="Mostrar desativadas" />
                  )}
                >
                  Regras de catalogação
                </SectionTitle>
                <p className="mb-2 text-xs text-[var(--fg-3)]">
                  Ordem: UTM campaign, lista do AC, tag do AC, oferta da Hotmart, funil, produto, formulário, SCK. Dentro do campo,
                  menor prioridade primeiro, depois “é igual” antes de “começa com” e “contém”. utm_campaign igual à chave de um
                  projeto conhecido liga sozinha.
                </p>
                {regras.length ? (
                  <ul className="space-y-2">
                    {regras.map((x) => (
                      <LinhaRegra key={x.id} x={x} podeEditar={podeEditar}
                        onEditar={() => setEditando(x)} onAlternar={() => { void alternar(x); }} />
                    ))}
                  </ul>
                ) : (
                  <Card><Vazio titulo="Nenhuma regra" icone="tags" /></Card>
                )}
              </section>

              <ListasAc listas={p.listasAc} podeEditar={podeEditar} flash={flash} onSalvo={() => { void r.recarregar(); }} />

              <NotaRodape>
                Chave do projeto = a mesma do utm_campaign, da etiqueta do ClickUp e da pasta do projeto (ex.: seminario-conjunto-2026-11).
                O nome vem do cadastro de projetos do Marketing quando ele tem a chave. Nada se apaga: desativar tira a regra do cálculo.
              </NotaRodape>

              {editando !== undefined && (
                <ModalRegra
                  inicial={editando}
                  projetos={p.projetos}
                  listas={p.listasAc}
                  onFechar={() => setEditando(undefined)}
                  onSalvo={async (msg) => { setEditando(undefined); flash(`${msg} Reaplique para recatalogar os sem projeto.`); await r.recarregar(); }}
                />
              )}
            </>
          );
        }}
      </Carregando>
    </div>
  );
}

function LinhaPendencia({ x, podeEditar, onClassificar }: { x: PendenciaCatalogo; podeEditar: boolean; onClassificar: () => void }) {
  return (
    <li className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 px-3 py-2">
      <div className="min-w-0 flex-1 basis-56">
        <div className="text-xs text-[var(--fg-3)]">{ROTULO_CAMPO_REGRA[x.campo]}</div>
        <div className="truncate text-sm text-[var(--fg)]" title={x.nome ?? x.valor}>
          <code>{x.valor}</code>{x.nome ? <span className="text-[var(--fg-2)]"> · {x.nome}</span> : null}
        </div>
      </div>
      <span className="shrink-0 text-sm tabular text-[var(--fg-2)]">{x.contatos.toLocaleString('pt-BR')} contato{x.contatos === 1 ? '' : 's'}</span>
      {podeEditar && <Button size="sm" variant="ghost" onClick={onClassificar}>Classificar</Button>}
    </li>
  );
}

function LinhaRegra({ x, podeEditar, onEditar, onAlternar }: {
  x: RegraCatalogo; podeEditar: boolean; onEditar: () => void; onAlternar: () => void;
}) {
  return (
    <li>
      <Card className={`flex flex-wrap items-start gap-x-4 gap-y-2 p-3 ${x.ativo ? '' : 'opacity-70'}`}>
        <div className="min-w-0 flex-1 basis-64 space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm text-[var(--fg)]">{fraseRegra(x)}</span>
            {x.tipo === 'mql' && <Badge tone="accent">MQL</Badge>}
            {!x.projeto && <Badge tone="neutral">sem projeto</Badge>}
            {!x.ativo && <Badge tone="neutral">Desativada</Badge>}
          </div>
          <div className="flex flex-wrap gap-x-3 text-xs text-[var(--fg-3)]">
            {x.projeto && <code>{x.projeto}</code>}
            <span className="tabular">prioridade {x.prioridade}</span>
            {x.contatos !== undefined && <span className="tabular">{x.contatos.toLocaleString('pt-BR')} contato{x.contatos === 1 ? '' : 's'}</span>}
          </div>
          {x.nota && <p className="text-xs leading-relaxed text-[var(--fg-3)]">{x.nota}</p>}
        </div>
        {podeEditar && (
          <div className="flex shrink-0 items-center gap-2">
            <Button size="sm" variant="ghost" onClick={onEditar} aria-label={`Editar regra ${x.padrao}`}><Icon name="pencil" size={14} /> Editar</Button>
            <Button size="sm" variant="ghost" onClick={onAlternar}>{x.ativo ? 'Desativar' : 'Reativar'}</Button>
          </div>
        )}
      </Card>
    </li>
  );
}

function ModalRegra({ inicial, projetos, listas, onFechar, onSalvo }: {
  inicial: Partial<RegraCatalogo>;
  projetos: PainelCatalogo['projetos'];
  listas: PainelCatalogo['listasAc'];
  onFechar: () => void;
  onSalvo: (msg: string) => Promise<void> | void;
}) {
  const [r, setR] = useState<RascunhoRegra>(() => rascunhoRegra(inicial));
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const mudar = (x: Partial<RascunhoRegra>) => { setR((v) => ({ ...v, ...x })); setErro(null); };
  const nomeLista = r.campo === 'ac_lista' ? listas.find((l) => l.id === r.padrao.trim())?.nome : undefined;

  async function salvar() {
    const v = validarRegra(r);
    if (!v.ok) { setErro(v.erro); return; }
    setSalvando(true);
    const res = await repo.salvarRegraCatalogo(v.regra);
    setSalvando(false);
    if (res.ok) await onSalvo(res.msg ?? 'Regra salva.');
    else setErro(res.msg ?? 'Não foi possível salvar.');
  }

  return (
    <Modal
      onClose={onFechar}
      title={r.id != null ? 'Editar regra de catalogação' : 'Nova regra de catalogação'}
      footer={(
        <>
          <Button size="sm" variant="ghost" onClick={onFechar} disabled={salvando}>Cancelar</Button>
          <Button size="sm" onClick={() => { void salvar(); }} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
        </>
      )}
    >
      <div className="space-y-4">
        <Campo rotulo="Tipo" dica={r.tipo === 'mql' ? 'A tag ou lista liga ao projeto E marca o contato como MQL (ex.: “PB MQL”; “PB NAO MQL” não).' : 'O valor liga o contato ao projeto.'}>
          <FilterSelect value={r.tipo} onChange={(e) => mudar({ tipo: e.target.value as TipoRegra, ...(e.target.value === 'mql' ? { semProjeto: false } : {}) })}>
            <option value="projeto">Projeto</option>
            <option value="mql">MQL do projeto</option>
          </FilterSelect>
        </Campo>
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Campo">
            <FilterSelect value={r.campo} onChange={(e) => mudar({ campo: e.target.value as CampoRegra })}>
              {ORDEM_CAMPOS.map((c) => <option key={c} value={c}>{ROTULO_CAMPO_REGRA[c]}</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Operador">
            <FilterSelect value={r.operador} onChange={(e) => mudar({ operador: e.target.value as OperadorRegra })}>
              {(Object.keys(ROTULO_OPERADOR) as OperadorRegra[]).map((o) => <option key={o} value={o}>{ROTULO_OPERADOR[o]}</option>)}
            </FilterSelect>
          </Campo>
        </div>
        <Campo rotulo="Valor" dica={nomeLista ? `Lista ${r.padrao.trim()}: ${nomeLista}` : DICA_CAMPO_REGRA[r.campo]}>
          <Input value={r.padrao} onChange={(e) => mudar({ padrao: e.target.value })} maxLength={200} autoFocus />
        </Campo>
        {r.tipo !== 'mql' && <Checkbox
          checked={r.semProjeto}
          onChange={(v) => mudar({ semProjeto: v })}
          label="Conhecido, sem projeto (lista ou funil geral do produto): tira das pendências sem inventar projeto"
        />}
        {(!r.semProjeto || r.tipo === 'mql') && (
          <Campo rotulo="Projeto (chave)" dica="Só projetos de gp-operacoes/projetos: a chave da pasta (= utm_campaign, ex.: cnhf-2026-08).">
            <Input list="catalogo-projetos" value={r.projeto} onChange={(e) => mudar({ projeto: e.target.value })} maxLength={80} />
            <datalist id="catalogo-projetos">
              {projetos.map((p) => <option key={p.chave} value={p.chave}>{nomeProjeto(p.chave, p.nome)}</option>)}
            </datalist>
          </Campo>
        )}
        <div className="grid gap-3 sm:grid-cols-3">
          <Campo rotulo="Vale de" dica="Opcional">
            <Input type="date" value={r.valeDe} onChange={(e) => mudar({ valeDe: e.target.value })} />
          </Campo>
          <Campo rotulo="Vale até" dica="Opcional">
            <Input type="date" value={r.valeAte} onChange={(e) => mudar({ valeAte: e.target.value })} />
          </Campo>
          <Campo rotulo="Prioridade" dica="Menor vence">
            <Input inputMode="numeric" value={r.prioridade} onChange={(e) => mudar({ prioridade: e.target.value.replace(/\D/g, '') })} maxLength={4} />
          </Campo>
        </div>
        <Campo rotulo="Nota">
          <Textarea value={r.nota} onChange={(e) => mudar({ nota: e.target.value })} maxLength={300} rows={2} />
        </Campo>
        {erro && <Aviso tom="danger" alerta>{erro}</Aviso>}
      </div>
    </Modal>
  );
}

function ListasAc({ listas, podeEditar, flash, onSalvo }: {
  listas: PainelCatalogo['listasAc']; podeEditar: boolean; flash: (m: string) => void; onSalvo: () => void;
}) {
  const [aberta, setAberta] = useState(false);
  const [id, setId] = useState('');
  const [nome, setNome] = useState('');
  const [salvando, setSalvando] = useState(false);
  async function salvar() {
    setSalvando(true);
    const res = await repo.salvarListaAc(id.trim(), nome.trim());
    setSalvando(false);
    flash(res.msg ?? (res.ok ? 'Lista salva.' : 'Não foi possível salvar.'));
    if (res.ok) { setId(''); setNome(''); onSalvo(); }
  }
  return (
    <section>
      <SectionTitle
        right={(
          <Button size="sm" variant="link" aria-expanded={aberta} onClick={() => setAberta((v) => !v)}>
            {aberta ? 'ocultar' : `ver (${listas.length})`}
          </Button>
        )}
      >
        Listas do ActiveCampaign
      </SectionTitle>
      <p className="text-xs text-[var(--fg-3)]">O webhook do AC manda só o número da lista. O nome daqui deixa a regra casar por nome.</p>
      {aberta && (
        <div className="mt-2 space-y-3">
          {podeEditar && (
            <div className="flex flex-wrap items-end gap-2">
              <Campo rotulo="Id" className="w-24"><Input inputMode="numeric" value={id} onChange={(e) => setId(e.target.value.replace(/\D/g, ''))} maxLength={10} /></Campo>
              <Campo rotulo="Nome" className="min-w-0 flex-1"><Input value={nome} onChange={(e) => setNome(e.target.value)} maxLength={200} /></Campo>
              <Button size="sm" disabled={salvando || !id || !nome.trim()} onClick={() => { void salvar(); }}>Salvar lista</Button>
            </div>
          )}
          <ul className="max-h-80 divide-y divide-[var(--border-faint)] overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)]">
            {listas.map((l) => (
              <li key={l.id} className="flex min-w-0 items-center gap-3 px-3 py-1.5 text-sm">
                <code className="w-12 shrink-0 tabular text-[var(--fg-3)]">{l.id}</code>
                <span className="min-w-0 truncate text-[var(--fg-2)]" title={l.nome}>{l.nome}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
    </section>
  );
}
