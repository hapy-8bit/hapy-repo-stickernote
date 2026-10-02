// 执行真实源码的数据行为检查；文件 API 使用内存替身，不代表真机存储验收。
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const projectRoot = path.resolve(__dirname, '..');
const root = path.join(projectRoot, 'entry/src/main/ets');
const documents = new Map(), handles = new Map();
let nextHandle = 0, failRename = false, renameCount = 0;
const directories = new Set(['/app', '/app/stickers', '/app/stickers/asset1']);
const links = new Set();
function missing() { return Object.assign(new Error('missing'), {code:13900002}); }
const mockFs = {
  OpenMode: {CREATE:1, WRITE_ONLY:2, READ_ONLY:4, NOFOLLOW:8},
  lstatSync(p) {
    if (!documents.has(p) && !directories.has(p) && !links.has(p)) throw missing();
    return {size:documents.get(p)?.length ?? 0, isFile:()=>documents.has(p), isDirectory:()=>directories.has(p), isSymbolicLink:()=>links.has(p)};
  },
  readTextSync(p) { if (!documents.has(p)) throw missing(); return documents.get(p).toString('utf8'); },
  openSync(p, mode) {
    if (links.has(p)) throw new Error('nofollow');
    if (mode & 1) documents.set(p, Buffer.alloc(0));
    else if (!documents.has(p)) throw missing();
    const fd = ++nextHandle; handles.set(fd,p); return {fd};
  },
  readSync(fd, buffer) { const bytes=documents.get(handles.get(fd)); const length=Math.min(bytes.length,buffer.byteLength); new Uint8Array(buffer).set(bytes.subarray(0,length)); return length; },
  writeSync(fd, buffer, options) {
    const p=handles.get(fd), bytes=Buffer.from(buffer), old=documents.get(p), start=options.offset;
    const next=Buffer.alloc(Math.max(old.length,start+bytes.length)); old.copy(next); bytes.copy(next,start); documents.set(p,next); return bytes.length;
  },
  closeSync(file) { handles.delete(file.fd); }, fsyncSync() {},
  renameSync(from,to) { if (failRename) throw new Error('disk'); renameCount++; documents.set(to,documents.get(from)); documents.delete(from); },
  unlinkSync(p) { documents.delete(p); }
};
const kits = {'@kit.CoreFileKit':{fileIo:mockFs},'@kit.ArkTS':{util:{generateRandomUUID:()=>`uuid-${nextHandle}`,TextEncoder:class {encodeInto(s){return new Uint8Array(Buffer.from(s));}}}}, '@kit.AbilityKit':{}, '@kit.BasicServicesKit':{}};
const cache = new Map();
function load(file) {
  file = path.resolve(file); if (cache.has(file)) return cache.get(file).exports;
  const compiled = ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020},reportDiagnostics:true});
  assert.equal(compiled.diagnostics?.length ?? 0,0);
  const mod={exports:{}}; cache.set(file,mod);
  const requireHere=(name)=>kits[name] ?? load(path.resolve(path.dirname(file),name+'.ets'));
  new Function('require','module','exports',compiled.outputText)(requireHere,mod,mod.exports);
  return mod.exports;
}
const {StickerCodec}=load(root+'/data/StickerCodec.ets');
const {StickerMigration}=load(root+'/data/StickerMigration.ets');
const {StickerFactory}=load(root+'/domain/StickerFactory.ets');
const {LocalStickerRepository}=load(root+'/data/StickerRepository.ets');
const {DEFAULT_STICKER_CATEGORIES}=load(root+'/domain/StickerModels.ets');
const png=Buffer.alloc(32); Buffer.from([137,80,78,71,13,10,26,10]).copy(png);
const asset=()=>StickerFactory.createAsset('asset1','/app/stickers/asset1/source.source','camera',2,2,100);
const revision=(id='rev1')=>StickerFactory.createRevision(id,'asset1','/app/stickers/asset1/raw.mask',`/app/stickers/asset1/${id}.png`,2,2,StickerFactory.defaultRecipe(),100);
const placement=(id='place1',revisionId='rev1')=>StickerFactory.createPlacement(id,'2026-09-29','asset1',revisionId,0,100);
const store=()=>({schemaVersion:2,assets:[asset()],revisions:[revision()],placements:[placement()],categories:DEFAULT_STICKER_CATEGORIES.slice()});
const clone=(v)=>JSON.parse(JSON.stringify(v));
let count=0;
async function check(name,body){ await body(); count++; console.log(`PASS ${name}`); }
async function rejectsPreserved(repo,work) { const old=documents.get('/app/sticker-store.json')?.toString(); await assert.rejects(work); assert.equal(documents.get('/app/sticker-store.json')?.toString(),old); }
function media(){ documents.set('/app/stickers/asset1/source.source',png); documents.set('/app/stickers/asset1/raw.mask',Buffer.alloc(4,255)); documents.set('/app/stickers/asset1/rev1.png',png); documents.set('/app/stickers/asset1/rev2.png',png); }
function reset(){documents.clear(); links.clear(); failRename=false; renameCount=0; media();}
(async()=>{
  await check('whole store roundtrip keeps distinct asset/revision/placement',()=>assert.deepEqual(StickerCodec.decode(StickerCodec.encode(store(),'/app/stickers'),'/app/stickers'),store()));
  await check('early schema 2 missing asset note normalizes to empty',()=>{const s=store();delete s.assets[0].note;const decoded=StickerCodec.decode(JSON.stringify(s),'/app/stickers');assert.equal(decoded.assets[0].note,'');});
  await check('asset note length is validated',()=>{const s=store();s.assets[0].note='字'.repeat(2001);assert.throws(()=>StickerCodec.validate(s,'/app/stickers'));});
  await check('invalid leap-day is rejected',()=>{const s=store();s.placements[0].dateKey='2025-02-29';assert.throws(()=>StickerCodec.validate(s,'/app/stickers'));});
  await check('valid leap-day accepted',()=>{const s=store();s.placements[0].dateKey='2024-02-29';StickerCodec.validate(s,'/app/stickers');});
  await check('crop must fit source',()=>{const s=store();s.revisions[0].recipe.cropX=.5;assert.throws(()=>StickerCodec.validate(s,'/app/stickers'));});
  await check('placement cannot point at another asset revision',()=>{const s=store();s.placements[0].assetId='absent';assert.throws(()=>StickerCodec.validate(s,'/app/stickers'));});
  await check('duplicate version ids rejected',()=>{const s=store();s.revisions.push(clone(s.revisions[0]));assert.throws(()=>StickerCodec.validate(s,'/app/stickers'));});
  await check('outside / traversal / picker / deep paths rejected',()=>{for(const p of ['/app/stickers2/x.png','/app/stickers/../x.png','datashare://image','/app/stickers/a/b/x.png'])assert.throws(()=>StickerCodec.filePath(p,'/app/stickers','image'));});
  await check('factory owns recipe copy',()=>{const recipe=StickerFactory.defaultRecipe();const r=StickerFactory.createRevision('r','a','','/app/stickers/x.png',2,2,recipe,100);recipe.borderWidth=10;assert.equal(r.recipe.borderWidth,8);});
  const old={schemaVersion:1,entries:[{id:'old1',dateKey:'2026-09-28',title:'茶杯',category:'日常',note:'第一天',imagePath:'/app/stickers/old.png',mode:'subject',createdAt:100,updatedAt:100},{id:'old2',dateKey:'2026-09-29',title:'杯子',category:'美食',note:'第二天',imagePath:'/app/stickers/old.png',mode:'original',createdAt:110,updatedAt:120}]};
  await check('legacy shared file one asset two dates and no fake source',()=>{const s=StickerMigration.fromLegacy(JSON.stringify(old),'/app/stickers');assert.equal(s.assets.length,1);assert.equal(s.revisions.length,2);assert.equal(s.placements.length,2);assert.deepEqual(s.placements.map(x=>x.note),['第一天','第二天']);assert.equal(s.assets[0].note,'第二天');assert.equal(s.assets[0].sourcePath,'');assert.equal(s.assets[0].width,0);assert.equal(s.revisions[1].recipe.mode,'original');});
  await check('legacy migration deterministic',()=>assert.deepEqual(StickerMigration.fromLegacy(JSON.stringify(old),'/app/stickers'),StickerMigration.fromLegacy(JSON.stringify(old),'/app/stickers')));
  await check('legacy oversized IDs stay valid',()=>{const d=clone(old);d.entries[0].id='a'.repeat(128);d.entries[1].id='a'.repeat(127)+'b';const s=StickerMigration.fromLegacy(JSON.stringify(d),'/app/stickers');assert.notEqual(s.placements[0].id,s.placements[1].id);assert.ok(s.placements.every(x=>x.id.length<=128));});
  reset(); let repo=new LocalStickerRepository({filesDir:'/app'});
  await check('empty load creates no fake data or index',async()=>{assert.equal((await repo.load()).assets.length,0);assert.equal(documents.has('/app/sticker-store.json'),false);});
  await check('library-only save restores asset note without a day',async()=>{const a=asset();a.note='只收进贴纸盒';await repo.saveAsset(a,revision(),undefined);const saved=await repo.load();assert.equal(saved.assets[0].note,'只收进贴纸盒');assert.equal(saved.placements.length,0);await repo.removeAsset(a.id);});
  await check('atomic asset/version/day saved',async()=>{const p=placement();p.note='当天的注记';await repo.saveAsset(asset(),revision(),p);assert.equal((await repo.load()).placements.length,1);});
  await check('loaded objects cannot mutate persistent store',async()=>{const s=await repo.load();s.assets[0].title='mutated';assert.equal((await repo.load()).assets[0].title,'');});
  await check('editing asset note does not rewrite historical day note',async()=>{const a=(await repo.load()).assets[0];a.note='资产的新注记';await repo.updateAsset(a);const saved=await repo.load();assert.equal(saved.assets[0].note,'资产的新注记');assert.equal(saved.placements[0].note,'当天的注记');});
  await check('in-use asset deletion rejected',async()=>rejectsPreserved(repo,()=>repo.removeAsset('asset1')));
  await check('new revision leaves original history pinned',async()=>{await repo.saveAsset(asset(),revision('rev2'),undefined);assert.equal((await repo.load()).placements[0].revisionId,'rev1');});
  await check('immutable revision cannot be overwritten',async()=>{const r=revision();r.recipe.borderWidth=9;await rejectsPreserved(repo,()=>repo.saveAsset(asset(),r,undefined));});
  await check('new revision cannot reuse output file',async()=>{const r=revision('rev3');r.imagePath=revision().imagePath;await rejectsPreserved(repo,()=>repo.saveAsset(asset(),r,undefined));});
  await check('asset source immutable',async()=>{const a=asset();a.sourcePath='/app/stickers/x.png';await rejectsPreserved(repo,()=>repo.updateAsset(a));});
  await check('invalid batch commits zero placements',async()=>{const good=placement('p2');const bad=placement('p3');bad.revisionId='missing';await rejectsPreserved(repo,()=>repo.savePlacements([good,bad]));assert.equal((await repo.load()).placements.length,1);});
  await check('valid batch exactly one atomic commit',async()=>{const before=renameCount;await repo.savePlacements([placement('p2'),placement('p3')]);assert.equal(renameCount,before+1);assert.equal((await repo.load()).placements.length,3);});
  await check('duplicate batch ID rejected without write',async()=>rejectsPreserved(repo,()=>repo.savePlacements([placement('p4'),placement('p4')])));
  await check('category rename updates assets once',async()=>{const a=asset();a.category='日常';await repo.updateAsset(a);await repo.renameCategory('日常','每日');assert.equal((await repo.load()).assets[0].category,'每日');});
  await check('cannot remove occupied category',async()=>{const s=await repo.load();await rejectsPreserved(repo,()=>repo.saveCategories(s.categories.filter(x=>x!=='每日')));});
  await check('failed rename preserves old index and removes pending',async()=>{const p=placement('p2');p.x=.6;p.updatedAt=200;failRename=true;await rejectsPreserved(repo,()=>repo.savePlacement(p));failRename=false;assert.equal([...documents.keys()].some(x=>x.includes('.pending-')),false);});
  await check('delete day keeps reusable asset',async()=>{for(const p of (await repo.load()).placements)await repo.removePlacement(p.id);assert.equal((await repo.load()).assets.length,1);});
  await check('remove unused asset returns distinct media after commit',async()=>{const paths=await repo.removeAsset('asset1');assert.equal(new Set(paths).size,4);assert.equal((await repo.load()).assets.length,0);assert.ok(documents.has(paths[0]));});
  reset();repo=new LocalStickerRepository({filesDir:'/app'});documents.set('/app/journal.json',Buffer.from(JSON.stringify(old)));documents.set('/app/stickers/old.png',png);
  await check('migration keeps exact old bytes and rerun does not append',async()=>{const bytes=documents.get('/app/journal.json').toString();const one=await repo.load(),two=await repo.load();assert.deepEqual(one,two);assert.equal(documents.get('/app/journal.json').toString(),bytes);});
  await check('legacy deletion preserves old PNG recovery reference',async()=>{let s=await repo.load();for(const p of s.placements)await repo.removePlacement(p.id);assert.deepEqual(await repo.removeAsset(s.assets[0].id),[]);assert.ok(documents.has('/app/stickers/old.png'));});
  reset();repo=new LocalStickerRepository({filesDir:'/app'});documents.set('/app/journal.json',Buffer.from('{bad'));
  await check('bad legacy never creates empty replacement',async()=>{await assert.rejects(()=>repo.load());assert.equal(documents.has('/app/sticker-store.json'),false);assert.equal(documents.get('/app/journal.json').toString(),'{bad');});
  reset();repo=new LocalStickerRepository({filesDir:'/app'});documents.set('/app/sticker-store.json',Buffer.from('{bad'));
  await check('bad new index cannot be overwritten by save',async()=>rejectsPreserved(repo,()=>repo.saveAsset(asset(),revision(),undefined)));
  reset();repo=new LocalStickerRepository({filesDir:'/app'});documents.set('/app/stickers/asset1/raw.mask',Buffer.alloc(3));
  await check('wrong mask size rejects save',async()=>{await assert.rejects(()=>repo.saveAsset(asset(),revision(),undefined));assert.equal(documents.has('/app/sticker-store.json'),false);});
  reset();repo=new LocalStickerRepository({filesDir:'/app'});links.add('/app/stickers/asset1');
  await check('symlink asset folder rejected',async()=>{await assert.rejects(()=>repo.saveAsset(asset(),revision(),undefined));assert.equal(documents.has('/app/sticker-store.json'),false);});
  reset();repo=new LocalStickerRepository({filesDir:'/app'});documents.set('/app/stickers/asset1/rev1.png',Buffer.from('not PNG'));
  await check('wrong image format rejected',async()=>{await assert.rejects(()=>repo.saveAsset(asset(),revision(),undefined));assert.equal(documents.has('/app/sticker-store.json'),false);});
  console.log(`${count} behavior checks passed; source-transpiled logic with in-memory file API, not device storage QA.`);
})().catch(e=>{console.error(e);process.exitCode=1;});
