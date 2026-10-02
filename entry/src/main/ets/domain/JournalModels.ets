/** 领域合同只保存本地数据，不引用 ArkUI、相册 Picker、SDK 或会员服务。 */
export interface StickerEntry {
  id: string;
  dateKey: string;
  title: string;
  category: string;
  note: string;
  imagePath: string;
  mode: string;
  createdAt: number;
  updatedAt: number;
}

export interface PhotoResult {
  imagePath: string;
  mode: string;
  warning: string;
}

export const CATEGORIES: string[] = ['日常', '美食', '穿搭', '购物', '宠物', '花草', '出行', '学习'];

export interface JournalRepository {
  list(): Promise<StickerEntry[]>;
  save(entry: StickerEntry): Promise<void>;
  delete(id: string): Promise<void>;
}

export interface PhotoService {
  pick(): Promise<PhotoResult | undefined>;
  discard(imagePath: string): Promise<void>;
}
