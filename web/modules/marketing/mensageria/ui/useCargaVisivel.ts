'use client';

import { useEffect, useState } from 'react';

/**
 * Busca só quando a aba fica visível pela 1ª vez; depois, de novo só quando `versao` sobe (gravação ou "Atualizar")
 * — e, se a aba estiver escondida nessa hora, uma vez ao voltar. Trocar de aba sem gravar não refaz consulta.
 * `carregar` precisa ser estável (função do módulo mensageria-data). Enquanto recarrega, `dados` é o anterior.
 */
export function useCargaVisivel<T>(carregar: () => Promise<T | null>, ativo: boolean, versao: number) {
  // null = a aba ainda não foi aberta: nenhuma consulta.
  const [vista, setVista] = useState<number | null>(null);
  // Ajuste durante o render (estado derivado da prop), como em useListaDisparos.
  if (ativo && vista !== versao) setVista(versao);
  const [res, setRes] = useState<{ v: number; r: T | null } | null>(null);
  useEffect(() => {
    if (vista == null) return;
    let vivo = true;
    carregar().then((r) => { if (vivo) setRes({ v: vista, r }); });
    return () => { vivo = false; };
  }, [carregar, vista]);
  return {
    /** undefined = carregando a 1ª vez; null = falhou (rede, sem acesso ou função ainda não existe no banco). */
    dados: res ? res.r : undefined,
    atualizando: vista != null && (!res || res.v !== vista),
  };
}
