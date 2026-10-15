import { describe, expect, it } from 'vitest';
import { consertarNomeInterno, lerCsvStudio, normalizarTitulo, resumirStudio, tituloCombina, tituloDoNomeInterno } from './lives-studio';

const CAB = 'Posição na transmissão ao vivo (segundos),Espectadores simultâneos na transmissão,Mensagens do chat ao vivo,Média de espectadores simultâneos,Envolvimentos ao vivo,Reações';

describe('CSV do Studio', () => {
  it('lê as linhas e resume', () => {
    const r = lerCsvStudio(`${CAB}\n0,12,12,6,12,0\n60,161,9,138,9,2\n120,150,1,140,1,0\n`);
    expect(r.erros).toEqual([]);
    expect(r.linhas).toEqual([{ seg: 0, espectadores: 12, chat: 12, reacoes: 0 }, { seg: 60, espectadores: 161, chat: 9, reacoes: 2 }, { seg: 120, espectadores: 150, chat: 1, reacoes: 0 }]);
    expect(r.resumo).toEqual({ linhas: 3, pico: 161, picoSeg: 60, duracaoSeg: 180, ultimo: 150, chat: 22, reacoes: 2 });
  });
  it('aceita BOM e fim de linha do Windows', () => {
    expect(lerCsvStudio(`﻿${CAB}\r\n0,5,1,5,1,0\r\n`).linhas).toHaveLength(1);
  });
  it('recusa arquivo sem as colunas obrigatórias, linha inválida e segundo repetido', () => {
    expect(lerCsvStudio('a,b\n1,2').erros[0]).toContain('Falta a coluna');
    expect(lerCsvStudio(`${CAB}\n0,x,1,1,1,0`).erros[0]).toContain('não são números');
    expect(lerCsvStudio(`${CAB}\n0,1,1,1,1,0\n0,2,1,1,1,0`).erros[0]).toContain('repetem');
    expect(lerCsvStudio(CAB).erros[0]).toContain('não tem linhas');
  });
  it('chat ausente vira aviso (o banco deixa em branco), nunca erro calado', () => {
    const r = lerCsvStudio(`${CAB}\n0,5,,5,1,0\n`);
    expect(r.erros).toEqual([]);
    expect(r.avisos.join(' ')).toContain('sem número de chat');
    expect(r.avisos.join(' ')).toContain('fica em branco (sem dado)');
    expect(r.avisos.join(' ')).not.toContain('grava 0');
    expect(r.resumo?.chat).toBeNull();
    expect(r.resumo?.reacoes).toBe(0);
  });
  it('minuto com chat ausente fica fora da soma', () => {
    const r = lerCsvStudio(`${CAB}\n0,5,7,5,7,1\n60,6,,6,0,2\n120,6,3,6,3,\n`);
    expect(r.linhas[1].chat).toBeUndefined();
    expect(r.resumo?.chat).toBe(10);
    expect(r.resumo?.reacoes).toBe(3);
    expect(r.avisos.join(' ')).toContain('1 linha(s) sem número de chat');
    expect(r.avisos.join(' ')).toContain('1 linha(s) sem número de reações');
  });
  it('0 explícito no arquivo conta como 0, não como ausente', () => {
    const r = lerCsvStudio(`${CAB}\n0,5,0,5,0,0\n60,6,0,6,0,0\n`);
    expect(r.avisos).toEqual([]);
    expect(r.resumo?.chat).toBe(0);
    expect(r.resumo?.reacoes).toBe(0);
  });
  it('todos os minutos ausentes: total null (Sem dado), com a coluna presente ou ausente', () => {
    const vazio = lerCsvStudio(`${CAB}\n0,5,,5,0,\n60,6,,6,0,\n`);
    expect(vazio.resumo?.chat).toBeNull();
    expect(vazio.resumo?.reacoes).toBeNull();
    const semColuna = lerCsvStudio('Posição na transmissão ao vivo (segundos),Espectadores simultâneos na transmissão\n0,5\n');
    expect(semColuna.avisos.join(' ')).toContain('chat fica em branco (sem dado)');
    expect(semColuna.avisos.join(' ')).toContain('reações ficam em branco (sem dado)');
    expect(semColuna.resumo?.chat).toBeNull();
    expect(semColuna.resumo?.reacoes).toBeNull();
  });
  it('resumirStudio direto: ausente fora da soma e todos ausentes = null', () => {
    expect(resumirStudio([{ seg: 0, espectadores: 1, chat: 4 }, { seg: 60, espectadores: 2 }])?.chat).toBe(4);
    expect(resumirStudio([{ seg: 0, espectadores: 1 }, { seg: 60, espectadores: 2 }])?.chat).toBeNull();
    expect(resumirStudio([{ seg: 0, espectadores: 1, chat: 0 }])?.chat).toBe(0);
  });
});

describe('título do arquivo', () => {
  it('conserta o nome interno que veio byte a byte', () => {
    const mojibake = Array.from(new TextEncoder().encode('Transmissões ao vivo Naírio'), (b) => String.fromCharCode(b)).join('');
    expect(consertarNomeInterno(mojibake)).toBe('Transmissões ao vivo Naírio');
    expect(consertarNomeInterno('Já certo ✓')).toBe('Já certo ✓');
  });
  it('tira o prefixo do Studio e a extensão', () => {
    expect(tituloDoNomeInterno('liveViewership_Transmissões ao vivo Método Perfeito - Primeiro Pilar.csv')).toBe('Método Perfeito - Primeiro Pilar');
    expect(tituloDoNomeInterno('qualquer.csv')).toBeNull();
  });
  it('compara sem brigar com acento, pontuação e caixa', () => {
    expect(normalizarTitulo('Naírio  Augusto - 13/10')).toBe('nairioaugusto1310');
    expect(tituloCombina('Consultoria ao vivo com Joyce Nunes - 13/10', 'Consultoria ao vivo com Joyce Nunes e Naírio Augusto - 13/10')).toBe(false);
    expect(tituloCombina('Consultoria ao vivo com Joyce Nunes e Naírio Augusto - 13/10', 'Consultoria ao vivo com Joyce Nunes e Naírio Augusto - 13/10')).toBe(true);
    expect(tituloCombina('qualquer coisa longa aqui', null)).toBeNull();
  });
});
