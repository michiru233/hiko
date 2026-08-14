import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../playback/playback_controller.dart';
import '../../utils/rj.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';

/// 详情抽屉（对应旧版 aside.details）：封面、标签、RJ 号、曲目列表、进度、收藏、从头播放
class DetailDrawer extends ConsumerStatefulWidget {
  const DetailDrawer({super.key, required this.album, required this.onClose});

  final Album album;
  final VoidCallback onClose;

  @override
  ConsumerState<DetailDrawer> createState() => _DetailDrawerState();
}

class _DetailDrawerState extends ConsumerState<DetailDrawer> {
  late Album _album = widget.album;

  void _refresh(Album album) {
    setState(() => _album = album);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final albums = ref.watch(libraryProvider);
    // 保持与库同步（收藏切换等）
    final album = albums.firstWhere((a) => a.id == _album.id, orElse: () => _album);
    _album = album;

    final playback = ref.watch(playbackProvider);
    final isCurrentAlbum = playback.album?.id == album.id;
    final currentIndex = isCurrentAlbum ? playback.queueIndex : -1;
    final progress = album.totalDuration > 0
        ? ((album.played / album.totalDuration) * 100).round().clamp(0, 100)
        : 0;
    final rj = albumRjCode(album);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: theme.dividerColor)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 35, offset: const Offset(-15, 0)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: AlbumCover(album: album),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Text(
                    '${album.genre.toUpperCase()} · ALBUM ${album.id.padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    album.title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.7),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${album.artist} · ${album.group}',
                    style: TextStyle(fontSize: 12, color: theme.hintColor),
                  ),
                  const SizedBox(height: 20),
                  // 操作
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => ref.read(playbackProvider.notifier).playAlbum(album, index: 0),
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('从头播放', style: TextStyle(fontSize: 11)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () async {
                          await ref
                              .read(libraryProvider.notifier)
                              .updateAlbum(album.id, (a) => a.copyWith(favorite: !a.favorite));
                          _refresh(albums.firstWhere((x) => x.id == album.id));
                        },
                        icon: Icon(
                          album.favorite ? Icons.favorite : Icons.favorite_border,
                          size: 14,
                          color: album.favorite ? const Color(0xFFD34C44) : null,
                        ),
                        label: Text(album.favorite ? '已收藏' : '收藏', style: const TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // 信息行
                  _InfoRow(label: '总时长', value: '${album.tracks.length} 首${album.totalDuration > 0 ? ' · ${formatDuration(album.totalDuration)}' : ''}'),
                  _InfoRow(label: '完成进度', value: '$progress%'),
                  // DLsite 标签
                  if (album.tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        for (final t in album.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE3F4F2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(t, style: const TextStyle(fontSize: 9, color: Color(0xFF2E8A8F))),
                          ),
                      ],
                    ),
                  ],
                  if (rj != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'DLsite $rj${album.dlsiteTitle != null ? ' · ${album.dlsiteTitle}' : ''}',
                      style: TextStyle(fontSize: 10, color: theme.hintColor),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // 曲目列表
                  for (var i = 0; i < album.tracks.length; i++)
                    _TrackRow(
                      track: album.tracks[i],
                      index: i,
                      active: isCurrentAlbum && currentIndex == i,
                      playing: isCurrentAlbum && currentIndex == i && playback.playing,
                      onTap: () {
                        final controller = ref.read(playbackProvider.notifier);
                        if (isCurrentAlbum && currentIndex == i && playback.playing) {
                          controller.pause();
                        } else {
                          controller.playAlbum(album, index: i);
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
          // 关闭按钮
          Positioned(
            right: 14,
            top: 14,
            child: IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 15),
              style: IconButton.styleFrom(
                backgroundColor: Colors.black.withValues(alpha: 0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: theme.hintColor)),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.index,
    required this.active,
    required this.playing,
    required this.onTap,
  });

  final Track track;
  final int index;
  final bool active;
  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: active ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    playing ? 'Ⅱ' : '▶',
                    style: TextStyle(
                      fontSize: 9,
                      color: active ? theme.colorScheme.onPrimary : theme.hintColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 17,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(fontSize: 10, color: theme.hintColor),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color, fontWeight: active ? FontWeight.w600 : FontWeight.w400),
              ),
            ),
            Text(
              track.duration > 0 ? formatTime(track.duration) : '--:--',
              style: TextStyle(fontSize: 10, color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
  }
}
