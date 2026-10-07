// archi.js — vue interactive de l'architecture (report.py, section « Architecture »).
// Données : <script id="archi-data"> = { archi (archi.json), decisions (§9), planned_files, real, warnings, stage }.
// Tout se re-rend depuis l'état S à chaque interaction ; les arêtes de la carte sont tracées après layout.
(function () {
  const dataEl = document.getElementById('archi-data');
  const app = document.getElementById('archi-app');
  if (!dataEl || !app) return;
  const D = JSON.parse(dataEl.textContent);
  const A = D.archi || {};
  const DEC = A.decisions || {};
  const LAYERS = [['presentation', 'Presentation'], ['domain', 'Domain'], ['data', 'Data'],
                  ['injection', 'Injection'], ['external', 'Autres packages']];
  const STATUS = { new: 'nouveau', modified: 'modifié', reused: 'réutilisé', unplanned: 'hors plan' };
  const late = /contracts|tests|mutants|qa|evidence/.test(D.stage || '');
  const S = { sel: null, alt: {}, std: false, view: D.real && late ? 'code' : 'plan',
              tree: D.real && late ? 'gaps' : 'plan', flow: 0, closed: new Set() };

  const esc = s => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const altOf = id => (DEC[id] || {}).alternative || null;
  const decKind = st => /valid/i.test(st) ? 'ok' : /modif/i.test(st) ? 'human' : 'warn';
  const dBadges = ids => (ids || []).filter(Boolean).map(d => `<span class="ax-dbadge" data-dec="${esc(d)}">${esc(d)}</span>`).join('');

  // --- modèle : plan + alternatives activées + superposition du code ------------------------------
  function model() {
    const nodes = (A.nodes || []).map(n => ({ ...n }));
    const edges = (A.edges || []).map(e => ({ ...e }));
    for (const id of Object.keys(S.alt)) {
      const alt = S.alt[id] && altOf(id);
      if (!alt) continue;
      const gone = new Set(alt.remove || []);
      nodes.forEach(n => { if (gone.has(n.id)) n.altGone = id; });
      (alt.add || []).forEach(n => nodes.push({ ...n, altAdd: id, decisions: [...(n.decisions || []), id] }));
      edges.forEach(e => {
        if (gone.has(e.from) || gone.has(e.to) ||
            (alt.remove_edges || []).some(r => r.from === e.from && r.to === e.to)) e.gone = true;
      });
      (alt.add_edges || []).forEach(e => edges.push({ ...e, alt: true }));
    }
    if (S.view === 'code' && D.real) {
      const present = new Set(D.real.present || []);
      const files = new Set((D.real.files || []).map(f => f.path));
      nodes.forEach(n => {
        if (n.altAdd || !(n.status === 'new' || n.status === 'modified')) return;
        if (!(n.layer === 'external' ? files.has(n.file) : present.has(n.id))) n.missing = true;
      });
      (D.real.unplanned || []).forEach(u => nodes.push({ ...u, status: 'unplanned' }));
      (D.real.edges || []).forEach(e => edges.push({ ...e, real: true }));
    }
    return { nodes, edges };
  }

  function plannedFiles() {
    const out = (D.planned_files || []).map(f => ({ ...f }));
    for (const id of Object.keys(S.alt)) {
      const alt = S.alt[id] && altOf(id);
      if (!alt) continue;
      const gone = new Set(alt.remove || []);
      out.forEach(f => { if (f.node && gone.has(f.node)) f.gap = 'gone'; });
      (alt.add || []).forEach(n => n.file && out.push({ path: n.file, status: n.status || 'new', node: n.id, decisions: [id], gap: 'alt' }));
      (alt.files_add || []).forEach(f => out.push({ ...f, decisions: [id], gap: 'alt' }));
    }
    return out;
  }

  function highlights(m) {
    if (!S.sel) return null;
    const n = new Set(), f = new Set(), st = new Set();
    const flows = A.flows || [];
    if (S.sel.kind === 'd') {
      const id = S.sel.id;
      m.nodes.forEach(x => { if ((x.decisions || []).includes(id)) n.add(x.id); });
      const alt = altOf(id);
      if (alt) {
        (alt.remove || []).forEach(x => n.add(x));
        (alt.add || []).forEach(x => n.add(x.id));
        (alt.remove_edges || []).concat(alt.add_edges || []).forEach(e => { n.add(e.from); n.add(e.to); });
      }
      plannedFiles().forEach(x => { if ((x.decisions || []).includes(id)) f.add(x.path); });
      flows.forEach((fl, i) => (fl.steps || []).forEach((s, j) => { if (s.decision === id) st.add(i + ':' + j); }));
    } else {
      n.add(S.sel.id);
    }
    m.nodes.forEach(x => { if (n.has(x.id) && x.file) f.add(x.file); });
    if (!st.size) flows.forEach((fl, i) => (fl.steps || []).forEach((s, j) => {
      if (n.has(s.from) || n.has(s.to)) st.add(i + ':' + j);
    }));
    return { n, f, st };
  }

  // --- sections ----------------------------------------------------------------------------------
  function summaryHtml() {
    const nodes = A.nodes || [];
    const cnt = s => nodes.filter(n => n.status === s).length;
    const pf = D.planned_files || [];
    const chips = [
      [cnt('new'), 'classe(s) nouvelle(s)', 'new'], [cnt('modified'), 'modifiée(s)', 'modified'],
      [cnt('reused'), 'réutilisée(s)', ''], [pf.filter(f => f.status === 'new').length, 'fichier(s) ajouté(s)', 'new'],
      [pf.filter(f => f.status === 'modified').length, 'fichier(s) modifié(s)', 'modified'],
      [(D.decisions || []).length, 'décision(s)', 'human'],
    ].filter(c => c[0]).map(c => `<span class="badge ${c[2] === 'new' ? '' : c[2] === 'modified' ? 'warn' : c[2]}">${c[0]} ${c[1]}</span>`);
    const sum = (A.summary || []).map(l => `<li>${esc(l)}</li>`).join('');
    const warn = (D.warnings || []).length
      ? `<div class="ax-warn"><b>${D.warnings.length} incohérence(s) entre archi.json et la spec</b><ul>${D.warnings.map(w => `<li>${esc(w)}</li>`).join('')}</ul></div>` : '';
    return `<h3>En bref</h3>${sum ? `<ul class="ax-summary">${sum}</ul>` : '<p class="muted">pas de résumé</p>'}
      <div class="ax-counts">${chips.join('')}</div>${warn}`;
  }

  function selBarHtml() {
    if (!S.sel) return '';
    const label = S.sel.kind === 'd'
      ? `Décision ${esc(S.sel.id)} : ${esc(((D.decisions || []).find(d => d.id === S.sel.id) || {}).subject || '')}`
      : `Classe ${esc(S.sel.id)}`;
    return `<div class="ax-sel-bar">Surligné : <b>${label}</b> (carte, parcours, fichiers)<button class="ax-btn" data-act="clear">Effacer</button></div>`;
  }

  function decisionsHtml(m) {
    const ds = D.decisions || [];
    if (!ds.length) return '<h3>Décisions</h3><p class="muted">aucune décision en §9</p>';
    const cards = ds.map(d => {
      const k = decKind(d.status);
      const alt = altOf(d.id);
      const on = !!S.alt[d.id];
      const anchors = m.nodes.filter(n => (n.decisions || []).includes(d.id)).length;
      return `<div class="ax-dec ${k}${S.sel && S.sel.kind === 'd' && S.sel.id === d.id ? ' sel' : ''}" data-dec="${esc(d.id)}">
        <div class="dh"><b>${esc(d.id)}</b><span class="dt">${esc(d.subject)}</span><span class="badge ${k}">${esc(d.status)}</span></div>
        <div class="row"><span class="lbl">Proposé</span>${esc(d.proposed)}</div>
        <div class="row${on ? ' alt-on' : ''}"><span class="lbl">Alternative</span>${esc(d.alternative)}</div>
        <div class="row"><span class="lbl">Raison</span>${esc(d.reason)}</div>
        ${alt && alt.impact ? `<div class="impact">Si l'alternative : ${esc(alt.impact)}</div>` : ''}
        <div class="row" style="display:flex;gap:6px;align-items:center;margin-top:6px">
          ${alt ? `<button class="ax-btn${on ? ' on' : ''}" data-alt="${esc(d.id)}">${on ? 'Alternative affichée' : 'Voir l\'alternative'}</button>` : ''}
          <span class="hint">${anchors} nœud(s)</span></div></div>`;
    }).join('');
    return `<h3>Décisions à trancher</h3><p class="ax-hint">Clique une décision pour la situer dans la carte, les parcours et les fichiers. « Voir l'alternative » redessine la carte et l'arborescence comme si tu la choisissais.</p><div class="ax-decisions">${cards}</div>`;
  }

  function contract(m, visible) {
    // Arêtes à travers les nœuds masqués : A → (masqués…) → B devient A ⇢ B.
    // Un implements se parcourt de l'interface vers l'implémentation (sens d'exécution).
    const adj = {};
    const add = (a, b) => (adj[a] = adj[a] || []).push(b);
    m.edges.forEach(e => { if (e.gone) return; e.kind === 'implements' ? add(e.to, e.from) : add(e.from, e.to); });
    const out = [];
    const seen = new Set();
    m.edges.forEach(e => { if (visible.has(e.from) && visible.has(e.to)) out.push(e); });
    visible.forEach(src => {
      const stack = (adj[src] || []).filter(x => !visible.has(x));
      const vis = new Set(stack);
      while (stack.length) {
        const cur = stack.pop();
        (adj[cur] || []).forEach(nx => {
          if (visible.has(nx)) {
            const key = src + '>' + nx;
            if (nx !== src && !seen.has(key) && !out.some(e => e.from === src && e.to === nx)) { seen.add(key); out.push({ from: src, to: nx, via: true }); }
          } else if (!vis.has(nx)) { vis.add(nx); stack.push(nx); }
        });
      }
    });
    return out;
  }

  function mapHtml(m, hl) {
    const hasStd = m.nodes.some(n => n.standard);
    const shown = n => S.std || !n.standard || n.missing || n.altGone || (hl && hl.n.has(n.id));
    const visible = new Set(m.nodes.filter(shown).map(n => n.id));
    const cols = LAYERS.map(([key, title]) => {
      const all = m.nodes.filter(n => (LAYERS.some(l => l[0] === n.layer) ? n.layer : 'external') === key);
      const vis = all.filter(n => visible.has(n.id));
      const hidden = all.length - vis.length;
      if (!all.length) return '';
      let body = '';
      let pkg = null;
      vis.forEach(n => {
        if (key === 'external' && n.package !== pkg) { pkg = n.package; body += `<div class="ax-pkg">${esc(pkg || '?')}</div>`; }
        const cls = ['ax-node', n.status || 'new', n.missing && 'missing', n.altAdd && 'alt-add', n.altGone && 'alt-gone',
                     hl && hl.n.has(n.id) && 'hl'].filter(Boolean).join(' ');
        const st = n.missing ? 'absent du code' : n.altAdd ? `alternative ${n.altAdd}` : n.altGone ? `retiré si ${n.altGone}` : (STATUS[n.status] || n.status);
        body += `<div class="${cls}" data-node="${esc(n.id)}"><div class="st">${esc(st)}</div>
          <div class="nm">${n.kind === 'interface' ? '<span class="kd">«interface» </span>' : ''}${esc(n.id)}${dBadges(n.decisions)}</div>
          ${n.note ? `<div class="nt">${esc(n.note)}</div>` : ''}</div>`;
      });
      if (hidden) body += `<div class="ax-std" data-act="std">+${hidden} classe(s) standard${A.standard_as ? ` (comme ${esc(A.standard_as)})` : ''}</div>`;
      return `<div class="ax-col"><div class="ax-col-title">${title}</div>${body}</div>`;
    }).join('');
    const tools = [
      D.real ? `<span class="ax-seg"><button class="ax-btn${S.view === 'plan' ? ' on' : ''}" data-view="plan">Plan</button><button class="ax-btn${S.view === 'code' ? ' on' : ''}" data-view="code">Plan vs code</button></span>` : '',
      hasStd ? `<button class="ax-btn${S.std ? ' on' : ''}" data-act="std">Squelette standard</button>` : '',
    ].join('');
    const legend = `<div class="ax-legend"><span><i style="border-color:var(--accent)"></i>nouveau</span>
      <span><i style="border-color:var(--warn)"></i>modifié</span><span><i style="border-color:var(--muted);border-style:dashed"></i>réutilisé</span>
      ${S.view === 'code' ? '<span><i style="border-color:var(--ko);background:var(--ko-bg)"></i>hors plan</span><span><i style="border-color:var(--ko);border-style:dashed"></i>absent du code</span>' : ''}
      ${Object.values(S.alt).some(Boolean) ? '<span><i style="border-color:var(--ok);background:var(--ok-bg);border-style:dashed"></i>ajouté par l\'alternative</span>' : ''}
      <span>— appel · - - implements · ⋯ via le squelette masqué</span></div>`;
    MAP_EDGES = contract(m, visible);
    MAP_HL = hl;
    return `<h3>Ce qui change<span class="tools">${tools}</span></h3>
      <p class="ax-hint">Une colonne par couche. ${hasStd && !S.std ? 'Le squelette standard (page, repository, DI…) est masqué : seules les classes propres à cette feature apparaissent. ' : ''}Clique une classe pour la suivre dans les parcours et les fichiers.</p>
      <div class="ax-map-wrap${hl ? ' ax-dim' : ''}"><div class="ax-map">${cols}</div></div>${legend}`;
  }

  let MAP_EDGES = [];
  let MAP_HL = null;

  function drawEdges() {
    const map = app.querySelector('.ax-map');
    if (!map) return;
    const old = map.querySelector('svg.ax-edges');
    if (old) old.remove();
    const base = map.getBoundingClientRect();
    if (!base.width) return;
    const rect = id => {
      const el = map.querySelector(`[data-node="${CSS.escape(id)}"]`);
      if (!el) return null;
      const r = el.getBoundingClientRect();
      return { l: r.left - base.left, r: r.right - base.left, t: r.top - base.top, b: r.bottom - base.top,
               cx: (r.left + r.right) / 2 - base.left, cy: (r.top + r.bottom) / 2 - base.top };
    };
    const NS = 'http://www.w3.org/2000/svg';
    const svg = document.createElementNS(NS, 'svg');
    svg.setAttribute('class', 'ax-edges');
    svg.setAttribute('width', map.scrollWidth);
    svg.setAttribute('height', map.scrollHeight);
    const markers = [['n', 'var(--muted)'], ['hl', 'var(--human)'], ['alt', 'var(--ok)'], ['ko', 'var(--ko)']];
    svg.innerHTML = '<defs>' + markers.map(([k, c]) =>
      `<marker id="ax-arr-${k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" style="fill:${c};stroke:none"/></marker>`).join('') + '</defs>';
    MAP_EDGES.forEach(e => {
      const s = rect(e.from), t = rect(e.to);
      if (!s || !t) return;
      let p0, p3, c1, c2;
      if (t.l >= s.r - 4) { p0 = [s.r, s.cy]; p3 = [t.l, t.cy]; }
      else if (t.r <= s.l + 4) { p0 = [s.l, s.cy]; p3 = [t.r, t.cy]; }
      else { p0 = [s.r, s.cy]; p3 = [t.r, t.cy]; }
      if (Math.abs(p0[0] - p3[0]) < 8) { c1 = [p0[0] + 40, p0[1]]; c2 = [p3[0] + 40, p3[1]]; }
      else { const dx = (p3[0] - p0[0]) / 2; c1 = [p0[0] + dx, p0[1]]; c2 = [p3[0] - dx, p3[1]]; }
      const isHl = MAP_HL && MAP_HL.n.has(e.from) && MAP_HL.n.has(e.to);
      const cls = [e.kind === 'implements' && 'impl', e.via && 'impl', e.alt && 'alt', e.gone && 'gone', e.real && 'real', isHl && 'hl'].filter(Boolean).join(' ');
      const mk = isHl ? 'hl' : e.alt ? 'alt' : (e.gone || e.real) ? 'ko' : 'n';
      const path = document.createElementNS(NS, 'path');
      path.setAttribute('d', `M${p0} C${c1} ${c2} ${p3}`);
      path.setAttribute('class', cls);
      path.setAttribute('marker-end', `url(#ax-arr-${mk})`);
      if (e.via) path.setAttribute('stroke-dasharray', '1 4');
      svg.appendChild(path);
      const label = e.label || (e.kind === 'implements' ? 'implements' : '');
      if (label) {
        const x = (p0[0] + 3 * c1[0] + 3 * c2[0] + p3[0]) / 8, y = (p0[1] + 3 * c1[1] + 3 * c2[1] + p3[1]) / 8;
        const tx = document.createElementNS(NS, 'text');
        tx.setAttribute('x', x); tx.setAttribute('y', y - 3); tx.setAttribute('text-anchor', 'middle');
        tx.textContent = label;
        svg.appendChild(tx);
      }
    });
    map.prepend(svg);
  }

  function flowsHtml(m, hl) {
    const flows = A.flows || [];
    if (!flows.length) return '<h3>Parcours</h3><p class="muted">aucun parcours dans archi.json</p>';
    const fi = Math.min(S.flow, flows.length - 1);
    const fl = flows[fi];
    const byId = Object.fromEntries(m.nodes.map(n => [n.id, n]));
    const parts = [];
    (fl.steps || []).forEach(s => [s.from, s.to].forEach(p => { if (!parts.includes(p)) parts.push(p); }));
    parts.sort((a, b) => (a === 'user' ? -1 : b === 'user' ? 1 : 0));
    const n = parts.length;
    const pct = x => (x / n * 100).toFixed(3) + '%';
    const tabs = flows.map((f, i) => {
      const touched = hl && (f.steps || []).some((_, j) => hl.st.has(i + ':' + j));
      return `<button class="ax-btn${i === fi ? ' on' : ''}" data-flow="${i}">${esc(f.title)}${touched ? ' ●' : ''}</button>`;
    }).join('');
    const lifes = parts.map((_, i) => `<div class="ax-life" style="left:${pct(i + 0.5)}"></div>`).join('');
    const head = parts.map(p => {
      const nd = byId[p];
      const cls = ['ax-part', p === 'user' ? 'user' : (nd && nd.status) || '', hl && hl.n.has(p) && 'hl'].filter(Boolean).join(' ');
      return `<div class="${cls}"><span ${p === 'user' ? '' : `data-node="${esc(p)}"`}>${p === 'user' ? 'Utilisateur' : esc(p)}</span></div>`;
    }).join('');
    const rows = (fl.steps || []).map((s, j) => {
      const a = parts.indexOf(s.from), b = parts.indexOf(s.to);
      const isHl = hl && hl.st.has(fi + ':' + j);
      const lo = Math.min(a, b), hi = Math.max(a, b);
      const cls = ['ax-msg', s.return && 'ret', a === b ? 'self' : b > a ? 'r' : 'l', isHl && 'hl'].filter(Boolean).join(' ');
      const lbl = `<span class="n">${j + 1}</span>${esc(s.msg)}${dBadges([s.decision])}`;
      const data = s.decision ? `data-dec="${esc(s.decision)}"` : s.to !== 'user' ? `data-node="${esc(s.to)}"` : '';
      if (a === b) return `<div class="${cls}" style="grid-column:1/-1" ${data}><div class="tx" style="left:calc(${pct(a + 0.5)} + 6px)">↻ ${lbl}</div></div>`;
      return `<div class="${cls}" style="grid-column:1/-1" ${data}>
        <div class="ln" style="left:${pct(lo + 0.5)};width:${pct(hi - lo)}"></div>
        <div class="tx" style="left:${pct((lo + hi + 1) / 2)}">${lbl}</div></div>`;
    }).join('');
    return `<h3>Parcours</h3><p class="ax-hint">Ce qui se passe quand l'utilisateur agit, de l'écran à la donnée.${fl.scenario ? ` Scénario §4 : <i>${esc(fl.scenario)}</i>.` : ''}</p>
      <div class="ax-tabs">${tabs}</div>
      <div class="ax-seq-wrap"><div class="ax-seq" style="grid-template-columns:repeat(${n},minmax(130px,1fr));min-width:${n * 130}px">${lifes}${head}${rows}</div></div>`;
  }

  function treeFiles() {
    const planned = plannedFiles();
    const real = (D.real && D.real.files) || [];
    if (S.tree === 'real' && D.real) return real.map(f => ({ ...f }));
    if (S.tree === 'gaps' && D.real) {
      const rp = new Map(real.map(f => [f.path, f]));
      const out = planned.map(f => rp.has(f.path) ? { ...f, status: rp.get(f.path).status, tag: ['ok', 'conforme'] }
                                                  : { ...f, gap: f.gap || 'missing', tag: ['ko', 'prévu, absent'] });
      real.forEach(f => { if (!planned.some(p => p.path === f.path)) out.push({ ...f, gap: 'unplanned', tag: ['ko', 'non prévu'] }); });
      return out;
    }
    return planned;
  }

  function treeHtml(m, hl) {
    const files = treeFiles();
    const root = { dirs: {}, files: [] };
    files.forEach(f => {
      const parts = String(f.path).split('/');
      let cur = root;
      parts.slice(0, -1).forEach(p => { cur = cur.dirs[p] = cur.dirs[p] || { dirs: {}, files: [] }; });
      cur.files.push({ ...f, name: parts[parts.length - 1] });
    });
    const count = d => d.files.length + Object.values(d.dirs).reduce((a, x) => a + count(x), 0);
    const nodeOfFile = Object.fromEntries(m.nodes.filter(n => n.file).map(n => [n.file, n.id]));
    const render = (d, prefix) => {
      let html = '';
      Object.keys(d.dirs).sort().forEach(name => {
        let sub = d.dirs[name], label = name;
        while (!sub.files.length && Object.keys(sub.dirs).length === 1) {
          const k = Object.keys(sub.dirs)[0]; label += '/' + k; sub = sub.dirs[k];
        }
        const path = prefix + label;
        html += `<li class="${S.closed.has(path) ? 'closed' : ''}"><span class="dir" data-dir="${esc(path)}">${esc(label)}/ <span class="cnt">(${count(sub)})</span></span><ul>${render(sub, path + '/')}</ul></li>`;
      });
      d.files.sort((a, b) => a.name.localeCompare(b.name)).forEach(f => {
        const mk = { new: '+', modified: '~', deleted: '−' }[f.status] || '·';
        const node = f.node || nodeOfFile[f.path];
        const cls = ['file', f.status, f.gap && 'gap-' + f.gap, hl && hl.f.has(f.path) && 'hl'].filter(Boolean).join(' ');
        const data = node ? `data-node="${esc(node)}"` : (f.decisions || []).length ? `data-dec="${esc(f.decisions[0])}"` : '';
        html += `<li><span class="${cls}" ${data}><span class="mk">${mk}</span><span class="nm">${esc(f.name)}</span>${dBadges(f.decisions)}${f.tag ? `<span class="tag badge ${f.tag[0]}">${esc(f.tag[1])}</span>` : ''}${f.gap === 'alt' ? '<span class="tag badge ok">alternative</span>' : ''}${f.why ? `<span class="why">${esc(f.why)}</span>` : ''}</span></li>`;
      });
      return html;
    };
    const tools = D.real ? `<span class="ax-seg">${[['plan', 'Prévu'], ['real', 'Réel (git)'], ['gaps', 'Écarts']].map(([k, l]) =>
      `<button class="ax-btn${S.tree === k ? ' on' : ''}" data-tree="${k}">${l}</button>`).join('')}</span>` : '';
    const nNew = files.filter(f => f.status === 'new').length, nMod = files.filter(f => f.status === 'modified').length;
    return `<h3>Fichiers<span class="tools">${tools}</span></h3>
      <p class="ax-hint"><b style="color:var(--accent)">+</b> ajouté (${nNew}) · <b style="color:var(--warn)">~</b> modifié (${nMod}).
      ${S.tree === 'real' ? 'Tiré de git depuis la base de la branche, hors .claude/.' : S.tree === 'gaps' ? 'Prévu (archi.json) comparé à git.' : 'Prévu par archi.json.'} Clique un dossier pour le replier, un fichier pour surligner sa classe.</p>
      <div class="ax-tree">${files.length ? `<ul>${render(root, '')}</ul>` : '<p class="muted">aucun fichier</p>'}</div>`;
  }

  // --- rendu et interactions ---------------------------------------------------------------------
  function render() {
    const m = model();
    const hl = highlights(m);
    app.innerHTML = summaryHtml() + selBarHtml() + decisionsHtml(m) + mapHtml(m, hl) + flowsHtml(m, hl) + treeHtml(m, hl);
    requestAnimationFrame(drawEdges);
  }

  app.addEventListener('click', ev => {
    const t = ev.target.closest('[data-alt],[data-view],[data-tree],[data-flow],[data-act],[data-dir],[data-dec],[data-node]');
    if (!t || !app.contains(t)) return;
    const d = t.dataset;
    if (d.alt) S.alt[d.alt] = !S.alt[d.alt];
    else if (d.view) S.view = d.view;
    else if (d.tree) S.tree = d.tree;
    else if (d.flow) S.flow = +d.flow;
    else if (d.act === 'std') S.std = !S.std;
    else if (d.act === 'clear') S.sel = null;
    else if (d.dir) { S.closed.has(d.dir) ? S.closed.delete(d.dir) : S.closed.add(d.dir); }
    else if (d.dec) S.sel = S.sel && S.sel.kind === 'd' && S.sel.id === d.dec ? null : { kind: 'd', id: d.dec };
    else if (d.node) S.sel = S.sel && S.sel.kind === 'n' && S.sel.id === d.node ? null : { kind: 'n', id: d.node };
    render();
  });
  window.addEventListener('resize', () => requestAnimationFrame(drawEdges));
  document.querySelectorAll('details').forEach(x => x.addEventListener('toggle', () => requestAnimationFrame(drawEdges)));
  render();
})();
