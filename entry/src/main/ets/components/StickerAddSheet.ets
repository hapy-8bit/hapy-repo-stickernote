import { Theme } from './Theme';
import { PaperActionStyle, PaperTitleStyle } from './PaperStyles';

/** 只发出来源意图；选图、权限与图片文件仍由入口和媒体服务拥有。 */
@Component
export struct StickerAddSheet {
  onSelect: (source: string) => void = (_source: string): void => {};
  onCancel: () => void = (): void => {};

  @Builder
  private source(label: string, symbol: Resource, key: string) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 14 }) {
        SymbolGlyph(symbol).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
        Text(label).fontSize(Theme.BODY_SIZE).fontColor(Theme.INK).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(Theme.SMALL_ICON_SIZE).fontColor([Theme.MUTED])
      }.width('100%').padding({ top: 14, bottom: 14 })
    }.width('100%').constraintSize({ minHeight: 52 }).padding({ left: 4, right: 4 })
      .backgroundColor(Color.Transparent).borderRadius(Theme.CONTROL_RADIUS)
      .accessibilityText(label).onClick((): void => this.onSelect(key))
  }

  build() {
    Column({ space: 8 }) {
      Text('添加一张贴纸').attributeModifier(new PaperTitleStyle()).width('100%').margin({ bottom: 8 })
      this.source('拍照制作', $r('sys.symbol.camera'), 'camera')
      this.source('从相册选择', $r('sys.symbol.picture_2'), 'gallery')
      this.source('从贴纸盒挑选', $r('sys.symbol.square_grid_2x2'), 'library')
      Divider().color(Theme.LINE).margin({ top: 8 })
      Button('取消', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('quiet')).width('100%')
        .onClick((): void => this.onCancel())
    }.width('100%').padding({ top: 24, bottom: 24, left: 24, right: 24 }).backgroundColor(Theme.CARD)
  }
}
