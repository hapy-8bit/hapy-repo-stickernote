import { LegalDocument } from '../legal/LegalDocuments';
import { PaperTopBar } from './PaperTopBar';
import { Theme } from './Theme';
import { PaperBodyStyle, PaperCaptionStyle, PaperEmptyTitleStyle, PaperSectionStyle } from './PaperStyles';

/** 内置文档由提供者加载后注入，阅读页本身不访问网络或文件。 */
@Component
export struct LegalView {
  @Prop document: LegalDocument | undefined = undefined;
  @Prop loading: boolean = false;
  @Prop errorMessage: string = '';
  @Prop paperColor: string = Theme.PAPER;
  onBack: () => void = (): void => {};

  private title(): string { return this.document === undefined ? '协议' : this.document.title; }
  private subtitle(): string {
    return this.document === undefined ? '' : `${this.document.updatedAt} · ${this.document.version}`;
  }
  private paragraphs(): string[] {
    if (this.document === undefined) return [];
    return this.document.body.split(/\n\s*\n/).filter((value: string): boolean => value.trim().length > 0 &&
      !value.startsWith('# ') && !value.startsWith('版本：'));
  }

  build() {
    Column({ space: 0 }) {
      PaperTopBar({ title: this.title(), subtitle: this.subtitle(), onBack: (): void => this.onBack() })
      if (this.loading) {
        Column() {
          Column({ space: 12 }) {
            LoadingProgress().width(32).height(32).color(Theme.ACCENT)
            Text('正在打开协议…').attributeModifier(new PaperCaptionStyle())
          }.width('100%').padding(32).backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
            .borderRadius(Theme.CARD_RADIUS)
        }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8 })
      } else if (this.errorMessage.length > 0) {
        Column() {
          Column({ space: 16 }) {
            Stack({ alignContent: Alignment.Center }) {
              Rect().width(64).height(72).radius(20).fill(Color.Transparent).stroke(Theme.LINE).strokeWidth(1)
              SymbolGlyph($r('sys.symbol.doc_plaintext')).fontSize(28).fontColor([Theme.MUTED])
            }.width(72).height(80)
            Text('协议暂时打不开').attributeModifier(new PaperEmptyTitleStyle())
            Text(this.errorMessage).attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
              .textAlign(TextAlign.Center).width('100%')
          }.width('100%').padding(24).backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
            .borderRadius(Theme.CARD_RADIUS)
        }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8 })
      } else {
        Scroll() {
          Column({ space: 20 }) {
            ForEach(this.paragraphs(), (paragraph: string) => {
              Text(paragraph).attributeModifier(/^[一二三四五六七八九十]+、/.test(paragraph) ?
                new PaperSectionStyle() : new PaperBodyStyle()).width('100%')
                .fontWeight(/^[一二三四五六七八九十]+、/.test(paragraph) ? FontWeight.Medium : FontWeight.Normal)
                .copyOption(CopyOptions.InApp)
            }, (paragraph: string, index: number): string => `${index}`)
          }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
            .backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE }).borderRadius(Theme.CARD_RADIUS)
            .margin({ top: 8, bottom: 24 })
        }.width('100%').layoutWeight(1).scrollBar(BarState.Off)
          .padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER })
      }
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }
}
