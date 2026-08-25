'use client';

import { forwardRef, useEffect, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';

/** Barra de ferramentas — agrupa busca, filtros e ações com espaçamento consistente. */
export function Toolbar({ children, className = '' }: { children: React.ReactNode; className?: string }) {
  return <div className={`flex flex-wrap items-center gap-2 ${className}`}>{children}</div>;
}

const inputCls =
  'w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg)] placeholder:text-[var(--fg-3)] ' +
  'px-3 py-2 text-sm transition-colors focus:border-[var(--border-accent)] disabled:opacity-50';

/** Filtro de múltipla seleção (checkboxes). Recebe/retorna array de valores. */
export function MultiSelect({ values, onChange, placeholder, options, className = '' }: {
  values: string[];
  onChange: (v: string[]) => void;
  placeholder: string;
  options: { value: string; label: string }[];
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const onDoc = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false); };
    document.addEventListener('mousedown', onDoc);
    return () => document.removeEventListener('mousedown', onDoc);
  }, []);
  const toggle = (val: string) => onChange(values.includes(val) ? values.filter((v) => v !== val) : [...values, val]);
  const allSelected = options.length > 0 && values.length === options.length;
  const texto = values.length === 0 ? placeholder
    : values.length === 1 ? (options.find((o) => o.value === values[0])?.label ?? values[0])
    : `${values.length} selecionados`;
  return (
    <div ref={ref} className={`relative ${className}`}>
      <button type="button" onClick={() => setOpen((o) => !o)} className={`${inputCls} flex items-center justify-between gap-2 min-w-[160px] cursor-pointer ${values.length ? '!text-[var(--fg)]' : '!text-[var(--fg-2)]'}`}>
        <span className="truncate">{texto}</span>
        <span className="shrink-0 text-[var(--fg-3)]"><Icon name="chevron-down" size={14} /></span>
      </button>
      {open && (
        <div className="absolute left-0 z-30 mt-1 w-max min-w-full max-w-[280px] max-h-64 overflow-auto rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-2)] shadow-[var(--shadow-lg)] p-1">
          {options.length > 0 && (
            <div className="flex items-center gap-3 px-2 py-1">
              {!allSelected && (
                <button type="button" onClick={() => onChange(options.map((o) => o.value))} className="text-[11px] font-semibold text-[var(--accent)] hover:underline">Selecionar todas</button>
              )}
              {values.length > 0 && (
                <button type="button" onClick={() => onChange([])} className="text-[11px] font-semibold text-[var(--accent)] hover:underline">Limpar seleção</button>
              )}
            </div>
          )}
          {options.length === 0 && <div className="px-2 py-1.5 text-sm text-[var(--fg-3)]">Sem opções</div>}
          {options.map((o) => (
            <label key={o.value} className="flex items-center gap-2 px-2 py-1.5 rounded-[var(--r-sm)] text-sm text-[var(--fg-2)] hover:bg-[var(--surface-3)] cursor-pointer">
              <input type="checkbox" checked={values.includes(o.value)} onChange={() => toggle(o.value)} className="accent-[var(--accent)]" />
              <span className="truncate">{o.label}</span>
            </label>
          ))}
        </div>
      )}
    </div>
  );
}

/** Campo de busca com ícone (paridade .search-wrap / .search-icon).
 *
 *  O botão de limpar mora AQUI, e não em cada tela, porque globals.css suprime
 *  o "x" NATIVO do input[type=search] em todo o app (o nativo não tem rótulo
 *  acessível e empilhava com botões próprios). Uma vez suprimido o nativo, o
 *  substituto tem que nascer no componente compartilhado — senão cada tela que
 *  esquecer de desenhar o seu fica sem nenhuma forma de limpar a busca.
 *
 *  O botão aparece quando há texto E o chamador passou `onLimpar` — sem ele,
 *  o botão não é desenhado (melhor nenhum botão que um botão inerte). `dica`
 *  desenha um <kbd> no lugar dele enquanto o campo está vazio, para telas que
 *  anunciam atalho de teclado. */
export const SearchInput = forwardRef<
  HTMLInputElement,
  React.InputHTMLAttributes<HTMLInputElement> & { dica?: string; onLimpar?: () => void }
>(function SearchInput({ className = '', dica, onLimpar, ...rest }, ref) {
  const interno = useRef<HTMLInputElement>(null);
  const temTexto = String(rest.value ?? '') !== '';

  // `onLimpar` explícito, sem sintetizar evento de input pelo setter nativo do
  // prototype: aquele truque funciona, mas depende de detalhe interno de como
  // o React intercepta `value` — é o tipo de código que quebra em silêncio numa
  // atualização de versão e ninguém liga o defeito à causa. O chamador já tem
  // o setter do próprio estado; pedir uma linha a ele é mais barato que manter
  // um truque frágil no componente compartilhado.
  const limpar = () => {
    onLimpar?.();
    interno.current?.focus();
  };

  return (
    <div className="relative min-w-[200px] flex-1">
      <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-[var(--fg-3)]"><Icon name="search" size={15} /></span>
      <input
        ref={mesclarRefs(ref, interno)}
        type="search"
        className={`${inputCls} pl-8 ${(temTexto && onLimpar) || dica ? 'pr-9' : ''} ${className}`}
        {...rest}
      />
      {temTexto && onLimpar ? (
        <button
          type="button"
          onClick={limpar}
          aria-label="Limpar busca"
          className="absolute right-1.5 top-1/2 flex h-7 w-7 -translate-y-1/2 items-center justify-center rounded-[var(--r-sm)] text-[var(--fg-3)] transition-colors hover:bg-[var(--surface-2)] hover:text-[var(--fg)] focus-visible:ring-2"
        >
          <Icon name="x" size={14} />
        </button>
      ) : dica ? (
        <kbd
          aria-hidden
          className="pointer-events-none absolute right-2.5 top-1/2 -translate-y-1/2 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-2)] px-1.5 py-0.5 text-[10px] font-semibold text-[var(--fg-4)]"
        >
          {dica}
        </kbd>
      ) : null}
    </div>
  );
});

/** Encaminha o mesmo nó para o ref do chamador e para o ref interno. */
function mesclarRefs<T>(externo: React.Ref<T> | undefined, interno: React.RefObject<T | null>) {
  return (no: T | null) => {
    interno.current = no;
    if (typeof externo === 'function') externo(no);
    else if (externo) (externo as React.MutableRefObject<T | null>).current = no;
  };
}

/**
 * Input de texto padrão do design system.
 * `revealable`: em campos de senha, mostra um botão de olho para alternar
 * a visibilidade do valor digitado. O `ref` permanece no <input>.
 */
export const Input = forwardRef<
  HTMLInputElement,
  React.InputHTMLAttributes<HTMLInputElement> & { revealable?: boolean }
>(function Input({ className = '', revealable = false, type, ...rest }, ref) {
  const [show, setShow] = useState(false);
  if (!revealable) {
    return <input ref={ref} type={type} className={`${inputCls} ${className}`} {...rest} />;
  }
  const isPassword = type === 'password';
  return (
    <div className="relative">
      <input
        ref={ref}
        type={isPassword && show ? 'text' : type}
        className={`${inputCls} pr-10 ${className}`}
        {...rest}
      />
      <button
        type="button"
        onClick={() => setShow((s) => !s)}
        aria-label={show ? 'Ocultar senha' : 'Mostrar senha'}
        aria-pressed={show}
        tabIndex={-1}
        className="absolute right-2 top-1/2 -translate-y-1/2 grid place-items-center rounded-[var(--r-sm)] p-1 text-[var(--fg-3)] transition-colors hover:text-[var(--fg)]"
      >
        <Icon name={show ? 'eye-off' : 'eye'} size={16} />
      </button>
    </div>
  );
});

/** Select com chevron custom (paridade .filter-select). */
export const FilterSelect = forwardRef<HTMLSelectElement, React.SelectHTMLAttributes<HTMLSelectElement>>(
  function FilterSelect({ className = '', children, ...rest }, ref) {
    return (
      <div className="relative">
        <select
          ref={ref}
          className={`${inputCls} appearance-none pr-8 cursor-pointer ${className}`}
          {...rest}
        >
          {children}
        </select>
        <span className="pointer-events-none absolute right-2 top-1/2 -translate-y-1/2 text-[var(--fg-3)]"><Icon name="chevron-down" size={14} /></span>
      </div>
    );
  },
);

/** Switch (paridade .toggle/.toggle-slider). Controlado. */
export function Toggle({ checked, onChange, label, disabled }: {
  checked: boolean; onChange: (v: boolean) => void; label?: string; disabled?: boolean;
}) {
  return (
    <label className={`inline-flex items-center gap-2 select-none ${disabled ? 'opacity-50' : 'cursor-pointer'}`}>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => !disabled && onChange(!checked)}
        className="relative inline-flex shrink-0 rounded-[var(--r-pill)] transition-colors duration-150"
        style={{ width: 38, height: 21, background: checked ? 'var(--accent)' : 'var(--surface-4)' }}
      >
        <span
          className="absolute top-0.5 rounded-full bg-white transition-transform duration-150"
          style={{ width: 17, height: 17, left: 2, transform: checked ? 'translateX(17px)' : 'translateX(0)' }}
        />
      </button>
      {label && <span className="text-sm text-[var(--fg-2)]">{label}</span>}
    </label>
  );
}
