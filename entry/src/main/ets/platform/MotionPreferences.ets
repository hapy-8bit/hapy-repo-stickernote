import { accessibility } from '@kit.AccessibilityKit';
import { deviceInfo } from '@kit.BasicServicesKit';

/** API 13 没有系统减少动态查询；仅在 API 23+ 具备能力时读取，不改变本机数据或偏好。 */
export class MotionPreferences {
  static reduced(): boolean {
    try {
      if (deviceInfo.sdkApiVersion < 23 || !canIUse('SystemCapability.BarrierFree.Accessibility.Core')) return false;
      return accessibility.isAnimationReduceEnabledSync();
    } catch (_) { return false; }
  }
}
