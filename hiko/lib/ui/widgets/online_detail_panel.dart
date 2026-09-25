import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/online/online_models.dart';
import '../../data/online/online_provider.dart';
import 'online_cover.dart';

/// 桌面端：在线作品详情（从右侧滑出的面板）
class OnlineDetailPanel extends StatelessWidget {
  const OnlineDetailPanel({
    super.key,
    required this.workId,
    required this.onClose,
    this.onSelectTagName,
  });

  final int workId;
  final VoidCallback onClose;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '作品详情',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '关闭',
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.4)),
          Expanded(
            child: OnlineDetailBody(
              workId: workId,
              onSelectTagName: onSelectTagName,
            ),
          ),
        ],
      ),
    );
  }
}

/// 移动端：在线作品详情全屏页
class OnlineDetailScreen extends StatelessWidget {
  const OnlineDetailScreen({super.key, required this.workId, this.onSelectTagName});

  final int workId;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('作品详情', style: TextStyle(fontSize: 15)),
      ),
      body: OnlineDetailBody(workId: workId, onSelectTagName: onSelectTagName),
    );
  }
}

/// 详情主体：面板与全屏页共用
class OnlineDetailBody extends ConsumerWidget {
  const OnlineDetailBody({super.key, required this.workId, this.onSelectTagName});

  final int workId;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(onlineDetailProvider(workId));
    return async.when(
      loading: () => const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (error, _) => _ErrorView(
        message: '$error',
        onRetry: () => ref.invalidate(onlineDetailProvider(workId)),
      ),
      data: (detail) => _DetailContent(
        detail: detail,
        onSelectTagName: onSelectTagName,
      ),
    );
  }
}

class _DetailContent extends ConsumerWidget {
  const _DetailContent({required this.detail, this.onSelectTagName});

  final OnlineDetail detail;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final work = detail.work;
    final audio = detail.audioTracks;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 1,
            child: OnlineCover(url: ref.watch(onlineClientProvider).coverUrl(work.id)),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          work.title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4),
        ),
        const SizedBox(height: 8),
        _MetaLine(work: work),
        if (work.tags.isNotEmpty) ...[
          const SizedBox(height: 14),
          _TagWrap(tags: work.tags, onSelectTagName: onSelectTagName),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: audio.isEmpty
                    ? null
                    : () => _play(context, ref, startIndex: 0),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: Text(audio.isEmpty ? '无可播放音轨' : '播放全部'),
              ),
            ),
          ],
        ),
        if (detail.hasLyrics)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '该作品附带字幕，播放时自动加载到歌词',
              style: TextStyle(fontSize: 11, color: theme.hintColor),
            ),
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Text(
              '音轨（${audio.length}）',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (audio.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('服务器未返回可播放的音轨',
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
          )
        else
          for (var i = 0; i < audio.length; i++)
            _TrackRow(
              index: i,
              track: audio[i],
              onTap: () => _play(context, ref, startIndex: i),
            ),
      ],
    );
  }

  Future<void> _play(BuildContext context, WidgetRef ref,
      {required int startIndex}) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    // 在线队列快照：供「专辑循环」跨作品接续时定位相邻作品
    final queue = ref.read(onlineBrowseProvider).works;
    final error = await ref.read(onlinePlaybackProvider).play(
          detail.work,
          detail.tracks,
          startIndex: startIndex,
          queue: queue,
        );
    if (error != null) {
      messenger?.showSnackBar(SnackBar(content: Text(error)));
    }
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.work});

  final OnlineWork work;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (work.circleName.isNotEmpty) work.circleName,
      if (work.rjCode != null) work.rjCode!,
      if (work.release != null) formatOnlineDate(work.release),
      if (work.durationLabel.isNotEmpty) work.durationLabel,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          parts.join(' · '),
          style: TextStyle(fontSize: 12, color: theme.hintColor),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.download_rounded, size: 13, color: theme.hintColor),
            const SizedBox(width: 3),
            Text(formatOnlineCount(work.dlCount),
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
            if (work.rateCount > 0) ...[
              const SizedBox(width: 12),
              Icon(Icons.star_rounded, size: 13, color: theme.hintColor),
              const SizedBox(width: 3),
              Text('${work.rateAverage}（${work.rateCount}）',
                  style: TextStyle(fontSize: 12, color: theme.hintColor)),
            ],
            if (work.hasSubtitle) ...[
              const SizedBox(width: 12),
              Icon(Icons.subtitles_outlined, size: 13, color: theme.colorScheme.primary),
              const SizedBox(width: 3),
              Text('字幕',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.primary)),
            ],
          ],
        ),
        if (work.vas.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '声优：${work.vas.join('・')}',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ],
    );
  }
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({required this.tags, this.onSelectTagName});

  final List<String> tags;
  final void Function(String tagName)? onSelectTagName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          InkWell(
            borderRadius: BorderRadius.circular(20),
            // 详情接口只给标签名不给 id，点选后由外层在标签表里反查 id
            onTap: onSelectTagName == null ? null : () => onSelectTagName!(tag),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tag, style: const TextStyle(fontSize: 11)),
            ),
          ),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.index, required this.track, required this.onTap});

  final int index;
  final OnlineTrack track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLyrics = track.lyricsHash != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                style: TextStyle(fontSize: 11, color: theme.hintColor),
              ),
            ),
            Expanded(
              child: Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (hasLyrics)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.subtitles_outlined,
                    size: 13, color: theme.colorScheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 30, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: theme.hintColor),
            ),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
