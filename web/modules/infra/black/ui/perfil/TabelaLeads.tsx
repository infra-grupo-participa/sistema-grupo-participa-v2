'use client';

// Tabela de leads do recorte, só ao abrir a sub-aba e 50 por página: nome, e-mail e telefone saem da fonte
// sob demanda (dado pessoal não vem junto do perfil). Falha na leitura segura a página anterior.
// Master marca e desmarca teste por linha (padrão do ATM: confirmação antes de marcar, recarrega depois). O
// `parece_teste` do banco só aparece como sugestão: nada é marcado sozinho.
import { useEffect, useState } from 'react';
import { Button, ConfirmDialog, DataTable, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { LEADS_POR_PAGINA } from '../../application/ports';
import { NAO_INFORMADO, ROTULO_FUNIL, ROTULO_PORTA, ROTULO_PROFISSAO, type LeadDetalhe, type LinhaPerfil } from '../../domain/tipos';
import type { DadosTela } from '../contexto';
import { inteiro } from '../pecas';

const quando = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
const ou = (v: string | null | undefined) => v ?? NAO_INFORMADO;

export function TabelaLeads({ d, linhas }: { d: DadosTela; linhas: LinhaPerfil[] }) {
  const [pagina, setPagina] = useState(0);
  const [lido, setLido] = useState<{ marca: string; detalhes: Map<string, LeadDetalhe>; erro: string | null } | null>(null);
  const [verTestes, setVerTestes] = useState(false);
  const [alvo, setAlvo] = useState<LeadDetalhe | null>(null);
  const [salvando, setSalvando] = useState<string | null>(null);
  const [erroAcao, setErroAcao] = useState<string | null>(null);
  const master = d.isMaster;
  const fonteLinhas = master && verTestes ? d.linhasTeste : linhas;
  const ordenadas = [...fonteLinhas].sort((a, b) => b.criadoEm.localeCompare(a.criadoEm));
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

  const mudar = async (lead: LeadDetalhe, teste: boolean) => {
    if (salvando) return;
    setSalvando(lead.leadId); setErroAcao(null);
    const r = await (teste ? d.fonte.marcarTeste(d.chave, lead) : d.fonte.desmarcarTeste(d.chave, lead));
    setSalvando(null); setAlvo(null);
    if (r.erro) setErroAcao(r.erro); else d.recarregar();
  };

  const alternar = master ? (
    <div className="flex justify-end">
      <Button variant="ghost" size="sm" onClick={() => { setVerTestes((v) => !v); setPagina(0); }}>
        {verTestes ? 'Voltar aos leads' : `Ver os testes do período (${inteiro(d.linhasTeste.length)})`}
      </Button>
    </div>
  ) : null;
  if (ordenadas.length === 0) {
    return <div className="space-y-2">{alternar}<p className="py-6 text-center text-sm text-[var(--fg-3)]">{verTestes ? 'Nenhum teste marcado neste período.' : 'Nenhum cadastro neste recorte.'}</p></div>;
  }

  return (
    <div className="space-y-2">
      {alternar}
      {lido?.erro && <p role="status" className="text-xs text-[var(--yellow)]">{lido.erro}</p>}
      {erroAcao && <p role="alert" className="text-xs text-[var(--yellow)]">{erroAcao}</p>}
      <DataTable minWidth={master ? 1080 : 880} className={carregando ? 'opacity-60' : ''}>
        <Thead>
          <Th>Nome</Th><Th>E-mail</Th><Th>Telefone</Th><Th>Profissão</Th><Th>Estado *</Th><Th>Funil</Th><Th>Porta</Th><Th>Cadastro</Th>
          {master && <><Th>Teste</Th><Th>Ação</Th></>}
        </Thead>
        <tbody>
          {daPagina.map((l) => {
            const x = detalhes.get(l.leadId);
            return (
              <Tr key={l.leadId} className={l.teste ? 'opacity-60' : undefined}>
                <Td className="text-sm">{x?.nome ?? '—'}</Td>
                <Td className="text-xs text-[var(--fg-2)]">{x?.email ?? '—'}</Td>
                <Td className="text-xs tabular text-[var(--fg-2)]">{x?.telefone ?? '—'}</Td>
                <Td className="text-xs">{l.profissao ? ROTULO_PROFISSAO[l.profissao] : ou(l.profissaoBruta)}</Td>
                <Td className="text-xs">{ou(l.uf)}</Td>
                <Td className="text-xs">{l.funil ? ROTULO_FUNIL[l.funil] : NAO_INFORMADO}</Td>
                <Td className="text-xs">{l.porta ? ROTULO_PORTA[l.porta] : NAO_INFORMADO}{l.primeiraPorta ? '' : ' (2ª porta)'}</Td>
                <Td className="text-xs tabular">{quando(l.criadoEm)}</Td>
                {master && (
                  <>
                    <Td className="text-xs">
                      {l.teste ? <span className="rounded-full border border-[var(--border)] px-2 py-0.5 text-[10px] uppercase">teste</span>
                        : l.pareceTeste ? <span title="Sugestão do banco (nome ou e-mail com teste, ou e-mail da equipe). Não foi marcado." className="rounded-full border border-dashed border-[var(--yellow)] px-2 py-0.5 text-[10px] text-[var(--yellow)]">parece teste</span>
                        : 'Não'}
                    </Td>
                    <Td className="text-xs">
                      {x && (x.email || x.telefone) && (
                        <button type="button" disabled={salvando === l.leadId}
                          onClick={() => { setErroAcao(null); if (l.teste) void mudar(x, false); else setAlvo(x); }}
                          className="whitespace-nowrap rounded border border-[var(--border)] px-2 py-1 text-xs hover:bg-[var(--surface-3)] disabled:opacity-50">
                          {salvando === l.leadId ? 'Salvando…' : l.teste ? 'Desmarcar teste' : 'Marcar como teste'}
                        </button>
                      )}
                    </Td>
                  </>
                )}
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
      {alvo && (
        <ConfirmDialog title="Marcar lead como teste" confirmLabel="Marcar como teste" cancelLabel="Cancelar"
          onCancel={() => setAlvo(null)} onConfirm={() => void mudar(alvo, true)}
          message="Esta marcação vale para esta Black Friday. A pessoa (pelo e-mail e pelo telefone) e os dados relacionados deixam de contar nos indicadores deste evento. Quer continuar?" />
      )}
    </div>
  );
}
