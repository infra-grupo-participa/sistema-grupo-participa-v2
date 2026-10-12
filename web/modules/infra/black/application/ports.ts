import type {
  ConfigBlack, LeadDetalhe, LinhaPerfil, Marcos, MensageriaBlack, Periodo, Resultado, TrafegoBlack,
} from '../domain/tipos';

/**
 * Fonte de dados do dashboard da Black. Duas implementações:
 * - demonstração (infrastructure/fixtures/fonte-fixtures.ts): dado fictício em memória, só em dev com NEXT_PUBLIC_BLACK_DEMO=1;
 * - real (infrastructure/fonte-supabase.ts): esboço; hoje devolve semDado em tudo, sem chamada de rede.
 * Contrato de cada método: docs/dashboard-black/README.md.
 */
export interface FonteDadosBlack {
  readonly modo: 'demonstracao' | 'real';
  /** Relógio da tela (o demo usa um relógio fixo, movível por ?relogio=AAAA-MM-DD). */
  agora(): Date;
  config(chave: string): Promise<Resultado<ConfigBlack>>;
  trafego(chave: string, p: Periodo): Promise<Resultado<TrafegoBlack>>;
  perfil(chave: string, p: Periodo): Promise<Resultado<LinhaPerfil[]>>;
  /** Dado pessoal: só ao abrir a tabela, 50 por página. */
  leads(chave: string, leadIds: string[]): Promise<Resultado<LeadDetalhe[]>>;
  mensageria(chave: string, p: Periodo): Promise<Resultado<MensageriaBlack>>;
  marcos(chave: string): Promise<Resultado<Marcos>>;
}

export const LEADS_POR_PAGINA = 50;
