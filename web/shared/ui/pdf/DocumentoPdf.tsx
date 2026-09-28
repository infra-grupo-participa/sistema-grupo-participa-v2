// Documento PDF de relatório com a identidade do Grupo Participa (A4 paisagem).
//
// Tom: documento de empresa, não formulário. Sem caixa, carimbo nem grade: texto
// grafite, um fio laranja sob o cabeçalho, tabela com zebra leve e fio fino.
// Cor, fonte e medida vêm TODAS de tema-pdf.ts (react-pdf não lê var(--token)).
//
// Este arquivo importa @react-pdf/renderer estaticamente: só pode ser carregado
// por `await import()` (gerar-pdf.ts), nunca por import de topo em tela — senão a
// lib entra no bundle da página (chunk medido no next build de 28/09: 1,22 MB, 443 KB gzip).
import { Document, Font, Page, Path, StyleSheet, Svg, Text, View } from '@react-pdf/renderer';
import type { DocumentoRelatorio, KpiPdf, SecaoPdf } from './modelo';
import { INDICADOR_NIVEL, dataHoraSaoPaulo } from './modelo';
import { larguraTabela, layoutTabela, linhasCabecalho, linhasCelula, paginar, textoCelula, type BlocoPagina } from './paginar';
import { COR_PDF, FONTE_PDF, MEDIDA_PDF } from './tema-pdf';
import { LOGO_LARANJA, LOGO_SILHUETA, LOGO_VIEWBOX } from './logo-pdf';

export interface RecursosPdf {
  /** Prefixo dos arquivos públicos (fontes): '/' no navegador, caminho de web/public/ no Node. */
  base: string;
}

let fontesRegistradas: string | null = null;

/** Registra o Inter uma vez por base. Hifenização desligada: nome e e-mail não se partem com hífen. */
export function registrarFontesPdf(base: string): void {
  if (fontesRegistradas === base) return;
  Font.register({
    family: FONTE_PDF.familia,
    fonts: FONTE_PDF.arquivos.map((f) => ({ src: `${base}${f.arquivo}`, fontWeight: f.peso })),
  });
  Font.registerHyphenationCallback((palavra) => [palavra]);
  fontesRegistradas = base;
}


const M = MEDIDA_PDF;
const s = StyleSheet.create({
  pagina: {
    fontFamily: FONTE_PDF.familia, fontSize: M.corpo, color: COR_PDF.texto, backgroundColor: COR_PDF.fundo,
    paddingTop: M.margemTopo, paddingBottom: M.margemBase, paddingHorizontal: M.margemX,
  },
  cabecalho: { position: 'absolute', top: 26, left: M.margemX, right: M.margemX },
  cabecalhoLinha: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-end' },
  gerado: { fontSize: M.rotulo + 0.5, color: COR_PDF.textoDiscreto },
  titulo: { fontSize: M.titulo, fontWeight: 600, marginTop: 10, color: COR_PDF.texto },
  recorte: { fontSize: M.corpo, color: COR_PDF.textoSecundario, marginTop: 3 },
  fioMarca: { marginTop: 8, height: 1, backgroundColor: COR_PDF.marca, width: 48 },
  rodape: {
    position: 'absolute', bottom: 18, left: M.margemX, right: M.margemX,
    flexDirection: 'row', justifyContent: 'space-between', fontSize: M.rodape, color: COR_PDF.textoDiscreto,
  },
  kpis: { flexDirection: 'row', marginBottom: 14 },
  kpi: { marginRight: 36 },
  kpiRotulo: { fontSize: M.rotulo, color: COR_PDF.textoSecundario, textTransform: 'uppercase', letterSpacing: 0.4 },
  kpiValor: { fontSize: M.kpiValor, fontWeight: 600, marginTop: 3 },
  secao: { marginBottom: 14 },
  secaoTitulo: { fontSize: M.secao, fontWeight: 600, marginBottom: 6 },
  secaoCont: { fontWeight: 400, color: COR_PDF.textoDiscreto },
  thLinha: { flexDirection: 'row', borderBottomWidth: 0.75, borderBottomColor: COR_PDF.fioForte },
  th: { fontWeight: 600, fontSize: M.rotulo + 0.5, color: COR_PDF.textoSecundario, paddingVertical: M.celulaPadY, paddingHorizontal: M.celulaPadX },
  tr: { flexDirection: 'row', borderBottomWidth: 0.5, borderBottomColor: COR_PDF.fio },
  trZebra: { backgroundColor: COR_PDF.zebra },
  td: { paddingVertical: M.celulaPadY, paddingHorizontal: M.celulaPadX },
  trTotal: { flexDirection: 'row', borderTopWidth: 0.75, borderTopColor: COR_PDF.fioForte },
  tdTotal: { fontWeight: 600 },
  vazio: { color: COR_PDF.textoSecundario, paddingVertical: 6 },
});

const direita = (tipo: string) => tipo === 'moeda' || tipo === 'numero';

/** Logo em vetor (ver logo-pdf.ts): um desenho por folha, sem imagem embutida. */
function Logo() {
  const { largura, altura } = LOGO_VIEWBOX;
  return (
    <Svg viewBox={`0 0 ${largura} ${altura}`} style={{ width: M.larguraLogo, height: (M.larguraLogo * altura) / largura }}>
      {LOGO_SILHUETA.map((d, i) => <Path key={`s${i}`} d={d} fill={COR_PDF.texto} />)}
      {LOGO_LARANJA.map((d, i) => <Path key={`l${i}`} d={d} fill={COR_PDF.marca} />)}
    </Svg>
  );
}

function Kpis({ kpis }: { kpis: KpiPdf[] }) {
  return (
    <View style={s.kpis} wrap={false}>
      {kpis.map((k) => (
        <View key={k.rotulo} style={s.kpi}>
          <Text style={s.kpiRotulo}>{k.rotulo}</Text>
          <Text style={s.kpiValor}>{k.valor}</Text>
        </View>
      ))}
    </View>
  );
}

function Tabela({ bloco }: { bloco: Extract<BlocoPagina, { tipo: 'secao' }> }) {
  const { secao } = bloco;
  // Larguras, corpo e quebra de linha vêm de paginar.ts: o texto chega já quebrado em
  // linhas que cabem (medidas com a métrica do Inter), igual ao que a paginação estimou.
  const layout = layoutTabela(secao);
  const { larguras, corpo, corpoTh, padX } = layout;
  const celula = (secaoAtual: SecaoPdf, valores: Record<string, string>, total = false) =>
    secaoAtual.colunas.map((c, i) => (
      <Text key={c.chave} style={[s.td, { width: larguras[i], paddingHorizontal: padX, textAlign: direita(c.tipo) ? 'right' : 'left' }, total ? s.tdTotal : {}]}>
        {linhasCelula(layout, i, textoCelula(valores, c, i, total), total ? 600 : 400).join('\n')}
      </Text>
    ));
  return (
    <View style={[s.secao, { width: larguraTabela(secao), fontSize: corpo }]}>
      <Text style={s.secaoTitulo}>
        {secao.titulo}{bloco.continuacao ? <Text style={s.secaoCont}> · continuação</Text> : null}
      </Text>
      <View style={s.thLinha} wrap={false}>
        {secao.colunas.map((c, i) => (
          <Text key={c.chave} style={[s.th, { width: larguras[i], paddingHorizontal: padX, fontSize: corpoTh, textAlign: direita(c.tipo) ? 'right' : 'left' }]}>
            {linhasCabecalho(layout, i, c.rotulo).join('\n')}
          </Text>
        ))}
      </View>
      {!secao.linhas.length && <Text style={s.vazio}>{secao.vazio ?? 'Nenhuma linha neste recorte.'}</Text>}
      {bloco.linhas.map(({ linha, indice }) => (
        <View key={indice} style={indice % 2 ? [s.tr, s.trZebra] : s.tr} wrap={false}>
          {celula(secao, linha.celulas)}
        </View>
      ))}
      {bloco.comTotal && secao.total && (
        <View style={s.trTotal} wrap={false}>{celula(secao, secao.total, true)}</View>
      )}
    </View>
  );
}

export function DocumentoPdf({ doc, recursos }: { doc: DocumentoRelatorio; recursos: RecursosPdf }) {
  if (!doc.protocolo) throw new Error('Documento sem protocolo: o PDF não é gerado.');
  registrarFontesPdf(recursos.base);
  const { data, hora } = dataHoraSaoPaulo(doc.emitidoEm);
  const folhas = paginar(doc.kpis, doc.secoes);
  const recorte = [...doc.recorte, INDICADOR_NIVEL[doc.nivel]].join('  ·  ');

  return (
    <Document title={`${doc.titulo} · ${doc.protocolo}`} author="Grupo Participa" creator="Sistema Grupo Participa" producer="Sistema Grupo Participa" language="pt-BR">
      {folhas.map((blocos, i) => (
        <Page key={i} size="A4" orientation="landscape" style={s.pagina}>
          <View style={s.cabecalho} fixed>
            <View style={s.cabecalhoLinha}>
              <Logo />
              <Text style={s.gerado}>Gerado em {data} {hora}</Text>
            </View>
            <Text style={s.titulo}>{doc.titulo}</Text>
            <Text style={s.recorte}>{recorte}</Text>
            <View style={s.fioMarca} />
          </View>

          {blocos.map((b, j) => (b.tipo === 'kpis' ? <Kpis key={j} kpis={b.kpis} /> : <Tabela key={j} bloco={b} />))}

          <View style={s.rodape} fixed>
            <Text>Emitido pelo Sistema Grupo Participa em {data} às {hora}  ·  Protocolo {doc.protocolo}</Text>
            <Text render={({ pageNumber, totalPages }) => `Página ${pageNumber} de ${totalPages}`} />
          </View>
        </Page>
      ))}
    </Document>
  );
}
