// =============================================================================
// The billing screen's item list, for the customer pages (/order table QR and
// /store online store). Mirrors frontend/lib/screens/home_screen.dart:
//
//   * one strip at the top — major categories once the menu uses them, else
//     the category chips. A jump-list: a tap scrolls (opening if folded), and
//     the lit chip follows the scroll.
//   * every major open by default; its card folds it shut / spreads it open.
//   * sub-categories are an accordion (one open at a time, the first one opened
//     on load). A menu with no majors keeps flat, independently-folding bars.
//   * 40px rows: name | price | − qty +. A dish with sizes unfolds its size
//     rows beneath it in place (one at a time).
//   * two independent columns at >= 1200px, cart panel at >= 720px, a cart
//     button + bottom sheet below that.
//
// Served at /order/menu-list.js (see server.js). Pages own the OTP / checkout /
// order-status parts and talk to this through the object MenuList() returns.
// =============================================================================
(function () {
  'use strict';

  // Mirrors MAX_LINE_QTY in src/menuPricing.js, which rejects the whole order
  // above it — the box must not accept a number that bounces at checkout.
  var MAX_QTY = 50;
  var WIDE = 720;      // home_screen.dart: isWide
  var TWO_COLS = 1200; // home_screen.dart: _twoColumns

  function svg(d) { return '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="' + d + '"/></svg>'; }
  var ICON = {
    more: svg('M16.59 8.59 12 13.17 7.41 8.59 6 10l6 6 6-6z'),
    right: svg('M10 6 8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z'),
    plus: svg('M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z'),
    minus: svg('M19 13H5v-2h14v2z'),
    search: svg('M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z'),
    close: svg('M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z'),
    cart: svg('M15.55 13c.75 0 1.41-.41 1.75-1.03l3.58-6.49A1 1 0 0 0 20.01 4H5.21l-.94-2H1v2h2l3.6 7.59-1.35 2.44C4.52 15.37 5.48 17 7 17h12v-2H7l1.1-2h7.45zM6.16 6h12.15l-2.76 5H8.53L6.16 6zM7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zm10 0c-1.1 0-1.99.9-1.99 2s.89 2 1.99 2 2-.9 2-2-.9-2-2-2z'),
    dish: svg('M11 9H9V2H7v7H5V2H3v7c0 2.12 1.66 3.84 3.75 3.97V22h2.5v-9.03C11.34 12.84 13 11.12 13 9V2h-2v7zm5-3v8h2.5v8H21V2c-2.76 0-5 2.24-5 4z'),
    searchOff: svg('M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z'),
  };

  // Tokens are lib/theme/app_theme.dart's AppColors / AppRadius; sizes are the
  // fixed extents _ExcelItemTable lays out with (major 50, sub 46, row 41).
  var STYLES = [
    ':root{--primary:#4F46E5;--primary-dark:#3730A3;--primary-light:#EEF2FF;--accent-light:#D1FAE5;',
    '--bg:#F8F9FC;--surface:#fff;--surface-variant:#F1F5F9;--border:#E2E8F0;--text:#0F172A;',
    '--muted:#64748B;--disabled:#CBD5E1;--danger:#EF4444;--grad:linear-gradient(135deg,#4F46E5 0%,#7C3AED 100%);',
    '--r-sm:10px;--r-md:14px;--r-lg:20px}',
    '*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}',
    'html,body{margin:0;padding:0;height:100%}',
    'body{font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:var(--bg);',
    'color:var(--text);-webkit-font-smoothing:antialiased;overflow:hidden}',
    'button,input,textarea{font-family:inherit}',
    'svg{width:20px;height:20px;fill:currentColor;flex:0 0 auto}',
    '.ml-app{display:flex;flex-direction:column;height:100vh;height:100dvh}',
    // app bar
    '.ml-bar{flex:0 0 auto;height:56px;display:flex;align-items:center;gap:4px;padding:0 4px 0 16px;',
    'background:var(--surface);border-bottom:1px solid var(--border)}',
    '.ml-title{flex:1;min-width:0}',
    '.ml-name{font-size:18px;font-weight:700;letter-spacing:-.2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.ml-chip{display:inline-block;max-width:100%;margin-top:2px;padding:1px 6px;border-radius:4px;background:var(--primary-light);',
    'color:var(--primary);font-size:11px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;vertical-align:top}',
    '.ml-chip:empty{display:none}',
    '.ml-search{display:none;flex:1;min-width:0;height:40px;border:1px solid var(--border);border-radius:var(--r-sm);',
    'padding:0 12px;font-size:14px;color:var(--text);background:var(--surface)}',
    '.ml-search:focus{outline:none;border-color:var(--primary)}',
    '.ml-bar.searching .ml-title{display:none}.ml-bar.searching .ml-search{display:block}',
    '.ml-ibtn{width:40px;height:40px;flex:0 0 auto;border:0;background:none;color:var(--muted);border-radius:999px;',
    'display:flex;align-items:center;justify-content:center;cursor:pointer;text-decoration:none;padding:0}',
    // body: items | cart panel
    '.ml-body{flex:1;min-height:0;display:flex}',
    '.ml-items{flex:1;min-width:0;display:flex;flex-direction:column}',
    '.ml-aside{display:none;width:360px;flex:0 0 360px;border-left:1px solid var(--border);background:var(--surface)}',
    '@media (min-width:' + WIDE + 'px){.ml-aside{display:block}.ml-fab{display:none!important}}',
    // chip strip — one row while it fits, else a two-row grid; scrolls sideways
    '.ml-strip{position:relative;flex:0 0 auto;background:var(--surface);overflow-x:auto;scrollbar-width:none;padding:6px 12px}',
    '.ml-strip::-webkit-scrollbar{display:none}.ml-strip[hidden]{display:none}',
    '.ml-chips{display:grid;grid-auto-flow:column;grid-auto-columns:minmax(max-content,1fr);gap:6px 8px;min-width:100%;width:max-content}',
    '.ml-chips.two{grid-template-rows:auto auto}',
    '.ml-chips button{height:32px;padding:0 12px;border:1px solid var(--border);background:var(--surface-variant);',
    'color:var(--muted);font-size:13px;font-weight:500;border-radius:var(--r-sm);cursor:pointer;white-space:nowrap}',
    '.ml-chips button.on{background:var(--primary);border-color:var(--primary);color:#fff;font-weight:600}',
    // list
    '.ml-scroll{flex:1;min-height:0;overflow-y:auto;position:relative;padding-bottom:80px;-webkit-overflow-scrolling:touch}',
    '.ml-extra{padding:8px 8px 0;display:grid;gap:8px}.ml-extra:empty{display:none}',
    '.ml-mj{height:50px;padding:10px 8px 0}',
    '.ml-mj button{width:100%;height:40px;display:flex;align-items:center;gap:8px;padding:0 12px;border:0;',
    'border-radius:var(--r-sm);background:var(--primary-light);font-size:15px;font-weight:700;color:var(--text);cursor:pointer;text-align:left}',
    '.ml-mj span,.ml-sub .lbl,.ml-cell .nm{min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.ml-mj span{flex:1}',
    '.ml-mj svg{width:22px;height:22px;color:var(--muted);transition:transform .3s}.ml-mj.open svg{transform:rotate(180deg)}',
    '.ml-sub{height:46px;padding:0 8px;display:flex}',
    // the tree rail: a neutral line down an 11px gutter, with an elbow to each sub card
    '.ml-rail{flex:0 0 11px;position:relative}',
    '.ml-rail::before{content:"";position:absolute;left:4.75px;top:0;bottom:0;width:1.5px;background:var(--border)}',
    '.ml-sub .ml-rail::after{content:"";position:absolute;left:5.5px;right:0;top:25.25px;height:1.5px;background:var(--border)}',
    '.ml-sub .ml-rail.last::before{bottom:auto;height:26px}',
    '.ml-sub button{flex:1;min-width:0;margin-top:6px;height:40px;display:flex;align-items:center;gap:8px;',
    'padding:0 8px 0 12px;border:1px solid var(--border);border-radius:var(--r-sm);background:var(--surface);cursor:pointer;text-align:left}',
    '.ml-sub.open button{border-color:var(--primary);background:var(--primary-light);border-radius:var(--r-sm) var(--r-sm) 0 0}',
    '.ml-sub .lbl{font-size:13px;font-weight:700;color:var(--text)}.ml-sub.open .lbl{color:var(--primary)}',
    '.ml-sub .ml-pill{flex:0 0 auto;padding:2px 7px;border-radius:999px;background:var(--surface-variant);',
    'color:var(--muted);font-size:10.5px;font-weight:600}',
    '.ml-sub.open .ml-pill{background:rgba(79,70,229,.12);color:var(--primary)}',
    '.ml-sub .grow{flex:1}',
    '.ml-sub svg{width:22px;height:22px;color:var(--muted);transition:transform .3s}',
    '.ml-sub.open svg{color:var(--primary);transform:rotate(-90deg)}',
    // item rows inside an open sub's box
    '.ml-row{height:41px;padding:0 8px;display:flex}',
    '.ml-frame{flex:1;min-width:0;display:flex;background:var(--surface);border:1px solid var(--primary);border-width:0 1px}',
    '.ml-row:not(.last) .ml-frame{border-bottom:1px solid var(--border)}',
    '.ml-row.last .ml-frame{border-bottom-width:1px;border-radius:0 0 var(--r-sm) var(--r-sm);overflow:hidden}',
    '.ml-sep{flex:0 0 1px;background:var(--border)}',
    '.ml-cell{flex:1;min-width:0;background:var(--surface);user-select:none;-webkit-user-select:none}',
    '.ml-cell.open,.ml-cell.nested{background:#FAFBFF}.ml-cell.in{background:#EEF2FF}',
    '.ml-cell[data-act]{cursor:pointer}',
    '.ml-in{height:100%;display:flex;align-items:center;padding:0 10px}',
    '.ml-cell.nested .ml-in{margin-left:16px;border-left:3px solid var(--primary);padding-left:8px}',
    '.ml-cell .nm{flex:1;font-size:13px;color:var(--text)}',
    '.ml-cell.in .nm{font-weight:600;color:var(--primary-dark)}',
    // Dish photo, always on show. Fits the 40px row, so the list keeps the
    // billing screen's rhythm; a tap opens it full size.
    '.ml-cell .th{width:32px;height:32px;flex:0 0 32px;margin-right:8px;border-radius:6px;object-fit:cover;',
    'background:var(--surface-variant)}.ml-cell img.th{cursor:zoom-in}',
    '.ml-cell span.th{display:flex;align-items:center;justify-content:center;color:var(--disabled)}',
    '.ml-cell span.th svg{width:18px;height:18px}.ml-app.pics .ml-cell span.th svg{width:26px;height:26px}',
    // A menu with photos gets taller rows so a dish can actually be seen, and
    // its name may take two lines. Without photos it stays the billing list.
    '.ml-app.pics .ml-row{height:65px}',
    '.ml-app.pics .ml-cell .th{width:52px;height:52px;flex-basis:52px;margin-right:10px;border-radius:8px}',
    '.ml-app.pics .ml-cell .nm{white-space:normal;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;line-height:1.3}',
    '.ml-cell .pr{flex:0 0 72px;text-align:right;font-size:12px;font-weight:500;color:var(--muted);white-space:nowrap;overflow:hidden}',
    '.ml-st{flex:0 0 112px;margin-left:8px;display:flex;align-items:center}',
    '.ml-st button{width:28px;height:28px;flex:0 0 28px;border:0;border-radius:8px;background:var(--primary);color:#fff;',
    'display:flex;align-items:center;justify-content:center;padding:0;cursor:pointer;transition:background .15s}',
    '.ml-st button svg{width:16px;height:16px}',
    '.ml-st button.off{background:var(--surface-variant);color:var(--muted);cursor:default}',
    '.ml-st input,.ml-st .q{flex:1;min-width:0;width:0;height:28px;border:0;background:transparent;text-align:center;',
    'font-size:13px;font-weight:700;color:var(--primary);padding:0;line-height:28px}',
    '.ml-st input:focus{outline:none}.ml-st input::placeholder{color:var(--disabled);font-weight:400}',
    '.ml-st .q.none{color:var(--disabled)}',
    '.ml-empty{display:flex;flex-direction:column;align-items:center;gap:12px;padding:64px 16px;color:var(--muted);font-size:14px}',
    '.ml-empty svg{width:40px;height:40px;color:var(--disabled)}',
    // cart panel (aside on wide, bottom sheet on narrow)
    '.ml-cp{display:flex;flex-direction:column;height:100%;min-height:0}',
    '.backdrop .ml-cp{height:auto;max-height:88vh}',
    '.ml-grab{width:36px;height:4px;border-radius:2px;background:var(--border);margin:10px auto 4px}',
    '.ml-cph{display:flex;align-items:center;gap:12px;padding:16px 16px 8px}',
    '.ml-tile{width:36px;height:36px;border-radius:var(--r-sm);background:var(--grad);color:#fff;display:flex;align-items:center;justify-content:center}',
    '.ml-tile svg{width:18px;height:18px}',
    '.ml-cph b{font-size:18px;font-weight:700}',
    '.ml-cnt{padding:2px 8px;border-radius:999px;background:var(--primary-light);color:var(--primary);font-size:12px;font-weight:700}',
    '.ml-lines{flex:1 1 auto;min-height:0;overflow-y:auto}',
    '.ml-line{display:flex;align-items:center;gap:8px;padding:6px 16px}',
    '.ml-line .i{flex:1;min-width:0}',
    '.ml-line .n{font-size:14px;font-weight:500;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}',
    '.ml-line .a{font-size:12px;font-weight:600;color:var(--primary)}',
    '.ml-qb{display:flex;align-items:center;background:var(--surface-variant);border:1px solid var(--border);border-radius:var(--r-sm)}',
    '.ml-qb button{border:0;background:none;padding:6px;color:var(--primary);display:flex;cursor:pointer}',
    '.ml-qb svg{width:16px;height:16px}',
    '.ml-cp .ml-qb input{width:34px;margin:0;border:0;border-radius:0;background:transparent;text-align:center;font-size:14px;font-weight:600;color:var(--text);padding:0}',
    '.ml-cp .ml-qb input:focus{outline:none;background:transparent}',
    '.ml-cpe{display:flex;flex-direction:column;align-items:center;gap:12px;padding:24px 16px;color:var(--muted);font-size:14px}',
    '.ml-cpe span{width:56px;height:56px;border-radius:var(--r-lg);background:var(--surface-variant);color:var(--disabled);',
    'display:flex;align-items:center;justify-content:center}.ml-cpe svg{width:28px;height:28px}',
    '.ml-cpf{padding:12px 16px 16px;border-top:1px solid var(--border)}',
    '.ml-tot{display:flex;justify-content:space-between;font-size:16px;font-weight:800;margin-bottom:12px}',
    '.ml-go{width:100%;height:48px;border:0;border-radius:var(--r-md);background:var(--primary);color:#fff;',
    'font-size:15px;font-weight:700;cursor:pointer}.ml-go:disabled{opacity:.5;cursor:default}',
    '.ml-note{margin-top:8px;font-size:12px;line-height:1.4;color:var(--muted,#64748b);text-align:center}',
    '.ml-note a{color:inherit;text-decoration:underline}',
    '.ml-fab{position:fixed;left:16px;right:16px;bottom:16px;z-index:30}.ml-fab[hidden]{display:none}',
    '.ml-fab button{width:100%;height:48px;border:0;border-radius:16px;background:var(--primary);color:#fff;font-size:14px;',
    'font-weight:600;display:flex;align-items:center;justify-content:center;gap:8px;box-shadow:0 4px 12px rgba(15,23,42,.25);cursor:pointer}',
    // shared by the pages: sheets, inputs, banners, toast, photo lightbox
    '.backdrop{position:fixed;inset:0;background:rgba(15,23,42,.5);z-index:40;display:none;align-items:flex-end}',
    '.backdrop.show{display:flex}',
    '.sheet{background:var(--surface);width:100%;max-width:560px;margin:0 auto;border-radius:var(--r-lg) var(--r-lg) 0 0;padding:24px;',
    'box-shadow:0 -8px 40px rgba(15,23,42,.2);max-height:88vh;overflow-y:auto}',
    '.sheet.flush{padding:0}',
    '.sheet h2{margin:0 0 6px;font-size:20px;font-weight:700}',
    '.sheet p{margin:0 0 18px;color:var(--muted);font-size:14px;line-height:1.5}',
    '.sheet input,.sheet textarea{width:100%;padding:14px;border:1px solid var(--border);border-radius:var(--r-sm);font-size:16px;',
    'margin-bottom:12px;background:var(--surface-variant);color:var(--text)}',
    '.sheet input:focus,.sheet textarea:focus{outline:none;border-color:var(--primary);background:var(--surface)}',
    '.sheet .btn{width:100%;padding:15px;background:var(--primary);color:#fff;border:0;border-radius:var(--r-md);',
    'font-size:16px;font-weight:600;cursor:pointer}.sheet .btn:disabled{opacity:.5}',
    '.sheet .link{display:block;margin:-4px 0 12px;padding:0;border:0;background:none;color:var(--primary);',
    'font-size:14px;font-weight:600;cursor:pointer}.sheet .link:disabled{color:var(--muted);cursor:default}',
    '.sheet .err{color:var(--danger);font-size:13px;margin:-6px 0 12px;min-height:16px;font-weight:500}',
    '.running{background:var(--accent-light);border:1px solid #a7f3d0;border-radius:var(--r-md);padding:12px 14px}',
    '.running h3{margin:0 0 8px;font-size:14px;color:#047857;font-weight:700;display:flex;align-items:center;gap:8px}',
    '.running .row{display:flex;justify-content:space-between;gap:12px;font-size:13px;padding:3px 0}',
    '.running .row .st{font-size:11px;color:var(--muted);font-weight:500}',
    '.center{text-align:center;padding:48px 20px;color:var(--muted);font-size:14px}',
    '.toast{position:fixed;left:50%;bottom:90px;transform:translateX(-50%);background:var(--text);color:#fff;padding:12px 22px;',
    'border-radius:999px;font-weight:600;z-index:70;opacity:0;transition:opacity .25s;font-size:14px;pointer-events:none}',
    '.toast.show{opacity:1}',
    '.lightbox{position:fixed;inset:0;background:rgba(15,23,42,.86);z-index:60;display:none;align-items:center;justify-content:center;padding:20px}',
    '.lightbox.show{display:flex}',
    '.lightbox img{max-width:100%;max-height:80vh;border-radius:var(--r-md)}',
    '.lightbox .cap{position:absolute;left:0;right:0;bottom:28px;text-align:center;color:#fff;font-size:15px;font-weight:600;padding:0 24px}',
    '.lightbox .close{position:absolute;top:16px;right:16px;width:40px;height:40px;border-radius:999px;border:0;',
    'background:rgba(255,255,255,.18);color:#fff;font-size:22px;cursor:pointer}',
  ].join('');

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }
  function trim(s) { return s == null ? '' : String(s).trim(); }
  // Dart's String.compareTo — code-unit order, so the strip sorts like the app.
  function cmp(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
  function uniqSorted(arr) {
    return arr.filter(function (v, i) { return v && arr.indexOf(v) === i; }).sort(cmp);
  }
  function money(n) { return '₹' + Number(n).toFixed(2); }
  function label(s) { return s === '' ? 'Other' : s; }
  function keyOf(itemId, variantId) { return itemId + '::' + (variantId || ''); }
  function hasSizes(item) { return !!(item.variants && item.variants.length); }

  // null when there is no usable price, so "free" and "not priced" stay apart —
  // the server refuses an unpriced line (menuPricing.js), so it is not offered.
  function unitPrice(item, variantId) {
    if (variantId) {
      var v = item.variants.find(function (x) { return x.id === variantId; });
      if (v && v.price != null) return Number(v.price);
    }
    return item.price == null ? null : Number(item.price);
  }

  window.MenuList = function (opts) {
    opts = opts || {};
    var style = document.createElement('style');
    style.textContent = STYLES;
    document.head.appendChild(style);

    var root = document.createElement('div');
    root.className = 'ml-app';
    root.innerHTML =
      '<header class="ml-bar"><div class="ml-title"><div class="ml-name">Loading…</div><div class="ml-chip"></div></div>' +
      '<input class="ml-search" type="search" placeholder="Search items" autocomplete="off">' +
      '<button class="ml-ibtn" data-search aria-label="Search">' + ICON.search + '</button><span class="ml-acts"></span></header>' +
      '<div class="ml-body"><div class="ml-items"><div class="ml-strip" hidden><div class="ml-chips"></div></div>' +
      '<div class="ml-scroll"><div class="ml-extra"></div><div class="ml-list"><div class="center">Loading menu…</div></div></div></div>' +
      '<aside class="ml-aside"></aside></div>' +
      '<div class="ml-fab" hidden><button>' + ICON.cart + '<span></span></button></div>';
    document.body.insertBefore(root, document.body.firstChild);
    document.body.insertAdjacentHTML('beforeend',
      '<div class="backdrop" data-cartsheet><div class="sheet flush"></div></div>' +
      '<div class="toast"></div>' +
      '<div class="lightbox"><button class="close" aria-label="Close">×</button><img alt=""><div class="cap"></div></div>');

    function q(sel) { return document.querySelector(sel); }
    var bar = q('.ml-bar'), searchInput = q('.ml-search'), searchBtn = q('[data-search]');
    var strip = q('.ml-strip'), chipsEl = q('.ml-chips');
    var scroller = q('.ml-scroll'), listEl = q('.ml-list'), extraEl = q('.ml-extra');
    var aside = q('.ml-aside'), sheetBg = q('[data-cartsheet]'), sheetEl = sheetBg.firstChild;
    var fab = q('.ml-fab'), toastEl = q('.toast'), lightbox = q('.lightbox');

    // ---- state (names follow _HomeScreenState) ------------------------------
    var items = [], byId = new Map(), majors = [], cats = [];
    var hasImages = false;                // any photo at all → every dish keeps a slot
    var cart = new Map();                 // key -> { item_id, variant_id, name, price, qty }
    var query = '';
    var collapsedMajors = new Set();      // every major open unless folded shut
    var expandedCats = new Set();         // accordion: at most one section key
    var collapsedCats = new Set();        // flat menu: each folds on its own
    var openVariant = null;               // item id whose sizes are unfolded
    var autoOpened = false;
    var activeMajor = null, activeCat = null;
    var tree = [], majorList = [], secList = [];
    var chipKind = null, chipVals = [];
    var jumping = false, jumpTimer = null;
    var twoCols = window.innerWidth >= TWO_COLS;
    var busy = false;

    function isFlat() { return !tree.length || tree[0].major === null; }

    function filtered() {
      if (!query) return items;
      // Name or category, the same rule the billing search uses.
      return items.filter(function (i) {
        return i.name.toLowerCase().indexOf(query) !== -1 ||
          trim(i.category).toLowerCase().indexOf(query) !== -1;
      });
    }

    function sectionKey(major, cat) { return major === null ? cat : major + '\u0000' + cat; }

    function groupByCategory(list, major) {
      var by = new Map();
      list.forEach(function (i) {
        var c = trim(i.category);
        if (!by.has(c)) by.set(c, []);
        by.get(c).push(i);
      });
      var ordered = cats.filter(function (c) { return by.has(c); });
      if (by.has('')) ordered.push('');
      return ordered.map(function (c) {
        var key = sectionKey(major, c);
        return {
          cat: c, key: key, major: major, items: by.get(c),
          expanded: !!query || (major === null ? !collapsedCats.has(key) : expandedCats.has(key)),
        };
      });
    }

    function buildTree() {
      var list = filtered();
      if (!majors.length) return [{ major: null, expanded: true, subs: groupByCategory(list, null) }];
      var by = new Map();
      list.forEach(function (i) {
        var m = trim(i.major_category);
        if (!by.has(m)) by.set(m, []);
        by.get(m).push(i);
      });
      var ordered = majors.filter(function (m) { return by.has(m); });
      // Items with no major of their own go last, under "Other".
      if (by.has('')) ordered.push('');
      return ordered.map(function (m) {
        return { major: m, expanded: !!query || !collapsedMajors.has(m), subs: groupByCategory(by.get(m), m) };
      });
    }

    // ---- rendering ------------------------------------------------------------
    function qtyFor(itemId) {
      var n = 0;
      cart.forEach(function (l) { if (l.item_id === itemId) n += l.qty; });
      return n;
    }

    function stepper(k, ids, inCart, line, price) {
      return '<span class="ml-st"><button data-act="dec"' + ids + (inCart ? '' : ' class="off"') +
        ' aria-label="One less">' + ICON.minus + '</button>' +
        '<input data-act="q" data-k="' + esc(k) + '"' + ids + ' inputmode="numeric" placeholder="—" aria-label="Quantity"' +
        (inCart ? ' value="' + line.qty + '"' : ' readonly') + '>' +
        '<button data-act="add"' + ids + (price == null ? ' class="off" title="Not available"' : '') +
        ' aria-label="Add">' + ICON.plus + '</button></span>';
    }

    // Leads the row. A dish without a photo gets a placeholder tile of the same
    // size while the menu has any photos, so the names stay in one column.
    function photo(item) {
      if (item.image_url) {
        return '<img class="th" src="' + esc(item.image_url) + '" alt="" loading="lazy" data-act="img" data-id="' +
          esc(item.id) + '">';
      }
      return hasImages ? '<span class="th" aria-hidden="true">' + ICON.dish + '</span>' : '';
    }

    // A dish (no sizes) or one size row of a dish.
    function lineCell(item, v) {
      var k = keyOf(item.id, v && v.id), line = cart.get(k), inCart = !!line;
      var price = unitPrice(item, v && v.id);
      var ids = ' data-id="' + esc(item.id) + '"' + (v ? ' data-vid="' + esc(v.id) + '"' : '');
      return '<div class="ml-cell' + (inCart ? ' in' : '') + (v ? ' nested' : '') + '"><div class="ml-in">' +
        (v ? '' : photo(item)) + '<span class="nm">' + esc(v ? v.label : item.name) + '</span>' +
        '<span class="pr">' + (price == null ? '' : money(price)) + '</span>' +
        stepper(k, ids, inCart, line, price) + '</div></div>';
    }

    // A dish with sizes: owns no price, and every tap on it unfolds its sizes.
    function parentCell(item) {
      var n = qtyFor(item.id), ids = ' data-act="var" data-id="' + esc(item.id) + '"';
      return '<div class="ml-cell' + (n > 0 ? ' in' : '') + (openVariant === item.id ? ' open' : '') + '"' + ids + '>' +
        '<div class="ml-in">' + photo(item) + '<span class="nm">' + esc(item.name) + '</span><span class="pr"></span>' +
        '<span class="ml-st"><button' + ids + (n > 0 ? '' : ' class="off"') + '>' + ICON.minus + '</button>' +
        '<span class="q' + (n > 0 ? '' : ' none') + '">' + (n > 0 ? n : '—') + '</span>' +
        '<button' + ids + '>' + ICON.plus + '</button></span></div></div>';
    }

    function cellHtml(c) {
      if (!c) return '<div class="ml-cell"></div>';
      if (c.v) return lineCell(c.item, c.v);
      return hasSizes(c.item) ? parentCell(c.item) : lineCell(c.item, null);
    }

    // Two INDEPENDENT column streams zipped into rows (_sectionEntries): dishes
    // alternate between columns, and an open dish's sizes lengthen only its own.
    function rowsHtml(s, railed) {
      var columns = twoCols ? [[], []] : [[]];
      s.items.forEach(function (item, i) {
        var col = columns[i % columns.length];
        col.push({ item: item });
        if (hasSizes(item) && openVariant === item.id) {
          item.variants.forEach(function (v) { col.push({ item: item, v: v }); });
        }
      });
      var rows = Math.max.apply(null, columns.map(function (c) { return c.length; }));
      var h = '';
      for (var r = 0; r < rows; r++) {
        var cells = columns.map(function (c) { return cellHtml(c[r]); });
        h += '<div class="ml-row' + (r === rows - 1 ? ' last' : '') + '">' + (railed ? '<span class="ml-rail"></span>' : '') +
          '<div class="ml-frame">' + cells.join('<span class="ml-sep"></span>') + '</div></div>';
      }
      return h;
    }

    function render() {
      tree = buildTree();
      // First load: spread the very first category open so there is something
      // to tap straight away. Once only, and never during a search.
      var first = tree.find(function (m) { return m.subs.length; });
      if (!autoOpened && first && !query) {
        autoOpened = true;
        expandedCats.clear();
        expandedCats.add(first.subs[0].key);
        activeCat = first.subs[0].key;
        tree = buildTree();
      }
      var railed = !isFlat();
      majorList = [];
      secList = [];
      var h = '';
      tree.forEach(function (m) {
        if (m.major !== null) {
          h += '<div class="ml-mj' + (m.expanded ? ' open' : '') + '" data-mi="' + majorList.length + '">' +
            '<button data-act="mj" data-mi="' + majorList.length + '"><span>' + esc(label(m.major)) + '</span>' +
            ICON.more + '</button></div>';
          majorList.push(m.major);
        }
        if (!m.expanded) return;
        m.subs.forEach(function (s, i) {
          var si = secList.push(s) - 1;
          h += '<div class="ml-sec" data-si="' + si + '"><div class="ml-sub' + (s.expanded ? ' open' : '') + '">' +
            (railed ? '<span class="ml-rail' + (i === m.subs.length - 1 ? ' last' : '') + '"></span>' : '') +
            '<button data-act="sec" data-si="' + si + '"><span class="lbl">' + esc(label(s.cat)) + '</span>' +
            '<span class="ml-pill">' + s.items.length + (s.items.length === 1 ? ' item' : ' items') + '</span>' +
            '<span class="grow"></span>' + ICON.right + '</button></div>' +
            (s.expanded ? rowsHtml(s, railed) : '') + '</div>';
        });
      });
      if (!secList.length) {
        h = '<div class="ml-empty">' + ICON.searchOff + (items.length ? 'No items found' : 'No items on the menu yet') + '</div>';
      }
      listEl.innerHTML = h;
      renderStrip();
      renderCart();
    }

    // ---- chip strip -----------------------------------------------------------
    function renderStrip() {
      var kind, vals;
      if (majors.length) {
        kind = 'major';
        vals = majors;
      } else {
        // The sections actually on screen; every category as a hint when the
        // search matched nothing.
        var subs = tree.length ? tree[0].subs : [];
        kind = 'cat';
        vals = subs.length ? subs.map(function (s) { return s.cat; }) : cats;
      }
      strip.hidden = !vals.length;
      if (kind !== chipKind || vals.join('\u0001') !== chipVals.join('\u0001')) {
        chipKind = kind;
        chipVals = vals;
        chipsEl.innerHTML = vals.map(function (v, i) {
          return '<button data-ci="' + i + '">' + esc(label(v)) + '</button>';
        }).join('');
        layoutChips();
      }
      lightChips();
    }

    // One row while the chips fit, otherwise two rows scrolling as one block.
    function layoutChips() {
      chipsEl.classList.remove('two');
      if (chipsEl.scrollWidth > strip.clientWidth - 24 + 1) chipsEl.classList.add('two');
    }

    function lightChips() {
      var active = chipKind === 'major' ? activeMajor : activeCat;
      Array.prototype.forEach.call(chipsEl.children, function (b, i) {
        var on = chipVals[i] === active;
        if (on && !b.classList.contains('on')) {
          // Centre the lit chip in the strip.
          strip.scrollTo({ left: b.offsetLeft - (strip.clientWidth - b.offsetWidth) / 2, behavior: 'smooth' });
        }
        b.classList.toggle('on', on);
      });
    }

    function setActiveMajor(m) { activeMajor = m; lightChips(); }
    function setActiveCat(k) { activeCat = k; lightChips(); }

    // ---- folding + jumping ------------------------------------------------------
    function majorEl(m) { return listEl.querySelector('.ml-mj[data-mi="' + majorList.indexOf(m) + '"]'); }
    function secEl(key) {
      var i = secList.findIndex(function (s) { return s.key === key; });
      return i < 0 ? null : listEl.querySelector('.ml-sec[data-si="' + i + '"]');
    }

    function scrollToEl(el) {
      if (!el) return;
      // The spy stays quiet while the list is driven, or the lit chip would
      // flicker through every major the scroll passes on the way.
      jumping = true;
      clearTimeout(jumpTimer);
      jumpTimer = setTimeout(function () { jumping = false; }, 1000);
      scroller.scrollTo({ top: el.offsetTop, behavior: 'smooth' });
    }

    // Capsule tap: take them TO a major — opens a folded one, never folds one.
    function jumpToMajor(m) {
      if (collapsedMajors.delete(m)) render();
      setActiveMajor(m);
      scrollToEl(majorEl(m));
    }

    // Major card tap: fold it shut, or spread it open and bring it to the top.
    function toggleMajor(m) {
      var wasOpen = !collapsedMajors.has(m);
      if (wasOpen) collapsedMajors.add(m); else collapsedMajors.delete(m);
      render();
      setActiveMajor(wasOpen ? null : m);
      if (!wasOpen) scrollToEl(majorEl(m));
    }

    // Sub bar tap. With majors it is an accordion — only one open in the whole
    // list; a flat menu's bars fold independently.
    function toggleSection(key) {
      var flat = isFlat();
      var wasOpen = flat ? !collapsedCats.has(key) : expandedCats.has(key);
      if (flat) {
        if (wasOpen) collapsedCats.add(key); else collapsedCats.delete(key);
      } else {
        expandedCats.clear();
        if (!wasOpen) expandedCats.add(key);
      }
      render();
      if (wasOpen) spy(); else setActiveCat(key);
    }

    // Category chip tap (flat menu only): open it if folded, scroll to its bar.
    function jumpToCategory(key) {
      if (!secEl(key)) return;
      if (collapsedCats.delete(key)) render();
      setActiveCat(key);
      scrollToEl(secEl(key));
    }

    function toggleVariant(id) {
      openVariant = openVariant === id ? null : id;
      render();
    }

    // Scroll-spy: the open section on screen (else the bar at the top) lights
    // the category chip; the major whose block holds the top lights the capsule.
    function spy() {
      if (jumping || !tree.length) return;
      var top = scroller.scrollTop, bottom = top + scroller.clientHeight;
      var spans = Array.prototype.map.call(listEl.querySelectorAll('.ml-sec'), function (el) {
        var s = secList[+el.dataset.si];
        return { key: s.key, start: el.offsetTop, end: el.offsetTop + el.offsetHeight, open: s.expanded };
      });
      var cat = null;
      if (spans.some(function (s) { return s.open; })) {
        var hit = spans.find(function (s) { return s.open && s.start < bottom && s.end > top; });
        if (hit) cat = hit.key;
        else {
          cat = spans[0].key;
          spans.forEach(function (s) { if (s.start <= top + 1) cat = s.key; });
        }
      }
      if (cat !== activeCat) setActiveCat(cat);
      var m = null;
      Array.prototype.forEach.call(listEl.querySelectorAll('.ml-mj'), function (el, i) {
        if (i === 0 || el.offsetTop <= top + 1) m = majorList[+el.dataset.mi];
      });
      if (m !== null && m !== activeMajor) setActiveMajor(m);
    }
    scroller.addEventListener('scroll', spy, { passive: true });
    scroller.addEventListener('scrollend', function () { jumping = false; });

    // ---- cart -------------------------------------------------------------------
    function addLine(item, v) {
      var price = unitPrice(item, v && v.id);
      if (price == null) return;
      var k = keyOf(item.id, v && v.id);
      var line = cart.get(k);
      if (line) { line.qty = Math.min(line.qty + 1, MAX_QTY); return; }
      cart.set(k, { item_id: item.id, variant_id: v ? v.id : null,
        name: item.name + (v ? ' (' + v.label + ')' : ''), price: price, qty: 1 });
    }

    function changeQty(k, d) {
      var line = cart.get(k);
      if (!line) return;
      line.qty = Math.min(line.qty + d, MAX_QTY);
      if (line.qty <= 0) cart.delete(k);
    }

    function lineFor(el) {
      var item = byId.get(el.dataset.id);
      var v = item && el.dataset.vid ? item.variants.find(function (x) { return x.id === el.dataset.vid; }) : null;
      return { item: item, v: v, k: item ? keyOf(item.id, v && v.id) : null };
    }

    function total() {
      var t = 0;
      cart.forEach(function (l) { t += l.price * l.qty; });
      return Math.round(t * 100) / 100;
    }

    function panelHtml(inSheet) {
      var h = (inSheet ? '<div class="ml-grab"></div>' : '') +
        '<div class="ml-cph"><span class="ml-tile">' + ICON.cart + '</span><b>Order</b>' +
        (cart.size ? '<span class="ml-cnt">' + cart.size + '</span>' : '') + '</div><div class="ml-lines">';
      if (!cart.size) {
        h += '<div class="ml-cpe"><span>' + ICON.cart + '</span>No items added yet</div>';
      }
      cart.forEach(function (l, k) {
        h += '<div class="ml-line"><div class="i"><div class="n">' + esc(l.name) + '</div>' +
          '<div class="a" data-amt="' + esc(k) + '">' + money(l.price * l.qty) + '</div></div>' +
          '<div class="ml-qb"><button data-act="cdec" data-k="' + esc(k) + '" aria-label="One less">' + ICON.minus + '</button>' +
          '<input data-act="q" data-k="' + esc(k) + '" inputmode="numeric" value="' + l.qty + '" aria-label="Quantity">' +
          '<button data-act="cinc" data-k="' + esc(k) + '" aria-label="One more">' + ICON.plus + '</button></div></div>';
      });
      h += '</div><div class="ml-cpf"><div class="ml-tot"><span>Total</span><span data-total>' + money(total()) + '</span></div>' +
        '<button class="ml-go" data-act="go"' + (cart.size && !busy ? '' : ' disabled') + '>' +
        esc(busy ? 'Please wait…' : (opts.actionLabel || 'Place Order')) + '</button>' +
        // opts.actionNote: trusted markup from the page itself (the Ordering
        // Terms notice and its link) — never customer or shop data.
        (opts.actionNote ? '<div class="ml-note">' + opts.actionNote + '</div>' : '') + '</div>';
      return '<div class="ml-cp">' + h + '</div>';
    }

    function renderCart() {
      aside.innerHTML = panelHtml(false);
      sheetEl.innerHTML = panelHtml(true);
      fab.hidden = cart.size === 0;
      fab.querySelector('span').textContent = 'Cart (' + cart.size + ')';
      if (!cart.size) sheetBg.classList.remove('show');
    }

    // A quantity typed into a box: only the figures move. Rebuilding would take
    // the caret (and the phone's keyboard) with it, or swallow a tap mid-flight.
    function renderFigures() {
      [aside, sheetEl].forEach(function (p) {
        cart.forEach(function (l, k) {
          var a = p.querySelector('[data-amt="' + cssEsc(k) + '"]');
          if (a) a.textContent = money(l.price * l.qty);
        });
        var t = p.querySelector('[data-total]');
        if (t) t.textContent = money(total());
      });
    }
    function cssEsc(s) { return window.CSS && window.CSS.escape ? window.CSS.escape(s) : s; }

    // ---- events -----------------------------------------------------------------
    function onClick(e) {
      var t = e.target.closest('[data-act]');
      if (!t || t.tagName === 'INPUT' && t.dataset.act !== 'q') return;
      var act = t.dataset.act;
      if (act === 'mj') return toggleMajor(majorList[+t.dataset.mi]);
      if (act === 'sec') return toggleSection(secList[+t.dataset.si].key);
      if (act === 'var') return toggleVariant(t.dataset.id);
      if (act === 'img') {
        var it = byId.get(t.dataset.id);
        return openLightbox(it.image_url, it.name);
      }
      if (act === 'go') {
        if (!cart.size || busy) return;
        sheetBg.classList.remove('show');
        return opts.onAction && opts.onAction();
      }
      if (act === 'cinc' || act === 'cdec') {
        changeQty(t.dataset.k, act === 'cinc' ? 1 : -1);
        return render();
      }
      var ref = lineFor(t);
      if (!ref.item) return;
      if (act === 'add') { addLine(ref.item, ref.v); return render(); }
      if (act === 'dec') { changeQty(ref.k, -1); return render(); }
      if (act === 'q' && !cart.has(ref.k)) {
        // An empty box: add one, then select it so typing replaces the 1.
        if (unitPrice(ref.item, ref.v && ref.v.id) == null) return;
        addLine(ref.item, ref.v);
        render();
        var inp = listEl.querySelector('input[data-k="' + cssEsc(ref.k) + '"]');
        if (inp) { inp.focus(); inp.select(); }
      }
    }

    // Typing commits a valid positive number live; leaving the box resolves
    // the rest — emptied or 0 removes the line.
    function onInput(e) {
      var t = e.target;
      if (t.dataset.act !== 'q' || !cart.has(t.dataset.k)) return;
      var n = parseInt(t.value, 10);
      if (isNaN(n) || n < 1) return;
      if (n > MAX_QTY) { n = MAX_QTY; t.value = String(n); }
      cart.get(t.dataset.k).qty = n;
      renderFigures();
    }
    function onFocusOut(e) {
      var t = e.target, k = t.dataset && t.dataset.k;
      if (!t.dataset || t.dataset.act !== 'q' || !cart.has(k)) return;
      var n = parseInt(t.value, 10);
      if (isNaN(n) || n < 1) {
        cart.delete(k);
        // After this event, so a tap that caused the blur still lands.
        return setTimeout(render, 0);
      }
      cart.get(k).qty = Math.min(n, MAX_QTY);
      // Only the number changed — sync the other copies of this line in place
      // rather than rebuilding the row under a tap that may be in flight.
      document.querySelectorAll('input[data-k="' + cssEsc(k) + '"]').forEach(function (i) {
        i.value = String(cart.get(k).qty);
      });
      renderFigures();
    }
    function onKey(e) {
      if (e.key === 'Enter' && e.target.dataset && e.target.dataset.act === 'q') e.target.blur();
    }
    [listEl, aside, sheetEl].forEach(function (el) {
      el.addEventListener('click', onClick);
      el.addEventListener('input', onInput);
      el.addEventListener('focusout', onFocusOut);
      el.addEventListener('keydown', onKey);
    });

    chipsEl.addEventListener('click', function (e) {
      var b = e.target.closest('[data-ci]');
      if (!b) return;
      var v = chipVals[+b.dataset.ci];
      if (chipKind === 'major') jumpToMajor(v); else jumpToCategory(v);
    });

    searchBtn.onclick = function () {
      var open = !bar.classList.contains('searching');
      bar.classList.toggle('searching', open);
      searchBtn.innerHTML = open ? ICON.close : ICON.search;
      if (open) { searchInput.focus(); return; }
      searchInput.value = '';
      if (query) { query = ''; render(); spy(); }
    };
    searchInput.oninput = function () {
      query = searchInput.value.trim().toLowerCase();
      render();
      spy();
    };

    fab.querySelector('button').onclick = function () { sheetBg.classList.add('show'); };
    sheetBg.addEventListener('click', function (e) { if (e.target === sheetBg) sheetBg.classList.remove('show'); });

    window.addEventListener('resize', function () {
      var two = window.innerWidth >= TWO_COLS;
      if (two !== twoCols) { twoCols = two; render(); }
      layoutChips();
    });

    // ---- toast + photo lightbox (used by the pages too) -------------------------
    var toastTimer = null;
    function toast(msg) {
      toastEl.textContent = msg;
      toastEl.classList.add('show');
      clearTimeout(toastTimer);
      toastTimer = setTimeout(function () { toastEl.classList.remove('show'); }, 2200);
    }
    function openLightbox(src, name) {
      if (!src) return;
      lightbox.querySelector('img').src = src;
      lightbox.querySelector('img').alt = name || '';
      lightbox.querySelector('.cap').textContent = name || '';
      lightbox.classList.add('show');
    }
    function closeLightbox() {
      lightbox.classList.remove('show');
      lightbox.querySelector('img').src = '';
    }
    lightbox.addEventListener('click', function (e) { if (e.target !== lightbox.querySelector('img')) closeLightbox(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeLightbox(); });

    // ---- what the pages use -------------------------------------------------------
    return {
      // Header: shop name + the small chip under it (table number / address).
      setHeader: function (title, chip) {
        q('.ml-name').textContent = title || '';
        q('.ml-chip').textContent = chip || '';
      },
      actions: q('.ml-acts'),   // app-bar slot, e.g. the store's call button
      extra: extraEl,           // above the list: running order, order status
      setItems: function (list) {
        items = (list || []).filter(function (i) { return i && i.id && i.is_active !== false; });
        byId = new Map(items.map(function (i) { return [i.id, i]; }));
        hasImages = items.some(function (i) { return !!i.image_url; });
        root.classList.toggle('pics', hasImages);
        majors = uniqSorted(items.map(function (i) { return trim(i.major_category); }));
        cats = uniqSorted(items.map(function (i) { return trim(i.category); }));
        // Lines whose dish vanished from a reloaded menu cannot be ordered.
        cart.forEach(function (l, k) { if (!byId.has(l.item_id)) cart.delete(k); });
        render();
        spy();
      },
      showError: function (msg) { listEl.innerHTML = '<div class="center">' + esc(msg) + '</div>'; },
      lines: function () { return Array.from(cart.values()); },
      total: total,
      clear: function () { cart.clear(); render(); },
      setBusy: function (b) { busy = !!b; renderCart(); },
      toast: toast,
      openLightbox: openLightbox,
      esc: esc,
    };
  };
})();
