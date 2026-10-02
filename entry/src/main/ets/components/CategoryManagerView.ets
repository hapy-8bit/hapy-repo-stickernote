import { PaperTopBar } from './PaperTopBar';
import { PaperActionStyle, PaperBodyStyle, PaperCaptionStyle } from './PaperStyles';
import { Theme } from './Theme';

/** 分类改名/删除会涉及资产索引，由上层仓库统一提交；此处仅收集名称。 */
@Component
export struct CategoryManagerView {
  @Prop categories: string[] = [];
  @Prop paperColor: string = Theme.PAPER;
  @Prop busy: boolean = false;
  @Prop message: string = '';
  onBack: () => void = (): void => {};
  onAdd: (name: string) => void = (_name: string): void => {};
  onRename: (oldName: string, newName: string) => void = (_oldName: string, _newName: string): void => {};
  onRemove: (name: string) => void = (_name: string): void => {};
  onMove: (name: string, direction: number) => void = (_name: string, _direction: number): void => {};
  @State private name: string = '';
  @State private editingName: string = '';

  build() {
    Column({ space: 0 }) {
      PaperTopBar({ title: '分类', subtitle: '可以慢慢整理，也可以一直未分类', busy: this.busy,
        onBack: (): void => this.onBack() })
      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 16 }) {
            Row({ space: 12 }) {
              TextInput({ text: this.name, placeholder: this.editingName.length > 0 ? '新的分类名称' : '添加一个分类' })
                .layoutWeight(1).height(Theme.INPUT_HEIGHT).fontSize(Theme.BODY_SIZE).fontColor(Theme.INK)
                .backgroundColor(Theme.SOFT).placeholderColor(Theme.MUTED).borderRadius(Theme.CONTROL_RADIUS)
                .maxLength(20).enabled(!this.busy)
                .onChange((value: string): void => { this.name = value; })
              Button(this.editingName.length > 0 ? '改名' : '添加', { type: ButtonType.Normal })
                .attributeModifier(new PaperActionStyle('primary')).constraintSize({ minHeight: Theme.ACTION_HEIGHT })
                .borderRadius(Theme.ACTION_RADIUS)
                .enabled(!this.busy && this.name.trim().length > 0)
                .onClick((): void => {
                  if (this.editingName.length > 0) this.onRename(this.editingName, this.name.trim());
                  else this.onAdd(this.name.trim());
                  this.name = ''; this.editingName = '';
                })
            }.width('100%')
            if (this.editingName.length > 0) {
              Button('取消改名', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('quiet'))
                .onClick((): void => { this.editingName = ''; this.name = ''; })
            }
            if (this.message.length > 0) {
              Text(this.message).attributeModifier(new PaperBodyStyle()).fontColor(Theme.ACCENT).width('100%')
            }
            ForEach(this.categories, (name: string, index: number) => {
              Column({ space: 12 }) {
                Row({ space: 8 }) {
                  Text(name).attributeModifier(new PaperBodyStyle()).fontWeight(FontWeight.Medium).layoutWeight(1)
                  if (name === '未分类') {
                    Text('默认').attributeModifier(new PaperCaptionStyle())
                  }
                }.width('100%')
                if (name !== '未分类') {
                  Row({ space: 8 }) {
                    Button('改名', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle()).layoutWeight(1)
                      .padding({ left: 0, right: 0 }).enabled(!this.busy)
                      .onClick((): void => { this.editingName = name; this.name = name; })
                    Button('上移', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle()).layoutWeight(1)
                      .padding({ left: 0, right: 0 }).enabled(!this.busy && index > 1)
                      .onClick((): void => this.onMove(name, -1))
                    Button('下移', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle()).layoutWeight(1)
                      .padding({ left: 0, right: 0 }).enabled(!this.busy && index < this.categories.length - 1)
                      .onClick((): void => this.onMove(name, 1))
                    Button('删除', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('danger')).layoutWeight(1)
                      .padding({ left: 0, right: 0 }).enabled(!this.busy).onClick((): void => this.onRemove(name))
                  }.width('100%')
                }
              }.width('100%').padding({ top: 8, bottom: 16 })
                .border({ width: { bottom: 0.5 }, color: Theme.LINE }).alignItems(HorizontalAlign.Start)
            }, (name: string): string => name)
          }.width('100%').padding(20).backgroundColor(Theme.CARD).border({ width: 0.5, color: Theme.LINE })
            .borderRadius(Theme.CARD_RADIUS).alignItems(HorizontalAlign.Start)
          Text('删除分类前会说明影响；贴纸本身不会因为整理分类而被删除。')
            .attributeModifier(new PaperCaptionStyle()).width('100%')
        }.width('100%').padding({ left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER, top: 8, bottom: 24 })
          .alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').scrollBar(BarState.Off)
    }.width('100%').height('100%').backgroundColor(this.paperColor)
  }
}
