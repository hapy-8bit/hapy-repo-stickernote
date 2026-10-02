import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/** Camera output is a draft. Ownership transfers to the caller only after an atomic write. */
export class CameraPhotoFiles {
  private readonly directory: string;

  constructor(filesDir: string) { this.directory = `${filesDir}/stickers`; }

  async saveJpeg(bytes: ArrayBuffer): Promise<string> {
    if (bytes.byteLength < 4) { throw new Error('相机没有返回完整照片，请重拍。'); }
    if (!fileIo.accessSync(this.directory)) { await fileIo.mkdir(this.directory); }
    const directoryStat = await fileIo.lstat(this.directory);
    if (!directoryStat.isDirectory() || directoryStat.isSymbolicLink()) {
      throw new Error('照片保存目录不可用。');
    }
    const destination = `${this.directory}/photo-${util.generateRandomUUID(false).toLowerCase()}.jpg`;
    const partial = `${destination}.partial`;
    let handle: fileIo.File | undefined = undefined;
    let complete = false;
    try {
      handle = await fileIo.open(partial,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.NOFOLLOW);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const count = await fileIo.write(handle.fd, bytes.slice(offset));
        if (count <= 0) { throw new Error('照片未能完整写入，请重拍。'); }
        offset += count;
      }
      await fileIo.fsync(handle.fd);
      await fileIo.close(handle);
      handle = undefined;
      await fileIo.rename(partial, destination);
      complete = true;
      return destination;
    } finally {
      if (handle !== undefined) { try { await fileIo.close(handle); } catch (_) {} }
      if (!complete && fileIo.accessSync(partial)) { try { await fileIo.unlink(partial); } catch (_) {} }
    }
  }

  async discard(path: string): Promise<void> {
    const prefix = `${this.directory}/`;
    if (!path.startsWith(prefix) ||
      !/^photo-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$/.test(path.slice(prefix.length))) {
      throw new Error('只能清理当前应用的相机草稿。');
    }
    if (!fileIo.accessSync(path)) { return; }
    const stat = await fileIo.lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink()) { throw new Error('相机草稿路径无效。'); }
    await fileIo.unlink(path);
  }
}
