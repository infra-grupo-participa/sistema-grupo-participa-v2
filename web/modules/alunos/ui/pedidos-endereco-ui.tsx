'use client';

// Bloco de endereço dos pedidos (pessoa nova na troca de sócio e "alterar dado" de endereço).
// País primeiro (padrão Brasil). Brasil: CEP com máscara e busca no ViaCEP (/api/cep), UF em lista fechada.
// Exterior: estado/província e CEP livres. `travado` = mostra o endereço de outra pessoa, cinza e sem edição.
import { useEffect, useRef, useState } from 'react';
import { ENDERECO_PARTES, PAISES_SUGERIDOS, UFS, ehBrasil, formatarCep, type Endereco, type ParteEndereco } from '../domain/pedidos-alteracao';
import { buscarCep } from './pedidos-alteracao-data';
import { FIELD_CLS, Rotulo } from './pedidos-alteracao-ui';

const TRAVADO_CLS = 'disabled:cursor-not-allowed disabled:bg-[var(--surface-2)] disabled:text-[var(--fg-3)] disabled:border-[var(--border-faint)]';
const ERRO_CLS = 'border-[var(--red-border)]';

export function ErroCampo({ id, msg }: { id: string; msg?: string | null }) {
  if (!msg) return null;
  return <p id={id} className="mt-1 text-xs text-[var(--red)]" role="alert">{msg}</p>;
}

const s = (v: unknown) => (v == null ? '' : String(v));

export function EnderecoCampos({ id, valor, onChange, erros = {}, travado = false, exemplos = null }: {
  id: string;
  valor: Endereco;
  onChange: (e: Endereco) => void;
  /** Mensagem por campo (validarEndereco().erros), mostrada ao lado do campo. */
  erros?: Partial<Record<ParteEndereco, string>>;
  travado?: boolean;
  /** Valores mostrados como exemplo (placeholder cinza) nos campos vazios. */
  exemplos?: Endereco | null;
}) {
  const br = ehBrasil(valor.pais);
  const [cepStatus, setCepStatus] = useState<'buscando' | 'nao_achou' | 'achou' | null>(null);
  const ultimoCep = useRef<string | null>(null);
  const valorRef = useRef(valor);
  useEffect(() => { valorRef.current = valor; });

  const set = (k: ParteEndereco, v: string) => onChange({ ...valor, [k]: v });
  const cepDig = s(valor.cep).replace(/\D/g, '');

  // CEP completo no Brasil: preenche logradouro, bairro, cidade e UF (tudo editável depois). Falhou: segue manual.
  useEffect(() => {
    if (travado || !br || cepDig.length !== 8 || ultimoCep.current === cepDig) return;
    ultimoCep.current = cepDig;
    let vivo = true;
    setCepStatus('buscando');
    buscarCep(cepDig).then((r) => {
      if (!vivo) return;
      if (!r) { setCepStatus('nao_achou'); return; }
      const atual = valorRef.current;
      onChange({
        ...atual,
        endereco_logradouro: r.logradouro || atual.endereco_logradouro,
        bairro: r.bairro || atual.bairro,
        cidade: r.cidade || atual.cidade,
        estado: (UFS as readonly string[]).includes(r.estado_uf) ? r.estado_uf : atual.estado,
      });
      setCepStatus('achou');
    });
    return () => { vivo = false; };
    // onChange muda a cada render do pai; a busca depende só do CEP.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cepDig, br, travado]);

  const ex = (k: ParteEndereco, padrao = '') => (travado ? '' : s(exemplos?.[k]) || padrao);
  const campo = (k: ParteEndereco, rotulo: string, extra: React.InputHTMLAttributes<HTMLInputElement> = {}, dica?: string) => (
    <label className="block" key={k}>
      <Rotulo dica={dica}>{rotulo}</Rotulo>
      <input
        id={`${id}-${k}`}
        className={`${FIELD_CLS} ${TRAVADO_CLS} ${erros[k] ? ERRO_CLS : ''}`}
        value={s(valor[k])}
        onChange={(e) => set(k, e.target.value)}
        disabled={travado}
        placeholder={ex(k)}
        aria-invalid={!!erros[k]}
        aria-describedby={erros[k] ? `${id}-${k}-erro` : undefined}
        {...extra}
      />
      <ErroCampo id={`${id}-${k}-erro`} msg={erros[k]} />
    </label>
  );
  const rotulos = Object.fromEntries(ENDERECO_PARTES.map((p) => [p.k, p.rotulo])) as Record<ParteEndereco, string>;

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-3 gap-y-2">
      <label className="block sm:col-span-2">
        <Rotulo dica={travado ? undefined : 'padrão Brasil; se mora fora, digite o país'}>País</Rotulo>
        <input
          id={`${id}-pais`}
          list={`${id}-paises`}
          className={`${FIELD_CLS} ${TRAVADO_CLS} ${erros.pais ? ERRO_CLS : ''}`}
          value={s(valor.pais)}
          onChange={(e) => set('pais', e.target.value)}
          disabled={travado}
          placeholder="Brasil"
          autoComplete="country-name"
        />
        <datalist id={`${id}-paises`}>
          <option value="Brasil" />
          {PAISES_SUGERIDOS.map((p) => <option key={p} value={p} />)}
        </datalist>
        <ErroCampo id={`${id}-pais-erro`} msg={erros.pais} />
      </label>

      <div className="block">
        {campo('cep', br ? 'CEP' : 'Código postal', {
          inputMode: br ? 'numeric' : 'text',
          autoComplete: 'postal-code',
          maxLength: br ? 9 : 20,
          onChange: (e) => set('cep', br ? formatarCep(e.target.value) : e.target.value),
          value: br ? formatarCep(s(valor.cep)) : s(valor.cep),
          placeholder: br ? (ex('cep') ? formatarCep(ex('cep')) : '00000-000') : ex('cep'),
        }, travado ? undefined : br ? 'preenche o endereço sozinho' : 'opcional')}
        {!travado && br && cepStatus === 'buscando' && <p className="mt-1 text-xs text-[var(--fg-3)]">Buscando o endereço do CEP…</p>}
        {!travado && br && cepStatus === 'nao_achou' && (
          <p className="mt-1 text-xs text-[var(--fg-3)]">Não achamos esse CEP. Preencha o endereço à mão.</p>
        )}
      </div>
      {campo('endereco_logradouro', br ? rotulos.endereco_logradouro : 'Endereço', { autoComplete: 'address-line1' })}
      {campo('endereco_numero', rotulos.endereco_numero, {}, !br && !travado ? 'opcional' : undefined)}
      {campo('endereco_complemento', rotulos.endereco_complemento, { autoComplete: 'address-line2' }, travado ? undefined : 'opcional')}
      {campo('bairro', rotulos.bairro, {}, !br && !travado ? 'opcional' : undefined)}
      {campo('cidade', rotulos.cidade, { autoComplete: 'address-level2' })}
      {br ? (
        <label className="block">
          <Rotulo>Estado (UF)</Rotulo>
          <select
            id={`${id}-estado`}
            className={`${FIELD_CLS} ${TRAVADO_CLS} ${erros.estado ? ERRO_CLS : ''} ${s(valor.estado) ? '' : 'text-[var(--fg-3)]'}`}
            value={(UFS as readonly string[]).includes(s(valor.estado).toUpperCase()) ? s(valor.estado).toUpperCase() : ''}
            onChange={(e) => set('estado', e.target.value)}
            disabled={travado}
            aria-invalid={!!erros.estado}
            aria-describedby={erros.estado ? `${id}-estado-erro` : undefined}
          >
            <option value="">{ex('estado') ? `Escolha a UF (ex.: ${ex('estado')})` : 'Escolha a UF'}</option>
            {UFS.map((u) => <option key={u} value={u}>{u}</option>)}
          </select>
          {s(valor.estado) && !(UFS as readonly string[]).includes(s(valor.estado).toUpperCase()) && !erros.estado && (
            <p className="mt-1 text-xs text-[var(--fg-3)]">Hoje está &quot;{s(valor.estado)}&quot;: escolha a UF na lista.</p>
          )}
          <ErroCampo id={`${id}-estado-erro`} msg={erros.estado} />
        </label>
      ) : (
        campo('estado', 'Estado ou província', { autoComplete: 'address-level1' }, travado ? undefined : 'opcional')
      )}
    </div>
  );
}
