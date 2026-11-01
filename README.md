# PhotoViewer

一个轻量的 macOS 原生图片查看器，目标很简单：

> 从 Finder 打开一张照片后，直接在当前文件夹里用左右方向键连续翻图，看到不要的按 Delete 移入废纸篓。Nikon 的 NEF+JPG 会按一张照片处理，删除时一起删。

不是网页套壳，使用 SwiftUI + AppKit + ImageIO 构建，打包为独立运行的 `PhotoViewer.app`。

## 当前功能

- 打开图片或文件夹（`⌘O` / `⇧⌘O`），自动扫描图片所在文件夹
- 按文件名自然排序（`IMG_1 / IMG_2 / IMG_10`）
- Nikon RAW+JPEG 配对：`DSC_0001.NEF` + `DSC_0001.JPG` 算一张
  - 计数按照片张数，不是文件数
  - 默认显示 JPEG（快）；按 `J` 切换到 NEF，或再按一次切回
  - 工具栏显示 `NEF+JPG` 和当前显示格式
- 工具栏显示当前位置，例如 `3 / 300`
- 选片：
  - `1–5` 打星，`0` 清除
  - `P` 保留，`X` 废片，`U` 取消旗标
  - 顶部筛选条：`全部 / 未评级 / 保留 / 废片`，带数量
  - 评分或标记后自动下一张（可在设置里关闭）
  - 星级和旗标保存在本地 `Application Support/PhotoViewer/marks.json`，不修改原始文件
  - 筛选栏可“删除废片”，一次删除所有 `X` 标记的照片；删除前会显示张数和文件数
  - `⌘Z` 从废纸篓恢复最近一次删除（整对 NEF+JPG 和标记一起恢复）
- `←` / `→` 切换上一张、下一张，工具栏和画面左右边缘都有按钮
- 底部胶片条：缩略图、当前项高亮、评分/废片角标，随当前照片自动滚动；下方带常显细滚动条，可拖动
- 胶片条可折叠：`T` 或筛选栏右侧箭头收起；折叠后底部只保留 22px 的展开条
- 网格视图：`G` 切换，单击选中、双击打开单张；`E` 回到单张
- 2-up 对比：`C` 进入，左边当前、右边下一张；共享缩放/平移，适合连拍检查对焦；点击右图可把它设为当前
- 4-up Survey：`N` 进入，显示当前及后续最多 3 张；点击任意一格设为当前，方向键移动并自动滚动窗口；共享缩放/平移
- 对比模式下 `⌘0 / ⌘1 / Z` 仍可适应窗口、100% 和来回切换；Survey 使用预览分辨率，检查对焦请用 2-up
- 缩略图异步加载并缓存，不会一次性解码整个文件夹
- `Delete` / `Backspace` 将当前照片移到 macOS 废纸篓
  - RAW+JPEG 会一起删除，不会留下孤儿 NEF
  - 删除后自动显示下一张
  - 删除的是最后一张时回到上一张
  - 删除唯一一张时显示空状态
  - 删除失败会弹出具体错误
- 图片等比适应窗口，黑色背景，不拉伸
- 缩放与平移：
  - 触控板双指捏合缩放
  - 双击图片在「适应窗口 / 100%」之间切换
  - 右下角有 `− / 百分比 / + / 适应 / 1:1` 控制条
  - 鼠标指针在图片上时，滚轮缩放；或使用 `⌘ + 滚轮`
  - 放大后按住左键拖动平移
  - 放大到需要更多细节时，自动按需加载高分辨率图
- 全屏浏览（工具栏按钮、`F` 或 `⇧⌘F`，`Esc` 退出全屏）
- 浮动控件自动隐藏：鼠标静止约 2 秒后，左右切换箭头和右下角缩放条淡出；鼠标在图片上移动、滚轮缩放、捏合或拖动时重新出现。顶部原生工具栏保持常驻。
- 支持把图片或文件夹直接拖进窗口
- 支持 Finder「打开方式」以及 `open -a PhotoViewer xxx.jpg`
- 前后各预加载一张，切换时优先命中缓存
- 图片使用 ImageIO 下采样解码，不会把整个文件夹的原图一次性读入内存

支持格式：Nikon NEF、JPEG、PNG、HEIC/HEIF、TIFF、GIF（首帧）、BMP、WebP。

NEF 使用 macOS ImageIO 解码，已在 Nikon Z30（5568×3712）样本上验证。其他品牌 RAW（CR3/ARW/DNG/RAF 等）尚未接入。

首次打开桌面、文稿、下载等受 macOS 保护的目录时，系统会请求一次文件访问权限，允许即可。

## 构建与运行

环境要求：

- macOS 15 或更高
- Apple Silicon（当前构建为 arm64）
- Swift 6 工具链（完整 Xcode 或 Xcode Command Line Tools 均可）

在项目根目录执行：

```bash
./Scripts/build_app.sh
open dist/PhotoViewer.app
```

脚本会：

1. `swift build -c release`
2. 组装 `dist/PhotoViewer.app`
3. 复制 `Info.plist` 和图标
4. 做本地 ad-hoc 签名

如果命令行环境对 SwiftPM 的 sandbox 有限制，可以加：

```bash
./Scripts/build_app.sh --disable-sandbox
```

## 运行检查

项目没有引入 XCTest（Command Line Tools 环境不自带 XCTest），而是提供了一个可执行检查程序，覆盖自然排序、RAW/JPEG 配对、ImageIO 解码、删除后的索引规则、缩放几何和控件自动隐藏：

```bash
swift run PhotoViewerChecks
# 或者
./.build/release/PhotoViewerChecks
```

还可以用它检查一个真实文件夹的配对结果：

```bash
./.build/debug/PhotoViewerChecks --scan "/path/to/photos"
# shots: 300  pairs: 297  raw-only: 3  jpeg-only: 0
```

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `←` / `→` | 上一张 / 下一张 |
| `G` | 网格视图 / 单张视图切换 |
| `E` | 回到单张视图 |
| `C` | 2-up 对比视图 |
| `N` | 4-up Survey 视图 |
| `T` | 折叠 / 展开底部胶片条 |
| `1–5` | 打 1–5 星 |
| `0` | 清除星级 |
| `P` | 标记为保留 |
| `X` | 标记为废片 |
| `U` | 取消保留/废片 |
| `Delete` / `Backspace` | 移到废纸篓（RAW+JPEG 一起） |
| `⌘Z` | 撤销最近一次删除 |
| `J` | 切换当前照片的 NEF / JPEG |
| `Z` | 适应窗口 ↔ 100% |
| `F` | 全屏 |
| 双击图片 | 适应窗口 ↔ 100% |
| 触控板捏合 | 缩放 |
| 鼠标滚轮（指针在图片上） | 缩放 |
| `⌘` + 滚轮 | 缩放 |
| `⌘+` / `⌘-` | 放大 / 缩小 |
| `⌘0` | 适应窗口 |
| `⌘1` | 原始比例（100%） |
| `⌘O` | 打开图片 |
| `⇧⌘O` | 打开文件夹 |
| `⇧⌘F` | 全屏 |
| `Esc` | 退出全屏 |

## 让 Finder 双击直接打开

`Info.plist` 已注册常见图片类型，但 `LSHandlerRank` 是 `Alternate`，不会抢走系统「预览」的默认打开方式。

任选一种方式：

1. 右键图片 → 打开方式 → PhotoViewer
2. 选中一张图片 → `⌘I` 显示简介 → 打开方式 → 选择 PhotoViewer → 全部更改

设置后，双击图片就会直接用 PhotoViewer 打开，并自动加载同文件夹。

也可以先把 `dist/PhotoViewer.app` 拖到 `/Applications`，再设置默认打开方式。

## 实现要点

- `ImageDecoder`：用 `CGImageSourceCreateThumbnailAtIndex` 按屏幕尺寸下采样，并应用 EXIF 方向
- `ImageLoader`：后台解码 + `NSCache` + 前后一张预加载；放大时单独加载一张高分辨率图
- `ZoomState`：独立的缩放/平移几何，100% 表示 1 个图片像素对应 1 个屏幕物理像素
- `ChromeVisibility`：浮动控件在鼠标静止 2 秒后隐藏，鼠标移入或缩放/拖动时恢复
- `ThumbnailLoader`：胶片条/网格的缩略图异步加载和缓存
- `ViewMode`：单张（loupe）、网格（grid）与 2-up 对比（compare）
- `CompareView` / `ComparePane`：共享缩放和平移的双图对比
- `SurveyView`：四宫格选片，点击切换当前，窗口随方向键滑动
- `DeletionUndo`：记录最近一次删除的废纸篓路径和标记，`⌘Z` 恢复
- `ShotMark` / `ShotMarkStore`：本地星级、保留/废片和 JSON 持久化
- `ShotFilter`：全部、未评级、保留、废片
- `CullingMath`：评分/标记后的自动前进索引
- `FolderScanner`：只扫描当前文件夹、过滤隐藏文件/包，使用 `localizedStandardCompare` 自然排序；`scanShots` 把 NEF+JPG 按文件名主体配对
- `Shot`：一张逻辑照片，包含 NEF/JPEG 两个文件；删除时遍历整组文件
- `TrashService`：只调用 `FileManager.trashItem`，不永久删除；`restore` 用于撤销
- `BrowserMath`：统一处理删除后的索引，避免越界
- `BrowserViewModel`：负责打开、扫描、切换、视图模式、评分/旗标、过滤、删除、批量删除、撤销和错误状态
- `KeyboardManager`：局部 `NSEvent` monitor，仅在主窗口生效，避免影响打开面板
- `OpenRequestCenter`：缓存 Finder 在窗口创建前发来的打开请求

```
Sources/
├── PhotoViewerCore/      # 可测试的核心逻辑（扫描、解码、缓存、废纸篓）
├── PhotoViewer/          # SwiftUI/AppKit 应用层
│   ├── App/
│   ├── Views/
│   └── Support/
Tools/PhotoViewerChecks/   # 命令行检查
Resources/                 # Info.plist、AppIcon.icns
Scripts/build_app.sh       # 打包脚本
```

## 已知限制 / 下一步

当前版本尚未实现：

- 按星级/旗标组合的高级过滤
- XMP / Lightroom 星级互通（当前星级只在 PhotoViewer 本地生效）
- 其他品牌 RAW（NEF 已支持）
- GIF 动画播放（当前显示首帧）
- 鼠标滚轮切换、空格 Quick Look
- App Sandbox、Developer ID 签名和公证（当前是本地 ad-hoc 签名）

这些都可以在现有结构上继续加，不需要推翻重写。

## 隐私

- 不联网、不上传图片
- 不修改原始图片
- 只有用户明确按下删除或点击删除按钮时，才会把文件移到系统废纸篓
- 缓存只保存在内存中，退出即释放
