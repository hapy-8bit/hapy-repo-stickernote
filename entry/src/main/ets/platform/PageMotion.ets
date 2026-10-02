import { UIContext } from '@kit.ArkUI';
import { Theme } from '../components/Theme';

type Presentation = (opacity: number, offset: number) => void;

/** 动画只拥有表现和回调代次；调用方拥有导航。退出失效后不得再提交旧页面。 */
export class PageMotion {
  private generation: number = 0;

  transition(ui: UIContext, reduced: boolean, direction: number, commit: () => void,
    present: Presentation, lock: (active: boolean) => void): void {
    const generation: number = ++this.generation;
    if (reduced) { commit(); present(1, 0); lock(false); return; }
    lock(true);
    ui.animateTo({ duration: Theme.FADE_OUT_MS, curve: Curve.EaseIn,
      onFinish: (): void => {
        if (generation !== this.generation) return;
        commit(); present(0, direction * Theme.MOTION_OFFSET);
        this.reveal(ui, generation, present, lock);
      }
    }, (): void => present(0, -direction * 6));
  }

  /** 相机 Surface 立即装卸，只淡入新页面，退出动画不会延长原生资源的生命期。 */
  enter(ui: UIContext, reduced: boolean, commit: () => void, present: Presentation,
    lock: (active: boolean) => void): void {
    const generation: number = ++this.generation;
    commit();
    if (reduced) { present(1, 0); lock(false); return; }
    lock(true); present(0, 0);
    this.reveal(ui, generation, present, lock);
  }

  private reveal(ui: UIContext, generation: number, present: Presentation, lock: (active: boolean) => void): void {
    ui.animateTo({ duration: Theme.FADE_IN_MS, curve: Curve.EaseOut,
      onFinish: (): void => { if (generation === this.generation) lock(false); }
    }, (): void => { if (generation === this.generation) present(1, 0); });
  }

  invalidate(): void { this.generation += 1; }
}
