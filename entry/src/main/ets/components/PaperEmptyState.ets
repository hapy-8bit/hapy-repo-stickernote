import { PaperActionStyle, PaperBodyStyle, PaperEmptyTitleStyle } from './PaperStyles';
import { Theme } from './Theme';

/** 空态只说明真实的空数据，不创建样例；动作由持有业务状态的页面传入。 */
@Component
export struct PaperEmptyState {
  @Prop title: string = '';
  @Prop description: string = '';
  @Prop icon: Resource = $r('sys.symbol.star_fill');
  @Prop actionLabel: string = '';
  @Prop busy: boolean = false;
  onAction: () => void = (): void => {};

  build() {
    Column({ space: 0 }) {
      Column() {
        SymbolGlyph(this.icon).fontSize(32).fontColor([Theme.MUTED]).opacity(0.7)
      }.width(90).height(90).justifyContent(FlexAlign.Center).borderRadius(45)
        .border({ width: 1.5, color: Theme.LINE, style: BorderStyle.Dashed }).margin({ bottom: 20 })
        .accessibilityLevel('no')
      Text(this.title).attributeModifier(new PaperEmptyTitleStyle()).textAlign(TextAlign.Center)
        .width('100%').margin({ bottom: 10 })
      Text(this.description).attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
        .textAlign(TextAlign.Center).width('100%')
      if (this.actionLabel.length > 0) {
        Button(this.actionLabel, { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('secondary'))
          .border({ width: 1, color: Theme.LINE }).borderRadius(Theme.ACTION_RADIUS)
          .backgroundColor(Theme.CARD).margin({ top: 22 })
          .enabled(!this.busy).onClick((): void => this.onAction())
      }
    }.width('100%').height('100%').justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 16, bottom: 40 })
  }
}
