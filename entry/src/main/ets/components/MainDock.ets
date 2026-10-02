import { Theme } from './Theme';

/** 添加是独立动作，由入口页选择来源，不作为可滞留的第三个内容标签。 */
@Component
export struct MainDock {
  @Prop selectedTab: string = 'today';
  @Prop disabled: boolean = false;
  @Prop paperColor: string = Theme.PAPER;
  onToday: () => void = (): void => {};
  onAdd: () => void = (): void => {};
  onLibrary: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 16 }) {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(Theme.ICON_SIZE)
              .fontColor([this.selectedTab === 'today' ? Theme.INK : Theme.MUTED])
            Text('手帐').fontSize(Theme.CAPTION_SIZE)
              .fontWeight(this.selectedTab === 'today' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedTab === 'today' ? Theme.INK : Theme.MUTED)
          }
        }.layoutWeight(1).borderRadius(Theme.CONTROL_RADIUS)
          .constraintSize({ minWidth: Theme.CONTROL_HEIGHT, minHeight: 52 })
          .backgroundColor(Color.Transparent)
          .enabled(!this.disabled).accessibilityText('今日纸面').onClick((): void => this.onToday())
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(28).fontWeight(FontWeight.Bold).fontColor([Theme.CARD])
        }.width(94).height(52).borderRadius(28).backgroundColor(Theme.INK).enabled(!this.disabled)
          .shadow({ radius: 12, color: '#17332F29', offsetY: 4 }).accessibilityText('添加贴纸')
          .onClick((): void => this.onAdd())
        Button({ type: ButtonType.Normal }) {
          Column({ space: 4 }) {
            SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(Theme.ICON_SIZE)
              .fontColor([this.selectedTab === 'library' ? Theme.INK : Theme.MUTED])
            Text('贴纸盒').fontSize(Theme.CAPTION_SIZE)
              .fontWeight(this.selectedTab === 'library' ? FontWeight.Medium : FontWeight.Normal)
              .fontColor(this.selectedTab === 'library' ? Theme.INK : Theme.MUTED)
          }
        }.layoutWeight(1).borderRadius(Theme.CONTROL_RADIUS)
          .constraintSize({ minWidth: Theme.CONTROL_HEIGHT, minHeight: 52 })
          .backgroundColor(Color.Transparent)
          .enabled(!this.disabled).accessibilityText('贴纸盒').onClick((): void => this.onLibrary())
      }.width('100%').constraintSize({ minHeight: 60 })
    }.width('100%').constraintSize({ minHeight: Theme.DOCK_HEIGHT })
      .padding({ top: 12, bottom: 12, left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER })
      .backgroundColor(this.paperColor)
  }
}
