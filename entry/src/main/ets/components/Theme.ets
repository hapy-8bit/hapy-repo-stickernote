/** 页面只共享视觉常量，不共享业务状态。 */
export class Theme {
  static readonly PAPER: string = '#F6F3EB';
  static readonly CARD: string = '#FFFDF8';
  static readonly INK: string = '#332F29';
  static readonly MUTED: string = '#827C73';
  static readonly ACCENT: string = '#BA6245';
  static readonly LINE: string = '#E8E3D9';
  static readonly SOFT: string = '#ECE7DC';
  static readonly PAGE_GUTTER: number = 20;
  static readonly PAPER_GUTTER: number = 18;
  static readonly CARD_RADIUS: number = 30;
  static readonly TOOL_RADIUS: number = 24;
  static readonly CONTROL_RADIUS: number = 14;
  static readonly ACTION_RADIUS: number = 24;
  static readonly CONTROL_HEIGHT: number = 44;
  static readonly ACTION_HEIGHT: number = 48;
  static readonly INPUT_HEIGHT: number = 48;
  static readonly BRAND_TITLE_SIZE: number = 30;
  static readonly PAGE_TITLE_SIZE: number = 22;
  static readonly EMPTY_TITLE_SIZE: number = 18;
  static readonly SECTION_TITLE_SIZE: number = 16;
  static readonly BODY_SIZE: number = 14;
  static readonly CAPTION_SIZE: number = 12;
  static readonly BUTTON_SIZE: number = 14;
  static readonly ICON_SIZE: number = 20;
  static readonly SMALL_ICON_SIZE: number = 16;
  // Keep the two paper tabs on the same measured canvas frame.
  static readonly HEADER_HEIGHT: number = 88;
  static readonly DOCK_HEIGHT: number = 84;
  static readonly FADE_OUT_MS: number = 100;
  static readonly FADE_IN_MS: number = 190;
  static readonly MOTION_OFFSET: number = 14;
  static readonly PAPER_STYLES: string[] = ['paper', 'cream', 'sage'];

  static paperColor(style: string): string {
    if (style === 'cream') return '#F7EEDF';
    if (style === 'sage') return '#EEF1E9';
    return Theme.PAPER;
  }

  static paperLabel(style: string): string {
    if (style === 'cream') return '奶油纸';
    if (style === 'sage') return '浅草纸';
    return '暖白纸';
  }
}
