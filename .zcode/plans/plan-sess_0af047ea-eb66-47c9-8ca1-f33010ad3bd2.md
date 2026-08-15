# 修复「偏好设置 -> 立即重新扫描」卡顿与缺少进度条方案

## 问题诊断与根本原因分析

1. **界面无进度条且点击后无即时反馈**：
   - `SettingsDialog` 为无状态组件，点击「立即重新扫描」时没有维护 `isScanning` 状态，也没有向 `scanAll` 传入 `onProgress` 回调，更没有渲染任何进度条（`LinearProgressIndicator`）或当前正在处理的文件/专辑数量文本。
2. **扫描过程主线程卡顿（Jank）**：
   - `collectFiles` 递归收集成千上万个文件时是在主 UI Isolate 上异步遍历，产生大量小对象和事件循环排队。
   - 专辑构建阶段 (`_buildAlbum`) 的封面图解码、缩放与转码（`coverDataUrl` -> `image.decodeImage` / `image.copyResize` / `image.encodeJpg`）是纯 CPU 计算密集型操作，全部同步阻塞在主 UI 线程上。
3. **弹窗版本号硬编码落后**：
   - `settings_dialog.dart` 中版本号硬编码为 `1.18.0`，实际已经迭代至 `1.20.0`。

---

## 优化与实施计划

### 1. 扫描器底层性能与线程解耦优化 (`lib/data/scanner.dart` & `lib/data/cover.dart`)
- 将 `collectFiles` 递归文件遍历移至后台 Isolate（使用 `compute` 或 `Isolate.run` 同步遍历），主 UI 线程零 I/O 停顿。
- 将 `coverDataUrl` 图片解码与缩放过程放到后台 Isolate 中执行（或 `compute`），避免主线程在构建大图封面专辑时掉帧卡顿。

### 2. 偏好设置弹窗升级 (`lib/ui/widgets/settings_dialog.dart`)
- 将 `SettingsDialog` 升级为 `ConsumerStatefulWidget`。
- 新增扫描状态管理：`_isScanning`、`_scanProgress`（0.0 ~ 1.0）、`_scanStatusText`（如 `正在扫描音频: 45 / 120`、`正在组装专辑: 3 / 8`）。
- **UI 呈现**：
  - 在「立即重新扫描」按钮下方或右侧区域新增精致平滑的进度条（`LinearProgressIndicator`）与实时进度文案。
  - 扫描进行时，按钮自动呈现 Loading 旋转指示器并处于禁用（disabled）防重复点击状态。
  - 扫描完成后通过 SnackBar 明确提示新增专辑数，并优雅恢复状态。
- **关于区域版本同步**：
  - 更新关于区域版本号为最新版本 `1.20.0`（并保持与 `pubspec.yaml` 同步）。

### 3. 全局扫描器透传 (`lib/data/music_folder_scanner.dart`)
- 确保 `scanAll` 接收 `onProgress` 并在每个阶段持续向上发射细粒度的 `ImportProgress`。

---

## 验证与发布

1. 运行全部单元测试 (`flutter test`) 确保扫描、排序、模型往返等 83+ 测试全部绿灯。
2. 执行 `flutter build macos --release` 并封包发布。
3. git commit / push 并更新 Release。
