'use client';

// Pessoas: busca na base única (nome, e-mail, telefone ou documento; ou todos os leads de um projeto) e cadastro.
// O banco decide se a pessoa já existe (cascata da casa); dúvida vai para a Revisão de identidade.
import { useState } from 'react';
import { Badge, Button, DataTable, EmptyState, FilterSelect, Input, Loading, Modal, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtData } from '@/shared/ui/format';
import type { ConfigCrm } from '../domain/crm';
import { temIdentificador, ROTULO_MOTIVO, type MotivoRevisao } from '../domain/identidade';
import { ROTULO_SITUACAO, type ItemBusca } from '../domain/pessoas';
import { buscarPessoas, cadastrarPessoa } from '../infrastructure/comercial-data';

interface Props {
  config: ConfigCrm;
  versao: number;
  onAbrirPessoa: (id: string) => void;
  flash: (m: string) => void;
  onMudou: () => void;
}

export function PessoasPainel({ config, onAbrirPessoa, flash, onMudou }: Props) {
  const [termo, setTermo] = useState('');
  const [projeto, setProjeto] = useState<number | null>(null);
  const [res, setRes] = useState<ItemBusca[] | null | undefined>(undefined);
  const [carregando, setCarregando] = useState(false);
  const [cadastro, setCadastro] = useState(false);

  async function buscar() {
    const t = termo.trim();
    if (t.length < 3 && projeto == null) { flash('Digite ao menos 3 letras ou escolha um projeto.'); return; }
    setCarregando(true);
    setRes(await buscarPessoas(t || null, projeto));
    setCarregando(false);
  }

  async function trazerAluno(alunoId: string) {
    const r = await cadastrarPessoa({ aluno_id: alunoId });
    flash(r.msg ?? (r.ok ? 'Aluno trazido para a base.' : 'Não foi possível.'));
    if (r.ok && r.pessoa_id) { onMudou(); onAbrirPessoa(r.pessoa_id); }
  }

  return (
    <div className="space-y-4">
      <SectionCard>
        <div className="flex flex-wrap items-end gap-3">
          <label className="block flex-1 min-w-[240px]">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Buscar</span>
            <Input value={termo} onChange={(e) => setTermo(e.target.value)} onKeyDown={(e) => e.key === 'Enter' && buscar()}
              placeholder="Nome, e-mail, telefone ou documento" aria-label="Buscar pessoa" />
          </label>
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Projeto</span>
            <FilterSelect value={projeto ?? ''} onChange={(e) => setProjeto(e.target.value ? Number(e.target.value) : null)} aria-label="Projeto">
              <option value="">Todos</option>
              {config.projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla} · {p.nome}</option>)}
            </FilterSelect>
          </label>
          <Button onClick={buscar}>Buscar</Button>
          {config.permissoes.pode_editar && <Button variant="ghost" onClick={() => setCadastro(true)}>Cadastrar pessoa</Button>}
        </div>
        <p className="mt-2 text-xs text-[var(--fg-3)]">
          Toda busca e toda ficha aberta ficam registradas (quem e quando). E-mail, telefone e documento aparecem mascarados para quem não pode ver.
        </p>
      </SectionCard>

      {carregando ? <Loading /> : res === undefined ? null : res === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível buscar (erro de rede, sem acesso, ou a migration 20261005o ainda não foi aplicada).</p>
      ) : res.length === 0 ? (
        <SectionCard><EmptyState title="Ninguém encontrado" hint="Confira a grafia, ou busque por e-mail, telefone com DDD ou documento." /></SectionCard>
      ) : (
        <SectionCard className="!p-0">
          <DataTable minWidth={820}>
            <Thead><tr><Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Projetos</Th><Th>Negócios abertos</Th><Th>Na base desde</Th><Th> </Th></tr></Thead>
            <tbody>
              {res.map((p) => (
                <Tr key={p.id ?? `a-${p.aluno_id}`} onClick={p.id ? () => onAbrirPessoa(p.id as string) : undefined}>
                  <Td>
                    <span className="font-medium text-[var(--fg)]">{p.nome ?? 'Sem nome'}</span>
                    <span className="ml-2 inline-flex gap-1">
                      {p.eh_aluno && <Badge tone="info">Aluno{p.turma ? ` ${p.turma}` : ''}</Badge>}
                      {p.eh_comprador && <Badge>Comprador</Badge>}
                      {p.situacao && p.situacao !== 'ativa' && <Badge tone="warning">{ROTULO_SITUACAO[p.situacao]}</Badge>}
                      {p.teste && <Badge>Teste</Badge>}
                    </span>
                  </Td>
                  <Td>{p.email ?? '—'}</Td>
                  <Td>{p.telefone ?? '—'}</Td>
                  <Td>{p.projetos.join(', ') || '—'}</Td>
                  <Td>{p.negocios_abertos}</Td>
                  <Td>{p.criado_em ? fmtData(p.criado_em) : '—'}</Td>
                  <Td>
                    {p.tipo === 'aluno' && p.aluno_id && config.permissoes.pode_editar && (
                      <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); trazerAluno(p.aluno_id as string); }}>Trazer para a base</Button>
                    )}
                  </Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        </SectionCard>
      )}

      {cadastro && <CadastroModal config={config} onFechar={() => setCadastro(false)} flash={flash}
        onFeito={(id) => { setCadastro(false); onMudou(); onAbrirPessoa(id); }} />}
    </div>
  );
}

function CadastroModal({ config, onFechar, flash, onFeito }: {
  config: ConfigCrm; onFechar: () => void; flash: (m: string) => void; onFeito: (id: string) => void;
}) {
  const [f, setF] = useState({ nome: '', email: '', telefone: '', documento: '', cep: '', projeto: '' });
  const [ocupado, setOcupado] = useState(false);
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLSelectElement>) => setF((x) => ({ ...x, [k]: e.target.value }));
  const valido = temIdentificador(f);

  async function salvar() {
    setOcupado(true);
    const r = await cadastrarPessoa({ ...f, projeto: f.projeto || null });
    setOcupado(false);
    flash(r.revisao ? `${r.msg} (${ROTULO_MOTIVO[r.revisao as MotivoRevisao] ?? r.revisao})` : r.msg);
    if (r.ok && r.pessoa_id) onFeito(r.pessoa_id);
  }

  return (
    <Modal onClose={onFechar} title="Cadastrar pessoa" width="max-w-lg">
      <div className="space-y-3 text-sm">
        <p className="text-xs text-[var(--fg-3)]">
          Se a pessoa já existir (documento, telefone, e-mail ou nome + CEP), o cadastro é ligado a ela e nada é duplicado. Se houver dúvida, vai para a Revisão de identidade.
        </p>
        <div className="grid gap-3 sm:grid-cols-2">
          <Rotulo t="Nome" cls="sm:col-span-2"><Input value={f.nome} onChange={set('nome')} maxLength={160} /></Rotulo>
          <Rotulo t="E-mail"><Input type="email" value={f.email} onChange={set('email')} /></Rotulo>
          <Rotulo t="Telefone com DDD"><Input value={f.telefone} onChange={set('telefone')} /></Rotulo>
          <Rotulo t="CPF ou CNPJ"><Input value={f.documento} onChange={set('documento')} /></Rotulo>
          <Rotulo t="CEP"><Input value={f.cep} onChange={set('cep')} /></Rotulo>
          <Rotulo t="Projeto (origem)" cls="sm:col-span-2">
            <FilterSelect value={f.projeto} onChange={set('projeto')} aria-label="Projeto">
              <option value="">Sem projeto</option>
              {config.projetos.map((p) => <option key={p.id} value={p.sigla}>{p.sigla} · {p.nome}</option>)}
            </FilterSelect>
          </Rotulo>
        </div>
        {!valido && <p className="text-xs text-[var(--yellow)]">Informe um e-mail, telefone com DDD ou documento válido.</p>}
        <div className="flex justify-end gap-2">
          <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
          <Button size="sm" onClick={salvar} disabled={!valido || ocupado}>Cadastrar</Button>
        </div>
      </div>
    </Modal>
  );
}

function Rotulo({ t, cls = '', children }: { t: string; cls?: string; children: React.ReactNode }) {
  return (
    <label className={`block ${cls}`}>
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">{t}</span>
      {children}
    </label>
  );
}
