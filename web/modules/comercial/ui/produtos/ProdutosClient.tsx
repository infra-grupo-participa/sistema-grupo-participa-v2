'use client';

// Tela "Produtos e ofertas". Produto e oferta NASCEM NA HOTMART: o CRM vincula o que a sincronização trouxe
// e acrescenta o que é do comercial (nome comercial, agrupador, escada, oferta vigente, condição).
// Objetivo: acabar com a dúvida "qual oferta eu vendo hoje".
import { useState } from 'react';
import { Button, ConfirmDialog, Tabs, Toast, idsAba, useFlash } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { ProdutoHotmart } from '../../domain/types';
import { Aviso, Carregando, EsqueletoLista, FaixaNumeros, PaginaComercial, combinarDados, useAbaHash, useEquipe } from '../comum';
import { avisarMudanca, repo, useAgora, useDados } from '../repositorio';
import { FichaProduto } from './FichaProduto';
import { ModalColarLink } from './ModalColarLink';
import { ModalVincular } from './ModalVincular';
import { FILTRO_INICIAL, diaLocal, resumoTela, type FiltroProdutos } from './produtos';
import { SecaoCatalogo, SecaoForaDoCatalogo, SecaoHoje } from './Secoes';

const ABAS = ['hoje', 'catalogo', 'orfas'] as const;
type Aba = (typeof ABAS)[number];

export function ProdutosClient() {
  const { gestor } = useEquipe();
  const agora = useAgora(60_000);
  const hojeISO = diaLocal(agora);
  const { toast, flash } = useFlash();
  const [aba, setAba] = useAbaHash<Aba>(ABAS, 'hoje');
  const [filtro, setFiltro] = useState<FiltroProdutos>(FILTRO_INICIAL);
  const [colar, setColar] = useState(false);
  const [ficha, setFicha] = useState<{ produtoId: string; destaque: string | null } | null>(null);
  const [vinculando, setVinculando] = useState<string | null>(null);
  const [desvinculando, setDesvinculando] = useState<string | null>(null);

  const rProdutos = useDados(() => repo.produtosHotmart());
  const rOfertas = useDados(() => repo.ofertas());
  const rOrfas = useDados(() => repo.ofertasOrfas());
  const rAgrupadores = useDados(() => repo.agrupadores());
  const est = combinarDados(rProdutos, rOfertas, rOrfas, rAgrupadores);

  const produtos = rProdutos.dados ?? [];
  const agrupadores = rAgrupadores.dados ?? [];
  const achar = (id: string | null | undefined): ProdutoHotmart | undefined => (id ? produtos.find((p) => p.produtoId === id) : undefined);
  const nomeAgrupador = (id: string | null) => (id ? agrupadores.find((a) => a.id === id)?.nome ?? null : null);
  const abrirFicha = (produtoId: string, destaque: string | null = null) => setFicha({ produtoId, destaque });

  async function desvincular(p: ProdutoHotmart) {
    const res = await repo.vincularProduto({
      produtoId: p.produtoId, noComercial: false, nomeComercial: p.nomeComercial, produtoKey: p.produtoKey, agrupadorId: p.agrupadorId, escada: p.escada,
    });
    setDesvinculando(null);
    flash(res.msg ?? (res.ok ? 'Produto desvinculado.' : 'Não foi possível desvincular.'));
    if (res.ok) avisarMudanca();
  }

  const resumo = est.dados ? resumoTela(est.dados[0], est.dados[1], est.dados[2], hojeISO) : null;
  const produtoFicha = achar(ficha?.produtoId);
  const produtoVinculo = achar(vinculando);
  const produtoDesvinculo = achar(desvinculando);

  return (
    <PaginaComercial
      titulo="Produtos e ofertas"
      subtitulo="Espelho da Hotmart: o que a sincronização trouxe e qual oferta o comercial vende hoje."
      acoes={<Button size="sm" onClick={() => setColar(true)}><Icon name="link" size={14} /> Cadastrar pela Hotmart</Button>}
      meta={resumo && (
        <FaixaNumeros rotulo="Resumo de produtos e ofertas" itens={[
          {
            rotulo: 'Produtos no comercial', valor: resumo.noComercial,
            onClick: () => { setFiltro({ ...FILTRO_INICIAL }); setAba('catalogo'); },
            info: {
              nome: 'Produtos no comercial',
              oQueE: 'Produtos da Hotmart vinculados ao comercial: aparecem em funis, ofertas e relatórios.',
              comoConta: `Produtos sincronizados com o vínculo ligado. Os outros ${resumo.foraDoComercial} estão na Hotmart, fora do comercial.`,
              paraQue: 'Produto que o time vende e não está aqui não tem oferta vigente nem relatório.',
            },
          },
          {
            rotulo: 'Ofertas vigentes', valor: resumo.ofertasVigentes, alerta: resumo.ofertasVencidas > 0,
            onClick: () => setAba('hoje'),
            title: resumo.ofertasVencidas > 0 ? `${resumo.ofertasVencidas} oferta(s) marcada(s) vigente(s) com a validade vencida` : undefined,
            info: {
              nome: 'Ofertas vigentes',
              oQueE: 'Ofertas que o vendedor pode oferecer hoje.',
              comoConta: 'Marcadas como vigentes pelo gestor, de produto no comercial e dentro da validade. Marcada com validade vencida não conta (fica em vermelho).',
              paraQue: 'É a cola do vendedor: condição fora delas não existe.',
            },
          },
          {
            rotulo: 'Fora do catálogo', valor: resumo.orfas, alerta: resumo.orfas > 0,
            onClick: () => setAba('orfas'),
            info: {
              nome: 'Ofertas vendidas fora do catálogo',
              oQueE: 'Códigos de oferta que aparecem em vendas da Hotmart mas não estão no catálogo sincronizado.',
              comoConta: `Códigos distintos com ao menos uma transação. Hoje somam ${resumo.transacoesOrfas.toLocaleString('pt-BR')} transações.`,
              paraQue: 'Venda com código fora do catálogo não vira pagamento no sistema. Catalogue no mesmo dia.',
              meta: 'Zero.',
            },
          },
          {
            rotulo: 'Sem oferta vigente', valor: resumo.semVigente, alerta: resumo.semVigente > 0,
            ativo: aba === 'catalogo' && filtro.semVigente,
            onClick: () => { setFiltro({ ...FILTRO_INICIAL, semVigente: true }); setAba('catalogo'); },
            info: {
              nome: 'Produtos sem oferta vigente',
              oQueE: 'Produtos do comercial sem nenhuma oferta que o vendedor possa oferecer hoje.',
              comoConta: 'Produtos no comercial com zero ofertas vigentes dentro da validade.',
              paraQue: 'Sem oferta vigente, não se aborda. O gestor define a oferta na ficha do produto.',
              meta: 'Zero.',
            },
          },
        ]} />
      )}
    >
      <div className="space-y-4">
        <Aviso tom="info" icone="link" titulo="Produto e oferta são criados na Hotmart.">
          Criou lá? Ele aparece aqui na próxima sincronização. Aqui você vincula ao comercial e define a oferta vigente.
          <ol className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1">
            <li><strong>1.</strong> Crie o produto e a oferta na Hotmart, na conta certa (Academy ou Escritório).</li>
            <li><strong>2.</strong> Aguarde a sincronização ou cole o link em “Cadastrar pela Hotmart”.</li>
            <li><strong>3.</strong> Vincule ao comercial e marque a oferta vigente.</li>
          </ol>
        </Aviso>

        <Tabs
          idBase="produtos"
          label="Vistas de produtos e ofertas"
          active={aba}
          onChange={(k) => setAba(k as Aba)}
          tabs={[
            { k: 'hoje', l: 'O que vender hoje' },
            { k: 'catalogo', l: 'Produtos' },
            { k: 'orfas', l: 'Fora do catálogo', n: rOrfas.dados?.length },
          ]}
        />

        <div role="tabpanel" id={idsAba('produtos', aba).panel} aria-labelledby={idsAba('produtos', aba).tab}>
          <Carregando dados={est.dados} erro={est.erro} onTentar={est.onTentar} esqueleto={<EsqueletoLista linhas={5} avatar={false} />}>
            {([listaProdutos, ofertas, orfas]) => (
              aba === 'hoje' ? (
                <SecaoHoje produtos={listaProdutos} ofertas={ofertas} hojeISO={hojeISO} gestor={gestor} flash={flash} onAbrir={abrirFicha} />
              ) : aba === 'catalogo' ? (
                <SecaoCatalogo
                  produtos={listaProdutos} ofertas={ofertas} hojeISO={hojeISO} gestor={gestor} filtro={filtro} onFiltro={setFiltro}
                  nomeAgrupador={nomeAgrupador} onAbrir={abrirFicha} onVincular={setVinculando} onColar={() => setColar(true)}
                />
              ) : (
                <SecaoForaDoCatalogo orfas={orfas} produtos={listaProdutos} flash={flash} onAbrir={abrirFicha} />
              )
            )}
          </Carregando>
        </div>
      </div>

      {colar && (
        <ModalColarLink
          gestor={gestor}
          onFechar={() => setColar(false)}
          onAbrir={(id, codigo) => { setColar(false); abrirFicha(id, codigo); }}
          onVincular={(p, codigo) => { setColar(false); abrirFicha(p.produtoId, codigo); setVinculando(p.produtoId); }}
        />
      )}

      {produtoFicha && ficha && (
        <FichaProduto
          produto={produtoFicha}
          gestor={gestor}
          hojeISO={hojeISO}
          destaque={ficha.destaque}
          nomeAgrupador={nomeAgrupador}
          onFechar={() => setFicha(null)}
          onVincular={() => setVinculando(produtoFicha.produtoId)}
          onDesvincular={() => setDesvinculando(produtoFicha.produtoId)}
          flash={flash}
        />
      )}

      {produtoVinculo && (
        <ModalVincular key={produtoVinculo.produtoId} produto={produtoVinculo} agrupadores={agrupadores} onFechar={() => setVinculando(null)} flash={flash} />
      )}

      {produtoDesvinculo && (
        <ConfirmDialog
          title="Desvincular do comercial?"
          danger
          confirmLabel="Desvincular"
          message={<>As ofertas de <strong>{produtoDesvinculo.nomeComercial ?? produtoDesvinculo.nomeHotmart}</strong> deixam de aparecer para o vendedor. O produto continua na Hotmart e volta para “fora do comercial”.</>}
          onCancel={() => setDesvinculando(null)}
          onConfirm={() => { void desvincular(produtoDesvinculo); }}
        />
      )}

      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}
