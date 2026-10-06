'use client';

// Novo negócio: escolhe o contato (se ainda não veio), o funil e a campanha de entrada.
// Usado pelo Funil e pela ficha do contato. Quem vira dono é a distribuição (do funil ou a geral).
// Na busca, telefone e dono à vista: é assim que o vendedor separa homônimos e vê que "tem dono, não é seu".
import { useEffect, useMemo, useState } from 'react';
import { Button, FilterSelect, Modal, SearchInput } from '@/shared/ui/components';
import { fmtTelefone } from '../domain/regras';
import type { Agrupador, Contato, Funil, Negocio } from '../domain/types';
import { Aviso, Campo, NotaRodape, Pessoa, Sinal, useEquipe } from './comum';
import { repo, useDados } from './repositorio';

const MAX_RESULTADOS = 8;

export function ModalNovoNegocio({ contatoFixo, contatos, funilInicial, onClose, onCriado }: {
  /** Contato já escolhido (ficha do contato). Sem ele, o modal pede a busca. */
  contatoFixo?: Contato;
  /** Base para a busca. Sem ela, a busca vai ao servidor (a partir de 3 letras), sem baixar a lista inteira. */
  contatos?: Contato[];
  funilInicial?: string;
  onClose: () => void;
  onCriado: (r: { negocioId: string; donoId: string | null }) => void;
}) {
  const { dados: funis } = useDados(() => repo.funis());
  const { dados: agrupadores } = useDados(() => repo.agrupadores());
  const { nomeDe } = useEquipe();
  const [busca, setBusca] = useState('');
  const [contatoId, setContatoId] = useState<string | null>(contatoFixo?.id ?? null);
  // Busca no servidor (sem lista inteira na tela): 400 ms depois da última tecla, a partir de 3 letras.
  const [termoServidor, setTermoServidor] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setTermoServidor(busca.trim()), 400);
    return () => clearTimeout(t);
  }, [busca]);
  const { dados: achados } = useDados(
    async () => (contatos || contatoFixo || termoServidor.length < 3 ? [] as Contato[] : repo.buscarContatos(termoServidor)),
    [termoServidor],
  );
  const [funilId, setFunilId] = useState<string>(funilInicial ?? '');
  const [campanhaId, setCampanhaId] = useState<string>('');
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);

  // Só funis manuais: os automáticos nascem dos eventos da Hotmart.
  const manuais = useMemo(() => (funis ?? []).filter((f) => f.tipo === 'manual'), [funis]);
  const funil = manuais.find((f) => f.id === funilId) ?? null;
  const base = contatos ?? achados ?? [];
  const contato = contatoFixo ?? base.find((c) => c.id === contatoId) ?? null;
  // Negócios só da pessoa escolhida (filtro no banco), para marcar o funil em que ela já tem negócio aberto.
  const { dados: negocios } = useDados(
    async () => (contato ? repo.negocios({ contatoId: contato.id, status: 'aberto' }) : [] as Negocio[]),
    [contato?.id ?? null],
  );
  const jaTem = (f: Funil) => (negocios ?? []).some((n: Negocio) => n.contatoId === contato?.id && n.funilId === f.id && n.status === 'aberto');

  // Busca também pelo telefone só com dígitos ("11 9…" acha "+55 11 9…").
  const termo = busca.trim().toLowerCase();
  const digitos = termo.replace(/\D/g, '');
  // Achados do servidor já casaram a busca (e-mail/telefone podem vir mascarados): só a base local é filtrada aqui.
  const filtrados = !contatos ? base : base.filter((c) =>
    `${c.nome} ${c.email ?? ''} ${c.telefone ?? ''}`.toLowerCase().includes(termo)
    || (digitos.length >= 4 && (c.telefone ?? '').replace(/\D/g, '').includes(digitos)));
  const lista = filtrados.slice(0, MAX_RESULTADOS);

  const podeCriar = !!contato && !!funil && !salvando && !contato.optOut;
  const criar = async () => {
    if (!podeCriar) return;
    setSalvando(true);
    setErro(null);
    const r = await repo.criarNegocio(contato!.id, funil!.id, campanhaId || null);
    setSalvando(false);
    if (r.ok && r.negocioId) onCriado({ negocioId: r.negocioId, donoId: r.donoId ?? null });
    else setErro(r.msg ?? 'Não foi possível criar.');
  };

  // Quem fica com o negócio, dito antes de criar.
  const donoPrevisto = !contato ? null
    : contato.optOut ? null
    : contato.donoId ? `Fica com ${nomeDe(contato.donoId)}, dono do contato.`
    : !funil ? 'Contato sem dono: a distribuição escolhe quem atende.'
    : funil.distribuicao ? 'Contato sem dono: vai pela distribuição própria deste funil.'
    : 'Contato sem dono: vai pela distribuição geral do Comercial.';

  return (
    <Modal
      onClose={onClose}
      title="Novo negócio"
      footer={<>
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!podeCriar} onClick={criar}>{salvando ? 'Criando…' : 'Criar negócio'}</Button>
      </>}
    >
      <div className="space-y-4">
        {contatoFixo ? (
          <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2">
            <Pessoa nome={contatoFixo.nome} sub={fmtTelefone(contatoFixo.telefone)} size={28} />
          </div>
        ) : (
          <div>
            <Campo rotulo="Contato" dica="Antes de falar com alguém fora da fila, busque pelo telefone: tem dono, não é seu.">
              <SearchInput
                autoFocus
                placeholder="Nome, e-mail ou telefone"
                value={busca}
                onChange={(e) => { setBusca(e.target.value); setContatoId(null); setErro(null); }}
                onLimpar={() => { setBusca(''); setContatoId(null); }}
              />
            </Campo>
            <div role="listbox" aria-label="Contatos encontrados" className="mt-2 max-h-56 overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)]">
              {lista.length === 0 && (
                <div className="px-3 py-4 text-center text-xs text-[var(--fg-3)]">
                  {!contatos && busca.trim().length < 3 ? 'Digite ao menos 3 letras do nome, o e-mail ou o telefone.' : `Nenhum contato com “${busca.trim()}”.`}
                </div>
              )}
              {lista.map((c) => {
                const sel = contatoId === c.id;
                return (
                  <button
                    key={c.id}
                    type="button"
                    role="option"
                    aria-selected={sel}
                    onClick={() => { setContatoId(c.id); setErro(null); }}
                    className={`w-full flex items-center justify-between gap-3 px-3 py-2 text-left border-b border-[var(--border-faint)] last:border-0 transition-colors ${sel ? 'bg-[var(--accent-subtle)]' : 'hover:bg-[var(--surface-3)]'}`}
                  >
                    <Pessoa
                      nome={c.nome}
                      sub={c.telefone ? fmtTelefone(c.telefone) : c.email ?? 'sem telefone'}
                      size={24}
                      flags={c.ehAluno ? <Sinal icone="graduation" rotulo="Já é aluno" /> : undefined}
                    />
                    <span className={`shrink-0 text-xs ${c.optOut ? 'font-medium text-[var(--red)]' : 'text-[var(--fg-3)]'}`}>
                      {c.optOut ? 'não quer contato' : c.donoId ? `dono: ${nomeDe(c.donoId)}` : 'sem dono'}
                    </span>
                  </button>
                );
              })}
            </div>
            {filtrados.length > MAX_RESULTADOS && (
              <NotaRodape className="mt-1">Mostrando {MAX_RESULTADOS} de {filtrados.length}. Refine pelo telefone.</NotaRodape>
            )}
          </div>
        )}

        <Campo rotulo="Funil">
          <FilterSelect autoFocus={!!contatoFixo} value={funilId} onChange={(e) => { setFunilId(e.target.value); setCampanhaId(''); setErro(null); }}>
            <option value="">Escolha o funil…</option>
            {(agrupadores ?? []).map((a: Agrupador) => {
              const fs = manuais.filter((f) => f.agrupadorId === a.id);
              if (!fs.length) return null;
              return (
                <optgroup key={a.id} label={a.nome}>
                  {fs.map((f) => <option key={f.id} value={f.id} disabled={jaTem(f)}>{f.nome}{jaTem(f) ? ' (já tem negócio aberto)' : ''}</option>)}
                </optgroup>
              );
            })}
          </FilterSelect>
        </Campo>

        {funil && funil.campanhas.length > 0 && (
          <Campo rotulo="Campanha de entrada" extra={<span className="text-[var(--fg-3)]">opcional</span>}>
            <FilterSelect value={campanhaId} onChange={(e) => setCampanhaId(e.target.value)}>
              <option value="">Sem campanha (entrada manual)</option>
              {funil.campanhas.filter((c) => c.ativa).map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
            </FilterSelect>
          </Campo>
        )}

        {contato?.optOut && (
          <Aviso tom="danger" icone="user-x">Este contato pediu para não receber contato. Negócio novo bloqueado.</Aviso>
        )}
        {donoPrevisto && <NotaRodape>{donoPrevisto}</NotaRodape>}
        {erro && <Aviso tom="danger" alerta>{erro}</Aviso>}
      </div>
    </Modal>
  );
}
