> **为什么留下它？** 固定每日贴纸当前分层、用户行为和验证边界，让相机、制作、数据及设置能够分别维护。

# 每日贴纸开发基线

当前工程 `com.lh.stickernote`，AppID `6917617717737387696`，版本 `0.1.0 / 100000`；事实来自 `AppScope/app.json5`。原生 ArkTS / ArkUI Stage，兼容 API 13、目标 API 24，当前设备目标为 nova 12。产品定位是拍下真实物件、制作可重复使用的贴纸，再贴进每天的纸面。

## 当前功能

| 页面/能力 | 当前源码行为 |
| --- | --- |
| 今日纸面 | 默认本机今天；七日条选择日期，月份入口转月历；中央加号提供拍照、相册与已有贴纸；长按真实贴纸后拖动，使用工具调整大小、旋转和层级；自动排版、当次撤销 |
| 拍摄 | CameraKit 实时取景收进圆角卡片，纸面外框随纸色变化；细实线构图框仅作引导，完整照片交接不变；独立快门、关闭及相册区，预览内保留闪光和翻转 |
| 制作贴纸 | 端侧 CoreVision 主体识别，全部/候选主体、保留照片、0..24 px 白边、90° 方向调整、翻转及居中比例裁切 |
| 保存 | 可贴入当前选中日期，也可只存贴纸盒；标题、分类、短注记和收藏随资产保存，某次每日注记独立保存 |
| 贴纸盒 | 搜索、分类和收藏筛选、再次贴入选中日期、打开制作、分类管理 |
| 月历 | 从真实摆放计算有记录日期和缩略展示；选中日期回到当天纸面，空日期保持空 |
| 设置 | 三种纸色、打开即拍照、真实文件占用、分类、关于/版本、联系开发者及两份离线协议 |
| 协议 | 首次明确同意；协议版本与接受记录独立保存；相机权限在使用时另行申请 |

没有联网 AI 名称/分类建议、账号、会员、云同步、备份/导出、画笔修边、独立缩略缓存、桌面卡片或应用内购买。基础拍摄、编辑与本机数据不依赖 One Day 服务，也不展示未接通的权益。

## 分层

```text
EntryAbility → ImmersiveWindowController（系统栏/避让区域/竖屏）
             → pages/Index（依赖装配、页面状态与制作事务）
                    ├─ components（画布/贴纸盒/制作/相机/日历/设置/协议）
                    ├─ application/StickerCommands（资产保存、摆放与撤销用例）
                    ├─ StickerRepository → LocalStickerRepository / StickerCodec / StickerMigration
                    ├─ StickerAcquisitionService → StickerMediaSession
                    │                            → StickerPhotoDecoder / StickerRenderTask / StickerMediaFiles
                    ├─ LocalPreferences / LegalDocuments
                    └─ PageMotion / MotionPreferences（页面表现与兼容动态偏好）

CameraView → CameraSession → CameraPhotoFiles（相机资源与临时 JPEG）
domain/StickerModels、StickerFactory、StickerCopies、DateTools：不依赖 SDK
```

`Index` 负责装配、状态和保存/取消流程；`StickerCommands` 把用户意图转成仓库事务，不依赖 ArkUI。普通显示组件通过回调输出意图；相机视图只连接独立 `CameraSession`，不操作 CameraKit 对象或照片文件。

沉浸式窗口延伸背景，实际控件使用系统、刘海和手势区避让值；拍摄页切换系统栏图标对比。当前锁定竖屏，不承诺横屏排版。

普通页面统一使用 100ms 退出与 190ms 入场、14vp 方向位移；手帐与贴纸盒切换时底部加号和导航保持原位。两个内容页保持挂载，隐藏页不接收输入或无障碍焦点；搜索、分类、收藏筛选和滚动位置在当前会话保留，切换前主动清除输入焦点。月历只对日期网格做 190ms 入场，标题和月历卡尺寸稳定。

`PageMotion` 用代次保护完成回调，页面退出后失效；相机 Surface 和已释放草稿的退出立即切路由，只动画新页面，避免延长原生资源生命期或显示已删除预览。API 23+ 按能力读取系统减少动态状态；API 13 不调用该查询，继续使用普通短动画。今日摆放工具条覆盖纸面，不改变编辑前后的坐标范围，并放在选中贴纸的相反半页以保留中心拖动区域；顶部和导航按最小高度适应字体，底部至少保留 12vp 手势留白。

## 界面样式合同

`Theme` 维护视觉尺寸，`PaperStyles` 通过 API 12 起支持的 `AttributeModifier` 共享实际样式，满足最低 API 13。各页面只传入动作层级或真实选中状态，回调、禁用条件和业务状态仍归原页面。

视觉方向为用户选定的「奶油手帐」，完整合同见 [UI_DESIGN.md](UI_DESIGN.md)。品牌标题 30、页面标题 22、空态标题 18，三者 Bold；分节 16，正文与按钮 14，辅助说明 12。普通按钮最小高度 44，主动作至少 48；主纸面圆角 30、工具纸面 24、控件 14、操作按钮 24；主要内容左右 20、首页外纸面 18。输入框高 48；操作图标 20，行末图标 16。

主动作采用深墨底与纸色字，次动作浅底，轻量动作透明；一般选项使用浅底和细边表示选中。贴纸盒筛选保留深墨选中标签；首页日期使用纸色竖胶囊。制作工具通过下划线页签切换，输入由制作页面持续持有。加号来源弹层关闭后才交接相机/选图器；普通页面不直接访问 Picker。

## 数据与资源所有权

- 资产保留私有原件和归档信息，版本保留蒙版、制作参数及 PNG；每日摆放只引用指定版本，重新制作不会覆盖其他日期。
- schema 2 索引为 `sticker-store.json`；首次升级严格读验 schema 1 `journal.json`，旧索引及其 PNG 保留。坏索引不能静默重置。
- 旧成品为 legacy 资产，缺失源图/蒙版以空路径表达，未知尺寸为 0；可以继续展示、摆放、对成品裁切/调整方向，不能恢复旧白边或丢失原图。
- 新图与预览先落盘，仓库提交后再更新 UI、转移所有权和清理未提交预览；取消只回收该草稿拥有的文件。
- 从一天移除只删除摆放；资产仍有摆放引用时拒绝永久删除。原图身份与已保存版本不可覆盖。
- 自动排版、撤销使用批量摆放事务，任何无效引用都不部分提交。撤销是当前会话的摆放历史，不是持久版本回退 UI。
- 相机、原生引擎、PixelMap、ImageSource、ImagePacker 和文件句柄各有独立所有者；后台/退出相机释放资源，取消或失败保留已提交文件。

详细坐标、路径、迁移和文件验证见 [DATA.md](DATA.md)，媒体生命周期见 [MEDIA.md](MEDIA.md)。

## 设置与维护

`LocalPreferences` 使用 `daily_sticker_preferences` 保存 `acceptedVersion`、`paperStyle`、`startWithCamera`，等待 flush 后更新页面。它不与贴纸索引共用文件。协议从 rawfile 的 `sticker_privacy.md` 与 `sticker_terms.md` 离线读取，版本由 `LegalDocuments` 统一提供。

每个页面/组件严格少于 800 行，职责按文件拆分；注释保留资源所有权、异常保护和兼容边界。当前仅使用系统 SDK，图片处理代码与品牌展示独立，不接入 Stitch 或第三方抠图模型。

## 验证边界

在工程根目录运行 `node tools/check-source.cjs`、`node tools/check-decoder.cjs`、`node tools/check-data.cjs` 与 `node tools/check-motion.cjs`。当前 99 条检查通过，分别为 45 条领域/图像、8 条解码、38 条数据和 8 条动画所有权检查；周条覆盖跨年、周日和闰日边界。动画检查覆盖过期回调、退出失效、相机立即切路由与系统关闭动画后的解锁；UIContext 替身不代表实际帧率或设备渲染。

当前源码构建与验签通过，API 24 模拟器已检查首页与贴纸盒空态、设置、月历、添加来源和返回流程；本轮未更新真机安装。产物事实以 [BUILD_RECEIPT.json](BUILD_RECEIPT.json) 为准，逐项设备观察见 [DEVICE.md](DEVICE.md)。真实照片工作台、贴纸摆放、大字号与 API 13 设备尚未验收；真实取景、授权拒绝、前后台恢复、拍照 EXIF、主体边缘、旧数据升级和重启回看仍须独立检查。
