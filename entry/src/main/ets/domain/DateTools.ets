/** 日期以设备本地年月日归属，避免 UTC 转换导致跨日。 */
export class DateTools {
  static key(date: Date = new Date()): string {
    return `${date.getFullYear()}-${DateTools.pad(date.getMonth() + 1)}-${DateTools.pad(date.getDate())}`;
  }

  static parse(key: string): Date {
    const parts: string[] = key.split('-');
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]), 12);
  }

  static recent(anchor: string): string[] {
    const result: string[] = [];
    const date: Date = DateTools.parse(anchor);
    for (let i: number = -6; i <= 0; i++) {
      result.push(DateTools.key(new Date(date.getFullYear(), date.getMonth(), date.getDate() + i, 12)));
    }
    return result;
  }

  static label(key: string): string {
    const date: Date = DateTools.parse(key);
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  static week(anchor: string): string[] {
    const date: Date = DateTools.parse(anchor);
    const mondayOffset: number = (date.getDay() + 6) % 7;
    const result: string[] = [];
    for (let i: number = 0; i < 7; i++) {
      result.push(DateTools.key(new Date(date.getFullYear(), date.getMonth(), date.getDate() - mondayOffset + i, 12)));
    }
    return result;
  }

  static weekday(key: string): string {
    const names: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    return names[DateTools.parse(key).getDay()];
  }

  private static pad(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
