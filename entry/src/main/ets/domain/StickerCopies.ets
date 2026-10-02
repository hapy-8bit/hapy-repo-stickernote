import { DayPlacement, StickerAsset } from './StickerModels';

/** 编辑事务使用独立对象；UI 中的旧快照只在仓库完整提交后替换。 */
export class StickerCopies {
  static asset(value: StickerAsset): StickerAsset {
    return { id: value.id, sourcePath: value.sourcePath, sourceType: value.sourceType,
      width: value.width, height: value.height, title: value.title, category: value.category,
      favorite: value.favorite, note: value.note, createdAt: value.createdAt, updatedAt: value.updatedAt };
  }

  static placement(value: DayPlacement): DayPlacement {
    return { id: value.id, dateKey: value.dateKey, assetId: value.assetId, revisionId: value.revisionId,
      x: value.x, y: value.y, scale: value.scale, rotation: value.rotation, zIndex: value.zIndex,
      note: value.note, createdAt: value.createdAt, updatedAt: value.updatedAt };
  }

  static placements(values: DayPlacement[]): DayPlacement[] {
    return values.map((value: DayPlacement): DayPlacement => StickerCopies.placement(value));
  }
}
