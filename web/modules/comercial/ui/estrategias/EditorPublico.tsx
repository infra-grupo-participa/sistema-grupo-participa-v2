'use client';

// Filtros estruturados do público (opcional no pedido; o gestor ajusta antes de transformar em ação).
// Sem tabela: blocos empilhados que quebram em coluna no celular.
import { Button, Checkbox, FilterSelect, Input, MultiSelect } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_BASE, type BasePublico, type FiltrosPublico, type OpcoesFiltro } from '../../domain/estrategias';
import { Campo, Chip } from '../comum';
import { comBloco, comRegra, textoDeTrechos, trechosDeTexto } from './editor';

const opc = (xs: string[]) => xs.map((x) => ({ value: x, label: x }));

export function EditorPublico({ valor, onChange, opcoes }: {
  valor: FiltrosPublico; onChange: (f: FiltrosPublico) => void; opcoes: OpcoesFiltro | null;
}) {
  const base = valor.base ?? 'alunos';
  const regras = valor.respondi?.regras ?? [];
  const linhas = (opcoes?.linhas ?? []).map((l) => ({ value: l.chave, label: `${l.nome} (escada ${l.escada})` }));
  const produtos = (opcoes?.produtos ?? []).map((p) => ({ value: p.id, label: p.nome }));
  const tipos = valor.alunos?.tiposTurma ?? [];
  const alternarTipo = (t: string) =>
    onChange(comBloco(valor, 'alunos', { ...valor.alunos, tiposTurma: tipos.includes(t) ? tipos.filter((x) => x !== t) : [...tipos, t] }));

  return (
    <div className="space-y-4">
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Base">
          <FilterSelect value={base} onChange={(e) => onChange({ ...valor, base: e.target.value as BasePublico })} className="w-full">
            {(Object.keys(ROTULO_BASE) as BasePublico[]).map((b) => <option key={b} value={b}>{ROTULO_BASE[b]}</option>)}
          </FilterSelect>
        </Campo>
        {/* Chips fora de <label>: clicar no rótulo não pode alternar o primeiro chip. */}
        <div role="group" aria-label="Tipo de turma" className="min-w-0">
          <span className="mb-1 block text-xs font-medium text-[var(--fg-2)]">Turma</span>
          <div className="flex flex-wrap gap-2">
            <Chip ativo={tipos.includes('thb')} onClick={() => alternarTipo('thb')}>Time Holding Brasil</Chip>
            <Chip ativo={tipos.includes('aurum')} onClick={() => alternarTipo('aurum')}>Aurum</Chip>
          </div>
        </div>
      </div>

      <fieldset className="space-y-3">
        <legend className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Alunos</legend>
        <div className="grid gap-3 sm:grid-cols-3">
          <Campo rotulo="Nível">
            <MultiSelect values={valor.alunos?.niveis ?? []} onChange={(v) => onChange(comBloco(valor, 'alunos', { ...valor.alunos, niveis: v }))}
              placeholder="Todos" options={opc(opcoes?.niveis ?? [])} className="w-full" />
          </Campo>
          <Campo rotulo="Turmas">
            <MultiSelect values={valor.alunos?.turmas ?? []} onChange={(v) => onChange(comBloco(valor, 'alunos', { ...valor.alunos, turmas: v }))}
              placeholder="Todas" options={opc((opcoes?.turmas ?? []).map((t) => t.codigo))} className="w-full" />
          </Campo>
          <Campo rotulo="Plano">
            <MultiSelect values={valor.alunos?.planos ?? []} onChange={(v) => onChange(comBloco(valor, 'alunos', { ...valor.alunos, planos: v }))}
              placeholder="Todos" options={opc(opcoes?.planos ?? [])} className="w-full" />
          </Campo>
        </div>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Compras (Hotmart)</legend>
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Comprou (produto)" dica="Base de compradores exige este filtro.">
            <MultiSelect values={valor.comprou?.produtos ?? []} onChange={(v) => onChange(comBloco(valor, 'comprou', { ...valor.comprou, produtos: v }))}
              placeholder="Qualquer" options={produtos} className="w-full" />
          </Campo>
          <Campo rotulo="Comprou (linha)">
            <MultiSelect values={valor.comprou?.linhas ?? []} onChange={(v) => onChange(comBloco(valor, 'comprou', { ...valor.comprou, linhas: v }))}
              placeholder="Qualquer" options={linhas} className="w-full" />
          </Campo>
          <Campo rotulo="Já comprou e sai (produto)">
            <MultiSelect values={valor.naoComprou?.produtos ?? []} onChange={(v) => onChange(comBloco(valor, 'naoComprou', { ...valor.naoComprou, produtos: v }))}
              placeholder="Nenhum" options={produtos} className="w-full" />
          </Campo>
          <Campo rotulo="Já comprou e sai (linha)">
            <MultiSelect values={valor.naoComprou?.linhas ?? []} onChange={(v) => onChange(comBloco(valor, 'naoComprou', { ...valor.naoComprou, linhas: v }))}
              placeholder="Nenhuma" options={linhas} className="w-full" />
          </Campo>
        </div>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Respostas de pesquisa</legend>
        <p className="text-xs text-[var(--fg-3)]">Entra quem respondeu uma das perguntas com uma resposta que contém um dos trechos. Várias regras somam (basta uma).</p>
        <datalist id="estrategia-perguntas">
          {(opcoes?.perguntas ?? []).map((p) => <option key={p.pergunta} value={p.pergunta} />)}
        </datalist>
        <ul className="space-y-2">
          {regras.map((r, i) => (
            <li key={i} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3">
              <div className="grid gap-2 sm:grid-cols-[1fr_1fr_auto] sm:items-end">
                <Campo rotulo="Pergunta (texto exato)" dica={r.perguntas.length > 1 ? `+ ${r.perguntas.length - 1} variação(ões) da pergunta` : undefined}>
                  <Input list="estrategia-perguntas" value={r.perguntas[0] ?? ''}
                    onChange={(e) => onChange(comRegra(valor, i, { ...r, perguntas: [e.target.value, ...r.perguntas.slice(1)] }))} />
                </Campo>
                <Campo rotulo="Resposta contém" dica="Separe por vírgula.">
                  <Input value={textoDeTrechos(r.contem)} onChange={(e) => onChange(comRegra(valor, i, { ...r, contem: trechosDeTexto(e.target.value) }))} />
                </Campo>
                <Button type="button" size="sm" variant="ghost" onClick={() => onChange(comRegra(valor, i, null))} aria-label={`Tirar a regra ${i + 1}`}>
                  <Icon name="trash" size={14} /> Tirar
                </Button>
              </div>
            </li>
          ))}
        </ul>
        <Button type="button" size="sm" variant="ghost" onClick={() => onChange(comRegra(valor, regras.length, { perguntas: [''], contem: [] }))}>
          <Icon name="plus" size={14} /> Regra de pesquisa
        </Button>
      </fieldset>

      <fieldset className="space-y-3">
        <legend className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Catalogação</legend>
        <div className="grid gap-3 sm:grid-cols-2">
          <Campo rotulo="Projeto">
            <MultiSelect values={valor.catalogacao?.projetos ?? []} onChange={(v) => onChange(comBloco(valor, 'catalogacao', { ...valor.catalogacao, projetos: v }))}
              placeholder="Qualquer" options={opc(opcoes?.projetos ?? [])} className="w-full" />
          </Campo>
          <Campo rotulo="Canal de entrada">
            <MultiSelect values={valor.catalogacao?.canais ?? []} onChange={(v) => onChange(comBloco(valor, 'catalogacao', { ...valor.catalogacao, canais: v }))}
              placeholder="Qualquer" options={opc(opcoes?.canais ?? [])} className="w-full" />
          </Campo>
        </div>
      </fieldset>

      <fieldset className="space-y-2">
        <legend className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Quem sai</legend>
        <p className="text-xs text-[var(--fg-3)]">Quem pediu para não receber contato sai sempre.</p>
        <div className="flex flex-col gap-2 sm:flex-row sm:gap-6">
          <Checkbox checked={valor.excluir?.emNegociacao !== false} label="Quem está em negociação aberta"
            onChange={(v) => onChange({ ...valor, excluir: { ...valor.excluir, emNegociacao: v } })} />
          <Checkbox checked={valor.excluir?.outraAcao !== false} label="Quem está em outra ação aberta"
            onChange={(v) => onChange({ ...valor, excluir: { ...valor.excluir, outraAcao: v } })} />
        </div>
      </fieldset>
    </div>
  );
}
