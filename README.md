> **为什么留下它？** 提供每日贴纸的当前功能入口、工程标识、构建与检查方式，让开发者从真实源码继续开发。

# 每日贴纸

HarmonyOS 本地照片贴纸手帐，工程目录名 StickerNote；当前版本 **0.1.0 / 100000**。

- 包名：`com.lh.stickernote`；AppID：`6917617717737387696`。
- 原生 ArkTS / ArkUI Stage，兼容 API 13，目标 API 24。
- 底部「手帐／加号／贴纸盒」共用奶油手帐样式；加号提供拍照、相册和已有贴纸。拍照或选图 → 主体识别 → 选择主体、白边与简单裁切 → 贴入一天或只存贴纸盒。
- 今日纸面支持摆放、方向/大小/层级调整、自动排版与撤销；贴纸盒支持搜索、分类、收藏和重复使用；日期入口回看月历。
- 沉浸式窗口统一系统栏和避让区域；设置提供纸色、打开即拍照、存储占用、隐私政策、用户服务协议、联系与版本。
- 私有原件、蒙版、不可变成品版本及每日引用分别保存；schema 1 旧索引显式迁移并保留恢复线索。

尚未接入联网 AI、账号、会员、云同步、备份/导出、画笔修边或独立缩略缓存。空日期和空贴纸盒保留真实空状态。构建通过不代表相机、抠图或设备视觉已经验收。

[奶油手帐 UI 合同](Documentation/UI_DESIGN.md) · [开发分层与功能边界](Documentation/DEVELOPMENT.md) · [照片与资源所有权](Documentation/MEDIA.md) · [数据合同](Documentation/DATA.md)

使用 DevEco Studio 打开本目录。重新从当前源码构建：

```sh
JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home \
PATH="/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH" \
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw \
assembleHap --mode module -p product=default -p module=entry@default \
-p buildMode=debug --no-daemon --no-incremental
```

本机签名配置为忽略文件 `build-profile.json5`，公开模板为 `build-profile.example.json5`。Profile、证书与私钥须匹配本 App 和目标设备，不能复用 One Day 的 Profile；凭证与密码不进入源码或文档。设备交接见 [DEVICE.md](Documentation/DEVICE.md)，当轮产物事实见 [BUILD_RECEIPT.json](Documentation/BUILD_RECEIPT.json)。

源码行为检查：

```sh
node tools/check-source.cjs
node tools/check-decoder.cjs
node tools/check-data.cjs
node tools/check-motion.cjs
```

当前 99 条检查通过：check-source 执行 45 条真实领域、编解码及描边源码检查；check-decoder 执行 8 条真实解码/合成检查，SDK 替身按官方区域 BGRA/UNPREMUL 与完整缓冲区 RGBA/源 alpha 合同验证颜色；check-data 执行 38 条资产、迁移、引用、原子提交和短注记检查；check-motion 执行 8 条动画回调所有权检查。

当前源码构建与验签通过，API 24 模拟器检查了空纸面、贴纸盒、设置、月历、添加来源与返回流程。本轮未更新真机；真实照片工作台、贴纸摆放、大字号和 API 13 设备尚未验收，纯逻辑与空态检查不代替真实拍摄、主体质量或重启恢复验证。
