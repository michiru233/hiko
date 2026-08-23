# 修复 macOS 桌面端特定专辑/音频播放卡在 0:00 无法播放的问题

## 1. 根因分析（Root Cause）

在 macOS 桌面端使用 `libmpv`（`just_audio_media_kit`）提供 64-bit 浮点增益与音频渲染时，存在底层 `MediaKitPlayer.load()` 的**时序竞态死锁（Race Condition Deadlock）**：
1. `just_audio_media_kit` 的 `load()` 内部创建了 `_loadCompleter`，并只在 `_player.stream.buffering` 收到 `!isBuffering && _mediaOpened` 时将其 complete。
2. 在快速的本地 SSD 磁盘上，`_player.open()` 速度极快，`libmpv` 往往在 `open()` 尚未 await 返回（即 `_mediaOpened` 仍为 `false`）时就已经完成了缓冲并触发了 `buffering: false`。
3. 随后 `_mediaOpened = true` 执行，但由于本地文件已缓冲完毕，`libmpv` 不会再发射新的 buffering 变化事件。
4. `await _loadCompleter?.future` 从而陷入**永久挂起（Hang）**，导致 `_player.setUrl()` 永远不返回，后续的 `syncVolume()` 和 `_player.play()` 永远无法被执行。
5. 伴随 `PlaybackController` 在切歌初始将 `duration` 设为 0 以及乐观设为 `playing: true`，最终导致 UI 底栏显示曲目已在播放但时长与进度永久卡在 `0:00 / 0:00`、无声音输出。

---

## 2. 解决方案

### A. 实现增强版 `HikoJustAudioMediaKit` / `HikoMediaKitPlayer` (`lib/playback/hiko_media_kit_player.dart`)
1. 继承 `JustAudioPlatform` 和 `AudioPlayerPlatform`，接管 `just_audio` 的桌面后端（macOS & Windows）。
2. **彻底解决死锁**：
   - 在 `open()` 完成且 `_mediaOpened = true` 后，主动检测 `_player.state`：若已非缓冲态或已有时长，立即触发 `_loadCompleter.complete()` 并广播就绪事件。
   - 在 `_player.stream.duration` 收到有效时长时，若 `_processingState == loading` 也立即推进完成。
   - 为 `_loadCompleter` 设置 6 秒超时防卡死兜底（超时自动以当前已有状态返回，永不挂起）。
3. 支持 64-bit 浮点软增益（1.0x~3.0x）、音量与播放速率调节。

### B. 优化 `PlaybackController` 播放与状态调度 (`lib/playback/playback_controller.dart`)
1. **立即初始化曲目时长**：在 `playAlbum` 中创建 `PlaybackState` 时，直接带入当前曲目元数据中已解析的时长 `duration: track.duration > 0 ? track.duration : 0.0`，杜绝显示 `0:00` 闪烁。
2. **保护性超时机制**：对 `_player.setUrl()` 增加 10 秒超时防护（`timeout(...)`），并在抛错时重置状态并安全回退。
3. **播放状态精准切换**：在 `_player.play()` 开始前先保持加载态，执行 `_player.play()` 后再确认 `playing: true`。

### C. 优化 `HikoAudioHandler` 系统状态同步 (`lib/playback/audio_handler.dart`)
1. 更加精确地根据 `_controller.player.playerState` 与实际播放进度同步 `playbackState`，避免在切歌/加载时向 macOS 系统控制中心发送错误的前置就绪状态。

---

## 3. 实施步骤

1. **创建 `lib/playback/hiko_media_kit_player.dart`**：完整实现防死锁与增强版桌面 mpv 播放器。
2. **更新 `lib/main.dart`**：将 `JustAudioMediaKit.ensureInitialized` 切换为 `HikoJustAudioMediaKit.ensureInitialized`。
3. **更新 `lib/playback/playback_controller.dart`**：增加初始时长填充与 `setUrl` 超时防护。
4. **更新 `lib/playback/audio_handler.dart`**：精细化处理加载中/播放中的状态映射。
5. **升级版本号**：
   - `pubspec.yaml`：`1.26.0+29` $\to$ `1.27.0+30`
   - `android/app/build.gradle.kts`：`versionCode = 30`，`versionName = "1.27.0"`
6. **运行测试**：`flutter test` 确保所有单元测试 100% 通过。
7. **更新实施规划文档**：`.zcode/plans/plan-hiko-flutter-rewrite.md`。
8. **构建 macOS Release**：`flutter build macos --release`，并压缩生成 `hiko-v1.27.0-macos.zip`。
9. **Git 提交、推送与发布 GitHub Release**：创建并上传 `v1.27.0`。