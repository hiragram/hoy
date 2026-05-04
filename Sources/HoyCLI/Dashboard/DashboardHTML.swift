// 単一ページの埋め込み HTML。fetch + 2秒ポーリングでシンプルに描画する。
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
  .container { max-width: 1100px; margin: 0 auto; padding: 16px 20px; }
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
            background: var(--card); border-radius: 3px; }
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
  footer { padding: 12px 20px; border-top: 1px solid var(--line);
           color: var(--muted); font-size: 12px; }
  .bad { color: var(--bad); }
  #status { color: var(--good); }
  #status.disconnected { color: var(--bad); }
</style>
</head>
<body>
<header>
  <h1>hoy dashboard</h1>
  <span class="meta" id="ts">—</span>
  <span class="meta" id="status">connecting…</span>
</header>
<div class="container">
  <section>
    <h2>active claims</h2>
    <div id="claims" class="empty">—</div>
  </section>
  <section>
    <h2>intents</h2>
    <div id="intents" class="empty">—</div>
  </section>
</div>
<footer>
  <span id="root">—</span> · refresh every 2s
</footer>
<script>
const $ = id => document.getElementById(id);
const esc = s => String(s).replace(/[&<>"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));

function shortId(s) { return s.slice(0, 8); }

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

function renderIntent(intent, claimsByIntent, depth) {
  const claimers = claimsByIntent[intent.id] || [];
  const isClosed = intent.status === 'closed';
  const isClaimed = claimers.length > 0;
  const cls = ['intent'];
  if (isClosed) cls.push('closed');
  if (isClaimed) cls.push('claimed');
  const taskHTML = renderTasks(intent.tasks || []);
  const childHTML = (intent.children || []).map(c => renderIntent(c, claimsByIntent, depth + 1)).join('');
  return `<div class="${cls.join(' ')}">
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

let connected = false;
async function refresh() {
  try {
    const r = await fetch('/api/state');
    if (!r.ok) throw new Error('http ' + r.status);
    const state = await r.json();
    connected = true;
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
      intentsEl.innerHTML = intents.map(i => renderIntent(i, claimsByIntent, 0)).join('');
    }
  } catch (e) {
    connected = false;
    $('status').textContent = '⚠ daemon に接続できません';
    $('status').classList.add('disconnected');
  }
}
refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
"""#
}
