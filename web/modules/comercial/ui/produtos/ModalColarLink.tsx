'use client';

// "Cadastrar pela Hotmart": a pessoa cola o link de checkout (ou o código da oferta) e o CRM procura no que a
// sincronização trouxe. Achou → leva para vincular/editar. Não achou → explica o porquê. Nunca cria nada local.
import { useState } from 'react';
import { Badge, Button, Input, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { fmtBRL } from '@/shared/ui/format';
import { extrairCodigoOferta } from '../../domain/hotmart';
import type { OfertaHotmart, ProdutoHotmart } from '../../domain/types';
import { Aviso, Campo } from '../comum';
import { repo } from '../repositorio';
import { ROTULO_CONTA, rotuloModo } from './produtos';

type Busca =
  | { estado: 'vazio' }
  | { estado: 'buscando' }
  | { estado: 'invalido' }
  | { estado: 'erro'; msg: string }
  | { estado: 'resultado'; codigo: string | null; produto: ProdutoHotmart | null; oferta: OfertaHotmart | null };

export function ModalColarLink({ gestor, onFechar, onAbrir, onVincular }: {
  gestor: boolean;
  onFechar: () => void;
  /** Abre a ficha do produto com a oferta em destaque. */
  onAbrir: (produtoId: string, codigo: string) => void;
  onVincular: (p: ProdutoHotmart, codigo: string) => void;
}) {
  const [texto, setTexto] = useState('');
  const [busca, setBusca] = useState<Busca>({ estado: 'vazio' });

  async function procurar(e?: React.FormEvent) {
    e?.preventDefault();
    if (!extrairCodigoOferta(texto)) { setBusca({ estado: 'invalido' }); return; }
    setBusca({ estado: 'buscando' });
    try {
      const r = await repo.buscarPorLinkHotmart(texto);
      setBusca({ estado: 'resultado', ...r });
    } catch (err) {
      setBusca({ estado: 'erro', msg: err instanceof Error ? err.message : 'Não foi possível procurar.' });
    }
  }

  const achou = busca.estado === 'resultado' && busca.produto && busca.oferta ? { produto: busca.produto, oferta: busca.oferta } : null;

  return (
    <Modal
      onClose={onFechar}
      title="Cadastrar pela Hotmart"
      width="max-w-xl"
      footer={
        <>
          <Button size="sm" variant="ghost" onClick={onFechar}>Fechar</Button>
          {achou ? (
            achou.produto.noComercial || !gestor
              ? <Button size="sm" onClick={() => onAbrir(achou.produto.produtoId, achou.oferta.codigo)}><Icon name="arrow-right" size={14} /> Abrir produto</Button>
              : <Button size="sm" onClick={() => onVincular(achou.produto, achou.oferta.codigo)}><Icon name="link" size={14} /> Vincular ao comercial</Button>
          ) : (
            <Button size="sm" onClick={() => { void procurar(); }} disabled={!texto.trim() || busca.estado === 'buscando'}>
              <Icon name="search" size={14} /> {busca.estado === 'buscando' ? 'Procurando…' : 'Procurar'}
            </Button>
          )}
        </>
      }
    >
      <div className="space-y-4">
        <p className="text-sm text-[var(--fg-2)] leading-relaxed">
          <strong className="text-[var(--fg)]">O produto e a oferta são criados na Hotmart, não aqui.</strong> Criou lá? Cole o link de
          checkout ou o código da oferta para achar o que a sincronização trouxe e vincular ao comercial.
        </p>

        <form onSubmit={procurar}>
          <Campo rotulo="Link de checkout ou código da oferta" dica="Ex.: https://pay.hotmart.com/4120577?off=hm30k12x ou só hm30k12x">
            <Input
              value={texto}
              onChange={(e) => { setTexto(e.target.value); if (busca.estado !== 'vazio') setBusca({ estado: 'vazio' }); }}
              placeholder="Cole aqui"
              autoFocus
              spellCheck={false}
            />
          </Campo>
        </form>

        {busca.estado === 'invalido' && (
          <Aviso tom="warning" alerta titulo="Não reconheci um código de oferta.">
            O link precisa ter <code>off=</code> (ex.: <code>?off=hm30k12x</code>). Copie o link de checkout da oferta na Hotmart, não o da página de vendas.
          </Aviso>
        )}

        {busca.estado === 'erro' && <Aviso tom="danger" alerta>{busca.msg}</Aviso>}

        {busca.estado === 'resultado' && !achou && (
          <Aviso tom="warning" alerta titulo={`A oferta ${busca.codigo ?? ''} ainda não está no CRM.`}>
            Ela não veio na sincronização. Confira se foi criada na conta certa da Hotmart (Academy ou Escritório) e
            aguarde a próxima sincronização. O CRM não cria produto nem oferta por aqui: se a venda já está entrando com esse código,
            ela aparece em “Fora do catálogo”.
          </Aviso>
        )}

        {achou && (
          <div className="rounded-[var(--r-lg)] border border-[var(--border-accent)] bg-[var(--surface-2)] p-3 space-y-2">
            <div className="flex flex-wrap items-center gap-1.5">
              <Icon name="check-circle" size={15} className="text-[var(--green)]" />
              <span className="text-sm font-semibold text-[var(--fg)]">Achei na Hotmart</span>
              {achou.produto.noComercial ? <Badge tone="success">No comercial</Badge> : <Badge>Fora do comercial</Badge>}
            </div>
            <dl className="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs">
              <dt className="text-[var(--fg-3)]">Produto</dt>
              <dd className="text-[var(--fg)] min-w-0 break-words">{achou.produto.nomeComercial ?? achou.produto.nomeHotmart} <span className="text-[var(--fg-3)]">· id {achou.produto.produtoId} · {ROTULO_CONTA[achou.produto.conta]}</span></dd>
              <dt className="text-[var(--fg-3)]">Oferta</dt>
              <dd className="text-[var(--fg)] min-w-0 break-words"><code>{achou.oferta.codigo}</code> · {achou.oferta.nomeHotmart ?? 'sem nome'}</dd>
              <dt className="text-[var(--fg-3)]">Preço</dt>
              <dd className="text-[var(--fg-2)]">{fmtBRL(achou.oferta.preco)} · {rotuloModo(achou.oferta.modo)}</dd>
            </dl>
            <p className="text-[11px] text-[var(--fg-3)]">
              {achou.produto.noComercial
                ? 'O produto já está no comercial. Abra a ficha para marcar esta oferta como vigente e escrever a condição.'
                : gestor
                  ? 'Vincule o produto ao comercial; depois marque a oferta vigente na ficha.'
                  : 'O produto ainda não está no comercial. Peça ao gestor para vincular.'}
            </p>
          </div>
        )}
      </div>
    </Modal>
  );
}
