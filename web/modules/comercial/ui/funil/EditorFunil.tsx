'use client';

// Editor de funil existente (modelo da Clint), por abas: dados gerais, etapas próprias, campanhas de entrada e
// distribuição. Funil novo nasce no assistente passo a passo (AssistenteFunil), que usa as mesmas seções.
// Só o gestor salva. As regras de validação são as de domain/funis.ts (o backend repete).
import { useMemo, useState } from 'react';
import { Button, ConfirmDialog, Drawer, Tabs } from '@/shared/ui/components';
import { validarFunil, type ProblemaFunil } from '../../domain/funis';
import type { Agrupador, Funil, Negocio, Vendedor } from '../../domain/types';
import { avisarMudanca, repo } from '../repositorio';
import {
  CAMPOS_GERAL, SecaoCampanhas, SecaoDistribuicao, SecaoEtapas, SecaoGeral, focarProblema, useEtapasAbertas,
} from './secoes-funil';

export { funilVazio } from './secoes-funil';

type Aba = 'geral' | 'etapas' | 'campanhas' | 'distribuicao';

/** Aba de cada campo de validação (para o "Ir para" dos avisos e o atalho do rodapé). */
const ABA_DO_CAMPO: Record<string, Aba> = { nome: 'geral', agrupador: 'geral', eventos: 'geral', etapas: 'etapas', distribuicao: 'distribuicao' };

export function EditorFunil({ inicial, agrupadores, vendedores, negociosDoFunil, onClose, onSalvo }: {
  inicial: Funil;
  agrupadores: Agrupador[];
  vendedores: Vendedor[];
  negociosDoFunil: Negocio[];
  onClose: () => void;
  onSalvo: (funilId: string, msg: string) => void;
}) {
  const [f, setF] = useState<Funil>(() => structuredClone(inicial));
  const [aba, setAba] = useState<Aba>('geral');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [arquivar, setArquivar] = useState(false);
  const [novoAgrupador, setNovoAgrupador] = useState<string | null>(null);
  const { abertas, alternar } = useEtapasAbertas();
  const problemas = useMemo(() => validarFunil(f, vendedores), [f, vendedores]);
  const doCampo = (campos: string[]) => problemas.filter((p) => campos.includes(p.campo));

  const set = (p: Partial<Funil>) => setF((x) => ({ ...x, ...p }));
  /** Leva ao campo do problema: troca de aba, abre a etapa citada e põe o foco no campo. */
  const irParaProblema = (p: ProblemaFunil) => {
    setAba(ABA_DO_CAMPO[p.campo] ?? 'geral');
    focarProblema(p, f, (id) => alternar(id, true));
  };

  const salvar = async () => {
    setSalvando(true);
    setErro(null);
    let agrupadorId = f.agrupadorId;
    if (novoAgrupador !== null) {
      const r = await repo.criarAgrupador(novoAgrupador, f.produto);
      if (!r.ok || !r.agrupadorId) { setErro(r.msg ?? 'Não foi possível criar o agrupador.'); setSalvando(false); return; }
      agrupadorId = r.agrupadorId;
    }
    const r = await repo.salvarFunil({ ...f, agrupadorId });
    setSalvando(false);
    if (!r.ok || !r.funilId) { setErro(r.msg ?? 'Não foi possível salvar.'); return; }
    avisarMudanca();
    onSalvo(r.funilId, r.msg ?? 'Funil salvo.');
  };

  return (
    <>
      <Drawer
        onClose={onClose}
        width="max-w-5xl"
        title={`Editar funil · ${inicial.nome}`}
        subtitle="Etapas, campanhas de entrada e distribuição do funil."
        footer={<>
          <Button size="sm" variant="danger" onClick={() => setArquivar(true)}>Arquivar funil</Button>
          <span className="flex-1 min-w-0 text-xs">
            {erro ? (
              <span role="alert" className="text-[var(--red)]">{erro}</span>
            ) : problemas.length > 0 ? (
              <button type="button" onClick={() => irParaProblema(problemas[0])} className="text-[var(--fg-2)] hover:text-[var(--fg)] underline-offset-2 hover:underline">
                {problemas.length === 1 ? '1 pendência para salvar' : `${problemas.length} pendências para salvar`}
              </button>
            ) : null}
          </span>
          <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
          <Button size="sm" disabled={salvando || problemas.length > 0 || (novoAgrupador !== null && !novoAgrupador.trim())} onClick={salvar}>
            Salvar alterações
          </Button>
        </>}
      >
        <Tabs
          tabs={[
            { k: 'geral', l: 'Geral', n: doCampo(CAMPOS_GERAL).length },
            { k: 'etapas', l: `Etapas (${f.etapas.length})`, n: doCampo(['etapas']).length },
            { k: 'campanhas', l: `Campanhas (${f.campanhas.length})` },
            { k: 'distribuicao', l: 'Distribuição', n: doCampo(['distribuicao']).length },
          ]}
          active={aba}
          onChange={(k) => setAba(k as Aba)}
          label="Seções do funil"
        />

        {aba === 'geral' && (
          <SecaoGeral f={f} set={set} agrupadores={agrupadores} novoAgrupador={novoAgrupador} setNovoAgrupador={setNovoAgrupador}
            problemas={doCampo(CAMPOS_GERAL)} irPara={irParaProblema} />
        )}
        {aba === 'etapas' && (
          <SecaoEtapas f={f} set={set} negociosDoFunil={negociosDoFunil} abertas={abertas} alternarEtapa={alternar}
            problemas={doCampo(['etapas'])} irPara={irParaProblema} />
        )}
        {aba === 'campanhas' && <SecaoCampanhas f={f} set={set} />}
        {aba === 'distribuicao' && (
          <SecaoDistribuicao f={f} set={set} vendedores={vendedores} problemas={doCampo(['distribuicao'])} irPara={irParaProblema} />
        )}
      </Drawer>

      {arquivar && (
        <ConfirmDialog
          title="Arquivar funil"
          message={negociosDoFunil.some((n) => n.status === 'aberto') ? 'Este funil tem negócio aberto. Mova ou encerre os negócios antes de arquivar.' : 'O funil some da lista. Negócios encerrados continuam no histórico dos contatos.'}
          confirmLabel="Arquivar"
          danger
          onCancel={() => setArquivar(false)}
          onConfirm={async () => {
            const r = await repo.arquivarFunil(inicial.id);
            setArquivar(false);
            if (!r.ok) { setErro(r.msg ?? 'Não foi possível arquivar.'); return; }
            avisarMudanca();
            onSalvo('', r.msg ?? 'Funil arquivado.');
          }}
        />
      )}
    </>
  );
}
