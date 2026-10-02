import { Theme } from './Theme';
import { PaperIconStyle, PaperTitleStyle, PaperCaptionStyle } from './PaperStyles';

@Component
export struct PaperTopBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop busy: boolean = false;
  onBack: () => void = (): void => {};

  build() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
      }.attributeModifier(new PaperIconStyle(Theme.CARD)).border({ width: 0.5, color: Theme.LINE })
        .borderRadius(Theme.CONTROL_RADIUS).enabled(!this.busy)
        .accessibilityText('返回').onClick((): void => this.onBack())
      Column({ space: 4 }) {
        Text(this.title).attributeModifier(new PaperTitleStyle()).width('100%')
        if (this.subtitle.length > 0) {
          Text(this.subtitle).attributeModifier(new PaperCaptionStyle()).width('100%')
        }
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
    }.width('100%').constraintSize({ minHeight: Theme.HEADER_HEIGHT })
      .padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 12, bottom: 12 })
  }
}
