'use strict';

const POLL_MS = 5000;
const STALE_AFTER = 90; // seconds before "updated Ns ago" turns yellow

const state = { data: null, student: null, failure: null };

/* ---------- tiny DOM helper (no innerHTML, ever) ---------- */
function el(tag, props, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props || {})) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key.startsWith('on') && typeof value === 'function') {
      node.addEventListener(key.slice(2).toLowerCase(), value);
    } else if (value === true) node.setAttribute(key, '');
    else node.setAttribute(key, String(value));
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) continue;
    node.append(child.nodeType ? child : document.createTextNode(String(child)));
  }
  return node;
}

/* ---------- formatting ---------- */
function relAge(seconds) {
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  if (seconds < 60) return Math.round(seconds) + ' s';
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return minutes + ' min';
  const hours = Math.floor(minutes / 60);
  return hours + ' h ' + (minutes % 60) + ' min';
}

function uptime(seconds) {
  if (!seconds) return '—';
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (days) return days + 'd ' + hours + 'h';
  if (hours) return hours + 'h ' + minutes + 'm';
  return minutes + 'm';
}

/* ---------- copy to clipboard (http:// LAN is not a secure context) ---------- */
async function copyText(value, button) {
  let ok = false;
  try {
    if (navigator.clipboard && window.isSecureContext) {
      await navigator.clipboard.writeText(value);
      ok = true;
    } else {
      const area = document.createElement('textarea');
      area.value = value;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.append(area);
      area.select();
      ok = document.execCommand('copy');
      area.remove();
    }
  } catch (err) {
    ok = false;
  }
  if (button) {
    const label = button.textContent;
    button.classList.toggle('copied', ok);
    button.textContent = ok ? 'copied' : 'copy failed';
    setTimeout(() => {
      button.textContent = label;
      button.classList.remove('copied');
    }, 1200);
  }
}

/* ---------- header ---------- */
function renderHeader() {
  const ageEl = document.getElementById('age');
  const sumEl = document.getElementById('summary');
  const data = state.data;

  if (!data) {
    ageEl.textContent = state.failure ? 'collector unreachable' : 'loading…';
    ageEl.className = 'age' + (state.failure ? ' bad' : '');
    sumEl.textContent = '';
    return;
  }

  const age = Math.max(0, Date.now() / 1000 - data.generated_epoch);
  ageEl.textContent = 'updated ' + relAge(age) + ' ago';
  ageEl.className = 'age' + (age > STALE_AFTER * 2 ? ' bad' : age > STALE_AFTER ? ' stale' : '');

  const guests = data.guests || [];
  const up = guests.filter((g) => g.state === 'running').length;
  sumEl.textContent =
    '· ' + up + '/' + guests.length + ' VMs up' +
    ' · cycle ' + (data.cycle_ms || 0) + ' ms' +
    (data.complete ? '' : ' · incomplete pass');

  const cadence = document.getElementById('cadence');
  if (cadence) cadence.textContent = String(data.interval || 10);
}

/* ---------- banners / warnings ---------- */
function renderBanner() {
  const box = document.getElementById('banner');
  if (state.failure) {
    box.hidden = false;
    box.textContent = 'Cannot read state.json: ' + state.failure;
  } else {
    box.hidden = true;
    box.textContent = '';
  }
}

function renderWarnings() {
  const box = document.getElementById('warnings');
  const list = (state.data && state.data.warnings) || [];
  box.replaceChildren();
  if (!list.length) {
    box.hidden = true;
    return;
  }
  box.hidden = false;
  box.append(
    el('h2', { text: list.length + ' warning' + (list.length > 1 ? 's' : '') })
  );
  const ul = el('ul');
  for (const warning of list) {
    ul.append(
      el('li', { class: warning.severity === 'error' ? 'error' : '' }, warning.text)
    );
  }
  box.append(ul);
}

/* ---------- badges ---------- */
function badge(text, cls) {
  return el('span', { class: 'badge' + (cls ? ' ' + cls : ''), text });
}

function statePill(guest) {
  const running = guest.state === 'running';
  return el('span', {
    class: 'pill ' + (running ? 'ok' : 'bad'),
    text: guest.state,
  });
}

function copyButton(label, value) {
  const button = el('button', { type: 'button', class: 'btn small', text: label });
  button.addEventListener('click', () => copyText(value, button));
  return button;
}

/* ---------- one VM block ---------- */
function vmBlock(role, guest, data) {
  const wrap = el('div', { class: 'vm' });
  const title = role === 'client' ? 'Client' : role === 'ebs' ? 'Sandbox' : 'VM';

  if (!guest) {
    wrap.append(
      el('div', { class: 'vm-head' },
        el('span', { class: 'role', text: title }),
        el('span', { class: 'pill na', text: 'missing' })
      ),
      el('div', { class: 'ip-row' }, el('span', { class: 'ip none', text: '—' }))
    );
    return wrap;
  }

  wrap.append(
    el('div', { class: 'vm-head' },
      el('span', { class: 'role', text: title }),
      el('span', { class: 'name', text: guest.name }),
      statePill(guest)
    )
  );

  const ipRow = el('div', { class: 'ip-row' });
  if (guest.ip) {
    ipRow.append(el('span', { class: 'ip', text: guest.ip }));
    if (guest.ip_stale) {
      const since = guest.last_seen
        ? relAge(Date.now() / 1000 - Date.parse(guest.last_seen) / 1000) + ' ago'
        : 'earlier';
      ipRow.append(el('span', { class: 'since stale', text: 'last seen ' + since }));
    }
  } else {
    ipRow.append(el('span', { class: 'ip none', text: 'no IP yet' }));
  }
  if (guest.carried) {
    ipRow.append(el('span', { class: 'since stale', text: 'not refreshed (endpoint down)' }));
  }
  wrap.append(ipRow);

  if (guest.conflict) {
    wrap.append(el('p', { class: 'hint', text: 'IP conflict: ' + guest.conflict }));
  }

  const ip = guest.ip;
  const actions = el('div', { class: 'actions' });

  if (ip && role === 'client') {
    actions.append(
      copyButton('copy IP', ip),
      copyButton('copy VNC', ip + ':' + data.vnc_port)
    );
  }

  if (ip && role === 'ebs') {
    const url = 'http://' + ip + ':' + data.app_port + '/OA_HTML/AppsLogin';
    actions.append(
      el('a', { class: 'btn small', href: url, target: '_blank', rel: 'noopener' }, 'Open EBS'),
      copyButton('copy URL', url),
      copyButton('copy DB', ip + ':' + data.db_port + '/' + data.db_sid),
      copyButton('copy SSH', 'ssh -oHostKeyAlgorithms=+ssh-rsa root@' + ip)
    );
  }

  if (ip && role === 'other') actions.append(copyButton('copy IP', ip));
  if (actions.childNodes.length) wrap.append(actions);

  const checks = guest.checks || {};
  const badges = el('div', { class: 'badges' });
  if (role === 'ebs') {
    const apps = checks.apps;
    badges.append(
      badge('Apps ' + (apps === null || apps === undefined ? '—' : apps),
        apps === 302 ? 'ok' : apps === null || apps === undefined ? '' : 'bad')
    );
    badges.append(
      badge('DB ' + data.db_port,
        checks.db === true ? 'ok' : checks.db === false ? 'bad' : '')
    );
  } else if (role === 'client') {
    badges.append(
      badge('VNC ' + data.vnc_port,
        checks.vnc === true ? 'ok' : checks.vnc === false ? 'bad' : '')
    );
  }
  if (guest.state === 'running') badges.append(badge('up ' + uptime(guest.uptime), ''));
  wrap.append(badges);

  return wrap;
}

/* ---------- cards ---------- */
function studentCard(number, slot, data) {
  const card = el('article', {
    class: 'card',
    'data-student': String(number),
    id: 'stu-' + number,
  });
  card.append(
    el('div', { class: 'card-head' },
      el('h3', { text: 'Student ' + String(number).padStart(2, '0') }),
      el('span', { class: 'num',
        text: slot.ebs ? 'sandbox ' + slot.ebs.vmid : '' })
    )
  );
  card.append(vmBlock('client', slot.client, data));
  card.append(vmBlock('ebs', slot.ebs, data));
  for (const extra of slot.extra || []) card.append(vmBlock(extra.role, extra, data));
  if ((slot.client && slot.client.conflict) || (slot.ebs && slot.ebs.conflict)) {
    card.classList.add('conflict');
  }
  if ((slot.client && slot.client.carried) || (slot.ebs && slot.ebs.carried)) {
    card.classList.add('stale');
  }
  return card;
}

function vmCard(guest, data) {
  const card = el('article', {
    class: 'card' + (guest.conflict ? ' conflict' : '') + (guest.carried ? ' stale' : ''),
  });
  card.append(
    el('div', { class: 'card-head' },
      el('h3', { text: guest.role === 'ebs' ? 'Class instance' : guest.name }),
      el('span', { class: 'num', text: guest.name + ' · ' + guest.vmid })
    )
  );
  card.append(vmBlock(guest.role, guest, data));
  return card;
}

/* ---------- sites ---------- */
function siteSection(label, endpoint, guests, data, multiple) {
  const section = el('section', { class: 'site' });
  const head = el('div', { class: 'site-head' },
    el('h2', { text: multiple ? label : 'Lab' })
  );

  if (endpoint) {
    if (!endpoint.ok) {
      head.append(el('span', { class: 'node',
        text: 'endpoint down — ' + (endpoint.error || 'unreachable') }));
    }
    for (const node of endpoint.nodes || []) {
      const ratio = node.mem && node.maxmem ? node.mem / node.maxmem : 0;
      const pct = Math.min(100, Math.round(ratio * 100));
      head.append(
        el('span', { class: 'node' },
          node.node + (node.status === 'online' ? '' : ' (' + node.status + ')'),
          el('span', { class: 'bar' }, el('i', { style: 'width:' + pct + '%' })),
          pct + '% RAM'
        )
      );
    }
  }
  section.append(head);

  for (const guest of guests) {
    if (guest.student === null && guest.role === 'ebs') section.append(vmCard(guest, data));
  }

  const byStudent = new Map();
  const others = [];
  for (const guest of guests) {
    if (guest.student === null) {
      if (guest.role !== 'ebs') others.push(guest);
      continue;
    }
    if (!byStudent.has(guest.student)) {
      byStudent.set(guest.student, { client: null, ebs: null, extra: [] });
    }
    const slot = byStudent.get(guest.student);
    if (guest.role === 'client') slot.client = guest;
    else if (guest.role === 'ebs') slot.ebs = guest;
    else slot.extra.push(guest);
  }

  if (byStudent.size) {
    const grid = el('div', { class: 'grid' });
    for (const number of [...byStudent.keys()].sort((a, b) => a - b)) {
      grid.append(studentCard(number, byStudent.get(number), data));
    }
    section.append(grid);
  }

  for (const guest of others) section.append(vmCard(guest, data));
  return section;
}

function renderSites() {
  const root = document.getElementById('sites');
  root.replaceChildren();
  const data = state.data;
  if (!data) return;

  const sites = new Map();
  for (const endpoint of data.endpoints || []) {
    sites.set(endpoint.label, { endpoint, guests: [] });
  }
  for (const guest of data.guests || []) {
    if (!sites.has(guest.site)) sites.set(guest.site, { endpoint: null, guests: [] });
    sites.get(guest.site).guests.push(guest);
  }

  const multiple = sites.size > 1;
  for (const [label, site] of sites) {
    root.append(siteSection(label, site.endpoint, site.guests, data, multiple));
  }
}

/* ---------- "you are" ---------- */
function renderWho() {
  const select = document.getElementById('who');
  const students = new Set();
  for (const guest of (state.data && state.data.guests) || []) {
    if (guest.student !== null && guest.student !== undefined) students.add(guest.student);
  }
  const list = [...students].sort((a, b) => a - b);
  const key = list.join(',');
  if (select.dataset.key !== key) {
    select.dataset.key = key;
    select.replaceChildren(
      el('option', { value: '', text: '—' }),
      ...list.map((n) =>
        el('option', { value: String(n), text: 'Student ' + String(n).padStart(2, '0') })
      )
    );
  }
  select.value = state.student === null ? '' : String(state.student);
}

function applyHighlight() {
  for (const card of document.querySelectorAll('.card[data-student]')) {
    card.classList.toggle(
      'me',
      state.student !== null && Number(card.dataset.student) === state.student
    );
  }
}

/* ---------- polling ---------- */
async function load() {
  try {
    const response = await fetch('state.json?ts=' + Date.now(), { cache: 'no-store' });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    state.data = await response.json();
    state.failure = null;
    renderHeader();
    renderBanner();
    renderWarnings();
    renderSites();
    renderWho();
    applyHighlight();
  } catch (err) {
    state.failure = String((err && err.message) || err);
    renderHeader();
    renderBanner();
  }
}

function boot() {
  const params = new URLSearchParams(window.location.search);
  let initial = params.get('stu');
  if (!initial) {
    try {
      initial = localStorage.getItem('portal.student');
    } catch (err) {
      initial = null;
    }
  }
  const number = Number(initial);
  if (Number.isFinite(number) && number > 0) state.student = number;

  document.getElementById('who').addEventListener('change', (event) => {
    const value = event.target.value;
    state.student = value ? Number(value) : null;
    try {
      if (value) localStorage.setItem('portal.student', value);
      else localStorage.removeItem('portal.student');
    } catch (err) {
      /* localStorage can be disabled - the page still works */
    }
    applyHighlight();
  });

  document.getElementById('refresh').addEventListener('click', load);

  load();
  window.setInterval(load, POLL_MS);
  window.setInterval(renderHeader, 1000);
}

document.addEventListener('DOMContentLoaded', boot);
