import type { CepLookup } from '../application/ports';

/** Adapter do port CepLookup sobre o ViaCEP. Porta de app/api/cep.php. */
export class ViaCepLookup implements CepLookup {
  async buscar(cepRaw: string) {
    const cep = String(cepRaw ?? '').replace(/\D+/g, '');
    if (cep.length !== 8) return null;

    const resp = await fetch(`https://viacep.com.br/ws/${encodeURIComponent(cep)}/json/`, {
      headers: { Accept: 'application/json' },
      signal: AbortSignal.timeout(8000),
      redirect: 'manual',
    });
    if (!resp.ok) return null;

    const data = (await resp.json().catch(() => null)) as Record<string, unknown> | null;
    if (!data || data.erro) return null;

    return {
      cep: String(data.cep ?? cep),
      logradouro: String(data.logradouro ?? ''),
      bairro: String(data.bairro ?? ''),
      cidade: String(data.localidade ?? ''),
      estado_uf: String(data.uf ?? ''),
    };
  }
}
