import { DayPlacement, StickerStore } from '../domain/StickerModels';
import { DateTools } from '../domain/DateTools';
import { StickerViewModels } from './StickerViewModels';
import { PaperTopBar } from './PaperTopBar';
import { PaperActionStyle, PaperCaptionStyle, PaperIconStyle, PaperSectionStyle } from './PaperStyles';
import { Theme } from './Theme';

@Component
export struct CalendarView {
  @Prop store: StickerStore = { schemaVersion: 2, assets: [], revisions: [], placements: [], categories: [] };
  @Prop selectedDate: string = '';
  @Prop paperColor: string = Theme.PAPER;
  @Prop reducedMotion: boolean = false;
  onSelectDate: (dateKey: string) => void = (_dateKey: string): void => {};
  onBack: () => void = (): void => {};
  @State private year: number = new Date().getFullYear();
  @State private month: number = new Date().getMonth();
  @State private gridOpacity: number = 1;
  @State private monthTranslationX: number = 0;
  @State private shifting: boolean = false;
  private animationGeneration: number = 0;
  private animationTimer: number = -1;

  aboutToAppear(): void {
    if (this.selectedDate.length === 0) return;
    const date: Date = DateTools.parse(this.selectedDate);
    this.year = date.getFullYear();
    this.month = date.getMonth();
  }

  aboutToDisappear(): void {
    // 离开页面后旧动画不能再解锁或修改下一次打开的月历。
    this.animationGeneration++;
    if (this.animationTimer >= 0) clearTimeout(this.animationTimer);
    this.animationTimer = -1;
    this.shifting = false;
    this.gridOpacity = 1;
    this.monthTranslationX = 0;
  }

  private shift(delta: number): void {
    if (this.shifting) return;
    const date: Date = new Date(this.year, this.month + delta, 1, 12);
    this.year = date.getFullYear();
    this.month = date.getMonth();
    if (this.reducedMotion) return;
    this.shifting = true;
    this.gridOpacity = 0;
    this.monthTranslationX = delta > 0 ? 10 : -10;
    const generation: number = ++this.animationGeneration;
    // 先提交新月份的初始位置；短锁覆盖入场过程，避免快速连按叠加动画。
    this.animationTimer = setTimeout((): void => {
      this.animationTimer = -1;
      if (generation !== this.animationGeneration) return;
      this.getUIContext().animateTo({ duration: Theme.FADE_IN_MS, curve: Curve.EaseOut,
        onFinish: (): void => {
          if (generation === this.animationGeneration) this.shifting = false;
        } }, (): void => {
        this.gridOpacity = 1;
        this.monthTranslationX = 0;
      });
    }, 16);
  }

  private cells(): string[] {
    const offset: number = (new Date(this.year, this.month, 1, 12).getDay() + 6) % 7;
    const count: number = new Date(this.year, this.month + 1, 0, 12).getDate();
    const values: string[] = [];
    // 六周固定高度让切月时卡片及底部操作保持原位，空位不生成记录。
    for (let index: number = 0; index < 42; index++) {
      const day: number = index - offset + 1;
      values.push(day > 0 && day <= count ? DateTools.key(new Date(this.year, this.month, day, 12)) : '');
    }
    return values;
  }

  private image(dateKey: string): string {
    const values: DayPlacement[] = StickerViewModels.day(this.store, dateKey);
    return values.length > 0 ? StickerViewModels.image(this.store, values[values.length - 1]) : '';
  }

  private recordedDays(): number {
    return this.cells().filter((dateKey: string): boolean => dateKey.length > 0 &&
      StickerViewModels.day(this.store, dateKey).length > 0).length;
  }

  private dayAccessibility(dateKey: string): string {
    const today: string = dateKey === DateTools.key() ? '，今天' : '';
    const selected: string = dateKey === this.selectedDate ? '，已选日期' : '';
    return `${dateKey}${today}${selected}，${StickerViewModels.day(this.store, dateKey).length}张贴纸`;
  }

  build() {
    Column({ space: 0 }) {
      PaperTopBar({ title: '回看', subtitle: '有贴纸的日子，都在这里', onBack: (): void => this.onBack() })
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 0 }) {
            this.monthBar()
            Divider().color(Theme.LINE).strokeWidth(0.5).margin({ top: 16, bottom: 16 })
            Row() {
              ForEach(['一', '二', '三', '四', '五', '六', '日'], (day: string) => {
                Text(day).attributeModifier(new PaperCaptionStyle()).layoutWeight(1).textAlign(TextAlign.Center)
              })
            }.width('100%').margin({ bottom: 12 })
            Grid() {
              ForEach(this.cells(), (dateKey: string) => {
                GridItem() {
                  if (dateKey.length > 0) this.dayCell(dateKey)
                }
              }, (dateKey: string, index: number): string => dateKey.length > 0 ? dateKey : `blank-${index}`)
            }.columnsTemplate('1fr 1fr 1fr 1fr 1fr 1fr 1fr').rowsTemplate('1fr 1fr 1fr 1fr 1fr 1fr')
              .rowsGap(7).columnsGap(2).width('100%').height(395).scrollBar(BarState.Off)
              .opacity(this.gridOpacity).translate({ x: this.monthTranslationX }).enabled(!this.shifting)
            Divider().color(Theme.LINE).strokeWidth(0.5).margin({ top: 14, bottom: 8 })
            Row({ space: 8 }) {
              Text(`本月 ${this.recordedDays()} 天留下贴纸`).attributeModifier(new PaperCaptionStyle()).layoutWeight(1)
              Button('回到今天', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('link'))
                .onClick((): void => this.onSelectDate(DateTools.key()))
            }.width('100%')
            Row({ space: 8 }) {
              Circle().width(8).height(8).fill(Color.Transparent).stroke(Theme.ACCENT).strokeWidth(1)
              Text('今天').attributeModifier(new PaperCaptionStyle())
              Blank().width(8)
              Rect().width(12).height(12).fill(Theme.SOFT).borderRadius(4)
              Text('所选日期').attributeModifier(new PaperCaptionStyle())
            }.width('100%').justifyContent(FlexAlign.Center).padding({ top: 12, bottom: 4 })
          }.width('100%').padding(16).backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
            .borderRadius(Theme.CARD_RADIUS)
          Text('点选日期，回到那一天的纸面。').attributeModifier(new PaperCaptionStyle())
            .textAlign(TextAlign.Center).width('100%')
        }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }

  @Builder
  private monthBar() {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
      }.attributeModifier(new PaperIconStyle(Theme.SOFT))
        .enabled(!this.shifting).accessibilityText('上个月').onClick((): void => this.shift(-1))
      Text(`${this.year}年 ${this.month + 1}月`).attributeModifier(new PaperSectionStyle())
        .layoutWeight(1).textAlign(TextAlign.Center)
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
      }.attributeModifier(new PaperIconStyle(Theme.SOFT))
        .enabled(!this.shifting).accessibilityText('下个月').onClick((): void => this.shift(1))
    }.width('100%')
  }

  @Builder
  private dayCell(dateKey: string) {
    Column({ space: 4 }) {
      Text(`${DateTools.parse(dateKey).getDate()}`).attributeModifier(new PaperCaptionStyle())
        .fontWeight(dateKey === this.selectedDate ? FontWeight.Bold : FontWeight.Regular).fontColor(Theme.INK)
      if (this.image(dateKey).length > 0) {
        Image(`file://${this.image(dateKey)}`).width(30).height(30).objectFit(ImageFit.Contain)
      } else if (StickerViewModels.day(this.store, dateKey).length > 0) {
        Circle().width(5).height(5).fill(Theme.INK).margin({ top: 10 })
      } else {
        Blank().height(30)
      }
    }.width('100%').height(60).padding({ top: 6 })
      .backgroundColor(dateKey === this.selectedDate ? Theme.SOFT : Color.Transparent)
      .border({ width: dateKey === DateTools.key() ? 1 : 0, color: Theme.ACCENT })
      .borderRadius(Theme.CONTROL_RADIUS)
      .onClick((): void => this.onSelectDate(dateKey)).accessibilityText(this.dayAccessibility(dateKey))
  }
}
