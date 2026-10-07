'use client';

import { useCallback, useEffect, useState } from 'react';
import { Button, DataTable, EmptyState, FilterSelect, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { logQueryError } from '@/shared/infrastructure/supabase/query-log';

type Vinculo = { id: number; perfil_id: string; nome: string | null; status: string | null; departamento: string; area: string | null; papel: 'responsavel' | 'membro'; vigente_de: string };
type Capacidade = { perfil_id: string; nome: string | null; chave: string };
type Catalogo = { key: string; label: string; areas: { key: string; label: string }[] };
type Lista = { masters: unknown[]; vinculos: Vinculo[]; capacidades: Capacidade[]; departamentos: Catalogo[] };
type Resposta = { ok: boolean; msg?: string; id?: number };
type Pessoa = { id: string; nome: string | null; email: string | null };
const CHAVES = ['financeiro.ver', 'financeiro.operar', 'cpf.ver', 'contato.ver'] as const;

export function AcessosV2Client({ pessoas }: { pessoas: Pessoa[] }) {
  const [lista, setLista] = useState<Lista | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [perfil, setPerfil] = useState('');
  const [departamento, setDepartamento] = useState('');
  const [area, setArea] = useState('');
  const [papel, setPapel] = useState<'membro' | 'responsavel'>('membro');
  const [capacidade, setCapacidade] = useState<string>(CHAVES[0]);
  const [ligar, setLigar] = useState(true);

  const carregar = useCallback(async () => {
    const { data, error } = await createBrowserSupabase().rpc('acesso_listar');
    if (error) {
      logQueryError('acesso_listar', { message: error.code });
      setErro(error.code === '42501' ? 'Você não tem acesso à gestão de permissões.' : 'Não foi possível carregar os acessos.');
      return;
    }
    const valor = data as Lista | null;
    if (!valor || !Array.isArray(valor.vinculos) || !Array.isArray(valor.capacidades) || !Array.isArray(valor.departamentos)) {
      setErro('Resposta de acessos inválida.');
      return;
    }
    setLista(valor);
    setErro(null);
  }, []);

  useEffect(() => { void Promise.resolve().then(carregar); }, [carregar]);

  async function gravar(nome: string, args: Record<string, unknown>) {
    setOcupado(true);
    const { data, error } = await createBrowserSupabase().rpc(nome, args);
    setOcupado(false);
    if (error) {
      logQueryError(nome, { message: error.code });
      setErro(error.code === '42501' ? 'Você não tem acesso à gestão de permissões.' : 'Não foi possível salvar.');
      return;
    }
    const resposta = data as Resposta | null;
    if (!resposta?.ok) { setErro(resposta?.msg ?? 'Não foi possível salvar.'); return; }
    await carregar();
  }

  const escolhido = lista?.departamentos.find((d) => d.key === departamento);
  return <div className="space-y-5">
    <p className="text-sm text-[var(--fg-2)]">Só administradores master concedem ou removem vínculos e capacidades. O histórico fica no banco.</p>
    {erro && <p role="alert" className="text-sm text-[var(--red)]">{erro}</p>}
    {!lista ? <p>Carregando acessos…</p> : <>
      <SectionCard title="Vincular pessoa a departamento ou área">
        <div className="flex flex-wrap items-end gap-2">
          <label className="text-xs text-[var(--fg-3)]">Pessoa<FilterSelect className="mt-1" value={perfil} onChange={(e) => setPerfil(e.target.value)}><option value="">Selecione</option>{pessoas.map((p) => <option key={p.id} value={p.id}>{p.nome || p.email || p.id}</option>)}</FilterSelect></label>
          <label className="text-xs text-[var(--fg-3)]">Departamento<FilterSelect className="mt-1" value={departamento} onChange={(e) => { setDepartamento(e.target.value); setArea(''); }}><option value="">Selecione</option>{lista.departamentos.map((d) => <option key={d.key} value={d.key}>{d.label}</option>)}</FilterSelect></label>
          <label className="text-xs text-[var(--fg-3)]">Área<FilterSelect className="mt-1" value={area} onChange={(e) => setArea(e.target.value)}><option value="">Departamento inteiro</option>{(escolhido?.areas ?? []).map((a) => <option key={a.key} value={a.key}>{a.label}</option>)}</FilterSelect></label>
          <label className="text-xs text-[var(--fg-3)]">Papel<FilterSelect className="mt-1" value={papel} onChange={(e) => setPapel(e.target.value as 'membro' | 'responsavel')}><option value="membro">Membro</option><option value="responsavel">Responsável</option></FilterSelect></label>
          <Button disabled={ocupado || !perfil || !departamento} onClick={() => gravar('acesso_vincular', { p_perfil: perfil, p_departamento: departamento, p_area: area || null, p_papel: papel })}>Vincular</Button>
        </div>
      </SectionCard>
      <SectionCard title="Vínculos vigentes">
        {!lista.vinculos.length ? <EmptyState title="Nenhum vínculo" /> : <DataTable><Thead><Th>Pessoa</Th><Th>Departamento</Th><Th>Área</Th><Th>Papel</Th><Th>Ação</Th></Thead><tbody>{lista.vinculos.map((v) => <Tr key={v.id}><Td>{v.nome ?? v.perfil_id}</Td><Td>{v.departamento}</Td><Td>{v.area ?? 'Departamento inteiro'}</Td><Td>{v.papel}</Td><Td><Button variant="ghost" size="sm" disabled={ocupado} onClick={() => gravar('acesso_desvincular', { p_vinculo: v.id })}>Remover vínculo</Button></Td></Tr>)}</tbody></DataTable>}
      </SectionCard>
      <SectionCard title="Capacidades especiais" subtitle="Financeiro, CPF e contato exigem concessão explícita.">
        <div className="mb-3 flex flex-wrap items-end gap-2">
          <label className="text-xs text-[var(--fg-3)]">Pessoa<FilterSelect className="mt-1" value={perfil} onChange={(e) => setPerfil(e.target.value)}><option value="">Selecione</option>{pessoas.map((p) => <option key={p.id} value={p.id}>{p.nome || p.email || p.id}</option>)}</FilterSelect></label>
          <label className="text-xs text-[var(--fg-3)]">Capacidade<FilterSelect className="mt-1" value={capacidade} onChange={(e) => setCapacidade(e.target.value)}>{CHAVES.map((chave) => <option key={chave} value={chave}>{chave}</option>)}</FilterSelect></label>
          <label className="text-xs text-[var(--fg-3)]">Ação<FilterSelect className="mt-1" value={ligar ? 'ligar' : 'desligar'} onChange={(e) => setLigar(e.target.value === 'ligar')}><option value="ligar">Conceder</option><option value="desligar">Revogar</option></FilterSelect></label>
          <Button disabled={ocupado || !perfil} onClick={() => gravar('acesso_capacidade_definir', { p_perfil: perfil, p_chave: capacidade, p_ligar: ligar })}>Aplicar</Button>
        </div>
        {!lista.capacidades.length ? <EmptyState title="Nenhuma capacidade explícita" /> : <DataTable><Thead><Th>Pessoa</Th><Th>Capacidade</Th></Thead><tbody>{lista.capacidades.map((c) => <Tr key={`${c.perfil_id}/${c.chave}`}><Td>{c.nome ?? c.perfil_id}</Td><Td>{c.chave}</Td></Tr>)}</tbody></DataTable>}
      </SectionCard>
    </>}
  </div>;
}
