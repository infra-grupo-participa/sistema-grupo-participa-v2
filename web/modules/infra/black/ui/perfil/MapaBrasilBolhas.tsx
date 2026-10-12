'use client';

// Mapa do Brasil com bolhas por estado (geometria do IBGE em domain/geo-brasil.ts). Estado = DDD do telefone,
// marcado na tela. Clicar na bolha ou no estado filtra o Perfil por aquela UF.
import { CONTORNO_BRASIL, UFS, VIEWBOX_BRASIL } from '../../domain/geo-brasil';
import { raioBolha } from '../../domain/perfil';
import { inteiro } from '../pecas';

export function MapaBrasilBolhas({ porUf, semUf, outros, selecionada, onSelect }: {
  porUf: ReadonlyMap<string, number>; semUf: number; outros: number; selecionada: string | null; onSelect: (uf: string) => void;
}) {
  const max = Math.max(0, ...porUf.values());
  const ordenadas = [...UFS].sort((a, b) => (porUf.get(b.sigla) ?? 0) - (porUf.get(a.sigla) ?? 0));
  return (
    <figure className="min-w-0">
      <figcaption className="mb-2 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]" title="Estado pelo DDD do telefone">
        Mapa por estado *
      </figcaption>
      <svg viewBox={`0 0 ${VIEWBOX_BRASIL.largura} ${VIEWBOX_BRASIL.altura}`} className="mx-auto block h-auto w-full max-w-md" role="img"
        aria-label={`Cadastros por estado: ${ordenadas.filter((u) => porUf.get(u.sigla)).map((u) => `${u.sigla} ${inteiro(porUf.get(u.sigla) ?? 0)}`).join(', ')}`}>
        <path d={CONTORNO_BRASIL} fill="var(--surface-3)" stroke="var(--border-strong)" strokeWidth="1" />
        {UFS.map((u) => (
          <path key={u.sigla} d={u.contorno} fill={selecionada === u.sigla ? 'var(--surface-4)' : 'transparent'} stroke="var(--border)" strokeWidth="0.6"
            className="cursor-pointer" onClick={() => onSelect(u.sigla)}>
            <title>{`${u.nome}: ${inteiro(porUf.get(u.sigla) ?? 0)}`}</title>
          </path>
        ))}
        {ordenadas.slice().reverse().map((u) => {
          const n = porUf.get(u.sigla) ?? 0;
          const r = raioBolha(n, max);
          const ativa = selecionada === u.sigla;
          return (
            <g key={u.sigla} className="cursor-pointer" onClick={() => onSelect(u.sigla)}>
              <title>{`${u.nome}: ${inteiro(n)}`}</title>
              {r > 0
                ? <circle cx={u.x} cy={u.y} r={r} fill="var(--accent)" fillOpacity={selecionada && !ativa ? 0.2 : 0.55} stroke={ativa ? 'var(--fg)' : 'var(--accent)'} strokeWidth={ativa ? 2 : 1} className="atm-historico-interativo" />
                : <circle cx={u.x} cy={u.y} r={1.8} fill="var(--fg-3)" />}
            </g>
          );
        })}
      </svg>
      <p className="mt-1 text-[11px] text-[var(--fg-3)]">
        * Estado pelo DDD do telefone. Sem DDD legível: {inteiro(semUf)}. DDD fora da tabela: {inteiro(outros)}.
      </p>
      {/* Versão em lista para leitor de tela e teclado. */}
      <ul className="sr-only">
        {ordenadas.filter((u) => porUf.get(u.sigla)).map((u) => (
          <li key={u.sigla}><button type="button" aria-pressed={selecionada === u.sigla} onClick={() => onSelect(u.sigla)}>{u.nome}: {inteiro(porUf.get(u.sigla) ?? 0)}</button></li>
        ))}
      </ul>
    </figure>
  );
}
