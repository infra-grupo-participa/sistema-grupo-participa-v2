import { describe, expect, it } from 'vitest';
import {
  avisoExclusao, caminhoMidiaValido, conversasExcluiveis, erroMotivoExclusao, mensagensDoCanal, podeExcluirConversa,
} from './excluir-conversa';

describe('quem exclui conversa', () => {
  it('só o gestor', () => {
    expect(podeExcluirConversa({ papel: 'gestor' })).toBe(true);
    expect(podeExcluirConversa({ papel: 'vendedor' })).toBe(false);
    expect(podeExcluirConversa({ papel: 'leitor' })).toBe(false);
    expect(podeExcluirConversa(null)).toBe(false);
  });
});

describe('motivo', () => {
  it('obrigatório, de 5 a 300 caracteres sem contar espaço das pontas', () => {
    expect(erroMotivoExclusao('')).toMatch(/mínimo 5/);
    expect(erroMotivoExclusao('  abc  ')).toMatch(/mínimo 5/);
    expect(erroMotivoExclusao('teste')).toBeNull();
    expect(erroMotivoExclusao('mensagem de teste')).toBeNull();
    expect(erroMotivoExclusao('x'.repeat(301))).toMatch(/máximo 300/);
  });
});

describe('aviso do modal', () => {
  it('diz quantas mensagens e que o WhatsApp do cliente não muda', () => {
    expect(avisoExclusao(13)).toBe('A conversa e as 13 mensagens somem do CRM para todos. Não apaga nada no WhatsApp do cliente.');
    expect(avisoExclusao(1)).toMatch(/^A conversa e a 1 mensagem somem/);
    expect(avisoExclusao(1200)).toMatch(/1\.200 mensagens/);
  });
});

describe('qual conversa', () => {
  it('as do contato, uma por número; sem lista = nada a excluir', () => {
    expect(conversasExcluiveis({ conversas: [{ id: 'c1', canalId: 'of' }, { id: 'c2', canalId: 'qr' }] }).map((c) => c.id)).toEqual(['c1', 'c2']);
    expect(conversasExcluiveis({})).toEqual([]);
    expect(conversasExcluiveis(null)).toEqual([]);
  });
  it('conta as mensagens carregadas do número', () => {
    const ms = [{ canalId: 'of' }, { canalId: 'of' }, { canalId: 'qr' }, {}];
    expect(mensagensDoCanal(ms, 'of')).toBe(2);
    expect(mensagensDoCanal(ms, 'qr')).toBe(1);
    expect(mensagensDoCanal(ms, null)).toBe(1);
  });
});

describe('caminho de mídia que o servidor apaga', () => {
  it('aceita os dois formatos do bucket', () => {
    expect(caminhoMidiaValido('d8ef24ec-0976-4136-a8f3-a4088745a582/9b1c.jpg')).toBe(true);
    expect(caminhoMidiaValido('envio/bd5361bc-3c3f-4f85-8b5a-f21433d040e3/0f0e.pdf')).toBe(true);
  });
  it('recusa travessia, vazio e caractere estranho', () => {
    expect(caminhoMidiaValido('../outro/arquivo.jpg')).toBe(false);
    expect(caminhoMidiaValido('a//b.jpg')).toBe(false);
    expect(caminhoMidiaValido('/abs.jpg')).toBe(false);
    expect(caminhoMidiaValido('a b.jpg')).toBe(false);
    expect(caminhoMidiaValido('')).toBe(false);
    expect(caminhoMidiaValido(42)).toBe(false);
  });
});
