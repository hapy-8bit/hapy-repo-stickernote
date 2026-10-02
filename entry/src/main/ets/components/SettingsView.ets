import { AppPreferences, LegalDocuments } from '../legal/LegalDocuments';
import { PaperTopBar } from './PaperTopBar';
import { PaperActionStyle, PaperBodyStyle, PaperCaptionStyle, PaperSectionStyle } from './PaperStyles';
import { Theme } from './Theme';

@Component
export struct SettingsView {
  @Prop preferences: AppPreferences = LegalDocuments.defaults();
  @Prop paperColor: string = Theme.PAPER;
  @Prop busy: boolean = false;
  @Prop storageBytes: number = -1;
  @Prop assetCount: number = 0;
  @Prop revisionCount: number = 0;
  @Prop message: string = '';
  onBack: () => void = (): void => {};
  onPreferencesChange: (value: AppPreferences) => void = (_value: AppPreferences): void => {};
  onLegal: (kind: string) => void = (_kind: string): void => {};
  onManageCategories: () => void = (): void => {};
  onStorage: () => void = (): void => {};
  @State private showAbout: boolean = false;
  @State private showContact: boolean = false;

  private paper(style: string): void {
    this.onPreferencesChange({ acceptedVersion: this.preferences.acceptedVersion, paperStyle: style,
      startWithCamera: this.preferences.startWithCamera });
  }

  private camera(value: boolean): void {
    this.onPreferencesChange({ acceptedVersion: this.preferences.acceptedVersion,
      paperStyle: this.preferences.paperStyle, startWithCamera: value });
  }

  private storageLabel(): string {
    if (this.storageBytes < 0) return '读取中';
    if (this.storageBytes < 1024 * 1024) return `${(this.storageBytes / 1024).toFixed(1)} KB`;
    return `${(this.storageBytes / (1024 * 1024)).toFixed(1)} MB`;
  }

  build() {
    Column({ space: 0 }) {
      PaperTopBar({ title: '设置', busy: this.busy, onBack: (): void => this.onBack() })
      Scroll() {
        Column({ space: 20 }) {
          Column({ space: 24 }) {
            this.appearance()
            Divider().color(Theme.LINE).strokeWidth(0.5)
            Column({ space: 12 }) {
              this.sectionTitle('拍摄')
              Row({ space: 12 }) {
                Column({ space: 4 }) {
                  Text('打开即拍照').attributeModifier(new PaperBodyStyle())
                  Text('完成首次同意后，直接进入相机').attributeModifier(new PaperCaptionStyle())
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.preferences.startWithCamera })
                  .selectedColor(Theme.ACCENT).enabled(!this.busy)
                  .onChange((value: boolean): void => this.camera(value))
                  .accessibilityText('打开即拍照')
              }.width('100%').constraintSize({ minHeight: Theme.CONTROL_HEIGHT })
              Text('相机权限只在你使用拍照时申请，拒绝后仍可浏览贴纸或使用相册选择器。')
                .attributeModifier(new PaperCaptionStyle()).width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
            Divider().color(Theme.LINE).strokeWidth(0.5)
            Column({ space: 8 }) {
              this.sectionTitle('贴纸与本机数据')
              Column({ space: 0 }) {
                this.row('分类管理', `${this.assetCount} 张贴纸`, (): void => this.onManageCategories())
                Divider().color(Theme.LINE).strokeWidth(0.5)
                this.row('存储占用', this.storageLabel(), (): void => this.onStorage())
              }.width('100%')
              Text('原图、蒙版和制作版本保存在本机。卸载或清除应用数据可能导致丢失，本机保存不能替代备份。')
                .attributeModifier(new PaperCaptionStyle()).width('100%')
            }.width('100%').alignItems(HorizontalAlign.Start)
            Divider().color(Theme.LINE).strokeWidth(0.5)
            Column({ space: 8 }) {
              this.sectionTitle('关于每日贴纸')
              Column({ space: 0 }) {
                this.row('隐私政策', '', (): void => this.onLegal('privacy'))
                Divider().color(Theme.LINE).strokeWidth(0.5)
                this.row('用户服务协议', '', (): void => this.onLegal('terms'))
                Divider().color(Theme.LINE).strokeWidth(0.5)
                this.row('联系开发者', '', (): void => { this.showContact = !this.showContact; }, this.showContact)
                if (this.showContact) {
                  Column({ space: 8 }) {
                    Text(`${LegalDocuments.DEVELOPER}\n${LegalDocuments.CONTACT_EMAIL}`).attributeModifier(new PaperBodyStyle())
                      .copyOption(CopyOptions.InApp).width('100%')
                    Text('反馈时请附设备型号、系统和应用版本；不要发送密码、验证码或不必要的私人照片。')
                      .attributeModifier(new PaperCaptionStyle()).width('100%')
                  }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 12 })
                }
                Divider().color(Theme.LINE).strokeWidth(0.5)
                this.row('关于与版本', '0.1.0', (): void => { this.showAbout = !this.showAbout; }, this.showAbout)
                if (this.showAbout) {
                  Text('每日贴纸\n拍下真实的东西，贴进每天的生活。\n版本 0.1.0 · 构建 100000\ncom.lh.stickernote')
                    .attributeModifier(new PaperCaptionStyle()).width('100%').padding({ bottom: 12 })
                }
              }.width('100%').alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(HorizontalAlign.Start)
          }.width('100%').padding(20).backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
            .borderRadius(Theme.CARD_RADIUS).alignItems(HorizontalAlign.Start)
          if (this.message.length > 0) {
            Text(this.message).attributeModifier(new PaperCaptionStyle()).fontColor(Theme.ACCENT).width('100%')
              .padding(16).backgroundColor(Theme.SOFT).borderRadius(Theme.TOOL_RADIUS)
          }
          Text('你的贴纸，由你留下。').attributeModifier(new PaperCaptionStyle()).width('100%')
            .textAlign(TextAlign.Center).margin({ bottom: 8 })
        }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.TopStart)
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }

  @Builder
  private appearance() {
    Column({ space: 12 }) {
      this.sectionTitle('纸面')
      Column({ space: 16 }) {
        Text('选一张喜欢的纸，留下每天的贴纸。').attributeModifier(new PaperCaptionStyle()).width('100%')
        Row({ space: 10 }) {
          ForEach(Theme.PAPER_STYLES, (style: string) => {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 8 }) {
                Stack() {
                  Rect().width('100%').height(64).fill(Theme.paperColor(style)).borderRadius(Theme.CONTROL_RADIUS)
                  if (this.preferences.paperStyle === style) {
                    SymbolGlyph($r('sys.symbol.checkmark')).fontSize(Theme.ICON_SIZE).fontColor([Theme.ACCENT])
                  }
                }.width('100%').height(64)
                  .border({ width: this.preferences.paperStyle === style ? 1.5 : 0.5,
                    color: this.preferences.paperStyle === style ? Theme.ACCENT : Theme.LINE })
                  .borderRadius(Theme.CONTROL_RADIUS).clip(true)
                Text(Theme.paperLabel(style)).attributeModifier(new PaperBodyStyle()).fontWeight(FontWeight.Medium)
                  .fontColor(this.preferences.paperStyle === style ? Theme.ACCENT : Theme.INK)
              }.width('100%')
            }.attributeModifier(new PaperActionStyle('quiet')).layoutWeight(1).padding(0).enabled(!this.busy)
              .accessibilityText(`${Theme.paperLabel(style)}${this.preferences.paperStyle === style ? '，当前使用' : ''}`)
              .onClick((): void => this.paper(style))
          }, (style: string): string => style)
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private sectionTitle(value: string) {
    Text(value).attributeModifier(new PaperSectionStyle())
  }

  @Builder
  private row(title: string, detail: string, action: () => void, expanded: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 10 }) {
        Text(title).attributeModifier(new PaperBodyStyle()).layoutWeight(1)
        if (detail.length > 0) Text(detail).attributeModifier(new PaperCaptionStyle())
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(Theme.SMALL_ICON_SIZE).fontColor([Theme.MUTED])
          .rotate({ angle: expanded ? 90 : 0 })
      }.width('100%').padding({ top: 16, bottom: 16 })
    }.attributeModifier(new PaperActionStyle('quiet')).width('100%').padding(0).enabled(!this.busy)
      .onClick((): void => action())
  }
}
