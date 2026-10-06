'use client';

// Ficha do produto: o que veio da Hotmart + as ofertas dele em cartões. O gestor marca a vigente aqui.
import { useEffect } from 'react';
import { Badge, Button, Drawer, Row } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtDataHora } from '@/shared/ui/format';
import { produto as produtoDoCatalogo } from '../../domain/catalogo';
import type { ProdutoHotmart } from '../../domain/types';
import { Aviso, Carregando, EsqueletoLista, NotaRodape, RodapeAcoes, Vazio } from '../comum';
import { repo, useDados } from '../repositorio';
import { CartaoOferta } from './CartaoOferta';
import { ROTULO_CONTA, ROTULO_ESCADA } from './produtos';

export function FichaProduto({ produto: p, gestor, hojeISO, destaque, nomeAgrupador, onFechar, onVincular, onDesvincular, flash }: {
  produto: ProdutoHotmart; gestor: boolean; hojeISO: string; destaque: string | null;
  nomeAgrupador: (id: string | null) => string | null;
  onFechar: () => void; onVincular: () => void; onDesvincular: () => void; flash: (m: string) => void;
}) {
  const r = useDados(() => repo.ofertas(p.produtoId), [p.produtoId]);

  // Veio de um link colado: rola até a oferta encontrada.
  useEffect(() => {
    if (!destaque || !r.dados) return;
    document.getElementById(`oferta-${destaque}`)?.scrollIntoView({ block: 'center' });
  }, [destaque, r.dados]);

  const agrupador = nomeAgrupador(p.agrupadorId);

  return (
    <Drawer
      onClose={onFechar}
      title={p.noComercial ? p.nomeComercial ?? p.nomeHotmart : p.nomeHotmart}
      subtitle={p.noComercial ? `Na Hotmart: ${p.nomeHotmart}` : 'Na Hotmart, fora do comercial'}
      badges={
        <>
          <Badge>{ROTULO_CONTA[p.conta]}</Badge>
          {p.familia && <Badge>{p.familia}</Badge>}
          {p.noComercial ? <Badge tone="success">No comercial</Badge> : <Badge>Fora do comercial</Badge>}
          {p.noComercial && p.escada && <Badge>{ROTULO_ESCADA[p.escada]}</Badge>}
        </>
      }
      footer={gestor ? (
        <RodapeAcoes
          perigo={p.noComercial ? <Button size="sm" variant="danger" onClick={onDesvincular}>Desvincular</Button> : undefined}
          secundario={<Button size="sm" variant="ghost" onClick={onFechar}>Fechar</Button>}
          primario={p.noComercial
            ? <Button size="sm" variant="subtle" onClick={onVincular}><Icon name="pencil" size={14} /> Editar vínculo</Button>
            : <Button size="sm" onClick={onVincular}><Icon name="link" size={14} /> Vincular ao comercial</Button>}
        />
      ) : <RodapeAcoes secundario={<Button size="sm" variant="ghost" onClick={onFechar}>Fechar</Button>} />}
    >
      <div className="space-y-4">
        <section aria-label="Dados do produto" className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-1">
          <Row k="Id na Hotmart" v={<span className="tabular">{p.produtoId}</span>} />
          <Row k="Conta" v={ROTULO_CONTA[p.conta]} />
          {p.noComercial && <Row k="Produto do CRM" v={p.produtoKey ? produtoDoCatalogo(p.produtoKey).nome : 'Nenhum'} />}
          {p.noComercial && <Row k="Agrupador" v={agrupador ?? 'Nenhum'} />}
          <Row k="Sincronizado em" v={fmtDataHora(p.sincronizadoEm)} />
        </section>

        <Aviso tom="neutral" icone="lock" titulo="O vendedor só oferece oferta vigente.">
          Condição fora dela não existe. Precisa de outra condição? Crie a oferta na Hotmart; ela aparece aqui na próxima sincronização.
        </Aviso>

        {!gestor && <NotaRodape>Só o gestor do Comercial vincula produtos e define a oferta vigente.</NotaRodape>}

        <section aria-labelledby="ofertas-produto">
          <h3 id="ofertas-produto" className="mb-2 text-sm font-semibold text-[var(--fg)]">Ofertas deste produto</h3>
          <Carregando dados={r.dados} erro={r.erro} onTentar={() => { void r.recarregar(); }} esqueleto={<EsqueletoLista linhas={3} avatar={false} />}>
            {(ofertas) => ofertas.length ? (
              <ul className="space-y-2">
                {ofertas.map((o) => (
                  <CartaoOferta
                    key={`${o.codigo}|${o.vigente}|${o.condicao}|${o.validaAte}|${o.uso}`}
                    oferta={o}
                    produtoNoComercial={p.noComercial}
                    gestor={gestor}
                    hojeISO={hojeISO}
                    destaque={destaque === o.codigo}
                    flash={flash}
                  />
                ))}
              </ul>
            ) : (
              <Vazio icone="receipt" titulo="Nenhuma oferta sincronizada" hint="Crie a oferta na Hotmart, na conta certa. Ela aparece aqui na próxima sincronização." />
            )}
          </Carregando>
        </section>
      </div>
    </Drawer>
  );
}
