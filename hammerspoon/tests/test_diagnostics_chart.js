// Run with: node hammerspoon/tests/test_diagnostics_chart.js
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

const html = fs.readFileSync('hammerspoon/diagnostics.html', 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const now = Math.floor(Date.now() / 1000);

function page(percents) {
  const nodes = new Map();
  class Node {
    constructor() {
      this.children = [];
      this.attributes = {};
      this.style = {};
      this.dataset = {};
      this.clientWidth = 800;
      this.classList = { toggle() {} };
    }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    append(child) { this.children.push(child); }
    replaceChildren() { this.children = []; }
    addEventListener(name, fn) { this[name] = fn; }
    contains(target) { return target === this; }
  }
  const get = id => nodes.get(id) || (nodes.set(id, new Node()), nodes.get(id));
  const buttons = ['fit', 'fixed'].map(scale => {
    const button = new Node();
    button.dataset.scale = scale;
    return button;
  });
  const rows = percents.map((percent, i) => [now - 120 + i * 60, percent * 1e9, 100e9, 1000000, 500000]);
  const data = Object.fromEntries(['1h', '6h', '24h', '7d', '30d', 'All'].map(key => [key, rows]));
  const posts = [];
  const listeners = {};
  const context = vm.createContext({
    document: {
      querySelector: get,
      querySelectorAll: selector => selector === '[data-scale]' ? buttons : [],
      createElementNS: () => new Node(),
      addEventListener(name, fn) { listeners[name] = fn; },
      documentElement: {},
    },
    ResizeObserver: class { observe() {} },
    addEventListener() {},
    getComputedStyle: () => ({ getPropertyValue: name => name === '--popup-inset' ? '24px' : '0.33' }),
    webkit: { messageHandlers: { popup: { postMessage: value => posts.push(value) } } },
    innerHeight: 900,
  });
  vm.runInContext(script.replace('/*__DATA__*/', `const DATA = ${JSON.stringify(data)};`), context);
  return { get, buttons, listeners, posts };
}

function axis(svg) {
  return svg.children.filter(node => node.attributes.class === 'axis').map(node => node.textContent);
}

const { get, buttons, listeners, posts } = page([94, 95, 97]);
assert.equal(get('#used').textContent, '97 GB');
assert.match(html, /\.metric \{ display: flex; flex-direction: column; min-height: 88px;/);
assert.match(html, /\.metric \.value \{ align-self: flex-end; margin-top: auto;[^}]*font-size: 23px;/);
assert.equal((html.match(/class="metric"><div class="name">[^<]+<\/div><div class="value"/g) || []).length, 3);
assert.doesNotMatch(html, /class="detail"/);
assert.equal(get('#used-percent').textContent, '97%');
assert.equal(get('#free').textContent, '3 GB');
assert.match(html, /class="name">Disk used %</);
assert.match(html, /class="name">Free space</);
assert.doesNotMatch(html, /id="(?:read|write)"/);
const fractional = page([95.3]);
assert.equal(fractional.get('#used-percent').textContent, '95.3%');
assert.equal(fractional.get('#free').textContent, '4.7 GB');
assert.match(html, /data-range="1h" class="active"/);
assert.match(html, /let range = '1h'/);
listeners.pointerdown({ target: {} });
listeners.keydown({ key: 'Escape' });
assert.deepEqual(posts, ['close', 'close']);
assert.deepEqual(axis(get('#fullness')).filter(label => label.endsWith('%')), ['98%', '97%', '96%', '95%', '94%', '93%']);
const activity = get('#activity');
assert.deepEqual(axis(activity).filter(label => label.endsWith('MB/s')), ['1 MB/s', '0.5 MB/s', '0 MB/s', '0.5 MB/s', '1 MB/s']);
assert.equal(activity.children.filter(node => node.attributes.class === 'gridline zero-line').length, 1);
assert.deepEqual(activity.children.filter(node => node.attributes.class?.startsWith('area ')).map(node => node.attributes.class), ['area read', 'area write']);
const path = style => activity.children.find(node => node.attributes.class === `line ${style}`).attributes.d;
const y = style => Number(path(style).match(/^M[\d.]+,([\d.]+)/)[1]);
assert(y('read') > 78 && y('write') < 78);
assert(activity.children.find(node => node.attributes.class === 'area read').attributes.d.includes('Z'));
assert(activity.children.find(node => node.attributes.class === 'area write').attributes.d.includes('Z'));
for (const style of ['read', 'write']) assert.match(activity.children.find(node => node.attributes.class === `area ${style}`).attributes.d, /,78 L[\d.]+,78 Z/);
assert(!axis(get('#fullness')).includes('100% max'));
assert.match(html, /\.area\.read \{ fill: var\(--color-diskRead\)/);
assert.match(html, /\.area\.write \{ fill: var\(--color-diskWrite\)/);
const throughput = [path('read'), path('write')];
buttons[1].click();
assert.deepEqual(axis(get('#fullness')).filter(label => label.endsWith('%')), ['100%', '75%', '50%', '25%', '0%']);
assert.match(get('#scale-subtitle').textContent, /fixed 0–100% scale$/);
assert.equal(buttons[1].attributes['aria-pressed'], 'true');
assert.deepEqual([path('read'), path('write')], throughput);
buttons[0].click();
assert.match(get('#scale-subtitle').textContent, /fitted scale$/);
assert.equal(buttons[0].attributes['aria-pressed'], 'true');

for (const percents of [[95], [95, 95]]) {
  const svg = page(percents).get('#fullness');
  const labels = axis(svg).filter(label => label.endsWith('%'));
  assert(labels.length >= 2 && labels.every(label => Number.isFinite(parseFloat(label))));
  assert.match(svg.children.find(node => node.attributes.class === 'line used').attributes.d, /^M[\d.]+,[\d.]+/);
}
const overfull = page([105]);
assert.equal(overfull.get('#used-percent').textContent, '100%');
assert.equal(overfull.get('#free').textContent, '0 GB');
const capped = overfull.get('#fullness');
const topY = Number(capped.children.find(node => node.attributes.class === 'line used').attributes.d.match(/^M[\d.]+,([\d.]+)/)[1]);
assert(topY >= 8);
assert(axis(capped).filter(label => label.endsWith('%')).every(label => parseFloat(label) <= 100));
console.log('diagnostics chart interactions passed');
