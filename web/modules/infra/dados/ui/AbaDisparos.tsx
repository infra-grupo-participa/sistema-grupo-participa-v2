import { useState } from 'react';
import { CANAIS_DISPARO_ATM, type CanalDisparoAtm } from '@/modules/infra/atm/domain/dashboard';
import type { DisparoDetalheAtm, Linha, Resultado } from '@/modules/infra/atm/infrastructure/atm-data';
import { DisparosDetalhe } from '@/modules/infra/atm/ui/DisparosDetalhe';
import { EmptyState, KpiCard, SectionCard, Tabs } from '@/shared/ui/components';

const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });
const CARDS_CANAL = [['Disparos', 'disparos'], ['Enviados', 'enviados'], ['Entregues', 'entregues'], ['Lidas / atendidas', 'lidas'], ['Cliques', 'cliques'], ['Falhas', 'falhas'], ['Custo', 'custo_centavos']] as const;
const vazioDisparos: Resultado<DisparoDetalheAtm[]> = { data: [], semDado: true, erro: null };

function numero(valor: unknown): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  const n = Number(valor);
  return Number.isFinite(n) ? n : null;
}
// Os resumos do banco chamam o canal "API" de `whatsapp_api`; os demais usam o mesmo código da aba.
const nomeCanal = (canal: CanalDisparoAtm): string => canal === 'api' ? 'whatsapp_api' : canal;

/** Visão de disparos igual à do Seminário ATM e à das Ações da Black: abas por canal, 7 cards e a lista com o detalhe de cada disparo. */
export function AbaDisparos({ canais, lista, carregando, canalInicial = 'api' }: { canais: Resultado<Linha[]> | null; lista: Resultado<DisparoDetalheAtm[]> | null; carregando: boolean; canalInicial?: CanalDisparoAtm }) {
  const [canalAtivo, setCanalAtivo] = useState<CanalDisparoAtm>(canalInicial);
  if (carregando && !canais && !lista) return <p>Carregando disparos…</p>;
  const canalNome = nomeCanal(canalAtivo);
  const canal = canais?.data.find((item) => item.canal === canalNome);
  const erroCanal = canais?.erro;
  return <SectionCard title="Visão do disparo" subtitle="Filtre por canal e abra cada registro para consultar os detalhes, como no ATM.">
    <div className="mb-4">
      <Tabs label="Canal do disparo" active={canalAtivo} onChange={(k) => setCanalAtivo(k as CanalDisparoAtm)} tabs={CANAIS_DISPARO_ATM.map((item) => ({ k: item.canal, l: item.rotulo }))} />
    </div>
    {erroCanal && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{erroCanal}</p>}
    {canal ? <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{CARDS_CANAL.map(([rotulo, campo]) => { const n = numero(canal[campo]); const dinheiro = campo === 'custo_centavos'; return <KpiCard key={campo} label={rotulo} value={n === null ? 'Sem dado' : dinheiro ? moeda.format(n / 100) : inteiro.format(n)} hint={n === null ? 'sem dado ainda' : undefined} />; })}</div> : <div className="mb-3"><EmptyState title="Sem dados para este canal" hint="sem dado ainda" /></div>}
    <DisparosDetalhe result={lista ?? vazioDisparos} canal={canalNome} semFiltroPeriodo />
  </SectionCard>;
}
