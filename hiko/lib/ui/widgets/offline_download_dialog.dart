import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/offline_downloads.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
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
    final theme = Theme.of(context);
    final groups = _groups.entries.toList();
    return AlertDialog(
      title: Text('离线下载 · ${widget.work.title}',
          style: const TextStyle(fontSize: 15), maxLines: 2),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => _toggleGroup(
                      '*', widget.audio, _selected.length != widget.audio.length),
                  child: Text(
                    _selected.length == widget.audio.length ? '全不选' : '全选',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const Spacer(),
                Text('${_selected.length}/${widget.audio.length} 轨 · $_sizeLabel',
                    style: TextStyle(fontSize: 11, color: theme.hintColor)),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final entry in groups) ...[
                    if (entry.key.isNotEmpty && entry.value.length > 1)
                      CheckboxListTile(
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: entry.value
                            .every((t) => _selected.contains(t.hash)),
                        onChanged: (v) => _toggleGroup(
                            entry.key, entry.value, v ?? false),
                        title: Text(
                          entry.key,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${entry.value.length} 轨 · ${_sizeOf(entry.value)}',
                          style:
                              TextStyle(fontSize: 10, color: theme.hintColor),
                        ),
                      ),
                    for (final t in entry.value)
                      CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _selected.contains(t.hash),
                        onChanged: (v) => setState(() {
                          v ?? false
                              ? _selected.add(t.hash)
                              : _selected.remove(t.hash);
                        }),
                        title: Text(t.title,
                            style: const TextStyle(fontSize: 11)),
                        subtitle: t.duration > 0
                            ? Text(
                                '${(t.duration / 60).floor()}:${(t.duration % 60).floor().toString().padLeft(2, '0')}'
                                '${t.size > 0 ? ' · ${_sizeOf([t])}' : ''}',
                                style: TextStyle(
                                    fontSize: 10, color: theme.hintColor),
                              )
                            : null,
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty ? null : _submit,
          child: Text(_selected.isEmpty ? '选择要下载的音轨' : '下载所选（$_sizeLabel）'),
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
