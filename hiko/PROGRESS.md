# PROGRESS — 1.28.0 滑动条无级增益 + 限幅防破音

## 开工回执（2026-08-23）
- 目标：增益从 mpv volume 属性（clamp 130 硬削波）整体搬进 af 链 lavfi volume+alimiter，UI 换 1.0~4.0 无级滑动条。
- 顺序：任务0 基线核对 ✅ → 任务1 引擎层 gain_chain → 任务2 滑动条 UI → 任务3 测试 → 任务4 发布（1.28.0+31，build/commit/push/gh release）。
- 基线：flutter test 87 passed +1 skipped 全绿；grep volume-max ~/.pub-cache/.../media_kit-1.2.6/lib 无输出。均符合。
- 最大风险：mpv 拒绝 lavfi 滤镜串（本机无 mpv CLI，只能 app 内读回验证）；降级路径=去掉 alimiter 只留 volume。

## 进度（全部完成）
- [x] 任务0：基线核对通过，回执已写。
- [x] 任务1：新建 `lib/playback/gain_chain.dart`（gainAfChain 纯函数）；`HikoJustAudioMediaKit.setGlobalGain`（幂等+读回日志+失败容忍）+ init 时对后续实例补挂；`pitch:false`；`playback_controller.syncVolume` 拆分（setVolume 只传 0~1，增益走 setGlobalGain，playAlbum/setAudioGain 调用点全覆盖）。
- [x] 任务2：settings_dialog 与 player_bar 档位组换 Slider（1.0~4.0 divisions=30，拖动仅更新显示、onChangeEnd 提交两处）；底栏弹窗 76→150；262 行文案改为如实描述。
- [x] 任务3：新建 `test/playback/gain_chain_test.dart`（3 测）；settings_store_test 仅改授权断言（上限 3.0→4.0，含 setAudioGain(5.0) 期望 4.0）；settings_store.dart 三处 clamp 3.0→4.0。
- [x] 运行时验收：`flutter run -d macos --dart-define=HIKO_GAIN_SELFTEST=1`（自检代码 dart-define 门控、默认不生效，为无人值守采集验收日志而加，PROGRESS 记录原因）：
  - 2.0x：`[gain] af=lavfi=graph=%89%volume=volume=2.0,alimiter=level=false:limit=-1dB:attack=5:release=50:asc=1:asc_level=0.5 (mpv volume=100.000000)` ← mpv 完整接受，未触发降级
  - 恢复 1.0x：`[gain] af= (mpv volume=100.000000)` ← af 清空
  - 两次切换 mpv volume 读数一致 ← 常规音量与增益通道隔离
- [x] 反向验证：临时把 `gainAfChain(0.5)==''` 断言改为 `'BREAK_FOR_RED_CHECK'` → 跑红（Expected 'BREAK_FOR_RED_CHECK' / Actual '' / Some tests failed）；还原后全绿。
- [x] 任务4：pubspec 1.28.0+31；flutter analyze 0 error（存量 info/warning 与改动前一致）；flutter test 90 passed +1 skipped 全绿；`flutter build macos --release` ✓ Built Hiko.app (73.3MB)；打包仓库根 `hiko-v1.28.0-macos.zip`（31MB，CFBundleShortVersionString=1.28.0）；git commit + push origin main；gh release v1.28.0。

## 备注
- 本机无 mpv CLI，滤镜串验证完全依赖 app 内 getProperty 读回（读回为 mpv 规范化转义形式 `lavfi=graph=%89%...`，属正常）。
- 实现细节偏离：无。
