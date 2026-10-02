import { StickerAsset, StickerRecipe, StickerRevision } from '../domain/StickerModels';
import { StickerFactory } from '../domain/StickerFactory';
import { DateTools } from '../domain/DateTools';
import { centeredCropForDisplay, NormalizedStickerCrop } from '../domain/StickerCrop';
import { PaperTopBar } from './PaperTopBar';
import { StickerPreview } from './StickerPreview';
import { Theme } from './Theme';
import { PaperActionStyle, PaperChoiceStyle, PaperBodyStyle, PaperCaptionStyle } from './PaperStyles';

/** 图像计算完全由上层服务执行。页面只提交配方和文字，不把预览变换冒充已保存结果。 */
@Component
export struct StickerWorkbench {
  @Prop asset: StickerAsset = {
    id: '', sourcePath: '', sourceType: '', width: 0, height: 0, title: '', note: '', category: '未分类',
    favorite: false, createdAt: 0, updatedAt: 0
  };
  @Prop revision: StickerRevision = {
    id: '', assetId: '', maskPath: '', imagePath: '', width: 0, height: 0,
    recipe: StickerFactory.defaultRecipe(), createdAt: 0
  };
  @Prop @Watch('syncRecipe') recipe: StickerRecipe = StickerFactory.defaultRecipe();
  @Prop subjectCount: number = 0;
  /** 传入会话母版尺寸；legacy 的资产尺寸未知，成品尺寸不可充当源裁切坐标。 */
  @Prop sourceWidth: number = 0;
  @Prop sourceHeight: number = 0;
  @Prop categories: string[] = ['未分类'];
  @Prop @Watch('syncAfterProcessing') busy: boolean = false;
  @Prop message: string = '';
  @Prop canRemake: boolean = false;
  @Prop canDelete: boolean = false;
  @Prop note: string = '';
  @Prop selectedDate: string = '';
  @Prop paperColor: string = Theme.PAPER;
  onRecipeChange: (value: StickerRecipe) => void = (_value: StickerRecipe): void => {};
  onSave: (title: string, category: string, note: string, placeOnDay: boolean) => void =
    (_title: string, _category: string, _note: string, _placeOnDay: boolean): void => {};
  onBack: () => void = (): void => {};
  onRetake: () => void = (): void => {};
  onDraftChange: (title: string, category: string, note: string) => void =
    (_title: string, _category: string, _note: string): void => {};
  onDelete: () => void = (): void => {};
  onFavorite: () => void = (): void => {};
  @State private draftTitle: string = '';
  @State private draftCategory: string = '未分类';
  @State private draftNote: string = '';
  @State private borderValue: number = 8;
  @State private toolTab: string = '图像';
  @State private transformExpanded: boolean = false;

  aboutToAppear(): void {
    this.draftTitle = this.asset.title;
    this.draftCategory = this.asset.category;
    this.draftNote = this.note;
    this.borderValue = this.recipe.borderWidth;
  }

  private syncRecipe(): void { this.borderValue = this.recipe.borderWidth; }
  private syncAfterProcessing(): void {
    // 失败时上层保留旧配方，标签也恢复为真实预览值，避免显示未成功的白边宽度。
    if (!this.busy) this.borderValue = this.recipe.borderWidth;
  }

  private subjects(): number[] {
    const values: number[] = [];
    for (let index: number = 0; index < this.subjectCount; index++) values.push(index);
    return values;
  }

  private mode(value: string): void {
    const next: StickerRecipe = StickerFactory.copyRecipe(this.recipe);
    next.mode = value;
    this.onRecipeChange(next);
  }

  private subject(index: number): void {
    const next: StickerRecipe = StickerFactory.copyRecipe(this.recipe);
    next.subjectIndex = index; next.mode = 'subject';
    this.onRecipeChange(next);
  }

  private rotatePhoto(): void {
    const next: StickerRecipe = StickerFactory.copyRecipe(this.recipe);
    next.rotation = (next.rotation + 90) % 360;
    this.onRecipeChange(next);
  }

  private flip(): void {
    const next: StickerRecipe = StickerFactory.copyRecipe(this.recipe);
    next.flipHorizontal = !next.flipHorizontal;
    this.onRecipeChange(next);
  }

  private crop(ratio: number): void {
    const next: StickerRecipe = StickerFactory.copyRecipe(this.recipe);
    const rectangle: NormalizedStickerCrop = centeredCropForDisplay(this.inputWidth(), this.inputHeight(),
      ratio, this.recipe.rotation);
    next.cropX = rectangle.x; next.cropY = rectangle.y;
    next.cropWidth = rectangle.width; next.cropHeight = rectangle.height;
    this.onRecipeChange(next);
  }

  private inputWidth(): number { return this.sourceWidth > 0 ? this.sourceWidth : this.asset.width; }
  private inputHeight(): number { return this.sourceHeight > 0 ? this.sourceHeight : this.asset.height; }
  private canCropRatio(): boolean { return this.inputWidth() > 0 && this.inputHeight() > 0; }

  private cropSelected(ratio: number): boolean {
    const fullFrame: boolean = this.recipe.cropX === 0 && this.recipe.cropY === 0 &&
      this.recipe.cropWidth === 1 && this.recipe.cropHeight === 1;
    if (fullFrame) return ratio === 0;
    if (ratio === 0) return false;
    const rectangle: NormalizedStickerCrop = centeredCropForDisplay(this.inputWidth(), this.inputHeight(),
      ratio, this.recipe.rotation);
    return Math.abs(this.recipe.cropX - rectangle.x) < 0.0001 &&
      Math.abs(this.recipe.cropY - rectangle.y) < 0.0001 &&
      Math.abs(this.recipe.cropWidth - rectangle.width) < 0.0001 &&
      Math.abs(this.recipe.cropHeight - rectangle.height) < 0.0001;
  }

  build() {
    Column({ space: 0 }) {
      PaperTopBar({ title: this.canDelete ? '重新制作' : '制作贴纸', subtitle: '先留下，再慢慢命名', busy: this.busy,
        onBack: (): void => this.onBack() })
      Scroll() {
        Column({ space: 16 }) {
          this.preview()
          if (this.message.length > 0) {
            Text(this.message).attributeModifier(new PaperCaptionStyle()).fontColor(Theme.ACCENT).width('100%')
          }
          if (this.asset.sourceType === 'legacy') {
            Text('这张旧贴纸只保留了成品。可以调整方向和裁切，但无法重新选择主体或去掉已经画入的白边。')
              .attributeModifier(new PaperCaptionStyle()).width('100%')
          }
          this.toolPaper()
        }.width('100%').alignItems(HorizontalAlign.Start)
          .padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8, bottom: 24 })
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
      this.saveBar()
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }

  @Builder
  private preview() {
    Column({ space: 4 }) {
      StickerPreview({ imagePath: this.revision.imagePath, busy: this.busy, paperColor: this.paperColor })
      Row({ space: 12 }) {
        Text(this.recipe.mode === 'subject' ? '透明主体' : '完整照片').attributeModifier(new PaperCaptionStyle())
          .layoutWeight(1)
        Button('重拍 / 换图', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('quiet'))
          .padding({ left: 12, right: 0, top: 10, bottom: 10 })
          .enabled(!this.busy).onClick((): void => {
            this.onDraftChange(this.draftTitle, this.draftCategory, this.draftNote); this.onRetake();
          })
      }.width('100%')
    }.width('100%')
  }

  @Builder
  private toolPaper() {
    Column({ space: 18 }) {
      Row() {
        this.toolTabButton('图像')
        this.toolTabButton('白边')
        this.toolTabButton('信息')
      }.width('100%')
      if (this.toolTab === '图像') this.imageTools()
      else if (this.toolTab === '白边') this.borderTools()
      else this.textTools()
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 16, right: 16, top: 8, bottom: 20 })
      .backgroundColor(Theme.CARD).borderRadius(Theme.TOOL_RADIUS).border({ width: 0.5, color: Theme.LINE })
  }

  @Builder
  private toolTabButton(label: string) {
    Button(label, { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('quiet'))
      .layoutWeight(1).fontColor(this.toolTab === label ? Theme.INK : Theme.MUTED)
      .fontWeight(this.toolTab === label ? FontWeight.Bold : FontWeight.Normal).borderRadius(0)
      .border({ width: { bottom: this.toolTab === label ? 2 : 0.5 }, color: this.toolTab === label ? Theme.INK : Theme.LINE })
      .accessibilityText(`${label}工具${this.toolTab === label ? '，已选中' : ''}`)
      .onClick((): void => { this.toolTab = label; })
  }

  @Builder
  private imageTools() {
    Column({ space: 16 }) {
      Text('制作方式').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
      Row({ space: 10 }) {
        Button('去背景', { type: ButtonType.Normal }).attributeModifier(new PaperChoiceStyle(this.recipe.mode === 'subject'))
          .layoutWeight(1)
          .enabled(!this.busy && this.canRemake && this.subjectCount > 0).onClick((): void => this.mode('subject'))
        Button('保留照片', { type: ButtonType.Normal }).attributeModifier(new PaperChoiceStyle(this.recipe.mode !== 'subject'))
          .layoutWeight(1)
          .enabled(!this.busy).onClick((): void => this.mode('original'))
      }.width('100%')
      if (this.canRemake && this.subjectCount > 0) {
        Column({ space: 10 }) {
          Text('选择主体').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
          Scroll() {
            Row({ space: 8 }) {
              Button('全部主体', { type: ButtonType.Normal }).attributeModifier(new PaperChoiceStyle(this.recipe.subjectIndex === -1))
                .enabled(!this.busy).onClick((): void => this.subject(-1))
              ForEach(this.subjects(), (index: number) => {
                Button(`主体 ${index + 1}`, { type: ButtonType.Normal })
                  .attributeModifier(new PaperChoiceStyle(this.recipe.subjectIndex === index))
                  .enabled(!this.busy).onClick((): void => this.subject(index))
              }, (index: number): string => `${index}`)
            }
          }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text('方向与裁切').attributeModifier(new PaperBodyStyle()).layoutWeight(1)
          Text(this.transformExpanded ? '收起' : '展开').attributeModifier(new PaperCaptionStyle())
        }.width('100%')
      }.attributeModifier(new PaperActionStyle('quiet')).width('100%').padding(0).borderRadius(0)
        .border({ width: { top: 0.5 }, color: Theme.LINE })
        .accessibilityText(`方向与裁切，${this.transformExpanded ? '已展开' : '已收起'}`)
        .onClick((): void => { this.transformExpanded = !this.transformExpanded; })
      if (this.transformExpanded) this.transformTools()
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private transformTools() {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Button('旋转 90°', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle()).layoutWeight(1)
          .enabled(!this.busy).onClick((): void => this.rotatePhoto())
        Button('水平翻转', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle()).layoutWeight(1)
          .enabled(!this.busy).onClick((): void => this.flip())
      }.width('100%')
      Column({ space: 10 }) {
        Text('居中裁切').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
        Row({ space: 10 }) {
          this.cropOption('全幅', 0)
          this.cropOption('正方形', 1)
        }.width('100%')
        Row({ space: 10 }) {
          this.cropOption('横向 4:3', 4 / 3)
          this.cropOption('竖向 3:4', 3 / 4)
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private borderTools() {
    Column({ space: 12 }) {
      Row() {
        Text('轮廓白边').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
        Blank()
        Text(`${Math.round(this.borderValue)} px`).attributeModifier(new PaperCaptionStyle())
      }.width('100%')
      Slider({ value: this.borderValue, min: 0, max: 24, step: 1 }).width('100%')
        .selectedColor(Theme.ACCENT).trackColor(Theme.LINE).blockColor(Theme.CARD)
        .accessibilityText('轮廓白边宽度')
        .enabled(!this.busy && this.asset.sourceType !== 'legacy')
        .onChange((value: number, mode: SliderChangeMode): void => {
          this.borderValue = value;
          if (mode !== SliderChangeMode.End && mode !== SliderChangeMode.Click) return;
          const next: StickerRecipe = StickerFactory.copyRecipe(this.recipe);
          next.borderWidth = value; this.onRecipeChange(next);
        })
      Text(this.asset.sourceType === 'legacy' ? '旧贴纸中的白边已画入成品，无法单独调整。' : '拖动滑块，调整贴纸边缘的留白。')
        .attributeModifier(new PaperCaptionStyle()).width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 8 })
  }

  @Builder
  private cropOption(label: string, ratio: number) {
    Button(label, { type: ButtonType.Normal }).attributeModifier(new PaperChoiceStyle(this.cropSelected(ratio))).layoutWeight(1)
      .enabled(!this.busy && (ratio === 0 || this.canCropRatio())).onClick((): void => this.crop(ratio))
  }

  @Builder
  private textTools() {
    Column({ space: 14 }) {
      Row() {
        Text('贴纸信息').attributeModifier(new PaperBodyStyle()).fontColor(Theme.MUTED)
        Blank()
        Text('可跳过').attributeModifier(new PaperCaptionStyle())
      }.width('100%')
      TextInput({ text: this.draftTitle, placeholder: '给贴纸起个名字 · 可跳过' }).fontSize(Theme.BODY_SIZE)
        .fontColor(Theme.INK).placeholderColor(Theme.MUTED).height(Theme.INPUT_HEIGHT).borderRadius(Theme.CONTROL_RADIUS)
        .backgroundColor(Theme.SOFT).maxLength(60).enabled(!this.busy)
        .onChange((value: string): void => { this.draftTitle = value; })
      Scroll() {
        Row({ space: 7 }) {
          ForEach(this.categories, (name: string) => {
            Button(name, { type: ButtonType.Normal }).attributeModifier(new PaperChoiceStyle(this.draftCategory === name)).enabled(!this.busy)
              .onClick((): void => { this.draftCategory = name; })
          }, (name: string): string => name)
        }
      }.width('100%').scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      TextArea({ text: this.draftNote, placeholder: '贴纸短注记 · 可跳过' }).fontSize(Theme.BODY_SIZE).fontColor(Theme.INK)
        .placeholderColor(Theme.MUTED).backgroundColor(Theme.SOFT).borderRadius(Theme.CONTROL_RADIUS).height(110)
        .maxLength(2000).padding(14).enabled(!this.busy).onChange((value: string): void => { this.draftNote = value; })
      if (this.canDelete) {
        Row({ space: 8 }) {
          Button(this.asset.favorite ? '取消收藏' : '收藏这张贴纸', { type: ButtonType.Normal })
            .attributeModifier(new PaperActionStyle('link')).layoutWeight(1)
            .enabled(!this.busy).onClick((): void => this.onFavorite())
          Button('永久删除', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('danger'))
            .enabled(!this.busy).onClick((): void => this.onDelete())
        }.width('100%').padding({ top: 8 }).border({ width: { top: 0.5 }, color: Theme.LINE })
        Text('保存会生成新的制作版本，其他日期已贴入的版本保持原样。')
          .attributeModifier(new PaperCaptionStyle()).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  @Builder
  private saveBar() {
    Row({ space: 10 }) {
      Button({ type: ButtonType.Normal }) {
        Text('只存贴纸盒').fontSize(Theme.BUTTON_SIZE).fontWeight(FontWeight.Medium)
          .fontColor(Theme.INK).textAlign(TextAlign.Center).width('100%')
      }.attributeModifier(new PaperActionStyle()).constraintSize({ minHeight: Theme.ACTION_HEIGHT }).layoutWeight(1)
        .borderRadius(Theme.ACTION_RADIUS)
        .padding({ left: 10, right: 10, top: 12, bottom: 12 }).enabled(!this.busy && this.revision.imagePath.length > 0)
        .onClick((): void => this.onSave(this.draftTitle.trim(), this.draftCategory, this.draftNote, false))
      Button({ type: ButtonType.Normal }) {
        Text(this.busy ? '正在处理…' : `贴入${DateTools.label(this.selectedDate.length > 0 ? this.selectedDate : DateTools.key())}`)
          .fontSize(Theme.BUTTON_SIZE).fontWeight(FontWeight.Medium)
          .fontColor(Theme.CARD).textAlign(TextAlign.Center).width('100%')
      }.attributeModifier(new PaperActionStyle('primary')).constraintSize({ minHeight: Theme.ACTION_HEIGHT }).layoutWeight(1.25)
        .borderRadius(Theme.ACTION_RADIUS)
        .padding({ left: 10, right: 10, top: 12, bottom: 12 })
        .enabled(!this.busy && this.revision.imagePath.length > 0)
        .onClick((): void => this.onSave(this.draftTitle.trim(), this.draftCategory, this.draftNote, true))
    }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 12, bottom: 16 })
      .backgroundColor(this.paperColor).border({ width: { top: 0.5 }, color: Theme.LINE })
  }
}
