import { common } from '@kit.AbilityKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { StickerAsset, StickerRevision } from '../domain/StickerModels';
import { StickerMediaFiles, StickerStorageUsage } from './StickerMediaFiles';
import { StickerMediaSession } from './StickerMediaSession';

/** 装配层依赖此入口；组件不接触临时 URI、图像 SDK 和私有文件。 */
export class StickerAcquisitionService {
  private readonly files: StickerMediaFiles;
  constructor(context: common.UIAbilityContext) { this.files = new StickerMediaFiles(context.filesDir); }

  async pick(): Promise<StickerMediaSession | undefined> {
    const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE; options.maxSelectNumber = 1;
    const result: photoAccessHelper.PhotoSelectResult = await new photoAccessHelper.PhotoViewPicker().select(options);
    if (result.photoUris.length === 0) return undefined;
    return await StickerMediaSession.create(this.files, result.photoUris[0], 'gallery');
  }

  async capture(path: string): Promise<StickerMediaSession> {
    try { return await StickerMediaSession.create(this.files, path, 'camera'); }
    finally { try { await this.files.discardCapture(path); } catch (_) { /* 临时照片清理失败不掩盖已导入图片。 */ } }
  }

  async reopen(asset: StickerAsset, revision: StickerRevision): Promise<StickerMediaSession> {
    return await StickerMediaSession.reopen(this.files, asset, revision);
  }

  async discardUnreferenced(paths: string[]): Promise<void> {
    for (const path of paths) await this.files.discard(path);
  }

  async usage(): Promise<StickerStorageUsage> { return await this.files.usage(); }
}
