import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { StickerAsset, StickerStore } from '../domain/StickerModels';
import { StickerCodec } from './StickerCodec';

/** 元数据仓库不创建/修改图片，只验证私有文件；清理图像由媒体层在提交后执行。 */
export class StickerLocalFiles {
  private readonly directory: string;

  constructor(directory: string) {
    this.directory = directory;
  }

  readOptional(path: string): string | undefined {
    const stat: fs.Stat | undefined = this.statOptional(path);
    if (stat === undefined) return undefined;
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('贴纸索引位置无效，原数据未改动。');
    try { return fs.readTextSync(path); } catch {
      throw new Error('无法读取贴纸索引，原数据未改动。');
    }
  }

  validate(store: StickerStore): void {
    const checked: Set<string> = new Set<string>();
    for (const asset of store.assets) {
      if (asset.sourcePath.length > 0) this.image(asset.sourcePath, 'source', checked);
    }
    for (const revision of store.revisions) {
      this.image(revision.imagePath, 'image', checked);
      if (revision.maskPath.length === 0) continue;
      if (revision.maskPath.endsWith('.png')) {
        this.image(revision.maskPath, 'mask', checked);
      } else {
        StickerCodec.filePath(revision.maskPath, this.directory, 'mask');
        const stat: fs.Stat = this.requireFile(revision.maskPath);
        const asset: StickerAsset | undefined = store.assets.find((item: StickerAsset): boolean => item.id === revision.assetId);
        if (asset === undefined || asset.width <= 0 || stat.size !== asset.width * asset.height) {
          throw new Error('主体蒙版与标准方向输入尺寸不一致，现有数据未改动。');
        }
      }
    }
  }

  writeAtomic(path: string, text: string): void {
    const temporaryPath: string = `${path}.pending-${util.generateRandomUUID()}`;
    let file: fs.File | undefined = undefined;
    let committed: boolean = false;
    try {
      file = fs.openSync(temporaryPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW);
      const bytes: Uint8Array = new util.TextEncoder().encodeInto(text);
      let offset: number = 0;
      while (offset < bytes.byteLength) {
        const part: ArrayBuffer = bytes.buffer.slice(bytes.byteOffset + offset, bytes.byteOffset + bytes.byteLength);
        const written: number = fs.writeSync(file.fd, part, { offset: offset });
        if (written <= 0) throw new Error('贴纸索引写入未完成。');
        offset += written;
      }
      fs.fsyncSync(file.fd);
      fs.closeSync(file);
      file = undefined;
      // 在原索引所在目录提交；不先删旧索引，也不修改 schema 1 的 journal.json。
      fs.renameSync(temporaryPath, path);
      committed = true;
    } catch {
      throw new Error('贴纸保存失败，原索引已保留，请稍后重试。');
    } finally {
      if (file !== undefined) {
        try { fs.closeSync(file); } catch { /* 关闭失败不能掩盖保存异常。 */ }
      }
      if (!committed) {
        try { fs.unlinkSync(temporaryPath); } catch { /* 只清理本次未提交文件。 */ }
      }
    }
  }

  private statOptional(path: string): fs.Stat | undefined {
    try { return fs.lstatSync(path); } catch (error) {
      const reason: BusinessError = error as BusinessError;
      if (reason.code === 13900002) return undefined;
      throw new Error('无法访问贴纸文件，现有数据未改动。');
    }
  }

  private requireFile(path: string): fs.Stat {
    const root: fs.Stat | undefined = this.statOptional(this.directory);
    if (root === undefined || !root.isDirectory() || root.isSymbolicLink()) {
      throw new Error('私有贴纸目录缺失或无效，现有数据未改动。');
    }
    const relative: string = path.slice(this.directory.length + 1);
    const parts: string[] = relative.split('/');
    if (parts.length === 2) {
      const parent: fs.Stat | undefined = this.statOptional(`${this.directory}/${parts[0]}`);
      if (parent === undefined || !parent.isDirectory() || parent.isSymbolicLink()) {
        throw new Error('私有资产目录缺失或无效，现有数据未改动。');
      }
    }
    const stat: fs.Stat | undefined = this.statOptional(path);
    if (stat === undefined || !stat.isFile() || stat.isSymbolicLink() || stat.size <= 0) {
      throw new Error('贴纸图片缺失或无效，现有数据未改动。');
    }
    return stat;
  }

  private image(path: string, kind: string, checked: Set<string>): void {
    StickerCodec.filePath(path, this.directory, kind);
    if (checked.has(path)) return;
    const stat: fs.Stat = this.requireFile(path);
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
      const buffer: ArrayBuffer = new ArrayBuffer(Math.min(64, stat.size));
      const length: number = fs.readSync(file.fd, buffer);
      const bytes: Uint8Array = new Uint8Array(buffer, 0, length);
      const png: boolean = bytes.length >= 8 && bytes[0] === 137 && bytes[1] === 80 && bytes[2] === 78 &&
        bytes[3] === 71 && bytes[4] === 13 && bytes[5] === 10 && bytes[6] === 26 && bytes[7] === 10;
      const jpeg: boolean = bytes.length >= 3 && bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
      const webp: boolean = bytes.length >= 12 && this.ascii(bytes, 0, 4) === 'RIFF' && this.ascii(bytes, 8, 12) === 'WEBP';
      const heif: boolean = bytes.length >= 16 && this.ascii(bytes, 4, 8) === 'ftyp' &&
        ['heic', 'heix', 'hevc', 'hevx', 'mif1', 'msf1', 'avif', 'avis'].includes(this.ascii(bytes, 8, 12));
      const source: boolean = path.endsWith('.source');
      const allowed: boolean = source ? png || jpeg || webp || heif : path.endsWith('.png') ? png : jpeg;
      if (!allowed) throw new Error('图像文件格式与路径不一致。');
    } catch {
      throw new Error('贴纸图像无法读取或格式无效，现有数据未改动。');
    } finally {
      if (file !== undefined) {
        try { fs.closeSync(file); } catch { /* 不掩盖原图读取异常。 */ }
      }
    }
    checked.add(path);
  }

  private ascii(bytes: Uint8Array, start: number, end: number): string {
    let value: string = '';
    for (let index: number = start; index < end && index < bytes.length; index++) value += String.fromCharCode(bytes[index]);
    return value;
  }
}
