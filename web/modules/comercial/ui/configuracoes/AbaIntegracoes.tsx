'use client';

// Aba #integracoes: painel real da Hotmart (só gestor) e um card por sistema (o que entra, o que sai, status e risco).
// Grade de cards, nada de tabela.
import { Badge, Card } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { Aviso } from '../comum';
import { MODO_DEMONSTRACAO } from '../repositorio';
import { INTEGRACOES, type Integracao } from './integracoes';
import { PainelHotmart } from './PainelHotmart';

export function AbaIntegracoes({ gestor, flash }: { gestor: boolean; flash: (m: string) => void }) {
  return (
    <div className="space-y-4">
      {gestor && <PainelHotmart gestor={gestor} flash={flash} />}
      <Aviso tom="neutral" icone="lock">
        {MODO_DEMONSTRACAO
          ? `Modo demonstração: nenhuma integração está ligada${gestor ? ' e os números da Hotmart acima são fictícios' : ''}.`
          : 'Mapa das integrações. O estado real da Hotmart fica no painel do gestor; a conexão com o Claude, na aba "Conectar ao Claude".'}
      </Aviso>
      <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        {INTEGRACOES.map((i) => <CardIntegracao key={i.nome} i={i} />)}
      </div>
    </div>
  );
}

function CardIntegracao({ i }: { i: Integracao }) {
  return (
    <Card className={`p-4 flex flex-col gap-3 min-w-0 ${i.ferramentas ? 'md:col-span-2 xl:col-span-3' : ''}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="flex items-center gap-3 min-w-0">
          <span className="w-8 h-8 shrink-0 grid place-items-center rounded-[var(--r-md)] bg-[var(--surface-3)] text-[var(--fg-2)]"><Icon name={i.icone} size={16} /></span>
          <div className="min-w-0">
            <h3 className="text-base font-semibold text-[var(--fg)] leading-tight">{i.nome}</h3>
            <div className="text-xs text-[var(--fg-3)]">{i.papel}</div>
          </div>
        </div>
        <span className="shrink-0"><Badge tone="neutral">{i.status}</Badge></span>
      </div>
      <dl className={`gap-x-6 gap-y-2 text-xs ${i.ferramentas ? 'grid md:grid-cols-2' : 'space-y-2'}`}>
        <div><dt className="font-medium text-[var(--fg-3)]">O que entra</dt><dd className="text-[var(--fg-2)] leading-relaxed">{i.entra}</dd></div>
        <div><dt className="font-medium text-[var(--fg-3)]">O que sai</dt><dd className="text-[var(--fg-2)] leading-relaxed">{i.sai}</dd></div>
      </dl>
      {i.ferramentas && (
        <div>
          <div className="mb-1.5 text-xs font-medium text-[var(--fg-3)]">Ferramentas que o servidor MCP expõe</div>
          <ul className="grid gap-x-6 gap-y-1.5 sm:grid-cols-2 xl:grid-cols-3">
            {i.ferramentas.map((f) => (
              <li key={f.nome} className="min-w-0 text-xs">
                <code className="text-[var(--fg)]">{f.nome}</code>
                <span className="block text-[var(--fg-2)] leading-relaxed">{f.descricao}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      <p className="mt-auto flex items-start gap-1.5 border-t border-[var(--border-faint)] pt-3 text-xs text-[var(--fg-3)] leading-relaxed">
        <Icon name="alert" size={13} className="mt-0.5 shrink-0" />
        <span><span className="sr-only">Risco: </span>{i.risco}</span>
      </p>
    </Card>
  );
}
