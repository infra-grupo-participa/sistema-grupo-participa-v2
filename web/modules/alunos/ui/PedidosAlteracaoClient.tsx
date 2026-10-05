'use client';

// Tela de quem PEDE alteração de cadastro (sem acesso à Central): novo pedido + "Meus pedidos".
import { useCallback, useEffect, useState } from 'react';
import {
  Badge, Button, DataTable, EmptyState, Loading, SectionCard, Td, Textarea, Th, Thead, Toast, Tr, useFlash, Input,
} from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { ESPACO_LABEL } from '../domain/aluno-360';
import {
  CAMPOS_EDITAVEIS,
  ENDERECO_PARTES,
  INSTRUCOES,
  ROTULO_TIPO,
  instrucaoDoSocio,
  resumoPedido,
  validarMotivoEvidencia,
  validarTrocaSocio,
  validarValor,
  type AlunoResumo,
  type PedidoLinha,
  type SocioNovo,
  type TipoPedido,
} from '../domain/pedidos-alteracao';
import { criarPedido, meusPedidos, sociosDoTitular, turmasPedido, valorAtual, type NovoPedido } from './pedidos-alteracao-data';
import { AlunoDistincao, BuscaAluno, FIELD_CLS, Rotulo, StatusPedido, rotuloInstrucao } from './pedidos-alteracao-ui';

const SOCIO_VAZIO: SocioNovo = { nome: '', email: '', telefone: '', documento: '' };

function CampoValor({ campo, valor, onChange, turmas }: {
  campo: string; valor: unknown; onChange: (v: unknown) => void; turmas: { id: number; codigo: string }[];
}) {
  if (campo === 'endereco') {
    const e = (valor ?? {}) as Record<string, string | null>;
    return (
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
        {ENDERECO_PARTES.map((p) => (
          <label key={p.k} className="block">
            <Rotulo>{p.rotulo}</Rotulo>
            <input className={FIELD_CLS} value={e[p.k] ?? ''} onChange={(ev) => onChange({ ...e, [p.k]: ev.target.value })} />
          </label>
        ))}
      </div>
    );
  }
  const s = valor == null ? '' : String(valor);
  if (campo === 'turma_id') {
    return (
      <select className={FIELD_CLS} value={s} onChange={(ev) => onChange(ev.target.value)}>
        <option value="">Escolha a turma</option>
        {turmas.map((t) => <option key={t.id} value={t.id}>{t.codigo}</option>)}
      </select>
    );
  }
  if (campo === 'instrucao') {
    return (
      <select className={FIELD_CLS} value={s} onChange={(ev) => onChange(ev.target.value)}>
        <option value="">Escolha a instrução</option>
        {INSTRUCOES.map((i) => <option key={i} value={i}>{i}</option>)}
      </select>
    );
  }
  if (campo === 'espaco_instrucao') {
    return (
      <select className={FIELD_CLS} value={s} onChange={(ev) => onChange(ev.target.value)}>
        <option value="">Escolha o espaço</option>
        {Object.entries(ESPACO_LABEL).map(([k, l]) => <option key={k} value={k}>{l}</option>)}
      </select>
    );
  }
  if (campo === 'obs_central') return <Textarea value={s} onChange={(ev) => onChange(ev.target.value)} rows={3} />;
  return <input className={FIELD_CLS} value={s} onChange={(ev) => onChange(ev.target.value)} />;
}

function NovoPedido({ onCriado }: { onCriado: (msg: string) => void }) {
  const [tipo, setTipo] = useState<TipoPedido>('alterar_dado');
  const [aluno, setAluno] = useState<AlunoResumo | null>(null);
  const [campo, setCampo] = useState('');
  const [atual, setAtual] = useState<{ valor: unknown; exibicao: string | null } | null>(null);
  const [novo, setNovo] = useState<unknown>('');
  const [turmas, setTurmas] = useState<{ id: number; codigo: string }[]>([]);
  const [socios, setSocios] = useState<AlunoResumo[] | null>(null);
  const [sai, setSai] = useState<AlunoResumo | null>(null);
  const [modoEntra, setModoEntra] = useState<'existente' | 'novo'>('existente');
  const [entra, setEntra] = useState<AlunoResumo | null>(null);
  const [socioNovo, setSocioNovo] = useState<SocioNovo>(SOCIO_VAZIO);
  const [descricao, setDescricao] = useState('');
  const [motivo, setMotivo] = useState('');
  const [evidencia, setEvidencia] = useState('');
  const [erro, setErro] = useState<string | null>(null);
  const [enviando, setEnviando] = useState(false);

  useEffect(() => {
    let vivo = true;
    turmasPedido().then((t) => { if (vivo) setTurmas(t); });
    return () => { vivo = false; };
  }, []);

  // Valor atual do campo escolhido (documento vem mascarado para quem não pode ver CPF).
  useEffect(() => {
    if (tipo !== 'alterar_dado' || !aluno || !campo) return;
    let vivo = true;
    valorAtual(aluno.id, campo).then((v) => {
      if (!vivo) return;
      setAtual(v);
      // Endereço e listas começam do valor atual; texto começa vazio (o valor atual aparece ao lado).
      if (campo === 'endereco') setNovo(v?.valor ?? {});
      else if (['turma_id', 'instrucao', 'espaco_instrucao'].includes(campo)) setNovo(v?.valor == null ? '' : String(v.valor));
      else setNovo('');
    });
    return () => { vivo = false; };
  }, [tipo, aluno, campo]);

  // Sócios do titular (troca guiada).
  useEffect(() => {
    if (tipo !== 'trocar_socio' || !aluno) return;
    let vivo = true;
    sociosDoTitular(aluno.id).then((s) => { if (vivo) setSocios(s); });
    return () => { vivo = false; };
  }, [tipo, aluno]);

  const limpar = (manterTipo = true) => {
    if (!manterTipo) setTipo('alterar_dado');
    setAluno(null); setCampo(''); setAtual(null); setNovo(''); setSocios(null); setSai(null); setEntra(null);
    setSocioNovo(SOCIO_VAZIO); setModoEntra('existente'); setDescricao(''); setMotivo(''); setEvidencia(''); setErro(null);
  };

  const trocarTipo = (t: TipoPedido) => { limpar(); setTipo(t); };
  const escolherAluno = (a: AlunoResumo | null) => {
    setAluno(a); setCampo(''); setAtual(null); setNovo(''); setSocios(null); setSai(null); setEntra(null);
  };

  // Validação de tela (o banco valida de novo).
  const valNovo = tipo === 'alterar_dado' && campo ? validarValor(campo, novo) : null;
  const erroTroca = tipo === 'trocar_socio'
    ? validarTrocaSocio({ titular: aluno, sai, socios: socios ?? [], entra: modoEntra === 'existente' ? entra : null,
                          novo: modoEntra === 'novo' ? socioNovo : null })
    : null;

  async function enviar() {
    setErro(null);
    if (!aluno) { setErro(tipo === 'trocar_socio' ? 'Escolha o titular.' : 'Escolha o aluno.'); return; }
    const em = validarMotivoEvidencia(motivo, evidencia);
    let p: NovoPedido = { tipo, aluno_id: aluno.id, motivo: motivo.trim(), evidencia: evidencia.trim() || undefined };
    if (tipo === 'alterar_dado') {
      if (!campo) { setErro('Escolha o campo.'); return; }
      if (!valNovo || !valNovo.ok) { setErro(valNovo && !valNovo.ok ? valNovo.erro : 'Informe o valor novo.'); return; }
      p = { ...p, campo, valor_novo: valNovo.valor };
    } else if (tipo === 'trocar_socio') {
      if (erroTroca) { setErro(erroTroca); return; }
      p = { ...p, socio_sai_id: sai!.id,
        ...(modoEntra === 'existente' ? { socio_entra_id: entra!.id } : { socio_entra_novo: socioNovo }) };
    } else {
      if (descricao.trim().length < 5) { setErro('Descreva a alteração (mínimo 5 caracteres).'); return; }
      p = { ...p, descricao: descricao.trim() };
    }
    if (em) { setErro(em); return; }
    setEnviando(true);
    const r = await criarPedido(p);
    setEnviando(false);
    if (!r.ok) { setErro(r.msg); return; }
    limpar();
    onCriado(r.msg);
  }

  const instrucaoEntra = aluno && tipo === 'trocar_socio' && aluno.instrucao
    ? instrucaoDoSocio({ instrucao: aluno.instrucao, espaco_instrucao: aluno.espaco }) : null;

  return (
    <SectionCard title="Novo pedido" subtitle="O pedido vai para aprovação. Você acompanha o andamento em Meus pedidos.">
      <div className="space-y-4">
        <div>
          <Rotulo>O que precisa mudar?</Rotulo>
          <div className="flex flex-wrap gap-2" role="radiogroup" aria-label="Tipo de pedido">
            {(Object.keys(ROTULO_TIPO) as TipoPedido[]).map((t) => (
              <button key={t} type="button" role="radio" aria-checked={tipo === t} onClick={() => trocarTipo(t)}
                className={`rounded-full border px-3 py-1.5 text-sm transition-colors ${tipo === t
                  ? 'border-[var(--accent)] text-[var(--accent)] bg-[var(--accent-subtle)]'
                  : 'border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)]'}`}>
                {ROTULO_TIPO[t]}
              </button>
            ))}
          </div>
        </div>

        <BuscaAluno rotulo={tipo === 'trocar_socio' ? 'Titular' : 'Aluno'} escolhido={aluno} onEscolher={escolherAluno}
          papelFixo={tipo === 'trocar_socio' ? 'titular' : undefined} />

        {tipo === 'alterar_dado' && aluno && (
          <div className="space-y-3">
            <label className="block">
              <Rotulo>Campo</Rotulo>
              <select className={FIELD_CLS} value={campo} onChange={(e) => { setCampo(e.target.value); setAtual(null); }}>
                <option value="">Escolha o campo</option>
                {CAMPOS_EDITAVEIS.map((c) => <option key={c.campo} value={c.campo}>{c.rotulo}</option>)}
              </select>
            </label>
            {campo && (
              <>
                <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm">
                  <span className="text-xs text-[var(--fg-3)]">Valor atual: </span>
                  <span className="text-[var(--fg)]">{atual ? (atual.exibicao ?? '(vazio)') : 'carregando…'}</span>
                </div>
                <div>
                  <Rotulo>Valor novo</Rotulo>
                  <CampoValor campo={campo} valor={novo} onChange={setNovo} turmas={turmas} />
                  {valNovo && !valNovo.ok && String(novo ?? '') !== '' && (
                    <p className="mt-1 text-xs text-[var(--red)]">{valNovo.erro}</p>
                  )}
                  {campo === 'email' && (
                    <p className="mt-1 text-xs text-[var(--fg-3)]">O e-mail antigo fica registrado no histórico do aluno e no pedido.</p>
                  )}
                </div>
              </>
            )}
          </div>
        )}

        {tipo === 'trocar_socio' && aluno && (
          <div className="space-y-3">
            <div>
              <Rotulo>Quem sai</Rotulo>
              {socios === null ? <Loading /> : socios.length === 0 ? (
                <p className="text-sm text-[var(--fg-3)]">Este titular não tem sócio cadastrado.</p>
              ) : (
                <div className="space-y-1" role="radiogroup" aria-label="Sócio que sai">
                  {socios.map((s) => (
                    <button key={s.id} type="button" role="radio" aria-checked={sai?.id === s.id} onClick={() => setSai(s)}
                      className={`w-full text-left rounded-[var(--r-md)] border px-3 py-2 transition-colors ${sai?.id === s.id
                        ? 'border-[var(--accent)] bg-[var(--accent-subtle)]' : 'border-[var(--border)] hover:bg-[var(--surface-3)]'}`}>
                      <AlunoDistincao a={s} />
                    </button>
                  ))}
                </div>
              )}
              <p className="mt-1 text-xs text-[var(--fg-3)]">Ao aprovar, abre um caso em Remoção de Acessos para quem sai.</p>
            </div>
            <div>
              <Rotulo>Quem entra</Rotulo>
              <div className="flex gap-2 mb-2">
                {(['existente', 'novo'] as const).map((m) => (
                  <Button key={m} size="sm" variant={modoEntra === m ? 'subtle' : 'ghost'} onClick={() => setModoEntra(m)}>
                    {m === 'existente' ? 'Já está na base' : 'Pessoa nova'}
                  </Button>
                ))}
              </div>
              {modoEntra === 'existente' ? (
                <BuscaAluno rotulo="Sócio que entra" escolhido={entra} onEscolher={setEntra}
                  excluirIds={[aluno.id, ...(socios ?? []).map((s) => s.id)]} />
              ) : (
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                  {([['nome', 'Nome completo'], ['email', 'E-mail'], ['telefone', 'Telefone'], ['documento', 'CPF ou CNPJ (opcional)']] as const).map(([k, l]) => (
                    <label key={k} className="block">
                      <Rotulo>{l}</Rotulo>
                      <input className={FIELD_CLS} value={socioNovo[k]} onChange={(e) => setSocioNovo((s) => ({ ...s, [k]: e.target.value }))} />
                    </label>
                  ))}
                </div>
              )}
              {instrucaoEntra && (
                <p className="mt-1 text-xs text-[var(--fg-3)]">
                  Quem entra recebe a instrução <strong>{rotuloInstrucao(instrucaoEntra)}</strong> e o vencimento do titular.
                </p>
              )}
            </div>
          </div>
        )}

        {tipo === 'outro' && aluno && (
          <label className="block">
            <Rotulo>O que precisa mudar</Rotulo>
            <Textarea value={descricao} onChange={(e) => setDescricao(e.target.value)} rows={3} placeholder="Descreva a alteração" />
          </label>
        )}

        {aluno && (
          <>
            <label className="block">
              <Rotulo>Motivo (obrigatório)</Rotulo>
              <Textarea value={motivo} onChange={(e) => setMotivo(e.target.value)} rows={2}
                placeholder="Por que mudar? Ex.: o aluno pediu por WhatsApp em 05/10." />
            </label>
            <label className="block">
              <Rotulo dica="opcional">Evidência (link)</Rotulo>
              <Input value={evidencia} onChange={(e) => setEvidencia(e.target.value)} placeholder="https://… (print, conversa, documento)" />
            </label>
          </>
        )}

        {erro && <p className="text-sm text-[var(--red)]" role="alert">{erro}</p>}
        <div className="flex justify-end gap-2">
          {aluno && <Button variant="ghost" onClick={() => limpar()}>Limpar</Button>}
          <Button onClick={enviar} disabled={enviando || !aluno}>{enviando ? 'Enviando…' : 'Enviar pedido'}</Button>
        </div>
      </div>
    </SectionCard>
  );
}

function MeusPedidos({ pedidos, erro }: { pedidos: PedidoLinha[] | null; erro: string | null }) {
  if (erro) return <EmptyState title={erro} />;
  if (!pedidos) return <Loading />;
  if (pedidos.length === 0) return <EmptyState title="Você ainda não fez pedidos." hint="Os pedidos que você enviar aparecem aqui com o andamento." />;
  return (
    <DataTable minWidth={760}>
      <Thead>
        <Th>Nº</Th><Th>Enviado</Th><Th>Aluno</Th><Th>Pedido</Th><Th>Situação</Th><Th>Decisão</Th>
      </Thead>
      <tbody>
        {pedidos.map((p) => (
          <Tr key={p.id}>
            <Td className="tabular text-[var(--fg-3)]">{p.id}</Td>
            <Td className="tabular text-xs text-[var(--fg-3)]">{fmtDataHora(p.solicitado_em)}</Td>
            <Td>{p.aluno_nome}</Td>
            <Td>
              <span className="block text-xs text-[var(--fg-3)]"><Badge>{ROTULO_TIPO[p.tipo]}</Badge></span>
              <span className="block text-sm text-[var(--fg)] break-words">{resumoPedido(p)}</span>
            </Td>
            <Td><StatusPedido p={p} /></Td>
            <Td className="text-xs text-[var(--fg-2)]">
              {p.decidido_em ? `${p.decidido_por_nome ?? ''} · ${fmtDataHora(p.decidido_em)}` : 'sem decisão ainda'}
              {p.motivo_recusa && <span className="block text-[var(--red)]">Motivo: {p.motivo_recusa}</span>}
            </Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}

export function PedidosAlteracaoClient() {
  const { toast, flash } = useFlash(4000);
  const [pedidos, setPedidos] = useState<PedidoLinha[] | null>(null);
  const [erro, setErro] = useState<string | null>(null);

  const carregar = useCallback(async () => {
    try { setPedidos(await meusPedidos()); setErro(null); }
    catch (e) { setErro(e instanceof Error ? e.message : 'Não foi possível carregar seus pedidos.'); }
  }, []);

  useEffect(() => {
    let vivo = true;
    meusPedidos().then((p) => { if (vivo) setPedidos(p); }).catch((e) => { if (vivo) setErro(e.message); });
    return () => { vivo = false; };
  }, []);

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-2xl font-bold text-[var(--fg)] mb-1">Pedidos de alteração de cadastro</h1>
        <p className="text-sm text-[var(--fg-3)] max-w-[70ch]">
          Peça a correção de um dado do aluno ou a troca de um sócio. Cada pedido passa pela aprovação antes de mudar a base.
        </p>
      </div>
      <NovoPedido onCriado={(msg) => { flash(msg); carregar(); }} />
      <SectionCard title="Meus pedidos" right={<Button variant="ghost" size="sm" onClick={carregar}>Atualizar</Button>}>
        <MeusPedidos pedidos={pedidos} erro={erro} />
      </SectionCard>
      <Toast>{toast}</Toast>
    </div>
  );
}
