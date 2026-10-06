'use client';

// Campo de número que guarda o texto enquanto a pessoa digita ("12,", "-", "1.500") e só entrega o número quando ele
// está completo. Antes, o modelo convertia a cada tecla: não dava para digitar vírgula nem dias negativos.
import { useState } from 'react';
import { Input } from '@/shared/ui/components';
import { lerNumeroBR, numeroParaCampo } from '../domain/numero';

type Props = Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'> & {
  valor: number | null;
  onValor: (n: number | null) => void;
  /** só inteiros (dias) */
  inteiro?: boolean;
};

export function CampoNumero({ valor, onValor, inteiro, onBlur, ...rest }: Props) {
  const [txt, setTxt] = useState(numeroParaCampo(valor));
  const [ultimo, setUltimo] = useState(valor);
  // o valor mudou por fora (ex.: linha reordenada): mostra o novo
  if (valor !== ultimo) {
    setUltimo(valor);
    if (lerNumeroBR(txt) !== valor) setTxt(numeroParaCampo(valor));
  }
  const invalido = txt.trim() !== '' && (lerNumeroBR(txt) === undefined || (inteiro && !Number.isInteger(lerNumeroBR(txt))));
  return (
    <Input
      {...rest}
      inputMode={inteiro ? 'numeric' : 'decimal'}
      value={txt}
      aria-invalid={invalido || undefined}
      onChange={(e) => {
        setTxt(e.target.value);
        const n = lerNumeroBR(e.target.value);
        if (n === undefined || (inteiro && n !== null && !Number.isInteger(n))) return;
        setUltimo(n);
        onValor(n);
      }}
      onBlur={(e) => { setTxt(numeroParaCampo(lerNumeroBR(txt) ?? valor)); onBlur?.(e); }}
    />
  );
}
