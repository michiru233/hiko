import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/offline_downloads.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../m3e/m3e.dart';
import 'toast.dart';

/// 整包离线下载的勾选对话框（1.99.16）。
/// 按目录（relativePath）分组展示可下载音轨，默认**全不选**（裁决：
/// 由用户自行选择下载哪些内容），顶部可全选，底部实时显示已选体积。
class OfflineDownloadDialog extends ConsumerStatefulWidget {
  const OfflineDownloadDialog({super.key, required this.work, required this.audio});

  final OnlineWork work;
  final List<OnlineTrack> audio;

  static Future<void> show(BuildContext context,
      {required OnlineWork work, required List<OnlineTrack> audio}) {
    return showDialog(
      context: context,
      builder: (_) => OfflineDownloadDialog(work: work, audio: audio),
    );
  }

  @override
  ConsumerState<OfflineDownloadDialog> createState() =>
      _OfflineDownloadDialogState();
}

class _OfflineDownloadDialogState extends ConsumerState<OfflineDownloadDialog> {
  final _selected = <String>{};

  /// relativePath → 该组音轨（保持服务端顺序）
  Map<String, List<OnlineTrack>> get _groups {
    final out = <String, List<OnlineTrack>>{};
    for (final t in widget.audio) {
      out.putIfAbsent(t.relativePath, () => []).add(t);
    }
    return out;
  }

  int get _selectedBytes => [
        for (final t in widget.audio)
          if (_selected.contains(t.hash)) t.size,
      ].fold(0, (a, b) => a + b);

  String get _sizeLabel {
    final b = _selectedBytes;
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }

  void _toggleGroup(String folder, List<OnlineTrack> tracks, bool value) {
    setState(() {
      for (final t in tracks) {
        value ? _selected.add(t.hash) : _selected.remove(t.hash);
      }
    });
  }

  void _submit() {
    final chosen =
        widget.audio.where((t) => _selected.contains(t.hash)).toList();
    if (chosen.isEmpty) return;
    final work = widget.work;
    ref.read(offlineDownloadProvider.notifier).enqueue(OfflineDownloadJob(
          workId: work.id,
          title: work.title,
          rjCode: work.rjCode,
          circleName: work.circleName,
          coverUrl:
              ref.read(onlineClientProvider).coverMainUrl(work.id),
          tracks: chosen,
        ));
    Navigator.pop(context);
    showHikoToast(context, '已加入离线队列（${chosen.length} 轨）');
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final groups = _groups.entries.toList();
    final allSelected = _selected.length == widget.audio.length;
    return M3EDialog(
      maxWidth: 520,
      title: '离线下载 · ${widget.work.title}',
      // 正文自带滚动（ListView 分组），行要贴边
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              M3EButton(
                label: allSelected ? '全不选' : '全选',
                variant: M3EButtonVariant.text,
                size: M3EButtonSize.small,
                onPressed: () => _toggleGroup('*', widget.audio, !allSelected),
              ),
              const Spacer(),
              Text(
                '${_selected.length}/${widget.audio.length} 轨 · $_sizeLabel',
                style: theme.type.bodySmall.copyWith(
                  color: theme.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                for (final entry in groups) ...<Widget>[
                  if (entry.key.isNotEmpty && entry.value.length > 1)
                    _TrackPickRow(
                      title: entry.key,
                      subtitle:
                          '${entry.value.length} 轨 · ${_sizeOf(entry.value)}',
                      selected: entry.value
                          .every((t) => _selected.contains(t.hash)),
                      onTap: () => _toggleGroup(
                        entry.key,
                        entry.value,
                        !entry.value.every((t) => _selected.contains(t.hash)),
                      ),
                    ),
                  for (final t in entry.value)
                    _TrackPickRow(
                      title: t.title,
                      subtitle: t.duration > 0
                          ? '${(t.duration / 60).floor()}:'
                              '${(t.duration % 60).floor().toString().padLeft(2, '0')}'
                              '${t.size > 0 ? ' · ${_sizeOf([t])}' : ''}'
                          : null,
                      selected: _selected.contains(t.hash),
                      onTap: () => setState(() {
                        _selected.contains(t.hash)
                            ? _selected.remove(t.hash)
                            : _selected.add(t.hash);
                      }),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          onPressed: () => Navigator.pop(context),
        ),
        M3EButton(
          label: _selected.isEmpty ? '选择要下载的音轨' : '下载所选（$_sizeLabel）',
          onPressed: _selected.isEmpty ? null : _submit,
        ),
      ],
    );
  }

  static String _sizeOf(List<OnlineTrack> tracks) {
    final b = tracks.fold<int>(0, (a, t) => a + t.size);
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    return '${(b / 1024).toStringAsFixed(0)} KB';
  }
}

/// 可多选的音轨行：`M3EListItem` + 勾选框图标（不用 Material `CheckboxListTile`）。
class _TrackPickRow extends StatelessWidget {
  const _TrackPickRow({
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return M3EListItem(
      title: title,
      subtitle: subtitle,
      selected: selected,
      leading: Icon(
        selected ? Icons.check_box_rounded : Icons.check_box_outline_blank,
        size: 20,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
