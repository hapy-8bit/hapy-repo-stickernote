// 本机签名装配：显式提供签名来源，不复用其他 App 的 Profile，也不打印密码。
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const JSON5 = require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor-ohos-plugin/node_modules/json5');
const root = path.resolve(__dirname, '..');
const args = process.argv.slice(2);
function option(name) { const index = args.indexOf(name); return index < 0 ? undefined : args[index + 1]; }
function fail(message) { console.error(message); process.exit(1); }
const input = option('--profile');
const sourceInput = option('--source-signing');
if (!input || !sourceInput) fail('用法：node tools/configure-signing.cjs --profile /绝对路径/StickerNoteDebug.p7b --source-signing /绝对路径/独立签名来源配置.json5');
const profile = path.resolve(input);
const sourceFile = path.resolve(sourceInput);

try {
  const app = JSON5.parse(fs.readFileSync(path.join(root, 'AppScope/app.json5'), 'utf8')).app;
  const source = JSON5.parse(fs.readFileSync(sourceFile, 'utf8'));
  const product = source.app.products.find((item) => item.name === 'default');
  const signing = source.app.signingConfigs.find((item) => item.name === product?.signingConfig);
  if (!signing?.material) fail('来源工程没有可用调试签名配置；请在 DevEco 配置与 Profile 配对的私钥。');
  const payload = JSON.parse(cp.execFileSync('/usr/bin/openssl',
    ['cms', '-verify', '-inform', 'DER', '-in', profile, '-noverify'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
  // OpenSSL 校验 CMS 内容签名；系统安装仍负责华为链信任和 Profile 授权校验。
  const bundle = payload['bundle-info'];
  if (payload.type !== 'debug' || bundle?.['bundle-name'] !== app.bundleName) fail('Profile 类型或包名不匹配 StickerNote。');
  if (bundle['app-identifier'] !== '6917617717737387696') fail('Profile App Identifier 与提供的 AppID 不匹配。');
  const expires = payload.validity?.['not-after'];
  if (!Number.isFinite(expires) || expires * 1000 <= Date.now()) fail('Profile 已过期或有效期无效。');
  const expectedCert = new crypto.X509Certificate(fs.readFileSync(signing.material.certpath));
  const actualCert = new crypto.X509Certificate(bundle['development-certificate']);
  if (expectedCert.fingerprint256 !== actualCert.fingerprint256) fail('Profile 证书与本机签名证书不匹配，请选择与本机密钥配对的调试证书。');
  const hdc = '/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc';
  const response = cp.execFileSync(hdc, ['-t', '2UCUT23C27028737', 'shell', 'bm', 'get', '-u'],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const match = response.match(/[A-Fa-f0-9]{64,}/);
  const devices = payload['debug-info']?.['device-ids'];
  if (!match || !Array.isArray(devices) || !devices.some((id) => id.toUpperCase() === match[0].toUpperCase())) {
    fail('Profile 未包含当前 USB nova 12，或未能核对设备 UDID。');
  }
  const destination = path.join(root, 'build-profile.json5');
  const config = JSON5.parse(fs.readFileSync(destination, 'utf8'));
  config.app.signingConfigs = [{ name: 'stickernote_debug', type: signing.type,
    material: { ...signing.material, profile } }];
  config.app.products.find((item) => item.name === 'default').signingConfig = 'stickernote_debug';
  fs.writeFileSync(destination, JSON.stringify(config, null, 2) + '\n', { mode: 0o600 });
  fs.chmodSync(destination, 0o600);
  console.log('Profile、包名、AppID、调试证书与 nova 12 已匹配；本机签名配置已写入。');
} catch (_) {
  // 子进程 stderr 或配置对象可能含签名信息，不能直接打印错误对象。
  fail('未能完成签名核对；请检查 Profile、证书配对、DevEco 环境与 USB 设备连接。');
}
