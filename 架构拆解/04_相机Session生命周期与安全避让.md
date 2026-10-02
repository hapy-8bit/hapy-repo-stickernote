> **为什么留下它？** 说明 CameraKit 会话管理、前后台切换、超时保护及全屏沉浸式窗口避让方案。

# 相机Session生命周期与安全避让

关联：[[00_每日贴纸_全景图谱|全景图谱]] · [[Documentation/MEDIA|媒体处理合同]] · [[Documentation/DEVELOPMENT|开发基线]]

## 1. CameraKit 封装与生命周期
- `CameraSession`：单一所有权管理 CameraKit `PhotoSession`、`CameraInput`、`PreviewOutput` 和 `PhotoOutput`。
- **序列化任务队列**：所有相机启动、停止、切换镜头操作通过内部 Promise 队列串行化执行，杜绝异步重入冲突。
- **代次保护 (Epoch/Generation)**：每次配置递增 epoch，识别并丢弃迟到的回调，防止退出后老回调唤醒已释放资源。
- **前后台切换**：监听 `stickerAppForeground`，切入后台立即停止 Session 释放传感器占用；切回前台重新初始化。
- **首帧与超时监控**：等待首帧 `frameStart` 再解锁快门按钮；拍照设 20 秒超时监控，超时自动重置并提示用户。

## 2. 沉浸式窗口与安全区避让
- `ImmersiveWindowController`：
  - 应用固定强制竖屏（`window.Orientation.PORTRAIT`）。
  - 设置全屏沉浸（`setWindowLayoutFullScreen(true)`）与透明状态栏/导航栏。
  - 动态监听 `avoidAreaChange`，计算系统状态栏与底部手势导航条的高宽，转为 vp 并注入 `AppStorage`（`stickerTopInset` / `stickerBottomInset`）。
  - 页面各组件根据安全边距自动避让，确保在刘海屏、挖孔屏及曲面屏设备上操作不被遮挡。
