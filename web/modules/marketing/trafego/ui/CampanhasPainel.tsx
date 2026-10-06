'use client';

// Campanhas fora do padrão de nome (GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA) e as sem projeto. Aqui dá para
// ligar à mão a um projeto (enquanto o nome não é corrigido no gerenciador) e reler os nomes depois de cadastrar um
// projeto ou uma página.
import { useEffect, useState } from 'react';
import { Badge, Button, DataTable, EmptyState, FilterSelect, Loading, SectionCard, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { motivoErro } from '../../projetos/domain/campanha';
import type { Campanha, LinhaResumo } from '../domain/tipos';
import { ajustarCampanha, listarCampanhas, relerCampanhas } from '../infrastructure/trafego-data';
import { SEM_DADO, reais } from './formato';

export function CampanhasPainel({ linhas, versao, flash, onMudou }: {
  linhas: LinhaResumo[]; versao: number; flash: (m: string) => void; onMudou: () => void;
}) {
  const [lista, setLista] = useState<Campanha[] | null | undefined>(undefined);
  const [semProjeto, setSemProjeto] = useState(false);
  const [relendo, setRelendo] = useState(false);

  useEffect(() => {
    let vivo = true;
    // fora do padrão (todas) ou só as sem projeto (dentro ou fora do padrão)
    listarCampanhas(null, semProjeto, !semProjeto).then((c) => { if (vivo) setLista(c); });
    return () => { vivo = false; };
  }, [versao, semProjeto]);

  async function ligar(c: Campanha, projeto: string) {
    const r = await ajustarCampanha({ id: c.id, projeto_id: projeto ? Number(projeto) : null });
    flash(r.msg);
    if (r.ok) onMudou();
  }

  async function reler() {
    setRelendo(true);
    const r = await relerCampanhas();
    setRelendo(false);
    flash(r.msg);
    if (r.ok) onMudou();
  }

  return (
    <SectionCard
      title={semProjeto ? 'Campanhas sem projeto' : 'Campanhas fora do padrão'}
      subtitle="Padrão: GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA. A descrição é tudo depois do objetivo (pode ter várias partes com |); a página é opcional, só no último campo e só no formato AK1, BL2, AK1-B. Cada linha diz o motivo. O certo é corrigir o nome no gerenciador; ligar à mão é o remendo até lá."
      right={
        <div className="flex flex-wrap items-center gap-2">
          <Toggle checked={semProjeto} onChange={setSemProjeto} label="Só as sem projeto" />
          <Button size="sm" variant="subtle" onClick={reler} disabled={relendo}>{relendo ? 'Relendo…' : 'Reler os nomes'}</Button>
        </div>
      }
    >
      {lista === undefined ? <Loading /> : !lista ? <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar as campanhas.</p>
        : lista.length === 0 ? <EmptyState title="Nenhuma campanha aqui" hint="Ou está tudo no padrão, ou a coleta ainda não trouxe campanhas." /> : (
          <DataTable minWidth={1000}>
            <Thead><Th>Campanha (nome exato)</Th><Th>Conta</Th><Th>Motivo</Th><Th>Gasto</Th><Th>Projeto</Th></Thead>
            <tbody>
              {lista.map((c) => (
                <Tr key={c.id}>
                  <Td><div className="font-mono text-xs break-all">{c.nome}</div><div className="text-[11px] text-[var(--fg-3)]">{c.status_plataforma ?? ''}</div></Td>
                  <Td>{c.conta}</Td>
                  <Td>{c.fora_padrao
                    ? <ul className="text-xs text-[var(--yellow)]">{c.erros.map((e) => <li key={e}>{motivoErro(e, { ...c, projeto: c.projeto_lido })}</li>)}</ul>
                    : <Badge tone="success">No padrão</Badge>}</Td>
                  <Td>{reais(c.gasto)}</Td>
                  <Td>
                    <FilterSelect value={c.projeto_manual ? (c.projeto_id ?? '') : ''} aria-label="Ligar a um projeto"
                      onChange={(e) => void ligar(c, e.target.value)}>
                      <option value="">{c.projeto_sigla && !c.projeto_manual ? `Pelo nome: ${c.projeto_sigla}` : `Pelo nome (${c.projeto_sigla ?? SEM_DADO})`}</option>
                      {linhas.map((l) => <option key={l.projeto_id} value={l.projeto_id}>À mão: {l.sigla}</option>)}
                    </FilterSelect>
                  </Td>
                </Tr>
              ))}
            </tbody>
          </DataTable>
        )}
    </SectionCard>
  );
}
