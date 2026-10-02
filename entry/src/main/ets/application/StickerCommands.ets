import { DayPlacement, StickerAsset, StickerRepository, StickerRevision, StickerStore } from '../domain/StickerModels';
import { StickerCopies } from '../domain/StickerCopies';
import { StickerFactory } from '../domain/StickerFactory';

/** 应用用例把用户意图变成仓库事务；不依赖页面、相机和文件 SDK。 */
export class StickerCommands {
  private readonly repository: StickerRepository;
  constructor(repository: StickerRepository) { this.repository = repository; }

  async save(asset: StickerAsset, revision: StickerRevision, store: StickerStore, date: string,
    placementId: string, title: string, category: string, note: string, placeOnDay: boolean): Promise<void> {
    const next: StickerAsset = StickerCopies.asset(asset);
    next.title = title.trim(); next.category = category; next.note = note.trim();
    next.updatedAt = Math.max(Date.now(), next.updatedAt);
    let placement: DayPlacement | undefined = undefined;
    if (placeOnDay) {
      const existing: DayPlacement | undefined = store.placements.find((value: DayPlacement): boolean => value.id === placementId);
      placement = existing === undefined ? this.newPlacement(store, date, asset.id, revision.id) : StickerCopies.placement(existing);
      placement.assetId = asset.id; placement.revisionId = revision.id;
      placement.note = note.trim(); placement.updatedAt = Math.max(Date.now(), placement.updatedAt);
    }
    await this.repository.saveAsset(next, revision, placement);
  }

  async place(store: StickerStore, assetId: string, date: string): Promise<void> {
    const revision: StickerRevision | undefined = store.revisions.filter((value: StickerRevision): boolean => value.assetId === assetId)
      .sort((left: StickerRevision, right: StickerRevision): number => right.createdAt - left.createdAt)[0];
    if (revision === undefined) throw new Error('贴纸成品不存在，请重新读取。');
    await this.repository.savePlacement(this.newPlacement(store, date, assetId, revision.id));
  }

  private newPlacement(store: StickerStore, date: string, assetId: string, revisionId: string): DayPlacement {
    const day: DayPlacement[] = store.placements.filter((value: DayPlacement): boolean => value.dateKey === date);
    const next: DayPlacement = StickerFactory.createPlacement(StickerFactory.newId('placement'), date, assetId, revisionId,
      day.reduce((maximum: number, value: DayPlacement): number => Math.max(maximum, value.zIndex), -1) + 1);
    if (day.length > 0) {
      next.x = day.length % 2 === 0 ? 0.32 : 0.68;
      next.y = Math.min(0.82, 0.24 + Math.floor(day.length / 2) * 0.22);
      next.scale = 0.9;
      next.rotation = day.length % 2 === 0 ? -5 : 5;
    }
    return next;
  }

  async favorite(store: StickerStore, id: string): Promise<void> {
    const asset: StickerAsset | undefined = store.assets.find((value: StickerAsset): boolean => value.id === id);
    if (asset === undefined) throw new Error('贴纸不存在，请重新读取。');
    const next: StickerAsset = StickerCopies.asset(asset);
    next.favorite = !next.favorite; next.updatedAt = Math.max(Date.now(), next.updatedAt);
    await this.repository.updateAsset(next);
  }

  async move(store: StickerStore, id: string, x: number, y: number): Promise<void> {
    const next: DayPlacement = this.findPlacement(store, id);
    next.x = Math.max(0.05, Math.min(0.95, x)); next.y = Math.max(0.05, Math.min(0.95, y));
    await this.repository.savePlacement(next);
  }

  async transform(store: StickerStore, id: string, scale: number, rotation: number): Promise<void> {
    const next: DayPlacement = this.findPlacement(store, id);
    next.scale = Math.max(0.3, Math.min(2.5, scale)); next.rotation = ((rotation + 180) % 360 + 360) % 360 - 180;
    await this.repository.savePlacement(next);
  }

  async layer(store: StickerStore, id: string, forward: boolean): Promise<void> {
    const next: DayPlacement = this.findPlacement(store, id);
    const day: DayPlacement[] = store.placements.filter((value: DayPlacement): boolean => value.dateKey === next.dateKey);
    const minimum: number = day.reduce((value: number, item: DayPlacement): number => Math.min(value, item.zIndex), next.zIndex);
    const maximum: number = day.reduce((value: number, item: DayPlacement): number => Math.max(value, item.zIndex), next.zIndex);
    next.zIndex = forward ? maximum + 1 : minimum - 1;
    await this.repository.savePlacement(next);
  }

  async arrange(store: StickerStore, date: string): Promise<void> {
    const day: DayPlacement[] = StickerCopies.placements(store.placements.filter((value: DayPlacement): boolean => value.dateKey === date))
      .sort((left: DayPlacement, right: DayPlacement): number => left.createdAt - right.createdAt);
    const columns: number = day.length === 1 ? 1 : 2;
    const rows: number = Math.ceil(day.length / columns);
    for (let i: number = 0; i < day.length; i++) {
      day[i].x = ((i % columns) + 0.5) / columns;
      day[i].y = (Math.floor(i / columns) + 0.5) / rows;
      day[i].scale = day.length < 3 ? 1 : Math.max(0.3, Math.min(0.85, 2 / rows));
      day[i].rotation = i % 2 === 0 ? -4 : 4; day[i].zIndex = i;
      day[i].updatedAt = Math.max(Date.now(), day[i].updatedAt);
    }
    await this.repository.savePlacements(day);
  }

  async restore(placements: DayPlacement[]): Promise<void> {
    const values: DayPlacement[] = StickerCopies.placements(placements);
    for (const value of values) value.updatedAt = Math.max(Date.now(), value.updatedAt);
    await this.repository.savePlacements(values);
  }

  private findPlacement(store: StickerStore, id: string): DayPlacement {
    const found: DayPlacement | undefined = store.placements.find((value: DayPlacement): boolean => value.id === id);
    if (found === undefined) throw new Error('先选择一张贴纸。');
    const next: DayPlacement = StickerCopies.placement(found); next.updatedAt = Math.max(Date.now(), next.updatedAt); return next;
  }
}
