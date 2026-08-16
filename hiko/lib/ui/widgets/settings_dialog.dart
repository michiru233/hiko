import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';
import '../../data/library_reorganizer.dart';
import '../../data/music_folder_scanner.dart';
import '../../data/settings_store.dart';
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
                trailing: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (gain, label) in [
                        (1.0, '1.0x 标准'),
                        (1.5, '1.5x'),
                        (2.0, '2.0x 翻倍'),
                        (3.0, '3.0x 极限'),
                      ])
                        InkWell(
                          onTap: () {
                            ref.read(settingsProvider.notifier).setAudioGain(gain);
                            ref.read(playbackProvider.notifier).setAudioGain(gain);
                          },
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: (settings.audioGain - gain).abs() < 0.05
                                  ? theme.colorScheme.surface
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: (settings.audioGain - gain).abs() < 0.05
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: (settings.audioGain - gain).abs() < 0.05
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '采用 64-bit 浮点软增益与平滑限幅，在放大微弱音频音量的同时最大程度避免爆音与削波失真。亦可在播放底栏音量图标处快捷调节。',
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
                        Text('版本 1.21.0 · 本地优先的音声库管理器', style: TextStyle(fontSize: 11, color: theme.hintColor)),
                      ],
                    ),
                  ),
                ],
              ),
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
