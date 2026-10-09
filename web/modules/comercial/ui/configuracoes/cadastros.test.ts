import { describe, expect, it } from 'vitest';
import { MOTIVOS_PADRAO } from '../../domain/catalogo';
import { FERRAMENTAS } from '../../domain/mcp-ferramentas';
import type { MotivoPerdaConfig, PreferenciasNotificacao } from '../../domain/types';
import { FERRAMENTAS_MCP, INTEGRACOES } from './integracoes';
import { alternarAtivo, ordenarMotivos, previaChave, rascunhoMotivo, resumoMotivos, validarMotivo } from './motivos';
import {
  alternarGatilho, definirSilencio, estadoPermissao, horaValida, preferenciasIguais, textoSilencio, validarPreferencias,
} from './preferencias';

const custom = (p: Partial<MotivoPerdaConfig> = {}): MotivoPerdaConfig => ({
  key: 'preco_alto', label: 'Preço alto', reativa: true, bloqueia: false, alertaGestor: false, nota: null, sistema: false, ativo: true, ...p,
});

describe('validarMotivo', () => {
  it('cria motivo novo com chave a partir do nome', () => {
    const r = validarMotivo({ ...rascunhoMotivo(), label: '  Preço acima do orçamento ', nota: ' ' }, MOTIVOS_PADRAO, null);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.motivo.key).toBe('preco_acima_do_orcamento');
      expect(r.motivo.label).toBe('Preço acima do orçamento');
      expect(r.motivo.nota).toBeNull();
      expect(r.motivo.sistema).toBe(false);
      expect(r.motivo.ativo).toBe(true);
    }
    expect(previaChave('Preço acima do orçamento')).toBe('preco_acima_do_orcamento');
  });

  it('recusa nome curto, repetido ou reativa + bloqueio', () => {
    expect(validarMotivo({ ...rascunhoMotivo(), label: 'ab' }, MOTIVOS_PADRAO, null).ok).toBe(false);
    expect(validarMotivo({ ...rascunhoMotivo(), label: 'sem interesse' }, MOTIVOS_PADRAO, null).ok).toBe(false);
    expect(validarMotivo({ ...rascunhoMotivo(), label: 'Sem-interesse' }, MOTIVOS_PADRAO, null).ok).toBe(false);
    expect(validarMotivo({ ...rascunhoMotivo(), label: 'Outro motivo', reativa: true, bloqueia: true }, MOTIVOS_PADRAO, null).ok).toBe(false);
  });

  it('de fábrica só muda a nota', () => {
    const fab = MOTIVOS_PADRAO[0];
    const r = validarMotivo({ ...rascunhoMotivo(fab), label: 'Outro nome', nota: 'Nova nota', reativa: true }, MOTIVOS_PADRAO, fab);
    expect(r).toEqual({ ok: true, motivo: { ...fab, nota: 'Nova nota' } });
  });

  it('edita personalizado mantendo chave e ativo', () => {
    const c = custom({ ativo: false });
    const r = validarMotivo({ ...rascunhoMotivo(c), label: 'Preço muito alto' }, [...MOTIVOS_PADRAO, c], c);
    expect(r.ok && r.motivo.key).toBe('preco_alto');
    expect(r.ok && r.motivo.ativo).toBe(false);
  });
});

describe('lista de motivos', () => {
  it('ordena ativos, fábrica primeiro, depois personalizados por nome', () => {
    const lista = [custom({ key: 'z', label: 'Zeta' }), ...MOTIVOS_PADRAO, custom({ key: 'a', label: 'Alfa' }), custom({ key: 'off', label: 'Antigo', ativo: false })];
    const o = ordenarMotivos(lista);
    expect(o[0].key).toBe(MOTIVOS_PADRAO[0].key);
    expect(o.slice(9, 11).map((m) => m.label)).toEqual(['Alfa', 'Zeta']);
    expect(o.at(-1)?.key).toBe('off');
  });

  it('resume e alterna ativo', () => {
    const lista = [...MOTIVOS_PADRAO, alternarAtivo(custom())];
    expect(resumoMotivos(lista)).toEqual({ ativos: 9, personalizados: 1, desativados: 1 });
  });
});

const prefs = (p: Partial<PreferenciasNotificacao> = {}): PreferenciasNotificacao => ({
  vendedorId: 'marcos', desktop: true, silencioInicio: null, silencioFim: null,
  gatilhos: { lead_novo: true, lead_respondeu: true, prazo_estourado: true, venda_aprovada: true, ficha_para_aprovar: false, atividade_vencendo: true },
  ...p,
});

describe('preferências de notificação', () => {
  it('liga o silêncio com o padrão e desliga zerando', () => {
    const on = definirSilencio(prefs(), true);
    expect(textoSilencio(on)).toBe('20:00 às 08:00');
    expect(textoSilencio(definirSilencio(on, false))).toBe('Desligado');
  });

  it('valida horário', () => {
    expect(horaValida('07:30')).toBe(true);
    expect(horaValida('24:00')).toBe(false);
    expect(validarPreferencias(prefs())).toBeNull();
    expect(validarPreferencias(prefs({ silencioInicio: '20:00', silencioFim: null }))).not.toBeNull();
    expect(validarPreferencias(prefs({ silencioInicio: '20:00', silencioFim: '20:00' }))).not.toBeNull();
  });

  it('compara rascunho com o salvo', () => {
    const a = prefs();
    expect(preferenciasIguais(a, structuredClone(a))).toBe(true);
    expect(preferenciasIguais(a, alternarGatilho(a, 'lead_novo', false))).toBe(false);
  });

  it('explica a permissão do navegador', () => {
    expect(estadoPermissao('granted').liberada).toBe(true);
    expect(estadoPermissao('default').podePedir).toBe(true);
    expect(estadoPermissao('denied').podePedir).toBe(false);
    expect(estadoPermissao('unsupported').liberada).toBe(false);
  });
});

describe('integrações', () => {
  it('cada card diz o que entra, o que sai e o risco', () => {
    for (const i of INTEGRACOES) {
      expect(i.entra && i.sai && i.risco).toBeTruthy();
    }
    expect(INTEGRACOES.map((i) => i.nome)).toEqual(expect.arrayContaining(['Unnichat', 'Manychat', 'MCP do Comercial', 'Instagram / Social selling']));
  });

  it('o MCP lista as 29 ferramentas reais, na ordem do servidor', () => {
    expect(INTEGRACOES.find((i) => i.nome === 'MCP do Comercial')?.ferramentas).toBe(FERRAMENTAS_MCP);
    expect(FERRAMENTAS_MCP).toHaveLength(29);
    expect(FERRAMENTAS_MCP.map((f) => f.nome)).toEqual(FERRAMENTAS.map((f) => f.name));
    expect(FERRAMENTAS_MCP.filter((f) => f.descricao.includes('(escreve;')).map((f) => f.nome))
      .toEqual(['comercial_criar_atividade', 'comercial_adicionar_nota', 'comercial_concluir_atividade', 'comercial_mover_etapa',
        'comercial_criar_contato', 'comercial_editar_contato', 'comercial_tag_adicionar', 'comercial_tag_remover', 'comercial_reabrir_atividade',
        'comercial_enviar_whatsapp', 'comercial_preencher_campos']);
    expect(FERRAMENTAS_MCP.filter((f) => f.descricao.includes('só consulta')).map((f) => f.nome))
      .toEqual(['comercial_numeros_whatsapp', 'comercial_templates_whatsapp', 'comercial_situacao_conversa']);
  });
});
