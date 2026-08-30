import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/settings_store.dart';
import '../../data/update_checker.dart';
import '../../playback/playback_controller.dart';
import '../../platform/platform_service.dart';
import 'toast.dart';

/// 偏好设置弹窗（对应旧版 settings-overlay）
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({
    super.key,
    this.onImportRequested,
    this.onRescanRequested,
    this.onReorganizeRequested,
    this.onCleanMissingRequested,
    this.onDownloadUpdateRequested,
  });

  /// 数据区「导入音声」入口
  final VoidCallback? onImportRequested;
  final VoidCallback? onRescanRequested;
  final VoidCallback? onReorganizeRequested;
  final VoidCallback? onCleanMissingRequested;
  final ValueChanged<GithubRelease>? onDownloadUpdateRequested;

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  double? _gainDrag; // 增益滑动条拖动中的临时值（松手才提交）

  // ---- 软件更新状态 ----
  String? _appVersion; // PackageInfo 异步加载
  bool _updateChecking = false;
  GithubRelease? _latestRelease; // 检查到的新版本(null=未检查/已是最新)

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  /// 检查 GitHub 最新 Release
  Future<void> _checkUpdate() async {
    if (_updateChecking) return;
    setState(() => _updateChecking = true);
    try {
      final current = _appVersion ?? (await PackageInfo.fromPlatform()).version;
      final release = await UpdateChecker.fetchLatestRelease();
      if (!mounted) return;
      if (UpdateChecker.isNewer(current, release.tagName)) {
        setState(() => _latestRelease = release);
      } else {
        setState(() => _latestRelease = null);
        _toast('已是最新版本($current)');
      }
    } catch (e) {
      if (mounted) _toast('检查更新失败:$e');
    } finally {
      if (mounted) setState(() => _updateChecking = false);
    }
  }

  void _toast(String message) => showHikoToast(context, message);

  /// 归一到一位小数并夹在 1.0~4.0，避免 divisions 步进的浮点尾差
  double _snapGain(double v) =>
      ((v * 10).round() / 10).clamp(1.0, 4.0).toDouble();

  Future<void> _cleanMissing() async {
    widget.onCleanMissingRequested?.call();
  }

  Future<void> _reorganizeLibrary() async {
    widget.onReorganizeRequested?.call();
  }

  void _startRescan() {
    widget.onRescanRequested?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---- 外观 ----
              _SectionTitle('外观'),
              _SettingRow(
                label: '主题',
                trailing: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (key, label) in [
                        ('light', '浅色'),
                        ('dark', '深色'),
                      ])
                        InkWell(
                          onTap: () =>
                              ref.read(settingsProvider.notifier).setTheme(key),
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: settings.theme == key
                                  ? theme.colorScheme.surface
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _SettingRow(
                label: '强调色',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final accent in AppSettings.accents)
                      InkWell(
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setAccent(accent),
                        mouseCursor: SystemMouseCursors.click,
                        child: Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: Color(
                              int.parse('FF${accent.substring(1)}', radix: 16),
                            ),
                            shape: BoxShape.circle,
                            border: settings.accent == accent
                                ? Border.all(
                                    color: theme.colorScheme.onSurface,
                                    width: 2,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ---- 音频与增益 ----
              _SectionTitle('音频与增益'),
              _SettingRow(
                label: '默认增益放大',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 180,
                      child: Slider(
                        min: 1.0,
                        max: 4.0,
                        divisions: 30,
                        value: (_gainDrag ?? settings.audioGain).clamp(
                          1.0,
                          4.0,
                        ),
                        label:
                            'x${(_gainDrag ?? settings.audioGain).toStringAsFixed(1)}',
                        mouseCursor: SystemMouseCursors.click,
                        onChanged: (v) =>
                            setState(() => _gainDrag = _snapGain(v)),
                        onChangeEnd: (v) {
                          final g = _snapGain(v);
                          setState(() => _gainDrag = null);
                          ref.read(settingsProvider.notifier).setAudioGain(g);
                          ref.read(playbackProvider.notifier).setAudioGain(g);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        'x${(_gainDrag ?? settings.audioGain).toStringAsFixed(1)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: (_gainDrag ?? settings.audioGain) > 1.0
                              ? theme.colorScheme.primary
                              : theme.hintColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '增益在音频滤镜链内以浮点精度放大，并经 -1dB 软限幅器兜底，高增益下不会削波破音。亦可在播放底栏音量图标处快捷调节。',
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.5,
                    color: theme.hintColor,
                  ),
                ),
              ),
              _SettingRow(
                label: '快进/快退秒数',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 键盘 ←→ 快退/快进的步长，白名单 3/5/10/30 秒
                    for (final step in const [3.0, 5.0, 10.0, 30.0])
                      InkWell(
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setSeekStep(step),
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: settings.seekStepSeconds == step
                                ? theme.colorScheme.surface
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${step.toStringAsFixed(0)}秒',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: settings.seekStepSeconds == step
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: settings.seekStepSeconds == step
                                  ? theme.colorScheme.onSurface
                                  : theme.hintColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ---- 主界面 ----
              _SectionTitle('主界面'),
              _SettingRow(
                label: '显示刮削标签',
                trailing: Switch(
                  value: settings.showScrapedTags,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setShowScrapedTags(v),
                ),
              ),
              _SettingRow(
                label: '每行专辑数',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 0=自动（按窗口宽度），其余为固定每行数量
                    for (final columns in const [
                      0.0, 4.0, 5.0, 6.0, 7.0, 8.0, 10.0, 12.0,
                    ])
                      InkWell(
                        onTap: () => ref
                            .read(settingsProvider.notifier)
                            .setGridColumns(columns),
                        mouseCursor: SystemMouseCursors.click,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: settings.gridColumns == columns
                                ? theme.colorScheme.surface
                                : null,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            columns == 0 ? '自动' : columns.toStringAsFixed(0),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: settings.gridColumns == columns
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: settings.gridColumns == columns
                                  ? theme.colorScheme.onSurface
                                  : theme.hintColor,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // ---- 数据 ----
              _SectionTitle('数据'),
              _SettingRow(
                label: '导入音声',
                trailing: _ActionButton(
                  label: '导入文件夹',
                  onTap: () => widget.onImportRequested?.call(),
                ),
              ),
              // ---- 音乐目录（常驻自动扫描）----
              _SectionTitle('音乐目录'),
              if (settings.musicFolders.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    '尚未设置音乐目录。导入音声文件夹时会自动记住；之后每次启动自动扫描新增内容。',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.6,
                      color: theme.hintColor,
                    ),
                  ),
                ),
              for (final folder in settings.musicFolders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 15,
                        color: theme.hintColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _displayFolder(folder),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14),
                        tooltip: '移除目录',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => ref
                            .read(settingsProvider.notifier)
                            .removeMusicFolder(folder),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  _ActionButton(label: '立即重新扫描', onTap: _startRescan),
                  if (settings.musicFolders.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '共 ${settings.musicFolders.length} 个目录',
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                  ],
                ],
              ),
              _SettingRow(
                label: '库文件位置',
                trailing: _ActionButton(
                  label: '打开数据目录',
                  onTap: () => ref.read(platformServiceProvider).openDataDir(),
                ),
              ),
              _SettingRow(
                label: '整理当前专辑',
                trailing: _ActionButton(
                  label: '整理专辑元数据',
                  onTap: _reorganizeLibrary,
                ),
              ),
              _SettingRow(
                label: '失效记录',
                trailing: _ActionButton(label: '清理失效记录', onTap: _cleanMissing),
              ),
              _SettingRow(
                label: '刮削代理',
                trailing: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: TextEditingController(
                      text: settings.scrapeProxy,
                    ),
                    onChanged: (v) => ref
                        .read(settingsProvider.notifier)
                        .setScrapeProxy(v.trim()),
                    decoration: InputDecoration(
                      hintText: '留空使用系统代理',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
              // ---- 关于 ----
              _SectionTitle('关于'),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Center(
                      child: Text(
                        'K',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hiko · 音声收藏室',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '版本 ${_appVersion ?? '…'} · 本地优先的音声库管理器',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.hintColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 软件更新(两端):检查 GitHub 最新 Release → 一键下载安装
              if (_latestRelease == null)
                _SettingRow(
                  label: '软件更新',
                  trailing: _ActionButton(
                    label: _updateChecking ? '检查中...' : '检查更新',
                    loading: _updateChecking,
                    onTap: _updateChecking ? null : _checkUpdate,
                  ),
                ),
              if (_latestRelease != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.35,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.system_update_alt_rounded,
                            size: 14,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '发现新版本 ${_latestRelease!.tagName}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (_latestRelease!.body.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 110),
                          child: SingleChildScrollView(
                            child: Text(
                              _latestRelease!.body.trim(),
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1.5,
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          _ActionButton(
                            label: Platform.isAndroid ? '下载并安装' : '下载更新包',
                            onTap: () {
                              final release = _latestRelease;
                              if (release == null) return;
                              Navigator.pop(context);
                              widget.onDownloadUpdateRequested?.call(release);
                            },
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () =>
                                setState(() => _latestRelease = null),
                            child: Text(
                              '暂不更新',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.hintColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '关闭',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.2,
          color: theme.hintColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          trailing,
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: BorderSide(color: theme.dividerColor),
        foregroundColor: theme.colorScheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      child: loading
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 11)),
              ],
            )
          : Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

/// 音乐目录展示名：SAF tree URI 取最后一段，路径取文件名
String _displayFolder(String folder) {
  if (folder.startsWith('content://')) {
    final idx = folder.lastIndexOf('%2F');
    if (idx >= 0) {
      return Uri.decodeComponent(folder.substring(idx + 3));
    }
    return folder;
  }
  final parts = folder.split(RegExp(r'[/\\]'));
  return parts.where((p) => p.isNotEmpty).lastOrNull ?? folder;
}
