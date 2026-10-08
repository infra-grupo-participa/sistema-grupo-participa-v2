'use client';

// Modo edição da ficha (aba Dados): nome, e-mail, telefone, cidade/UF, perfil, holding, empresa e observação.
// Grava pela crm_editar_contato (migration 20261008182832): a correção fica no CRM, por cima da base central, e a
// próxima ingestão não desfaz. Só as chaves que mudaram vão ao banco; o banco confere permissão e duplicidade de novo.
import { useMemo, useState } from 'react';
import { Button, FilterSelect, Input, Textarea } from '@/shared/ui/components';
import type { ComercialRepository, Resultado } from '../../application/ports';
import { ROTULO_ATUA, ROTULO_PERFIL } from '../../domain/catalogo';
import { LIMITES_EDICAO, mudancasEdicao, rascunhoDe, validarEdicao, type RascunhoEdicao } from '../../domain/editar-contato';
import type { AtuaComHolding, Contato, PerfilProfissional } from '../../domain/types';
import { Aviso, Campo } from '../comum';
import { avisarMudanca, repo } from '../repositorio';

/**
 * Escrita fora do contrato comum (como `criarContato`): o Supabase grava; a demonstração não.
 * Quando `editarContato` entrar em ports.ts (e no mock), este tipo some.
 */
type ComEdicao = ComercialRepository & {
  editarContato?: (contatoId: string, mudancas: Record<string, string>) => Promise<Resultado & { campos?: string[] }>;
};

export function FormEdicaoContato({ c, onSalvo, onCancelar }: {
  c: Contato;
  onSalvo: (msg: string) => void;
  onCancelar: () => void;
}) {
  const inicial = useMemo(() => rascunhoDe(c), [c]);
  const [r, setR] = useState<RascunhoEdicao>(inicial);
  const [tentou, setTentou] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const invalido = validarEdicao(r);
  const mudancas = mudancasEdicao(inicial, r);
  const nada = Object.keys(mudancas).length === 0;
  const fonte = repo as ComEdicao;

  const mudar = (k: keyof RascunhoEdicao) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
    setR((x) => ({ ...x, [k]: e.target.value }));
    setErro(null);
  };

  const salvar = async () => {
    setTentou(true);
    if (invalido || salvando) return;
    if (nada) { onCancelar(); return; }
    if (!fonte.editarContato) { setErro('Demonstração: a edição só grava no banco real.'); return; }
    setSalvando(true);
    const res = await fonte.editarContato(c.id, mudancas);
    setSalvando(false);
    if (!res.ok) { setErro(res.msg ?? 'Não foi possível salvar.'); return; }
    avisarMudanca();
    onSalvo(res.msg ?? 'Contato atualizado.');
  };

  return (
    <form
      className="space-y-3"
      onSubmit={(e) => { e.preventDefault(); void salvar(); }}
      onKeyDown={(e) => { if (e.key === 'Escape') { e.stopPropagation(); onCancelar(); } }}
      aria-label="Editar contato"
    >
      <Campo rotulo="Nome">
        <Input autoFocus value={r.nome} onChange={mudar('nome')} maxLength={LIMITES_EDICAO.nome} autoComplete="off" />
      </Campo>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Telefone (com DDD)" dica="Número novo entra como principal; o antigo fica guardado.">
          <Input type="tel" inputMode="tel" value={r.telefone} onChange={mudar('telefone')} placeholder="(11) 98765-4321" autoComplete="off" />
        </Campo>
        <Campo rotulo="E-mail">
          <Input type="email" value={r.email} onChange={mudar('email')} autoComplete="off" />
        </Campo>
      </div>
      <div className="grid gap-3 grid-cols-[1fr_5rem]">
        <Campo rotulo="Cidade">
          <Input value={r.cidade} onChange={mudar('cidade')} maxLength={LIMITES_EDICAO.cidade} autoComplete="off" />
        </Campo>
        <Campo rotulo="UF">
          <Input value={r.uf} onChange={mudar('uf')} maxLength={2} placeholder="SP" autoComplete="off" className="uppercase" />
        </Campo>
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Perfil">
          <FilterSelect value={r.perfil} onChange={mudar('perfil')}>
            <option value="">Não informado</option>
            {(Object.keys(ROTULO_PERFIL) as PerfilProfissional[]).map((k) => <option key={k} value={k}>{ROTULO_PERFIL[k]}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Holding">
          <FilterSelect value={r.atuaComHolding} onChange={mudar('atuaComHolding')}>
            <option value="">Não informado</option>
            {(Object.keys(ROTULO_ATUA) as AtuaComHolding[]).map((k) => <option key={k} value={k}>{ROTULO_ATUA[k]}</option>)}
          </FilterSelect>
        </Campo>
      </div>
      <Campo rotulo="Empresa / escritório">
        <Input value={r.empresa} onChange={mudar('empresa')} maxLength={LIMITES_EDICAO.empresa} autoComplete="off" />
      </Campo>
      <Campo rotulo="Observação" extra={<span className="tabular text-[var(--fg-3)]">{r.observacao.length}/{LIMITES_EDICAO.observacao}</span>}>
        <Textarea value={r.observacao} onChange={mudar('observacao')} maxLength={LIMITES_EDICAO.observacao} rows={3} />
      </Campo>
      <p className="text-[11px] text-[var(--fg-3)]">
        A correção vale no Comercial e não é desfeita pela próxima importação. Campo apagado volta ao dado da base.
      </p>
      {(erro || (tentou && invalido)) && <Aviso tom="danger" icone="alert">{erro ?? invalido}</Aviso>}
      <div className="flex justify-end gap-2">
        <Button type="button" variant="ghost" onClick={onCancelar} disabled={salvando}>Cancelar</Button>
        <Button type="submit" disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
      </div>
    </form>
  );
}
