import { Theme } from './Theme';

/** 只复用视觉属性；动作、可用状态和选中状态仍由各页面持有。 */
export class PaperActionStyle implements AttributeModifier<ButtonAttribute> {
  private tone: string;

  constructor(tone: string = 'secondary') { this.tone = tone; }

  applyNormalAttribute(button: ButtonAttribute): void {
    button.fontSize(Theme.BUTTON_SIZE).fontWeight(FontWeight.Medium)
      .fontColor(this.tone === 'primary' || this.tone === 'camera' ? Theme.CARD :
        (this.tone === 'link' || this.tone === 'danger' ? Theme.ACCENT :
          (this.tone === 'quiet' ? Theme.MUTED : Theme.INK)))
      .backgroundColor(this.tone === 'primary' ? Theme.INK :
        (this.tone === 'quiet' || this.tone === 'link' || this.tone === 'camera' ? Color.Transparent : Theme.SOFT))
      .constraintSize({ minHeight: Theme.CONTROL_HEIGHT }).borderRadius(Theme.ACTION_RADIUS)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 });
  }
}

export class PaperChoiceStyle implements AttributeModifier<ButtonAttribute> {
  private selected: boolean;

  constructor(selected: boolean) { this.selected = selected; }

  applyNormalAttribute(button: ButtonAttribute): void {
    button.fontSize(Theme.BUTTON_SIZE).fontWeight(FontWeight.Medium)
      .fontColor(Theme.INK).backgroundColor(this.selected ? Theme.SOFT : Theme.CARD)
      .border({ width: 1, color: this.selected ? Theme.INK : Theme.LINE })
      .constraintSize({ minHeight: Theme.CONTROL_HEIGHT }).borderRadius(Theme.CONTROL_RADIUS)
      .padding({ left: 16, right: 16, top: 10, bottom: 10 });
  }
}

export class PaperIconStyle implements AttributeModifier<ButtonAttribute> {
  private background: ResourceColor;

  constructor(background: ResourceColor = Color.Transparent) { this.background = background; }

  applyNormalAttribute(button: ButtonAttribute): void {
    button.width(Theme.CONTROL_HEIGHT).height(Theme.CONTROL_HEIGHT).padding(0)
      .backgroundColor(this.background).borderRadius(Theme.CONTROL_RADIUS);
  }
}

export class PaperTitleStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(text: TextAttribute): void {
    text.fontSize(Theme.PAGE_TITLE_SIZE).fontWeight(FontWeight.Bold).fontColor(Theme.INK);
  }
}

export class PaperBrandStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(text: TextAttribute): void {
    text.fontSize(Theme.BRAND_TITLE_SIZE).fontWeight(FontWeight.Bold).fontColor(Theme.INK);
  }
}

export class PaperEmptyTitleStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(text: TextAttribute): void {
    text.fontSize(Theme.EMPTY_TITLE_SIZE).fontWeight(FontWeight.Bold).fontColor(Theme.INK);
  }
}

export class PaperSectionStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(text: TextAttribute): void {
    text.fontSize(Theme.SECTION_TITLE_SIZE).fontWeight(FontWeight.Medium).fontColor(Theme.INK);
  }
}

export class PaperBodyStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(text: TextAttribute): void {
    text.fontSize(Theme.BODY_SIZE).lineHeight(24).fontColor(Theme.INK);
  }
}

export class PaperCaptionStyle implements AttributeModifier<TextAttribute> {
  applyNormalAttribute(text: TextAttribute): void {
    text.fontSize(Theme.CAPTION_SIZE).lineHeight(20).fontColor(Theme.MUTED);
  }
}
