import { Theme } from './Theme';
import { PaperBodyStyle, PaperCaptionStyle } from './PaperStyles';

/** 棋盘格仅是预览底层，不参与像素制作、文件编码或保存配方。 */
@Component
export struct StickerPreview {
  @Prop imagePath: string = '';
  @Prop busy: boolean = false;
  @Prop paperColor: string = Theme.PAPER;
  @State private checkerboard: boolean = false;
  private readonly canvasContext: CanvasRenderingContext2D =
    new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private canvasReady: boolean = false;
  private canvasWidth: number = 0;
  private canvasHeight: number = 245;

  private paintCheckers(): void {
    if (!this.canvasReady || this.canvasWidth <= 0 || this.canvasHeight <= 0) return;
    const context: CanvasRenderingContext2D = this.canvasContext;
    const cell: number = 16;
    context.clearRect(0, 0, this.canvasWidth, this.canvasHeight);
    context.fillStyle = Theme.CARD;
    context.fillRect(0, 0, this.canvasWidth, this.canvasHeight);
    context.fillStyle = Theme.LINE;
    for (let y: number = 0; y < this.canvasHeight; y += cell) {
      for (let x: number = 0; x < this.canvasWidth; x += cell) {
        if ((Math.floor(x / cell) + Math.floor(y / cell)) % 2 === 0) context.fillRect(x, y, cell, cell);
      }
    }
  }

  private resizeCanvas(area: Area): void {
    const width: number = Number(area.width);
    const height: number = Number(area.height);
    if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) return;
    this.canvasWidth = width; this.canvasHeight = height; this.paintCheckers();
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.canvasContext).width('100%').height('100%').opacity(this.checkerboard ? 1 : 0)
          .onReady((): void => { this.canvasReady = true; this.paintCheckers(); })
          .onAreaChange((_oldArea: Area, area: Area): void => this.resizeCanvas(area))
        if (this.imagePath.length > 0) {
          Image(`file://${this.imagePath}`).width('100%').height('100%').objectFit(ImageFit.Contain)
            .padding({ left: 20, right: 20, top: 52, bottom: 20 })
            .accessibilityText('当前制作结果预览，背景仅用于检查透明边缘')
        } else {
          Column({ space: 10 }) {
            if (!this.busy) {
              SymbolGlyph($r('sys.symbol.picture_2')).fontSize(32).fontColor([Theme.MUTED])
            }
            Text(this.busy ? '正在制作预览…' : '预览暂不可用').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
            if (!this.busy) {
              Text('可以重拍或换一张照片').attributeModifier(new PaperCaptionStyle())
            }
          }.padding({ top: 30 })
        }
        if (this.busy) {
          LoadingProgress().width(28).height(28).color(Theme.ACCENT)
            .translate({ y: this.imagePath.length === 0 ? -20 : 0 })
        }
      }.width('100%').height('100%')
      Row({ space: 0 }) {
        this.backgroundChoice('纸面', false)
        this.backgroundChoice('棋盘格', true)
      }.padding(2).backgroundColor(Theme.CARD).borderRadius(24)
        .border({ width: 0.5, color: Theme.LINE }).margin(8)
    }.width('100%').height(245).backgroundColor(this.paperColor === Theme.PAPER ? Theme.CARD : this.paperColor)
      .borderRadius(Theme.CARD_RADIUS).clip(true).border({ width: 0.5, color: Theme.LINE })
  }

  @Builder
  private backgroundChoice(label: string, checked: boolean) {
    Button(label, { type: ButtonType.Normal }).fontSize(Theme.CAPTION_SIZE)
      .fontColor(this.checkerboard === checked ? Theme.INK : Theme.MUTED)
      .backgroundColor(this.checkerboard === checked ? Theme.SOFT : Color.Transparent)
      .constraintSize({ minHeight: Theme.CONTROL_HEIGHT }).padding({ left: 12, right: 12 }).borderRadius(22)
      .accessibilityText(`检查背景：${label}${this.checkerboard === checked ? '，已选中' : ''}`)
      .onClick((): void => { this.checkerboard = checked; })
  }
}
