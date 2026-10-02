import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export interface StickerStorageUsage { sourceBytes: number; renderedBytes: number; maskBytes: number; }

/** 这里只拥有私有图片文件。仓库提交前仅可清理当前草稿，提交后才可删无引用资产。 */
export class StickerMediaFiles {
  readonly directory: string;

  constructor(filesDir: string) { this.directory = `${filesDir}/stickers`; }

  private ensureDirectory(path: string): void {
    if (!fs.accessSync(path)) fs.mkdirSync(path);
    const stat: fs.Stat = fs.lstatSync(path);
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error('贴纸目录不可用。');
  }

  assetDirectory(id: string): string {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(id)) throw new Error('贴纸标识无效。');
    this.ensureDirectory(this.directory);
    const folder: string = `${this.directory}/${id}`;
    this.ensureDirectory(folder);
    return folder;
  }

  private verifyPath(path: string): void {
    if (!path.startsWith(`${this.directory}/`)) throw new Error('图片必须位于本应用私有目录。');
    const relative: string = path.slice(this.directory.length + 1);
    if (!/^[A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)?\.(?:source|mask|png|jpg|jpeg)$/.test(relative)) {
      throw new Error('私有图片路径无效。');
    }
    this.ensureDirectory(this.directory);
    const parts: string[] = relative.split('/');
    if (parts.length === 2) this.ensureDirectory(`${this.directory}/${parts[0]}`);
  }

  async save(path: string, data: ArrayBuffer): Promise<void> {
    this.verifyPath(path);
    if (data.byteLength === 0 || fs.accessSync(path)) throw new Error('图片未完成或保存目标已存在。');
    const temporary: string = `${path}.partial-${util.generateRandomUUID()}`;
    let file: fs.File | undefined = undefined;
    let committed: boolean = false;
    try {
      file = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW);
      let offset: number = 0;
      while (offset < data.byteLength) {
        const count: number = await fs.write(file.fd, data.slice(offset));
        if (count <= 0) throw new Error('图片写入未完成。');
        offset += count;
      }
      await fs.fsync(file.fd); await fs.close(file); file = undefined;
      await fs.rename(temporary, path); committed = true;
    } finally {
      if (file !== undefined) { try { await fs.close(file); } catch (_) {} }
      if (!committed) { try { await fs.unlink(temporary); } catch (_) {} }
    }
  }

  /** 先复制原始字节；相册/相机临时 URI 永远不会进入持久化领域对象。 */
  async copySource(uri: string, destination: string): Promise<void> {
    this.verifyPath(destination);
    if (fs.accessSync(destination)) throw new Error('原图保存目标已存在。');
    const temporary: string = `${destination}.partial-${util.generateRandomUUID()}`;
    let source: fs.File | undefined = undefined;
    let target: fs.File | undefined = undefined;
    let committed: boolean = false;
    try {
      source = await fs.open(uri, fs.OpenMode.READ_ONLY);
      const stat: fs.Stat = await fs.stat(source.fd);
      if (stat.size < 1 || stat.size > 100 * 1024 * 1024) throw new Error('请选择小于 100 MB 的照片。');
      target = await fs.open(temporary, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.NOFOLLOW);
      await fs.copyFile(source.fd, target.fd);
      await fs.fsync(target.fd); await fs.close(target); target = undefined;
      await fs.rename(temporary, destination); committed = true;
    } finally {
      if (source !== undefined) { try { await fs.close(source); } catch (_) {} }
      if (target !== undefined) { try { await fs.close(target); } catch (_) {} }
      if (!committed) { try { await fs.unlink(temporary); } catch (_) {} }
    }
  }

  async read(path: string): Promise<ArrayBuffer> {
    this.verifyPath(path);
    const stat: fs.Stat = fs.lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > 100 * 1024 * 1024) throw new Error('本机图片文件不可用。');
    const file: fs.File = await fs.open(path, fs.OpenMode.READ_ONLY | fs.OpenMode.NOFOLLOW);
    try {
      const result: Uint8Array = new Uint8Array(stat.size);
      let offset: number = 0;
      while (offset < result.length) {
        const chunk: ArrayBuffer = new ArrayBuffer(Math.min(65536, result.length - offset));
        const count: number = await fs.read(file.fd, chunk);
        if (count < 1) throw new Error('本机图片文件不完整。');
        result.set(new Uint8Array(chunk, 0, count), offset); offset += count;
      }
      return result.buffer as ArrayBuffer;
    } finally { await fs.close(file); }
  }

  async discard(path: string): Promise<void> {
    this.verifyPath(path);
    if (!fs.accessSync(path)) return;
    const stat: fs.Stat = fs.lstatSync(path);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('图片文件不可删除。');
    await fs.unlink(path);
  }

  async discardCapture(path: string): Promise<void> {
    if (!/^photo-[0-9a-f-]{36}\.jpg$/i.test(path.slice(this.directory.length + 1))) {
      throw new Error('不是本次相机的临时照片。');
    }
    await this.discard(path);
  }

  async usage(): Promise<StickerStorageUsage> {
    const result: StickerStorageUsage = { sourceBytes: 0, renderedBytes: 0, maskBytes: 0 };
    if (!fs.accessSync(this.directory)) return result;
    this.ensureDirectory(this.directory);
    const names: string[] = fs.listFileSync(this.directory);
    for (const name of names) {
      if (!/^[A-Za-z0-9_.-]+$/.test(name)) continue;
      const path: string = `${this.directory}/${name}`;
      const stat: fs.Stat = await fs.lstat(path);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) {
        for (const child of fs.listFileSync(path)) {
          if (!/^[A-Za-z0-9_.-]+$/.test(child)) continue;
          await this.addUsage(`${path}/${child}`, child, result);
        }
      } else await this.addUsage(path, name, result);
    }
    return result;
  }

  private async addUsage(path: string, name: string, usage: StickerStorageUsage): Promise<void> {
    const stat: fs.Stat = await fs.lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink()) return;
    if (name.endsWith('.source')) usage.sourceBytes += stat.size;
    else if (name.endsWith('.mask')) usage.maskBytes += stat.size;
    else if (name.endsWith('.png') || name.endsWith('.jpg')) usage.renderedBytes += stat.size;
  }
}
