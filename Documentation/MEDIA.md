> **为什么留下它？** 说明真实相机、端侧主体识别、原件/蒙版/成品及草稿所有权的当前合同，防止制作取消或升级损坏已保存贴纸。

# 每日贴纸照片处理

当前版本 `0.1.0 / 100000`。装配入口使用 `StickerAcquisitionService`，取得 `StickerMediaSession`；它只负责媒体，不提交资产索引。数据提交由 `StickerCommands` 和 `StickerRepository` 完成。

## 来源与相机

`pick()` 调用系统 PhotoViewPicker 单选；未选中返回 `undefined`。相册临时 URI 仅用于当次复制原始 bytes，不进入持久化数据，也不读取整个相册。

`CameraSession` 使用 CameraKit 的 `CameraInput`、`PreviewOutput`、`PhotoOutput` 和 `PhotoSession`，取景由 CameraView 的 XComponent 提供 surface。进入拍摄页时申请 `ohos.permission.CAMERA`；纯照片不申请麦克风。支持可用的前后镜头切换及关闭/自动/开启闪光模式，能力不足时跳过不支持项。

相机页面等待首帧再允许快门；资源修改通过队列串行，generation 识别退出后迟到的回调。相机占用/错误、首帧等待和拍摄超时给出重试/相册路径；切后台或退出释放资源，前台回到相机页重新初始化。当前锁定竖屏，JPEG 使用镜头对应的拍摄旋转和支持的前置镜像。

`CameraPhotoFiles` 将拍摄 JPEG 完整写入私有 `stickers/photo-<UUID>.jpg`。`capture(path)` 将它复制为资产原件并在导入结束后清理临时拍摄文件；取消、迟到回调或页面已退出时也只清理当前拍摄草稿。

## 原件、坐标与解码

`StickerMediaFiles` 为每个新资产创建 `filesDir/stickers/<assetId>/`，保留原件 `source.source`，扩展名不改变原始内容格式。复制大小上限 100 MiB；PNG/JPEG/WebP/HEIF 等格式需系统 ImageSource 实际能解码，不能仅凭扩展名保证支持。

`StickerPhotoDecoder` 将第一帧转换为 SDR、RGBA_8888，处理 EXIF 方向与镜像，再限制分割输入最长边不超过 1280 像素。原始文件保留高分辨率 bytes，但当前制作母版和 PNG 以此标准输入渲染；尚无独立高分辨率导出链路。动画/实况视频不成为手帐内容。

解码后的 `ColorSpaceManager` 随会话母版保留；重建 RGBA PixelMap 后恢复相同颜色空间标记，再编码 PNG。不把 Display P3 的原始 RGB 字节当作默认 sRGB，也不靠重新贴 sRGB 标签假装做了转换。原件仍完整保留；HDR 到 SDR 的系统映射与图库 HDR 动态亮度可能不同，真实宽色域/HDR 色差仍需设备样本检查。

母版通过 `readPixelsToBuffer` 读取原生 RGBA 与原 alpha 类型，再按实际类型去预乘一次。区域 `readPixels(PositionArea)` 会转成 BGRA 与 UNPREMUL，旧代码错误地当作 RGBA/源 alpha 类型，导致红蓝交换或重复提亮；不再使用该路径。[官方区域与完整缓冲区实现](https://raw.githubusercontent.com/openharmony/multimedia_image_framework/OpenHarmony-5.0.0-Release/frameworks/innerkitsimpl/common/src/pixel_map.cpp)

资产 `width/height` 对应标准方向分割输入，`.mask` 为同尺寸逐像素 Uint8Array；版本 `width/height` 为裁切、边距与方向处理后的成品尺寸。纸面位置与制作裁切都使用归一化坐标，不能把成品坐标误当原图坐标。

## 主体识别与降级

使用 CoreVisionKit `subjectSegmentation.init/doSegmentation/release`，先检查系统能力，原生引擎使用全局忙锁。请求最多 6 个主体，并启用主体详情；界面可以选择全部主体或 SDK 返回的候选编号，不提供尚未实现的画笔选区。

蒙版长度须等于输入宽高乘积、数值为 0..255；只有格式错误或全零结果视为不可用，合法的全幅/小主体不能被面积阈值丢弃。先读单个候选，联合结果失效时按完整坐标逐像素取最大 alpha 合并有效候选。合成时 RGB 来自同一标准输入，alpha 为原图 alpha × 蒙版，PREMUL 颜色先还原；不拿裁切的原生 foreground 与全幅蒙版错配。

设备不支持、模型初始化失败、无有效主体、引擎正忙或原生异常时，明确提示并切换保留完整照片。读图或保存失败返回异常，不生成假主体、不假装保存成功。当前没有云端抠图或图片上传代码；系统模型初始化和不同设备离线行为仍需实际验证。

## 圆形描边与制作

`StickerRenderTask` 使用 `@Concurrent` 和 TaskPool 执行纯像素计算；禁止 transfer 会话母版，防止首次预览后源 buffer 被 detach。`StickerRaster` 按所选归一化范围裁切，再裁透明空白，补边距，以欧氏距离变换生成圆形轮廓扩张及抗锯齿边缘，替代旧方形膨胀算法。

当前制作界面提供 0..24 px 白边、90° 旋转、水平翻转、全幅/居中正方形/4:3/3:4 裁切。显示比例先按旋转角度换回源坐标，使用真实处理输入尺寸，不能用已裁切成品猜测。输出 UNPREMUL RGBA 的透明 PNG；纸面阴影属于展示层。

白边只写入完全透明的区域，主体非零 alpha 像素的 RGB 和透明度不随白边宽度变化，避免把白色底层烘焙进主体。alpha≥128 的明确主体用于生成外轮廓，弱噪点不生成不透明白色孤岛；透明裁边保留所有非零输出 alpha。制作页的棋盘格/纸面切换只影响预览底层，不写入 PNG。纯像素检查不表示人物细发、玻璃或现场照片颜色已完成真机验收。

每次渲染生成独立 `<revisionId>.png`；去背景版本同时保存 `<revisionId>.mask`。原件、蒙版和成品不可在历史版本路径上重写，重新制作生成新版本，其他日期仍引用原版本。

## 会话与文件所有权

`StickerMediaSession.create()` 复制源图、解码识别、生成首版；`reopen()` 用保留原件重做并尽可能读取对应旧蒙版。坐标不匹配或蒙版读取失败时提示重新识别，历史成品保留。

新资产的原件与全部草稿预览记录在 `ownedPaths`；已有版本从不进入此集合。渲染成功后仅回收该会话先前的未提交预览。若取消与 TaskPool/写入同时发生，generation 检查阻止迟到结果提交并清理本次文件。

仓库保存成功后调用 `markCommitted()`，转移当前原件/成品/蒙版所有权，清理其它预览并释放内存；清理失败只能提示部分文件未清理，不能把已提交贴纸显示成保存失败。`cancel()` 不改旧索引或历史文件，只清理会话拥有的新文件。

图片使用独立 `.partial-<UUID>` 文件完整写入、fsync、关闭，再 rename；不先删除旧文件。路径限制为私有贴纸根及一级资产子目录，拒绝穿越和符号链接。永久删除前由仓库检查每日引用并提交索引，媒体服务随后仅清理仓库返回的无引用路径。

legacy 只有旧成品 PNG：可对成品裁切、旋转和翻转，不能恢复源图、原蒙版或去除旧白边。界面明确显示此限制；保留的旧索引仍引用的 PNG 不进入清理列表。

## 当前缺口与验证

没有画笔擦除/恢复、独立缩略缓存、高分辨率导出、用户备份、联网 AI、账号或会员。设置中的存储占用来自真实私有文件统计，分原件/蒙版/成品，并不代表已有缓存清理或云备份。

`node tools/check-source.cjs` 执行真实像素与领域源码；`node tools/check-data.cjs` 检查索引、版本、文件边界和迁移（文件 API 内存替身）。构建/签名见 [BUILD_RECEIPT.json](BUILD_RECEIPT.json)，设备证据见 [DEVICE.md](DEVICE.md)。

源码图像检查覆盖白边宽度/方向/翻转变化时主体 RGB 与 alpha 保持一致、PREMUL 还原、软边与弱噪点、全幅/小主体蒙版、候选合并及旋转后的比例。`StickerCutout` 日志仅记录阶段、错误码、处理尺寸、蒙版长度和候选数，不记录用户图片、文字、路径或 URI。

`node tools/check-decoder.cjs` 的 8 项检查直接执行真实 Decoder→Raster，SDK 内存替身模拟区域 BGRA/UNPREMUL 与完整 RGBA/源 alpha 合同；红蓝不对称、PREMUL、较大分配、色彩标记引用和失败释放均覆盖。恢复旧区域读像素代码时，第一项 RGB 对照会失败；该检查不能证明原生 PNG 的 ICC 编码结果。

真机仍须检查授权允许/拒绝、前后台/锁屏恢复、相机占用、快门/切换/闪光、取消和迟到回调、HEIF/EXIF、多人及细发/透明物、无主体提示、重制版本隔离、空间不足、重启回看和 schema 1 升级。图像质量与相机稳定性取决于实际输入和设备，不能由源码接线推定。
