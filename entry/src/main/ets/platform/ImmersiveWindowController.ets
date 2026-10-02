import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** One owner configures window bars. Pages consume safe-area values in vp through AppStorage. */
export class ImmersiveWindowController {
  private static mainWindow: window.Window | undefined = undefined;
  private static cameraAppearance = false;
  private static barUpdates: Promise<void> = Promise.resolve();
  private static readonly onAvoidArea = (_options: window.AvoidAreaOptions): void => {
    ImmersiveWindowController.updateInsets();
  };

  static async attach(stage: window.WindowStage): Promise<void> {
    const main = await stage.getMainWindow();
    ImmersiveWindowController.mainWindow = main;
    // A single portrait surface keeps camera preview and image rotation contracts explicit.
    await main.setPreferredOrientation(window.Orientation.PORTRAIT);
    await main.setWindowLayoutFullScreen(true);
    main.on('avoidAreaChange', ImmersiveWindowController.onAvoidArea);
    ImmersiveWindowController.updateInsets();
    await ImmersiveWindowController.applyAppearance();
  }

  static detach(): void {
    if (ImmersiveWindowController.mainWindow !== undefined) {
      try {
        ImmersiveWindowController.mainWindow.off('avoidAreaChange', ImmersiveWindowController.onAvoidArea);
      } catch (_) {}
    }
    ImmersiveWindowController.mainWindow = undefined;
  }

  static setCameraAppearance(camera: boolean): void {
    ImmersiveWindowController.cameraAppearance = camera;
    ImmersiveWindowController.barUpdates = ImmersiveWindowController.barUpdates.then(async () => {
      await ImmersiveWindowController.applyAppearance();
    })
      .catch(() => { hilog.warn(0x0, 'StickerNote', 'System bar appearance could not update.'); });
  }

  private static async applyAppearance(): Promise<void> {
    const main = ImmersiveWindowController.mainWindow;
    if (main === undefined) { return; }
    const light = ImmersiveWindowController.cameraAppearance;
    const background = light ? '#121212' : '#F6F3EB';
    main.setWindowBackgroundColor(background);
    await main.setWindowSystemBarProperties({
      statusBarColor: '#00000000', navigationBarColor: '#00000000',
      statusBarContentColor: light ? '#FFFDF8' : '#332F29',
      navigationBarContentColor: light ? '#FFFDF8' : '#332F29',
      isStatusBarLightIcon: light, isNavigationBarLightIcon: light
    });
  }

  private static updateInsets(): void {
    const main = ImmersiveWindowController.mainWindow;
    if (main === undefined) { return; }
    try {
      const system = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const cutout = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_CUTOUT);
      const gesture = main.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM_GESTURE);
      const ui = main.getUIContext();
      AppStorage.setOrCreate('stickerTopInset', ui.px2vp(Math.max(system.topRect.height, cutout.topRect.height)));
      AppStorage.setOrCreate('stickerBottomInset', ui.px2vp(Math.max(system.bottomRect.height, gesture.bottomRect.height)));
    } catch (_) {
      // Retain the previous known insets while the window is being recreated.
      hilog.warn(0x0, 'StickerNote', 'Window avoid area is temporarily unavailable.');
    }
  }
}
