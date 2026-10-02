// 检查真实导航协调器的回调所有权，UIContext 替身只控制动画完成顺序，不模拟 ArkUI 渲染。
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const root = path.resolve(__dirname, '..');
const cache = new Map();
function load(filename) {
  filename = path.resolve(filename);
  if (!filename.endsWith('.ets')) filename += '.ets';
  if (cache.has(filename)) return cache.get(filename).exports;
  const module = { exports: {} };
  cache.set(filename, module);
  const output = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }
  }).outputText;
  const execute = vm.runInNewContext(`(function(require,module,exports){${output}\n})`, {
    Curve: { EaseIn: 'easeIn', EaseOut: 'easeOut' }
  }, { filename });
  execute((name) => {
    assert.ok(name.startsWith('.'), 'SDK value calls must stay in the platform adapter');
    return load(path.resolve(path.dirname(filename), name));
  }, module, module.exports);
  return module.exports;
}
const { PageMotion } = load(path.join(root, 'entry/src/main/ets/platform/PageMotion'));
function fixture() {
  const completions = [];
  const frames = [];
  const state = { route: 'main', locked: false };
  const ui = { animateTo(params, apply) { apply(); completions.push(params.onFinish); } };
  return { ui, completions, frames, state,
    commit(route) { return () => { state.route = route; }; },
    present(opacity, offset) { frames.push([opacity, offset]); },
    lock(active) { state.locked = active; } };
}
let checks = 0;
function check(name, run) { run(); checks++; console.log(`PASS ${name}`); }
check('navigation commits once between exit and entry and unlocks after entry', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.transition(f.ui, false, 1, f.commit('settings'), f.present, f.lock);
  assert.equal(f.state.route, 'main'); assert.equal(f.state.locked, true);
  f.completions.shift()();
  assert.equal(f.state.route, 'settings'); assert.equal(f.state.locked, true);
  f.completions.shift()();
  assert.equal(f.state.locked, false); assert.deepEqual(f.frames.at(-1), [1, 0]);
});
check('return direction reverses visual travel without changing the destination', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.transition(f.ui, false, -1, f.commit('main'), f.present, f.lock);
  assert.ok(f.frames[0][1] > 0);
  f.completions.shift()(); assert.ok(f.frames[1][1] < 0);
  f.completions.shift()(); assert.equal(f.state.locked, false);
});
check('reduced motion changes route immediately with no animation callback dependency', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.transition(f.ui, true, 1, f.commit('calendar'), f.present, f.lock);
  assert.equal(f.state.route, 'calendar'); assert.equal(f.state.locked, false);
  assert.equal(f.completions.length, 0); assert.deepEqual(f.frames.at(-1), [1, 0]);
});
check('a superseded exit callback cannot reopen an older page', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.transition(f.ui, false, 1, f.commit('settings'), f.present, f.lock);
  const stale = f.completions.shift();
  motion.transition(f.ui, false, 1, f.commit('calendar'), f.present, f.lock);
  stale(); assert.equal(f.state.route, 'main');
  f.completions.shift()(); f.completions.shift()();
  assert.equal(f.state.route, 'calendar'); assert.equal(f.state.locked, false);
});
check('disposing the owner invalidates pending navigation and presentation updates', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.transition(f.ui, false, 1, f.commit('settings'), f.present, f.lock);
  motion.invalidate(); const count = f.frames.length;
  f.completions.shift()(); assert.equal(f.state.route, 'main'); assert.equal(f.frames.length, count);
});
check('an older entry callback cannot unlock a newer transition', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.transition(f.ui, false, 1, f.commit('settings'), f.present, f.lock);
  f.completions.shift()(); const staleEntry = f.completions.shift();
  motion.transition(f.ui, false, -1, f.commit('main'), f.present, f.lock);
  staleEntry(); assert.equal(f.state.locked, true);
  f.completions.shift()(); f.completions.shift()(); assert.equal(f.state.locked, false);
});
check('camera navigation replaces the route immediately without retaining an exit surface', () => {
  const f = fixture(); const motion = new PageMotion();
  motion.enter(f.ui, false, f.commit('camera'), f.present, f.lock);
  assert.equal(f.state.route, 'camera'); assert.equal(f.completions.length, 1);
  f.completions.shift()(); assert.equal(f.state.locked, false); assert.deepEqual(f.frames.at(-1), [1, 0]);
});
check('system-disabled animations complete synchronously without leaving controls locked', () => {
  const f = fixture(); const motion = new PageMotion();
  f.ui.animateTo = (params, apply) => { apply(); params.onFinish?.(); };
  motion.transition(f.ui, false, 1, f.commit('settings'), f.present, f.lock);
  assert.equal(f.state.route, 'settings'); assert.equal(f.state.locked, false);
  assert.deepEqual(f.frames.at(-1), [1, 0]);
});
console.log(`${checks} motion checks passed`);
