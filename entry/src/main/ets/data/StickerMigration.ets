import { StickerEntry } from '../domain/JournalModels';
import { DEFAULT_STICKER_CATEGORIES, DayPlacement, StickerAsset, StickerRevision, StickerStore } from '../domain/StickerModels';
import { StickerFactory } from '../domain/StickerFactory';
import { JournalCodec } from './JournalCodec';
import { StickerCodec } from './StickerCodec';

/** schema 1 只有成品；保持旧文件不变，稳定 ID 让失败重试不会重复迁移。 */
export class StickerMigration {
  static fromLegacy(text: string, directory: string): StickerStore {
    const entries: StickerEntry[] = JournalCodec.decode(text, directory);
    entries.sort((left: StickerEntry, right: StickerEntry): number => {
      return left.createdAt !== right.createdAt ? left.createdAt - right.createdAt : left.id.localeCompare(right.id);
    });
    const assets: StickerAsset[] = [];
    const revisions: StickerRevision[] = [];
    const placements: DayPlacement[] = [];
    const categories: string[] = DEFAULT_STICKER_CATEGORIES.slice();
    const paths: Map<string, string> = new Map<string, string>();
    for (const entry of entries) {
      if (!categories.includes(entry.category)) categories.push(entry.category);
      let assetId: string | undefined = paths.get(entry.imagePath);
      if (assetId === undefined) {
        assetId = StickerMigration.stableId(entry.id, 'asset0');
        paths.set(entry.imagePath, assetId);
        assets.push({
          id: assetId, sourcePath: '', sourceType: 'legacy', width: 0, height: 0,
          title: entry.title, note: entry.note, category: entry.category, favorite: false,
          createdAt: entry.createdAt, updatedAt: entry.updatedAt
        });
      } else {
        const asset: StickerAsset | undefined = assets.find((item: StickerAsset): boolean => item.id === assetId);
        // 同一物理成品只存一个资产；标题/分类选最后更新的记录，备注和日期仍分别保留。
        if (asset !== undefined && entry.updatedAt >= asset.updatedAt) {
          asset.title = entry.title;
          asset.note = entry.note;
          asset.category = entry.category;
          asset.updatedAt = entry.updatedAt;
        }
      }
      const revisionId: string = StickerMigration.stableId(entry.id, 'revision0');
      revisions.push({
        id: revisionId, assetId: assetId, maskPath: '', imagePath: entry.imagePath,
        width: 0, height: 0, recipe: StickerFactory.defaultRecipe(entry.mode), createdAt: entry.createdAt
      });
      const dayCount: number = placements.filter((item: DayPlacement): boolean => item.dateKey === entry.dateKey).length;
      placements.push({
        id: StickerMigration.stableId(entry.id, 'placement0'), dateKey: entry.dateKey,
        assetId: assetId, revisionId: revisionId, x: 0.5, y: 0.5, scale: 1, rotation: 0,
        zIndex: dayCount, note: entry.note, createdAt: entry.createdAt, updatedAt: entry.updatedAt
      });
    }
    return StickerCodec.validate({
      schemaVersion: 2, assets: assets, revisions: revisions, placements: placements, categories: categories
    }, directory);
  }

  private static stableId(original: string, suffix: string): string {
    if (original.length + suffix.length + 1 <= 128) return `${original}_${suffix}`;
    let hash: number = 2166136261;
    for (let index: number = 0; index < original.length; index++) {
      hash = Math.imul(hash ^ original.charCodeAt(index), 16777619) >>> 0;
    }
    // 超长旧标识仍保留可读前缀；哈希避免只截断导致两条旧记录共用标识。
    return `${original.slice(0, 100)}_${hash.toString(16)}_${suffix}`;
  }
}
