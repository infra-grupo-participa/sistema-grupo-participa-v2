'use client';

// Marketing > Mensageria: monta as 4 abas (Disparos · Por projeto · Números · Ferramentas).
// Projetos carregam uma vez. Depois de gravar, recarrega só o que a gravação mudou (ver `RECARGA`). As abas ficam montadas (escondidas
// com `hidden`): trocar de aba não refaz consulta e não perde o filtro. A lista de disparos só recarrega na
// aba visível (prop `ativo`, ver useListaDisparos). Identidade e "hoje" vêm do servidor, por prop.
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Loading, Tabs, Toast, idsAba, useFlash } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import type { Ferramenta, Numero } from '../domain/mensageria';
import { listarFerramentas, listarNumeros, listarProjetos } from './mensageria-data';
import { AbaDisparos } from './AbaDisparos';
import { AbaPorProjeto } from './AbaPorProjeto';
import { AbaNumeros } from './AbaNumeros';
import { AbaFerramentas } from './AbaFerramentas';
import { Erro } from './pecas';

type Aba = 'disparos' | 'projeto' | 'numeros' | 'ferramentas';

/**
 * O que cada gravação manda recarregar. `lista` = lista de disparos (só a aba visível busca; a escondida busca uma vez
 * ao voltar). Disparo muda o consumo de hoje dos números. Número e ferramenta aparecem pelo nome na lista de disparos;
 * ferramenta também aparece pelo nome em Números.
 */
type Gravacao = 'disparo' | 'numero' | 'ferramenta';
const RECARGA: Record<Gravacao, { numeros: boolean; ferramentas: boolean; lista: boolean }> = {
  disparo: { numeros: true, ferramentas: false, lista: true },
  numero: { numeros: true, ferramentas: false, lista: true },
  ferramenta: { numeros: true, ferramentas: true, lista: true },
};
const ABAS: { k: Aba; l: string }[] = [
  { k: 'disparos', l: 'Disparos' },
  { k: 'projeto', l: 'Por projeto' },
  { k: 'numeros', l: 'Números' },
  { k: 'ferramentas', l: 'Ferramentas' },
];
const ID_BASE = 'mensageria';

/** undefined = carregando; null = falhou (rede ou sem acesso); array = carregado (pode ser vazio). */
type Carga<T> = T[] | null | undefined;

export function MensageriaClient({ hoje, nomeUsuario }: { hoje: string; nomeUsuario: string }) {
  const [aba, setAba] = useState<Aba>('disparos');
  const [projetos, setProjetos] = useState<Carga<Projeto>>(undefined);
  const [ferramentas, setFerramentas] = useState<Carga<Ferramenta>>(undefined);
  const [numeros, setNumeros] = useState<Carga<Numero>>(undefined);
  const [vLista, setVLista] = useState(0);
  const [vNumeros, setVNumeros] = useState(0);
  const [vFerramentas, setVFerramentas] = useState(0);
  const { toast, flash } = useFlash();

  useEffect(() => {
    let vivo = true;
    listarProjetos().then((p) => { if (vivo) setProjetos(p); });
    return () => { vivo = false; };
  }, []);

  // Na recarga a lista anterior continua na tela até a nova chegar (sem piscar "Carregando").
  useEffect(() => {
    let vivo = true;
    listarFerramentas().then((f) => { if (vivo) setFerramentas(f); });
    return () => { vivo = false; };
  }, [vFerramentas]);
  useEffect(() => {
    let vivo = true;
    listarNumeros().then((n) => { if (vivo) setNumeros(n); });
    return () => { vivo = false; };
  }, [vNumeros]);

  const gravou = (g: Gravacao) => (msg: string) => {
    flash(msg);
    const o = RECARGA[g];
    if (o.numeros) setVNumeros((v) => v + 1);
    if (o.ferramentas) setVFerramentas((v) => v + 1);
    if (o.lista) setVLista((v) => v + 1);
  };

  if (projetos === undefined || ferramentas === undefined || numeros === undefined) return <Loading />;

  const listaProjetos = projetos ?? [];
  const listaFerramentas = ferramentas ?? [];
  const listaNumeros = numeros ?? [];

  return (
    <div className="max-w-7xl space-y-4">
      <Link href="/marketing" className="inline-flex items-center gap-1.5 text-sm text-[var(--accent)] hover:underline">
        <Icon name="arrow-left" size={14} /> Voltar para Marketing
      </Link>
      <div>
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Marketing · Mensageria</div>
        <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Mensageria</h1>
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          Registro dos disparos de WhatsApp, e-mail, SMS, ligação e grupos, com o retorno e o custo de cada um.
        </p>
      </div>

      {projetos === null && <Erro msg="Não foi possível carregar os projetos (erro de rede ou sem acesso). As listas de projeto ficam vazias." />}

      <Tabs tabs={ABAS} active={aba} onChange={(k) => setAba(k as Aba)} idBase={ID_BASE} label="Mensageria" />

      <Painel k="disparos" aba={aba}>
        <AbaDisparos
          hoje={hoje} nomeUsuario={nomeUsuario} projetos={listaProjetos} ferramentas={listaFerramentas} numeros={listaNumeros}
          ativo={aba === 'disparos'} versao={vLista} onGravou={gravou('disparo')}
        />
      </Painel>
      <Painel k="projeto" aba={aba}>
        <AbaPorProjeto hoje={hoje} projetos={listaProjetos} ativo={aba === 'projeto'} versao={vLista} />
      </Painel>
      <Painel k="numeros" aba={aba}>
        <AbaNumeros numeros={listaNumeros} falhou={numeros === null} projetos={listaProjetos} ferramentas={listaFerramentas} onGravou={gravou('numero')} />
      </Painel>
      <Painel k="ferramentas" aba={aba}>
        <AbaFerramentas ferramentas={listaFerramentas} falhou={ferramentas === null} onGravou={gravou('ferramenta')} />
      </Painel>

      <Toast>{toast}</Toast>
    </div>
  );
}

function Painel({ k, aba, children }: { k: Aba; aba: Aba; children: React.ReactNode }) {
  const ids = idsAba(ID_BASE, k);
  return (
    <div role="tabpanel" id={ids.panel} aria-labelledby={ids.tab} hidden={aba !== k} tabIndex={0}>
      {children}
    </div>
  );
}
