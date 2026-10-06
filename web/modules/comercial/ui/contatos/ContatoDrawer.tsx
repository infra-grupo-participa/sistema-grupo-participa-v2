'use client';

// Ficha da pessoa: o histórico COMPLETO dela com a casa num cartão só. Cabeçalho com contato, dono, flags e o
// resumo (desde quando, lançamentos, compras, pago líquido, reembolsos, negócios abertos); abas Jornada (blocos por
// lançamento, cada um com a UTM daquela entrada) / Negócios (todos) / Dados / Conversa. Abre da base, das
// Conversas e da Recuperação.
import { useMemo, useState } from 'react';
import { AvatarInicial, Badge, Button, Drawer, Skeleton, Tabs, Toast, idsAba, useFlash } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { fmtTelefone } from '../../domain/regras';
import type { Contato } from '../../domain/types';
import type { TextoIndicador } from '../InfoIndicador';
import {
  Aviso, BotaoConversa, BotaoCopiar, Carregando, EstadoErro, FaixaNumeros, RodapeAcoes, Vazio, useEquipe,
} from '../comum';
import { ModalNovoNegocio } from '../ModalNovoNegocio';
import { NegocioDrawer } from '../NegocioDrawer';
import { avisarMudanca, repo, useAgora, useDados } from '../repositorio';
import { AbaConversa, AbaDados } from './AbaDados';
import { AbaJornada } from './AbaJornada';
import { AbaNegocios } from './AbaNegocios';
import { HistoricoAlteracoes } from '../registro/HistoricoAlteracoes';
import { resumoFicha } from './ficha-contato';
import { mapaDuplicados } from './regras-contatos';

type Aba = 'jornada' | 'negocios' | 'dados' | 'conversa' | 'alteracoes';
const ID_ABAS = 'ficha-contato';

/** Definições do resumo da ficha (não estão em domain/metricas.ts: são da pessoa, não da operação). */
const INFO: Record<'lancamentos' | 'compras' | 'pago' | 'reembolsos' | 'abertos', TextoIndicador> = {
  lancamentos: {
    nome: 'Lançamentos',
    oQueE: 'Quantos lançamentos ou captações diferentes a pessoa já entrou.',
    comoConta: 'Chaves de lançamento distintas na jornada (inscrição, lista, compra, negócio de funil de projeto). Pontos avulsos não contam.',
    paraQue: 'Quem volta a cada lançamento já conhece a casa: abordagem de relacionamento, não de apresentação.',
  },
  compras: {
    nome: 'Compras',
    oQueE: 'Pagamentos aprovados da pessoa, em todos os lançamentos.',
    comoConta: 'Cada pagamento aprovado na Hotmart conta uma vez, mesmo que depois tenha sido reembolsado.',
  },
  pago: {
    nome: 'Pago líquido',
    oQueE: 'Quanto a pessoa já pagou à casa, descontados os reembolsos.',
    comoConta: 'Soma dos pagamentos aprovados menos a soma dos reembolsos e chargebacks.',
    paraQue: 'Mostra o peso da pessoa como cliente antes de oferecer o próximo passo.',
  },
  reembolsos: {
    nome: 'Reembolsos',
    oQueE: 'Pedidos de reembolso ou chargeback da pessoa.',
    comoConta: 'Cada reembolso registrado na Hotmart conta uma vez.',
    paraQue: 'Reembolso pede cuidado na próxima oferta: leia o motivo na jornada antes de abordar.',
    meta: 'Zero.',
  },
  abertos: {
    nome: 'Negócios abertos',
    oQueE: 'Negócios em andamento da pessoa, do total que ela já teve.',
    comoConta: 'Status aberto, em qualquer funil, sobre todos os negócios (abertos, ganhos e perdidos).',
    paraQue: 'Com negócio aberto, a pessoa tem dono e conversa em andamento: não abra outro sem falar com ele.',
  },
};

export function ContatoDrawer({ contatoId, onClose, onAbrirContato, contatoReserva }: {
  contatoId: string;
  onClose: () => void;
  /** Troca a ficha para outro contato (usado no aviso de duplicidade). */
  onAbrirContato?: (id: string) => void;
  /** Contato cadastrado só na tela (demonstração): usado quando a fonte não o devolve. */
  contatoReserva?: Contato;
}) {
  const agora = useAgora();
  const { toast, flash } = useFlash(4000);
  const { nomeDe } = useEquipe();
  const cs = useDados(() => repo.contatos());
  const ns = useDados(() => repo.negocios());
  const fs = useDados(() => repo.funis());
  const ms = useDados(() => repo.motivosPerda());
  const jor = useDados(() => repo.jornada(contatoId), [contatoId]);
  const [negocioAberto, setNegocioAberto] = useState<string | null>(null);
  const [novo, setNovo] = useState(false);
  const [aba, setAba] = useState<Aba>('jornada');

  const contatos = useMemo(
    () => (cs.dados && contatoReserva && !cs.dados.some((x) => x.id === contatoReserva.id) ? [contatoReserva, ...cs.dados] : cs.dados),
    [cs.dados, contatoReserva],
  );
  const c = contatos?.find((x) => x.id === contatoId) ?? null;
  const soLocal = !!contatoReserva && c?.id === contatoReserva.id;
  const duplicados = useMemo(() => {
    if (!contatos) return [];
    const ids = mapaDuplicados(contatos).get(contatoId) ?? [];
    return contatos.filter((x) => ids.includes(x.id));
  }, [contatos, contatoId]);
  const dele = useMemo(() => (ns.dados ?? []).filter((n) => n.contatoId === contatoId), [ns.dados, contatoId]);

  // A ficha do negócio substitui esta enquanto estiver aberta (uma gaveta por vez: Esc fecha só a de cima).
  if (negocioAberto) return <NegocioDrawer negocioId={negocioAberto} onClose={() => setNegocioAberto(null)} />;

  // Carregando / erro / não encontrado: dentro da própria gaveta, sem pular de Modal para Drawer.
  if (!c) {
    const erro = cs.erro;
    return (
      <Drawer
        onClose={onClose}
        width="max-w-3xl"
        title={contatos ? 'Contato não encontrado' : erro ? 'Contato' : <Skeleton w={200} h={18} />}
        subtitle={!contatos && !erro ? <Skeleton w={160} h={10} className="mt-1" /> : undefined}
        avatar={!contatos && !erro ? <span className="block h-11 w-11 animate-pulse rounded-full bg-[var(--surface-3)]" /> : undefined}
      >
        {erro ? (
          <EstadoErro mensagem={erro} onTentar={cs.recarregar} />
        ) : contatos ? (
          <Vazio titulo="Esse contato não está na base" hint="Pode ter sido mesclado ou removido." icone="contact" />
        ) : (
          <div className="space-y-3" aria-busy="true" aria-label="Carregando ficha">
            {Array.from({ length: 6 }).map((_, i) => <Skeleton key={i} h={14} w={`${90 - i * 8}%`} />)}
          </div>
        )}
      </Drawer>
    );
  }

  const resumo = jor.dados && ns.dados ? resumoFicha(jor.dados, dele, c) : null;
  const sub = [
    fmtTelefone(c.telefone),
    c.email,
    resumo?.desde ? `${resumo.cliente ? 'Cliente' : 'Lead'} desde ${fmtData(resumo.desde)}` : null,
    c.donoId ? `Dono: ${nomeDe(c.donoId)}` : 'Sem dono',
  ].filter(Boolean).join(' · ');
  const bloqueioNovo = c.optOut
    ? 'Pediu para não receber contato: não abre negócio novo.'
    : soLocal ? 'Contato só desta tela (demonstração): grave o cadastro antes de abrir negócio.' : undefined;
  const podeConversar = !!c.telefone && !c.optOut;

  const botaoNovoNegocio = (
    <Button size="sm" onClick={() => setNovo(true)} disabled={!!bloqueioNovo} title={bloqueioNovo}>
      <Icon name="plus" size={14} /> Novo negócio
    </Button>
  );

  const painel = (k: Aba) => ({ role: 'tabpanel' as const, id: idsAba(ID_ABAS, k).panel, 'aria-labelledby': idsAba(ID_ABAS, k).tab });
  const esqueleto = (n = 3) => (
    <div className="space-y-2" aria-busy="true" aria-label="Carregando">{Array.from({ length: n }).map((_, i) => <Skeleton key={i} h={56} />)}</div>
  );

  return (
    <>
      <Drawer
        onClose={onClose}
        width="max-w-3xl"
        title={c.nome}
        subtitle={sub}
        avatar={<AvatarInicial nome={c.nome} size={44} />}
        badges={duplicados.length > 0 || c.ehAluno || c.optOut ? <>
          {c.optOut && <Badge tone="danger">Não quer contato</Badge>}
          {duplicados.length > 0 && <Badge tone="warning">Possível duplicado</Badge>}
          {c.ehAluno && <Badge tone="success">Já é aluno</Badge>}
        </> : undefined}
        actions={<>
          {podeConversar && <BotaoConversa contatoId={c.id} />}
          {c.telefone && <BotaoCopiar texto={fmtTelefone(c.telefone)} onCopiado={(m) => flash(m === 'Copiado.' ? 'Telefone copiado.' : m)} />}
        </>}
        footer={<RodapeAcoes primario={botaoNovoNegocio} />}
      >
        {c.optOut && (
          <Aviso tom="danger" icone="lock" className="mb-4">
            Pediu para não receber contato. Está na lista de bloqueio: fora de disparos e abordagens, sem negócio novo.
          </Aviso>
        )}

        <div className="mb-5">
          {resumo ? (
            <FaixaNumeros
              rotulo="Resumo da pessoa com a casa"
              itens={[
                { rotulo: 'Negócios abertos', valor: `${resumo.negociosAbertos} de ${resumo.negociosTotal}`, info: INFO.abertos },
                { rotulo: 'Lançamentos', valor: resumo.lancamentos, info: INFO.lancamentos },
                { rotulo: 'Compras', valor: resumo.compras, info: INFO.compras },
                { rotulo: 'Pago líquido', valor: fmtBRL(resumo.valorPago), info: INFO.pago },
                { rotulo: 'Reembolsos', valor: resumo.reembolsos, alerta: resumo.reembolsos > 0, info: INFO.reembolsos },
              ]}
            />
          ) : jor.erro ? null : <Skeleton h={40} />}
        </div>

        <Tabs
          idBase={ID_ABAS}
          label="Seções da ficha do contato"
          active={aba}
          onChange={(k) => setAba(k as Aba)}
          tabs={[
            { k: 'jornada', l: 'Jornada' },
            { k: 'negocios', l: 'Negócios', n: dele.length || undefined },
            { k: 'dados', l: 'Dados' },
            { k: 'conversa', l: 'Conversa' },
            { k: 'alteracoes', l: 'Alterações' },
          ]}
        />

        {aba === 'jornada' && (
          <div {...painel('jornada')}>
            <Carregando
              dados={jor.dados && fs.dados ? { pontos: jor.dados, funis: fs.dados } : null}
              erro={jor.erro ?? fs.erro}
              onTentar={() => { jor.recarregar(); fs.recarregar(); }}
              esqueleto={esqueleto()}
            >
              {(d) => <AbaJornada pontos={d.pontos} funis={d.funis} onAbrirNegocio={setNegocioAberto} />}
            </Carregando>
          </div>
        )}

        {aba === 'negocios' && (
          <div {...painel('negocios')}>
            <Carregando
              dados={ns.dados && fs.dados && ms.dados ? { funis: fs.dados, motivos: ms.dados } : null}
              erro={ns.erro ?? fs.erro ?? ms.erro}
              onTentar={() => { ns.recarregar(); fs.recarregar(); ms.recarregar(); }}
              esqueleto={esqueleto(2)}
            >
              {(d) => (
                <AbaNegocios
                  negocios={dele}
                  funis={d.funis}
                  motivos={d.motivos}
                  agora={agora}
                  nomeDe={nomeDe}
                  onAbrir={setNegocioAberto}
                  acaoVazio={bloqueioNovo ? undefined : botaoNovoNegocio}
                />
              )}
            </Carregando>
          </div>
        )}

        {aba === 'dados' && (
          <div {...painel('dados')}>
            <AbaDados c={c} duplicados={duplicados} nomeDe={nomeDe} onAbrirContato={onAbrirContato} />
          </div>
        )}

        {aba === 'conversa' && (
          <div {...painel('conversa')}>
            <AbaConversa c={c} nomeDe={nomeDe} />
          </div>
        )}

        {aba === 'alteracoes' && (
          <div {...painel('alteracoes')}>
            <HistoricoAlteracoes contatoId={c.id} />
          </div>
        )}
      </Drawer>

      {novo && (
        <ModalNovoNegocio
          contatoFixo={c}
          onClose={() => setNovo(false)}
          onCriado={({ donoId }) => {
            flash(donoId
              ? `Negócio criado. Dono: ${nomeDe(donoId)}${c.donoId ? ' (mantém o dono do contato)' : ' (pela distribuição)'}.`
              : 'Negócio criado sem dono: nenhum vendedor ativo na distribuição.');
            setNovo(false);
            setAba('negocios');
            avisarMudanca();
          }}
        />
      )}
      <Toast>{toast}</Toast>
    </>
  );
}
