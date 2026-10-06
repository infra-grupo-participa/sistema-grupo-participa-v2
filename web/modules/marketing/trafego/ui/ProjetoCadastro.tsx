'use client';

// Criar/editar o projeto (evento) na Central do Tráfego (migration 20261006a): sigla, nome, linha, tipo e unidade, tipo de
// lançamento (só os da unidade; Aurum fica em palestra sozinho), especialista, períodos de captação e do evento, etiqueta
// do ClickUp (a chave única), status, gestores e contas de anúncio. Mora no Tráfego porque os campos são de Tráfego e o
// cadastro grava na tabela de projetos única (mkt.projetos), que a Web e a Mensageria também leem.
import { useState } from 'react';
import { Button, FilterSelect, Input, Modal, Toggle } from '@/shared/ui/components';
import {
  ROTULO_AVISO_CADASTRO, ajustarForm, etiquetaSemAnoMes, lancamentoAutomatico, lancamentosDaUnidade, unidadesDoTipo, validarCadastro,
  type ListasCadastro, type ProjetoForm,
} from '../domain/cadastro';
import { ROTULO_TIPO, type ConfigTrafego, type Conta, type Tipo } from '../domain/tipos';
import { salvarProjetoCadastro } from '../infrastructure/trafego-data';

function Campo({ rotulo, dica, children }: { rotulo: string; dica?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">
        {rotulo}{dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}
      </span>
      {children}
    </label>
  );
}

function Grupo({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <fieldset className="sm:col-span-2 rounded-[var(--r-md)] border border-[var(--border)] p-3">
      <legend className="px-1 text-xs font-semibold text-[var(--fg-2)]">{titulo}</legend>
      <div className="grid gap-3 sm:grid-cols-2">{children}</div>
    </fieldset>
  );
}

export function ModalProjetoCadastro({ inicial, listas, config, contas, onFechar, onSalvo }: {
  inicial: ProjetoForm; listas: ListasCadastro; config: ConfigTrafego; contas: Conta[];
  onFechar: () => void; onSalvo: (msg: string) => void;
}) {
  const [f, setF] = useState<ProjetoForm>(() => ajustarForm(listas, inicial));
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof ProjetoForm>(k: K, v: ProjetoForm[K]) => setF((x) => ajustarForm(listas, { ...x, [k]: v }));
  const alterna = (k: 'gestores' | 'contas', v: string | number) => setF((x) => {
    const lista = x[k] as (string | number)[];
    return { ...x, [k]: lista.includes(v) ? lista.filter((y) => y !== v) : [...lista, v] };
  });

  const unidades = unidadesDoTipo(listas, f.tipo);
  const lancamentos = lancamentosDaUnidade(listas, f.unidade);
  const automatico = lancamentoAutomatico(listas, f.unidade);
  const especialistas = listas.especialistas.filter((e) => e.tipo === f.tipo);
  const etiquetas = listas.etiquetas_clickup;
  const avisoEtq = etiquetaSemAnoMes(f.etiqueta_clickup, f.captacao_fim || f.evento_fim || f.fim);
  const datasAntigas = !f.captacao_inicio && !f.evento_inicio && (f.inicio || f.fim);

  async function salvar() {
    const e = validarCadastro(listas, f);
    if (e) { setErro(e); return; }
    setSalvando(true);
    const r = await salvarProjetoCadastro(f);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    const extra = [
      ...(r.avisos ?? []).map((a) => ROTULO_AVISO_CADASTRO[a] ?? a),
      ...(r.campanhas_relidas ? [`${r.campanhas_relidas} campanha(s) religada(s) pela sigla.`] : []),
    ];
    onSalvo([r.msg, ...extra].join(' '));
  }

  return (
    <Modal onClose={onFechar} title={f.id ? `Editar projeto ${inicial.sigla}` : 'Novo projeto (evento)'} width="max-w-3xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
    </>}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Sigla" dica="a do nome de campanha; única (ex.: PB26)">
          <Input value={f.sigla} onChange={(e) => set('sigla', e.target.value.toUpperCase())} maxLength={14} autoFocus={!f.id} />
        </Campo>
        <Campo rotulo="Nome" dica="livre (ex.: Seminário Conjunto)">
          <Input value={f.nome} onChange={(e) => set('nome', e.target.value)} maxLength={120} />
        </Campo>
        <Campo rotulo="Linha" dica="ex.: Patrimônio Brasil, Holding Total">
          <Input value={f.linha} onChange={(e) => set('linha', e.target.value)} maxLength={60} />
        </Campo>
        <Campo rotulo="Status" dica="marcado à mão">
          <FilterSelect value={f.status} onChange={(e) => set('status', e.target.value)}>
            <option value="">Sem status</option>
            {config.status.map((s) => <option key={s.codigo} value={s.codigo}>{s.nome}</option>)}
          </FilterSelect>
        </Campo>

        <Grupo titulo="Tipo, unidade e lançamento">
          <Campo rotulo="Tipo">
            <FilterSelect value={f.tipo} onChange={(e) => set('tipo', e.target.value as '' | Tipo)}>
              <option value="">Escolha</option>
              {(Object.keys(ROTULO_TIPO) as Tipo[]).map((t) => <option key={t} value={t}>{ROTULO_TIPO[t]}</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Unidade" dica={f.tipo === 'interno' ? 'CSM ou Escritório' : f.tipo === 'externo' ? 'Aurum ou Diamantes' : 'escolha o tipo antes'}>
            <FilterSelect value={f.unidade} onChange={(e) => set('unidade', e.target.value)} disabled={!f.tipo}>
              <option value="">Escolha</option>
              {unidades.map((u) => <option key={u.codigo} value={u.codigo} title={u.descricao ?? ''}>{u.nome}{u.descricao ? ` (${u.descricao})` : ''}</option>)}
            </FilterSelect>
          </Campo>
          <Campo rotulo="Tipo de lançamento" dica={automatico ? 'fixo para esta unidade' : 'só os que valem para a unidade'}>
            {automatico ? (
              <div className="py-2 text-sm text-[var(--fg)]">{lancamentos[0]?.nome}</div>
            ) : (
              <FilterSelect value={f.tipo_lancamento} onChange={(e) => set('tipo_lancamento', e.target.value)} disabled={!f.unidade}>
                <option value="">Não definido</option>
                {lancamentos.map((t) => <option key={t.codigo} value={t.codigo}>{t.nome}</option>)}
              </FilterSelect>
            )}
          </Campo>
          <Campo rotulo="Especialista" dica={f.tipo === 'externo' ? 'a pessoa/cliente; escolha ou digite um nome novo' : 'da lista'}>
            <FilterSelect value={f.especialista_id ?? ''} disabled={!f.tipo}
              onChange={(e) => set('especialista_id', e.target.value ? Number(e.target.value) : null)}>
              <option value="">{f.tipo === 'externo' ? 'Nenhum ou novo (abaixo)' : 'Nenhum'}</option>
              {especialistas.map((x) => <option key={x.id} value={x.id}>{x.nome}</option>)}
            </FilterSelect>
            {f.tipo === 'externo' && f.especialista_id == null && (
              <Input className="mt-2" value={f.especialista_nome} onChange={(e) => set('especialista_nome', e.target.value)} maxLength={120}
                placeholder="Nome do especialista novo (cadastrado ao salvar)" aria-label="Nome do especialista novo" />
            )}
          </Campo>
        </Grupo>

        <Grupo titulo="Períodos">
          <Campo rotulo="Captação: início"><Input type="date" value={f.captacao_inicio} onChange={(e) => set('captacao_inicio', e.target.value)} /></Campo>
          <Campo rotulo="Captação: fim"><Input type="date" value={f.captacao_fim} onChange={(e) => set('captacao_fim', e.target.value)} /></Campo>
          <Campo rotulo="Evento: início"><Input type="date" value={f.evento_inicio} onChange={(e) => set('evento_inicio', e.target.value)} /></Campo>
          <Campo rotulo="Evento: fim"><Input type="date" value={f.evento_fim} onChange={(e) => set('evento_fim', e.target.value)} /></Campo>
          <p className="sm:col-span-2 text-xs text-[var(--fg-3)]">
            A captação é o padrão da fase de captação e da receita quando o produto da Hotmart não tem período próprio.
            {datasAntigas ? ` Datas de antes (sem separação): ${f.inicio || '?'} a ${f.fim || '?'}; ficam até preencher os períodos.` : ''}
          </p>
        </Grupo>

        <Campo rotulo="Etiqueta do ClickUp" dica="a chave do projeto, exata (ex.: black-friday-2026-10)">
          {etiquetas.length > 0 ? (
            <FilterSelect value={f.etiqueta_clickup} onChange={(e) => set('etiqueta_clickup', e.target.value)}>
              <option value="">Sem etiqueta</option>
              {f.etiqueta_clickup && !etiquetas.includes(f.etiqueta_clickup) && <option value={f.etiqueta_clickup}>{f.etiqueta_clickup} (não está no ClickUp)</option>}
              {etiquetas.map((x) => <option key={x} value={x}>{x}</option>)}
            </FilterSelect>
          ) : (
            <Input value={f.etiqueta_clickup} onChange={(e) => set('etiqueta_clickup', e.target.value.toLowerCase())} maxLength={80} placeholder="nome-curto-aaaa-mm" />
          )}
          {avisoEtq && <span className="mt-1 block text-[11px] text-[var(--yellow)]">{ROTULO_AVISO_CADASTRO.etiqueta_sem_ano_mes}</span>}
        </Campo>
        <div className="flex items-end"><Toggle checked={f.ativo} onChange={(v) => set('ativo', v)} label="Projeto ativo" /></div>

        <fieldset>
          <legend className="block text-xs font-medium text-[var(--fg-2)] mb-1">Gestores <span className="font-normal text-[var(--fg-3)]"> · um ou mais; qualquer um opera interno ou externo</span></legend>
          <div className="flex flex-wrap gap-3 pt-1">
            {config.gestores.map((g) => (
              <label key={g.sigla} className="inline-flex items-center gap-1.5 text-sm text-[var(--fg-2)] cursor-pointer">
                <input type="checkbox" checked={f.gestores.includes(g.sigla)} onChange={() => alterna('gestores', g.sigla)} />
                <span title={g.nome}>{g.sigla}</span>
              </label>
            ))}
          </div>
        </fieldset>
        <fieldset>
          <legend className="block text-xs font-medium text-[var(--fg-2)] mb-1">Contas de anúncio do projeto</legend>
          {contas.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Nenhuma conta cadastrada (aba Contas de anúncio).</p> : (
            <div className="flex flex-col gap-1 pt-1">
              {contas.filter((c) => c.ativa || f.contas.includes(c.id)).map((c) => (
                <label key={c.id} className="inline-flex items-center gap-1.5 text-sm text-[var(--fg-2)] cursor-pointer">
                  <input type="checkbox" checked={f.contas.includes(c.id)} onChange={() => alterna('contas', c.id)} />
                  <span>{c.nome} <span className="text-[var(--fg-3)]">({c.plataforma === 'meta' ? 'Meta' : c.plataforma === 'google' ? 'Google' : c.plataforma})</span></span>
                </label>
              ))}
            </div>
          )}
        </fieldset>
      </div>
      <p className="mt-3 text-xs text-[var(--fg-3)]">As contas sugerem campanhas com a sigla e avisam no resumo do dia quando a sigla roda em conta de fora.</p>
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}
