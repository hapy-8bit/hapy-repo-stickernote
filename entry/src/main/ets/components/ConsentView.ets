import { Theme } from './Theme';
import { PaperActionStyle, PaperBodyStyle, PaperCaptionStyle } from './PaperStyles';

/** 不预勾选同意，不在协议页提前申请相机。接受必须由用户明确点击。 */
@Component
export struct ConsentView {
  @Prop busy: boolean = false;
  @Prop message: string = '';
  onLegal: (kind: string) => void = (_kind: string): void => {};
  onAccept: () => void = (): void => {};
  onDecline: () => void = (): void => {};

  build() {
    Scroll() {
      Column({ space: 24 }) {
        Column({ space: 16 }) {
          Stack({ alignContent: Alignment.Center }) {
            Rect().width(68).height(80).radius(20).fill(Color.Transparent).stroke(Theme.LINE).strokeWidth(1)
            SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(30).fontColor([Theme.INK])
          }.width(80).height(88)
          Text('每日贴纸').fontSize(Theme.BRAND_TITLE_SIZE).fontWeight(FontWeight.Bold).fontColor(Theme.INK)
          Text('拍下真实的东西，\n贴进每天的生活。').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
            .textAlign(TextAlign.Center)
          Text('照片、贴纸和纸面保存在本机。\n拍照时才申请相机权限，相册只读取你选中的图片。')
            .attributeModifier(new PaperCaptionStyle()).textAlign(TextAlign.Center).margin({ top: 8 })
        }.width('100%').padding(24).backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
          .borderRadius(Theme.CARD_RADIUS)
        Column({ space: 12 }) {
          Text('开始前，请阅读并接受').attributeModifier(new PaperCaptionStyle())
          Row({ space: 4 }) {
            Button('隐私政策', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('link'))
              .enabled(!this.busy).onClick((): void => this.onLegal('privacy'))
            Text('与').attributeModifier(new PaperCaptionStyle())
            Button('用户服务协议', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('link'))
              .enabled(!this.busy).onClick((): void => this.onLegal('terms'))
          }
          if (this.message.length > 0) {
            Text(this.message).attributeModifier(new PaperCaptionStyle()).fontColor(Theme.ACCENT).textAlign(TextAlign.Center)
          }
          Button(this.busy ? '正在保存…' : '同意并开始', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('primary'))
            .width('100%').constraintSize({ minHeight: Theme.ACTION_HEIGHT }).enabled(!this.busy)
            .borderRadius(Theme.ACTION_RADIUS)
            .onClick((): void => this.onAccept())
          Button('暂不使用', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('quiet'))
            .enabled(!this.busy).onClick((): void => this.onDecline())
        }.width('100%')
      }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 32, bottom: 24 })
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(Theme.PAPER)
  }
}
