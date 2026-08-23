'use client';

// Rodapé de totais do board. Recalcula sobre o array filtrado —
// calcularTotais() é síncrono e puro, sem query nova ao trocar o filtro.
// semValorDefinido e perdaDetalhe SEMPRE aparecem quando > 0: dinheiro não
// pode sumir em silêncio atrás de um total arredondado.
//
// Redesign 2026-08-19: deixou de ser `sticky` sobre o board — problema 4 do
// Marcio (rodapé flutuando por cima cortava cards). Agora é um bloco normal
// no fluxo, abaixo da área de scroll das colunas — nunca sobrepõe conteúdo.
// Também deixa explícito se o total é do RECORTE filtrado ou da carteira
// inteira (problema 6): sem isso "5 card(s) no board" parecia contradizer os
// 305 cards somados nos chips da timeline de ações.
//
// Redesign 2026-08-19 (2ª passada — abas de produto): o recorte agora tem
// DOIS eixos (produto + canal), nunca só um. O rótulo do recorte vira
// "HM · Captação T40 — 45 cards" em vez de só o nome do canal — sem isso,
// trocar de aba de produto não deixava claro que os totais tinham mudado de
// universo. Cada KpiCard ganhou `title` com a definição do indicador (o que
// está fraco hoje: 4 números sem dizer o que significam) — não é tooltip
// decorativo, é a definição que já existe nos comentários de domain/totais.ts,
// só que invisível para quem usa a tela.
import { KpiCard } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL } from '@/shared/ui/format';
import type { Totais } from '../domain/totais';

export function RodapeTotais({ totais, totalCards, produtoAtivo, filtroAtivo }: {
  totais: Totais;
  totalCards: number;
  /** Rótulo do produto ativo (ex.: "Holding Masters", "Aurum") — sempre presente, é o 1º eixo do recorte. */
  produtoAtivo: string;
  /** Rótulo legível da ação/canal ativo na timeline (null = sem filtro de canal, ainda dentro do produto). */
  filtroAtivo: string | null;
}) {
  const recorte = filtroAtivo ? `${produtoAtivo} · ${filtroAtivo}` : produtoAtivo;
  return (
    <div className="gp-print-hide mt-3 pt-3 border-t border-[var(--border)]">
      <div className="mb-2 flex items-center gap-1.5 text-[11px] text-[var(--fg-3)]">
        <Icon name="alert" size={12} className="text-[var(--accent)]" />
        <span>
          Totais abaixo são só de <strong className="text-[var(--accent)] font-semibold">{recorte}</strong> —
          <strong className="tabular text-[var(--fg-2)] font-semibold"> {totalCards} </strong>card(s), não a carteira inteira.
        </span>
      </div>
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-2.5">
        <KpiCard
          label="Valor esperado"
          value={fmtBRL(totais.esperado)}
          bar="accent"
          hint="Em casa + na rua"
          title="VALOR ESPERADO = tudo que este recorte deve gerar de receita: o que já entrou (Em casa) mais o que ainda falta cobrar de quem segue vivo (Na rua). Não inclui a 2ª metade condicional."
        />
        <KpiCard
          label="Na rua"
          value={fmtBRL(totais.naRua)}
          bar="purple"
          hint={totais.reservas ? `${totais.reservas} reserva(s) de vaga inclusa(s)` : undefined}
          title="NA RUA = saldo a receber de contas vivas (não canceladas/reembolsadas). Inclui reserva de vaga (quem pagou só o sinal) — é dinheiro contratado, mesmo que ainda frágil."
        />
        <KpiCard
          label="Em casa"
          value={fmtBRL(totais.emCasa)}
          bar="green"
          hint={`líquido ${fmtBRL(totais.emCasaLiquido)}`}
          title="EM CASA = tudo que já foi pago (bruto), de todo mundo, inclusive contas mortas — dinheiro que entrou não deixa de ter entrado. O valor líquido (descontada taxa da Hotmart) aparece como referência."
        />
        <KpiCard
          label="Perda"
          value={fmtBRL(totais.perda)}
          bar="red"
          hint={`devolvido ${fmtBRL(totais.perdaDetalhe.devolvido)} · não realizado ${fmtBRL(totais.perdaDetalhe.naoRealizado)}`}
          title="PERDA = dinheiro que não vai virar receita: o que já saiu do caixa em devolução (devolvido) mais o saldo de contas mortas que nunca mais será cobrado (não realizado)."
        />
      </div>
      {/* Dinheiro/contas que não somam em nenhum dos 4 totais acima — nunca ficam invisíveis. */}
      {(totais.semValorDefinido > 0 || totais.segundaMetade.parceiros > 0) && (
        <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] text-[var(--fg-3)]">
          {totais.semValorDefinido > 0 && (
            <span>
              {/* --info, não --yellow: "sem valor definido" cobre incalculavel/sem_acordo,
                  que na gramática de CorStatus são AZUL (em negociação). --yellow agora
                  significa "vencido" — manter amarelo aqui seria a 6ª divergência no dia 1. */}
              <strong className="text-[var(--info)] font-semibold">{totais.semValorDefinido}</strong> conta(s) sem valor definido — fora dos 4 totais (não é zero, é &quot;não sabemos&quot;)
            </span>
          )}
          {totais.segundaMetade.parceiros > 0 && (
            <span
              title="2ª metade do honorário do parceiro — condicional ao marco de faturamento dele. Fica fora do Valor esperado por não ter fonte de dados que confirme o marco."
            >
              2ª metade condicional: {fmtBRL(totais.segundaMetade.valor)} ({totais.segundaMetade.parceiros} parceiro(s), fora do esperado)
            </span>
          )}
        </div>
      )}
    </div>
  );
}
