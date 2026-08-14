# Kikoeru Flutter 重写计划（plan-kikoeru-flutter-rewrite）

> 目标：放弃 Electron + Capacitor 混合架构，用 Flutter 完全重写 Kikoeru，覆盖 **macOS + Android + Windows** 三平台。
> 旧代码（Electron/Capacitor）保留在仓库根目录作参考，功能对等后归档。
> 本文档为 Flutter 重写的里程碑与修复记录，新改动请追加章节。

## 1. 背景与决策（2026-08-14）

原架构：`index.html` / `app.js` / `styles.css` 三端真源，Electron（macOS/Web）+ Capacitor（Android）共用；
桥接契约 `window.kikoeru` 三方一致；播放层 Android 走原生 Media3 前台服务。

重写动因：多端覆盖（Flutter 一次编写覆盖桌面+移动）、UI 下限更高、开发效率更高。

### 已确认决策

| 决策点 | 结论 |
|---|---|
| 平台 | macOS + Android + Windows（不做 iOS / Web） |
| 旧数据 | 全新开始，不迁移旧 library.json，schema 自由设计（沿用已验证字段） |
| 存储 | library.json（JSON 整体读写；原子写 + 每 5 张增量保存防崩溃） |
| 播放 | just_audio + audio_service（Android: ExoPlayer + 前台服务通知锁屏；macOS: AVPlayer；Windows: just_audio_media_kit） |
| 状态管理 | Riverpod（flutter_riverpod） |
| Android 原生 | 移植 ImportScanner.kt / KikoeruPlugin.kt 为 MethodChannel 插件（SAF 导入、删除、cleanMissing、revealInFolder、openDataDir 分享导出） |
| 版本 | 从 1.0.0 重启；每次修复/发版必须 bump（pubspec.yaml + android build.gradle versionCode） |
| 刮削 | Dart http 实现（原生无 CORS），代理配置支持，400ms 限速 |

### 移植不丢的需求清单（对照旧版 plan 2.1 节 + 全部修复行为）

1. 本地文件夹导入：按文件夹聚合、递归扫描、深层目录 RJ 号提取、封面自动识别
2. 封面：12 种离线 SVG 兜底封面 + 内嵌封面 + 文件夹封面图（统一 ≤300px/120KB JPEG）
3. 元数据解析：标题/社团/声优/专辑艺术家/时长/内嵌图；GBK/Shift-JIS 乱码 repairText 多字符集打分还原；乱码回退文件名
4. 网格浏览、搜索（标题/社团/声优）、排序（最近添加/标题/时长）
5. 筛选：未听完（played < totalDuration）/已收藏；视图：全部/最近添加/正在播放/收藏夹 + 4 分类（ASMR/剧情向/治愈系/环境音）
6. 详情抽屉：封面、标签、RJ 号、曲目列表、进度、收藏、从头播放
7. 播放：播放/暂停/上一首/下一首/进度拖动/音量；4 种播放模式（列表循环/单曲循环/随机/专辑循环）；播放进度定期落盘
8. 主题（浅/深）+ 6 强调色；侧栏折叠；⌘K/Ctrl+K 聚焦搜索
9. 多选模式：全选/刮削标签/删除所选/删除所选及源文件
10. 右键菜单（桌面）/长按（移动）：刮削 DLsite 标签/打开所在文件夹/删除/删除及源文件
11. DLsite 刮削：RJ 号提取、代理支持、卡片（前 3 个 +N）/详情（全部）展示、手动/批量触发、进度条、已刮跳过 + force
12. 清理失效记录、打开数据目录、导入/刮削进度条、确认对话框、Toast、版本号显示

### 明确不做

- 跨端数据同步、云端服务、账号体系
- iOS / Web 平台

## 2. 项目结构

```
kikoeru/                          # flutter create --org top.voicehub --platforms macos,android,windows
├── pubspec.yaml                  # 版本单一真源
├── lib/
│   ├── main.dart
│   ├── models/                   # Album / Track / 设置（JSON 序列化）
│   ├── data/
│   │   ├── library_store.dart    # library.json 原子写 + 增量保存
│   │   ├── settings_store.dart   # shared_preferences：主题/强调色/音量/播放模式/侧栏/代理
│   │   ├── scanner.dart          # 桌面端目录扫描（分组/自然排序/RJ/封面识别）
│   │   ├── metadata.dart         # audio_metadata_reader 封装 + repairText
│   │   ├── cover.dart            # 封面提取与压缩（≤300px/120KB）
│   │   └── dlsite_scraper.dart   # DLsite 刮削
│   ├── playback/
│   │   ├── playback_controller.dart  # 队列 + 4 播放模式 + seek/音量 + 进度落盘
│   │   └── audio_handler.dart        # audio_service 集成
│   ├── ui/
│   │   ├── screens/  widgets/  covers/  theme.dart
│   ├── platform/                 # Android MethodChannel 封装
│   └── utils/                    # rj / natural_compare / repair_text / time
├── android/  macos/  windows/
└── test/                         # 单测：RJ/自然排序/repairText/模型往返/播放模式队列
```

## 3. 里程碑

### M0 脚手架（1.0.0）
- [x] 决策与规划（本文档）
- [ ] 安装 Flutter SDK（brew install --cask flutter）
- [ ] `flutter create` 三平台工程
- [ ] 依赖引入（riverpod、just_audio、audio_service、shared_preferences、path_provider、file_selector、http、image、audio_metadata_reader、fast_gbk、shift_jis）
- [ ] AGENTS.md / README.md 更新
- [ ] `flutter run -d macos` 冒烟

### M1 数据层
- models（Album/Track/JSON 往返）
- library_store（原子写 + 增量保存）
- settings_store（主题/强调色/音量/播放模式/侧栏/代理）
- utils：RJ 提取、自然排序、repairText（Dart 移植）、时间格式化
- 单测

### M2 桌面导入
- file_selector 目录选择
- 隔离线程扫描（分组 → 逐专辑元数据 → 封面压缩）
- 导入进度事件
- 合并入库 + 保存
- 用 scripts/create-test-library.js 数据验证（含 Shift-JIS 标签）

### M3 桌面播放
- just_audio 接入（play/pause/seek/volume）
- 队列管理 + 4 种播放模式
- 播放条 UI（封面/标题/进度/音量/模式）
- 进度持久化（5s 心跳落盘 + 暂停/停止落盘）

### M4 桌面 UI 完整
- 三栏布局（侧栏 240 + 主区 + 详情抽屉 390 + 底部播放条）
- 网格、搜索、筛选、排序、视图切换
- 浅/深主题 + 6 强调色、侧栏折叠、⌘K
- 多选模式、右键菜单、Toast、确认框、导入/刮削进度条
- 正在播放视图（当前队列）

### M5 数据操作与刮削
- 删除（含源文件）、cleanMissing、reveal in Finder、打开数据目录
- DLsite 刮削 + 代理 + 标签展示

### M6 Android
- MethodChannel 插件移植（SAF 导入/删除/cleanMissing/reveal/openDataDir 分享）
- audio_service 后台播放 + 通知 + 锁屏
- 移动布局（≤1000px 底部导航/抽屉侧栏/全屏详情/长按菜单/系统返回逐层关闭）
- 模拟器 kikoeru_test（zh-CN）验证

### M7 Windows
- 构建配置、explorer reveal、just_audio_media_kit
- 本机（macOS）无法构建验证，保证代码跨平台正确

### M8 打包发布
- 图标、macOS dmg、Windows 安装包、Android release APK、README、版本收尾

## 4. 风险与不确定点

1. Flutter SDK 本机状态未知（M0 检查；缺失则 brew install --cask flutter）
2. audio_metadata_reader 对 Shift-JIS/GBK 标签解码行为需样例验证；不行则 Dart 字节级 repairText（fast_gbk + shift_jis 包），再不行 macOS 走 Swift AVFoundation 平台通道
3. Windows 无法本机构建验证（just_audio_media_kit 接入；后续 CI/真机）
4. 刮削代理在 http 包的接线需验证（dart:io HttpClient 支持代理）
5. Android SAF 目录选择必须走自写插件（file_selector 在 Android 不提供目录选择）

## 5. 版本记录

| 版本 | 日期 | 内容 |
|---|---|---|
| 1.0.0 | 2026-08-14 | M0 脚手架（规划中） |
