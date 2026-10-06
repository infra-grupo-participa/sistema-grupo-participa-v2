'use client';

// Concluir atividade e agendar o próximo passo, no mesmo fluxo (playbook, inegociável 4:
// nenhum negócio aberto sem próxima atividade com data). Usado na agenda e no Início.
import { useState } from 'react';
import { Button, FilterSelect, Input, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ICONE_ATIVIDADE, ROTULO_ATIVIDADE } from '../../domain/catalogo';
import type { Atividade, Negocio, TipoAtividade } from '../../domain/types';
import { avisarMudanca, repo } from '../repositorio';
import { RESULTADOS_RAPIDOS, amanhaAs10, sugestaoProximoPasso } from './agenda';

const TIPOS: TipoAtividade[] = ['ligacao', 'whatsapp', 'email', 'reuniao', 'tarefa'];

/** Chip selecionável (aria-pressed). Selecionado = surface-4 + fg + semibold. */
export function Chip({ ativo, onClick, children, title }: { ativo?: boolean; onClick: () => void; children: React.ReactNode; title?: string }) {
  return (
    <button
      type="button"
      aria-pressed={!!ativo}
      title={title}
      onClick={onClick}
      className={`inline-flex items-center gap-1.5 min-h-8 rounded-[var(--r-pill)] border px-3 text-xs transition-colors cursor-pointer ${
        ativo ? 'border-[var(--border-strong)] bg-[var(--surface-4)] text-[var(--fg)] font-semibold' : 'border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]'
      }`}
    >
      {children}
    </button>
  );
}

function Campo({ rotulo, children }: { rotulo: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block mb-1 text-xs font-medium text-[var(--fg-2)]">{rotulo}</span>
      {children}
    </label>
  );
}

/** Resultado de um toque: um clique num resultado rápido conclui; "Outro resultado…" abre o campo livre. */
export function ResultadosRapidos({ onEscolher, onCancelar }: {
  onEscolher: (resultado: string) => void; onCancelar?: () => void;
}) {
  const [livre, setLivre] = useState<string | null>(null);
  return (
    <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Resultado do toque">
      {livre === null ? (
        <>
          {RESULTADOS_RAPIDOS.map((r) => (
            <Chip key={r} onClick={() => onEscolher(r)} title={`Concluir como "${r}"`}>{r}</Chip>
          ))}
          <Button size="sm" variant="link" onClick={() => setLivre('')}>Outro resultado…</Button>
        </>
      ) : (
        <form
          className="flex flex-1 flex-wrap items-center gap-2 min-w-0"
          onSubmit={(e) => { e.preventDefault(); onEscolher(livre.trim()); }}
        >
          <Input
            autoFocus
            aria-label="Resultado do toque"
            placeholder="O que aconteceu (opcional)"
            value={livre}
            onChange={(e) => setLivre(e.target.value)}
            className="flex-1 min-w-[180px]"
          />
          <Button size="sm" variant="ghost" type="submit"><Icon name="check" size={14} /> Concluir</Button>
        </form>
      )}
      {onCancelar && <Button size="sm" variant="link" className="!text-[var(--fg-3)]" onClick={onCancelar}>Cancelar</Button>}
    </div>
  );
}

export interface OpcaoNegocio { id: string; contatoId: string; rotulo: string }

/**
 * Agendar atividade. Com `negocio` fixo é o "Agendar próximo passo" depois de concluir;
 * com `opcoes` é a "Nova atividade" da agenda (escolhe o negócio).
 */
export function ModalAgendar({ titulo, intro, inicial, negocio, opcoes, rotuloCancelar = 'Cancelar', onClose, onAgendado }: {
  titulo: string;
  intro?: React.ReactNode;
  inicial?: { tipo: TipoAtividade; titulo: string };
  negocio?: { id: string | null; contatoId: string };
  opcoes?: OpcaoNegocio[];
  rotuloCancelar?: string;
  onClose: () => void;
  onAgendado: (msg: string) => void;
}) {
  const [tipo, setTipo] = useState<TipoAtividade>(inicial?.tipo ?? 'ligacao');
  const [texto, setTexto] = useState(inicial?.titulo ?? '');
  const [quando, setQuando] = useState(() => amanhaAs10(new Date()));
  const [escolhido, setEscolhido] = useState('');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const alvo = negocio ?? (() => {
    const o = opcoes?.find((x) => x.id === escolhido);
    return o ? { id: o.id, contatoId: o.contatoId } : null;
  })();
  const valido = !!alvo && !!texto.trim() && !!quando;

  const agendar = async () => {
    if (!alvo || !valido) return;
    setSalvando(true);
    setErro(null);
    const r = await repo.criarAtividade({ negocioId: alvo.id, contatoId: alvo.contatoId, tipo, titulo: texto.trim(), venceEm: new Date(quando).toISOString() });
    setSalvando(false);
    if (!r.ok) { setErro(r.msg || 'Não foi possível agendar.'); return; }
    avisarMudanca();
    onAgendado(r.msg || 'Atividade agendada.');
  };

  return (
    <Modal
      onClose={onClose}
      title={titulo}
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>{rotuloCancelar}</Button>
        <Button size="sm" disabled={!valido || salvando} onClick={agendar}>Agendar</Button>
      </>}
    >
      <div className="space-y-4">
        {intro && <p className="text-sm text-[var(--fg-2)]">{intro}</p>}
        {opcoes && (
          <Campo rotulo="Negócio">
            <FilterSelect value={escolhido} onChange={(e) => setEscolhido(e.target.value)} className="w-full">
              <option value="">Escolha o negócio…</option>
              {opcoes.map((o) => <option key={o.id} value={o.id}>{o.rotulo}</option>)}
            </FilterSelect>
          </Campo>
        )}
        <div>
          <span className="block mb-1 text-xs font-medium text-[var(--fg-2)]" id="tipo-atividade">Tipo</span>
          <div className="flex flex-wrap gap-2" role="group" aria-labelledby="tipo-atividade">
            {TIPOS.map((t) => (
              <Chip key={t} ativo={tipo === t} onClick={() => setTipo(t)}>
                <Icon name={ICONE_ATIVIDADE[t]} size={13} /> {ROTULO_ATIVIDADE[t]}
              </Chip>
            ))}
          </div>
        </div>
        <Campo rotulo="O que fazer">
          <Input placeholder="Ex.: Ligar para apresentar a oferta" value={texto} onChange={(e) => setTexto(e.target.value)} />
        </Campo>
        <Campo rotulo="Quando">
          <Input type="datetime-local" value={quando} onChange={(e) => setQuando(e.target.value)} />
        </Campo>
        {erro && <p role="alert" className="text-xs text-[var(--red)]">{erro}</p>}
      </div>
    </Modal>
  );
}

/**
 * Fluxo "concluir e agendar próximo": conclui na hora e, se o negócio segue aberto, abre o
 * "Agendar próximo passo" já preenchido (toque seguinte da cadência, amanhã 10h).
 * `pedirResultado` abre um modal com os resultados rápidos (para listas sem espaço inline, como o Início).
 */
export function useConcluirComProximo(
  flash: (msg: string) => void,
  /** Por que o negócio é só leitura para quem está logado (`motivoSomenteLeitura`). Texto = não oferece o próximo passo. */
  leituraDe?: (n: Negocio) => string | null,
) {
  const [proximo, setProximo] = useState<{ a: Atividade; resultado: string; negocioId: string | null } | null>(null);
  const [pedindo, setPedindo] = useState<{ a: Atividade; negocio?: Negocio } | null>(null);

  const concluir = async (a: Atividade, resultado: string, negocio?: Negocio) => {
    const r = await repo.concluirAtividade(a.id, resultado);
    if (!r.ok) { flash(r.msg || 'Não foi possível concluir.'); return false; }
    avisarMudanca();
    // Negócio encerrado não pede próximo passo. Negócio alheio (ou sem dono) também não: o banco recusaria
    // "Este negócio não é seu." no crm_criar_atividade; quem agenda é o dono ou o gestor.
    const leitura = negocio ? leituraDe?.(negocio) ?? null : null;
    if (negocio && negocio.status !== 'aberto') flash(r.msg || 'Atividade concluída.');
    else if (leitura) flash(`Atividade concluída. ${leitura}`);
    else setProximo({ a, resultado, negocioId: negocio?.id ?? a.negocioId });
    return true;
  };

  const sugestao = proximo ? sugestaoProximoPasso(proximo.a, proximo.resultado) : null;

  const modais = (
    <>
      {pedindo && (
        <Modal onClose={() => setPedindo(null)} title="Concluir atividade">
          <p className="mb-3 text-sm text-[var(--fg-2)]">
            <span className="font-medium text-[var(--fg)]">{pedindo.a.titulo}</span>. Como foi?
          </p>
          <ResultadosRapidos
            onEscolher={async (res) => { const p = pedindo; setPedindo(null); await concluir(p.a, res, p.negocio); }}
          />
        </Modal>
      )}
      {proximo && sugestao && (
        <ModalAgendar
          key={proximo.a.id}
          titulo="Agendar próximo passo"
          intro={<>Atividade concluída{proximo.resultado ? <> como <strong className="text-[var(--fg)]">{proximo.resultado}</strong></> : null}. Negócio aberto precisa de próxima atividade com data.</>}
          inicial={{ tipo: sugestao.tipo, titulo: sugestao.titulo }}
          negocio={{ id: proximo.negocioId, contatoId: proximo.a.contatoId }}
          rotuloCancelar="Agora não"
          onClose={() => { setProximo(null); flash('Atividade concluída. Lembre de agendar o próximo passo.'); }}
          onAgendado={() => { setProximo(null); flash('Atividade concluída e próximo passo agendado.'); }}
        />
      )}
    </>
  );

  return {
    concluir,
    pedirResultado: (a: Atividade, negocio?: Negocio) => setPedindo({ a, negocio }),
    modais,
  };
}
