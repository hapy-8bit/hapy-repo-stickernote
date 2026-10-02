import { common } from '@kit.AbilityKit';
import { CameraSession, CameraViewState } from '../camera/CameraSession';
import { CameraPhotoFiles } from '../camera/CameraPhotoFiles';
import { ImmersiveWindowController } from '../platform/ImmersiveWindowController';
import { Theme } from './Theme';
import { PaperActionStyle, PaperIconStyle, PaperBodyStyle, PaperCaptionStyle } from './PaperStyles';

@Component
export struct CameraView {
  @Prop paperColor: string = Theme.PAPER;
  onCapture: (privatePhotoPath: string) => void = () => {};
  onClose: () => void = () => {};
  onGallery: () => void = () => {};
  @StorageLink('stickerTopInset') topInset: number = 0;
  @StorageLink('stickerBottomInset') bottomInset: number = 0;
  @StorageLink('stickerAppForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State ready: boolean = false;
  @State busy: boolean = false;
  @State message: string = '正在启动相机…';
  @State canSwitch: boolean = false;
  @State flash: string = '关闭';
  @State previewRatio: number = 0.75;
  @State zoomRatio: number = 1.0;
  @State minZoom: number = 1.0;
  @State maxZoom: number = 6.0;
  @State isZooming: boolean = false;
  @State viewportWidth: number = 360;
  @State viewportHeight: number = 780;
  private controller: XComponentController = new XComponentController();
  private session: CameraSession | undefined = undefined;
  private surfaceId: string = '';
  private mounted: boolean = false;
  private leaving: boolean = false;
  private baseZoom: number = 1.0;
  private zoomTimer: number = -1;

  aboutToAppear(): void {
    this.mounted = true;
    this.leaving = false;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.session = new CameraSession(context, (state: CameraViewState) => {
      if (!this.mounted) { return; }
      this.ready = state.ready;
      this.busy = state.busy;
      this.message = state.message;
      this.canSwitch = state.canSwitch;
      this.flash = state.flash;
      this.previewRatio = state.previewRatio;
      this.zoomRatio = state.zoomRatio;
      this.minZoom = state.minZoom;
      this.maxZoom = state.maxZoom;
    });
    // The system bars now sit on the paper surround, outside the dark viewfinder.
    ImmersiveWindowController.setCameraAppearance(false);
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.leaving = true;
    if (this.zoomTimer !== -1) {
      clearTimeout(this.zoomTimer);
      this.zoomTimer = -1;
    }
    this.session?.stop().catch(() => {});
    ImmersiveWindowController.setCameraAppearance(false);
  }

  private foregroundChanged(): void {
    if (!this.mounted || this.leaving) { return; }
    if (!this.foreground) {
      this.session?.stop().catch(() => {});
    } else if (this.surfaceId.length > 0) {
      this.session?.start(this.surfaceId).catch(() => {});
    }
  }

  private retry(): void {
    if (this.foreground && this.surfaceId.length > 0 && !this.leaving) {
      this.session?.start(this.surfaceId).catch(() => {});
    }
  }

  private async exit(gallery: boolean): Promise<void> {
    if (this.leaving) { return; }
    this.leaving = true;
    await this.session?.stop();
    ImmersiveWindowController.setCameraAppearance(false);
    if (!this.mounted) { return; }
    if (gallery) { this.onGallery(); } else { this.onClose(); }
  }

  private async shoot(): Promise<void> {
    if (!this.ready || this.busy || this.session === undefined || this.leaving) { return; }
    try {
      const path = await this.session.capture();
      if (!this.mounted || this.leaving || !this.foreground) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await new CameraPhotoFiles(context.filesDir).discard(path);
        return;
      }
      this.leaving = true;
      await this.session.stop();
      ImmersiveWindowController.setCameraAppearance(false);
      if (!this.mounted || !this.foreground) {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        await new CameraPhotoFiles(context.filesDir).discard(path);
        return;
      }
      // The caller receives a complete private JPEG, never an Image/Surface or external URI.
      this.onCapture(path);
    } catch (error) {
      if (this.mounted && !this.leaving) {
        this.message = error instanceof Error ? error.message : '拍摄失败，请重试。';
      }
    }
  }

  private showZoomIndicator(): void {
    this.isZooming = true;
    if (this.zoomTimer !== -1) {
      clearTimeout(this.zoomTimer);
      this.zoomTimer = -1;
    }
  }

  private scheduleHideZoomIndicator(): void {
    if (this.zoomTimer !== -1) {
      clearTimeout(this.zoomTimer);
    }
    this.zoomTimer = setTimeout(() => {
      this.isZooming = false;
      this.zoomTimer = -1;
    }, 1500);
  }

  private applyZoom(ratio: number): void {
    const clamped = Math.max(this.minZoom, Math.min(this.maxZoom, ratio));
    this.session?.setZoomRatio(clamped);
    this.showZoomIndicator();
  }

  private zoomPresets(): number[] {
    const candidates: number[] = [0.6, 1.0, 2.0, 3.0, 5.0];
    const result: number[] = [];
    for (let i = 0; i < candidates.length; i++) {
      const p = candidates[i];
      if (p >= this.minZoom && p <= this.maxZoom) {
        result.push(p);
      }
    }
    if (result.length === 0) {
      result.push(1.0);
    }
    return result;
  }

  private formatZoom(ratio: number): string {
    return ratio % 1 === 0 ? `${ratio.toFixed(0)}×` : `${ratio.toFixed(1)}×`;
  }

  private previewWidth(): number {
    return Math.max(this.viewportWidth, this.viewportHeight * this.previewRatio);
  }

  @Builder
  private zoomBar() {
    Row({ space: 8 }) {
      ForEach(this.zoomPresets(), (preset: number) => {
        Button(this.formatZoom(preset), { type: ButtonType.Normal })
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Math.abs(this.zoomRatio - preset) < 0.15 ? Theme.INK : Theme.CARD)
          .backgroundColor(Math.abs(this.zoomRatio - preset) < 0.15 ? Theme.CARD : '#4D332F29')
          .height(28)
          .padding({ left: 10, right: 10, top: 0, bottom: 0 })
          .borderRadius(14)
          .enabled(this.ready && !this.busy)
          .onClick(() => {
            this.applyZoom(preset);
            this.scheduleHideZoomIndicator();
          })
          .accessibilityText(`放大倍数 ${this.formatZoom(preset)}`)
      }, (preset: number) => preset.toString())
    }
    .padding({ left: 8, right: 8, top: 4, bottom: 4 })
    .backgroundColor('#66332F29')
    .borderRadius(Theme.TOOL_RADIUS)
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal })
        .onActionStart(() => {
          if (!this.ready || this.busy) { return; }
          this.baseZoom = this.zoomRatio;
          this.showZoomIndicator();
        })
        .onActionUpdate((event: GestureEvent) => {
          if (!this.ready || this.busy) { return; }
          const span = Math.max(1, this.maxZoom - this.minZoom);
          const delta = (event.offsetX / 160) * span;
          this.applyZoom(this.baseZoom + delta);
        })
        .onActionEnd(() => { this.scheduleHideZoomIndicator(); })
        .onActionCancel(() => { this.scheduleHideZoomIndicator(); })
    )
  }

  @Builder
  private viewfinder() {
    Stack({ alignContent: Alignment.Center }) {
      XComponent({ id: 'sticker-camera-preview', type: XComponentType.SURFACE, controller: this.controller })
        .width(this.previewWidth())
        .height(this.previewWidth() / this.previewRatio)
        .onLoad(() => {
          this.surfaceId = this.controller.getXComponentSurfaceId();
          this.retry();
        })
        .onDestroy(() => {
          this.surfaceId = '';
          this.session?.stop().catch(() => {});
        })

      if (this.ready && this.message.length === 0) {
        // A composition guide only: capture still hands off the complete private JPEG.
        Rect().width(this.viewportWidth * 0.76)
          .height(Math.min(this.viewportHeight * 0.54, this.viewportWidth * 0.9))
          .radius(Theme.TOOL_RADIUS).fill(Color.Transparent).stroke('#80FFFDF8').strokeWidth(1)
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }

      Column() {
        Text('把主体变成贴纸').attributeModifier(new PaperCaptionStyle()).fontColor(Theme.PAPER).maxLines(1)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor('#66332F29').borderRadius(Theme.ACTION_RADIUS)
        Blank()
        if (this.message.length > 0) {
          Column({ space: 16 }) {
            Text(this.message).attributeModifier(new PaperBodyStyle()).fontColor(Theme.CARD).textAlign(TextAlign.Center).maxLines(5)
            if (!this.ready && !this.busy) {
              Button('重试', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('camera')).onClick(() => { this.retry(); })
            }
          }.padding(20).width('100%').backgroundColor('#99332F29').borderRadius(Theme.TOOL_RADIUS)
        }
        Blank()
        if (this.ready && this.isZooming) {
          Text(this.formatZoom(this.zoomRatio))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.CARD)
            .padding({ left: 14, right: 14, top: 6, bottom: 6 })
            .backgroundColor('#CC332F29')
            .borderRadius(16)
            .margin({ bottom: 8 })
        }
        if (this.ready) {
          this.zoomBar()
        }
        Row({ space: 4 }) {
          Button(`闪光 ${this.flash}`, { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('camera'))
            .enabled(this.ready && !this.busy)
            .onClick(() => { this.session?.cycleFlash(); })
            .accessibilityText(`闪光灯${this.flash}，点击切换`)
          Divider().vertical(true).height(16).color('#40FFFFFF')
          Button('翻转', { type: ButtonType.Normal }).attributeModifier(new PaperActionStyle('camera'))
            .enabled(this.canSwitch && this.ready && !this.busy)
            .onClick(() => { this.session?.switchCamera().catch(() => {}); })
            .accessibilityText('切换前后摄像头')
        }.padding(4).backgroundColor('#88332F29').borderRadius(Theme.TOOL_RADIUS)
        .margin({ top: 8 })
      }.width('100%').height('100%').padding(20)
    }.width('100%').layoutWeight(1).backgroundColor(Theme.INK).borderRadius(Theme.CARD_RADIUS).clip(true)
      .gesture(
        GestureGroup(GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              if (!this.ready || this.busy) { return; }
              this.baseZoom = this.zoomRatio;
              this.showZoomIndicator();
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.ready || this.busy) { return; }
              this.applyZoom(this.baseZoom * event.scale);
            })
            .onActionEnd(() => { this.scheduleHideZoomIndicator(); })
            .onActionCancel(() => { this.scheduleHideZoomIndicator(); }),
          PanGesture({ direction: PanDirection.Vertical })
            .onActionStart(() => {
              if (!this.ready || this.busy) { return; }
              this.baseZoom = this.zoomRatio;
              this.showZoomIndicator();
            })
            .onActionUpdate((event: GestureEvent) => {
              if (!this.ready || this.busy) { return; }
              const delta = -event.offsetY / 140;
              this.applyZoom(this.baseZoom + delta);
            })
            .onActionEnd(() => { this.scheduleHideZoomIndicator(); })
            .onActionCancel(() => { this.scheduleHideZoomIndicator(); })
        )
      )
      .onAreaChange((_old, area) => {
        // Fill the viewfinder bounds, not the whole page including its paper controls.
        this.viewportWidth = Number(area.width);
        this.viewportHeight = Number(area.height);
      })
  }

  @Builder
  private captureControls() {
    Row() {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.xmark')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
      }.attributeModifier(new PaperIconStyle(Theme.CARD))
        .onClick(() => { this.exit(false); }).accessibilityText('关闭拍摄，返回原页面')
      Blank()
      Button({ type: ButtonType.Circle }) {
        Stack({ alignContent: Alignment.Center }) {
          Circle().width(76).height(76).fill(Theme.CARD).stroke(Theme.LINE).strokeWidth(1)
          Circle().width(58).height(58).fill(Theme.INK)
          if (this.busy) {
            LoadingProgress().width(24).height(24).color(Theme.CARD)
          }
        }.width(82).height(82)
      }.width(82).height(82).backgroundColor(Color.Transparent)
        .enabled(this.ready && !this.busy).opacity(this.ready ? 1 : 0.4)
        .onClick(() => { this.shoot(); })
        .accessibilityText(this.busy ? '正在保存照片' : '拍照制作贴纸')
      Blank()
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.picture_2')).fontSize(Theme.ICON_SIZE).fontColor([Theme.INK])
      }.attributeModifier(new PaperIconStyle(Theme.CARD)).enabled(!this.busy)
        .onClick(() => { this.exit(true); }).accessibilityText('从相册选择照片制作贴纸')
    }.width('100%').height(112).padding({ left: 20, right: 20 })
  }

  build() {
    Column() {
      this.viewfinder()
      this.captureControls()
    }.width('100%').height('100%').backgroundColor(this.paperColor)
      .padding({ top: this.topInset + 12, bottom: Math.max(this.bottomInset, 12),
        left: Theme.PAGE_GUTTER, right: Theme.PAGE_GUTTER })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
