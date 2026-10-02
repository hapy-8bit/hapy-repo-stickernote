import { StickerAsset, StickerRevision, StickerStore } from '../domain/StickerModels';
import { DateTools } from '../domain/DateTools';
import { StickerViewModels } from './StickerViewModels';
import { Theme } from './Theme';
import { PaperBrandStyle, PaperCaptionStyle, PaperIconStyle } from './PaperStyles';
import { PaperEmptyState } from './PaperEmptyState';

/** 归档检索只读取资产；点“贴入”复用原资产，不复制源图。 */
@Component
export struct StickerLibrary {
  @Prop store: StickerStore = { schemaVersion: 2, assets: [], revisions: [], placements: [], categories: [] };
  @Prop paperColor: string = Theme.PAPER;
  @Prop busy: boolean = false;
  @Prop selectedDate: string = '';
  // 筛选由入口持有，切到今日或设置再返回时仍保留用户正在找的贴纸。
  @Link query: string;
  @Link category: string;
  @Link favoritesOnly: boolean;
  onOpenAsset: (id: string) => void = (_id: string): void => {};
  onPlaceAsset: (id: string) => void = (_id: string): void => {};
  onToggleFavorite: (id: string) => void = (_id: string): void => {};
  onManageCategories: () => void = (): void => {};
  onSettings: () => void = (): void => {};
  onCamera: () => void = (): void => {};

  private items(): StickerAsset[] {
    const query: string = this.query.trim().toLocaleLowerCase();
    return this.store.assets.filter((asset: StickerAsset): boolean =>
      (!this.favoritesOnly || asset.favorite) && (this.category.length === 0 || asset.category === this.category) &&
      (query.length === 0 || `${asset.title} ${asset.category}`.toLocaleLowerCase().includes(query)))
      .sort((left: StickerAsset, right: StickerAsset): number => right.createdAt - left.createdAt);
  }

  private image(asset: StickerAsset): string {
    const value: StickerRevision | undefined = StickerViewModels.latest(this.store, asset.id);
    return value === undefined ? '' : value.imagePath;
  }

  private title(asset: StickerAsset): string {
    return asset.title.length > 0 ? asset.title : '未命名贴纸';
  }

  private clearFilters(): void {
    this.query = ''; this.category = ''; this.favoritesOnly = false;
  }

  build() {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text('贴纸盒').attributeModifier(new PaperBrandStyle())
          Text(`${this.store.assets.length} 张生活贴纸 · 慢慢收集喜欢的东西`)
            .attributeModifier(new PaperCaptionStyle()).width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.gearshape')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
        }.attributeModifier(new PaperIconStyle())
          .enabled(!this.busy).onClick((): void => this.onSettings()).accessibilityText('设置')
      }.width('100%').constraintSize({ minHeight: Theme.HEADER_HEIGHT })
        .padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 20, bottom: 16 })
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(Theme.SMALL_ICON_SIZE).fontColor([Theme.MUTED])
        TextInput({ text: this.query, placeholder: '找贴纸，或找分类' }).fontSize(Theme.BODY_SIZE).fontColor(Theme.INK)
          .placeholderColor(Theme.MUTED).height(Theme.CONTROL_HEIGHT).padding({ left: 0, right: 0 })
          .backgroundColor(Color.Transparent).layoutWeight(1).accessibilityText('搜索贴纸名称或分类')
          .onChange((value: string): void => { this.query = value; })
      }.width(`calc(100% - ${Theme.PAGE_GUTTER * 2}vp)`).height(Theme.CONTROL_HEIGHT)
        .padding({ left: 14, right: 14 }).backgroundColor(Theme.CARD).borderRadius(Theme.CONTROL_RADIUS)
        .border({ width: 0.5, color: Theme.LINE })
      this.filters()
      Column({ space: 0 }) {
        Row() {
          Text(`贴入${DateTools.label(this.selectedDate.length > 0 ? this.selectedDate : DateTools.key())}`)
            .attributeModifier(new PaperCaptionStyle())
          Blank()
          Text(`${this.items().length} 张`).attributeModifier(new PaperCaptionStyle())
        }.width('100%').padding({ top: 17, bottom: 8, left: 20, right: 20 })
        if (this.items().length === 0) {
          this.emptyState()
        } else {
          Grid() {
            ForEach(this.items(), (asset: StickerAsset) => {
              GridItem() { this.tile(asset) }
            }, (asset: StickerAsset): string => asset.id)
          }.columnsTemplate('1fr 1fr').columnsGap(16).rowsGap(18).width('100%').layoutWeight(1)
            .padding({ left: 16, right: 16, top: 8, bottom: 24 }).scrollBar(BarState.Off)
        }
      }.width(`calc(100% - ${Theme.PAPER_GUTTER * 2}vp)`).layoutWeight(1)
        .backgroundColor(Theme.CARD).borderRadius(Theme.CARD_RADIUS).border({ width: 0.5, color: Theme.LINE }).clip(true)
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }

  @Builder
  private filters() {
    Row({ space: 8 }) {
      Scroll() {
        Row({ space: 8 }) {
          this.filter('全部', this.category.length === 0 && !this.favoritesOnly,
            (): void => { this.category = ''; this.favoritesOnly = false; })
          this.filter('收藏', this.favoritesOnly, (): void => { this.favoritesOnly = !this.favoritesOnly; })
          ForEach(this.store.categories, (name: string) => {
            this.filter(name, this.category === name, (): void => { this.category = this.category === name ? '' : name; })
          }, (name: string): string => name)
        }
      }.layoutWeight(1).scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.slider_horizontal_2')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
      }.attributeModifier(new PaperIconStyle())
        .enabled(!this.busy).onClick((): void => this.onManageCategories()).accessibilityText('管理分类')
    }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8, bottom: 12 })
  }

  @Builder
  private filter(label: string, selected: boolean, action: () => void) {
    Button(label, { type: ButtonType.Normal }).fontSize(Theme.CAPTION_SIZE)
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(selected ? Theme.CARD : Theme.MUTED).backgroundColor(selected ? Theme.INK : Color.Transparent)
      .height(Theme.CONTROL_HEIGHT).constraintSize({ minWidth: Theme.CONTROL_HEIGHT })
      .padding({ left: 14, right: 14 }).borderRadius(22).enabled(!this.busy).onClick((): void => action())
  }

  @Builder
  private emptyState() {
    PaperEmptyState({ title: this.store.assets.length === 0 ? '把喜欢的东西装进来' : '还没有找到这张贴纸',
      description: this.store.assets.length === 0 ? '拍下身边的一件小东西，\n贴进今天，也留在贴纸盒。' : '试试其他分类，或换个搜索词。',
      icon: $r('sys.symbol.square_grid_2x2'), actionLabel: this.store.assets.length === 0 ? '拍一张贴纸' : '清除筛选',
      busy: this.busy, onAction: (): void => {
        if (this.store.assets.length === 0) this.onCamera();
        else this.clearFilters();
      } }).layoutWeight(1)
  }

  @Builder
  private tile(asset: StickerAsset) {
    Column({ space: 10 }) {
      Button({ type: ButtonType.Normal }) {
        Stack({ alignContent: Alignment.Center }) {
          if (this.image(asset).length > 0) {
            Image(`file://${this.image(asset)}`).width('100%').height('100%').padding(6).objectFit(ImageFit.Contain)
          } else {
            Text('图片暂不可用').attributeModifier(new PaperCaptionStyle())
          }
        }.width('100%').aspectRatio(1)
      }.width('100%').aspectRatio(1).padding(0).borderRadius(Theme.CONTROL_RADIUS).backgroundColor(Color.Transparent)
        .enabled(!this.busy).accessibilityText(`打开${this.title(asset)}，重新制作`)
        .onClick((): void => this.onOpenAsset(asset.id))
      Column({ space: 5 }) {
        Text(this.title(asset)).fontSize(Theme.BODY_SIZE).fontWeight(FontWeight.Medium).fontColor(Theme.INK)
          .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(asset.category).attributeModifier(new PaperCaptionStyle()).width('100%').maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').alignItems(HorizontalAlign.Start)
      Row() {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph(asset.favorite ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
            .fontSize(Theme.ICON_SIZE).fontColor([asset.favorite ? Theme.ACCENT : Theme.MUTED])
        }.attributeModifier(new PaperIconStyle())
          .enabled(!this.busy).accessibilityText(asset.favorite ? '取消收藏' : '收藏贴纸')
          .onClick((): void => this.onToggleFavorite(asset.id))
        Blank()
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
        }.attributeModifier(new PaperIconStyle(Theme.SOFT))
          .enabled(!this.busy).accessibilityText(`将${this.title(asset)}贴入所选日期`)
          .onClick((): void => this.onPlaceAsset(asset.id))
      }.width('100%')
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
