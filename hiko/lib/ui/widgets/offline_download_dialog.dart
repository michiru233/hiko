import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/offline_downloads.dart';
import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import '../m3e/m3e.dart';
import 'toast.dart';

String _formatBytes(int b) {
  if (b >= 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024).toStringAsFixed(0)} KB';
}

/// 整包离线下载的勾选对话框（1.99.16；1.99.53 按 M3E 重排）。
///
/// 按目录（relativePath）分组展示可下载音轨，默认**全不选**（裁决 Q：
/// 由用户自行选择下载哪些内容）。这一版的定位是**文件清单**而不是曲目清单 ——
/// 行标题保留原始文件名（含 `.mp3` 与作者给的 `TrackN` 前缀），
/// 用户在下载前要能看清自己选的到底是哪个文件。
///
/// 结构（自上而下）：
/// 1. 标题「离线下载」+ 作品名副行（2 行省略）+ 总量；
/// 2. 全选栏：三态勾选 + 「全选」+ 右侧「已选 N / M 轨 · 体积」；
/// 3. 分组列表：组头（目录末段 + 上级路径 + 组统计 + 组三态勾选，点整组切换）
///    + 56dp 单行文件行（勾选 + 文件名 + 时长 + 体积）；
/// 4. 底部：取消 / 下载（文案固定，体积只在全选栏出现一次）。
class OfflineDownloadDialog extends ConsumerStatefulWidget {
  const OfflineDownloadDialog({
    super.key,
    required this.work,
    required this.audio,
  });

  final OnlineWork work;
  final List<OnlineTrack> audio;

  static Future<void> show(
    BuildContext context, {
    required OnlineWork work,
    required List<OnlineTrack> audio,
  }) {
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

  String get _sizeLabel => _formatBytes(_selectedBytes);

  bool get _allSelected =>
      widget.audio.isNotEmpty && _selected.length == widget.audio.length;

  bool get _someSelected => _selected.isNotEmpty && !_allSelected;

  void _toggleGroup(List<OnlineTrack> tracks, bool value) {
    setState(() {
      for (final t in tracks) {
        value ? _selected.add(t.hash) : _selected.remove(t.hash);
      }
    });
  }

  void _toggleAll(bool value) => _toggleGroup(widget.audio, value);

  void _submit() {
    final chosen = widget.audio
        .where((t) => _selected.contains(t.hash))
        .toList();
    if (chosen.isEmpty) return;
    final work = widget.work;
    ref
        .read(offlineDownloadProvider.notifier)
        .enqueue(
          OfflineDownloadJob(
            workId: work.id,
            title: work.title,
            rjCode: work.rjCode,
            circleName: work.circleName,
            coverUrl: ref.read(onlineClientProvider).coverMainUrl(work.id),
            tracks: chosen,
          ),
        );
    Navigator.pop(context);
    showHikoToast(context, '已加入离线队列（${chosen.length} 轨）');
  }

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final type = m3e.type;
    final groups = _groups.entries.toList();
    // 列表最多吃掉半个屏高：32 条轨也不会把对话框顶出屏幕
    final listMaxHeight = (MediaQuery.sizeOf(context).height * 0.5).clamp(
      180.0,
      480.0,
    );

    return M3EDialog(
      maxWidth: 520,
      title: '离线下载',
      // 正文自带滚动（分组列表），行要贴边
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // 作品名做副行：标题位只留给「离线下载」，长作品名最多两行
          Text(
            widget.work.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: type.bodyMedium.copyWith(color: colors.onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            '${widget.audio.length} 轨 · ${_formatBytes(_totalBytes)}',
            style: type.labelSmall.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          _SelectAllBar(
            allSelected: _allSelected,
            someSelected: _someSelected,
            summary:
                '已选 ${_selected.length} / ${widget.audio.length} 轨'
                '${_selected.isEmpty ? '' : ' · $_sizeLabel'}',
            onToggle: _toggleAll,
          ),
          Divider(height: 1, thickness: 1, color: colors.outlineVariant),
          const SizedBox(height: 4),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '服务器没有可下载的音轨',
                textAlign: TextAlign.center,
                style: type.bodyMedium.copyWith(color: colors.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: listMaxHeight),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 4),
                children: <Widget>[
                  for (final entry in groups) ...<Widget>[
                    if (entry.key.isNotEmpty && entry.value.length > 1)
                      _GroupHeader(
                        path: entry.key,
                        count: entry.value.length,
                        sizeLabel: _formatBytes(_sum(entry.value)),
                        allSelected: entry.value.every(
                          (t) => _selected.contains(t.hash),
                        ),
                        someSelected:
                            entry.value.any(
                              (t) => _selected.contains(t.hash),
                            ) &&
                            !entry.value.every(
                              (t) => _selected.contains(t.hash),
                            ),
                        onToggle: () => _toggleGroup(
                          entry.value,
                          !entry.value.every((t) => _selected.contains(t.hash)),
                        ),
                      ),
                    for (final t in entry.value)
                      _FilePickRow(
                        track: t,
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
        M3EButton(label: '下载', onPressed: _selected.isEmpty ? null : _submit),
      ],
    );
  }

  int get _totalBytes => _sum(widget.audio);

  static int _sum(List<OnlineTrack> tracks) =>
      tracks.fold<int>(0, (a, t) => a + t.size);
}

/// 全选栏：三态勾选 + 文案 + 右侧摘要。48dp，不随列表滚动。
class _SelectAllBar extends StatelessWidget {
  const _SelectAllBar({
    required this.allSelected,
    required this.someSelected,
    required this.summary,
    required this.onToggle,
  });

  final bool allSelected;
  final bool someSelected;
  final String summary;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    return SizedBox(
      height: 48,
      child: Row(
        children: <Widget>[
          // 勾选框与「全选」两个字是一个整体：点哪都切换（48dp 行高做热区）
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: M3EPressable(
                onTap: () => onToggle(!allSelected),
                borderRadius: M3EShape.radius(M3EShape.sm),
                pressScale: 0.99,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    M3ECheckbox(
                      value: allSelected,
                      indeterminate: someSelected,
                      semanticLabel: '全选',
                      onChanged: onToggle,
                    ),
                    Text(
                      '全选',
                      style: m3e.type.labelLarge.copyWith(
                        color: m3e.colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            summary,
            style: m3e.type.labelSmall.copyWith(
              color: m3e.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 目录组头（40dp）：目录末段 + 上级路径小字 + 组统计 + 组三态勾选。
/// 点整行 = 勾选/取消整组；悬停可看完整路径。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.path,
    required this.count,
    required this.sizeLabel,
    required this.allSelected,
    required this.someSelected,
    required this.onToggle,
  });

  final String path;
  final int count;
  final String sizeLabel;
  final bool allSelected;
  final bool someSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final type = m3e.type;
    final segments = path.split('/');
    final name = segments.last;
    final parent = segments.length > 1
        ? segments.sublist(0, segments.length - 1).join(' / ')
        : '';

    return Tooltip(
      message: path,
      child: M3EPressable(
        onTap: onToggle,
        borderRadius: M3EShape.radius(M3EShape.sm),
        pressScale: 0.99,
        child: SizedBox(
          height: 40,
          child: Row(
            children: <Widget>[
              const SizedBox(width: 4),
              Icon(
                Icons.folder_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: name,
                        style: type.labelLarge.copyWith(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (parent.isNotEmpty)
                        TextSpan(
                          text: '  $parent',
                          style: type.labelSmall.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count 轨 · $sizeLabel',
                style: type.labelSmall.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              M3ECheckbox(
                value: allSelected,
                indeterminate: someSelected,
                semanticLabel: '全选 $name',
                onChanged: (_) => onToggle(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个文件行（56dp）：勾选 + 原始文件名 + 时长 + 体积。
///
/// 标题**不做清洗**（1.99.53 裁决）：下载前用户要看清拿到的到底是哪个文件，
/// `.mp3` 与 `TrackN` 前缀都是源文件结构的一部分；过长时省略 + tooltip 看全名。
class _FilePickRow extends StatelessWidget {
  const _FilePickRow({
    required this.track,
    required this.selected,
    required this.onTap,
  });

  final OnlineTrack track;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final type = m3e.type;

    return M3EPressable(
      onTap: onTap,
      borderRadius: M3EShape.radius(M3EShape.lg),
      pressScale: 0.99,
      stateLayerColor: selected
          ? colors.onSecondaryContainer
          : colors.onSurface,
      child: AnimatedContainer(
        duration: m3e.motion.stateLayerDuration,
        height: 56,
        padding: const EdgeInsets.only(left: 4, right: 8),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: M3EShape.radius(M3EShape.lg),
        ),
        child: Row(
          children: <Widget>[
            M3ECheckbox(
              value: selected,
              semanticLabel: track.title,
              onChanged: (_) => onTap(),
            ),
            Expanded(
              child: Tooltip(
                message: track.title,
                child: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: type.bodyMedium.copyWith(
                    color: selected
                        ? colors.onSecondaryContainer
                        : colors.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 48,
              child: Text(
                _durationLabel(track.duration),
                textAlign: TextAlign.right,
                style: type.labelMedium.copyWith(
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Text(
                track.size > 0 ? _formatBytes(track.size) : '--',
                textAlign: TextAlign.right,
                style: type.labelMedium.copyWith(
                  color: selected
                      ? colors.onSecondaryContainer
                      : colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _durationLabel(double seconds) {
    if (seconds <= 0) return '--:--';
    final m = seconds ~/ 60;
    final s = (seconds % 60).floor();
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
