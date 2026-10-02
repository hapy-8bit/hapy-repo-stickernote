import { common } from '@kit.AbilityKit';
import { DEFAULT_STICKER_CATEGORIES, DayPlacement, StickerAsset, StickerRepository, StickerRevision, StickerStore } from '../domain/StickerModels';
import { StickerCodec } from './StickerCodec';
import { StickerLocalFiles } from './StickerLocalFiles';
import { StickerMigration } from './StickerMigration';
import { JournalCodec } from './JournalCodec';

/** 小型本机索引在同步读取—验证—rename 事务内完成，避免 await 间隙导致更新丢失。 */
export class LocalStickerRepository implements StickerRepository {
  private readonly indexPath: string;
  private readonly legacyPath: string;
  private readonly directory: string;
  private readonly files: StickerLocalFiles;

  constructor(context: common.UIAbilityContext) {
    this.indexPath = `${context.filesDir}/sticker-store.json`;
    this.legacyPath = `${context.filesDir}/journal.json`;
    this.directory = `${context.filesDir}/stickers`;
    this.files = new StickerLocalFiles(this.directory);
  }

  async load(): Promise<StickerStore> { return this.read(); }

  async saveAsset(asset: StickerAsset, revision: StickerRevision, placement: DayPlacement | undefined): Promise<void> {
    const store: StickerStore = this.read();
    const nextAsset: StickerAsset = StickerCodec.asset(asset, this.directory, store.categories);
    const nextRevision: StickerRevision = StickerCodec.revision(revision, this.directory);
    if (nextRevision.assetId !== nextAsset.id) throw new Error('成品版本与资产不匹配。');
    const index: number = store.assets.findIndex((item: StickerAsset): boolean => item.id === nextAsset.id);
    if (index >= 0) {
      this.assertAssetIdentity(store.assets[index], nextAsset);
      store.assets[index] = nextAsset;
    } else {
      store.assets.push(nextAsset);
    }
    const existing: StickerRevision | undefined = store.revisions.find((item: StickerRevision): boolean => item.id === nextRevision.id);
    if (existing !== undefined) {
      if (JSON.stringify(existing) !== JSON.stringify(nextRevision)) throw new Error('已保存版本不可覆盖，请创建新版本。');
    } else {
      if (nextAsset.sourceType !== 'legacy' && store.revisions.some((item: StickerRevision): boolean => item.imagePath === nextRevision.imagePath)) {
        throw new Error('新版本必须使用独立成品文件，避免改变历史纸面。');
      }
      store.revisions.push(nextRevision);
    }
    if (placement !== undefined) {
      if (placement.assetId !== nextAsset.id || placement.revisionId !== nextRevision.id) throw new Error('摆放必须引用本次保存的资产和版本。');
      this.upsertPlacement(store, StickerCodec.placement(placement));
    }
    this.write(store);
  }

  async updateAsset(asset: StickerAsset): Promise<void> {
    const store: StickerStore = this.read();
    const next: StickerAsset = StickerCodec.asset(asset, this.directory, store.categories);
    const index: number = store.assets.findIndex((item: StickerAsset): boolean => item.id === next.id);
    if (index < 0) throw new Error('贴纸已不存在，请刷新贴纸盒。');
    this.assertAssetIdentity(store.assets[index], next);
    store.assets[index] = next;
    this.write(store);
  }

  async savePlacement(placement: DayPlacement): Promise<void> {
    await this.savePlacements([placement]);
  }

  async savePlacements(placements: DayPlacement[]): Promise<void> {
    const store: StickerStore = this.read();
    if (!Array.isArray(placements)) throw new Error('批量摆放列表无效。');
    const ids: Set<string> = new Set<string>();
    for (const placement of placements) {
      const next: DayPlacement = StickerCodec.placement(placement);
      if (ids.has(next.id)) throw new Error('批量摆放不能包含重复标识。');
      ids.add(next.id);
      this.upsertPlacement(store, next);
    }
    if (placements.length === 0) return;
    // 自动排版和撤销作为一次索引事务提交，任一摆放无效时不会出现部分成功。
    this.write(store);
  }

  async removePlacement(id: string): Promise<void> {
    StickerCodec.id(id);
    const store: StickerStore = this.read();
    const remaining: DayPlacement[] = store.placements.filter((item: DayPlacement): boolean => item.id !== id);
    if (remaining.length === store.placements.length) return;
    // 删除一天的摆放不删除贴纸资产，贴纸盒仍可重复使用。
    store.placements = remaining;
    this.write(store);
  }

  async removeAsset(id: string): Promise<string[]> {
    StickerCodec.id(id);
    const store: StickerStore = this.read();
    const asset: StickerAsset | undefined = store.assets.find((item: StickerAsset): boolean => item.id === id);
    if (asset === undefined) return [];
    if (store.placements.some((item: DayPlacement): boolean => item.assetId === id)) {
      throw new Error('这张贴纸仍在每日纸面中使用，请先移除对应摆放。');
    }
    const candidates: Set<string> = new Set<string>();
    if (asset.sourcePath.length > 0) candidates.add(asset.sourcePath);
    for (const revision of store.revisions) {
      if (revision.assetId !== id) continue;
      candidates.add(revision.imagePath);
      if (revision.maskPath.length > 0) candidates.add(revision.maskPath);
    }
    store.assets = store.assets.filter((item: StickerAsset): boolean => item.id !== id);
    store.revisions = store.revisions.filter((item: StickerRevision): boolean => item.assetId !== id);
    const retained: Set<string> = this.referencedFiles(store);
    this.retainLegacyFiles(candidates, retained);
    const unused: string[] = Array.from(candidates).filter((path: string): boolean => !retained.has(path));
    // 文件清理失败只会留下无引用文件；元数据失败时绝不返回清理列表。
    this.write(store);
    return unused;
  }

  async renameCategory(oldName: string, newName: string): Promise<void> {
    const store: StickerStore = this.read();
    if (!store.categories.includes(oldName)) throw new Error('原分类不存在。');
    if (oldName === '未分类' && newName !== oldName) throw new Error('未分类入口不能改名。');
    if (oldName === newName) return;
    if (store.categories.includes(newName)) throw new Error('分类名称已存在。');
    const categories: string[] = store.categories.map((value: string): string => value === oldName ? newName : value);
    store.categories = StickerCodec.categories(categories);
    const now: number = Date.now();
    for (const asset of store.assets) {
      if (asset.category !== oldName) continue;
      asset.category = newName;
      asset.updatedAt = Math.max(now, asset.updatedAt);
    }
    this.write(store);
  }

  async saveCategories(categories: string[]): Promise<void> {
    const store: StickerStore = this.read();
    const next: string[] = StickerCodec.categories(categories);
    if (store.assets.some((asset: StickerAsset): boolean => !next.includes(asset.category))) {
      throw new Error('分类仍有贴纸，请先改分类或使用分类改名。');
    }
    store.categories = next;
    this.write(store);
  }

  private read(): StickerStore {
    const text: string | undefined = this.files.readOptional(this.indexPath);
    if (text !== undefined) {
      const store: StickerStore = StickerCodec.decode(text, this.directory);
      this.files.validate(store);
      return store;
    }
    const legacy: string | undefined = this.files.readOptional(this.legacyPath);
    if (legacy === undefined) {
      return { schemaVersion: 2, assets: [], revisions: [], placements: [], categories: DEFAULT_STICKER_CATEGORIES.slice() };
    }
    const migrated: StickerStore = StickerMigration.fromLegacy(legacy, this.directory);
    // 首次迁移也先验证真实图片，损坏索引/丢图时不创建空 schema 2 来遮蔽旧记录。
    this.write(migrated);
    return migrated;
  }

  private write(store: StickerStore): void {
    const next: StickerStore = StickerCodec.validate(store, this.directory);
    this.files.validate(next);
    this.files.writeAtomic(this.indexPath, StickerCodec.encode(next, this.directory));
  }

  private upsertPlacement(store: StickerStore, next: DayPlacement): void {
    const index: number = store.placements.findIndex((item: DayPlacement): boolean => item.id === next.id);
    if (index >= 0) {
      const existing: DayPlacement = store.placements[index];
      if (next.createdAt !== existing.createdAt || next.updatedAt < existing.updatedAt) throw new Error('摆放更新时间或创建时间无效。');
      store.placements[index] = next;
    } else {
      store.placements.push(next);
    }
  }

  private assertAssetIdentity(existing: StickerAsset, next: StickerAsset): void {
    if (existing.id !== next.id || existing.sourcePath !== next.sourcePath || existing.sourceType !== next.sourceType ||
      existing.width !== next.width || existing.height !== next.height || existing.createdAt !== next.createdAt ||
      next.updatedAt < existing.updatedAt) {
      throw new Error('资产原图与坐标尺寸不可覆盖，请保留原资产并创建新版本。');
    }
  }

  private referencedFiles(store: StickerStore): Set<string> {
    const paths: Set<string> = new Set<string>();
    for (const asset of store.assets) if (asset.sourcePath.length > 0) paths.add(asset.sourcePath);
    for (const revision of store.revisions) {
      paths.add(revision.imagePath);
      if (revision.maskPath.length > 0) paths.add(revision.maskPath);
    }
    return paths;
  }

  private retainLegacyFiles(candidates: Set<string>, retained: Set<string>): void {
    try {
      const legacy: string | undefined = this.files.readOptional(this.legacyPath);
      if (legacy === undefined) return;
      for (const entry of JournalCodec.decode(legacy, this.directory)) retained.add(entry.imagePath);
    } catch {
      // schema 2 可继续使用；旧备份无法读验时保守留下文件，不以清理破坏恢复线索。
      for (const path of candidates) retained.add(path);
    }
  }
}
