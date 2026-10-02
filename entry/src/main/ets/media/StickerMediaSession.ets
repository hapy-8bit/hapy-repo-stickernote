import { image } from '@kit.ImageKit';
import { taskpool } from '@kit.ArkTS';
import { StickerAsset, StickerRecipe, StickerRevision } from '../domain/StickerModels';
import { StickerFactory } from '../domain/StickerFactory';
import { StickerMediaFiles } from './StickerMediaFiles';
import { StickerPhotoDecoder, DecodedStickerPhoto } from './StickerPhotoDecoder';
import { StickerRaster } from './StickerRaster';
import { renderStickerTask } from './StickerRenderTask';

/** 草稿拥有新文件；提交转移所有权给仓库，取消只删除自己创建的文件。 */
export class StickerMediaSession {
  asset: StickerAsset;
  revision: StickerRevision;
  readonly isNew: boolean;
  private readonly files: StickerMediaFiles;
  private decoded: DecodedStickerPhoto;
  private ownedPaths: string[] = [];
  private committed: boolean = false;
  private closed: boolean = false;
  private generation: number = 0;

  private constructor(files: StickerMediaFiles, asset: StickerAsset, revision: StickerRevision,
    decoded: DecodedStickerPhoto, isNew: boolean) {
    this.files = files; this.asset = asset; this.revision = revision;
    this.decoded = decoded; this.isNew = isNew;
  }

  get subjectCount(): number { return this.decoded.subjects.length; }
  get sourceWidth(): number { return this.decoded.width; }
  get sourceHeight(): number { return this.decoded.height; }
  get canRemake(): boolean { return this.asset.sourceType !== 'legacy' && this.decoded.fullMask.length > 0; }
  get warning(): string { return this.asset.sourceType === 'legacy' ? '旧贴纸只有成品，可裁切和调整方向；无法恢复已丢失的原图或白边。' : this.decoded.warning; }

  static async create(files: StickerMediaFiles, uri: string, kind: string): Promise<StickerMediaSession> {
    const id: string = StickerFactory.newId();
    const path: string = `${files.assetDirectory(id)}/source.source`;
    await files.copySource(uri, path);
    let session: StickerMediaSession | undefined = undefined;
    try {
      const decoded: DecodedStickerPhoto = await new StickerPhotoDecoder().decode(path, true);
      const asset: StickerAsset = StickerFactory.createAsset(id, path, kind, decoded.width, decoded.height);
      const recipe: StickerRecipe = StickerFactory.defaultRecipe(decoded.fullMask.length > 0 ? 'subject' : 'original');
      const revision: StickerRevision = StickerFactory.createRevision(StickerFactory.newId('revision'), id, '', '', 0, 0, recipe);
      session = new StickerMediaSession(files, asset, revision, decoded, true);
      session.ownedPaths.push(path);
      await session.render(recipe);
      return session;
    } catch (error) {
      if (session !== undefined) await session.cancel();
      else { try { await files.discard(path); } catch (_) {} }
      throw new Error((error as Error).message || '照片无法制作，请重新选择。');
    }
  }

  static async reopen(files: StickerMediaFiles, asset: StickerAsset,
    revision: StickerRevision): Promise<StickerMediaSession> {
    const legacy: boolean = asset.sourcePath.length === 0;
    const decoded: DecodedStickerPhoto = await new StickerPhotoDecoder().decode(legacy ? revision.imagePath : asset.sourcePath, !legacy);
    const recipe: StickerRecipe = legacy ? StickerFactory.defaultRecipe('original') : StickerFactory.copyRecipe(revision.recipe);
    if (!legacy && revision.maskPath.length > 0 && (asset.width !== decoded.width || asset.height !== decoded.height)) {
      decoded.warning = '原蒙版坐标与当前处理尺寸不同，本次重新识别；历史成品保持不变。';
    }
    if (!legacy && revision.maskPath.length > 0 && asset.width === decoded.width && asset.height === decoded.height) {
      try {
        const mask: Uint8Array = new Uint8Array(await files.read(revision.maskPath));
        if (mask.length === decoded.width * decoded.height) {
          if (recipe.subjectIndex < 0) decoded.fullMask = mask;
          else if (recipe.subjectIndex < decoded.subjects.length) decoded.subjects[recipe.subjectIndex] = mask;
          else { decoded.fullMask = mask; decoded.subjects = [mask]; recipe.subjectIndex = -1; }
        }
      } catch (_) { decoded.warning = '原蒙版无法读取；本次按重新识别的结果制作，旧成品仍然保留。'; }
    }
    if (recipe.mode === 'subject' && decoded.fullMask.length === 0) {
      recipe.mode = 'original'; recipe.borderWidth = 0;
      decoded.warning = '当前无法重做主体，保留完整照片；旧贴纸不会被覆盖。';
    }
    const initial: StickerRevision = StickerFactory.createRevision(revision.id, revision.assetId, revision.maskPath,
      revision.imagePath, revision.width, revision.height, recipe, revision.createdAt);
    const session: StickerMediaSession = new StickerMediaSession(files, asset, initial, decoded, false);
    try { await session.render(recipe); return session; }
    catch (error) { await session.cancel(); throw new Error((error as Error).message || '贴纸无法重新制作。'); }
  }

  async render(recipe: StickerRecipe): Promise<StickerRevision> {
    if (this.committed || this.closed) throw new Error('已结束的编辑会话不能继续修改。');
    const generation: number = this.generation;
    const nextRecipe: StickerRecipe = StickerFactory.copyRecipe(recipe);
    if (this.asset.sourceType === 'legacy') nextRecipe.mode = 'original';
    let mask: Uint8Array = new Uint8Array(0);
    if (nextRecipe.mode === 'subject') {
      mask = nextRecipe.subjectIndex < 0 ? this.decoded.fullMask : this.decoded.subjects[nextRecipe.subjectIndex];
      if (mask === undefined || mask.length === 0) throw new Error('没有可用主体，请保留照片或重拍。');
    }
    const task: taskpool.Task = new taskpool.Task(renderStickerTask, this.decoded.pixels,
      mask.buffer as ArrayBuffer, this.decoded.width, this.decoded.height, this.decoded.premultiplied, nextRecipe);
    // 输入是会话母版，显式禁止 transfer，避免第一次预览后原像素被 detach。
    task.setTransferList([]);
    const raster: StickerRaster = await taskpool.execute(task) as StickerRaster;
    if (this.closed || generation !== this.generation) throw new Error('本次编辑已经取消。');
    const id: string = StickerFactory.newId('revision');
    const folder: string = this.files.assetDirectory(this.asset.id);
    const imagePath: string = `${folder}/${id}.png`;
    const maskPath: string = nextRecipe.mode === 'subject' ? `${folder}/${id}.mask` : '';
    const newPaths: string[] = [];
    try {
      await this.encode(raster, imagePath); newPaths.push(imagePath);
      if (maskPath.length > 0) { await this.files.save(maskPath, mask.buffer.slice(mask.byteOffset, mask.byteOffset + mask.byteLength)); newPaths.push(maskPath); }
      if (this.closed || generation !== this.generation) throw new Error('本次编辑已经取消。');
    } catch (error) {
      for (const path of newPaths) { try { await this.files.discard(path); } catch (_) { this.ownedPaths.push(path); } }
      throw new Error((error as Error).message || '贴纸预览保存失败。');
    }
    for (const path of newPaths) this.ownedPaths.push(path);
    const previous: StickerRevision = this.revision;
    this.revision = StickerFactory.createRevision(id, this.asset.id, maskPath, imagePath,
      raster.width, raster.height, nextRecipe);
    // 仅回收此草稿先前的预览；仓库中的旧版本从来不在 ownedPaths 里。
    for (const path of [previous.imagePath, previous.maskPath]) {
      if (this.ownedPaths.includes(path)) {
        try { await this.files.discard(path); this.ownedPaths = this.ownedPaths.filter((item: string): boolean => item !== path); } catch (_) {}
      }
    }
    return this.revision;
  }

  private async encode(raster: StickerRaster, path: string): Promise<void> {
    const pixels: image.PixelMap = await image.createPixelMap(raster.pixels, {
      size: { width: raster.width, height: raster.height }, editable: false,
      pixelFormat: image.PixelMapFormat.RGBA_8888, srcPixelFormat: image.PixelMapFormat.RGBA_8888,
      alphaType: image.AlphaType.UNPREMUL });
    let packer: image.ImagePacker | undefined = undefined;
    try {
      // Pixels still use the source's decoded SDR color space. Restoring that metadata
      // does not recolor them; treating Display P3 bytes as default sRGB would.
      pixels.setColorSpace(this.decoded.colorSpace);
      packer = image.createImagePacker();
      await this.files.save(path, await packer.packing(pixels, { format: 'image/png', quality: 100 }));
    } finally {
      if (packer !== undefined) { try { await packer.release(); } catch (_) {} }
      try { await pixels.release(); } catch (_) {}
    }
  }

  async markCommitted(): Promise<boolean> {
    // 只有本次入库版本与源图转移所有权；失败的预览/旧草稿仍须清理。
    this.committed = true;
    const retained: string[] = [this.asset.sourcePath, this.revision.imagePath, this.revision.maskPath];
    const unused: string[] = this.ownedPaths.filter((path: string): boolean => !retained.includes(path));
    this.ownedPaths = [];
    let cleaned: boolean = true;
    for (const path of unused) { try { await this.files.discard(path); } catch (_) { cleaned = false; } }
    this.decoded.pixels = new ArrayBuffer(0); this.decoded.subjects = []; this.decoded.fullMask = new Uint8Array(0);
    return cleaned;
  }

  async cancel(): Promise<void> {
    if (this.committed) return;
    this.closed = true; this.generation++;
    const failed: string[] = [];
    for (const path of this.ownedPaths) { try { await this.files.discard(path); } catch (_) { failed.push(path); } }
    this.ownedPaths = failed;
    if (failed.length > 0) throw new Error('草稿文件清理未完成，请重试；已保存贴纸没有改动。');
    this.decoded.pixels = new ArrayBuffer(0); this.decoded.subjects = []; this.decoded.fullMask = new Uint8Array(0);
  }
}
