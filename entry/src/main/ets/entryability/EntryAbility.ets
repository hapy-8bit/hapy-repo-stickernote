import { ConfigurationConstant, UIAbility } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImmersiveWindowController } from '../platform/ImmersiveWindowController';

export default class EntryAbility extends UIAbility {
  onCreate(): void {
    this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    AppStorage.setOrCreate('stickerAppForeground', true);
    AppStorage.setOrCreate('stickerTopInset', 0);
    AppStorage.setOrCreate('stickerBottomInset', 0);
  }

  onWindowStageCreate(stage: window.WindowStage): void {
    // Configure edge-to-edge before loading content; interactive controls consume stored insets.
    ImmersiveWindowController.attach(stage).catch(() => {
      hilog.warn(0x0, 'StickerNote', 'Immersive window configuration could not complete.');
    }).then(() => {
      stage.loadContent('pages/Index', (error) => {
        if (error.code) { hilog.error(0x0, 'StickerNote', 'Page load failed: %{public}d', error.code); }
      });
    });
  }

  onForeground(): void { AppStorage.setOrCreate('stickerAppForeground', true); }

  onBackground(): void { AppStorage.setOrCreate('stickerAppForeground', false); }

  onWindowStageDestroy(): void { ImmersiveWindowController.detach(); }
}
