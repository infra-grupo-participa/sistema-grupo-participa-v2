'use client';

// Carrega o registro em páginas do banco. Quem vê o quê é regra do banco (public.crm_log + policy de crm.log):
// a tela não baixa o registro dos outros para recortar aqui.
import { useCallback, useMemo, useState } from 'react';
import type { FiltroLog, LogCrm } from '../../domain/types';
import { useEquipe } from '../comum';
import { repo, useDados } from '../repositorio';
import { juntarPaginas, LIMITE_PAGINA } from './registro';

export function useRegistroVisivel(filtro: FiltroLog) {
  const chave = JSON.stringify(filtro);
  const rLog = useDados(() => repo.log({ ...filtro, limite: LIMITE_PAGINA }), [filtro]);
  const equipe = useEquipe();
  const [antigas, setAntigas] = useState<{ chave: string; linhas: LogCrm[]; temMais: boolean } | null>(null);
  const [carregandoMais, setCarregandoMais] = useState(false);
  const [erroMais, setErroMais] = useState<{ chave: string; msg: string } | null>(null);

  // Páginas e erro valem só para a busca (período) em que foram carregados.
  const atuais = antigas?.chave === chave ? antigas : null;
  const dados = useMemo<LogCrm[] | null>(
    () => (rLog.dados ? juntarPaginas(rLog.dados, atuais?.linhas ?? []) : null),
    [rLog.dados, atuais],
  );
  const temMais = atuais ? atuais.temMais : (rLog.dados?.length ?? 0) >= LIMITE_PAGINA;

  const carregarMais = useCallback(async () => {
    const ultima = dados?.[dados.length - 1];
    if (!ultima || carregandoMais) return;
    setCarregandoMais(true);
    setErroMais(null);
    try {
      const pagina = await repo.log({ ...filtro, limite: LIMITE_PAGINA, antes: ultima.id });
      setAntigas((a) => ({
        chave,
        linhas: [...(a?.chave === chave ? a.linhas : []), ...pagina],
        temMais: pagina.length >= LIMITE_PAGINA,
      }));
    } catch (e) {
      setErroMais({ chave, msg: e instanceof Error ? e.message : 'Não foi possível carregar as anteriores.' });
    } finally {
      setCarregandoMais(false);
    }
  }, [dados, carregandoMais, filtro, chave]);

  return {
    dados,
    erro: rLog.erro,
    onTentar: () => { void rLog.recarregar(); },
    temMais,
    carregarMais,
    carregandoMais,
    erroMais: erroMais?.chave === chave ? erroMais.msg : null,
    ...equipe,
  };
}
