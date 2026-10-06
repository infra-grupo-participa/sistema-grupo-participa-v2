'use client';

// Na vida do projeto (migration 20261006a): o cadastro (tipo, unidade, lançamento, especialista, períodos, contas), as
// campanhas sugeridas pela conta e sigla, o pacote da campanha, o checklist de montagem e o gerador de nome de campanha e
// UTM. Leitura e gravação pelas funções public.trafego_* (admin/dev).
import { useEffect, useState } from 'react';
import { Badge, Button, CopyField, EmptyState, FilterSelect, Input, ProgressBar, Row } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { linhaUtm, montarNomeCampanha, type ListasCadastro, type ProjetoCadastro } from '../domain/cadastro';
import { ROTULO_TIPO, type Checklist, type ConfigTrafego, type Conta } from '../domain/tipos';
import { ajustarCampanha, aplicarPacote, carregarChecklist, marcarChecklist } from '../infrastructure/trafego-data';
import { SEM_DADO, dataBR } from './formato';

type Flash = (msg: string) => void;

const periodo = (a: string | null, b: string | null) => (a || b ? `${dataBR(a)} a ${dataBR(b)}` : SEM_DADO);

/** Resumo do cadastro, sugestões de campanha e o pacote. */
export function CadastroResumo({ cad, listas, contas, flash, onMudou }: {
  cad: ProjetoCadastro; listas: ListasCadastro; contas: Conta[]; flash: Flash; onMudou: () => void;
}) {
  const unidade = listas.unidades.find((u) => u.codigo === cad.unidade);
  const lanc = listas.tipos_lancamento.find((t) => t.codigo === cad.tipo_lancamento);
  const nomesContas = cad.contas.map((id) => contas.find((c) => c.id === id)?.nome ?? `conta ${id}`);

  async function ligar(id: number) {
    const r = await ajustarCampanha({ id, projeto_id: cad.id });
    flash(r.msg);
    if (r.ok) onMudou();
  }
  async function pacote() {
    const r = await aplicarPacote(cad.id);
    flash(r.msg);
    if (r.ok) onMudou();
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-x-6 sm:grid-cols-2">
        <Row k="Tipo e unidade" v={cad.tipo ? `${ROTULO_TIPO[cad.tipo]} · ${unidade?.nome ?? 'unidade não marcada'}` : 'Não marcado'} />
        <Row k="Tipo de lançamento" v={lanc?.nome ?? 'Não definido'} />
        <Row k="Especialista" v={cad.especialista_nome ?? 'Não definido'} />
        <Row k="Etiqueta do ClickUp" v={cad.etiqueta_clickup ? <span className="font-mono text-xs">{cad.etiqueta_clickup}</span> : 'Sem etiqueta'} />
        <Row k="Captação" v={periodo(cad.captacao_inicio, cad.captacao_fim)} />
        <Row k="Evento" v={periodo(cad.evento_inicio, cad.evento_fim)} />
        <Row k="Contas de anúncio" v={nomesContas.length ? nomesContas.join(', ') : 'Nenhuma ligada'} />
        <Row k="Pacote do tipo de lançamento" v={
          <span className="inline-flex items-center gap-2">
            {cad.pacote_fases ? `${cad.pacote_fases} fase(s) no modelo` : 'modelo vazio'}
            <Button size="sm" variant="subtle" onClick={() => void pacote()} disabled={!cad.tipo_lancamento}>Montar fases do pacote</Button>
          </span>} />
      </div>
      {cad.sugestoes.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">Campanhas sugeridas (conta do projeto, sigla no nome, sem projeto)</div>
          <ul className="mt-1 divide-y divide-[var(--border)]">
            {cad.sugestoes.map((s) => (
              <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-1.5">
                <span><span className="font-mono text-xs break-all">{s.nome}</span> <span className="text-xs text-[var(--fg-3)]">· {s.conta}</span></span>
                <Button size="sm" variant="subtle" onClick={() => void ligar(s.id)}>Ligar ao projeto</Button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/** O checklist em si (sem carregar), para testar a renderização. */
export function ChecklistVista({ c, onMarcar }: { c: Checklist | null; onMarcar?: (item: number, feito: boolean) => void }) {
  if (c === null) return <p className="text-sm text-[var(--fg-3)]">Indisponível (sem acesso, ou a migration 20261006a ainda não foi aplicada).</p>;
  const pct = c.total ? Math.round((c.feitos / c.total) * 1000) / 10 : 0;
  const linha = (ok: boolean, aplica: boolean) => (
    <span className={`inline-grid w-5 h-5 shrink-0 place-items-center rounded-full ${!aplica ? 'bg-[var(--surface-3)] text-[var(--fg-3)]' : ok ? 'bg-[var(--green)] text-black' : 'border border-[var(--border)] text-[var(--fg-3)]'}`}>
      {aplica && ok ? <Icon name="check" size={12} /> : null}
    </span>
  );
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-3">
        <div className="text-sm font-semibold text-[var(--fg)] tabular">{c.feitos} de {c.total} prontos</div>
        <div className="w-40"><ProgressBar value={pct} tone={c.feitos === c.total ? 'green' : 'accent'} ariaLabel={`${c.feitos} de ${c.total} itens prontos`} /></div>
      </div>
      <div className="grid gap-4 sm:grid-cols-2">
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">O sistema confere</div>
          <ul className="mt-1 space-y-1">
            {c.automaticos.map((i) => (
              <li key={i.codigo} className="flex items-start gap-2 text-sm">
                {linha(i.ok, i.aplica)}
                <span className={i.aplica ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}>
                  {i.texto}{!i.aplica ? ' (não se aplica)' : i.detalhe ? ` · ${i.detalhe}` : ''}
                </span>
              </li>
            ))}
          </ul>
        </div>
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">A pessoa marca quando fica pronto</div>
          {c.manuais.length === 0 ? <p className="mt-1 text-xs text-[var(--fg-3)]">Nenhum item manual para este tipo de lançamento.</p> : (
            <ul className="mt-1 space-y-1">
              {c.manuais.map((i) => (
                <li key={i.id} className="text-sm">
                  <label className="inline-flex items-start gap-2 cursor-pointer text-[var(--fg-2)]">
                    <input type="checkbox" className="mt-1" checked={i.ok} disabled={!onMarcar} onChange={(e) => onMarcar?.(i.id!, e.target.checked)} />
                    <span>{i.texto}</span>
                  </label>
                  {i.ok && <div className="pl-6 text-[11px] text-[var(--fg-3)]">Marcado por {i.marcado_por ?? 'sem nome'} em {dataBR(i.marcado_em ?? null)}</div>}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}

export function ChecklistPainel({ projetoId, versao, flash, onMudou }: { projetoId: number; versao: number; flash: Flash; onMudou: () => void }) {
  const [c, setC] = useState<Checklist | null | undefined>(undefined);
  const [n, setN] = useState(0);
  useEffect(() => {
    let vivo = true;
    carregarChecklist(projetoId).then((x) => { if (vivo) setC(x); });
    return () => { vivo = false; };
  }, [projetoId, versao, n]);
  if (c === undefined) return null;
  return <ChecklistVista c={c} onMarcar={async (item, feito) => {
    const r = await marcarChecklist(projetoId, item, feito);
    flash(r.msg);
    if (r.ok) { setN((x) => x + 1); onMudou(); }
  }} />;
}

/** Gerador do nome de campanha no padrão e da linha de UTM do Meta, com botão de copiar. */
export function GeradorCampanha({ sigla, listas, config, paginas, gestoresProjeto }: {
  sigla: string; listas: ListasCadastro; config: ConfigTrafego; paginas: { codigo: string; nome: string }[]; gestoresProjeto: string[];
}) {
  const [gestor, setGestor] = useState(gestoresProjeto[0] ?? '');
  const [objetivo, setObjetivo] = useState('');
  const [descricao, setDescricao] = useState('');
  const [pagina, setPagina] = useState('');
  const r = montarNomeCampanha({ gestor, sigla, objetivo, descricao, pagina },
    { gestores: config.gestores.map((g) => g.sigla), objetivos: listas.objetivos });
  const utm = listas.utm.meta ?? [];
  const pronto = gestor && objetivo && descricao.trim();

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-4">
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Gestor</span>
          <FilterSelect value={gestor} onChange={(e) => setGestor(e.target.value)}>
            <option value="">Escolha</option>
            {config.gestores.map((g) => <option key={g.sigla} value={g.sigla}>{g.sigla} · {g.nome}</option>)}
          </FilterSelect>
        </label>
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Objetivo</span>
          <FilterSelect value={objetivo} onChange={(e) => setObjetivo(e.target.value)}>
            <option value="">Escolha</option>
            {listas.objetivos.map((o) => <option key={o} value={o}>{o}</option>)}
          </FilterSelect>
        </label>
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Descrição <span className="font-normal text-[var(--fg-3)]">· livre; partes separadas por |</span></span>
          <Input value={descricao} onChange={(e) => setDescricao(e.target.value.toUpperCase())} maxLength={160} placeholder="TEASER | META | PQ | ABO" />
        </label>
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Página (só teste de página)</span>
          <FilterSelect value={pagina} onChange={(e) => setPagina(e.target.value)}>
            <option value="">Nenhuma</option>
            {paginas.map((p) => <option key={p.codigo} value={p.codigo}>{p.codigo.toUpperCase()} · {p.nome}</option>)}
          </FilterSelect>
        </label>
      </div>
      {pronto && r.erros.length > 0 && <p role="alert" className="text-sm text-[var(--red)]">{r.erros.join(' ')}</p>}
      {pronto && r.nome && <CopyField label="Nome da campanha" value={r.nome} />}
      {utm.length > 0 ? (
        <div>
          <CopyField label="Parâmetros de URL (Meta)" value={linhaUtm(utm)} />
          <p className="mt-1 text-xs text-[var(--fg-3)]">
            Colar no campo &quot;Parâmetros de URL&quot; do anúncio. O Meta troca as macros pelo nome e id da campanha, do conjunto e do anúncio e pelo
            posicionamento (padrão do gp-operacoes). O sistema cruza pelo id.
          </p>
        </div>
      ) : <EmptyState title="Sem parâmetros de UTM cadastrados" hint="mkt_trafego.utm_parametros (migration 20261006a)." />}
    </div>
  );
}

/** Progresso do checklist na tabela da Central. */
export function ProgressoMontagem({ feitos, total }: { feitos: number | null | undefined; total: number | null | undefined }) {
  if (feitos == null || !total) return <span className="text-xs text-[var(--fg-3)]">{SEM_DADO}</span>;
  return <Badge tone={feitos === total ? 'success' : 'neutral'}>{feitos}/{total}</Badge>;
}

