// 単一ページの埋め込み HTML。SSE で events を受信し、状態は /api/state を fetch。
enum DashboardHTML {
    static let page = #"""
<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<title>hoy dashboard</title>
<style>
  :root {
    --bg: #0f1116; --fg: #e6e6ea; --muted: #8a8f9d; --accent: #7aa6ff;
    --good: #61c886; --warn: #f0b658; --bad: #f06a6a;
    --card: #161922; --line: #262a35;
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--fg);
         font: 14px/1.45 ui-monospace, "SF Mono", Menlo, monospace; }
  header { padding: 12px 20px; border-bottom: 1px solid var(--line);
           display: flex; align-items: baseline; gap: 16px; }
  header h1 { margin: 0; font-size: 16px; font-weight: 600; }
  header .meta { color: var(--muted); font-size: 12px; }
  .container { max-width: 1100px; margin: 0 auto; padding: 16px 20px;
               display: grid; grid-template-columns: 1fr 360px; gap: 24px; }
  .left { min-width: 0; }
  section { margin-bottom: 24px; }
  section h2 { font-size: 12px; font-weight: 600; color: var(--muted);
               text-transform: uppercase; letter-spacing: .08em;
               margin: 0 0 10px; }
  .empty { color: var(--muted); font-style: italic; }
  .claim { padding: 6px 10px; background: var(--card);
           border-left: 3px solid var(--accent);
           margin-bottom: 6px; border-radius: 3px; }
  .claim .who { color: var(--accent); }
  .claim .target { color: var(--muted); margin-left: 6px; }
  .claim .ttl { color: var(--muted); float: right; font-size: 12px; }
  .intent { padding: 6px 10px; margin: 4px 0; border-left: 3px solid var(--line);
            background: var(--card); border-radius: 3px;
            transition: background 0.6s; }
  .intent.flash { background: rgba(122, 166, 255, 0.15); }
  .intent.closed { opacity: 0.5; }
  .intent.claimed { border-left-color: var(--accent); }
  .intent .head { display: flex; align-items: center; gap: 8px; }
  .intent .id { color: var(--muted); font-size: 12px; }
  .intent .v { color: var(--muted); font-size: 12px; }
  .intent .title { font-weight: 600; }
  .intent .by { color: var(--accent); margin-left: 8px; font-size: 12px; }
  .intent .x { color: var(--muted); margin-right: 4px; }
  .intent .x.closed { color: var(--bad); }
  .children { margin-left: 20px; }
  .tasks { margin: 6px 0 0 4px; font-size: 13px; color: var(--muted); }
  .tasks .counts { margin-bottom: 4px; }
  .tasks .badge { display: inline-block; padding: 1px 6px; border-radius: 8px;
                  background: var(--line); margin-right: 4px; font-size: 11px; }
  .tasks .badge.open, .tasks .badge.claimed, .tasks .badge.inProgress {
    color: var(--warn); background: rgba(240, 182, 88, 0.1); }
  .tasks .badge.completed { color: var(--good); background: rgba(97, 200, 134, 0.1); }
  .tasks .badge.reverted, .tasks .badge.closed {
    color: var(--muted); background: rgba(138, 143, 157, 0.1); }
  .tasks .item { padding: 2px 0; }
  .tasks .item .tid { color: var(--muted); font-size: 11px; }
  .events { background: var(--card); border-radius: 4px; padding: 8px;
            max-height: 70vh; overflow-y: auto; }
  .event { padding: 6px 4px; border-bottom: 1px solid var(--line);
           font-size: 12px; }
  .event:last-child { border-bottom: none; }
  .event .when { color: var(--muted); margin-right: 6px; }
  .event .name { font-weight: 600; margin-right: 6px; }
  .event .name.task-completed { color: var(--good); }
  .event .name.task-reverted { color: var(--warn); }
  .event .name.conflict-detected { color: var(--bad); }
  .event .name.claim-expired { color: var(--muted); }
  .event .name.verification-invalidated { color: var(--warn); }
  .event .body { color: var(--fg); white-space: pre-wrap; word-break: break-all;
                 font-size: 11px; opacity: 0.7; }
  footer { padding: 12px 20px; border-top: 1px solid var(--line);
           color: var(--muted); font-size: 12px; }
  .bad { color: var(--bad); }
  #status { color: var(--good); }
  #status.disconnected { color: var(--bad); }
  @media (max-width: 800px) {
    .container { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>
<header>
  <h1>hoy dashboard</h1>
  <span class="meta" id="ts">—</span>
  <span class="meta" id="status">connecting…</span>
  <span class="meta" id="event-status">events: —</span>
</header>
<div class="container">
  <div class="left">
    <section>
      <h2>active claims</h2>
      <div id="claims" class="empty">—</div>
    </section>
    <section>
      <h2>intents</h2>
      <div id="intents" class="empty">—</div>
    </section>
  </div>
  <div class="right">
    <section>
      <h2>events <span style="color:var(--muted);font-weight:normal">(live)</span></h2>
      <div id="events" class="events"><div class="empty">no events yet</div></div>
    </section>
  </div>
</div>
<footer>
  <span id="root">—</span>
</footer>
<script>
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
function shortId(s) { return s ? s.slice(0, 8) : '?'; }
function nowHHMMSS() {
  const d = new Date();
  return d.toTimeString().slice(0, 8);
}

// === state rendering ===
function renderClaims(claims) {
  const el = $('claims');
  if (!claims.length) { el.className = 'empty'; el.textContent = 'なし'; return; }
  el.className = '';
  const now = Date.now() / 1000;
  el.innerHTML = claims.map(c => {
    const remain = Math.max(0, Math.round(c.expiresAt - now));
    return `<div class="claim">
      <span class="ttl">残り ${remain}s</span>
      <span class="who">${esc(c.principal.id)}</span>
      <span class="target">→ ${shortId(c.targetIntentId)}</span>
    </div>`;
  }).join('');
}

let flashTaskId = null;
function renderIntent(intent, claimsByIntent) {
  const claimers = claimsByIntent[intent.id] || [];
  const isClosed = intent.status === 'closed';
  const isClaimed = claimers.length > 0;
  const cls = ['intent'];
  if (isClosed) cls.push('closed');
  if (isClaimed) cls.push('claimed');
  if ((intent.tasks || []).some(t => t.id === flashTaskId)) cls.push('flash');
  const taskHTML = renderTasks(intent.tasks || []);
  const childHTML = (intent.children || []).map(c => renderIntent(c, claimsByIntent)).join('');
  return `<div class="${cls.join(' ')}" data-id="${intent.id}">
    <div class="head">
      <span class="x ${isClosed?'closed':''}">${isClosed?'✕':'○'}</span>
      <span class="id">${shortId(intent.id)}</span>
      <span class="v">v${intent.version}</span>
      <span class="title">${esc(intent.title)}</span>
      ${claimers.length ? `<span class="by">claimed by ${esc(claimers.map(c=>c.principal.id).join(', '))}</span>` : ''}
    </div>
    ${taskHTML}
    ${childHTML ? `<div class="children">${childHTML}</div>` : ''}
  </div>`;
}

function renderTasks(tasks) {
  if (!tasks.length) return '';
  const counts = {};
  for (const t of tasks) counts[t.status] = (counts[t.status] || 0) + 1;
  const order = ['open', 'claimed', 'inProgress', 'completed', 'reverted', 'closed'];
  const badges = order.filter(k => counts[k]).map(k =>
    `<span class="badge ${k}">${k}:${counts[k]}</span>`).join(' ');
  const active = tasks.filter(t => ['open','claimed','inProgress'].includes(t.status));
  const items = active.slice(0, 5).map(t =>
    `<div class="item">· <span class="tid">${shortId(t.id)}</span> ${esc(t.title)}</div>`).join('');
  const more = active.length > 5 ? `<div class="item">… +${active.length - 5} more</div>` : '';
  return `<div class="tasks"><div class="counts">${badges}</div>${items}${more}</div>`;
}

async function refreshState() {
  try {
    const r = await fetch('/api/state');
    if (!r.ok) throw new Error('http ' + r.status);
    const state = await r.json();
    $('status').textContent = '● connected';
    $('status').classList.remove('disconnected');
    $('ts').textContent = new Date().toISOString();
    $('root').textContent = state.root || '';
    const claims = state.claims || [];
    const claimsByIntent = {};
    for (const c of claims) {
      (claimsByIntent[c.targetIntentId] = claimsByIntent[c.targetIntentId] || []).push(c);
    }
    renderClaims(claims);
    const intents = state.intents || [];
    const intentsEl = $('intents');
    if (!intents.length) {
      intentsEl.className = 'empty';
      intentsEl.textContent = 'なし';
    } else {
      intentsEl.className = '';
      intentsEl.innerHTML = intents.map(i => renderIntent(i, claimsByIntent)).join('');
    }
  } catch (e) {
    $('status').textContent = '⚠ daemon に接続できません';
    $('status').classList.add('disconnected');
  }
}

// === event log via SSE ===
const MAX_EVENTS = 50;
const eventLog = [];
function renderEvents() {
  const el = $('events');
  if (eventLog.length === 0) {
    el.innerHTML = '<div class="empty">no events yet</div>';
    return;
  }
  el.innerHTML = eventLog.map(e => {
    const cls = e.method.replace(/\./g, '-');
    let body = '';
    if (e.params) {
      const keys = Object.keys(e.params).filter(k => k !== 'principal');
      body = keys.map(k => {
        let v = e.params[k];
        if (typeof v === 'string' && v.length > 60) v = v.slice(0, 57) + '…';
        return `${k}=${typeof v === 'string' ? v : JSON.stringify(v)}`;
      }).join(' ');
    }
    return `<div class="event">
      <span class="when">${e.when}</span>
      <span class="name ${cls}">${esc(e.method)}</span>
      <div class="body">${esc(body)}</div>
    </div>`;
  }).join('');
}

function connectEvents() {
  const es = new EventSource('/api/events');
  es.onopen = () => { $('event-status').textContent = 'events: ● live'; };
  es.onerror = () => {
    $('event-status').textContent = 'events: ⚠ retry…';
    es.close();
    setTimeout(connectEvents, 2000);
  };
  es.onmessage = (msg) => {
    try {
      const obj = JSON.parse(msg.data);
      if (!obj.method) return;
      eventLog.unshift({ when: nowHHMMSS(), method: obj.method, params: obj.params });
      while (eventLog.length > MAX_EVENTS) eventLog.pop();
      renderEvents();
      // ハイライトと再フェッチ
      flashTaskId = obj.params && obj.params.taskId;
      refreshState().then(() => {
        setTimeout(() => { flashTaskId = null; refreshState(); }, 800);
      });
    } catch {}
  };
}

refreshState();
connectEvents();
// 念のため 10s ごとに状態同期 (claim TTL の表示更新等)
setInterval(refreshState, 10000);
</script>
</body>
</html>
"""#
}
