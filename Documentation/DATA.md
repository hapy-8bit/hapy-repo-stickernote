> **为什么留下它？** 说明每日贴纸资产、不可变成品版本、每日摆放的当前合同与 schema 1 升级保护，供页面、图像服务和存储共同使用。

# 本机贴纸数据合同

新页面依赖 `domain/StickerModels.ets` 中的 `StickerRepository`，本机实现为 `data/StickerRepository.ets` 的 `LocalStickerRepository(context)`。小型 JSON 索引存于 `filesDir/sticker-store.json`，`schemaVersion: 2`。仓库不创建示例、不修改图像、不访问相机。

## 三类数据

- `StickerAsset`：稳定 ID、`sourcePath`、`sourceType`、`width/height`、标题、`note` 短注记、分类、收藏、创建/更新时间。`width/height` 为方向已统一的分割输入尺寸，和二进制蒙版坐标一致；原始 `.source` 文件保留拍摄原件，可另外读取原始分辨率。
- `StickerRevision`：ID、`assetId`、`maskPath`、`imagePath`、实际成品 `width/height`、`recipe`、创建时间。保存后不可变，制作编辑必须创建新 ID 和独立成品路径。
- `DayPlacement`：ID、日期、`assetId/revisionId`、纸面位置 `x/y`、比例、旋转、层级、短注记及时间。移除摆放不删除资产；重新制作只更新明确选中的摆放，其余历史日期继续引用原版本。

`StickerRecipe` 保存 `mode`（subject/original）、白边宽度/颜色、旋转、水平翻转、归一化裁切范围及 `subjectIndex`。裁切全部位于 0..1；`subjectIndex=-1` 表示合并主体，0..19 表示 SDK 候选索引。照片 mode 和纸面旋转分别保存，不能把纸面摆放写回原图。

## 接口与写入顺序

| 方法 | 行为 |
| --- | --- |
| `load()` | 独立读取/验证当前索引；首次必要时迁移旧索引 |
| `saveAsset(asset, revision, placement)` | 一次提交资产、不可变新版本，以及可选的新增或更新摆放；第三参数不用时传 `undefined` |
| `updateAsset(asset)` | 只更新标题、短注记、分类、收藏及更新时间，不能换源图、坐标尺寸或创建时间 |
| `savePlacement(placement)` | 新增/更新一个摆放，资产必须存在且版本确属该资产 |
| `savePlacements(placements)` | 批量 upsert，一次验证和 rename；不删除未列出的摆放，自动排版或撤销不会部分提交 |
| `removePlacement(id)` | 移除每日摆放，资产和成品仍在贴纸盒 |
| `removeAsset(id)` | 仍被每日摆放引用时拒绝；成功提交后返回可清理文件路径 |
| `renameCategory(oldName, newName)` | 一次提交分类改名及资产分类更新，未分类入口不可改名 |
| `saveCategories(categories)` | 新增/排序/删除空分类，拒绝移除仍有资产的分类 |

图像服务先将源图、蒙版和版本 PNG 完整落盘，仓库提交成功后才更新 UI。取消仅删除本次草稿文件；媒体清理失败不回滚成功索引，可能留下无引用文件，不造成有效照片先被删除。

只存贴纸盒时短注记保留在 `StickerAsset.note`；某次贴入纸面的注记使用 `DayPlacement.note` 独立保存。修改资产短注记不自动改变历史摆放。两者最长 2000 个字符；读取早期 schema 2 缺失的资产 `note` 时正规化为 `''`。

`StickerFactory` 提供 `newId(prefix)`、`defaultRecipe(mode)`、`createAsset(id, sourcePath, sourceType, width, height, now)`、`createRevision(id, assetId, maskPath, imagePath, width, height, recipe, now)`、`createPlacement(id, dateKey, assetId, revisionId, zIndex, now)`、`copyRecipe(recipe)`。末尾时间和 zIndex 可省略，ID 可在写入媒体前生成。

## 路径与真实文件

仅允许 `filesDir/stickers/<文件>` 或 `filesDir/stickers/<assetId>/<文件>`，ID/文件名使用英文字母、数字、下划线、连字符。拒绝临时 Picker URI、其他目录、路径穿越、深层目录、反斜杠和查询参数。

- 原件：`.source`，保留原始 bytes（PNG/JPEG/WebP/HEIF），或 `.png/.jpg/.jpeg`。
- 成品：`.png/.jpg/.jpeg`，正常制作输出透明 PNG。
- 蒙版：`.mask`（逐像素 Uint8Array）或 `.png`；二进制长度必须严格等于资产标准方向输入的 `width * height`。

仓库验证私有目录、子目录和文件均非符号链接，文件存在且非空；图像读取文件头检查格式一致。完整图像解码、EXIF 方向及渲染质量仍归图像服务；文件头合法不能替代解码验收。

## schema 1 升级

仅在 schema 2 索引不存在时读取 `filesDir/journal.json`。旧文件由现有 `JournalCodec` 严格验证；验证失败、丢图或格式异常时不给空索引遮蔽旧数据。

迁移结果先写 schema 2 的同目录临时文件、处理短写、fsync、关闭，再 rename。`journal.json` 始终保留不改，旧 PNG 仍可用。迁移中断后再次以稳定 ID 计算，不追加重复记录。

同一旧 PNG 文件映射到一个 legacy 资产。每条旧记录使用原 ID 加稳定后缀建立版本和每日摆放，保留日期、mode、备注及时间。共享成品的标题/短注记/分类使用最后更新记录的值，每个每日摆放仍保留自己的旧注记，其他旧值完整保留在原索引。超长旧 ID 加哈希后缀以减少截断冲突，发现重复会拒绝提交。

legacy 的 `sourcePath=''`、`maskPath=''`、宽高 `0` 表示未保存/未知，不能伪造原图和蒙版或声称能精确重做旧白边。其真实成品可继续展示、重复使用。

`removeAsset()` 返回清理列表时还排除被保留的 `journal.json` 引用的旧 PNG；旧索引无法读验时保守不清理该次文件。保留旧索引及图像是升级恢复线索，不宣称已提供用户备份或回退 UI。

## 损坏保护与边界

每次操作重读并验证索引，校验重复 ID、引用完整性、自然日、坐标、缩放、分类、文本长度与时间。不支持的 schema、坏 JSON、无效文件、权限错误均返回可读异常，原索引不覆盖。临时文件失败只清理本次临时路径。

写入事务内无 await，也不缓存可变 store；当前同一 UIAbility 的并发调用不会在读写之间让出执行。未设计跨进程锁，若接入后台任务或多个写进程需改用明确事务存储。当前不包含 RDB、云同步、加密、用户导出或完整断电恢复 UI。

建议验证真实行为：旧索引重复升级无重复资产；同 PNG 归并但两个日期保留；坏旧/新索引不覆盖；新版本不改变其他日期；引用中的资产不能删除；从日期移除后贴纸盒可继续使用；分类改名保持引用；私有目录外、子目录符号链接、蒙版尺寸错误与缺图拒绝。

可在工程根目录运行 `node tools/check-data.cjs`。检查从当前工程路径直接读取并转译真实 `.ets` 数据/领域源码，文件 API 使用内存替身。它覆盖迁移稳定性、索引保护、引用和版本隔离、资产/每日短注记隔离、批量原子更新、文件边界、蒙版尺寸及失败清理；不代替 ArkTS 构建、设备文件 API、完整图像解码和断电恢复验证。
