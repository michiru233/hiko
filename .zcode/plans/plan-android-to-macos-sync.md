# Android → macOS 功能同步计划

**制定时间**: 2026-09-09  
**目标**: 将 Android 端 1.53.0~1.61.0 的新功能同步到 macOS 端  
**策略**: 按重要性分批，功能对等优先，2-3 个功能一组发布

---

## 📋 功能分类总览

### ✅ 可直接同步（跨平台，无平台差异）

**A. 播放体验增强**
1. 睡眠定时器（1.29.0）- 15/30/60分钟 + 曲终停止 + 淡出
2. 播放倍速（1.29.0）- 0.5x~2.0x，步进 0.1
3. 进度记忆 + 继续收听横幅（1.41.0）- 专辑断点续播

**B. 内容管理增强**
4. 星级评分（1.48.0）- 0~5星，支持排序
5. 自定义分类系统（1.18.0）- 自由新建/编辑/调色

**C. UI 体验优化**
6. 隐私模糊（1.52.0）- ⌘⇧H 一键模糊封面 + macOS 特殊处理
7. 瀑布流 + 动态卡片（1.51.0）- Masonry 自适应布局
8. 字号全局缩放（1.56.0）- 四档位 0.85/1.0/1.15/1.30

### 🔧 需适配（有平台差异）

9. **歌词自动检测** - Android 导入时自动读取 `.lrc/.vtt/.srt`，macOS 需在扫描时实现
10. **音频增益扩展** - Android 已支持 1.0~4.0x，macOS 当前 1.0~1.3x（**单独立项**，不在本次同步范围）

### 🍎 macOS 已有优势（保持）

- 窗口记忆（1.48.0）
- 菜单栏中文化（1.48.0）
- 键盘快捷键（1.41.0）
- macOS Now Playing（1.26.0）
- 桌面悬浮歌词 HUD（1.20.0）

---

## 🎯 分批同步计划

### 第一批：播放体验核心（v1.62.0）

**功能清单**
1. **睡眠定时器** - 15/30/60分钟倒计时 + 曲终停止 + 10秒线性淡出
2. **播放倍速** - 0.5x~2.0x，步进 0.1，持久化
3. **进度记忆 + 继续收听横幅** - Album 断点字段 + 主界面续播入口

**实现位置**
- `lib/playback/sleep_timer.dart` - 已存在（Android 已用）
- `lib/playback/playback_controller.dart` - 补充 macOS 倍速逻辑
- `lib/models/album.dart` - 添加 `resumeTrackIndex/resumePosition/lastPlayedAt` 字段
- `lib/playback/playback_rules.dart` - 进度保存与恢复逻辑
- `lib/ui/screens/home_screen.dart` - 添加继续收听横幅卡

**测试重点**
- 睡眠定时器淡出效果（AVPlayer 音量控制）
- 倍速在 AVPlayer 下的表现（`rate` 属性）
- 进度记忆的原子性（中断/崩溃场景）
- 多专辑切换时断点正确性

**预计工作量**: 1-2 天

---

### 第二批：内容管理增强（v1.63.0）

**功能清单**
4. **星级评分** - 0~5星，详情抽屉/右键菜单/批量操作，排序「评分优先」
5. **自定义分类系统** - 侧栏管理，专辑右键/批量归类
9. **歌词自动检测**（适配项）- macOS 扫描时自动查找同名 `.lrc/.vtt/.srt` 文件

**实现位置**
- `lib/models/album.dart` - 添加 `rating` 字段
- `lib/ui/widgets/rating_dialog.dart` - 已存在（Android 已用）
- `lib/models/category.dart` + `lib/data/categories_provider.dart` - 已存在
- `lib/data/scanner.dart` - 添加 macOS 歌词自动检测逻辑（文件系统同名查找）

**macOS 歌词检测实现**
```dart
// 伪代码
Future<String?> _findLyricsFile(String audioPath) async {
  final dir = Directory(path.dirname(audioPath));
  final baseName = path.basenameWithoutExtension(audioPath);
  
  for (final ext in ['.lrc', '.vtt', '.srt']) {
    final lyricsPath = path.join(dir.path, '$baseName$ext');
    final file = File(lyricsPath);
    
    if (await file.exists()) {
      final stat = await file.stat();
      if (stat.size <= 64 * 1024) { // ≤64KB
        return await file.readAsString(); // 尝试 UTF-8/Shift-JIS/GBK
      }
    }
  }
  return null;
}
```

**测试重点**
- 评分排序正确性
- 分类颜色持久化
- 歌词文件多编码支持（UTF-8/Shift-JIS/GBK）
- 歌词文件大小限制（>64KB 跳过）

**预计工作量**: 2-3 天

---

### 第三批：UI 体验优化（v1.64.0）

**功能清单**
6. **隐私模糊** - ⌘⇧H 模糊 + macOS Now Playing 中性化 + HUD 自动隐藏
7. **瀑布流 + 动态卡片** - Masonry 布局，卡宽自适应
8. **字号全局缩放** - 四档位 0.85/1.0/1.15/1.30

**实现位置**
- `lib/data/settings_store.dart` - 添加 `privacyBlurEnabled` 内存态 ValueNotifier
- `lib/ui/covers/cover_art.dart` - 应用高斯模糊（σ=20）
- `lib/playback/macos_now_playing.dart` - 模糊时使用空白封面
- `lib/ui/lyrics/desktop_lyrics_hud.dart` - 监听模糊状态，自动隐藏
- `flutter_staggered_grid_view` 包 + `lib/utils/masonry_layout.dart`
- 主题系统 - 全局字号缩放因子

**macOS 隐私模糊增强**
- UI 封面：高斯模糊 σ=20（与 Android 一致）
- Now Playing：切换到透明/空白封面
- 桌面 HUD：检测模糊状态，自动隐藏窗口
- 快捷键：⌘⇧H 切换（全局监听）

**测试重点**
- Now Playing 封面切换无闪烁
- HUD 隐藏/恢复流畅性
- 瀑布流窗口 resize 响应
- 字号缩放后布局不错乱

**预计工作量**: 2-3 天

---

## 🚫 暂不同步（单独立项）

### 音频增益扩展到 4.0x

**当前状态**
- macOS: 1.0~1.3x（libavfilter 限制，1.46.0）
- Android: 1.0~4.0x（AndroidLoudnessEnhancer，真生效）

**技术挑战**
- mpv 滤镜链复杂度（1.45.0/1.46.0 已有音频自愈诊断）
- 需要 `volume` + `alimiter` 滤镜（当前 libavfilter 缺失）
- 可能需要重新编译 mpv 或切换音频后端

**立项条件**
- 用户明确需求（当前 1.3x 是否够用？）
- 技术方案验证（mpv 滤镜链 vs AVAudioEngine）
- 独立测试周期（避免影响其他功能稳定性）

**建议时机**: 三批同步完成后，作为 v1.65.0+ 独立优化

---

## 📦 版本规划

| 批次 | 版本号 | 功能数 | 预计完成 | 发布说明重点 |
|------|--------|--------|----------|--------------|
| 第一批 | v1.62.0 | 3 | Day 1-2 | 播放体验追平 Android：定时器/倍速/断点续播 |
| 第二批 | v1.63.0 | 3 | Day 3-5 | 内容管理增强：评分/分类/歌词自动检测 |
| 第三批 | v1.64.0 | 3 | Day 6-8 | UI 现代化：隐私模糊/瀑布流/字号缩放 |
| 立项研究 | v1.65.0+ | 1 | 待定 | 音频增益扩展（需技术验证） |

---

## ✅ 验收标准

### 功能层面
- [ ] 所有跨平台功能在 macOS 上行为与 Android 一致
- [ ] macOS 特殊处理（Now Playing/HUD）符合平台惯例
- [ ] 歌词自动检测支持 UTF-8/Shift-JIS/GBK 三种编码

### 质量层面
- [ ] 每批功能完成后运行 `flutter test`，无回归
- [ ] 每批功能在 macOS 上构建 Release 包（`flutter build macos --release`）
- [ ] 手动测试覆盖：正常流程 + 边界情况（文件缺失/格式错误/网络中断）

### 交付层面
- [ ] 每批完成后 bump `hiko/pubspec.yaml` 版本号
- [ ] 执行 `git add/commit/push`，提交信息格式：`feat(hiko): vX.Y.Z <批次简述>`
- [ ] 打包 macOS Release：`hiko-vX.Y.Z-macos.zip`
- [ ] 通过 `gh release create` 上传到 GitHub Releases
- [ ] 更新 `.zcode/plans/plan-hiko-flutter-rewrite.md`，追加本次同步记录

---

## 🔄 回滚方案

如果某批功能上线后发现严重问题：

1. **代码回滚**: `git revert <commit-hash>`，bump 版本号到 vX.Y.Z+1
2. **Release 标记**: 在问题版本的 Release 页面添加 "⚠️ 已知问题" 说明
3. **用户通知**: 如果已有用户下载，通过 GitHub Issue 通知回滚版本
4. **问题修复**: 单独分支修复，合并后重新发布 vX.Y.Z+2

---

## 📝 实施检查清单

### 开始第一批前
- [ ] 确认当前 macOS 版本号（`hiko/pubspec.yaml`）
- [ ] 确认当前代码在 `main` 分支且无未提交改动
- [ ] 运行 `flutter test` 确保基线通过
- [ ] 构建当前 macOS Release 作为回归对比基准

### 每批完成后
- [ ] 代码自测（功能正常 + 无崩溃）
- [ ] 运行 `flutter test`（无新增失败）
- [ ] 构建 Release 包并手动验证
- [ ] Bump 版本号
- [ ] Git commit + push
- [ ] 创建 GitHub Release + 上传 zip
- [ ] 更新计划文档

### 全部完成后
- [ ] 对比 Android/macOS 功能矩阵，确认对等
- [ ] 撰写用户面向的 Release Notes（中文）
- [ ] 评估"音频增益扩展"立项可行性
- [ ] 归档本计划到 `.zcode/plans/` 目录

---

## 🎯 成功指标

1. **功能覆盖率**: macOS 端功能与 Android 端（1.53.0~1.61.0 范围）对等度 ≥90%
2. **质量稳定性**: 三批发布后无 P0/P1 级别回归
3. **用户感知**: Release Notes 中能清晰传达"macOS 追平 Android"的价值
4. **可维护性**: 跨平台代码复用率高，平台差异集中在 `lib/platform/` 抽象层

---

**制定人**: ZCode AI  
**审批人**: 待用户确认  
**状态**: 🟢 第一批已存在（跨平台实现），直接进入第二批

---

## ⚠️ 重要发现：第一批功能已经是跨平台实现！

经过代码审查发现，**第一批的三个功能从一开始就是跨平台设计，macOS 已经完全可用**：

1. ✅ **睡眠定时器**（1.29.0）- `lib/playback/sleep_timer.dart` 纯逻辑 + `PlaybackController` 集成，播放条有 UI 入口
2. ✅ **播放倍速**（1.29.0）- `settings.playbackRate` 持久化 + `_player.setSpeed()`，播放条有倍速滑条
3. ✅ **进度记忆 + 继续收听横幅**（1.41.0）- `Album.resumeTrackIndex/resumePosition/lastPlayedAt` 字段 + `home_screen.dart:841` 横幅实现

**验证结果**：
- macOS Release 构建成功（73.8MB）
- 代码审查确认无平台差异逻辑
- 播放条、主界面均有对应 UI 入口

**结论**：第一批无需同步，**直接进入第二批功能开发**（星级评分 + 自定义分类 + 歌词自动检测）

**状态**: 🟡 执行第二批中
