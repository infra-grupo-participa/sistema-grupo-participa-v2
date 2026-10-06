/* Grupo Participa · Marketing > Web · gravador de página (radar-v1, 05/10/2026).
   Adaptado do gravador do Radar do Luiz Fernando (radar-051026-0007.js, pacote de 05/10/2026), que passou a ser do
   Grupo. Mudou: manda para o NOSSO coletor (/api/web/coletar, no mesmo domínio deste arquivo), o projeto é a sigla
   de campanha (data-projeto="PB26") e NÃO grava vídeo (replay fica para outra fase): sem rrweb.
   Uso (no <head> de cada página do projeto; a linha pronta está em Marketing > Web > Instalação):
   <script src="https://grupoparticipa.app.br/web/radar-v1.js" data-projeto="PB26" async></script>
   Com "async" a página nunca espera por este arquivo. Versão nova = nome novo (radar-v2.js...), por causa do cache.

   O que faz, em cada visita (100% das visitas):
   - página vista, cliques (posição, elemento, clique de raiva, clique morto), rolagem máxima, tempo visível e ativo,
     vai e vem da rolagem, erros de JavaScript e os eventos do funil que a página já empurra no dataLayer;
   - origem: utm_source, utm_medium, utm_campaign, utm_content, utm_term, campaign_id, adset_id, ad_id, se veio com
     fbclid ou gclid (só sim/não) e o site de onde veio (só o domínio). utm_content = o anúncio (criativo) no formato
     nome|id, padrão oficial do gp-operacoes (departamentos/dados/areas/infraestrutura/processos/
     padronizar-utm-dos-links.md); no Meta campanha e conjunto também vêm em nome|id. O gravador manda o texto como
     veio; o banco separa e cruza pelo id (mkt.utm_separar, migration 20261006f);
   - sistema, navegador e app (Instagram, Facebook...) e o lugar aproximado quando a página já tem a VisitorAPI;
   - velocidade real (LCP, INP, CLS, FCP, TTFB, carga, peso e rede), só números;
   - leitura: segundos em cada seção (<section> ou data-secao), botões (data-cta) que apareceram, rolagem nos primeiros
     30 s e, do formulário, o nome de cada campo, focos, tempo, se ficou preenchido e se deu erro. O VALOR digitado
     nunca é lido.

   Regras que não se quebram:
   - só LÊ o dataLayer, nunca escreve: não mexe no GTM, no Pixel nem no envio do formulário;
   - nada pessoal sai daqui: do dataLayer só o nome do evento e as chaves permitidas (pagina, motivo, origem, area,
     versao); campos ocultos, #dados-lead e [data-radar-bloquear] ficam de fora; o IP nunca é lido aqui;
   - qualquer erro aqui dentro é engolido: a página nunca quebra por causa do gravador;
   - o gravador ouve o coletor: "pausado" desliga neste navegador por 30 min; "limite" por 5 min; "dominio" ou
     "projeto" por 60 min; 3 falhas seguidas (coletor fora do ar) por 10 min. Nada disso aparece para quem visita.
   Desligar num navegador: localStorage.radar_off = '1'. Visita de teste: ?radar=teste na URL ou data-teste="1". */
(function () {
  'use strict';
  try {
    var eu = document.currentScript || document.querySelector('script[data-projeto][src*="radar"]');
    if (!eu) return;
    var PROJETO = eu.getAttribute('data-projeto');
    var COLETA = eu.getAttribute('data-coleta') || '';
    var BLOQUEAR = eu.getAttribute('data-bloquear') || '#dados-lead, input[type="hidden"], [data-radar-bloquear]';
    /* o coletor mora no mesmo dominio deste arquivo: https://grupoparticipa.app.br/web/radar-v1.js -> /api/web/coletar */
    try { if (!COLETA) COLETA = new URL(eu.src).origin + '/api/web/coletar'; } catch (e) { return; }
    var CHAVES_DL = ['pagina', 'motivo', 'origem', 'area', 'versao'];
    if (!PROJETO || !/^[A-Za-z]{2,10}[0-9]{2,4}$/.test(PROJETO)) return;
    try { if (localStorage.getItem('radar_off') === '1') return; } catch (e) {}
    /* pausado pelo coletor ha pouco (banco cheio, coleta pausada ou fora do ar): nem comeca */
    try { if (parseInt(localStorage.getItem('radar_pausa') || '0', 10) > Date.now()) return; } catch (e) {}

    var q = new URLSearchParams(location.search);
    var agora = function () { return Date.now(); };
    function id() {
      try { if (crypto.randomUUID) return crypto.randomUUID().replace(/-/g, '').slice(0, 24); } catch (e) {}
      return (Math.random().toString(36).slice(2) + Math.random().toString(36).slice(2)).slice(0, 24);
    }
    function ler(armazem, chave) { try { return armazem.getItem(chave); } catch (e) { return null; } }
    function gravar(armazem, chave, valor) { try { armazem.setItem(chave, valor); } catch (e) {} }
    /* O armazenamento do navegador pode estar bloqueado (so de olhar ja da erro) ou nao passar de uma pagina para a
       outra: no primeiro lead de verdade (iPhone, dentro do Instagram, 01/10/2026) o obrigado entrou como outra pessoa,
       em outra visita. Por isso os dois codigos aleatorios ficam tambem num biscoito da propria pagina. */
    var doNavegador = null, daAba = null;
    try { doNavegador = window.localStorage; } catch (e) {}
    try { daAba = window.sessionStorage; } catch (e) {}
    var CODIGO = /^[A-Za-z0-9]{8,40}$/;
    function lerBiscoito(nome) {
      try { var m = document.cookie.match(new RegExp('(?:^|; )' + nome + '=([^;]*)')); return m ? decodeURIComponent(m[1]) : null; } catch (e) { return null; }
    }
    function gravarBiscoito(nome, valor, segundos) {
      try {
        document.cookie = nome + '=' + encodeURIComponent(valor) + '; path=/; max-age=' + segundos + '; SameSite=Lax' + (location.protocol === 'https:' ? '; Secure' : '');
      } catch (e) {}
    }

    /* visitante (1 ano, no navegador) */
    var visitante = ler(doNavegador, 'radar_v');
    if (!CODIGO.test(visitante || '')) visitante = lerBiscoito('radar_v');
    if (!CODIGO.test(visitante || '')) visitante = id();
    gravar(doNavegador, 'radar_v', visitante);
    gravarBiscoito('radar_v', visitante, 31536000);

    /* sessao (visita): segue de uma pagina para a outra na mesma aba e acaba depois de 30 min parada. Quando a aba
       nao guardou a sessao, vale a do biscoito se ela tem menos de 30 min e a pagina chegou SEM parametro de campanha:
       e a mesma visita seguindo. Chegou com utm, fbclid ou gclid: e clique novo de anuncio, visita nova. */
    var sessao = ler(daAba, 'radar_s');
    var ultimo = parseInt(ler(daAba, 'radar_t') || '0', 10);
    if (!CODIGO.test(sessao || '') || agora() - ultimo > 30 * 60 * 1000) {
      var guardada = String(lerBiscoito('radar_s') || '').split('.');
      var cliqueNovo = /(^|[?&])(utm_[a-z]+|fbclid|gclid|campaign_id|adset_id|ad_id)=/.test(location.search);
      if (!cliqueNovo && CODIGO.test(guardada[0] || '') && agora() - parseInt(guardada[1] || '0', 10) <= 30 * 60 * 1000) sessao = guardada[0];
      else { sessao = id(); try { if (daAba) daAba.removeItem('radar_o'); } catch (e) {} }
      gravar(daAba, 'radar_s', sessao);
    }
    gravar(daAba, 'radar_t', String(agora()));
    gravarBiscoito('radar_s', sessao + '.' + agora(), 1800);

    /* origem: a primeira da sessao vale para a sessao toda (utm e ids do anuncio). Cada valor vai cortado em 120
       caracteres; no formato nome|id o id fica no fim, entao nome muito longo perde o id (o banco cai na reserva pelo
       nome). Mantido assim no v1; o v2 deve guardar o fim do texto. */
    var CHAVES_ORIGEM = ['utm_source', 'utm_medium', 'utm_campaign', 'utm_content', 'utm_term', 'campaign_id', 'adset_id', 'ad_id'];
    var origem = {};
    try { origem = JSON.parse(ler(daAba, 'radar_o') || 'null') || null; } catch (e) { origem = null; }
    if (!origem) {
      origem = {};
      CHAVES_ORIGEM.forEach(function (k) { if (q.get(k)) origem[k] = q.get(k).slice(0, 120); });
      origem.fbclid = q.get('fbclid') ? 1 : 0;
      origem.gclid = q.get('gclid') ? 1 : 0;
      try { origem.referrer = document.referrer ? new URL(document.referrer).hostname : ''; } catch (e) { origem.referrer = ''; }
      gravar(daAba, 'radar_o', JSON.stringify(origem));
    }
    var teste = eu.getAttribute('data-teste') === '1' || q.get('radar') === 'teste' || /teste/i.test(origem.utm_source || '') ? 1 : 0;

    /* A partida do gravador nao le medida nenhuma da pagina: ler largura, rolagem ou posicao de elemento antes da
       primeira pintura obriga o navegador a montar a pagina fora de hora. Celular, tablet ou computador sai da
       regra de tela (que nao obriga); a largura em px e lida no primeiro pacote. */
    function telaAte(px) { try { return window.matchMedia('(max-width: ' + px + 'px)').matches; } catch (e) { return (window.innerWidth || 0) <= px; } }
    var dispositivo = telaAte(767) ? 'mobile' : (telaAte(1024) ? 'tablet' : 'desktop');
    var largura = 0;
    var pv = id();
    var inicio = agora();

    /* informacoes da visita: so o sistema, o navegador e o app (Instagram, Facebook...). Sem versao, modelo, tela,
       idioma ou fuso: as telas desta fase nao usam e somariam impressao digital do aparelho. */
    var info = {};
    var APPS = [['instagram', /Instagram/i], ['messenger', /MessengerForiOS|FBAN\/Messenger|FB_IAB\/MESSENGER|FBMS/i],
                ['facebook', /FBAN|FBAV|FB_IAB|FBIOS|FB4A/i], ['threads', /Barcelona/i], ['tiktok', /musical_ly|BytedanceWebview|TikTok/i],
                ['linkedin', /LinkedInApp/i], ['whatsapp', /WhatsApp/i], ['telegram', /Telegram/i], ['pinterest', /Pinterest/i],
                ['snapchat', /Snapchat/i], ['google', /GSA\/\d/i]];
    var NOME_APP = { instagram: 'Instagram', messenger: 'Messenger', facebook: 'Facebook', threads: 'Threads', tiktok: 'TikTok', linkedin: 'LinkedIn',
                     whatsapp: 'WhatsApp', telegram: 'Telegram', pinterest: 'Pinterest', snapchat: 'Snapchat', google: 'App do Google' };
    function aparelho() {
      try {
        var ua = navigator.userAgent || '';
        var app = '';
        for (var i = 0; i < APPS.length; i++) if (APPS[i][1].test(ua)) { app = APPS[i][0]; break; }
        var ios = /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
        if (/Android/i.test(ua)) info.sis = 'Android';
        else if (ios) info.sis = 'iOS';
        else if (/Windows NT/.test(ua)) info.sis = 'Windows';
        else if (/CrOS/.test(ua)) info.sis = 'ChromeOS';
        else if (/Mac OS X/.test(ua)) info.sis = 'macOS';
        else if (/Linux/.test(ua)) info.sis = 'Linux';
        if (app) { info.app = app; info.nav = NOME_APP[app]; }
        else {
          var navs = [['Edge', /Edg(?:A|iOS)?\//], ['Opera', /OPR\//], ['Samsung Internet', /SamsungBrowser\//],
                      ['Firefox', /(?:Firefox|FxiOS)\//], ['Chrome', /(?:Chrome|CriOS)\//], ['Safari', /Version\/[\d.]+ (?:Mobile\/\S+ )?Safari/]];
          for (var j = 0; j < navs.length; j++) if (navs[j][1].test(ua)) { info.nav = navs[j][0]; break; }
          if (/; wv\)/.test(ua)) info.nav = 'WebView';
          if (!info.nav) info.nav = 'Outro';
        }
      } catch (e) {}
    }
    /* o aparelho e lido com o navegador livre (ou, no mais tardar, no primeiro pacote): nao disputa com a primeira
       pintura da pagina */
    var aparelhoLido = false;
    function leAparelho() { if (!aparelhoLido) { aparelhoLido = true; aparelho(); } }
    function quandoLivre(fn, prazo) {
      try { if (window.requestIdleCallback) return window.requestIdleCallback(function () { fn(); }, { timeout: prazo }); } catch (e) {}
      return setTimeout(fn, Math.min(prazo, 400));
    }
    quandoLivre(leAparelho, 2500);
    var infoEnviada = '';

    var parado = false;   /* o coletor mandou parar (ou falhou 3 vezes seguidas) */
    var fila = [];        /* eventos leves */
    var seq = 0;
    var rolagemMax = 0;
    var visivelDesde = document.visibilityState === 'visible' ? agora() : 0;
    var visivelTotal = 0;

    /* Ler a altura do documento obriga o navegador a refazer a conta da pagina inteira. Por isso ela fica guardada e
       so e relida quando a pagina muda de tamanho (o navegador avisa), no maximo uma vez por segundo, e a cada 5 s por
       garantia. Sem o aviso (navegador antigo), uma vez por segundo. */
    var alturaGuardada = 0, alturaEm = 0, alturaMudou = true, olhoAltura = null;
    function vigiaAltura() {
      try {
        if (olhoAltura || !window.ResizeObserver || !document.body) return;
        olhoAltura = new ResizeObserver(function () { alturaMudou = true; });
        olhoAltura.observe(document.documentElement);
        olhoAltura.observe(document.body);
      } catch (e) {}
    }
    function alturaDoc() {
      var t = agora();
      vigiaAltura();
      if (!alturaGuardada || ((alturaMudou || !olhoAltura) && t - alturaEm >= 1000) || t - alturaEm >= 5000) {
        var d = document.documentElement, b = document.body || {};
        alturaGuardada = Math.max(d.scrollHeight || 0, b.scrollHeight || 0);
        alturaEm = t; alturaMudou = false;
      }
      return alturaGuardada;
    }
    function evento(tipo, dados) {
      if (parado) return;
      var e = { t: tipo, ts: agora() - inicio };
      if (dados) for (var k in dados) e[k] = dados[k];
      fila.push(e);
    }

    /* seletor curto e estavel do elemento clicado (id, data-cta, classe) */
    function seletor(el) {
      var partes = [];
      for (var i = 0; el && el.nodeType === 1 && i < 4; i++, el = el.parentElement) {
        var s = el.tagName.toLowerCase();
        /* o nome do botao (data-cta) vale mais que o id: e por ele que a Inteligencia conta os cliques de cada botao */
        if (el.getAttribute('data-cta')) { partes.unshift(s + '[data-cta="' + el.getAttribute('data-cta') + '"]'); break; }
        if (el.id) { partes.unshift(s + '#' + el.id); break; }
        var cls = (el.getAttribute('class') || '').trim().split(/\s+/).filter(Boolean).slice(0, 2);
        if (cls.length) s += '.' + cls.join('.');
        partes.unshift(s);
      }
      return partes.join(' > ').slice(0, 200);
    }
    /* elemento fixo na tela (janela do formulario, barra fixa): no mapa ele nao tem lugar na pagina */
    function flutuante(el) {
      try {
        for (var i = 0; el && el.nodeType === 1 && i < 12; i++, el = el.parentElement) {
          var p = getComputedStyle(el).position;
          if (p === 'fixed') return true;   /* sticky fica: rola junto com a pagina e tem lugar no mapa */
        }
      } catch (e) {}
      return false;
    }
    function interativo(el) {
      for (var i = 0; el && el.nodeType === 1 && i < 5; i++, el = el.parentElement) {
        var tag = el.tagName;
        if (tag === 'A' || tag === 'BUTTON' || tag === 'INPUT' || tag === 'LABEL' || tag === 'SELECT' || tag === 'TEXTAREA' || tag === 'SUMMARY') return true;
        if (el.getAttribute('role') === 'button' || el.hasAttribute('onclick') || el.getAttribute('data-cta') || el.getAttribute('tabindex') === '0') return true;
      }
      return false;
    }

    /* cliques: posicao relativa (x em % da largura, y em px do documento), raiva (3+ em 700 ms no mesmo lugar) e morto */
    var ultimos = [];
    document.addEventListener('click', function (ev) {
      try {
        var alvo = ev.target && ev.target.nodeType === 1 ? ev.target : (ev.target && ev.target.parentElement);
        var x = ev.pageX, y = ev.pageY, t = agora();
        ultimos = ultimos.filter(function (c) { return t - c.t < 700 && Math.abs(c.x - x) < 30 && Math.abs(c.y - y) < 30; });
        ultimos.push({ t: t, x: x, y: y });
        /* texto do elemento clicado, nunca de campo de formulario nem de area bloqueada */
        var campo = alvo && /^(INPUT|TEXTAREA|SELECT|OPTION)$/.test(alvo.tagName);
        var texto = alvo && !campo ? String(alvo.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 40) : '';
        if (alvo && alvo.closest && alvo.closest(BLOQUEAR)) texto = '';
        evento('clique', {
          x: Math.round(x / Math.max(1, document.documentElement.scrollWidth) * 10000) / 100,
          y: Math.round(y), sel: alvo ? seletor(alvo) : '', txt: texto,
          raiva: ultimos.length >= 3 ? 1 : 0, morto: alvo && !interativo(alvo) ? 1 : 0, fixo: alvo && flutuante(alvo) ? 1 : 0
        });
      } catch (e) {}
    }, true);

    /* rolagem maxima em % do documento e o vai e vem: quantas vezes a rolagem mudou de direcao depois de andar
       250 px ou mais (quem sobe e desce procurando algo que nao acha) */
    var yAnterior = 0, direcao = 0, inicioPerna = 0, vaivem = 0;
    var rolagem30 = 0;   /* ate onde a rolagem foi nos primeiros 30 s da pagina */
    function mede() {
      try {
        var h = alturaDoc(), vh = window.innerHeight || 1, y = window.scrollY || window.pageYOffset || 0;
        var p = h > vh ? Math.min(100, Math.round((y + vh) / h * 100)) : 100;
        if (p > rolagemMax) rolagemMax = p;
        if (agora() - inicio <= 30000) rolagem30 = rolagemMax;
        var d = y > yAnterior ? 1 : (y < yAnterior ? -1 : 0);
        if (d) {
          if (direcao && d !== direcao) {
            if (Math.abs(yAnterior - inicioPerna) >= 250) vaivem++;
            inicioPerna = yAnterior;
          } else if (!direcao) inicioPerna = yAnterior;
          direcao = d;
        }
        yAnterior = y;
      } catch (e) {}
    }
    /* a rolagem avisa dezenas de vezes por segundo: a medida roda no maximo 5 vezes por segundo */
    var medeMarcado = 0;
    function medeLogo() { if (!medeMarcado) medeMarcado = setTimeout(function () { medeMarcado = 0; mede(); }, 200); }
    window.addEventListener('scroll', medeLogo, { passive: true });
    var relogioRolagem = setInterval(mede, 1000);   /* tambem por relogio: alguns navegadores seguram o evento de rolagem */

    /* tempo ativo: a pagina aberta e a pessoa mexendo nela (rolar, tocar, digitar, mover o mouse) nos ultimos 5 s */
    var ultimaAcao = agora(), ativoTotal = 0, ativoRelogio = agora();
    var ultimoToque = 0;   /* o ultimo toque, clique ou tecla: e o que separa o foco que a pessoa deu do foco que a pagina deu */
    function acao(ev) {
      ultimaAcao = agora();
      if (ev && (ev.type === 'pointerdown' || ev.type === 'touchstart' || ev.type === 'keydown')) ultimoToque = ultimaAcao;
    }
    ['scroll', 'pointerdown', 'touchstart', 'keydown', 'mousemove', 'wheel'].forEach(function (n) {
      window.addEventListener(n, acao, { passive: true, capture: true });
    });
    var relogioAtivo = setInterval(function () {
      var t = agora();
      if (document.visibilityState === 'visible' && t - ultimaAcao < 5000) ativoTotal += t - ativoRelogio;
      ativoRelogio = t;
      leitura(t);
    }, 1000);

    /* leitura da pagina (para a Inteligencia): secoes, botoes e formulario. So nomes de elemento e numeros. */
    function nomeCurto(v) { return String(v || '').toLowerCase().replace(/[^a-z0-9_-]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40); }
    function naTela(el) {
      var r = el.getBoundingClientRect();
      return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < (window.innerHeight || 0) ? r : null;
    }
    var secoesEl = [], secoesNome = [], secoesSeg = Object.create(null), batidas = 0;
    var ctasEl = [], ctasNome = [], ctasVisto = Object.create(null), olhoCta = null;
    var camposEl = [], camposNome = [], campos = Object.create(null), formVisto = 0, formInicio = 0, formFim = 0, formUltimo = '', formEnvios = 0;
    var focoEm = '', focoEl = null, focoConta = 0;   /* focoConta: o foco veio de um gesto da pessoa, ou ela ja digitou no campo */
    var mapaEnviado = '';
    /* o botao de enviar do formulario nao e "botao que leva ao formulario": fica fora da conta dos botoes */
    function botaoDeEnvio(el) {
      if (el.closest && el.closest('form')) return true;
      if (el.tagName !== 'BUTTON' && el.tagName !== 'INPUT') return false;
      for (var i = 0, p = el.parentElement; p && i < 3; i++, p = p.parentElement) {
        if (p.querySelector && p.querySelector('input:not([type="hidden"]), select, textarea')) return true;
      }
      return false;
    }
    function nomeCampo(el) {
      if (!el || !el.tagName || !/^(INPUT|SELECT|TEXTAREA)$/.test(el.tagName)) return '';
      var tipo = String(el.getAttribute('type') || '').toLowerCase();
      if (/^(hidden|submit|button|image|reset|file)$/.test(tipo)) return '';
      try { if (el.closest && el.closest(BLOQUEAR)) return ''; } catch (e) {}
      return nomeCurto(el.getAttribute('name') || el.id || tipo || el.tagName);
    }
    /* acha as secoes, os botoes e os campos da pagina (de novo um pouco depois: tem pagina que monta pedaco mais tarde) */
    function desenho() {
      try {
        var i, j, n, el, cls, usados = Object.create(null), vezes = Object.create(null), cand = [], lista = document.querySelectorAll('section, [data-secao]');
        var els = [], nomes = [];
        for (i = 0; i < lista.length; i++) {
          el = lista[i];
          /* secao dentro de secao: vale a de fora, a nao ser que a de dentro tenha nome proprio (data-secao) */
          if (!el.hasAttribute('data-secao') && el.parentElement && el.parentElement.closest('section, [data-secao]')) continue;
          cls = String(el.getAttribute('class') || '').trim().split(/\s+/).filter(Boolean);
          for (j = 0; j < cls.length; j++) vezes[cls[j]] = (vezes[cls[j]] || 0) + 1;
          cand.push([el, cls]);
        }
        /* o nome: data-secao, o id ou a classe. Entre as classes, a primeira que so esta nesta secao ("secao percurso"
           e "secao conduz" viram "percurso" e "conduz"). O numero de desempate e o lugar da secao na pagina, contando
           as escondidas: o nome nao muda quando uma secao aparece depois, nem entre o celular e o computador */
        for (i = 0; i < cand.length && els.length < 30; i++) {
          el = cand[i][0]; cls = cand[i][1];
          n = el.getAttribute('data-secao') || el.id || '';
          for (j = 0; !n && j < cls.length; j++) if (vezes[cls[j]] === 1) n = cls[j];
          n = nomeCurto(n || cls[0]) || ('secao-' + (i + 1));
          if (usados[n]) n = n.slice(0, 36) + '-' + (i + 1);
          usados[n] = 1;
          if (!el.getBoundingClientRect().height) continue;   /* escondida: fica fora ate aparecer */
          els.push(el); nomes.push(n);
        }
        secoesEl = els; secoesNome = nomes;

        lista = document.querySelectorAll('[data-cta]');
        els = []; nomes = [];
        for (i = 0; i < lista.length && nomes.length < 20; i++) {
          el = lista[i]; n = nomeCurto(el.getAttribute('data-cta'));
          if (!n || botaoDeEnvio(el)) continue;
          els.push([el, n]);
          if (nomes.indexOf(n) < 0) { nomes.push(n); if (!(n in ctasVisto)) ctasVisto[n] = 0; }
        }
        ctasEl = els; ctasNome = nomes;
        if (window.IntersectionObserver) {
          if (olhoCta) olhoCta.disconnect();
          olhoCta = new IntersectionObserver(function (entradas) {
            try {
              entradas.forEach(function (x) {
                if (!x.isIntersecting) return;
                for (var k = 0; k < ctasEl.length; k++) if (ctasEl[k][0] === x.target) ctasVisto[ctasEl[k][1]] = 1;
              });
            } catch (e) {}
          }, { threshold: 0.5 });
          ctasEl.forEach(function (x) { if (!ctasVisto[x[1]]) olhoCta.observe(x[0]); });
        }

        lista = document.querySelectorAll('input, select, textarea');
        els = []; nomes = [];
        for (i = 0; i < lista.length && nomes.length < 30; i++) {
          n = nomeCampo(lista[i]);
          if (!n) continue;
          els.push(lista[i]);
          if (nomes.indexOf(n) < 0) nomes.push(n);
        }
        camposEl = els; camposNome = nomes;
      } catch (e) {}
    }
    /* onde o elemento mora: o numero da secao (a de dentro, quando ha secao dentro de secao); -2 se, antes de chegar
       a uma secao, ele esta numa janela fixa por cima da pagina (formulario que abre, aviso, barra); -1 fora de tudo */
    function moradia(el) {
      try {
        for (var i = 0, k; el && el.nodeType === 1 && i < 60; i++, el = el.parentElement) {
          k = secoesEl.indexOf(el);
          if (k >= 0) return k;
          if (getComputedStyle(el).position === 'fixed') return -2;
        }
      } catch (e) {}
      return -1;
    }
    function soltaFoco() {
      if (focoConta) formFim = agora();
      focoEm = ''; focoEl = null; focoConta = 0;
    }
    /* a cada segundo com a pagina na tela e a pessoa por perto (mexeu nos ultimos 30 s), UMA secao ganha 1 s:
       - com a pessoa num campo do formulario (foco dela, campo na tela), o campo ganha 1 s e a secao onde ele mora
         tambem (campo em janela por cima da pagina ou fora de qualquer secao nao conta para secao nenhuma: quem
         digita ali nao esta lendo a secao de tras);
       - senao, a secao que esta na LINHA DE LEITURA. A linha fica no meio da tela; no comeco da pagina ela sobe ate
         1/4 da tela e no fim desce ate 3/4, porque pelo meio da tela a primeira e a ultima secao, quando curtas,
         nunca passam. Vale o que esta na frente: janela aberta por cima da pagina nao conta para a secao de tras.
         Linha fora de qualquer secao (cabecalho, rodape, vao): a secao visivel mais perto, ate 1/4 de tela.
       Sem IntersectionObserver, os botoes sao conferidos aqui; o formulario, ate aparecer. */
    function leitura(t) {
      try {
        /* o foco saiu sem avisar (o proprio formulario escondeu ou tirou o campo da pagina): fecha a conta dele */
        if (focoEm && focoEl && document.activeElement !== focoEl) soltaFoco();
        if (document.visibilityState !== 'visible' || t - ultimaAcao > 30000) return;
        if (++batidas % 10 === 0) desenho();   /* pagina que revela pedacos depois: secao, botao ou campo novo */
        var vh = window.innerHeight || 0, alvo = -1, i, r, d, perto;
        if (focoEm && focoConta && focoEl && naTela(focoEl)) { campo(focoEm)[1] += 1000; alvo = moradia(focoEl); }
        else {
          var y = Math.max(0, window.scrollY || window.pageYOffset || 0), resto = Math.max(0, alturaDoc() - vh - y);
          var linha = vh / 2 + Math.min(y, vh / 4) - Math.min(resto, vh / 4);
          alvo = moradia(document.elementFromPoint((window.innerWidth || 0) / 2, linha));
          if (alvo === -1) {
            perto = vh / 4;
            for (i = 0; i < secoesEl.length; i++) {
              r = secoesEl[i].getBoundingClientRect();
              if (!(r.height > 0) || r.bottom <= 0 || r.top >= vh) continue;
              d = r.top <= linha && r.bottom >= linha ? 0 : Math.min(Math.abs(r.top - linha), Math.abs(r.bottom - linha));
              if (d <= perto) { perto = d; alvo = i; }   /* entre iguais, a que vem depois (a de dentro) */
            }
          }
        }
        if (alvo >= 0) secoesSeg[secoesNome[alvo]] = (secoesSeg[secoesNome[alvo]] || 0) + 1;
        if (!window.IntersectionObserver) {
          for (i = 0; i < ctasEl.length; i++) if (!ctasVisto[ctasEl[i][1]] && naTela(ctasEl[i][0])) ctasVisto[ctasEl[i][1]] = 1;
        }
        if (!formVisto) {
          for (i = 0; i < camposEl.length; i++) if (naTela(camposEl[i])) { formVisto = 1; break; }
        }
      } catch (e) {}
    }
    function campo(n) { return campos[n] || (campos[n] = [0, 0, 0, 0]); }   /* focos, ms com foco, ficou preenchido, erros */
    /* a pessoa entrou no campo: e aqui que o formulario "comeca" */
    function contaFoco(n) {
      campo(n)[0]++; focoConta = 1; formUltimo = n; formVisto = 1;
      if (!formInicio) formInicio = agora();
    }
    /* o campo que ja estava selecionado quando este arquivo chegou (a pagina selecionou antes): fica em espera,
       sem contar, ate a pessoa digitar nele */
    function adotaFoco() {
      try {
        var el = document.activeElement, n = nomeCampo(el);
        if (n && !focoEm) { focoEm = n; focoEl = el; focoConta = 0; }
      } catch (e) {}
    }
    function preenchido(el) {
      var tipo = String(el.getAttribute('type') || '').toLowerCase();
      if (tipo === 'checkbox' || tipo === 'radio') return el.checked ? 1 : 0;
      return String(el.value || '').length > 0 ? 1 : 0;   /* so se tem algo: o valor nunca e lido */
    }
    document.addEventListener('focusin', function (ev) {
      try {
        var n = nomeCampo(ev.target);
        if (!n) return;
        if (focoEm) soltaFoco();   /* o campo anterior saiu sem avisar */
        if (camposNome.indexOf(n) < 0 && camposNome.length < 30) { camposNome.push(n); camposEl.push(ev.target); }
        focoEm = n; focoEl = ev.target; focoConta = 0;
        /* foco que a propria pagina deu (o campo ja vem selecionado quando ela abre) nao e a pessoa comecando o
           formulario: so conta o que vem logo depois de um toque, clique ou tecla, ou quando ela digita no campo */
        if (agora() - ultimoToque < 1000) contaFoco(n);
      } catch (e) {}
    }, true);
    /* digitou ou escolheu algo num campo (so o aviso do navegador: o que foi digitado nao e lido) */
    document.addEventListener('input', function (ev) {
      try {
        var n = nomeCampo(ev.target);
        if (!n) return;
        if (!focoEm && ev.target === document.activeElement) adotaFoco();
        if (focoEm === n && !focoConta) contaFoco(n);
        formUltimo = n; formFim = agora();
        if (!formInicio) formInicio = formFim;
      } catch (e) {}
    }, true);
    document.addEventListener('focusout', function (ev) {
      try {
        var n = nomeCampo(ev.target);
        if (!n) return;
        var c = campo(n), el = ev.target;
        if (focoEm === n) soltaFoco();
        c[2] = preenchido(el);
        if ((c[2] && el.validity && !el.validity.valid) || el.getAttribute('aria-invalid') === 'true') c[3]++;
        formFim = agora();
      } catch (e) {}
    }, true);
    document.addEventListener('change', function (ev) {
      try { var n = nomeCampo(ev.target); if (n) { campo(n)[2] = preenchido(ev.target); formUltimo = n; formFim = agora(); if (!formInicio) formInicio = formFim; } } catch (e) {}
    }, true);
    document.addEventListener('invalid', function (ev) {
      try { var n = nomeCampo(ev.target); if (n) campo(n)[3]++; } catch (e) {}
    }, true);
    document.addEventListener('submit', function () { formEnvios++; }, true);
    function leituraForm() {
      /* pagina sem formulario nao manda nada; formulario que a pagina tirou depois (trocou pelo "obrigado") continua valendo */
      if (!camposNome.length && !formVisto) return undefined;
      var c = {}, t = agora();
      for (var n in campos) {
        var x = campos[n];
        c[n] = [x[0], Math.round(x[1] / 1000), x[2], x[3]];
      }
      /* tempo do formulario: do primeiro campo em que a pessoa entrou ate a ultima coisa que ela fez nele. Com um
         campo ainda aberto, vai ate agora, mas para de contar 30 s depois do ultimo gesto (largou o celular) */
      var fim = focoEm && focoConta ? Math.max(formFim, Math.min(t, ultimaAcao + 30000)) : (formFim || t);
      return { v: formVisto, t: formInicio ? Math.round(Math.max(0, fim - formInicio) / 1000) : 0, s: formEnvios, u: formUltimo, c: c };
    }
    adotaFoco();
    /* o primeiro desenho mede as secoes: espera o primeiro quadro, quando o navegador ja montou a pagina por conta
       propria. Com "async", este arquivo pode rodar antes de a pagina estar montada: desenha de novo quando ela estiver */
    try { (window.requestAnimationFrame || function (f) { setTimeout(f, 50); })(desenho); } catch (e) { setTimeout(desenho, 50); }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', function () { setTimeout(desenho, 0); });
    setTimeout(desenho, 2000);
    setTimeout(desenho, 6000);

    /* erros de JavaScript da pagina (so a mensagem e o arquivo, sem pilha) */
    window.addEventListener('error', function (ev) {
      try { evento('erro', { msg: String(ev.message || '').slice(0, 160), arq: String(ev.filename || '').split('/').pop().slice(0, 80), linha: ev.lineno || 0 }); } catch (e) {}
    });

    /* eventos do funil: varre o dataLayer (so leitura), como o coletor de metricas. O lugar aproximado da
       VisitorAPI (quando a pagina ja tem) entra nas informacoes da visita; o IP nunca. */
    var lidos = 0;
    /* "rio de janeiro" vira "Rio de Janeiro"; a sigla do estado ("rj") vira "RJ" */
    function nomeDeLugar(v) {
      var s = String(v || '').trim().slice(0, 60);
      if (s.length <= 3) return s.toUpperCase();
      return s.toLowerCase().replace(/(^|[\s-])([a-z\u00e0-\u00ff])([a-z\u00e0-\u00ff']*)/g, function (m, antes, a, resto, pos) {
        return antes + (pos > 0 && /^(de|da|do|das|dos|e|del|la|el)$/.test(a + resto) ? a + resto : a.toUpperCase() + resto);
      });
    }
    function varre() {
      try {
        var dl = window.dataLayer || [];
        for (; lidos < dl.length; lidos++) {
          var item = dl[lidos];
          if (!item || typeof item !== 'object') continue;
          /* o que as tags de modelo do GTM empurram (a VisitorAPI) chega embrulhado em { value: {...} }: dali so
             interessa o lugar. Evento de tag do GTM nao e evento do funil da pagina (e contaria como engajamento) */
          var dentro = !item.event && item.value && typeof item.value === 'object' ? item.value : null;
          var lugar = dentro || item;
          if (lugar.visitorApiCity) info.cidade = nomeDeLugar(lugar.visitorApiCity);
          if (lugar.visitorApiRegion) info.estado = nomeDeLugar(lugar.visitorApiRegion).slice(0, 40);
          if (lugar.visitorApiCountryCode) info.pais = String(lugar.visitorApiCountryCode).slice(0, 2).toUpperCase();
          if (dentro) continue;
          if (!item.event || /^gtm\./.test(item.event)) continue;
          var d = { nome: String(item.event).slice(0, 60) };
          CHAVES_DL.forEach(function (k) { if (item[k] !== undefined && item[k] !== null) d[k] = String(item[k]).slice(0, 60); });
          evento('funil', d);
        }
      } catch (e) {}
    }

    /* velocidade real (Web Vitals), medida no navegador de quem visita: LCP (maior elemento na tela), CLS (quanto
       a pagina pula), INP (resposta ao toque), FCP (primeiro conteudo), TTFB (espera pelo servidor), carga completa,
       peso transferido e o tipo de rede. So numeros: nada da pagina sai daqui. LCP, CLS e INP crescem ate a saida. */
    var vitais = {};
    var vitaisEnviados = '';
    function observa(tipo, fn, extra) {
      try {
        if (!window.PerformanceObserver || (PerformanceObserver.supportedEntryTypes || []).indexOf(tipo) < 0) return;
        var opcoes = { type: tipo, buffered: true };
        if (extra) for (var k in extra) opcoes[k] = extra[k];
        new PerformanceObserver(function (lista) { try { lista.getEntries().forEach(fn); } catch (e) {} }).observe(opcoes);
      } catch (e) {}
    }
    observa('largest-contentful-paint', function (e) { vitais.lcp = Math.round(e.renderTime || e.loadTime || e.startTime); });
    observa('paint', function (e) { if (e.name === 'first-contentful-paint') vitais.fcp = Math.round(e.startTime); });
    var clsJanela = 0, clsInicio = 0, clsUltimo = 0;
    /* pagina que nao pula nada tambem e medida: CLS 0 (o navegador so avisa quando algo se mexe) */
    try { if ((PerformanceObserver.supportedEntryTypes || []).indexOf('layout-shift') >= 0) vitais.cls = 0; } catch (e) {}
    observa('layout-shift', function (e) {
      if (e.hadRecentInput) return;
      if (clsJanela && e.startTime - clsUltimo < 1000 && e.startTime - clsInicio < 5000) clsJanela += e.value;
      else { clsJanela = e.value; clsInicio = e.startTime; }
      clsUltimo = e.startTime;
      if (!(vitais.cls >= clsJanela)) vitais.cls = Math.round(clsJanela * 10000) / 10000;
    });
    function interacao(e) { if ((e.interactionId || e.entryType === 'first-input') && !(vitais.inp >= e.duration)) vitais.inp = Math.round(e.duration); }
    observa('first-input', interacao);
    observa('event', interacao, { durationThreshold: 16 });
    function navegacao() {
      try {
        var n = performance.getEntriesByType && performance.getEntriesByType('navigation')[0];
        if (n) {
          var ini = n.activationStart || 0;
          if (n.responseStart > 0) vitais.ttfb = Math.round(Math.max(0, n.responseStart - ini));
          if (n.loadEventEnd > 0) vitais.carga = Math.round(Math.max(0, n.loadEventEnd - ini));
          var peso = n.transferSize || 0;
          (performance.getEntriesByType('resource') || []).forEach(function (r) { peso += r.transferSize || 0; });
          if (peso) vitais.peso = Math.round(peso / 1024);
        }
        var rede = navigator.connection && navigator.connection.effectiveType;
        if (rede) vitais.rede = String(rede).slice(0, 10);
      } catch (e) {}
    }

    /* envio: lotes a cada 3 s, sempre como texto puro (o navegador nao pede licenca antes e o beacon da saida
       funciona). No maximo 300 eventos por pacote (o resto vai no seguinte). As informacoes da visita vao no primeiro pacote de cada pagina e de novo so quando mudam. */
    function dadosSessao(comInfo) {
      var s = { id: sessao, visitante: visitante, teste: teste, origem: origem, dispositivo: dispositivo };
      if (comInfo) s.info = info;
      return s;
    }
    function dadosPagina() {
      var d = { id: pv, caminho: location.pathname, titulo: document.title.slice(0, 120), inicio: inicio,
                largura: largura || (largura = window.innerWidth || document.documentElement.clientWidth || 0), altura: window.innerHeight, altura_doc: alturaDoc(), rolagem: rolagemMax,
                visivel_ms: visivelTotal, ativo_ms: ativoTotal, vaivem: vaivem, vitais: vitais };
      /* a leitura vai de carona em todo pacote (numeros que so crescem; o banco fica com o maior) e o desenho da
         pagina, so quando muda */
      try {
        d.r30 = rolagem30; d.secoes = secoesSeg; d.ctas = ctasVisto; d.form = leituraForm();
        var m = JSON.stringify({ s: secoesNome, c: ctasNome, f: camposNome });
        if (m !== mapaEnviado) { mapaEnviado = m; d.mapa = { s: secoesNome, c: ctasNome, f: camposNome }; }
      } catch (e) {}
      return d;
    }
    function pacote(final, sempre) {
      mede(); varre(); navegacao(); leAparelho();
      var v = JSON.stringify(vitais);
      var i = JSON.stringify(info);
      if (!fila.length && !final && !sempre && v === vitaisEnviados && i === infoEnviada) return null;
      vitaisEnviados = v;
      var comInfo = i !== infoEnviada;
      infoEnviada = i;
      if (visivelDesde) { visivelTotal += agora() - visivelDesde; visivelDesde = document.visibilityState === 'visible' ? agora() : 0; }
      return {
        v: 2, projeto: PROJETO, seq: seq++, final: final ? 1 : 0,
        sessao: dadosSessao(comInfo), pv: dadosPagina(),
        eventos: fila.splice(0, 300)
      };
    }
    function beacon(obj) {
      var corpo = JSON.stringify(obj);
      try {
        if (corpo.length < 60000 && navigator.sendBeacon && navigator.sendBeacon(COLETA, new Blob([corpo], { type: 'text/plain' }))) return;
        fetch(COLETA, { method: 'POST', body: corpo, keepalive: corpo.length < 60000, headers: { 'Content-Type': 'text/plain' } }).catch(function () {});
      } catch (e) {}
    }
    function manda(p, saindo) {
      if (!p || parado) return;
      try {
        /* na saida da pagina vai pelo beacon (o navegador garante o envio mesmo fechando a aba) */
        if (saindo) { beacon(p); return; }
        envia(JSON.stringify(p));
      } catch (e) {}
    }
    /* o que o coletor responde: "ok" e "repetido" seguem; "pausado", "limite", "dominio" e "projeto" desligam o
       gravador neste navegador por um tempo; falha de rede ou do banco conta (3 seguidas = 10 min parado) */
    var falhasSeguidas = 0;
    function envia(corpo) {
      if (parado) return;
      fetch(COLETA, { method: 'POST', body: corpo, headers: { 'Content-Type': 'text/plain' } }).then(function (r) {
        /* 429 e 413 tambem trazem a resposta em texto ("limite", "tamanho") */
        return r.text().then(ouvir, falhou);
      }, falhou);
    }
    function ouvir(texto) {
      try {
        var r = String(texto || '').replace(/"/g, '').trim();
        if (r === 'pausado') return parar(30);
        if (r === 'limite') return parar(5);
        if (r === 'dominio' || r === 'projeto') return parar(60);
        if (r !== 'ok' && r !== 'repetido') return falhou();
        falhasSeguidas = 0;
      } catch (e) {}
    }
    function falhou() { falhasSeguidas++; if (falhasSeguidas >= 3) parar(10); }
    function parar(minutos) {
      if (parado) return;
      parado = true;
      try { localStorage.setItem('radar_pausa', String(agora() + minutos * 60000)); } catch (e) {}
      try { clearInterval(relogio); clearInterval(relogioRolagem); clearInterval(relogioAtivo); if (olhoCta) olhoCta.disconnect(); if (olhoAltura) olhoAltura.disconnect(); } catch (e) {}
      fila.length = 0;
    }
    var relogio = setInterval(function () { manda(pacote(false), false); }, 3000);
    var saiu = false;
    function sai() { if (saiu) return; saiu = true; clearInterval(relogio); manda(pacote(true), true); }
    window.addEventListener('pagehide', sai);
    document.addEventListener('visibilitychange', function () {
      /* pagina escondida (trocou de aba ou de app): manda sempre, mesmo sem evento novo. No celular a pagina pode nunca
         avisar que fechou, e sem isso o tempo, a rolagem e a leitura do fim da visita se perdiam */
      if (document.visibilityState === 'hidden') { manda(pacote(false, true), true); }
      else if (!visivelDesde) { visivelDesde = agora(); }
    });

    evento('pagina', { ref: origem.referrer || '' });
    varre();

  } catch (e) {}
})();
