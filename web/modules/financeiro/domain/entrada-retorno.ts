// "Entrou por" / "Voltou em" do card e da ficha — função PURA.
//
// acao_nome = ação de ENTRADA (é por ela que o Resultado por ação conta; não muda).
// voltou_* (fn_fin_board, z75/z77) = COMPRA NOVA (sinal ou HM cheio) numa ação diferente da entrada,
// nos últimos 90 dias. Pagamento de saldo não é "voltar" (z77). Sem voltou_nome → só a linha de entrada.
// voltou_data é a data da AÇÃO de retorno (não a da compra) — a tela rotula assim.

/** Prefixo de turma do nome da ação ("T39 · Holding…") — mesmo corte de rotuloDaAcao (ui/TimelineAcoes). */
const TURMA = /^(T\d+(?:\.\d+)?) · /;

/** timestamptz → 'dd/mm' no fuso de São Paulo. Inválido/ausente → null. */
export function fmtDiaMes(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const soData = iso.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (soData) return `${soData[3]}/${soData[2]}`;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Sao_Paulo' });
}

export interface EntradaRetorno {
  /** "Entrou por <ação>" — null quando o card não tem ação de entrada. */
  entrou: string | null;
  /** "Voltou em <ação> · dd/mm" — null quando não houve compra nova em outra ação. */
  voltou: string | null;
  /** dd/mm da AÇÃO de retorno (voltou_data), para o rótulo "data da ação". null sem data. */
  voltouData: string | null;
}

export function entradaRetorno(c: {
  acao_nome?: string | null;
  voltou_nome?: string | null;
  voltou_data?: string | null;
}): EntradaRetorno {
  const entrou = c.acao_nome ? `Entrou por ${c.acao_nome.replace(TURMA, '')}` : null;
  let voltou: string | null = null;
  let voltouData: string | null = null;
  if (c.voltou_nome) {
    voltouData = fmtDiaMes(c.voltou_data);
    voltou = `Voltou em ${c.voltou_nome.replace(TURMA, '')}${voltouData ? ` · ${voltouData}` : ''}`;
  }
  return { entrou, voltou, voltouData };
}
