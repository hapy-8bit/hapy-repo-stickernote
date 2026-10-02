import { DayPlacement, StickerAsset, StickerRevision, StickerStore } from '../domain/StickerModels';

/** 仅关联领域数据供页面展示；缺失引用保持为空，不生成示例贴纸。 */
export class StickerViewModels {
  static asset(store: StickerStore, id: string): StickerAsset | undefined {
    return store.assets.find((value: StickerAsset): boolean => value.id === id);
  }

  static revision(store: StickerStore, id: string): StickerRevision | undefined {
    return store.revisions.find((value: StickerRevision): boolean => value.id === id);
  }

  static latest(store: StickerStore, assetId: string): StickerRevision | undefined {
    return store.revisions.filter((value: StickerRevision): boolean => value.assetId === assetId)
      .sort((left: StickerRevision, right: StickerRevision): number => right.createdAt - left.createdAt)[0];
  }

  static day(store: StickerStore, dateKey: string): DayPlacement[] {
    return store.placements.filter((value: DayPlacement): boolean => value.dateKey === dateKey)
      .sort((left: DayPlacement, right: DayPlacement): number => left.zIndex - right.zIndex);
  }

  static image(store: StickerStore, placement: DayPlacement): string {
    const revision: StickerRevision | undefined = StickerViewModels.revision(store, placement.revisionId);
    return revision === undefined ? '' : revision.imagePath;
  }

  static title(store: StickerStore, assetId: string): string {
    const asset: StickerAsset | undefined = StickerViewModels.asset(store, assetId);
    return asset !== undefined && asset.title.length > 0 ? asset.title : '未命名贴纸';
  }
}
