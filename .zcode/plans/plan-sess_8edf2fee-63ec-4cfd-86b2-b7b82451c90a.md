## 安卓导入与元数据修复计划

### 1. 实时导入进度

当前 `scanAlbums()` 会先递归发现文件、并行解析全部音频、完成分组，`HikoPlugin.scanTree()` 等整个扫描结束后才发送 `onAlbum/onProgress`，所以 UI 在整个耗时阶段只能显示 `0/0`。

调整为分阶段事件，保留现有 MethodChannel 事件流：

- `scanAlbums` 增加进度回调，在文件发现完成后立即发送扫描阶段事件，携带 `processed/total/unit/phase`。
- 解析每个音频完成时持续发送 `processed/total`，保证扫描阶段不是静默等待。
- 分组后逐张构建专辑；每构建并发送一张专辑就发送专辑阶段进度，确保最终专辑进度单调到 `N/N`。
- `HikoPlugin` 不再在扫描完成后重复发送一套批量进度，避免总数先代表音频、后突然切换成专辑。
- Dart `AndroidPlatformService` 解析 `phase/unit`，UI 在扫描阶段显示“正在扫描音频文件 X/Y”，在专辑阶段显示“正在导入专辑 X/Y”；总量未知时使用不确定进度条，而不是固定显示 `0/0`。
- 处理空目录、取消、异常路径，确保进度浮条最终关闭且不会残留旧 handler。

### 2. 防止中文/日文标签被错误解成韩文或其他错误文字

问题根因是 ID3 encoding=0 的原始字节在 GB18030、Shift-JIS、EUC-JP 等字符集中可能都能合法解码，当前仅按汉字/假名数量评分，容易选到语义错误的候选；raw 候选还会无条件覆盖 `MediaMetadataRetriever` 的结果。

调整 `Id3v2Parser`：

- 为候选保留 charset、解码结果、脚本统计、非法/控制/替换字符、可逆往返结果和置信度，不再只返回字符串。
- 对声明为 UTF-8/UTF-16/UTF-16BE 的帧继续严格按规范解码；非法或带压缩/加密等未支持 frame flags 的帧跳过，让系统元数据继续兜底。
- 对 encoding=0 仅在候选有明确优势时采用：
  - 日文有假名或日文标点时优先真实日文编码；
  - 中文脚本证据明显时选择 GB18030；
  - 纯汉字且多个候选合法、分差不足时不猜测，交给 `MediaMetadataRetriever`，仍不可信则回退文件名/文件夹名；
  - 明确拒绝含 Hangul/异常脚本、控制字符、替换字符和可疑 mojibake 的候选，避免出现韩文标题。
- raw ID3 与 retriever 结果改为字段级选择：只有 raw 候选达到置信阈值才覆盖；否则保留 retriever 的可用值。标题、专辑、艺术家、专辑艺术家、曲号分别独立兜底。
- 修正 `looksGarbled`：不再把所有合法 Latin-1（如 `Café`、`Beyoncé`）当乱码；只识别问号/替换字符/C1 控制符和明确的 mojibake 特征。这样合法 ALBUM 不会无故回退文件夹名。
- 增加测试向量：纯 Shift-JIS 汉字 `日本` 的歧义字节、含假名日文、GB18030 中文、EUC-JP、Hangul 负例、合法 Latin-1、损坏/截断标签，以及 raw 候选与 retriever fallback 的优先级。

### 3. 专辑名优先使用 ALBUM 标签

- 规范化 ALBUM 文本（trim、Unicode NFC、去除 NUL/不可见尾部），只让高置信、可用的 ALBUM 进入分组 key。
- 同一目录内若存在一致且高置信的 ALBUM，吸收没有 ALBUM 的曲目，避免同一专辑被拆成“标签组 + 文件夹组”。只有同目录存在多个不同 ALBUM 时才按标签拆分。
- 构建专辑标题时优先组内最常见的有效 ALBUM；只有 ALBUM 缺失或明确损坏时才回退目录名。
- 对跨文件夹标签组保留 album artist 维度，同时用规范化值组成 key，避免空格/Unicode 形式差异造成重复专辑。
- 标签组的文件夹封面继续作为内嵌封面缺失时的 fallback，且跨目录时逐目录尝试封面。
- Android 旧的目录级 `scanAlbum` 路径同步使用相同的字段可用性判断，避免未来调用路径行为不一致。

### 4. 版本、记录与验证

- 将 `hiko/pubspec.yaml` 更新为 `1.13.0+14`，由 Flutter 同步 Android `versionName/versionCode`。
- 在 `.zcode/plans/plan-hiko-flutter-rewrite.md` 追加本次修复记录。
- 运行完整 `flutter test`、Android JVM 单测和 debug APK 构建。
- 安装 APK 到现有模拟器，核对版本与启动；若无可复现实音频目录，则明确报告未完成真实 SAF 标签导入验证。

本次只改 `hiko/` 当前 Flutter 主线，不修改根目录旧 Electron/Capacitor 代码，也不回退上一轮 ID3 修复。