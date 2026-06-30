'use client';

/** Checkbox para multi-seleção (≠ Toggle/switch). Input nativo estilizado com accent. */
export function Checkbox({ checked, onChange, label, disabled, className = '' }: {
  checked: boolean; onChange: (v: boolean) => void; label?: React.ReactNode; disabled?: boolean; className?: string;
}) {
  return (
    <label className={`inline-flex items-center gap-2 select-none ${disabled ? 'opacity-50' : 'cursor-pointer'} ${className}`}>
      <input
        type="checkbox"
        checked={checked}
        disabled={disabled}
        onChange={(e) => onChange(e.target.checked)}
        className="w-4 h-4 rounded-[var(--r-sm)] accent-[var(--accent)] cursor-pointer disabled:cursor-not-allowed"
      />
      {label && <span className="text-sm text-[var(--fg-2)]">{label}</span>}
    </label>
  );
}
