import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/offline_downloads.dart';
import '../../data/online/online_provider.dart';
import '../detail_jump_requests.dart';
import '../m3e/m3e.dart';
import '../widgets/online_cover.dart';
import '../widgets/toast.dart';

/// 下载中心（1.99.54）。
///
/// 三段的固定顺序：**进行中 → 失败 → 已完成**。进行中的作品逐文件展开，
/// 每行带自己的阶段（等待 / 下载中 x% / 完成 / 失败）；已完成的收成一行。
///
/// 为什么单独一页而不是塞进设置：这里的核心诉求是「下载时能看到进度」，
/// 它得是一个随时可进、且能一直盯着的地方。
class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key, this.isMobile = false});

  final bool isMobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m3e = M3ETheme.of(context);
    final states = ref.watch(offlineDownloadProvider);
    final done = ref.watch(offlineIndexListProvider);
    final service = ref.read(offlineDownloadProvider.notifier);

    final active = <int>[
      for (final e in states.entries)
        if (e.value is DownloadQueued || e.value is DownloadRunning) e.key,
    ];
    final failed = <int>[
      for (final e in states.entries)
        if (e.value is DownloadFailed) e.key,
    ];

    final summary = <String>[
      if (active.isNotEmpty) '${active.length} 进行中',
      if (failed.isNotEmpty) '${failed.length} 失败',
      if (done.isNotEmpty) '${done.length} 已完成',
    ].join(' · ');

    final children = <Widget>[
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          Text(
            '下载',
            style: m3e.type.headlineSmall.copyWith(color: m3e.colors.onSurface),
          ),
          const SizedBox(width: 12),
          if (summary.isNotEmpty)
            Text(
              summary,
              style: m3e.type.labelSmall.copyWith(
                color: m3e.colors.onSurfaceVariant,
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
    ];

    if (active.isEmpty && failed.isEmpty && done.isEmpty) {
      children.add(_EmptyDownloads(m3e: m3e));
    }

    for (final id in active) {
      final state = states[id];
      if (state == null) continue;
      children.add(_JobCard(state: state, onCancel: () => service.cancel(id)));
      children.add(const SizedBox(height: 12));
    }

    for (final id in failed) {
      final state = states[id];
      if (state is! DownloadFailed) continue;
      children.add(
        _FailedCard(
          title: state.title,
          message: state.message,
          onRetry: () => service.retry(id),
          onDismiss: () => service.forget(id),
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    for (final entry in done) {
      children.add(
        _DoneCard(
          entry: entry,
          onOpen: () {
            // 复用「打开在线详情」那条指令通道：宿主会切到在线视图并弹详情
            ref.read(onlineDetailRequestProvider.notifier).state = entry.workId;
          },
          onDelete: () => _confirmDelete(context, ref, entry),
        ),
      );
      children.add(const SizedBox(height: 12));
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 48,
        isMobile ? 12 : 24,
        isMobile ? 16 : 48,
        32,
      ),
      children: children,
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    OfflineWorkEntry entry,
  ) async {
    final m3e = M3ETheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => M3EDialog(
        title: '删除离线内容',
        content: Text(
          '将删除「${entry.title}」已下载的 ${entry.files.length} 个文件，'
          '再次收听需要重新联网。',
          style: m3e.type.bodyMedium.copyWith(
            color: m3e.colors.onSurfaceVariant,
          ),
        ),
        actions: <Widget>[
          M3EButton(
            label: '取消',
            variant: M3EButtonVariant.text,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          M3EButton(
            label: '删除',
            variant: M3EButtonVariant.destructive,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(onlineAudioCacheProvider).removeWork(entry.workId);
    await ref.read(offlineIndexListProvider.notifier).remove(entry.workId);
    ref.read(offlineDownloadProvider.notifier).forget(entry.workId);
    if (context.mounted) showHikoToast(context, '已删除离线内容');
  }
}

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads({required this.m3e});

  final M3EThemeData m3e;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: <Widget>[
          Icon(
            Icons.download_for_offline_outlined,
            size: 36,
            color: m3e.colors.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            '还没有离线下载',
            style: m3e.type.titleSmall.copyWith(color: m3e.colors.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            '在在线作品的详情页点「离线下载」，选中的文件会出现在这里',
            textAlign: TextAlign.center,
            style: m3e.type.bodySmall.copyWith(
              color: m3e.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// 进行中 / 排队中的作品卡：总进度 + 逐文件阶段。
class _JobCard extends StatelessWidget {
  const _JobCard({required this.state, required this.onCancel});

  final WorkDownloadState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final running = state is DownloadRunning ? state as DownloadRunning : null;
    final queued = state is DownloadQueued;
    final title = switch (state) {
      DownloadRunning(:final title) => title,
      DownloadQueued(:final title) => title,
      _ => '',
    };
    final cover = switch (state) {
      DownloadRunning(:final coverUrl) => coverUrl,
      DownloadQueued(:final coverUrl) => coverUrl,
      _ => '',
    };

    final percent = _percentOf(running);
    final meta = running == null
        ? '${queued ? (state as DownloadQueued).trackCount : 0} 轨 · 排队中'
        : '${running.done} / ${running.total} 文件 · '
              '${_bytes(running.receivedBytes)} / ${_bytes(running.totalBytes)}';

    return M3ECard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: M3EShape.radius(M3EShape.sm),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: OnlineCover(url: cover),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: m3e.type.titleSmall.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      style: m3e.type.labelSmall.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              if (running != null) ...<Widget>[
                const SizedBox(width: 8),
                Text(
                  '$percent%',
                  style: m3e.type.labelLarge.copyWith(color: colors.primary),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          M3EProgress(value: percent / 100),
          if (running != null) ...<Widget>[
            const SizedBox(height: 8),
            for (final file in running.files) _FileProgressRow(file: file),
          ],          Row(
            children: <Widget>[
              const Spacer(),
              M3EButton(
                label: queued ? '取消排队' : '取消下载',
                variant: M3EButtonVariant.text,
                size: M3EButtonSize.small,
                onPressed: onCancel,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static int _percentOf(DownloadRunning? running) {
    if (running == null) return 0;
    if (running.totalBytes > 0) {
      final p = running.receivedBytes * 100 / running.totalBytes;
      return p.clamp(0, 100).round();
    }
    if (running.total > 0) {
      return (running.done * 100 / running.total).round();
    }
    return 0;
  }
}

/// 单个文件的阶段行：完成 / 下载中（带 2dp 细条）/ 等待 / 失败。
class _FileProgressRow extends StatelessWidget {
  const _FileProgressRow({required this.file});

  final FileDownloadProgress file;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final style = m3e.type.labelSmall.copyWith(
      color: file.phase == FileDownloadPhase.pending
          ? colors.onSurfaceVariant
          : colors.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final (icon, trailing) = switch (file.phase) {
      FileDownloadPhase.done => (
        Icon(Icons.check_rounded, size: 14, color: colors.primary),
        _bytes(file.size),
      ),
      FileDownloadPhase.running => (
        Icon(Icons.arrow_downward_rounded, size: 14, color: colors.primary),
        file.size > 0
            ? '${(file.received * 100 / file.size).clamp(0, 100).round()}%'
            : '下载中',
      ),
      FileDownloadPhase.failed => (
        Icon(Icons.error_outline_rounded, size: 14, color: colors.error),
        '失败',
      ),
      FileDownloadPhase.pending => (
        Icon(
          Icons.radio_button_unchecked_rounded,
          size: 12,
          color: colors.outline,
        ),
        '等待',
      ),
    };

    final fraction = file.phase == FileDownloadPhase.done
        ? 1.0
        : (file.size > 0 ? (file.received / file.size).clamp(0.0, 1.0) : 0.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(width: 16, child: Center(child: icon)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  file.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: m3e.type.labelSmall.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          if (file.phase == FileDownloadPhase.running)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 3),
              child: M3EProgress(value: fraction, height: 2),
            ),
        ],
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.onDismiss,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    return M3ECard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: m3e.type.titleSmall.copyWith(color: colors.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: m3e.type.bodySmall.copyWith(color: colors.onSurfaceVariant),
          ),
          Row(
            children: <Widget>[
              const Spacer(),
              M3EButton(
                label: '移除',
                variant: M3EButtonVariant.text,
                size: M3EButtonSize.small,
                onPressed: onDismiss,
              ),
              M3EButton(
                label: '重试',
                size: M3EButtonSize.small,
                onPressed: onRetry,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({
    required this.entry,
    required this.onOpen,
    required this.onDelete,
  });

  final OfflineWorkEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final colors = m3e.colors;
    final audioCount = entry.files.values
        .where((f) => f.kind == 'audio')
        .length;
    return M3ECard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: M3EShape.radius(M3EShape.sm),
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: OnlineCover(url: entry.coverUrl),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: m3e.type.titleSmall.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '已完成 · $audioCount 轨 · ${_bytes(entry.totalBytes)}',
                      style: m3e.type.labelSmall.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Row(
            children: <Widget>[
              const Spacer(),
              M3EButton(
                label: '删除',
                variant: M3EButtonVariant.text,
                size: M3EButtonSize.small,
                onPressed: onDelete,
              ),
              M3EButton(
                label: '打开',
                size: M3EButtonSize.small,
                onPressed: onOpen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _bytes(int b) {
  if (b >= 1024 * 1024 * 1024) {
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
  if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  return '$b B';
}
