// Edge mensageria-planilha (migration 20261011120000) testada SEM credencial e SEM Google real: a resposta do
// values:batchGet é simulada (dados inventados, no formato documentado da API). A regra de qual linha entra e como
// grava mora no banco (mkt_mensageria.planilha_sync_receber) e é provada no ensaio da migration.
import { describe, expect, it } from 'vitest';
import { contaDoSegredo, intervalo, lerAbas } from '../../../../../infra/supabase/functions/mensageria-planilha/planilha';

const resposta = (status: number, corpo: unknown) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

describe('intervalo', () => {
  it('cerca o nome da aba com aspas e dobra aspas internas', () => {
    expect(intervalo('LIGAÇÃO')).toBe("'LIGAÇÃO'!A1:AD2000");
    expect(intervalo("Aba d'água")).toBe("'Aba d''água'!A1:AD2000");
  });
});

describe('contaDoSegredo', () => {
  it('recusa segredo vazio, inválido ou incompleto', () => {
    expect(contaDoSegredo('')).toBeNull();
    expect(contaDoSegredo('não é base64')).toBeNull();
    expect(contaDoSegredo(btoa(JSON.stringify({ client_email: 'x@y' })))).toBeNull();
  });
  it('aceita a conta completa', () => {
    const sa = { client_email: 'teste@exemplo.iam.gserviceaccount.com', private_key: 'k', token_uri: 'https://t' };
    expect(contaDoSegredo(btoa(JSON.stringify(sa)))).toEqual(sa);
  });
});

describe('lerAbas', () => {
  it('pede todas as abas numa chamada, com valores formatados, e devolve na ordem pedida', async () => {
    let url = '';
    const buscar = async (u: string) => {
      url = u;
      return resposta(200, { valueRanges: [
        { range: 'API!A1:AD3', values: [['ETAPA', 'DATA'], ['TESTE', '09/10/2026', 3, null]] },
        { range: "'LIGAÇÃO'!A1:AD1", values: [['FASE']] },
      ] });
    };
    const abas = await lerAbas('PLANILHA_TESTE', ['API', 'LIGAÇÃO'], 'tok', buscar);
    const qs = new URL(url).searchParams;
    expect(qs.getAll('ranges')).toEqual(["'API'!A1:AD2000", "'LIGAÇÃO'!A1:AD2000"]);
    expect(qs.get('valueRenderOption')).toBe('FORMATTED_VALUE');
    expect(abas).toEqual([
      { aba: 'API', valores: [['ETAPA', 'DATA'], ['TESTE', '09/10/2026', '3', '']] },
      { aba: 'LIGAÇÃO', valores: [['FASE']] },
    ]);
  });
  it('aba sem valores vem como lista vazia (o banco recusa pelo cabeçalho)', async () => {
    const abas = await lerAbas('P', ['GRUPO'], 'tok', async () => resposta(200, { valueRanges: [{ range: 'GRUPO!A1:AD2000' }] }));
    expect(abas).toEqual([{ aba: 'GRUPO', valores: [] }]);
  });
  it('aba que o Google não devolveu vira erro, sem misturar com a de outra', async () => {
    const abas = await lerAbas('P', ['API', 'SMS'], 'tok', async () => resposta(200, { valueRanges: [{ range: 'SMS!A1:AD1', values: [['FASE']] }] }));
    expect(abas).toEqual([{ aba: 'API', erro: 'aba_nao_veio' }, { aba: 'SMS', erro: 'aba_nao_veio' }]);
  });
  it('429 espera e tenta de novo; volta com dado se a cota liberar', async () => {
    const status = [429, 429, 200];
    const esperas: number[] = [];
    const abas = await lerAbas('P', ['API'], 'tok',
      async () => resposta(status.shift()!, { valueRanges: [{ range: 'API!A1:AD1', values: [['ETAPA']] }] }),
      [20, 40], async (ms) => { esperas.push(ms); });
    expect(esperas).toEqual([20, 40]);
    expect(abas).toEqual([{ aba: 'API', valores: [['ETAPA']] }]);
  });
  it('429 que não passa depois das tentativas vira erro com o código', async () => {
    let chamadas = 0;
    const abas = await lerAbas('P', ['API'], 'tok', async () => { chamadas++; return resposta(429, {}); }, [1, 1], async () => {});
    expect(chamadas).toBe(3);
    expect(abas).toEqual([{ aba: 'API', erro: 'google_429' }]);
  });
  it('erro HTTP do Google vira erro em todas as abas, só com o código', async () => {
    const abas = await lerAbas('P', ['API', 'GRUPO'], 'tok', async () => resposta(403, { error: { message: 'detalhe' } }));
    expect(abas).toEqual([{ aba: 'API', erro: 'google_403' }, { aba: 'GRUPO', erro: 'google_403' }]);
  });
});
