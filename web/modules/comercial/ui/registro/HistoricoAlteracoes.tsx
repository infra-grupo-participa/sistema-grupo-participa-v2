'use client';

// Aba "Alterações" das fichas (negócio, contato): o registro do CRM recortado para um negócio ou uma pessoa.
import { useMemo } from 'react';
import Link from 'next/link';
import { Carregando, EsqueletoLista, NotaRodape, Vazio } from '../comum';
import { useAgora } from '../repositorio';
import { ItemLog } from './ItemLog';
import { agruparPorDia } from './registro';
import { useRegistroVisivel } from './usar-registro';

export const NOTA_REGISTRO = 'No banco, o registro é gravado por trigger em toda escrita e não pode ser editado nem apagado pela tela.';

export function HistoricoAlteracoes({ entidadeId, contatoId }: { entidadeId?: string; contatoId?: string }) {
  const agora = useAgora(60_000);
  const filtro = useMemo(() => ({ entidadeId, contatoId, limite: 500 }), [entidadeId, contatoId]);
  const reg = useRegistroVisivel(filtro);

  return (
    <div className="space-y-4">
      <Carregando dados={reg.dados} erro={reg.erro} onTentar={reg.onTentar} esqueleto={<EsqueletoLista linhas={4} />}>
        {(logs) => logs.length === 0 ? (
          <Vazio icone="clipboard" titulo="Nenhuma alteração registrada" hint="Mover, editar, trocar dono, perder ou concluir aparece aqui com quem fez e quando." />
        ) : (
          <div className="space-y-4">
            {agruparPorDia(logs, agora).map((g) => (
              <section key={g.dia} aria-label={g.titulo}>
                <h3 className="mb-1 flex items-center justify-between text-xs font-semibold text-[var(--fg-3)]">
                  <span className="first-letter:uppercase">{g.titulo}</span>
                  <span className="tabular font-normal">{g.itens.length}</span>
                </h3>
                <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)]">
                  {g.itens.map((l) => <ItemLog key={l.id} l={l} nomeDe={reg.nomeDe} compacto />)}
                </ul>
              </section>
            ))}
          </div>
        )}
      </Carregando>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <NotaRodape className="flex-1 min-w-[200px]">{NOTA_REGISTRO}</NotaRodape>
        <Link href="/comercial/registro" className="text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:underline">
          Ver registro completo
        </Link>
      </div>
    </div>
  );
}
