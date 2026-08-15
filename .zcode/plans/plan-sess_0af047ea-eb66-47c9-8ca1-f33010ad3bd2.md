# Hiko 歌词/字幕系统实施方案（方案二：详情抽屉双Tab + 方案四：系统级桌面置顶悬浮窗）

基于用户需求：
1. 自动加载同文件夹下的 `.lrc` 与 `.vtt` 歌词/字幕。
2. 实现 **方案二**：右侧抽屉（DetailDrawer）新增「曲目 / 歌词」双 Tab 切换联动。
3. 实现 **方案四**：macOS 原生轻量级「系统级置顶半透明悬浮窗（Desktop Lyrics HUD）」，主窗口后台或做其他事时依然悬浮显示当前台词。
4. 针对音声作品大多为单语字幕的实际情况，提供清晰聚焦的单语歌词展示与行级点击跳转（Seek）。

---

## 总体架构分层设计

```
hiko/
├── lib/
│   ├── lyrics/
│   │   ├── models/
│   │   │   └── lyric_line.dart           # 单行歌词/台词数据模型与文档模型
│   │   ├── parsers/
│   │   │   ├── lrc_parser.dart           # LRC 标准/多时间戳/元数据标签解析器
│   │   │   └── vtt_parser.dart           # WebVTT 时间跨度/说话人/HTML标签清洗解析器
│   │   ├── lyrics_resolver.dart          # 同目录/子目录扫描与 UTF-8/Shift-JIS/GBK 编码自动探测
│   │   ├── lyrics_controller.dart        # Riverpod 状态管理，O(log N) 二分查找高频定位，滑动防抖
│   │   └── desktop_lyrics_service.dart   # macOS MethodChannel 桌面悬浮窗通信服务
│   └── ui/
│       ├── lyrics/
│       │   └── drawer_lyrics_view.dart   # 抽屉歌词组件（滚动跟随、高亮、悬停时间点、点击跳转）
│       └── widgets/
│           ├── detail_drawer.dart        # 改造：顶部增加「曲目 (N) | 歌词 (LRC/VTT)」Segmented Tab
│           └── player_bar.dart           # 改造：右侧播控栏增加「桌面悬浮歌词」切换按钮
├── macos/
│   └── Runner/
│       ├── DesktopLyricsHUD.swift        # 原生 NSPanel + SwiftUI 浮动窗口（置顶/穿透/毛玻璃/多桌面漫游）
│       └── MainFlutterWindow.swift       # 注册 top.voicehub.hiko/desktop_lyrics 频道
└── test/
    └── lyrics_parser_test.dart           # 单元测试（LRC、WebVTT、多编码、二分查找）
```

---

## 模块详细设计

### 1. 数据模型与解析器 (`lib/lyrics/`)
- **`LyricLine` & `ParsedLyrics`**：
  - `Duration startTime`, `Duration? endTime`, `String text`, `String? speaker`。
  - `isActive(Duration position)` 快速区间判定。
- **`LrcParser`**：
  - 支持多时间戳行合并 `[00:10.00][00:20.00]台词`。
  - 支持 `[offset:+500]` 全局时间轴补偿。
  - 自动识别说话人前缀（如 `【店员】`、`女主角:`、`[speaker:xxx]`）。
- **`VttParser`**：
  - 支持 `00:01.000 --> 00:04.500` 与 `00:00:01.000 --> ...`。
  - 自动提取 `<v 角色名>台词</v>` 并剥离样式标签（`<b>`, `<i>`, `<c.color>`）与 HTML entities。
- **`LyricsResolver`**：
  - 扫描音轨同目录及 `lyrics/`, `lrc/`, `sub/`, `subtitles/` 子目录。
  - 匹配精确同名文件、前缀音轨号（`01. Intro.mp3` $\leftrightarrow$ `01.lrc`）。
  - 多字符集自适应解码：UTF-8 (含BOM) $\to$ `charset` 库评分（Shift-JIS、GBK、EUC-JP）$\to$ 彻底避免日文与中文乱码。
- **`LyricsController`**：
  - 监听 `playbackProvider` 的曲目切换与播放进度。
  - 使用 $O(\log N)$ 二分查找毫秒级计算当前句 `activeIndex`。
  - 自动滚动（Auto-Scroll）逻辑：用户手动滚动时暂停跟随 3 秒，之后平滑恢复。
  - 提供 `seekToLine(index)` 触发播放器瞬时跳转。

---

### 2. 方案二：右侧抽屉「曲目 / 歌词」双 Tab 联动 (`lib/ui/widgets/detail_drawer.dart` & `drawer_lyrics_view.dart`)
- **UI 布局**：
  - 在封面与操作按钮下方，将原本固定的曲目列表升级为精致的 **Segmented Control Tab**：
    - `📋 曲目列表 (12)` | `💬 歌词字幕`（当检测到有歌词时附带高亮小圆点或格式角标）
  - 切换到「歌词字幕」Tab：
    - 呈现丝滑垂直滚动的台词流。
    - **当前句**：字体放大（17px）、粗体、强调主题色高亮、左侧有微光指示器。
    - **非当前句**：适度透明度（45%）、浅灰配色。
    - **说话人角标**：若包含 `speaker`，显示精致彩色胶囊 Badge。
    - **悬停与跳转**：鼠标悬停在某一行时，右侧显示小时间戳（如 `03:45`），点击整行直接 Seek 到对应位置。
    - **无歌词提示**：当音轨无歌词文件时，展示友好占位图：“暂未检测到同名歌词文件 (.lrc / .vtt)”。

---

### 3. 方案四：系统级 macOS 置顶桌面悬浮歌词 HUD (`DesktopLyricsHUD.swift` + `desktop_lyrics_service.dart`)
- **原生 AppKit / SwiftUI 架构**：
  - 使用 `NSPanel`（`.floating` 层级，`.canJoinAllSpaces` 支持跨多桌面 Space 漫游，`.fullScreenAuxiliary` 全屏应用上方依然可见）。
  - `isMovableByWindowBackground = true`：按住半透明背景任意拖拽到屏幕任意角落。
  - 支持 **锁定（点击穿透 / Lock Mode）**：`panel.ignoresMouseEvents = true`，玩游戏或打字时鼠标点击直接穿透至下层窗口。
  - 半透明深色磨砂背景 + 柔和文字阴影，保证在任何桌面壁纸和应用背景下均清晰可读。
- **播控栏开关**：
  - 在 `PlayerBar` 的右侧控制区（音量按钮旁）新增「桌面悬浮歌词图标（💬 / 悬浮 HUD 开关）」。
  - 点击即可快速呼出 / 隐藏桌面置顶悬浮窗，状态持久化到 `settingsProvider`。

---

## 验证与测试方案

1. **单元测试 (`test/lyrics_parser_test.dart`)**：
   - 验证标准 LRC 解析（含偏移量、多时间戳、说话人前缀提取）。
   - 验证 WebVTT 解析（含时间跨度、`<v 角色>` 标签过滤、HTML 实体转义）。
   - 验证多编码检测（UTF-8、Shift-JIS 日文、GBK 中文无乱码）。
   - 验证二分查找当前句计算在各种边界条件下的正确性（0s、末尾、无歌词）。
2. **端到端功能验证**：
   - 本地运行 `flutter test`。
   - 在 macOS 上运行 `flutter run -d macos` 验证抽屉 Tab 切换、歌词同步滚动、点击跳转、悬停高亮。
   - 验证桌面悬浮 HUD 窗口的弹出、拖拽移动、跨全屏桌面显示、穿透锁定以及实时台词同步。
3. **发布封包与 GitHub 自动化**：
   - 递增 `hiko/pubspec.yaml` 版本号（1.20.0）与 Android `versionCode`。
   - 执行 `flutter build macos --release` 生成 release 产物。
   - 提交代码推送至 GitHub，打包产物并通过 `gh release create` 上传 Releases。
