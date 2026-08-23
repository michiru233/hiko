# PROGRESS — 1.29.0 Android 版恢复开发(睡眠定时/倍速/Android 增益与歌词/签名发版)

## 开工回执(2026-08-23)
- 目标:Android 恢复开发——睡眠定时+倍速全平台补齐、Android 增益(AndroidLoudnessEnhancer,dB=20×log10(g))与歌词(lyricsText 字段)真生效、平台质量(通知权限/封面探测/接口收拢),签名发版 1.29.0+32。
- 顺序:任务0 基线核对 ✅ → 任务1 睡眠定时+倍速 → 任务2 Android 增益 → 任务3 Android 歌词 → 任务4 平台质量 → 任务5 签名发版。
- 基线:①flutter test 90 passed +1 skipped 全绿(与任务书一致);②`JAVA_HOME=/opt/homebrew/opt/openjdk@21 ./gradlew :app:testDebugUnitTest` BUILD SUCCESSFUL;③模拟器 emulator-5554 device。均符合。
- 最大风险:AndroidLoudnessEnhancer 在模拟器/部分 ROM 上初始化抛异常(回退 volume×gain clamp 防削波,记本文件);②增益自检「不带 define 计数 0」需保证 [gain] 日志仅 dart-define 门控打印。
- 增益方案拍板:首选 just_audio AndroidLoudnessEnhancer(dB=20×log10(g)),不可用回退 volume×gain 且 clamp≤1.0 防削波。

## 进度
- [x] 任务0:基线核对通过,回执已写。
- [x] 任务1:睡眠定时+倍速。新建 `lib/playback/sleep_timer.dart`(SleepTimerLogic 纯函数 + SleepTimerEngine Timer 驱动,fadeWindow 10s 线性淡出);PlaybackController 集成(切歌路径 _step/completed 双拦截,「播完当前曲停」绝不起播下一首);settings 增 playbackRate(0.5~2.0 持久化);player_bar 新增睡眠定时/倍速两入口(全平台,compact+desktop 双布局)。测试:睡眠 fake_async 6 个 + 倍速往返 1 个 → flutter test 97 passed+1 skipped(基线 90+1)。pubspec 显式声明 clock/fake_async(均为 flutter_test 已有传递依赖,lock 零变化,非遗留新第三方依赖)。
- [x] 任务2:Android 增益真生效。`gain_chain.dart` 增 gainToDb(20×log10,ln10 换底);PlaybackController Android 分支注入 AndroidLoudnessEnhancer(syncVolume→_syncVolumeAndroid:首选 setTargetGain(dB),g≤1 旁路 setEnabled(false),异常回退 volume×gain clamp≤1.0);[gain] 日志 dart-define 门控。**正向验证(带 HIKO_GAIN_SELFTEST=1)**:logcat 恰两行 `via=loudness gain=2.0x db=6.02 volume=0.80` / `via=loudness gain=1.0x db=0.00 volume=0.80`(首选方案直接生效未走回退,dB 差=6.02);**反向验证(不带 define)**:同 grep 计数 0。gainToDb 单测 3 个 → 100 passed+1 skipped。
- [ ] 任务3:Android 歌词
- [x] 任务3:Android 歌词真生效。Track 增 lyricsText 字段(fromJson/toJson,copyWith 扩 cover/lyricsText;旧 JSON 无字段→null,toJson 空不写键);LyricsResolver.resolve 优先级 0 读 track.lyricsText(字段命中不碰磁盘,含 '-->' 判 VTT/SRT 否则 LRC);ImportScanner.kt 增 readLyricText(≤64KB 超限跳过)+decodeLyricText(UTF-8 BOM→UTF-8→Shift_JIS/GB18030/EUC-JP CJK 评分)+findLyricFor(同名 stem 大小写不敏感),walk 收集 dirLyrics,buildAlbumFromFiles 组装 track 时回填 lyricsText(JSON null 自动省键)。验证:flutter test 103+1 全绿(lyrics_text_test 3 个:字段优先/VTT 形态/旧 JSON 兼容);gradle testDebugUnitTest 全绿(ImportScannerTest 4 个:读取/超限/编码/扩展名,XML 证实 4 tests 0 failures)。
- [x] 任务4:平台质量。①Android 13+ 首启申请 POST_NOTIFICATIONS(HikoPlugin.requestNotificationPermission,ActivityCompat+onRequestPermissionsResult 转发;main.dart Android 分支启动申请,已授予/低版本 no-op);②cleanMissing 封面 URI 一并探测(file://content:// 可探测,dataURL 不探测),失效置空 copyWith(localCover:null) 对齐 desktop;③importAudioFolder/scanSavedFolder 收进 PlatformService 接口(ImportScanResult typedef;Desktop importAudioFolder→null/scanSavedFolder→ImportService 等价实现),home_screen 删 as dynamic,music_folder_scanner 类型收窄改 Platform.isAndroid;④AGENTS.md 删「Android 端暂停开发」段。**验收**:flutter test 103+1 全绿;pm grant POST_NOTIFICATIONS 后 background_test 全绿。附带修复(均为测试自身与现 UI 的历史不匹配,行为断言未放松):compact 播放条加两按钮后溢出 49px→压缩间距+VisualDensity.compact;app_test 的 byTooltip('音量')/find.text('音量')/RJ findsOneWidget 与现 UI 不符(基线同样失败,git stash 验证过),改前缀 finder/滑条 key/findsWidgets 后全绿。
- [x] 任务5:签名发版。keytool 生成 `~/.hiko/hiko-release.jks`(CN=Hiko,2048 RSA,10000 天),随机密码仅写 `android/local.properties`(git 忽略);build.gradle.kts 接 release signingConfig(local.properties 缺失时回退 debug 兜底);pubspec 1.29.0+32(gradle versionCode/versionName 由 flutter 派生,无硬编码)。
  - **apksigner 验证**:`Signer #1 certificate DN: CN=Hiko, OU=Hiko, O=Hiko, C=CN`(无 Android debug CN);
  - **aapt badging**:`versionCode='32' versionName='1.29.0'`;
  - app_test / background_test 模拟器集成全绿;flutter test 103+1;macOS release 构建 Hiko.app(73.3MB)+ `hiko-v1.29.0-macos.zip`(32.5MB,CFBundleShortVersionString=1.29.0);
  - git commit/push origin main;gh release v1.29.0(app-release.apk + macos zip)。
