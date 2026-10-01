import { describe, expect, it } from 'vitest';
import { TURMAS, mensagemErroServidor, queryDeclaracao, validarArquivoUpload, UPLOAD_MAX_BYTES } from './solicitar-placa-constants';

const arq = (name: string, type: string, size = 1000) => ({ name, type, size });

describe('validarArquivoUpload', () => {
  it('aceita pdf/jpg/png/webp até 10 MB', () => {
    expect(validarArquivoUpload(arq('a.pdf', 'application/pdf'))).toBeNull();
    expect(validarArquivoUpload(arq('a.jpg', 'image/jpeg'))).toBeNull();
    expect(validarArquivoUpload(arq('a.png', 'image/png'))).toBeNull();
    expect(validarArquivoUpload(arq('a.webp', 'image/webp', UPLOAD_MAX_BYTES))).toBeNull();
  });
  it('sem MIME (alguns Android) decide pela extensão', () => {
    expect(validarArquivoUpload(arq('a.JPEG', ''))).toBeNull();
    expect(validarArquivoUpload(arq('a.docx', ''))).toMatch(/Formato não aceito/);
  });
  it('HEIC do iPhone tem mensagem própria', () => {
    expect(validarArquivoUpload(arq('IMG_1.HEIC', 'image/heic'))).toMatch(/HEIC não é aceita/);
    expect(validarArquivoUpload(arq('IMG_1.heic', ''))).toMatch(/HEIC não é aceita/);
  });
  it('acima de 10 MB e vazio são recusados', () => {
    expect(validarArquivoUpload(arq('a.pdf', 'application/pdf', UPLOAD_MAX_BYTES + 1))).toMatch(/limite de 10 MB/);
    expect(validarArquivoUpload(arq('a.pdf', 'application/pdf', 0))).toMatch(/vazio/);
  });
});

describe('queryDeclaracao', () => {
  it('leva nivel_label e nivel_valor do domínio', () => {
    const q = new URLSearchParams(queryDeclaracao({ nome: 'Ana', nivel: 'ouro', cidade: 'Recife', estado_uf: 'PE' }));
    expect(q.get('nivel')).toBe('ouro');
    expect(q.get('nivel_label')).toBe('Ouro');
    expect(q.get('nivel_valor')).toBe('R$ 50.000');
    expect(q.get('nome')).toBe('Ana');
  });
  it('diamante vermelho', () => {
    const q = new URLSearchParams(queryDeclaracao({ nivel: 'diamante_vermelho' }));
    expect(q.get('nivel_label')).toBe('Diamante Vermelho');
    expect(q.get('nivel_valor')).toBe('R$ 5.000.000');
  });
  it('nível sem faixa de faturamento não manda valor', () => {
    expect(new URLSearchParams(queryDeclaracao({ nivel: 'pessoal' })).get('nivel_valor')).toBeNull();
  });
});

describe('mensagemErroServidor', () => {
  it('orienta por status', () => {
    expect(mensagemErroServidor(409, 'x')).toMatch(/já foi enviado/);
    expect(mensagemErroServidor(502)).toMatch(/Tente de novo em instantes/);
    expect(mensagemErroServidor(404)).toMatch(/Recuperar/);
    expect(mensagemErroServidor(403)).toMatch(/Recarregue/);
    expect(mensagemErroServidor(0)).toMatch(/internet/);
  });
  it('422 mantém o motivo específico do servidor', () => {
    expect(mensagemErroServidor(422, 'Informe o CEP.')).toBe('Informe o CEP.');
  });
});

describe('TURMAS (reserva)', () => {
  it('vai até T41', () => {
    expect(TURMAS[0]).toBe('T1');
    expect(TURMAS.at(-1)).toBe('T41');
  });
});
