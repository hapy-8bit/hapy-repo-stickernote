> **为什么留下它？** 固定当前签名、安装证据和真机验收边界，避免把源码构建通过当作拍照与抠图效果已验收。

# 签名、模拟器检查与 nova 12 验收

当前包名 `com.lh.stickernote`，AppID `6917617717737387696`，版本 `0.1.0 / 100000`。
当前 A「奶油手帐」版已从源码构建为 Debug HAP、通过验签，并覆盖安装到 API 24 模拟器 `127.0.0.1:5555` 与 nova 12 Ultra。最新产物和验证边界见 [BUILD_RECEIPT.json](BUILD_RECEIPT.json)，当前视觉合同见 [UI_DESIGN.md](UI_DESIGN.md)。

## 本机签名

本机已经配置独立调试密钥、完整证书链和包含 nova 12 UDID 的 Debug Profile；Profile、包名、AppID 和 keystore alias 公钥已配对核验。
签名配置仅位于忽略文件 `build-profile.json5`，公开模板为 `build-profile.example.json5`。证书、私钥、Profile 及密码不进入源码或开发文档。

更换签名材料时，使用配套的完整来源配置：

```sh
node tools/configure-signing.cjs --profile /绝对路径/StickerNoteDebug.p7b --source-signing /绝对路径/独立签名来源配置.json5
```

来源配置必须有完整 `app.products` / `app.signingConfigs` 结构，default 产品引用签名项；证书链、keystore、alias 与 Profile 须配套。
密码使用本机 DevEco 加密值及配套 material 目录，不能直接复制其它目录的加密密码。辅助工具核对证书和 Profile，不替代构建签名与设备授权校验。

## 构建、核验、安装

在工程根目录从源码构建：

```sh
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw --mode module -p product=default -p module=entry@default -p buildMode=debug assembleHap --no-daemon --no-incremental
```

产物：`entry/build/default/outputs/default/entry-default-signed.hap`。
使用 SDK `hap-sign-tool.jar verify-app` 时，明确提供 `-inFile`、`-outCertChain` 和 `-outProfile`；输出签名材料仅保存在忽略的 `.local/`。

已连接的 USB 目标为 `2UCUT23C27028737`，设备为 nova 12 Ultra / `ADA-AL00U`：

```sh
hdc -t 2UCUT23C27028737 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 2UCUT23C27028737 shell aa start -b com.lh.stickernote -a EntryAbility
hdc -t 2UCUT23C27028737 shell pidof com.lh.stickernote
```

升级使用 `install -r`，保留应用数据；签名不匹配时核对材料，不通过卸载或清数据绕过。

## 奶油手帐版的验证边界（2026-09-30）

- 页面标题、按钮、纸面、空态和导航采用共享规则；首页增加当周日期条与来源菜单，制作页整理为图像、白边、信息三个工具页签。源码构建和 SDK 验签通过；45 个 ArkTS 文件均少于 800 行，最大为 Index 的 528 行。
- API 24 模拟器已核对今日空纸面、贴纸盒、设置、分类按钮及禁用态、月历和历史日期返回、离线隐私政策；没有创建贴纸或手帐记录。
- 中央加号的拍照、相册、已有贴纸入口可到达对应页面；原生照片选择器取消及相机关闭均返回主页面。模拟器相机报告暂时不可用，不能据此确认真实取景和拍摄效果。
- 已运行 45 项领域/图像、8 项解码、38 项数据及 8 项动画检查，共 99 项通过；包含跨月跨年与闰日七日条边界。制作页带真实照片、有贴纸网格、摆放工具、大字号、API 13 设备渲染和真实相机效果仍待设备验证。
- 最终包的首页、贴纸盒、设置、来源菜单与相机截图已保存；本轮证据位于忽略目录 `.local/cream-design-validation/`。构建通过和模拟器观察不代表真机验收。

## 真机当前安装版本

nova 12 Ultra（`2UCUT23C27028737` / `ADA-AL00U`）已在 2026-09-30 覆盖安装并启动当前 A「奶油手帐」Debug 包；`pidof` 返回进程 `49328`。设备包信息为 `com.lh.stickernote`、`0.1.0 / 100000`、兼容 API 13、目标 API 24。因为版本号未变，当前包以 SHA-256 `cb54847e…f60ab007` 区分，完整值和安装时间记录在 `BUILD_RECEIPT.json` 的 `physicalDeviceDeployment`。

升级使用 `install -r`，未清除应用数据。安装与进程存在不代表首页显示、取景、拍摄、抠图或摆放已经过真机验收；这些仍按下节逐项体验。模拟器沿用此前授予的相机权限，本轮未重新授权，也未清除应用数据。

## 下一步真机体验

1. 阅读隐私政策和用户服务协议；确认后进入今日纸面。没有记录时应保持空白，设置中应能再次离线打开两份协议。
2. 点中央加号，再选择拍照，分别检查授权允许与拒绝；允许后检查取景、拍照、切换镜头、支持的闪光模式及退出返回。
3. 拍摄或选图，检查全部/单个主体、保留照片、白边、方向和比例裁切；无有效主体时应有明确降级提示。
4. 保存标题、分类和短注记，分别体验贴入选中日期与只存贴纸盒；分类、收藏、搜索和重复贴入应使用真实数据。
5. 长按纸面贴纸，检查拖动、大小/旋转、层级、自动排版与撤销；月历选日期后应回到对应纸面。
6. 重新制作形成新版本，其它日期仍保留旧图；重拍/编辑取消不得覆盖原记录。删除有每日引用的资产应被阻止。
7. 检查切后台、锁屏、相机占用、重启回看、模型初始化/离线、真实 EXIF 与空间不足；升级旧数据另作专项验证。

构建及页面观察不是完整产品验收。毛发、玻璃、细线、多主体、低光和被画面截断的物体须用真实照片评价。
