'use client';

// Carrega o registro já recortado pelo que a pessoa logada pode ver (regra em registro.ts).
import { useMemo } from 'react';
import type { FiltroLog, LogCrm } from '../../domain/types';
import { useEquipe } from '../comum';
import { repo, useDados } from '../repositorio';
import { escopoDoVendedor, visivelPara } from './registro';

export function useRegistroVisivel(filtro: FiltroLog) {
  const rLog = useDados(() => repo.log(filtro), [filtro]);
  const rNeg = useDados(() => repo.negocios());
  const equipe = useEquipe();
  const { sessao } = equipe;

  const visiveis = useMemo<LogCrm[] | null>(() => {
    if (!rLog.dados || !rNeg.dados || !sessao) return null;
    const escopo = escopoDoVendedor(rNeg.dados, sessao.vendedorId);
    return rLog.dados.filter((l) => visivelPara(l, sessao, escopo));
  }, [rLog.dados, rNeg.dados, sessao]);

  return {
    dados: visiveis,
    erro: rLog.erro ?? rNeg.erro,
    onTentar: () => { void rLog.recarregar(); void rNeg.recarregar(); },
    ...equipe,
  };
}
