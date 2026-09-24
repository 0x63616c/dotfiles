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
    contains() { return true; }
  }
  const get = id => nodes.get(id) || (nodes.set(id, new Node()), nodes.get(id));
  const buttons = ['fit', 'fixed'].map(scale => {
    const button = new Node();
    button.dataset.scale = scale;
    return button;
  });
  const rows = percents.map((percent, i) => [now - 120 + i * 60, percent, 100, 1000000, 500000]);
  const data = Object.fromEntries(['1h', '6h', '24h', '7d', '30d', 'All'].map(key => [key, rows]));
  const context = vm.createContext({
    document: {
      querySelector: get,
      querySelectorAll: selector => selector === '[data-scale]' ? buttons : [],
      createElementNS: () => new Node(),
      addEventListener() {},
    },
    ResizeObserver: class { observe() {} },
    addEventListener() {},
    innerHeight: 900,
  });
  vm.runInContext(script.replace('/*__DATA__*/', `const DATA = ${JSON.stringify(data)};`), context);
  return { get, buttons };
}

function axis(svg) {
  return svg.children.filter(node => node.attributes.class === 'axis').map(node => node.textContent);
}

const { get, buttons } = page([94, 95, 97]);
assert.deepEqual(axis(get('#fullness')).filter(label => label.endsWith('%')), ['98%', '97%', '96%', '95%', '94%', '93%']);
const activity = get('#activity');
assert.deepEqual(axis(activity).filter(label => label.endsWith('MB/s')), ['1 MB/s', '0.5 MB/s', '0 MB/s', '0.5 MB/s', '1 MB/s']);
assert.equal(activity.children.filter(node => node.attributes.class === 'gridline zero-line').length, 1);
const path = style => activity.children.find(node => node.attributes.class === `line ${style}`).attributes.d;
const y = style => Number(path(style).match(/^M[\d.]+,([\d.]+)/)[1]);
assert(y('read') > 78 && y('write') < 78);
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
console.log('diagnostics chart interactions passed');
