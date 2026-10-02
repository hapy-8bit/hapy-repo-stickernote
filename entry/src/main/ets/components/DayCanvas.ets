import { DayPlacement, StickerStore } from '../domain/StickerModels';
import { DateTools } from '../domain/DateTools';
import { StickerViewModels } from './StickerViewModels';
import { Theme } from './Theme';
import { PaperEmptyState } from './PaperEmptyState';
import { PaperActionStyle, PaperBodyStyle, PaperBrandStyle, PaperCaptionStyle, PaperEmptyTitleStyle,
  PaperIconStyle } from './PaperStyles';

/** 纸面只预览拖动；手势结束后交给上层事务落盘，未提交时不改领域对象。 */
@Component
export struct DayCanvas {
  @Prop store: StickerStore = { schemaVersion: 2, assets: [], revisions: [], placements: [], categories: [] };
  @Prop selectedDate: string = '';
  @Prop paperColor: string = Theme.PAPER;
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop reducedMotion: boolean = false;
  @Prop errorMessage: string = '';
  @Prop editing: boolean = false;
  @Prop selectedPlacementId: string = '';
  onCalendar: () => void = (): void => {};
  onSelectDate: (dateKey: string) => void = (_dateKey: string): void => {};
  onSettings: () => void = (): void => {};
  onCamera: () => void = (): void => {};
  onLibrary: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  onSelectPlacement: (id: string) => void = (_id: string): void => {};
  onEditAsset: (assetId: string, placementId: string) => void = (_assetId: string, _placementId: string): void => {};
  onMovePlacement: (id: string, x: number, y: number) => void = (_id: string, _x: number, _y: number): void => {};
  onTransformPlacement: (id: string, scale: number, rotation: number) => void =
    (_id: string, _scale: number, _rotation: number): void => {};
  onLayerPlacement: (id: string, forward: boolean) => void = (_id: string, _forward: boolean): void => {};
  onRemovePlacement: (id: string) => void = (_id: string): void => {};
  onArrange: () => void = (): void => {};
  onUndo: () => void = (): void => {};
  onFinishLayout: () => void = (): void => {};
  @State private canvasWidth: number = 1;
  @State private canvasHeight: number = 1;
  @State private dragId: string = '';
  @State private dragX: number = 0;
  @State private dragY: number = 0;

  private date(): string { return this.selectedDate.length > 0 ? this.selectedDate : DateTools.key(); }
  private placements(): DayPlacement[] { return StickerViewModels.day(this.store, this.date()); }
  private selected(): DayPlacement | undefined {
    return this.placements().find((value: DayPlacement): boolean => value.id === this.selectedPlacementId);
  }
  private controlsAtTop(): boolean { return (this.selected()?.y ?? 0) > 0.5; }
  private hasRecord(dateKey: string): boolean {
    return this.store.placements.some((value: DayPlacement): boolean => value.dateKey === dateKey);
  }
  private dayAccessibility(dateKey: string): string {
    return `${DateTools.label(dateKey)}，星期${DateTools.weekday(dateKey)}` +
      (dateKey === DateTools.key() ? '，今天' : '') + (dateKey === this.date() ? '，已选日期' : '') +
      `，${StickerViewModels.day(this.store, dateKey).length}张贴纸`;
  }
  private ruledLines(): number[] {
    const result: number[] = [];
    for (let index: number = 0; index < Math.ceil(this.canvasHeight / 38); index++) result.push(index);
    return result;
  }
  private x(value: DayPlacement): number {
    return value.x * this.canvasWidth + (this.dragId === value.id ? this.dragX : 0);
  }
  private y(value: DayPlacement): number {
    return value.y * this.canvasHeight + (this.dragId === value.id ? this.dragY : 0);
  }
  private transformSelection(scaleDelta: number, rotationDelta: number): void {
    if (this.busy) return;
    const value: DayPlacement | undefined = this.selected();
    if (value === undefined) return;
    this.onTransformPlacement(value.id, Math.max(0.3, Math.min(2.5, value.scale + scaleDelta)),
      value.rotation + rotationDelta);
  }

  build() {
    Column({ space: 0 }) {
      this.header()
      this.weekStrip()
      Stack({ alignContent: Alignment.Bottom }) {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 0 }) {
            ForEach(this.ruledLines(), (_line: number) => {
              Row().width('100%').height(38)
                .border({ width: { bottom: 0.5 }, color: Theme.LINE, style: BorderStyle.Dashed })
            }, (line: number): string => `${line}`)
          }.width('100%').height('100%').padding({ top: 22, left: 20, right: 20 })
            .opacity(0.7).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress().width(28).height(28).color(Theme.ACCENT)
              Text('正在打开纸面…').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
            }.width('100%').height('100%').justifyContent(FlexAlign.Center)
          } else if (this.errorMessage.length > 0) {
            Column({ space: 15 }) {
              Text('纸面暂时打不开').attributeModifier(new PaperEmptyTitleStyle())
              Text(this.errorMessage).attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED).textAlign(TextAlign.Center)
              Button('重新读取', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('primary'))
                .constraintSize({ minHeight: Theme.ACTION_HEIGHT })
                .enabled(!this.busy).onClick((): void => this.onRetry())
            }.width('100%').height('100%').justifyContent(FlexAlign.Center).padding(32)
          } else if (this.placements().length === 0) {
            PaperEmptyState({ title: '这一天还没有贴纸',
              description: '一杯咖啡，一束花，一本书，\n都能成为这一天的小贴纸。' })
          } else {
            ForEach(this.placements(), (placement: DayPlacement) => {
              this.placedSticker(placement)
            }, (placement: DayPlacement): string => placement.id)
            if (!this.editing) {
              Text('长按贴纸，重新摆放').attributeModifier(new PaperCaptionStyle())
                .position({ x: Theme.PAGE_GUTTER, y: this.canvasHeight - 26 }).hitTestBehavior(HitTestMode.None)
            }
          }
          if (!this.loading && this.errorMessage.length === 0) {
            Row() {
              Text(DateTools.label(this.date())).attributeModifier(new PaperCaptionStyle())
              Blank()
              Text(`${this.placements().length} 张`).attributeModifier(new PaperCaptionStyle())
            }.width('100%').padding({ top: 17, left: 20, right: 20 })
              .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
          }
        }.width('100%').height('100%').clip(true)
          .onAreaChange((_oldArea: Area, area: Area): void => {
            this.canvasWidth = Math.max(1, Number(area.width));
            this.canvasHeight = Math.max(1, Number(area.height));
          })
        // Editing controls overlay the paper; opening them never rescales saved coordinates.
        if (this.editing) this.layoutControls()
      }.width(`calc(100% - ${Theme.PAPER_GUTTER * 2}vp)`).layoutWeight(1)
        .backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
        .borderRadius(Theme.CARD_RADIUS).clip(true)
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }

  @Builder
  private header() {
    Column({ space: 4 }) {
      Row({ space: 12 }) {
        Column({ space: 6 }) {
          Text('每日贴纸').attributeModifier(new PaperBrandStyle())
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('把这一刻贴进今天').attributeModifier(new PaperCaptionStyle())
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Column({ space: 2 }) {
          Text(this.loading || this.errorMessage.length > 0 ? '—' : `${this.store.assets.length}`)
            .fontSize(22).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('张生活贴纸').attributeModifier(new PaperCaptionStyle())
        }.alignItems(HorizontalAlign.End).constraintSize({ maxWidth: 100 })
          .accessibilityText(this.loading || this.errorMessage.length > 0 ? '贴纸数量暂不可用' : `共${this.store.assets.length}张生活贴纸`)
      }.width('100%')
      Row({ space: 4 }) {
        Text(`${DateTools.parse(this.date()).getFullYear()} 年 ${DateTools.parse(this.date()).getMonth() + 1} 月`)
          .attributeModifier(new PaperCaptionStyle()).layoutWeight(1)
        if (this.editing) {
          Button('完成', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('primary'))
            .enabled(!this.busy).onClick((): void => this.onFinishLayout())
        } else {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 4 }) {
              SymbolGlyph($r('sys.symbol.calendar')).fontSize(Theme.SMALL_ICON_SIZE).fontColor([Theme.INK])
              Text('月历').fontSize(Theme.CAPTION_SIZE).fontColor(Theme.INK).fontWeight(FontWeight.Medium)
            }
          }.height(Theme.CONTROL_HEIGHT).padding({ left: 12, right: 12 })
            .backgroundColor(Theme.SOFT).borderRadius(Theme.CONTROL_RADIUS)
            .enabled(!this.loading && !this.busy).accessibilityText('月历，选择日期与回看')
            .onClick((): void => this.onCalendar())
        }
      }.width('100%').height(Theme.CONTROL_HEIGHT)
    }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 20, bottom: 4 })
  }

  @Builder
  private weekStrip() {
    Row({ space: 2 }) {
      ForEach(DateTools.week(this.date()), (dateKey: string) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 7 }) {
            Text(`周${DateTools.weekday(dateKey)}`).fontSize(Theme.CAPTION_SIZE)
              .fontColor(dateKey === this.date() ? Theme.INK : Theme.MUTED).maxLines(1)
            Text(`${DateTools.parse(dateKey).getDate()}`).fontSize(20)
              .fontWeight(dateKey === this.date() ? FontWeight.Bold : FontWeight.Medium)
              .fontColor(dateKey === this.date() ? Theme.INK : Theme.MUTED).maxLines(1)
            Row({ space: 3 }) {
              if (dateKey === DateTools.key()) Circle().width(4).height(4).fill(Theme.ACCENT)
              if (this.hasRecord(dateKey)) Circle().width(4).height(4).fill(Theme.MUTED)
            }.height(4)
          }.justifyContent(FlexAlign.Center)
        }.layoutWeight(1).constraintSize({ minHeight: 80 })
          .padding({ top: 8, bottom: 6, left: 0, right: 0 }).borderRadius(30)
          .backgroundColor(dateKey === this.date() ? Theme.CARD : Color.Transparent)
          .enabled(!this.busy && !this.loading && this.errorMessage.length === 0)
          .accessibilityText(this.dayAccessibility(dateKey)).onClick((): void => this.onSelectDate(dateKey))
      }, (dateKey: string): string => dateKey)
    }.width('100%').padding({ left: Theme.PAPER_GUTTER, right: Theme.PAPER_GUTTER, bottom: 14 })
  }

  @Builder
  private placedSticker(placement: DayPlacement) {
    Column({ space: 5 }) {
      if (StickerViewModels.image(this.store, placement).length > 0) {
        Image(`file://${StickerViewModels.image(this.store, placement)}`).width('100%').height(160 * placement.scale)
          .objectFit(ImageFit.Contain).draggable(false).accessibilityText(StickerViewModels.title(this.store, placement.assetId))
      } else {
        Text('图片暂不可用').attributeModifier(new PaperCaptionStyle()).height(80)
      }
      if (placement.note.length > 0) {
        Text(placement.note).attributeModifier(new PaperCaptionStyle()).fontColor(Theme.INK).maxLines(3).textAlign(TextAlign.Center)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }.width(160 * placement.scale).padding(5).rotate({ angle: placement.rotation })
      .border({ width: this.editing && placement.id === this.selectedPlacementId ? 1 : 0, color: Theme.ACCENT })
      .borderRadius(10).position({ x: this.x(placement), y: this.y(placement) })
      .translate({ x: '-50%', y: '-50%' })
      .onClick((): void => {
        if (this.busy) return;
        if (this.editing) this.onSelectPlacement(placement.id);
        else this.onEditAsset(placement.assetId, placement.id);
      })
      .gesture(GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false }).onAction((): void => {
          if (!this.busy) this.onSelectPlacement(placement.id);
        }),
        PanGesture().onActionStart((): void => {
          if (!this.editing || this.busy) return;
          this.onSelectPlacement(placement.id); this.dragId = placement.id; this.dragX = 0; this.dragY = 0;
        }).onActionUpdate((event: GestureEvent): void => {
          if (this.dragId !== placement.id) return;
          this.dragX = event.offsetX; this.dragY = event.offsetY;
        }).onActionEnd((): void => {
          if (this.dragId !== placement.id) return;
          this.onMovePlacement(placement.id, Math.max(0.05, Math.min(0.95, this.x(placement) / this.canvasWidth)),
            Math.max(0.05, Math.min(0.95, this.y(placement) / this.canvasHeight)));
          this.dragId = ''; this.dragX = 0; this.dragY = 0;
        }).onActionCancel((): void => { this.dragId = ''; this.dragX = 0; this.dragY = 0; })
      ))
  }

  @Builder
  private layoutControls() {
    Column() {
      Column({ space: 8 }) {
        Row() {
          Text(this.selected() === undefined ? '先轻点一张贴纸' : '调整摆放')
            .fontSize(Theme.BODY_SIZE).fontWeight(FontWeight.Medium)
            .fontColor(Theme.INK)
          Blank()
          Text('左右滑动查看更多').attributeModifier(new PaperCaptionStyle())
        }.width('100%')
        Scroll() {
          Row({ space: 6 }) {
            this.control('缩小', this.selected() !== undefined, (): void => this.transformSelection(-0.1, 0))
            this.control('放大', this.selected() !== undefined, (): void => this.transformSelection(0.1, 0))
            this.control('左转', this.selected() !== undefined, (): void => this.transformSelection(0, -10))
            this.control('右转', this.selected() !== undefined, (): void => this.transformSelection(0, 10))
            this.control('置前', this.selected() !== undefined,
              (): void => this.onLayerPlacement(this.selectedPlacementId, true))
            this.control('置后', this.selected() !== undefined,
              (): void => this.onLayerPlacement(this.selectedPlacementId, false))
            this.control('移除', this.selected() !== undefined, (): void => this.onRemovePlacement(this.selectedPlacementId))
            this.control('排版', true, (): void => this.onArrange())
            this.control('撤销', true, (): void => this.onUndo())
          }
        }.width('100%').height(Theme.CONTROL_HEIGHT).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      }.width('100%').padding(12).backgroundColor(Theme.CARD).borderRadius(Theme.CARD_RADIUS)
        .border({ width: 0.5, color: Theme.LINE }).shadow({ radius: 14, color: '#10242220', offsetY: 4 })
    }.width('100%').padding({ left: 16, right: 16, top: 14, bottom: 14 })
      // 靠下的贴纸被选中时工具条放到上方，保留该贴纸中心的拖动区域。
      .align(this.controlsAtTop() ? Alignment.Top : Alignment.Bottom)
      .transition(TransitionEffect.opacity(0).combine(TransitionEffect.translate({
        y: this.reducedMotion ? 0 : (this.controlsAtTop() ? -8 : 8) }))
        .animation({ duration: this.reducedMotion ? 0 : 140, curve: Curve.EaseOut }))
  }

  @Builder
  private control(label: string, available: boolean, action: () => void) {
    Button(label, { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle(label === '移除' ? 'danger' : 'secondary'))
      .constraintSize({ minWidth: 54, minHeight: Theme.CONTROL_HEIGHT }).padding({ left: 12, right: 12 })
      .enabled(available && !this.busy).opacity(available ? 1 : 0.45).onClick((): void => action())
  }
}
