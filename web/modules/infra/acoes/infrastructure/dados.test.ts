import { beforeEach, describe, expect, it, vi } from 'vitest';
import { dashboardAtmSemDado } from '@/modules/infra/atm/domain/dashboard';

const mocks = vi.hoisted(() => ({
  resumo: vi.fn(), serie: vi.fn(), canais: vi.fn(), disparos: vi.fn(), comparecimento: vi.fn(),
}));

vi.mock('@/modules/infra/atm/infrastructure/atm-data', () => ({
  carregarAtmResumo: mocks.resumo,
  carregarAtmSerie: mocks.serie,
  carregarAtmCanais: mocks.canais,
  carregarAtmDisparosLista: mocks.disparos,
  carregarAtmComparecimento: mocks.comparecimento,
}));

import { carregarDadosAcoesBlack } from './dados';

const ok = <T,>(data: T) => ({ data, semDado: false, erro: null });
const erroP0002 = { data: [], semDado: true, erro: 'Dashboard ou identificador não encontrado neste evento.' };
const acao = { id: 'thb-vencidos', nome: 'THB vencidos', estado: 'ativa' as const, etiqueta: 'black-thb-2026-10', origem: 'renovacao-thb-vencidos', ofertaHotmart: null };

describe('carregar dados das ações Black', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.resumo.mockResolvedValue(ok(dashboardAtmSemDado(acao.etiqueta)));
    mocks.serie.mockResolvedValue(ok([]));
    mocks.canais.mockResolvedValue(ok([]));
    mocks.disparos.mockResolvedValue(ok([]));
    mocks.comparecimento.mockResolvedValue(ok([]));
  });

  it('reutiliza as leituras do ATM com a etiqueta cadastrada e sem recorte de data', async () => {
    await carregarDadosAcoesBlack(acao);
    expect(mocks.resumo).toHaveBeenCalledWith('black-thb-2026-10');
    expect(mocks.serie).toHaveBeenCalledWith('black-thb-2026-10');
    expect(mocks.canais).toHaveBeenCalledWith('black-thb-2026-10');
    expect(mocks.disparos).toHaveBeenCalledWith('black-thb-2026-10');
    expect(mocks.comparecimento).toHaveBeenCalledWith('black-thb-2026-10');
  });

  it('não chama RPCs para abas sem etiqueta', async () => {
    await expect(carregarDadosAcoesBlack({ ...acao, estado: 'em breve', etiqueta: null })).resolves.toBeNull();
    expect(mocks.resumo).not.toHaveBeenCalled();
    expect(mocks.serie).not.toHaveBeenCalled();
  });

  it('traduz P0002 para estado em preparação, sem propagá-lo como erro de tela', async () => {
    mocks.resumo.mockResolvedValue(erroP0002);
    const resultado = await carregarDadosAcoesBlack(acao);
    expect(resultado?.emPreparacao).toBe(true);
    expect(resultado?.resumo.erro).toBeNull();
    expect(resultado?.resumo.semDado).toBe(true);
  });
});
