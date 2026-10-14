/**
 * Lista de disparo da Black (live da consultoria), de hora em hora.
 * Planilha: "[BLACK FRIDAY/26] LISTA DISPARO LIVE CONSULTORIA 13/10" (abas "Lista" e "Telefone fora do padrao").
 * PROJETO SEPARADO (script.google.com > Novo projeto), dono só o Victor: não fica preso à planilha, então quem edita a
 * planilha não vê a chave nem mexe no código que o gatilho roda (pentester 13/10). Permissões fixas em appsscript.json.
 * Docs: docs/dashboard-black/README.md, seção "Lista de disparo automática".
 * Migration: infra/supabase/migrations/20261013174100_dados_black_lista_disparo.sql.
 *
 * DESLIGADO (14/10/2026, migration 20261014010100): public.black_lista_disparo não é mais executável por anon; este
 * script receberia erro de permissão. Nunca foi ligado. Religar exige migration nova (grant a anon) com ok do Victor.
 *
 * Fluxo: lê public.black_lista_disparo (anon key + chave própria, em Script Properties) → tira a Turma Especial
 * (planilha da Isabela, aba Página1, por e-mail ou telefone) → regrava as duas abas, mantendo o cabeçalho.
 * Sem service_role. Nenhum dado pessoal vai para o log: só contagens.
 *
 * Instalação (uma vez, pelo Victor):
 *   1. script.google.com > Novo projeto; colar este arquivo e o appsscript.json (Configurações > mostrar manifesto).
 *   2. Configurações do projeto > Propriedades do script: SUPABASE_URL e SUPABASE_ANON (a anon key é pública).
 *   3. Rodar `instalar` e autorizar. Ele gera a chave, guarda nas Propriedades e mostra no log SÓ o sha256 dela
 *      (não é segredo). Mandar esse sha256 para o Galego/Maestro, que grava em dados.black_lista_config.
 *   4. Depois do ok de que o hash foi gravado, rodar `ligar`: cria o gatilho de hora em hora e roda a 1ª atualização.
 */

const PLANILHA_ID = '1Ym6Lq6y228Xgipn6JAVgCOH6pHmkXKZFxNfd2j3yjEo';
const TURMA_ESPECIAL_ID = '1fLrJL4EkIQHwuhM-Fj_kXT8oojH7hZbsBBoGjsWUmH0';
const TURMA_ESPECIAL_ABA = 'Página1';
const ABA_LISTA = 'Lista';
const ABA_FORA = 'Telefone fora do padrao';
const QUEDA_MAXIMA = 0.5; // a lista nova menor que metade da atual: não grava (fonte quebrada não apaga a lista)

function instalar() {
  const props = PropertiesService.getScriptProperties();
  const chave = (Utilities.getUuid() + Utilities.getUuid()).replace(/-/g, ''); // 64 hex, 244 bits aleatórios
  props.setProperty('LISTA_CHAVE', chave);
  const hash = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, chave, Utilities.Charset.UTF_8)
    .map((b) => ('0' + (b & 0xff).toString(16)).slice(-2)).join('');
  console.log('sha256 da chave (mandar para o Galego/Maestro): ' + hash);
}

function ligar() {
  ScriptApp.getProjectTriggers()
    .filter((t) => t.getHandlerFunction() === 'atualizar')
    .forEach((t) => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('atualizar').timeBased().everyHours(1).create();
  atualizar();
}

function atualizar() {
  const trava = LockService.getScriptLock();
  if (!trava.tryLock(30000)) return;
  try {
    const props = PropertiesService.getScriptProperties();
    const url = props.getProperty('SUPABASE_URL');
    const anon = props.getProperty('SUPABASE_ANON');
    const chave = props.getProperty('LISTA_CHAVE');
    if (!url || !anon || !chave) throw new Error('Propriedades do script incompletas: ver a instalação no topo');

    const resp = UrlFetchApp.fetch(url + '/rest/v1/rpc/black_lista_disparo', {
      method: 'post',
      contentType: 'application/json',
      headers: { apikey: anon, Authorization: 'Bearer ' + anon },
      payload: JSON.stringify({ p_chave: chave }),
      muteHttpExceptions: true,
    });
    if (resp.getResponseCode() !== 200) throw new Error('banco respondeu HTTP ' + resp.getResponseCode());
    let dados;
    try { dados = JSON.parse(resp.getContentText()); } catch (e) { throw new Error('resposta do banco não é JSON'); }
    if (!dados || !Array.isArray(dados.pessoas) || !dados.resumo) throw new Error('resposta do banco sem pessoas');

    // Turma Especial: e-mail (minúsculo) ou telefone (8 últimos dígitos de DDD + Número). Documento não casa: nenhuma
    // fonte da lista tem CPF (formulários da Black e Respondi da consultoria não pedem).
    const te = turmaEspecial();
    const naTurma = (p) =>
      (p.emails || []).some((e) => te.emails.has(String(e).toLowerCase())) ||
      (p.fones8 || []).some((f) => te.fones8.has(String(f)));

    const lista = [];
    const fora = [];
    let tirados = 0;
    for (const p of dados.pessoas) {
      if (naTurma(p)) { tirados++; continue; }
      if (p.aba === 'fora') fora.push([p.nome, p.email, p.telefone_como_veio, p.motivo]);
      else lista.push([p.nome, p.email, p.telefone]);
    }

    const pl = SpreadsheetApp.openById(PLANILHA_ID);
    const abaLista = pl.getSheetByName(ABA_LISTA);
    const abaFora = pl.getSheetByName(ABA_FORA);
    if (!abaLista || !abaFora) throw new Error('aba da lista não encontrada');
    const atual = Math.max(abaLista.getLastRow() - 1, 0);
    if (atual > 0 && lista.length < atual * QUEDA_MAXIMA) {
      throw new Error('lista nova (' + lista.length + ') menor que metade da atual (' + atual + '): nada gravado');
    }
    gravar(abaLista, lista, 3);
    gravar(abaFora, fora, 4);

    const r = {
      em: new Date().toISOString(), pessoas_banco: dados.pessoas.length, turma_especial: tirados,
      lista: lista.length, fora_do_padrao: fora.length, resumo: dados.resumo,
    };
    props.setProperty('ULTIMA_EXECUCAO', JSON.stringify(r));
    console.log(JSON.stringify(r));
  } finally {
    trava.releaseLock();
  }
}

function turmaEspecial() {
  const v = SpreadsheetApp.openById(TURMA_ESPECIAL_ID).getSheetByName(TURMA_ESPECIAL_ABA).getDataRange().getDisplayValues();
  const h = v[0].map((x) => String(x).trim().toLowerCase());
  const iMail = h.indexOf('e-mail');
  const iDdd = h.indexOf('ddd');
  const iNum = h.indexOf('número');
  if (iMail < 0 || iNum < 0) throw new Error('cabeçalho da Turma Especial mudou');
  const emails = new Set();
  const fones8 = new Set();
  for (const r of v.slice(1)) {
    const e = String(r[iMail] || '').trim().toLowerCase();
    if (e) emails.add(e);
    const f = (String(iDdd >= 0 ? r[iDdd] : '') + String(r[iNum] || '')).replace(/\D/g, '');
    if (f.length >= 8) fones8.add(f.slice(-8));
  }
  if (emails.size === 0) throw new Error('Turma Especial veio vazia: nada gravado');
  return { emails, fones8 };
}

// Regrava da linha 2 para baixo (o cabeçalho da linha 1 fica), tudo como texto (telefone não vira número).
function gravar(aba, linhas, colunas) {
  const ultima = aba.getLastRow();
  if (ultima > 1) aba.getRange(2, 1, ultima - 1, colunas).clearContent();
  if (!linhas.length) return;
  if (aba.getMaxRows() < linhas.length + 1) aba.insertRowsAfter(aba.getMaxRows(), linhas.length + 1 - aba.getMaxRows());
  const faixa = aba.getRange(2, 1, linhas.length, colunas);
  faixa.setNumberFormat('@');
  faixa.setValues(linhas.map((l) => l.map((x) => (x == null ? '' : String(x)))));
}
