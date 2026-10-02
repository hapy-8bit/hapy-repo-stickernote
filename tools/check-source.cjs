// 直接转译真实的纯逻辑源码执行检查，不复制一套模拟实现。
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
  const compiled = vm.runInThisContext(`(function(require,module,exports){${output}\n})`, { filename });
  compiled((name) => {
    if (!name.startsWith('.')) throw new Error('Only pure domain sources may be loaded');
    return load(path.resolve(path.dirname(filename), name));
  }, module, module.exports);
  return module.exports;
}

let checks = 0;
function check(name, test) { test(); checks++; console.log(`PASS ${name}`); }
const { JournalCodec } = load(path.join(root, 'entry/src/main/ets/data/JournalCodec'));
const { DateTools } = load(path.join(root, 'entry/src/main/ets/domain/DateTools'));
const { makeStickerRaster } = load(path.join(root, 'entry/src/main/ets/media/StickerRaster'));
const { StickerFactory } = load(path.join(root, 'entry/src/main/ets/domain/StickerFactory'));
const { copySubjectMask, mergeSubjectMasks } = load(path.join(root, 'entry/src/main/ets/media/StickerSubjectMask'));
const { centeredCropForDisplay } = load(path.join(root, 'entry/src/main/ets/domain/StickerCrop'));
const media = '/data/storage/el2/base/files/stickers';
const entry = { id: 'record-1', dateKey: '2024-02-29', title: '午后', category: '日常', note: '一张真实照片',
  imagePath: `${media}/photo-1.png`, mode: 'subject', createdAt: 100, updatedAt: 100 };
check('empty document stays empty', () => assert.deepEqual(JournalCodec.decode('{"schemaVersion":1,"entries":[]}', media), []));
check('valid leap day round trip', () => assert.deepEqual(JournalCodec.decode(JournalCodec.encode([entry], media), media), [entry]));
check('multiple photos on one day are valid', () => assert.equal(JournalCodec.decode(JournalCodec.encode([entry, { ...entry, id: 'record-2' }], media), media).length, 2));
check('corrupt JSON is rejected', () => assert.throws(() => JournalCodec.decode('{', media)));
check('future schema is rejected', () => assert.throws(() => JournalCodec.decode('{"schemaVersion":2,"entries":[]}', media)));
check('duplicate ids are rejected', () => assert.throws(() => JournalCodec.encode([entry, entry], media)));
check('invalid calendar date is rejected', () => assert.throws(() => JournalCodec.validate({ ...entry, dateKey: '2023-02-29' }, media)));
for (const invalid of ['../secret.png', '/nested/image.png', 'bad.png?x=1', 'bad\\path.png']) {
  check(`invalid image basename ${invalid}`, () => assert.throws(() => JournalCodec.validate({ ...entry, imagePath: `${media}/${invalid}` }, media)));
}
check('picker uri is rejected', () => assert.throws(() => JournalCodec.validate({ ...entry, imagePath: 'file://media/Photo/1' }, media)));
check('oversize text is rejected', () => assert.throws(() => JournalCodec.validate({ ...entry, note: '字'.repeat(2001) }, media)));
check('unknown image mode is rejected', () => assert.throws(() => JournalCodec.validate({ ...entry, mode: 'fake-success' }, media)));
check('invalid timestamps are rejected', () => assert.throws(() => JournalCodec.validate({ ...entry, updatedAt: 99 }, media)));
check('decoded records are independent copies', () => { const result = JournalCodec.validate(entry, media); result.title = 'changed'; assert.equal(entry.title, '午后'); });
check('seven days cross month and leap day', () => assert.deepEqual(DateTools.recent('2024-03-02'), ['2024-02-25','2024-02-26','2024-02-27','2024-02-28','2024-02-29','2024-03-01','2024-03-02']));
check('journal week is Monday through Sunday across a year boundary', () => {
  const expected = ['2024-12-30','2024-12-31','2025-01-01','2025-01-02','2025-01-03','2025-01-04','2025-01-05'];
  assert.deepEqual(DateTools.week('2025-01-01'), expected);
  assert.deepEqual(DateTools.week('2025-01-05'), expected);
});
check('journal week includes leap day without shifting local dates', () => {
  assert.deepEqual(DateTools.week('2024-02-29'), ['2024-02-26','2024-02-27','2024-02-28','2024-02-29','2024-03-01','2024-03-02','2024-03-03']);
});
const rgba = new Uint8Array(8 * 8 * 4);
for (let i = 0; i < 64; i++) rgba.set([128, 64, 32, 255], i * 4);
const mask = new Uint8Array(64);
for (let y = 2; y < 6; y++) for (let x = 2; x < 6; x++) mask[y * 8 + x] = 255;
const recipe=StickerFactory.defaultRecipe();
function render(next=recipe, input=rgba, selected=mask, w=8, h=8, premul=false) {
  return makeStickerRaster(input.buffer,selected.buffer,w,h,premul,next);
}
check('cutout keeps subject color and a transparent outside', () => {
  const result = render();
  const pixels = new Uint8Array(result.pixels);
  assert.deepEqual(Array.from(pixels.slice((10 * result.width + 10) * 4, (10 * result.width + 10) * 4 + 4)), [128,64,32,255]);
  assert.equal(pixels[3], 0);
});
check('outline adds white outside subject', () => {
  const result = render();
  const pixels = new Uint8Array(result.pixels);
  const offset = (10 * result.width + 9) * 4;
  assert.deepEqual(Array.from(pixels.slice(offset, offset + 4)), [255,255,255,255]);
});
check('empty subject crop cannot silently save blank', () => assert.throws(()=>render(recipe,rgba,new Uint8Array(64))));
check('invalid mask dimensions are rejected', () => assert.throws(()=>render(recipe,rgba,new Uint8Array(63))));
check('round outline excludes square corner outside circle', () => {
  const result=render({...recipe,borderWidth:2});
  const p=new Uint8Array(result.pixels);
  assert.equal(p[(2*result.width+2)*4+3],0);
  assert.equal(p[(4*result.width+2)*4+3],128);
});
check('zero border recovers subject color without baked outline', () => {
  const result=render({...recipe,borderWidth:0});
  assert.equal(result.width,8);
  const p=new Uint8Array(result.pixels);
  assert.deepEqual(Array.from(p.slice((2*result.width+2)*4,(2*result.width+2)*4+4)),[128,64,32,255]);
  assert.equal(p[(2*result.width+1)*4+3],0);
});
check('crop and mask share input coordinates',()=>{
  const result=render({...recipe,cropX:0.5,cropWidth:0.5,borderWidth:0});
  assert.equal(result.width,6); assert.equal(result.height,8);
});
check('original photo has explicit full-frame mode',()=>{
  const result=render({...recipe,mode:'original',borderWidth:0},rgba,new Uint8Array());
  assert.equal(result.width,12); assert.equal(result.height,12);
});
check('rotate and flip preserve dimensions and original colors',()=>{
  const input=new Uint8Array([20,30,40,255,90,80,70,255]);
  const result=render({...recipe,mode:'original',borderWidth:0,rotation:90,flipHorizontal:true},input,new Uint8Array(),2,1);
  const p=new Uint8Array(result.pixels); assert.equal(result.width,5); assert.equal(result.height,6);
  assert.deepEqual(Array.from(p.slice((2*5+2)*4,(2*5+2)*4+4)),[90,80,70,255]);
  assert.deepEqual(Array.from(p.slice((3*5+2)*4,(3*5+2)*4+4)),[20,30,40,255]);
});
check('premultiplied pixels restore straight RGB for export',()=>{
  const input=new Uint8Array([64,32,16,128]);
  const result=render({...recipe,mode:'original',borderWidth:0},input,new Uint8Array(),1,1,true);
  const p=new Uint8Array(result.pixels); assert.deepEqual(Array.from(p.slice((2*5+2)*4,(2*5+2)*4+4)),[128,64,32,128]);
});
check('recipe cannot crop outside source',()=>assert.throws(()=>render({...recipe,cropX:0.9,cropWidth:0.5})));
check('non-right-angle image orientation is rejected',()=>assert.throws(()=>render({...recipe,rotation:13})));
check('white outline never repaints soft subject RGB or alpha',()=>{
  const input=new Uint8Array([30,60,90,255]);
  for (const alpha of [7,15,16,64,128,200,254,255]) {
    const r=render({...recipe,borderWidth:8},input,new Uint8Array([alpha]),1,1);
    const p=new Uint8Array(r.pixels);
    const center=(10*r.width+10)*4;
    assert.deepEqual(Array.from(p.slice(center,center+4)),[30,60,90,alpha]);
  }
});
check('weak isolated mask flecks cannot grow opaque white islands',()=>{
  const w=20,h=8,input=new Uint8Array(w*h*4),m=new Uint8Array(w*h);
  for(let i=0;i<w*h;i++) input.set([20,40,60,255],i*4);
  m[3*w+1]=255; m[3*w+18]=16;
  const r=render({...recipe,borderWidth:2},input,m,w,h);
  const p=new Uint8Array(r.pixels);
  // bbox starts at x1/y3; padding4; the weak fleck stays alpha16, its neighbour clear.
  assert.deepEqual(Array.from(p.slice((4*r.width+21)*4,(4*r.width+21)*4+4)),[20,40,60,16]);
  assert.equal(p[(4*r.width+22)*4+3],0);
});
check('low alpha tail survives transparent trimming',()=>{
  const w=20,h=8,input=new Uint8Array(w*h*4),m=new Uint8Array(w*h);
  for(let i=0;i<w*h;i++) input.set([18,36,54,255],i*4);
  for(let y=2;y<6;y++) for(let x=2;x<6;x++) m[y*w+x]=255;
  m[3*w+15]=7;
  const r=render({...recipe,borderWidth:0},input,m,w,h);
  assert.equal(r.width,18);
  const p=new Uint8Array(r.pixels);
  assert.deepEqual(Array.from(p.slice((3*r.width+15)*4,(3*r.width+15)*4+4)),[18,36,54,7]);
});
check('premultiplied soft colors survive outlining without white tint',()=>{
  const r=render({...recipe,borderWidth:8},new Uint8Array([64,32,16,128]),new Uint8Array([200]),1,1,true);
  const p=new Uint8Array(r.pixels);
  assert.deepEqual(Array.from(p.slice((10*r.width+10)*4,(10*r.width+10)*4+4)),[128,64,32,100]);
});
check('matte preserves each source color across widths and orientations',()=>{
  const w=3,h=2,input=new Uint8Array([12,34,56,255,71,92,113,255,149,167,185,255,207,29,51,255,67,89,101,255,131,157,179,255]);
  const alphas=new Uint8Array([255,200,128,64,16,7]);
  const expected=new Set(Array.from(alphas,(a,i)=>`${input[i*4]},${input[i*4+1]},${input[i*4+2]},${a}`));
  for(const borderWidth of [0,1,8,24]) for(const rotation of [0,90,180,270]) for(const flipHorizontal of [false,true]) {
    const r=render({...recipe,borderWidth,rotation,flipHorizontal},input,alphas,w,h);
    const p=new Uint8Array(r.pixels); const found=new Set();
    for(let i=0;i<p.length;i+=4) {
      const key=Array.from(p.slice(i,i+4)).join(','); if(expected.has(key)) found.add(key);
    }
    assert.deepEqual(found,expected);
  }
});
for(const field of ['cropX','cropY','cropWidth','cropHeight']) {
  check(`nonfinite ${field} is rejected`,()=>assert.throws(()=>render({...recipe,mode:'original',[field]:NaN})));
}
check('full-frame and tiny native masks remain selectable',()=>{
  assert.deepEqual(Array.from(copySubjectMask(new Int32Array([255,255,255,255]),2,2)),[255,255,255,255]);
  assert.deepEqual(Array.from(copySubjectMask(new Int32Array([7,0,0,0]),2,2)),[7,0,0,0]);
});
check('malformed and empty native masks are rejected',()=>{
  for(const values of [[0,0,0,0],[255,-1,0,0],[256,0,0,0],[255,0]]) assert.equal(copySubjectMask(new Int32Array(values),2,2).length,0);
});
check('candidate union preserves transparency and complete input coordinates',()=>{
  assert.deepEqual(Array.from(mergeSubjectMasks([new Uint8Array([255,64,0,0]),new Uint8Array([0,128,32,0])],2,2)),[255,128,32,0]);
});
check('display crop ratio follows rotated source coordinates',()=>{
  for(const angle of [0,90,180,270]) for(const ratio of [1,4/3,3/4]) {
    const c=centeredCropForDisplay(800,600,ratio,angle);
    const sw=c.width*800,sh=c.height*600;
    const display=angle===90||angle===270?sh/sw:sw/sh;
    assert.ok(Math.abs(display-ratio)<1e-10);
    assert.ok(c.x>=0&&c.y>=0&&c.x+c.width<=1&&c.y+c.height<=1);
  }
});
function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((x) => x.isDirectory() ? walk(path.join(dir, x.name)) : [path.join(dir, x.name)]);
}
check('all ArkTS files remain below 800 lines', () => {
  for (const file of walk(path.join(root, 'entry/src/main/ets')).filter((x) => x.endsWith('.ets'))) {
    assert.ok(fs.readFileSync(file, 'utf8').split('\n').length < 800, file);
  }
});
console.log(`${checks} checks passed (domain and codec; excludes device SDK runtime).`);
