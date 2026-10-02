import { CATEGORIES, StickerEntry } from '../domain/JournalModels';

interface JournalDocument {
  schemaVersion: number;
  entries: StickerEntry[];
}

/** JSON 只在此边界解析；验证后重新构造领域对象，不把原始对象交给页面。 */
export class JournalCodec {
  static decode(text: string, mediaDirectory: string): StickerEntry[] {
    let document: JournalDocument;
    try {
      document = JSON.parse(text) as JournalDocument;
    } catch {
      throw new Error('本地日记文件无法解析，原文件已保留。');
    }
    if (document === null || typeof document !== 'object' || Array.isArray(document)) {
      throw new Error('本地日记文件结构无效，原文件已保留。');
    }
    if (document.schemaVersion !== 1) {
      throw new Error('本地日记文件版本不支持，原文件已保留。');
    }
    if (!Array.isArray(document.entries)) {
      throw new Error('本地日记列表结构无效，原文件已保留。');
    }
    try {
      return JournalCodec.validateEntries(document.entries, mediaDirectory);
    } catch (error) {
      const reason: Error = error as Error;
      throw new Error(`本地日记数据无效，原文件已保留。${reason.message}`);
    }
  }

  static encode(entries: StickerEntry[], mediaDirectory: string): string {
    const document: JournalDocument = {
      schemaVersion: 1,
      entries: JournalCodec.validateEntries(entries, mediaDirectory)
    };
    return JSON.stringify(document);
  }

  static validate(entry: StickerEntry, mediaDirectory: string): StickerEntry {
    if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new Error('日记记录必须是有效对象。');
    }
    if (typeof entry.id !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/.test(entry.id)) {
      throw new Error('日记记录标识无效。');
    }
    if (typeof entry.dateKey !== 'string' || !JournalCodec.validDate(entry.dateKey)) {
      throw new Error('日记日期必须是有效的 YYYY-MM-DD 自然日。');
    }
    if (typeof entry.title !== 'string' || entry.title.length > 60) {
      throw new Error('标题最多 60 个字符。');
    }
    if (typeof entry.note !== 'string' || entry.note.length > 2000) {
      throw new Error('备注最多 2000 个字符。');
    }
    if (typeof entry.category !== 'string' || !CATEGORIES.includes(entry.category)) {
      throw new Error('请选择有效的日记分类。');
    }
    if (entry.mode !== 'subject' && entry.mode !== 'original') {
      throw new Error('日记图片模式无效。');
    }
    if (typeof entry.imagePath !== 'string' || !JournalCodec.validImagePath(entry.imagePath, mediaDirectory)) {
      throw new Error('日记图片必须是本应用贴纸目录中的 PNG 文件。');
    }
    if (!Number.isSafeInteger(entry.createdAt) || entry.createdAt < 0 ||
      !Number.isSafeInteger(entry.updatedAt) || entry.updatedAt < entry.createdAt) {
      throw new Error('日记创建或更新时间无效。');
    }
    return {
      id: entry.id, dateKey: entry.dateKey, title: entry.title, category: entry.category,
      note: entry.note, imagePath: entry.imagePath, mode: entry.mode,
      createdAt: entry.createdAt, updatedAt: entry.updatedAt
    };
  }

  private static validateEntries(entries: StickerEntry[], mediaDirectory: string): StickerEntry[] {
    const ids: Set<string> = new Set<string>();
    const result: StickerEntry[] = [];
    for (const candidate of entries) {
      const entry: StickerEntry = JournalCodec.validate(candidate, mediaDirectory);
      if (ids.has(entry.id)) throw new Error('日记文件包含重复的记录标识。');
      ids.add(entry.id);
      result.push(entry);
    }
    return result;
  }

  private static validDate(value: string): boolean {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000-')) return false;
    const date: Date = new Date(`${value}T00:00:00.000Z`);
    return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
  }

  private static validImagePath(value: string, mediaDirectory: string): boolean {
    const prefix: string = `${mediaDirectory}/`;
    if (!value.startsWith(prefix)) return false;
    const basename: string = value.slice(prefix.length);
    // 不接收 Picker URI、子目录、路径穿越、反斜杠或带查询参数的地址。
    return /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}\.png$/.test(basename);
  }
}
