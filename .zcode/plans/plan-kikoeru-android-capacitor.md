# Kikoeru Android 版规划（Capacitor 混合方案）

## 1. 结论先行

**可行，且成本可控。** 核心判断依据：渲染层 `app.js` 已经写成"无 Electron 也能跑"——它对 `window.kikoeru` 全部走可选调用（`window.kikoeru?.X`），已有浏览器降级逻辑（`webkitdirectory` 导入、fetch `package.json` 取版本号、桌面功能缺失时 Toast 提示）。这意味着同一份 UI 代码（`index.html` + `app.js` + `styles.css`）可以直接装进 Android WebView，只要写一个原生插件补齐 `window.kikoeru` 的全部接口，就能做到"功能与代码统一"。

技术路线（已确认）：**Capacitor 混合方案**，原生层用 Kotlin。
统一范围（已确认）：**功能与代码统一**——三端（macOS / 浏览器 / Android）功能对齐、UI 代码共享；Android 音声库独立，**不做**跨端数据同步。

## 2. 现状盘点（可复用资产）

### 2.1 已实现功能（0.24.0 → 0.26.0）
1. 本地文件夹导入：按文件夹聚合、递归扫描、深层目录 RJ 号提取、封面自动识别（`cover/front/封面` 等）
2. 封面：离线 SVG 封面 + 内嵌封面（≤500px JPEG dataURL）+ 文件夹封面图
3. 元数据解析（music-metadata）：标题/社团/声优/专辑艺术家/时长/内嵌图
4. 网格浏览、搜索（标题/社团/声优）、排序（最近添加/标题/时长）
5. 筛选：未听完 / 已收藏；视图：全部/最近添加/正在播放/收藏夹 + 4 个分类
6. 详情侧栏：封面、标签、RJ 号、曲目列表、进度、收藏、从头播放
7. 真实音频播放：播放/暂停/上一首/下一首/进度拖动/音量；4 种播放模式（列表/单曲/随机/专辑循环）
8. 主题（浅/深）+ 6 色强调色；侧栏折叠；⌘K 聚焦搜索
9. 多选模式：全选 / 刮削标签 / 删除所选 / 删除所选及源文件
10. 右键菜单：刮削 DLsite 标签 / 打开所在文件夹 / 删除 / 删除及源文件
11. DLsite 标签刮削：RJ 号提取、代理支持、卡片（前 3 个 +N）/详情（全部）展示、手动/批量触发、进度条
12. 清理失效记录、打开数据目录、导入/刮削进度条、确认对话框、Toast

### 2.2 架构与接口
- `main.js`（Electron 主进程）：库持久化 `library.json`（userData）、递归扫描、music-metadata 解析、DLsite 刮削（net.fetch + 代理）、全部 IPC handler
- `preload.js`：contextBridge 暴露 `window.kikoeru` —— 这是**接口契约**，Android 插件照此实现即可：
  `loadLibrary / saveAlbums / removeAlbum / removeAlbums / cleanMissing / getVersion / openDataDir / importAudioFolder / onImportRequested / onImportProgress / scrapeDlsite / onDlsiteProgress / getScrapeConfig / setScrapeConfig / revealInFolder`
- `app.js`（渲染逻辑，跨端共用）：视图/筛选/排序/封面/详情/播放器/主题/多选/删除/右键菜单/刮削 UI/进度条
- `styles.css`（跨端共用，需加移动端断点）
- `server.js`：浏览器预览（现有降级模式，正是 Android WebView 的预演）

### 2.3 与 Android 的主要差异点
| 能力 | macOS（已有） | Android（要补） |
|---|---|---|
| 文件夹选择 | `dialog.showOpenDialog` | SAF `ACTION_OPEN_DOCUMENT_TREE` + `takePersistableUriPermission` |
| 文件访问 | 文件系统路径 `file://` | `content://` URI（DocumentFile 遍历） |
| 元数据解析 | music-metadata（Node） | `MediaMetadataRetriever`（系统内置） |
| 封面缩放 | Electron `nativeImage` | BitmapFactory + Canvas + JPEG 压缩 |
| 网络请求 | Electron `net.fetch`（无 CORS） | `@capacitor/http`（原生 OkHttp，无 CORS）或插件内 OkHttp |
| 播放 | HTML5 `<audio>`（Electron 内核） | 原生 Media3 + 前台服务通知/锁屏；或先期 HTML5 `<audio>` 兜底 |
| 后台播放/通知 | 无需 | 必需：MediaSessionService + 媒体通知 + 音频焦点 |
| 右键菜单 | contextmenu 事件 | 长按手势（touch 事件适配） |
| 打开所在文件夹 | `shell.openPath` / `showItemInFolder` | 尽力而为：DocumentsUI 打开树/分享 |
| 打开数据目录 | `shell.openPath` | 替换为"导出库文件"分享或打开外部文件目录 |
| 版本号 | Electron `app.getVersion` | `BuildConfig.VERSION_NAME` |

## 3. 总体架构

```
┌─────────────────────────────────────────────────┐
│  Kikoeru UI（index.html + app.js + styles.css）     │ ← 三端共用同一份（含移动端断点）
│  长按菜单 / 平台标记 / 移动端布局适配（少量共享改动）      │
└───────────────────┬─────────────────────────────┘
            window.kikoeru API（同签名契约）
┌───────────────────┴─────────────────────────────┐
│ macOS: Electron main.js     （已有，不动）            │
│ Web:   server.js 降级模式     （已有，不动）            │
│ Android: Capacitor 原生插件 KikoeruPlugin（Kotlin）   │
│   ├ LibraryStore.kt    library.json 持久化（filesDir）│
│   ├ Import/            SAF 扫描 + 元数据 + 封面 + RJ    │
│   ├ Playback/          Media3 服务 + 通知 + 锁屏       │
│   ├ Scrape/            DLsite 抓取（OkHttp/共享解析）   │
│   └ android/           （npx cap add android 生成）   │
└─────────────────────────────────────────────────┘
        web/（Capacitor webDir，由 scripts/sync-web.js 生成）
        ├ kikoeru-bridge.js  window.kikoeru = Capacitor 封装
        └ native-audio.js    <audio> DOM shim → Media3
```

- **单份 UI 源码**：`index.html / app.js / styles.css` 仍是仓库根目录的真源。`scripts/sync-web.js` 构建时拷贝进 `web/`（Capacitor webDir），避免双份维护。
- **接口契约**：`preload.js` 的 `window.kikoeru` 签名 = 插件必须实现的签名，事件名（`import:progress` / `dlsite:progress`）也保持一致。
- **平台标记**：桥接层注入 `window.kikoeru.platform = 'android'`，共享代码里需要分支的地方据此判断。

## 4. 工程结构（同一仓库，桌面端不动）

```
New project/
├── index.html / app.js / styles.css / main.js / preload.js / server.js   （桌面端，不变）
├── capacitor.config.ts
├── android/                            ← npx cap add android 生成
│   └── app/src/main/java/top/voicehub/kikoeru/
│       ├── KikoeruPlugin.kt            （插件入口，@CapacitorPlugin + MainActivity 注册）
│       ├── LibraryStore.kt
│       ├── ImportScanner.kt            （递归扫描 + 分组 + RJ 提取）
│       ├── AudioMetadata.kt            （MediaMetadataRetriever 解析 + 封面缩放）
│       ├── PlaybackController.kt       （Media3 状态桥接，事件转发）
│       ├── PlaybackService.kt          （MediaSessionService + 前台通知）
│       └── DlsiteClient.kt             （可选：若刮削走 JS 侧则可省）
├── web/                                ← 构建产物（git 忽略或提交均可）
│   ├── index.html / app.js / styles.css （sync-web.js 拷贝）
│   ├── kikoeru-bridge.js
│   └── native-audio.js
├── scripts/
│   ├── sync-web.js                     （新增：拷贝共享文件 + 注入 Android 专有脚本）
│   ├── bump-version.js                 （已有）
│   └── create-test-library.js          （已有，可复用做导入测试数据）
└── package.json                        （新增 @capacitor/cli/core/android/http + scripts）
```

appId / 包名沿用现有 `top.voicehub.kikoeru`。

## 5. 核心模块设计

### 5.1 桥接层（kikoeru-bridge.js）
`window.kikoeru` 的 Capacitor 实现，逐个对齐 preload.js 签名：
- `loadLibrary() / saveAlbums(albums)` → 调用 `KikoeruPlugin.loadLibrary()/saveAlbums()`（JSON 原样透传，schema 与桌面完全一致）
- `importAudioFolder()` → 插件拉起 SAF 树选择 → 扫描 → 返回 `{canceled, albums, scannedPath}`，与桌面同构
- `onImportProgress(cb)` / `onDlsiteProgress(cb)` → `Capacitor.addListener('import:progress'/'dlsite:progress', ...)`，payload 结构与桌面 IPC 事件一致（`{folderIndex, folderTotal, processed, total}` / `{processed, total}`）
- `scrapeDlsite(ids, force)` / `getScrapeConfig()` / `setScrapeConfig(cfg)` → 插件（或 JS 侧 CapacitorHttp 实现，见 5.5）
- `removeAlbum / removeAlbums / cleanMissing / getVersion / openDataDir / revealInFolder` → 插件对应实现
- `onImportRequested` → Android 无菜单，注册为空实现（不触发）
- 注入 `platform: 'android'`、`isAndroid: true`

### 5.2 库持久化（LibraryStore.kt）
- `library.json` 存 `context.filesDir`，schema 与桌面 `{albums: [...]}` 一致（字段含 `sourcePath / tracks[].url / localCover / rjCode / tags / dlsiteTitle / played / favorite / ...`）
- 关键差异：`tracks[].url` 存 **content:// URI 字符串**，`localCover` 为 dataURL 或 content:// URI
- 导入时对根树 URI `takePersistableUriPermission`；启动时校验权限，丢失则提示重新授权

### 5.3 导入管线（ImportScanner + AudioMetadata）
对齐 main.js `scanAlbum / scanFolder / findFiles` 的行为：
1. `ACTION_OPEN_DOCUMENT_TREE` 选根目录（支持多选 → 依次处理，映射桌面 `folderIndex/folderTotal`）
2. `findFiles` 递归遍历（跳过 `.` 开头），按**直接父目录**聚合分组（= `groupFilesByFolder`）
3. 每张专辑：仅取音频扩展名（mp3/m4a/wav/flac/ogg/aac/opus/webm），文件名自然序排序
4. 元数据：`MediaMetadataRetriever.setDataSource(context, contentUri)` → 时长/标题/艺术家/专辑/专辑艺术家/内嵌图；解析失败的曲目用文件名兜底（与桌面注释一致："可播放的本地文件即使标签损坏也应可导入"）
5. 封面：内嵌图 → Bitmap 缩放到 ≤500px → JPEG 82% → `data:image/jpeg;base64,...`（与桌面 `coverDataUrl` 同策略，控制 library.json 体积）；文件夹封面按 `(cover|front|folder|album|封面)` 优先级取
6. RJ 号：`/RJ\d{5,}/i` 从**路径全层级**提取（对应 0.26.0 深层目录修复），回退标题/曲目名
7. 专辑兜底字段与桌面一致：`title`（多数专辑名或文件夹名）、`artist`（多数声优或"本地导入"）、`group:'本地文件夹'`、`genre:'未分类'`、`shape/color` 默认、`date:now`、`played:0`、`favorite:false`
8. 进度：每完成一张发 `import:progress`；合并入库（按 `id` 去重，id 用路径 stableId，与桌面 `local-<sha1(path)>` 同源算法）
9. 已知取舍：`MediaMetadataRetriever` 对 FLAC/Ogg 的专辑艺术家、部分格式封面支持受系统版本影响，缺失即回退（桌面同策略）；不引入额外 tag 库

### 5.4 播放（PlaybackService + PlaybackController + native-audio.js）
目标：**原生 Media3 引擎 + 前台媒体通知 + 锁屏控制 + 后台播放**，同时让 app.js 零改动。
- `native-audio.js`（在 Android 构建的 index.html 中先于 app.js 加载）：将 `<audio id="audio">` 替换为 DOM shim，仅对 `#audio` 这个 selector 做特殊化（`document.querySelector` 补丁），实现 app.js 用到的媒体接口：`src / currentTime / duration / paused / volume / muted` + `play() / pause()` + 事件 `timeupdate / loadedmetadata / play / pause / ended`
- shim 将操作转发给 `KikoeruPlugin.playback`：`play(uri, meta)` / `pause` / `seek(ms)` / `setVolume`；原生侧回推事件 `audio:timeupdate / audio:ended / audio:duration / audio:state`，shim 同步属性并派发 DOM 事件 → app.js 的 `audio.addEventListener('timeupdate'...)` 等照常工作
- 原生侧：`MediaSessionService` + `ExoPlayer` + `MediaSession`，设置前台通知（封面/标题/播放暂停/上一首/下一首）、音频焦点、`setMediaNotificationProvider` 锁屏控件
- 通知上的"上一首/下一首/播放暂停" → `audio:command` 事件 → shim 触发 `#prevBtn/#nextBtn/#playBtn` 的 `.click()`，**复用渲染层播放逻辑**（播放模式/队列全部走 app.js 现有实现）
- 进度条拖动 = `audio.currentTime = ...` setter → 原生 seek；`ended` → 原生发事件 → app.js 的 `ended` 处理器决定单曲循环/下一首
- **兜底方案**：若 DOM shim 复杂度过高风险不可控，第一版可先用 HTML5 `<audio>` 直接播 content:// URI（Android WebView 默认允许 content 协议，`setAllowContentAccess(true)`），前台播放即可全功能对齐；后台播放+通知作为独立里程碑跟进

### 5.5 DLsite 刮削
- 网络：走 `@capacitor/http` 的 `CapacitorHttp.get()`（原生 OkHttp，**无 CORS**，绕开 WebView 对 dlsite.com 的跨域拦截）；或用插件内 OkHttp
- 解析：优先把 main.js 的正则解析（`parseDlsiteTags / parseDlsiteTitle / extractRjCode / albumRjCode`）**抽成共享 JS 模块**（如 `dlsite-shared.js`），macOS 与 Android 复用同一套正则，避免两处漂移；若抽模块超出范围，则在 Kotlin 内等价移植（正则同款）
- 流程与桌面一致：逐个专辑顺序请求、间隔 ~400ms 限速、失败跳过不中断、返回 `{scraped, failed, skipped, noRj, details}`、每张发 `dlsite:progress`
- 代理：设置项保留（API 对齐），Android 默认留空直连（127.0.0.1 代理在手机上无意义），若填写则交给 OkHttp `Proxy` 使用

### 5.6 数据操作
- `removeAlbum / removeAlbums(ids, deleteFiles)`：库记录删除 + `DocumentFile` 逐文件删除（对应桌面 `fs.rm`），目录非空则保留（`rmdir` 语义）；`deleteFiles` 选项 UI 在 Android 同样显示（轨道 url 是 content:// 时菜单项判断需放宽，见 6）
- `cleanMissing()`：`contentResolver.openFileDescriptor(uri)` 或 `DocumentFile.exists()` 检测失效；逻辑与桌面一致（专辑曲目全失效 → 删专辑；部分失效 → 保留存活曲目）
- `revealInFolder`：尽力而为——`ACTION_VIEW` 打开专辑内第一个文件，或用树 URI 打开 DocumentsUI；实现限制在计划内说明（Android 无 Finder 语义）
- `openDataDir`：改为"导出音声库"（ShareCompat 分享 library.json）或打开外部文件目录；app.js 已有降级 Toast，仅需桥接层实现

### 5.7 版本号
- `getVersion()` 返回 `BuildConfig.VERSION_NAME`；Android `versionName` 与 package.json 版本对齐（后续可扩展 bump-version 同时改 gradle，M0 先手动对齐）

## 6. 移动端 UI 适配（共享代码的少量改动清单）

原则：**尽量在 `styles.css` 用断点解决，少量 `app.js` 改动全部用平台标记或能力检测包裹，不破坏 macOS/浏览器行为。**

### styles.css（新增移动端断点 @media (max-width: ~720px)）
- 侧栏 → 底部导航（全部/最近/播放/收藏）+ 分类收纳；`sidebar-hidden` 逻辑复用于抽屉开合
- 顶栏/hero 精简；工具栏搜索框占满一行，⌘K 提示隐藏
- 网格 2 列（竖屏）/ 3 列（横屏/平板）；卡片触控目标加大（≥44px）
- 详情侧栏 → 全屏底部弹层（`details.open` 样式覆盖）
- 播放条固定底部、按钮加大；音量/模式弹层触控适配
- 多选操作条 → 底部悬浮条；设置弹层 → 全屏
- 全窗口根元素加 `platform-android` class，与移动端断点配合

### app.js（共享改动，全部可选调用/能力检测）
- 右键菜单 → 长按：`touchstart` + 定时器（~500ms）触发 `showCtxMenu`，仅在 `ontouchstart` 存在时注册；桌面 contextmenu 逻辑保留
- 菜单项显示判断 `t.url.startsWith('file:')` → 增加 `|| t.url.startsWith('content:')`（桌面行为不变）
- `⌘K`：移动端改为点击搜索框即聚焦（原生行为），无需改代码
- 桌面专属功能（`openDataDir` / `revealInFolder`）保留现有 `window.kikoeru?.X` 可选调用与 Toast 降级——Android 桥接层实现后即为可用状态

### index.html
- 引用 `styles.css / app.js` 不变；Android 构建版（web/ 内）额外加载 `native-audio.js`、`kikoeru-bridge.js`

## 7. 权限与 Manifest
- `INTERNET`（刮削）
- `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_MEDIA_PLAYBACK`（后台播放通知）
- `POST_NOTIFICATIONS`（Android 13+ 运行时申请，或随播放时申请）
- 媒体按钮（`MEDIA_BUTTON` intent-filter，MediaSessionService 自带）
- **无需**存储读权限：全程 SAF，系统级授权，不碰 `READ_MEDIA_AUDIO`
- WebView：`setAllowContentAccess(true)`（HTML5 兜底方案需要）

## 8. 构建与发布
- 开发流：改共享文件 → `node scripts/sync-web.js` → `npx cap sync android` → `./gradlew assembleDebug` → 装真机/模拟器
- 真机调试需 `adb reverse tcp:5173 tcp:5173` 或走 `cap run android` 的 livereload
- 发布：签名配置（keystore 放入 `android/` 不入库）、`assembleRelease`、`versionName` 与桌面版本对齐
- 回归保障：每次发布前跑 `npm run dev`（浏览器）+ `npm run desktop`（macOS），确认共享代码改动未回归桌面

## 9. 里程碑

| 阶段 | 内容 | 出口标准 |
|---|---|---|
| **M0 脚手架** | capacitor init + `sync-web.js` + `cap add android` + 插件骨架 + 桥接层（loadLibrary/saveAlbums/getVersion/platform） | 应用在 Android 启动、读到空库、版本号显示 |
| **M1 导入** | SAF 树选择、递归扫描、元数据/封面/RJ 提取、进度事件、合并入库 | 导入 RJ 命名测试文件夹 → 卡片/详情/标签正确；进度条走完 |
| **M2 播放** | Media3 服务 + DOM shim；播放/暂停/seek/上下曲/ended；后台播放 + 通知 + 锁屏 | 全播放模式可用；灭屏继续播；通知可控制 |
| **M3 刮削** | CORS-free 请求 + 共享解析 + 进度 + 代理设置 | 对测试 RJ 专辑刮削成功，卡片/详情显示标签 |
| **M4 数据操作** | removeAlbum(s)/cleanMissing/revealInFolder/openDataDir/版本对齐 | 删除（含源文件）、清理失效、打开文件夹走通 |
| **M5 移动端 UI** | 响应式断点、底部导航、长按菜单、全屏详情/设置 | 手机竖屏/横屏/平板操作顺畅，触控目标达标 |
| **M6 打磨发布** | 图标/启动页、签名 APK、桌面+浏览器回归、README 更新 | 发布 Release APK；macOS/web 无回归 |

## 10. 测试计划
- **数据**：复用 `scripts/create-test-library.js` 造 RJ 命名测试专辑（含封面、多曲目、深层目录）
- **导入**：SAF 选树 → 验证分组/元数据/封面/RJ；含无标签、损坏标签、深层目录场景
- **播放**：前台/后台/锁屏/灭屏；4 种播放模式；seek；音量；通知控制；来电/焦点中断
- **刮削**：单张/批量/强制重刮/无 RJ 号；断网重试
- **数据操作**：删库不删文件/连文件删除（验证 DocumentFile 删除后重导入）/清理失效
- **UI**：横竖屏、不同尺寸设备、长按菜单、多选流程、主题/强调色
- **回归**：浏览器 `npm run dev` + macOS `npm run desktop` 全功能烟测

## 11. 风险与应对
| 风险 | 应对 |
|---|---|
| WebView 播放/后台不可控 | 主方案原生 Media3；HTML5 `<audio>` 前台播放为 M2 兜底，可先发布再升级 |
| DOM shim 与 app.js 媒体用法有出入 | 先跑通 HTML5 版建立基线，再切 shim；shim 只对 `#audio` 生效，影响面可控 |
| `MediaMetadataRetriever` 标签覆盖不全（FLAC 专辑艺术家等） | 与桌面同策略回退；不引第三方 tag 库 |
| dlsite.com CORS | CapacitorHttp / OkHttp 原生请求，无 CORS |
| 共享文件改动回归桌面 | 发布前强制双端烟测；改动全部可选调用/能力检测包裹 |
| SAF 权限丢失（用户撤销/重启） | 启动时校验 + 提示重新授权；库内 URI 失效走 cleanMissing |
| 刮削正则与桌面漂移 | 优先抽 `dlsite-shared.js` 共享模块，macOS 与 Android 复用 |

## 12. 明确不做（本期范围外）
- 跨端数据同步（macOS ↔ Android 库同步）——用户已确认只做功能与代码统一
- 云端服务、账号体系
- Windows 桌面版（同一套 Capacitor 架构未来可顺带支持，本期不承诺）

## 13. 已确认决策（2026-08-13）
1. **最低 Android 版本：API 35（Android 15）**，targetSdk API 36（Android 16）——用户已确认，面向新设备，无兼容负担
2. **测试方式：真机 + macOS 模拟器均可**，从 M1 起直接手动验证
3. **web/ 目录不进 git**（.gitignore），由 `scripts/sync-web.js` 构建时生成
4. 技术路线：Capacitor 混合方案（已确认）；统一范围：功能与代码统一，不做跨端数据同步（已确认）

## 20. 日文内容适配 + 中文环境验证（2026-08-14）

用户反馈：DLsite 专辑/曲名基本是日文，测试要多用日文；实机是中文环境。已处理：

1. **日文标签乱码还原升级**：日文标签常用 **Shift-JIS** 编码，原 GBK-only 还原会把它错误还原成中文乱码。`repairText` 改为**多字符集打分**——GB18030 / Shift_JIS / windows-31j 逐一还原，按"假名 +3、汉字 +2、日文标点 +1"取分最高者；`looksGarbled` 与正常文本判定把**假名（平假名/片假名）**也视为正常字符。
2. **日文字体**：样式字体栈加入 Noto Sans JP（`DM Sans / Noto Sans SC / Noto Sans JP`）。
3. **验证（zh-CN locale 模拟器 + 真实日文测试文件）**：
   - UTF-8 日文标签（ID3v2.4）→ 标题「RJ05000123_癒しの耳かきASMR」/ 声优「サークル名 ～CV. CV名～」/ 曲目「耳かきASMR ～癒しのひととき～」正常
   - **Shift-JIS 日文标签（ID3v2.3 encoding=0x00）→ 正确还原为日文**（打分选对 Shift_JIS）
   - 无标签日文文件夹 `RJ05000124_耳かきASMR ～癒しのひととき～` → 剥离 RJ 前缀显示「耳かきASMR ～癒しのひととき～」
   - 中文 locale 下 SAF 授权、导入、详情展示全部正常

## 19. 专辑标题显示为文件夹名修复（2026-08-14）

用户反馈：部分专辑名显示成文件夹名，应显示专辑名。已定位：DLsite 下载的音频普遍**不带 ALBUM 标签**（只有每曲 TITLE/ARTIST），此时回退显示原始文件夹名（如 `RJ030000061_噪声专辑61`）。

**修复**：`cleanFolderTitle`——文件夹名回退时剥离 DLsite 命名前缀 `RJ\d{5,}[_\- ]+`，只保留作品名（`RJ123456_雨夜耳语 → 雨夜耳语`）；元数据 ALBUM 标签仍优先（含乱码还原）。验证：100 张 RJ 前缀文件夹专辑重导后标题全部变干净、无残留；GBK 还原专辑不受影响。旧专辑重导后（按 id 覆盖）自动生效。

## 18. 大库导入崩溃与乱码修复（2026-08-14）

用户实机反馈：90+ 专辑导入崩溃（回桌面）、重回软件专辑"慢慢出现"、专辑名乱码。已定位并修复：

1. **崩溃/慢加载根因 = 桥载荷过大**：整份 library.json（含 base64 封面）经 native↔JS 桥整体传输。实测 143 张专辑（500px/300KB 封面）library.json 达 **13.7MB**——实机堆小 → 桥序列化/WebView 解析 OOM 崩溃；重进软件解析大 JSON 就是"专辑慢慢出现"。
   **修复**：Android 封面策略降为 **300px / JPEG 75% / ≤120KB**（手机屏幕视觉无损）。实测 100 张噪声封面专辑导入：载荷 13.7MB → **4.01MB**（缩 3.4 倍）、10s 内完成无崩溃、**重启加载 <1s**。
2. **专辑名乱码根因 = MediaMetadataRetriever 误读 GBK ID3**：中文 MP3 的 GBK/GB2312 标签常被按 ISO-8859-1 解码成拉丁乱码（如 你好世界 → ÄãºÃÊÀ½ç）。
   **修复**：`repairText` 启发式——检测"无 CJK 但含 Latin-1 扩展字符"的乱码特征 → ISO-8859-1 重编码 → GB18030/GBK 重解码，仅当还原结果含 CJK 才采纳（正常中文/英文不误伤，JDK 单测通过）；仍乱码则 `looksGarbled` 回退文件名（恒为正确 Unicode）。
   **端到端验证**：构造 GBK 标签 MP3（修正 ID3v2.3 帧标志位为 2 字节后）→ 导入后 title「雨夜耳语专辑」/ artist「测试声优」/ 曲目「你好世界」全部正确还原并正常显示。

## 17. 导入稳定性与交互修复（2026-08-14）

用户反馈：导入无进度条、多文件多专辑导入慢且崩溃（回桌面、专辑全部丢失）。已修复：

1. **导入崩溃根因 = 大封面整图解码 OOM**：原 `coverDataUrl` 直接 `decodeByteArray` 全尺寸解码（实机几千像素封面单图占几十上百 MB）。改为 **inSampleSize 先降采样（解码上限 1000px）再缩放**，bitmap 及时 recycle；`readBytes` 加 15MB 文件门控。**压力验证**：40 张专辑 × 4000×4000 封面（全解码 64MB/张）导入全部成功，无 FATAL/OOM；封面平均压缩到 2.3KB，library.json 217KB。
2. **导入线程安全**：进度事件 `notifyListeners` 与最终 `call.resolve/reject` 改用 `execute{}` 切主线程投递，消除后台线程直接操作 WebView 消息通道的风险。
3. **增量保存**：每扫描 5 张专辑保存一次 library.json，崩溃也不丢全部（最终再保存一次）。
4. **进度条验证**：模拟器实测「正在导入 20 / 40 张专辑 → 40/40」，进度条 + 百分比实时显示（此前机制已通，崩溃掩盖了可见性）。
5. **点击左下角正在播放封面 → 跳转专辑详情**：`#nowCover` 绑定 `openDetail(selected)`，验证通过。

## 16. 触屏操作优化（2026-08-14，用户三连需求）

1. **抽屉点击外部关闭**：`index.html` 新增真实遮罩元素 `#sidebarBackdrop`（替代原 `::after` 伪元素），`app.js` 点击遮罩调用 `applySidebar(false)`；选完导航视图也自动收抽屉。验证：开抽屉→点遮罩→收起。
2. **系统返回手势逐层关闭浮层**：接入 `@capacitor/app`（8.1.1），桥接层注册 `backButton` 监听，按栈序关闭 确认框→右键菜单→多选→设置→详情→抽屉，无浮层时 `App.minimizeApp()` 最小化到后台。验证：详情/设置按返回键关闭、无浮层返回最小化。修复过程中发现并解决桥接层 `const cap` 声明在 `appPlugin` 之后导致 TDZ ReferenceError 的 bug。
3. **播放条两行布局**：移动端播放条改为 `flex-wrap` 两行——第一行封面/曲名/控制/模式音量，第二行（order:9, flex 100%）进度条整行下移成**大全宽进度条**（触摸高度 34px、轨道 6px、滑块 20px），紧贴底部导航上方；详情弹层/浮动条对应上移。验证：timeline 388px 全宽、底部 y=775 与导航 y=779 相接、播放回归正常。

## 15. 实机反馈修复（2026-08-14）

用户实机测试反馈两点，已修复并验证：

1. **界面不适应竖屏操作逻辑** → 根因：移动布局依赖 760px 媒体断点，实机 WebView 视口差异导致不触发。改为 **class 驱动**：Android 桥接层按 `innerWidth ≤ 1000` 设置 `html.mobile`（旋转跟随更新），Web 窄窗 `≤760` 同理由 app.js 设置。并新增**底部导航栏**（全部/最近/播放/收藏/设置），播放条改为固定于导航上方，详情/浮动条上移避让——手机原生操作逻辑。
2. **导入入口放偏好设置** → 设置「数据」区新增「导入文件夹」按钮，复用顶部导入按钮完整逻辑（Android SAF / 桌面对话框 / Web 文件夹选择），实机点击已拉起 SAF 选择器。

## 14. 实施状态（2026-08-14）

| 里程碑 | 状态 | 验证证据 |
|---|---|---|
| M0 脚手架 | ✅ | 模拟器运行：bridge 加载、空库、版本 0.26.0、UI 渲染（CDP 查询） |
| M1 导入 | ✅ | 3 张测试专辑导入（标题/封面/RJ/曲目/进度事件/重启持久化）；深层目录 RJ01234567 提取 |
| M2 播放 | ✅ | 播放/暂停/seek/上下曲/单曲循环/自动切曲循环；Home 后台继续播放；通知 id=1001 三动作；通知 PAUSE/NEXT/PLAY 生效且渲染层同步；元数据推送到通知 |
| M3 刮削 | ✅ | 真实 RJ01434001 抓取成功：8 标签 + 标题；卡片前3+N、详情全标签；代理 10.0.2.2:7890 走宿主代理；进度事件 1/3→3/3；404 优雅失败 |
| M4 数据操作 | ✅ | removeAlbum(仅库/含源文件 4 文件+空目录)、cleanMissing(移除 1 失效曲目)、openDataDir(分享面板)、revealInFolder(DocumentsUI 打开) |
| M5 移动端 UI | ✅ | 412px 竖屏：单列布局、抽屉侧栏默认收起、2 列网格、全屏详情、64px 播放条；长按唤起菜单（含 content:// 判断） |
| M6 打磨 | ✅ | Kikoeru K 图标、版本同步脚本、README、最终烟测（3 专辑/播放/布局无崩溃） |

**关键实现决策（与规划一致）**：
- 播放服务改用普通前台 Service + 手动 `startForeground` + MediaStyle 通知（MediaSessionService 的隐式前台化在短视频播放场景会触发 FGS 崩溃，已实测规避）
- 事件投递必须用 `Capacitor.Plugins.Kikoeru.addListener`（全局 `Capacitor.addListener` 不注册到插件事件表）
- 刮削在原生侧用 HttpURLConnection（直连无 CORS）；模拟器网络下 DLsite 经 fake-IP 代理 DNS 不可达，用代理 `10.0.2.2:7890` 走宿主代理验证

**遗留说明**：
- 桌面 main.js 的刮削正则未抽共享模块（Kotlin 侧等价移植），后续可抽 `dlsite-shared.js` 双端复用
- 模拟器直连 DLsite 受宿主代理网络限制；真机/正常网络下留空代理直连即可
- 发布 APK 需配置签名（keystore）后 `./gradlew assembleRelease`
