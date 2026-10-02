import { DayPlacement, StickerAsset, StickerRecipe, StickerRevision, StickerStore } from '../domain/StickerModels';

/** 只在索引边界解析 JSON，重建所有对象；文件存在性由本机仓库验证。 */
export class StickerCodec {
  static decode(text: string, directory: string): StickerStore {
    let store: StickerStore;
    try { store = JSON.parse(text) as StickerStore; } catch {
      throw new Error('贴纸索引无法解析，原文件已保留。');
    }
    return StickerCodec.validate(store, directory);
  }

  static encode(store: StickerStore, directory: string): string {
    return JSON.stringify(StickerCodec.validate(store, directory));
  }

  static validate(store: StickerStore, directory: string): StickerStore {
    StickerCodec.object(store);
    if (store.schemaVersion !== 2) throw new Error('贴纸索引版本不支持，原文件已保留。');
    if (!Array.isArray(store.assets) || !Array.isArray(store.revisions) || !Array.isArray(store.placements)) {
      throw new Error('贴纸索引列表无效，原文件已保留。');
    }
    const categories: string[] = StickerCodec.categories(store.categories);
    const assets: StickerAsset[] = [];
    const revisions: StickerRevision[] = [];
    const placements: DayPlacement[] = [];
    const assetIds: Set<string> = new Set<string>();
    const revisionIds: Set<string> = new Set<string>();
    const placementIds: Set<string> = new Set<string>();
    for (const candidate of store.assets) {
      const asset: StickerAsset = StickerCodec.asset(candidate, directory, categories);
      StickerCodec.unique(assetIds, asset.id);
      assets.push(asset);
    }
    for (const candidate of store.revisions) {
      const revision: StickerRevision = StickerCodec.revision(candidate, directory);
      StickerCodec.unique(revisionIds, revision.id);
      const asset: StickerAsset | undefined = assets.find((item: StickerAsset): boolean => item.id === revision.assetId);
      if (asset === undefined) throw new Error('贴纸版本引用了不存在的资产。');
      if (asset.sourceType !== 'legacy' && (revision.width <= 0 || revision.height <= 0)) {
        throw new Error('新贴纸版本必须保存真实成品尺寸。');
      }
      if (asset.sourceType !== 'legacy' && revision.recipe.mode === 'subject' && revision.maskPath.length === 0) {
        throw new Error('去背景版本必须保留真实主体蒙版，不能只存成品。');
      }
      if (asset.sourceType === 'legacy' && revision.maskPath.length > 0) {
        throw new Error('旧贴纸没有原始蒙版，不能伪造重制数据。');
      }
      revisions.push(revision);
    }
    for (const candidate of store.placements) {
      const placement: DayPlacement = StickerCodec.placement(candidate);
      StickerCodec.unique(placementIds, placement.id);
      const revision: StickerRevision | undefined = revisions.find((item: StickerRevision): boolean => item.id === placement.revisionId);
      if (!assetIds.has(placement.assetId) || revision === undefined || revision.assetId !== placement.assetId) {
        throw new Error('每日摆放的资产和版本引用不一致。');
      }
      placements.push(placement);
    }
    for (const asset of assets) {
      if (!revisions.some((item: StickerRevision): boolean => item.assetId === asset.id)) {
        throw new Error('贴纸资产必须至少包含一个成品版本。');
      }
    }
    return { schemaVersion: 2, assets: assets, revisions: revisions, placements: placements, categories: categories };
  }

  static asset(asset: StickerAsset, directory: string, categories: string[]): StickerAsset {
    StickerCodec.object(asset);
    StickerCodec.id(asset.id);
    const legacy: boolean = asset.sourceType === 'legacy';
    if (!legacy && asset.sourceType !== 'camera' && asset.sourceType !== 'gallery') throw new Error('照片来源无效。');
    if (legacy) {
      if (asset.sourcePath !== '') throw new Error('旧贴纸不能伪造源图。');
    } else {
      StickerCodec.filePath(asset.sourcePath, directory, 'source');
    }
    StickerCodec.dimensions(asset.width, asset.height, legacy);
    StickerCodec.text(asset.title, 60, '标题');
    // 早期 schema 2 没有资产短注记；补空值即可，不能将每日使用注记反向覆盖资产。
    const note: string = asset.note === undefined ? '' : asset.note;
    StickerCodec.text(note, 2000, '备注');
    if (typeof asset.category !== 'string' || !categories.includes(asset.category)) throw new Error('贴纸分类不在分类列表中。');
    if (typeof asset.favorite !== 'boolean') throw new Error('收藏状态无效。');
    StickerCodec.timestamps(asset.createdAt, asset.updatedAt);
    return {
      id: asset.id, sourcePath: asset.sourcePath, sourceType: asset.sourceType, width: asset.width,
      height: asset.height, title: asset.title, note: note, category: asset.category, favorite: asset.favorite,
      createdAt: asset.createdAt, updatedAt: asset.updatedAt
    };
  }

  static revision(revision: StickerRevision, directory: string): StickerRevision {
    StickerCodec.object(revision);
    StickerCodec.id(revision.id);
    StickerCodec.id(revision.assetId);
    StickerCodec.filePath(revision.imagePath, directory, 'image');
    if (revision.maskPath !== '') StickerCodec.filePath(revision.maskPath, directory, 'mask');
    StickerCodec.dimensions(revision.width, revision.height, true);
    StickerCodec.timestamp(revision.createdAt);
    return {
      id: revision.id, assetId: revision.assetId, maskPath: revision.maskPath, imagePath: revision.imagePath,
      width: revision.width, height: revision.height, recipe: StickerCodec.recipe(revision.recipe), createdAt: revision.createdAt
    };
  }

  static recipe(recipe: StickerRecipe): StickerRecipe {
    StickerCodec.object(recipe);
    if (recipe.mode !== 'subject' && recipe.mode !== 'original') throw new Error('贴纸制作模式无效。');
    if (!Number.isFinite(recipe.borderWidth) || recipe.borderWidth < 0 || recipe.borderWidth > 128) throw new Error('白边宽度无效。');
    if (typeof recipe.borderColor !== 'string' || !/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(recipe.borderColor)) {
      throw new Error('白边颜色无效。');
    }
    StickerCodec.angle(recipe.rotation);
    if (typeof recipe.flipHorizontal !== 'boolean') throw new Error('翻转设置无效。');
    StickerCodec.unit(recipe.cropX);
    StickerCodec.unit(recipe.cropY);
    StickerCodec.unit(recipe.cropWidth);
    StickerCodec.unit(recipe.cropHeight);
    if (recipe.cropWidth <= 0 || recipe.cropHeight <= 0 || recipe.cropX + recipe.cropWidth > 1.000001 ||
      recipe.cropY + recipe.cropHeight > 1.000001) throw new Error('裁切区域必须位于原始画面内。');
    if (!Number.isInteger(recipe.subjectIndex) || recipe.subjectIndex < -1 || recipe.subjectIndex > 19) {
      throw new Error('主体选择无效。');
    }
    return {
      mode: recipe.mode, borderWidth: recipe.borderWidth, borderColor: recipe.borderColor,
      rotation: recipe.rotation, flipHorizontal: recipe.flipHorizontal, cropX: recipe.cropX,
      cropY: recipe.cropY, cropWidth: recipe.cropWidth, cropHeight: recipe.cropHeight, subjectIndex: recipe.subjectIndex
    };
  }

  static placement(placement: DayPlacement): DayPlacement {
    StickerCodec.object(placement);
    StickerCodec.id(placement.id);
    StickerCodec.id(placement.assetId);
    StickerCodec.id(placement.revisionId);
    if (typeof placement.dateKey !== 'string' || !StickerCodec.validDate(placement.dateKey)) throw new Error('贴纸日期无效。');
    StickerCodec.unit(placement.x);
    StickerCodec.unit(placement.y);
    if (!Number.isFinite(placement.scale) || placement.scale < 0.1 || placement.scale > 8) throw new Error('摆放缩放比例无效。');
    StickerCodec.angle(placement.rotation);
    if (!Number.isSafeInteger(placement.zIndex) || Math.abs(placement.zIndex) > 1000000) throw new Error('摆放层级无效。');
    StickerCodec.text(placement.note, 2000, '备注');
    StickerCodec.timestamps(placement.createdAt, placement.updatedAt);
    return {
      id: placement.id, dateKey: placement.dateKey, assetId: placement.assetId, revisionId: placement.revisionId,
      x: placement.x, y: placement.y, scale: placement.scale, rotation: placement.rotation, zIndex: placement.zIndex,
      note: placement.note, createdAt: placement.createdAt, updatedAt: placement.updatedAt
    };
  }

  static categories(values: string[]): string[] {
    if (!Array.isArray(values) || values.length === 0 || values.length > 100) throw new Error('分类列表无效。');
    const result: string[] = [];
    for (const value of values) {
      if (typeof value !== 'string' || value.trim() !== value || value.length === 0 || value.length > 24) {
        throw new Error('分类名称须为 1 至 24 个字符，首尾不能为空格。');
      }
      if (result.includes(value)) throw new Error('分类名称不能重复。');
      result.push(value);
    }
    if (!result.includes('未分类')) throw new Error('请保留未分类入口。');
    return result;
  }

  static id(value: string): void {
    if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(value)) throw new Error('贴纸标识无效。');
  }

  static filePath(value: string, directory: string, kind: string): void {
    if (typeof value !== 'string' || !value.startsWith(`${directory}/`)) throw new Error('图片只能引用应用私有贴纸目录。');
    const relative: string = value.slice(directory.length + 1);
    const pieces: string[] = relative.split('/');
    if (pieces.length < 1 || pieces.length > 2) throw new Error('图片目录层级无效。');
    if (pieces.length === 2) StickerCodec.id(pieces[0]);
    const filename: string = pieces[pieces.length - 1];
    const extensions: string = kind === 'mask' ? '(mask|png)' : kind === 'source' ? '(source|png|jpg|jpeg)' : '(png|jpg|jpeg)';
    if (!new RegExp(`^[A-Za-z0-9][A-Za-z0-9_-]{0,127}\\.${extensions}$`).test(filename)) {
      throw new Error('图片路径、文件名或扩展名无效。');
    }
  }

  private static object(value: Object): void {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) throw new Error('贴纸数据必须是有效对象。');
  }

  private static unique(ids: Set<string>, id: string): void {
    if (ids.has(id)) throw new Error('贴纸索引包含重复标识。');
    ids.add(id);
  }

  private static dimensions(width: number, height: number, allowUnknown: boolean): void {
    if (!Number.isInteger(width) || !Number.isInteger(height) || width < 0 || height < 0 ||
      width > 100000 || height > 100000 || ((width === 0 || height === 0) && !(allowUnknown && width === 0 && height === 0))) {
      throw new Error('图片尺寸无效。');
    }
  }

  private static unit(value: number): void {
    if (!Number.isFinite(value) || value < 0 || value > 1) throw new Error('归一化位置须在 0 到 1 之间。');
  }

  private static angle(value: number): void {
    if (!Number.isFinite(value) || Math.abs(value) > 3600) throw new Error('旋转角度无效。');
  }

  private static timestamp(value: number): void {
    if (!Number.isSafeInteger(value) || value < 0) throw new Error('创建时间无效。');
  }

  private static timestamps(createdAt: number, updatedAt: number): void {
    StickerCodec.timestamp(createdAt);
    StickerCodec.timestamp(updatedAt);
    if (updatedAt < createdAt) throw new Error('更新时间早于创建时间。');
  }

  private static text(value: string, maximum: number, label: string): void {
    if (typeof value !== 'string' || value.length > maximum) throw new Error(`${label}最多 ${maximum} 个字符。`);
  }

  private static validDate(value: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) return false;
    const date: Date = new Date(`${value}T00:00:00.000Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }
}
