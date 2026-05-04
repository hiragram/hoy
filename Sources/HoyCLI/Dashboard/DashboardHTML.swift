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
           display: flex; align-items: baseline; gap: 16px; flex-wrap: wrap; }
  header h1 { margin: 0; font-size: 16px; font-weight: 600; }
  header .meta { color: var(--muted); font-size: 12px; }
  header .stat { color: var(--fg); font-size: 12px; }
  header .stat .num { color: var(--accent); font-weight: 600; }
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
  .events, .audit { background: var(--card); border-radius: 4px; padding: 8px;
            max-height: 35vh; overflow-y: auto; }
  .event, .audit-entry { padding: 6px 4px; border-bottom: 1px solid var(--line);
           font-size: 12px; }
  .event:last-child, .audit-entry:last-child { border-bottom: none; }
  .event .when, .audit-entry .when { color: var(--muted); margin-right: 6px; }
  .event .name, .audit-entry .op { font-weight: 600; margin-right: 6px; }
  .event .name.task-completed, .audit-entry .op.task-complete { color: var(--good); }
  .event .name.task-reverted, .audit-entry .op.task-revert { color: var(--warn); }
  .event .name.conflict-detected { color: var(--bad); }
  .event .name.claim-expired { color: var(--muted); }
  .event .name.verification-invalidated { color: var(--warn); }
  .audit-entry .op.intent-create, .audit-entry .op.intent-update { color: var(--accent); }
  .audit-entry .op.intent-close { color: var(--muted); }
  .audit-entry .op.task-create { color: var(--accent); }
  .audit-entry .op.task-close { color: var(--muted); }
  .audit-entry .op.session-create, .audit-entry .op.session-delete { color: var(--muted); }
  .audit-entry .actor { color: var(--accent); margin-right: 4px; font-size: 11px; }
  .event .body, .audit-entry .body { color: var(--fg); white-space: pre-wrap;
                 word-break: break-all; font-size: 11px; opacity: 0.7; }
  .verif-summary { display: inline-block; margin-left: 6px; }
  .verif-dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%;
               margin-right: 2px; vertical-align: middle; }
  .verif-dot.passed { background: var(--good); }
  .verif-dot.failed { background: var(--bad); }
  .verif-dot.waived { background: var(--muted); }
  .verif-dot.pending, .verif-dot.running { background: var(--warn); }
  .clickable { cursor: pointer; }
  .clickable:hover { outline: 1px solid var(--accent); }
  .modal-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.6);
                   display: none; align-items: flex-start; justify-content: center;
                   padding-top: 60px; z-index: 100; }
  .modal-overlay.open { display: flex; }
  .modal { background: var(--card); border: 1px solid var(--line); border-radius: 6px;
           max-width: 720px; width: 92%; max-height: 80vh; overflow-y: auto;
           padding: 20px; box-shadow: 0 10px 40px rgba(0,0,0,0.5); }
  .modal h3 { margin: 0 0 12px; font-size: 14px; font-weight: 700; }
  .modal .kind { color: var(--accent); font-size: 11px; text-transform: uppercase;
                 letter-spacing: 0.08em; margin-bottom: 4px; }
  .modal .row { margin: 6px 0; font-size: 13px; }
  .modal .row .k { color: var(--muted); display: inline-block; min-width: 90px; }
  .modal .body-text { background: var(--bg); border: 1px solid var(--line);
                      padding: 8px; border-radius: 3px; white-space: pre-wrap;
                      font-size: 12px; margin-top: 4px; }
  .modal .verif { padding: 8px; background: var(--bg); border-left: 3px solid var(--line);
                  border-radius: 3px; margin: 6px 0; font-size: 12px; }
  .modal .verif.passed { border-left-color: var(--good); }
  .modal .verif.failed { border-left-color: var(--bad); }
  .modal .verif.waived { border-left-color: var(--muted); }
  .modal .verif.pending, .modal .verif.running { border-left-color: var(--warn); }
  .modal .verif .vhead { font-weight: 600; margin-bottom: 4px; }
  .modal .task-row { padding: 6px 8px; background: var(--bg); border-radius: 3px;
                     margin: 4px 0; font-size: 12px; }
  .modal .close-btn { float: right; cursor: pointer; color: var(--muted);
                      font-size: 16px; padding: 0 4px; }
  .modal .close-btn:hover { color: var(--fg); }
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
  <span class="stat"><span class="num" id="stat-intents">0</span> intents</span>
  <span class="stat"><span class="num" id="stat-tasks-open">0</span> open</span>
  <span class="stat"><span class="num" id="stat-claims">0</span> claims</span>
  <span class="stat"><span class="num" id="stat-worktrees">0</span> worktrees</span>
  <span class="meta" id="ts" style="margin-left:auto">—</span>
  <span class="meta" id="status">connecting…</span>
  <span class="meta" id="event-status">events: —</span>
</header>

<style id="extra"></style>
<script>
// no-op placeholder
</script>
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
    <section>
      <h2>worktrees</h2>
      <div id="worktrees" class="audit"><div class="empty">—</div></div>
    </section>
    <section>
      <h2>recent activity <span style="color:var(--muted);font-weight:normal">(audit)</span></h2>
      <div id="audit" class="audit"><div class="empty">—</div></div>
    </section>
  </div>
</div>
<footer>
  <span id="root">—</span> · click any intent / task to inspect
</footer>
<div class="modal-overlay" id="modal" onclick="if(event.target===this)closeModal()">
  <div class="modal" id="modal-body"></div>
</div>
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
const intentMap = {};   // id -> intent (with full body/children/etc)
const taskMap = {};     // id -> { task, intent }

function indexState(intents) {
  for (const i of intents) {
    intentMap[i.id] = i;
    for (const t of (i.tasks || [])) taskMap[t.id] = { task: t, intent: i };
    if (i.children) indexState(i.children);
  }
}

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
  cls.push('clickable');
  return `<div class="${cls.join(' ')}" data-id="${intent.id}" onclick="event.stopPropagation();showIntent('${intent.id}')">
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
  const items = active.slice(0, 5).map(t => {
    const verifs = (t.verifications || []).map(v =>
      `<span class="verif-dot ${v.status}" title="${esc(v.kind)}:${esc(v.category)} ${esc(v.status)}"></span>`
    ).join('');
    const verifBlock = verifs ? `<span class="verif-summary">${verifs}</span>` : '';
    return `<div class="item clickable" onclick="event.stopPropagation();showTask('${t.id}')">· <span class="tid">${shortId(t.id)}</span> ${esc(t.title)}${verifBlock}</div>`;
  }).join('');
  const more = active.length > 5 ? `<div class="item">… +${active.length - 5} more</div>` : '';
  return `<div class="tasks"><div class="counts">${badges}</div>${items}${more}</div>`;
}

function renderWorktrees(wts) {
  const el = $('worktrees');
  if (!wts.length) { el.innerHTML = '<div class="empty">なし</div>'; return; }
  el.innerHTML = wts.map(w => {
    const entry = taskMap[w.taskId];
    const title = entry ? esc(entry.task.title) : '(unknown task)';
    const status = entry ? esc(entry.task.status) : '';
    return `<div class="audit-entry">
      <span class="when">${shortId(w.taskId)}</span>
      <span class="op">${status}</span>
      <span>${title}</span>
      <div class="body">${esc(w.path)}</div>
    </div>`;
  }).join('');
}

function updateStats(state) {
  let totalIntents = 0, openTasks = 0;
  function walk(node) {
    totalIntents++;
    for (const t of (node.tasks || [])) {
      if (['open','claimed','inProgress'].includes(t.status)) openTasks++;
    }
    for (const c of (node.children || [])) walk(c);
  }
  for (const i of (state.intents || [])) walk(i);
  $('stat-intents').textContent = totalIntents;
  $('stat-tasks-open').textContent = openTasks;
  $('stat-claims').textContent = (state.claims || []).length;
  $('stat-worktrees').textContent = (state.worktrees || []).length;
  // page title でブラウザタブからも見えるように
  document.title = openTasks > 0
    ? `(${openTasks}) hoy dashboard`
    : 'hoy dashboard';
}

function renderAudit(entries) {
  const el = $('audit');
  if (!entries || !entries.length) { el.innerHTML = '<div class="empty">—</div>'; return; }
  el.innerHTML = entries.map(e => {
    const cls = e.op.replace(/\./g, '-');
    const when = new Date(e.timestamp * 1000).toTimeString().slice(0, 8);
    const keys = Object.keys(e.payload || {});
    const body = keys.map(k => `${k}=${esc(String(e.payload[k]).slice(0, 40))}`).join(' ');
    return `<div class="audit-entry">
      <span class="when">${when}</span>
      <span class="actor">${esc(e.actor.id)}</span>
      <span class="op ${cls}">${esc(e.op)}</span>
      <div class="body">${body}</div>
    </div>`;
  }).join('');
}

function showIntent(id) {
  const i = intentMap[id];
  if (!i) return;
  const tasks = i.tasks || [];
  const taskList = tasks.length ? tasks.map(t => `
    <div class="task-row clickable" onclick="event.stopPropagation();showTask('${t.id}')">
      <span class="tid">${shortId(t.id)}</span>
      [${esc(t.status)}] ${esc(t.title)}
    </div>`).join('') : '<div class="empty" style="padding:8px">no tasks</div>';
  const closedInfo = i.closedReason ? `<div class="row"><span class="k">closed reason</span> ${esc(i.closedReason)}</div>` : '';
  const parentInfo = i.parentId ? `<div class="row"><span class="k">parent</span> ${shortId(i.parentId)}</div>` : '';
  const bodyHTML = i.body ? `<div class="row"><span class="k">body</span></div><div class="body-text">${esc(i.body)}</div>` : '';
  $('modal-body').innerHTML = `
    <span class="close-btn" onclick="closeModal()">×</span>
    <div class="kind">intent</div>
    <h3>${esc(i.title)}</h3>
    <div class="row"><span class="k">id</span> ${esc(i.id)}</div>
    <div class="row"><span class="k">version</span> ${i.version}</div>
    <div class="row"><span class="k">status</span> ${esc(i.status)}</div>
    ${closedInfo}
    ${parentInfo}
    ${bodyHTML}
    <div class="row" style="margin-top:12px"><span class="k">tasks (${tasks.length})</span></div>
    ${taskList}
  `;
  $('modal').classList.add('open');
}

function showTask(id) {
  const entry = taskMap[id];
  if (!entry) return;
  const t = entry.task;
  const verifList = (t.verifications || []).map(v => {
    const evidenceHTML = v.evidence ? `<div class="body-text">${esc(v.evidence)}</div>` : '';
    return `<div class="verif ${v.status}">
      <div class="vhead">[${esc(v.status)}] ${esc(v.kind)}:${esc(v.category)}${v.required ? ' (required)' : ''}</div>
      <div style="color:var(--muted);font-size:11px">spec: ${esc(v.spec || '')}</div>
      ${evidenceHTML}
    </div>`;
  }).join('') || '<div class="empty" style="padding:8px">no checks</div>';
  const deps = (t.dependsOn || []).map(d => `${shortId(d.id)}@v${d.version}`).join(', ') || 'なし';
  const sha = t.completedSha ? t.completedSha : '—';
  const intentInfo = entry.intent ? `${shortId(entry.intent.id)} ${esc(entry.intent.title)}` : '';
  $('modal-body').innerHTML = `
    <span class="close-btn" onclick="closeModal()">×</span>
    <div class="kind">task</div>
    <h3>${esc(t.title)}</h3>
    <div class="row"><span class="k">id</span> ${esc(t.id)}</div>
    <div class="row"><span class="k">intent</span> <span class="clickable" onclick="showIntent('${entry.intent.id}')">${intentInfo}</span></div>
    <div class="row"><span class="k">status</span> ${esc(t.status)}</div>
    <div class="row"><span class="k">created by</span> ${esc(t.createdBy.id)} (${esc(t.createdBy.kind)})</div>
    <div class="row"><span class="k">depends on</span> ${esc(deps)}</div>
    <div class="row"><span class="k">completed sha</span> ${esc(sha)}</div>
    <div class="row" style="margin-top:12px"><span class="k">verifications (${(t.verifications || []).length})</span></div>
    ${verifList}
  `;
  $('modal').classList.add('open');
}

function closeModal() {
  $('modal').classList.remove('open');
}
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeModal(); });

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
    // click 用のインデックス再構築
    Object.keys(intentMap).forEach(k => delete intentMap[k]);
    Object.keys(taskMap).forEach(k => delete taskMap[k]);
    indexState(intents);
    const intentsEl = $('intents');
    if (!intents.length) {
      intentsEl.className = 'empty';
      intentsEl.textContent = 'なし';
    } else {
      intentsEl.className = '';
      intentsEl.innerHTML = intents.map(i => renderIntent(i, claimsByIntent)).join('');
    }
    renderAudit(state.audit || []);
    renderWorktrees(state.worktrees || []);
    updateStats(state);
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
