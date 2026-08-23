import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/library_provider.dart';
import '../../data/library_reorganizer.dart';
import '../../data/music_folder_scanner.dart';
import '../../data/settings_store.dart';
import '../../data/update_checker.dart';
import '../../playback/playback_controller.dart';
import '../../platform/platform_service.dart';

/// 偏好设置弹窗（对应旧版 settings-overlay）
class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key, this.onImportRequested});

  /// 数据区「导入音声」入口
  final VoidCallback? onImportRequested;

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog> {
  bool _isScanning = false;
  double? _scanProgress;
  String? _scanStatusText;
  double? _gainDrag; // 增益滑动条拖动中的临时值（松手才提交）

  // ---- 软件更新状态 ----
  String? _appVersion; // PackageInfo 异步加载
  bool _updateChecking = false;
  GithubRelease? _latestRelease; // 检查到的新版本(null=未检查/已是最新)
  bool _updateDownloading = false;
  double _downloadProgress = 0;
  int _downloadReceived = 0;
  int _downloadTotal = 0;

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

  /// 下载更新包并落地(Android 调起安装器 / 桌面定位到下载文件)
  Future<void> _downloadUpdate() async {
    final release = _latestRelease;
    if (release == null || _updateDownloading) return;
    final asset = UpdateChecker.pickAsset(release, Platform.operatingSystem);
    if (asset == null) {
      _toast('未找到适用于本平台的安装包,请前往 GitHub Releases 手动下载');
      return;
    }
    setState(() {
      _updateDownloading = true;
      _downloadProgress = 0;
      _downloadReceived = 0;
      _downloadTotal = asset.size;
    });
    try {
      final dest = await UpdateChecker.suggestDestPath(asset);
      await UpdateChecker.downloadAsset(asset, dest, onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _downloadReceived = received;
          _downloadTotal = total > 0 ? total : asset.size;
          _downloadProgress = total > 0 ? (received / total).clamp(0.0, 1.0) : 0;
        });
      });
      await ref.read(platformServiceProvider).openDownloadedUpdate(dest);
      if (!mounted) return;
      _toast(Platform.isAndroid
          ? '下载完成,已调起系统安装器'
          : '已下载到 ${asset.name},请在文件管理器中解压并替换应用');
    } catch (e) {
      if (mounted) _toast('下载失败:$e');
    } finally {
      if (mounted) setState(() => _updateDownloading = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// 归一到一位小数并夹在 1.0~4.0，避免 divisions 步进的浮点尾差
  double _snapGain(double v) => ((v * 10).round() / 10).clamp(1.0, 4.0).toDouble();

  Future<void> _cleanMissing() async {
    final albums = ref.read(libraryProvider);
    final kept = await ref.read(platformServiceProvider).cleanMissing(albums);
    final removed = albums.length - kept.length;
    await ref.read(libraryProvider.notifier).replaceAll(kept);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(removed > 0 ? '已清理 $removed 张失效专辑' : '库中暂无失效记录'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  Future<void> _reorganizeLibrary() async {
    try {
      final result = await ref.read(libraryReorganizerProvider).reorganizeAll();
      final stats = result.stats;
      if (!mounted) return;
      if (!stats.hasChanges) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已检查全部专辑，元数据与曲目均与本地文件一致'),
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      final parts = <String>[];
      if (stats.updatedAlbums > 0) {
        parts.add('更新 ${stats.updatedAlbums} 张专辑');
      }
      if (stats.removedAlbums > 0) {
        parts.add('清理 ${stats.removedAlbums} 张空专辑');
      }
      if (stats.tracksAdded > 0) {
        parts.add('+${stats.tracksAdded} 首新增');
      }
      if (stats.tracksRemoved > 0) {
        parts.add('-${stats.tracksRemoved} 首删除');
      }
      if (stats.tracksModified > 0) {
        parts.add('${stats.tracksModified} 首标签/信息更新');
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('整理完成：${parts.join('，')}'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('整理失败：$e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _startRescan() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _scanProgress = null;
      _scanStatusText = '准备扫描...';
    });

    try {
      final added = await ref.read(musicFolderScannerProvider).scanAll(
        silent: false,
        onProgress: (p) {
          if (!mounted) return;
          setState(() {
            if (p.total > 0) {
              _scanProgress = (p.processed / p.total).clamp(0.0, 1.0);
            } else {
              _scanProgress = null;
            }
            final folderInfo = p.folderTotal > 1 ? ' [目录 ${p.folderIndex}/${p.folderTotal}]' : '';
            if (p.phase == 'files') {
              _scanStatusText = '正在扫描音频文件: ${p.processed} / ${p.total}$folderInfo';
            } else {
              _scanStatusText = '正在解析组装专辑: ${p.processed} / ${p.total}$folderInfo';
            }
          });
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(added > 0 ? '扫描完成，新增 $added 张专辑' : '扫描完成，没有新内容'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('扫描失败：$e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _scanProgress = null;
          _scanStatusText = null;
        });
      }
    }
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
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (key, label) in [('light', '浅色'), ('dark', '深色')])
                        InkWell(
                          onTap: () => ref.read(settingsProvider.notifier).setTheme(key),
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: settings.theme == key ? theme.colorScheme.surface : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(label, style: const TextStyle(fontSize: 11)),
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
                        onTap: () => ref.read(settingsProvider.notifier).setAccent(accent),
                        mouseCursor: SystemMouseCursors.click,
                        child: Container(
                          width: 22,
                          height: 22,
                          margin: const EdgeInsets.only(left: 8),
                          decoration: BoxDecoration(
                            color: Color(int.parse('FF${accent.substring(1)}', radix: 16)),
                            shape: BoxShape.circle,
                            border: settings.accent == accent
                                ? Border.all(color: theme.colorScheme.onSurface, width: 2)
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
                        value: (_gainDrag ?? settings.audioGain).clamp(1.0, 4.0),
                        label: 'x${(_gainDrag ?? settings.audioGain).toStringAsFixed(1)}',
                        mouseCursor: SystemMouseCursors.click,
                        onChanged: (v) => setState(() => _gainDrag = _snapGain(v)),
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
                  style: TextStyle(fontSize: 10.5, height: 1.5, color: theme.hintColor),
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
                    style: TextStyle(fontSize: 11, height: 1.6, color: theme.hintColor),
                  ),
                ),
              for (final folder in settings.musicFolders)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 15, color: theme.hintColor),
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
                        onPressed: _isScanning
                            ? null
                            : () =>
                                ref.read(settingsProvider.notifier).removeMusicFolder(folder),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  _ActionButton(
                    label: _isScanning ? '扫描中...' : '立即重新扫描',
                    loading: _isScanning,
                    onTap: _isScanning ? null : _startRescan,
                  ),
                  if (settings.musicFolders.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('共 ${settings.musicFolders.length} 个目录',
                        style: TextStyle(fontSize: 10, color: theme.hintColor)),
                  ],
                ],
              ),
              if (_isScanning) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _scanProgress,
                    minHeight: 4,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
                if (_scanStatusText != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    _scanStatusText!,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
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
                  onTap: _isScanning ? null : _reorganizeLibrary,
                ),
              ),
              _SettingRow(
                label: '失效记录',
                trailing: _ActionButton(
                  label: '清理失效记录',
                  onTap: _isScanning ? null : _cleanMissing,
                ),
              ),
              _SettingRow(
                label: '刮削代理',
                trailing: SizedBox(
                  width: 220,
                  child: TextField(
                    controller: TextEditingController(text: settings.scrapeProxy),
                    onChanged: (v) => ref.read(settingsProvider.notifier).setScrapeProxy(v.trim()),
                    decoration: InputDecoration(
                      hintText: '留空使用系统代理',
                      hintStyle: TextStyle(fontSize: 11, color: theme.hintColor),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                      child: Text('K', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Hiko · 音声收藏室', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Text('版本 ${_appVersion ?? '…'} · 本地优先的音声库管理器',
                            style: TextStyle(fontSize: 11, color: theme.hintColor)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 软件更新(两端):检查 GitHub 最新 Release → 一键下载安装
              if (_latestRelease == null && !_updateDownloading)
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
                    color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.system_update_alt_rounded,
                              size: 14, color: theme.colorScheme.primary),
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
                              style: TextStyle(fontSize: 10.5, height: 1.5, color: theme.hintColor),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      if (_updateDownloading)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0 ? _downloadProgress : null,
                                minHeight: 4,
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '正在下载 ${_formatBytes(_downloadReceived)}'
                              '${_downloadTotal > 0 ? ' / ${_formatBytes(_downloadTotal)}' : ''}',
                              style: TextStyle(fontSize: 10, color: theme.hintColor),
                            ),
                          ],
                        )
                      else
                        Row(
                          children: [
                            _ActionButton(
                              label: Platform.isAndroid ? '下载并安装' : '下载更新包',
                              onTap: _downloadUpdate,
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => setState(() => _latestRelease = null),
                              child: Text('暂不更新',
                                  style: TextStyle(fontSize: 11, color: theme.hintColor)),
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
          child: Text('关闭', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface)),
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

/// 字节数人性化显示(下载进度)
String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}
