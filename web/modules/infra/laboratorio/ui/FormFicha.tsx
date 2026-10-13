'use client';

// Ficha por nível (seções 4, 5, 6.2 e 6A). Usada no assistente (novo) e na ficha (editar).
// Depois do "no ar", régua, métrica, tipo, variável e sorteio ficam travados: mudar pede motivo e reinicia o relógio.
import { Card, FilterSelect, Input, Textarea } from '@/shared/ui/components';
import type { Resultado } from '../domain/estatistica';
import { ROTULO_RESULTADO } from '../domain/estatistica';
import { AREAS, type Experimento, type Nivel, type Pessoa } from '../domain/types';
import { PainelAmostra, Rotulo, num } from './Calculadora';

export type Rascunho = Partial<Experimento> & { motivo_mudanca?: string };

function Campo({ rotulo, dica, children, largo }: { rotulo: string; dica?: string; children: React.ReactNode; largo?: boolean }) {
  return <label className={`block space-y-1 ${largo ? 'sm:col-span-2' : ''}`}><Rotulo dica={dica}>{rotulo}</Rotulo>{children}</label>;
}

export function FormFicha({ valor, onChange, nivel, equipe, travado, somenteLeitura }: {
  valor: Rascunho;
  onChange: (v: Rascunho) => void;
  nivel: Nivel;
  equipe: Pessoa[];
  /** Status fora do rascunho: os campos que definem o teste pedem motivo para mudar. */
  travado: boolean;
  somenteLeitura?: boolean;
}) {
  const set = <K extends keyof Rascunho>(k: K, v: Rascunho[K]) => onChange({ ...valor, [k]: v });
  const txt = (k: keyof Rascunho, linhas = 2) => (
    <Textarea rows={linhas} disabled={somenteLeitura} value={(valor[k] as string | null) ?? ''} onChange={(e) => set(k, e.target.value as never)} />
  );
  const linha = (k: keyof Rascunho, placeholder?: string) => (
    <Input disabled={somenteLeitura} placeholder={placeholder} value={(valor[k] as string | null) ?? ''} onChange={(e) => set(k, e.target.value as never)} />
  );
  const data = (k: 'inicio' | 'leitura_em' | 'revisao_em') => (
    <Input type="date" disabled={somenteLeitura} value={valor[k] ?? ''} onChange={(e) => set(k, e.target.value || null)} />
  );
  const pessoa = (k: 'monta_id' | 'confere_id' | 'le_id') => (
    <FilterSelect disabled={somenteLeitura} value={valor[k] ?? ''} onChange={(e) => set(k, e.target.value || null)}>
      <option value="">—</option>
      {equipe.map((p) => <option key={p.id} value={p.id}>{p.nome}</option>)}
    </FilterSelect>
  );
  const pr = valor.perguntas_regua ?? {};
  const dc = valor.decisao_combinada ?? {};
  const reguaPct = valor.regua != null ? String(Math.round(valor.regua * 1000) / 10).replace('.', ',') : '';
  const taxaPct = valor.taxa_base != null ? String(Math.round(valor.taxa_base * 10000) / 100).replace('.', ',') : '';

  return (
    <div className="space-y-5">
      <Card className="grid gap-4 p-4 sm:grid-cols-2">
        <Campo rotulo="Nome" dica={nivel === 3 ? 'A x B, em poucas palavras' : undefined} largo>{linha('titulo')}</Campo>
        <Campo rotulo="Área">
          <FilterSelect disabled={somenteLeitura} value={valor.area ?? 'outro'} onChange={(e) => set('area', e.target.value as Rascunho['area'])}>
            {AREAS.map((a) => <option key={a.k} value={a.k}>{a.l}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Link da tarefa no ClickUp" dica="Opcional">{linha('clickup', 'https://app.clickup.com/…')}</Campo>
      </Card>

      {nivel === 1 && (
        <Card className="grid gap-4 p-4 sm:grid-cols-2">
          <Campo rotulo="Decisão" dica="O que vamos fazer" largo>{txt('decisao')}</Campo>
          <Campo rotulo="Por quê" dica="A hipótese, em uma frase" largo>{txt('hipotese')}</Campo>
          <Campo rotulo="Previsão com número" dica="O que esperamos ver, e até quando" largo>{txt('previsao')}</Campo>
          <Campo rotulo="Data de revisão" dica="Quando vamos conferir">{data('revisao_em')}</Campo>
        </Card>
      )}

      {nivel >= 2 && (
        <Card className="grid gap-4 p-4 sm:grid-cols-2">
          <Campo rotulo="Hipótese" dica={'Com número. "Vai melhorar" não é hipótese: não dá para saber se errou.'} largo>{txt('hipotese')}</Campo>
          {nivel === 2 && <>
            <Campo rotulo="Grupo piloto" dica="Quem faz a mudança">{txt('grupo_piloto')}</Campo>
            <Campo rotulo="Grupo de comparação" dica="Quem continua como está. Por que é parecido com o piloto?">{txt('grupo_comparacao')}</Campo>
            <Campo rotulo="Medição antes" dica="Os números dos dois grupos antes da mudança" largo>{txt('medicao_antes')}</Campo>
            <Campo rotulo="Confundidores" dica="O que mais pode explicar o resultado" largo>{txt('confundidores')}</Campo>
          </>}
          {nivel === 3 && <>
            <Campo rotulo="Variável única" dica="A única coisa que muda">{txt('variavel')}</Campo>
            <Campo rotulo="O que NÃO muda" dica="Liste o resto, para ninguém mexer">{txt('nao_muda')}</Campo>
            <Campo rotulo="Como sortear" dica="Como cada caso cai em A ou em B" largo>{txt('sorteio')}</Campo>
          </>}
          <Campo rotulo="Métrica de decisão" dica="Uma só, a mais próxima do resultado que importa">{linha('metrica_decisao')}</Campo>
          <Campo rotulo="Métricas de diagnóstico" dica="As que ajudam a explicar o porquê">{linha('metricas_diagnostico')}</Campo>
          <Campo rotulo="Início">{data('inicio')}</Campo>
          <Campo rotulo="Data de leitura" dica="Data fixa. Olhe todo dia, decida só nela">{data('leitura_em')}</Campo>
          {nivel === 3 && <Campo rotulo="Alarme" dica="Quando paramos antes: dano claro ou medição quebrada" largo>{txt('alarme')}</Campo>}
        </Card>
      )}

      {nivel === 3 && (
        <Card className="space-y-4 p-4">
          <div>
            <h4 className="text-sm font-semibold text-[var(--fg)]">A régua: menor diferença que importa (6A)</h4>
            <p className="text-xs text-[var(--fg-3)]">Não é previsão: é a sensibilidade do teste. Responda as quatro perguntas, escolha antes de ligar e não mude depois.</p>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            {([['vale', '1. Quanto vale a pena?', 'Qual a menor melhora que justifica o trabalho de mudar?'],
               ['dados', '2. O que os nossos dados já mostram?', 'Quanto essa métrica já varia entre as opções de hoje?'],
               ['conta', '3. Faz sentido na conta?', 'De trás para frente: o número exigido já foi visto?'],
               ['alavanca', '4. Qual o tamanho da alavanca?', 'Quem recebe > o que dizemos > formato > gancho > execução']] as const).map(([k, l, d]) => (
              <Campo key={k} rotulo={l} dica={d}>
                <Textarea rows={2} disabled={somenteLeitura} value={pr[k] ?? ''} onChange={(e) => set('perguntas_regua', { ...pr, [k]: e.target.value })} />
              </Campo>
            ))}
          </div>
          <div className="grid gap-4 sm:grid-cols-3">
            <Campo rotulo="Tipo de métrica">
              <FilterSelect disabled={somenteLeitura} value={valor.metrica_tipo ?? ''} onChange={(e) => set('metrica_tipo', (e.target.value || null) as Rascunho['metrica_tipo'])}>
                <option value="">—</option><option value="taxa">Taxa (conversão, resposta, presença)</option><option value="custo">Custo (por lead, MQL, venda)</option>
              </FilterSelect>
            </Campo>
            {valor.metrica_tipo === 'taxa' && (
              <Campo rotulo="Taxa de hoje (%)">
                <Input inputMode="decimal" disabled={somenteLeitura} defaultValue={taxaPct} onBlur={(e) => { const v = num(e.target.value); set('taxa_base', Number.isFinite(v) && v > 0 ? v / 100 : null); }} />
              </Campo>
            )}
            <Campo rotulo="Menor diferença que importa (%)">
              <Input inputMode="decimal" disabled={somenteLeitura} defaultValue={reguaPct} onBlur={(e) => { const v = num(e.target.value); set('regua', Number.isFinite(v) && v > 0 ? v / 100 : null); }} />
            </Campo>
          </div>
          {valor.metrica_tipo && <PainelAmostra tipo={valor.metrica_tipo} taxaBase={valor.taxa_base ?? null} regua={valor.regua ?? null} />}
          <Campo rotulo="Amostra mínima por grupo" dica="Use o número acima (ou o que a sua conta mostrar)">
            <Input inputMode="numeric" disabled={somenteLeitura} value={valor.amostra_minima ?? ''} onChange={(e) => { const v = num(e.target.value); set('amostra_minima', Number.isFinite(v) && v > 0 ? Math.round(v) : null); }} />
          </Campo>
        </Card>
      )}

      {nivel >= 2 && (
        <Card className="space-y-4 p-4">
          <div>
            <h4 className="text-sm font-semibold text-[var(--fg)]">Decisão combinada</h4>
            <p className="text-xs text-[var(--fg-3)]">Antes de ligar: o que fazemos em cada resultado.</p>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            {(['vencedor', 'provavel', 'empate', 'inconclusivo'] as Resultado[]).map((r) => (
              <Campo key={r} rotulo={ROTULO_RESULTADO[r]}>
                <Textarea rows={2} disabled={somenteLeitura} value={dc[r] ?? ''} onChange={(e) => set('decisao_combinada', { ...dc, [r]: e.target.value })} />
              </Campo>
            ))}
          </div>
        </Card>
      )}

      <Card className="grid gap-4 p-4 sm:grid-cols-3">
        <Campo rotulo="Quem monta">{pessoa('monta_id')}</Campo>
        <Campo rotulo="Quem confere">{pessoa('confere_id')}</Campo>
        <Campo rotulo="Quem lê">{pessoa('le_id')}</Campo>
      </Card>

      {travado && !somenteLeitura && (
        <Card className="space-y-2 border-[var(--yellow-border)] p-4">
          <Rotulo dica="Só se mudou régua, métrica, tipo de métrica, variável ou sorteio. Mudar no meio reinicia o relógio (início = hoje).">Motivo da mudança</Rotulo>
          <Textarea rows={2} value={valor.motivo_mudanca ?? ''} onChange={(e) => set('motivo_mudanca', e.target.value)} />
        </Card>
      )}
    </div>
  );
}

/** O que vai para lab_salvar: só as colunas da ficha. */
export function paraSalvar(v: Rascunho): Record<string, unknown> {
  const campos = ['id', 'area', 'nivel', 'titulo', 'decisao', 'hipotese', 'previsao', 'variavel', 'nao_muda', 'sorteio', 'metrica_tipo', 'metrica_decisao',
    'metricas_diagnostico', 'taxa_base', 'regua', 'perguntas_regua', 'amostra_minima', 'grupo_piloto', 'grupo_comparacao', 'medicao_antes', 'confundidores',
    'alarme', 'decisao_combinada', 'controle_a', 'controle_b', 'inicio', 'leitura_em', 'revisao_em', 'clickup', 'monta_id', 'confere_id', 'le_id', 'motivo_mudanca'] as const;
  const out: Record<string, unknown> = {};
  for (const k of campos) {
    if (!(k in v)) continue;
    const x = (v as Record<string, unknown>)[k];
    out[k] = typeof x === 'string' ? x.trim() : x ?? null;
  }
  return out;
}
