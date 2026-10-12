'use client';

// Tabela de leads do recorte, só ao abrir a sub-aba e 50 por página: nome, e-mail e telefone saem da fonte
// sob demanda (dado pessoal não vem junto do perfil). Falha na leitura segura a página anterior.
import { useEffect, useState } from 'react';
import { Button, DataTable, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { LEADS_POR_PAGINA } from '../../application/ports';
import { NAO_INFORMADO, ROTULO_FUNIL, ROTULO_PORTA, ROTULO_PROFISSAO, type LeadDetalhe, type LinhaPerfil } from '../../domain/tipos';
import type { DadosTela } from '../contexto';
import { inteiro } from '../pecas';

const quando = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
const ou = (v: string | null | undefined) => v ?? NAO_INFORMADO;

export function TabelaLeads({ d, linhas }: { d: DadosTela; linhas: LinhaPerfil[] }) {
  const [pagina, setPagina] = useState(0);
  const [lido, setLido] = useState<{ marca: string; detalhes: Map<string, LeadDetalhe>; erro: string | null } | null>(null);
  const ordenadas = [...linhas].sort((a, b) => b.criadoEm.localeCompare(a.criadoEm));
  const paginas = Math.max(1, Math.ceil(ordenadas.length / LEADS_POR_PAGINA));
  const atual = Math.min(pagina, paginas - 1);
  const daPagina = ordenadas.slice(atual * LEADS_POR_PAGINA, (atual + 1) * LEADS_POR_PAGINA);
  const ids = daPagina.map((l) => l.leadId);
  const marca = ids.join(',');

  useEffect(() => {
    if (!marca) return;
    let vivo = true;
    const tempo = new Promise<never>((_, falha) => setTimeout(() => falha(new Error('tempo')), 15_000));
    Promise.race([d.fonte.leads(d.chave, marca.split(',')), tempo]).then(
      (r) => { if (vivo) setLido((ant) => (r.erro ? { marca, detalhes: ant?.detalhes ?? new Map(), erro: r.erro } : { marca, detalhes: new Map(r.data.map((x) => [x.leadId, x])), erro: null })); },
      () => { if (vivo) setLido((ant) => ({ marca, detalhes: ant?.detalhes ?? new Map(), erro: 'Falha ao ler os contatos desta página.' })); },
    );
    return () => { vivo = false; };
  }, [d.fonte, d.chave, marca]);

  const carregando = Boolean(marca) && lido?.marca !== marca;
  const detalhes = lido?.detalhes ?? new Map<string, LeadDetalhe>();
  if (ordenadas.length === 0) return <p className="py-6 text-center text-sm text-[var(--fg-3)]">Nenhum cadastro neste recorte.</p>;

  return (
    <div className="space-y-2">
      {lido?.erro && <p role="status" className="text-xs text-[var(--yellow)]">{lido.erro}</p>}
      <DataTable minWidth={880} className={carregando ? 'opacity-60' : ''}>
        <Thead>
          <Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Profissão</Th><Th>Estado *</Th><Th>Funil</Th><Th>Porta</Th><Th>Cadastro</Th>
        </Thead>
        <tbody>
          {daPagina.map((l) => {
            const x = detalhes.get(l.leadId);
            return (
              <Tr key={l.leadId}>
                <Td className="text-sm">{x?.nome ?? '—'}</Td>
                <Td className="text-xs text-[var(--fg-2)]">{x?.email ?? '—'}</Td>
                <Td className="text-xs tabular text-[var(--fg-2)]">{x?.telefone ?? '—'}</Td>
                <Td className="text-xs">{l.profissao ? ROTULO_PROFISSAO[l.profissao] : ou(l.profissaoBruta)}</Td>
                <Td className="text-xs">{ou(l.uf)}</Td>
                <Td className="text-xs">{l.funil ? ROTULO_FUNIL[l.funil] : NAO_INFORMADO}</Td>
                <Td className="text-xs">{l.porta ? ROTULO_PORTA[l.porta] : NAO_INFORMADO}{l.primeiraPorta ? '' : ' (2ª porta)'}</Td>
                <Td className="text-xs tabular">{quando(l.criadoEm)}</Td>
              </Tr>
            );
          })}
        </tbody>
      </DataTable>
      <div className="flex flex-wrap items-center justify-between gap-2 text-xs text-[var(--fg-3)]">
        <span>* Estado pelo DDD do telefone. {inteiro(ordenadas.length)} cadastros, página {atual + 1} de {paginas}.</span>
        <span className="flex gap-2">
          <Button variant="ghost" size="sm" disabled={atual === 0} onClick={() => setPagina(atual - 1)}>Anterior</Button>
          <Button variant="ghost" size="sm" disabled={atual >= paginas - 1} onClick={() => setPagina(atual + 1)}>Próxima</Button>
        </span>
      </div>
    </div>
  );
}
