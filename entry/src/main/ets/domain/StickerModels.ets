/** 图片尺寸属于对应文件坐标系；裁切和纸面位置均使用归一化坐标。 */
export interface StickerRecipe {
  mode: string;
  borderWidth: number;
  borderColor: string;
  rotation: number;
  flipHorizontal: boolean;
  cropX: number;
  cropY: number;
  cropWidth: number;
  cropHeight: number;
  subjectIndex: number;
}

/** 资产负责原图和可变归档信息；legacy 的 sourcePath 为空、宽高为 0 表示未知。 */
export interface StickerAsset {
  id: string;
  sourcePath: string;
  sourceType: string;
  width: number;
  height: number;
  title: string;
  note: string;
  category: string;
  favorite: boolean;
  createdAt: number;
  updatedAt: number;
}

/** 保存后不可变。修改制作参数必须生成新版本，历史纸面继续引用原版本。 */
export interface StickerRevision {
  id: string;
  assetId: string;
  maskPath: string;
  imagePath: string;
  width: number;
  height: number;
  recipe: StickerRecipe;
  createdAt: number;
}

export interface DayPlacement {
  id: string;
  dateKey: string;
  assetId: string;
  revisionId: string;
  x: number;
  y: number;
  scale: number;
  rotation: number;
  zIndex: number;
  note: string;
  createdAt: number;
  updatedAt: number;
}

export interface StickerStore {
  schemaVersion: number;
  assets: StickerAsset[];
  revisions: StickerRevision[];
  placements: DayPlacement[];
  categories: string[];
}

export const DEFAULT_STICKER_CATEGORIES: string[] = ['未分类', '日常', '美食', '植物', '物件', '宠物', '出行'];

/** 每次操作读取并验证当前索引，再一次提交；调用方只能在提交成功后更新 UI。 */
export interface StickerRepository {
  load(): Promise<StickerStore>;
  saveAsset(asset: StickerAsset, revision: StickerRevision, placement: DayPlacement | undefined): Promise<void>;
  updateAsset(asset: StickerAsset): Promise<void>;
  savePlacement(placement: DayPlacement): Promise<void>;
  savePlacements(placements: DayPlacement[]): Promise<void>;
  removePlacement(id: string): Promise<void>;
  removeAsset(id: string): Promise<string[]>;
  renameCategory(oldName: string, newName: string): Promise<void>;
  saveCategories(categories: string[]): Promise<void>;
}
