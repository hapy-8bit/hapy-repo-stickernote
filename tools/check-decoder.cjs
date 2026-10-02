// Execute the real Decoder + Raster sources with an in-memory SDK substitute.
// These checks cover channel/alpha contracts, not device SDK or camera acceptance.
// An optional first argument supplies an older Decoder source for regression comparison;
// relative imports still resolve against the real project's media directory.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/typescript');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');
const decoderFile = path.join(sourceRoot, 'media/StickerPhotoDecoder.ets');
const alternateDecoder = process.argv[2] ? path.resolve(process.argv[2]) : undefined;
const PixelMapFormat = { RGBA_8888: 3 };
const AlphaType = { OPAQUE: 1, PREMUL: 2, UNPREMUL: 3 };
let fixture;

function makeFixture(premultiplied, extraBytes = 0) {
  const width = 6, height = 4;
  const colors = premultiplied ?
    [[64, 16, 8, 128], [4, 32, 64, 128], [20, 4, 12, 85], [2, 8, 25, 85]] :
    [[224, 32, 18, 255], [11, 88, 201, 255], [171, 53, 29, 255], [7, 44, 233, 255]];
  const rgba = new Uint8Array(width * height * 4);
  const mask = new Int32Array(width * height);
  for (let i = 0; i < mask.length; i++) {
    rgba.set(colors[i % colors.length], i * 4);
    mask[i] = [255, 200, 128, 64][i % 4];
  }
  mask[mask.length - 1] = 0;
  const colorSpace = Object.freeze({ getColorSpaceName: () => 3, description: 'Display P3' });
  const data = {
    width, height, rgba, mask, colorSpace, premultiplied,
    nativeBytes: rgba.length + extraBytes,
    counts: { open: 0, close: 0, sourceRelease: 0, pixelRelease: 0,
      foregroundRelease: 0, init: 0, visionRelease: 0 },
    handles: new Set(), logs: [], failRead: false, failSegment: false
  };
  data.foreground = { release: async () => { data.counts.foregroundRelease++; } };
  data.pixelMap = {
    getImageInfo: async () => ({ size: { width, height }, pixelFormat: PixelMapFormat.RGBA_8888,
      alphaType: premultiplied ? AlphaType.PREMUL : AlphaType.OPAQUE }),
    getPixelBytesNumber: () => data.nativeBytes,
    getColorSpace: () => colorSpace,
    // The full-buffer API preserves actual RGBA bytes and source alpha type. The native
    // allocation may be larger, while the SDK copies dense logical rows into its front.
    readPixelsToBuffer: async (buffer) => {
      if (data.failRead) throw Object.assign(new Error('private SDK detail'), { code: 62980101 });
      assert.ok(buffer.byteLength >= data.nativeBytes, 'SDK requires its native allocation size');
      const destination = new Uint8Array(buffer);
      destination.fill(0xA5);
      destination.set(rgba);
    },
    // PositionArea conversion follows the official native contract: BGRA + UNPREMUL,
    // regardless of the PixelMap's RGBA/PREMUL declaration. This catches the old bug
    // by the resulting colors, rather than checking which method the source calls.
    readPixels: async (area) => {
      if (data.failRead) throw Object.assign(new Error('private SDK detail'), { code: 62980101 });
      const destination = new Uint8Array(area.pixels);
      const region = area.region;
      for (let y = 0; y < region.size.height; y++) for (let x = 0; x < region.size.width; x++) {
        const input = ((y + region.y) * width + x + region.x) * 4;
        const output = area.offset + y * area.stride + x * 4;
        const alpha = rgba[input + 3];
        const straight = (channel) => premultiplied && alpha > 0 ?
          Math.min(255, Math.round(rgba[input + channel] * 255 / alpha)) : rgba[input + channel];
        destination.set([straight(2), straight(1), straight(0), alpha], output);
      }
    },
    release: async () => { data.counts.pixelRelease++; },
    rotate: async () => { throw new Error('This fixture intentionally has Top-left EXIF'); },
    flip: async () => { throw new Error('This fixture intentionally has Top-left EXIF'); }
  };
  return data;
}

const kits = {
  '@kit.CoreFileKit': { fileIo: {
    OpenMode: { READ_ONLY: 1, NOFOLLOW: 2 },
    open: async () => { const fd = ++fixture.counts.open; fixture.handles.add(fd); return { fd }; },
    close: async (handle) => {
      assert.ok(fixture.handles.delete(handle.fd), 'each open file must close once'); fixture.counts.close++;
    }
  } },
  '@kit.ImageKit': { image: {
    PixelMapFormat, AlphaType, DecodingDynamicRange: { SDR: 0 }, PropertyKey: { ORIENTATION: 'Orientation' },
    createImageSource: (fd) => {
      assert.ok(fixture.handles.has(fd));
      const data = fixture;
      return {
        getImageInfo: async () => ({ size: { width: data.width, height: data.height } }),
        getImageProperty: async () => 'Top-left',
        createPixelMap: async () => data.pixelMap,
        release: async () => { data.counts.sourceRelease++; }
      };
    }
  } },
  '@kit.ArkGraphics2D': { colorSpaceManager: {} },
  '@kit.BasicServicesKit': {},
  '@kit.PerformanceAnalysisKit': { hilog: {
    info: (...args) => { fixture.logs.push(args); }, warn: (...args) => { fixture.logs.push(args); }
  } },
  '@kit.CoreVisionKit': { subjectSegmentation: {
    init: async () => { fixture.counts.init++; return true; },
    doSegmentation: async ({ pixelMap }) => {
      assert.equal(pixelMap, fixture.pixelMap);
      if (fixture.failSegment) throw Object.assign(new Error('private vision detail'), { code: 1011000002 });
      const left = new Int32Array(fixture.mask.length), right = new Int32Array(fixture.mask.length);
      for (let i = 0; i < left.length; i++) (i % fixture.width < 3 ? left : right)[i] = fixture.mask[i];
      // Shared foreground references test identity-based native resource cleanup.
      const subject = (mattingList) => ({ mattingList, foregroundImage: fixture.foreground,
        subjectRectangle: { left: 0, top: 0, width: fixture.width, height: fixture.height } });
      return { subjectCount: 2, fullSubject: subject(fixture.mask), subjectDetails: [subject(left), subject(right)] };
    },
    release: async () => { fixture.counts.visionRelease++; }
  } }
};

const cache = new Map();
function load(file) {
  file = path.resolve(file); if (!file.endsWith('.ets')) file += '.ets';
  if (cache.has(file)) return cache.get(file).exports;
  const actualFile = file === decoderFile && alternateDecoder ? alternateDecoder : file;
  const compiled = ts.transpileModule(fs.readFileSync(actualFile, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 }, reportDiagnostics: true
  });
  assert.equal(compiled.diagnostics?.length ?? 0, 0, 'real source must transpile');
  const mod = { exports: {} }; cache.set(file, mod);
  const requireHere = (name) => {
    if (Object.hasOwn(kits, name)) return kits[name];
    if (!name.startsWith('.')) throw new Error(`Unsupported SDK dependency: ${name}`);
    return load(path.resolve(path.dirname(file), name));
  };
  new Function('require', 'module', 'exports', 'canIUse', compiled.outputText)(requireHere, mod, mod.exports, () => true);
  return mod.exports;
}

const { StickerPhotoDecoder } = load(decoderFile);
const { makeStickerRaster } = load(path.join(sourceRoot, 'media/StickerRaster.ets'));
const { StickerFactory } = load(path.join(sourceRoot, 'domain/StickerFactory.ets'));
let checks = 0;
async function check(name, work) { await work(); checks++; console.log(`PASS ${name}`); }

function assertReleased(visionStarted) {
  assert.equal(fixture.counts.open, 1); assert.equal(fixture.counts.close, 1);
  assert.equal(fixture.handles.size, 0);
  assert.equal(fixture.counts.pixelRelease, 1); assert.equal(fixture.counts.sourceRelease, 1);
  assert.equal(fixture.counts.init, visionStarted ? 1 : 0);
  assert.equal(fixture.counts.visionRelease, visionStarted ? 1 : 0);
}

function assertRenderedColors(decoded, mode, borderWidth) {
  const recipe = { ...StickerFactory.defaultRecipe(mode), borderWidth };
  const raster = makeStickerRaster(decoded.pixels, decoded.fullMask.buffer,
    decoded.width, decoded.height, decoded.premultiplied, recipe);
  const pixels = new Uint8Array(raster.pixels), padding = borderWidth + 2;
  for (let index = 0; index < fixture.mask.length; index++) {
    const originalAlpha = fixture.rgba[index * 4 + 3];
    const alpha = mode === 'subject' ? Math.round(fixture.mask[index] * originalAlpha / 255) : originalAlpha;
    // The only zero mask is bottom-right, so trimming preserves the full fixture bbox.
    if (alpha === 0 && borderWidth > 0) continue;
    const expected = [0, 1, 2].map((channel) => alpha === 0 ? 0 : fixture.premultiplied ?
      Math.min(255, Math.round(fixture.rgba[index * 4 + channel] * 255 / originalAlpha)) :
      fixture.rgba[index * 4 + channel]);
    expected.push(alpha);
    const offset = ((Math.floor(index / fixture.width) + padding) * raster.width + index % fixture.width + padding) * 4;
    assert.deepEqual(Array.from(pixels.slice(offset, offset + 4)), expected,
      `${mode} border=${borderWidth}: source pixel ${index} must retain red/blue order and one alpha conversion`);
  }
}

(async () => {
  for (const premultiplied of [false, true]) for (const extraBytes of [0, 32]) {
    await check(`${premultiplied ? 'PREMUL' : 'OPAQUE'} decode/render preserves RGB, alpha, P3 and SDK ownership${extraBytes ? ' with larger native allocation' : ''}`, async () => {
      fixture = makeFixture(premultiplied, extraBytes);
      const decoded = await new StickerPhotoDecoder().decode('/private/sample.source', true);
      assert.equal(decoded.width, fixture.width); assert.equal(decoded.height, fixture.height);
      assert.equal(decoded.pixels.byteLength, fixture.rgba.length, 'native padding must not enter the logical raster');
      assert.deepEqual(Array.from(new Uint8Array(decoded.pixels)), Array.from(fixture.rgba));
      assert.equal(decoded.premultiplied, premultiplied);
      assert.equal(decoded.colorSpace, fixture.colorSpace, 'Display P3 metadata must survive as the original reference');
      assert.deepEqual(Array.from(decoded.fullMask), Array.from(fixture.mask));
      assertRenderedColors(decoded, 'original', 0);
      assertRenderedColors(decoded, 'subject', 0);
      assertRenderedColors(decoded, 'subject', 8);
      assertReleased(true); assert.equal(fixture.counts.foregroundRelease, 1);
    });
  }
  await check('undersized native allocation fails safely and releases SDK resources', async () => {
    fixture = makeFixture(false); fixture.nativeBytes = fixture.rgba.length - 1;
    await assert.rejects(() => new StickerPhotoDecoder().decode('/private/sample.source', true)); assertReleased(false);
  });
  await check('oversized native allocation is rejected before reading and releases SDK resources', async () => {
    fixture = makeFixture(false); fixture.nativeBytes = 16 * 1024 * 1024 + 1;
    await assert.rejects(() => new StickerPhotoDecoder().decode('/private/sample.source', true)); assertReleased(false);
  });
  await check('pixel-read failure releases ImageSource, PixelMap and file', async () => {
    fixture = makeFixture(true); fixture.failRead = true;
    await assert.rejects(() => new StickerPhotoDecoder().decode('/private/sample.source', true)); assertReleased(false);
  });
  await check('vision failure keeps original colors and releases initialized engine', async () => {
    fixture = makeFixture(true); fixture.failSegment = true;
    const decoded = await new StickerPhotoDecoder().decode('/private/sample.source', true);
    assert.equal(decoded.fullMask.length, 0); assert.ok(decoded.warning.length > 0);
    assert.equal(decoded.colorSpace, fixture.colorSpace); assertRenderedColors(decoded, 'original', 0);
    assertReleased(true);
    assert.ok(fixture.logs.every((args) => !args.join(' ').includes('/private/sample.source') &&
      !args.join(' ').includes('private vision detail')), 'diagnostic logs must exclude path and native message');
  });
  console.log(`${checks} decoder integration checks passed (in-memory SDK substitute; not device SDK testing).`);
})().catch((error) => { console.error(error); process.exitCode = 1; });
