import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';
import '../../data/library_reorganizer.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../playback/playback_controller.dart';
import '../../utils/rj.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../lyrics/drawer_lyrics_view.dart';
import '../theme.dart';
import 'category_dialog.dart';
import 'rating_dialog.dart';
import 'toast.dart';

/// 详情抽屉：沉浸式玻璃拟态界面（背景大图虚化 + 拟态高光药丸按钮 + 晶透曲目项）
class DetailDrawer extends ConsumerStatefulWidget {
  const DetailDrawer({super.key, required this.album, required this.onClose});

  final Album album;
  final VoidCallback onClose;

  @override
  ConsumerState<DetailDrawer> createState() => _DetailDrawerState();
}

class _DetailDrawerState extends ConsumerState<DetailDrawer> {
  int _selectedTabIndex = 0; // 0: 曲目列表, 1: 歌词字幕

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final album = ref.watch(
      libraryProvider.select(
        (list) => list.firstWhere(
          (a) => a.id == widget.album.id,
          orElse: () => widget.album,
        ),
      ),
    );

    // 精确监听播放状态，避免 positionStream 高频更新导致抽屉频繁整树重建
    final isCurrentAlbum = ref.watch(
      playbackProvider.select((p) => p.album?.id == album.id),
    );
    final currentIndex = ref.watch(
      playbackProvider.select((p) => isCurrentAlbum ? p.queueIndex : -1),
    );
    final isPlaying = ref.watch(
      playbackProvider.select((p) => isCurrentAlbum && p.playing),
    );

    final hasLyrics = ref.watch(
      lyricsProvider.select((l) => l.hasLyrics),
    );

    final progress = album.totalDuration > 0
        ? ((album.played / album.totalDuration) * 100).round().clamp(0, 100)
        : 0;
    final rj = albumRjCode(album);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? HikoColors.darkGlassSurface : HikoColors.lightGlassSurface,
        border: Border(
          left: BorderSide(
            color: isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorder,
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
            blurRadius: 40,
            offset: const Offset(-15, 0),
          ),
        ],
      ),
      child: Stack(
        children: [
          // 沉浸式虚化封面氛围背板 (Ambient Cover Backdrop)
          Positioned(
            top: -60,
            right: -60,
            width: 320,
            height: 320,
            child: IgnorePointer(
              child: Opacity(
                opacity: isDark ? 0.22 : 0.16,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                  child: AlbumCover(album: album),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面（带玻璃投光阴影与精细圆角）
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.15),
                            blurRadius: 26,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: AlbumCover(album: album),
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        InkWell(
                          onTap: () async {
                            final chosen = await showSelectCategoryDialog(
                              context,
                              currentGenre: album.genre,
                              albumCount: 1,
                            );
                            if (chosen != null && chosen != album.genre) {
                              await ref
                                  .read(libraryProvider.notifier)
                                  .updateAlbum(album.id, (a) => a.copyWith(genre: chosen));
                            }
                          },
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: theme.colorScheme.primary.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${album.genre.toUpperCase()} · ALBUM ${album.id.padLeft(2, '0')}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.1,
                                    fontWeight: FontWeight.w700,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.arrow_drop_down, size: 14, color: theme.colorScheme.primary),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      album.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${album.artist} · ${album.rjCode ?? '本地导入'}',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    const SizedBox(height: 20),
                    // 操作胶囊按钮
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            elevation: 0,
                          ),
                          onPressed: () => ref.read(playbackProvider.notifier).playAlbum(album, index: 0),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('从头播放', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            side: BorderSide(
                              color: isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorderSubtle,
                            ),
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                          ),
                          onPressed: () async {
                            await ref
                                .read(libraryProvider.notifier)
                                .updateAlbum(album.id, (a) => a.copyWith(favorite: !a.favorite));
                          },
                          icon: Icon(
                            album.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 15,
                            color: album.favorite ? const Color(0xFFD34C44) : null,
                          ),
                          label: Text(album.favorite ? '已收藏' : '收藏', style: const TextStyle(fontSize: 11)),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            side: BorderSide(
                              color: isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorderSubtle,
                            ),
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                          ),
                          onPressed: () async {
                            final rating = await showRatingDialog(
                              context,
                              initialRating: album.rating,
                            );
                            if (rating == null || !context.mounted) return;
                            await ref
                                .read(libraryProvider.notifier)
                                .updateAlbum(album.id, (a) => a.copyWith(rating: rating));
                          },
                          icon: Icon(
                            album.rating > 0 ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: 15,
                            color: album.rating > 0 ? const Color(0xFFE8B33C) : null,
                          ),
                          label: Text(
                            album.rating > 0 ? '${album.rating} 星' : '未评分',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                            side: BorderSide(
                              color: isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorderSubtle,
                            ),
                            backgroundColor: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                          ),
                          onPressed: () async {
                            try {
                              final result = await ref
                                  .read(libraryReorganizerProvider)
                                  .reorganizeSingleAlbum(album);
                              if (result.albums.isNotEmpty) {
                                final updated = result.albums.first;
                                await ref
                                    .read(libraryProvider.notifier)
                                    .updateAlbum(album.id, (_) => updated);
                              }
                              if (context.mounted) {
                                final stats = result.stats;
                                final msg = stats.hasChanges
                                    ? '专辑已整理完成（变动已同步）'
                                    : '专辑文件与元数据已是最新';
                                showHikoToast(context, msg);
                              }
                            } catch (e) {
                              if (context.mounted) {
                                showHikoToast(context, '整理失败：$e');
                              }
                            }
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 15),
                          label: const Text('整理专辑', style: TextStyle(fontSize: 11)),
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
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in album.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE3F4F2).withValues(alpha: isDark ? 0.2 : 0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(t, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Color(0xFF2E8A8F))),
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
                    const SizedBox(height: 20),
                    // 双 Tab 导航：曲目列表 vs 歌词字幕（胶囊分段开关）
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? HikoColors.darkGlassBorderSubtle : HikoColors.lightGlassBorderSubtle,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TabButton(
                              label: '曲目列表 (${album.tracks.length})',
                              icon: Icons.format_list_bulleted_rounded,
                              selected: _selectedTabIndex == 0,
                              onTap: () => setState(() => _selectedTabIndex = 0),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _TabButton(
                              label: '歌词字幕',
                              icon: Icons.subtitles_rounded,
                              hasBadge: isCurrentAlbum && hasLyrics,
                              selected: _selectedTabIndex == 1,
                              onTap: () => setState(() => _selectedTabIndex = 1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Tab 内容切换
                    if (_selectedTabIndex == 0) ...[
                      for (var i = 0; i < album.tracks.length; i++)
                        _TrackRow(
                          track: album.tracks[i],
                          index: i,
                          active: isCurrentAlbum && currentIndex == i,
                          playing: isCurrentAlbum && currentIndex == i && isPlaying,
                          onTap: () {
                            final controller = ref.read(playbackProvider.notifier);
                            if (isCurrentAlbum && currentIndex == i && isPlaying) {
                              controller.pause();
                            } else {
                              controller.playAlbum(album, index: i);
                            }
                          },
                        ),
                    ] else ...[
                      const SizedBox(
                        height: 380,
                        child: DrawerLyricsView(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 关闭按钮（玻璃悬浮微圆角）
          Positioned(
            right: 14,
            top: 14,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: IconButton(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.hasBadge = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool hasBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 13,
              color: selected ? primaryColor : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? (isDark ? Colors.white : primaryColor)
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
            ),
            if (hasBadge) ...[
              const SizedBox(width: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
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
    final isDark = theme.brightness == Brightness.dark;
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      mouseCursor: SystemMouseCursors.click,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: active
              ? Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  width: 1,
                )
              : null,
        ),
        child: Row(
          children: [
            InkWell(
              onTap: onTap,
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: active
                      ? theme.colorScheme.primary
                      : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05)),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  // Material 图标：与播放条统一，避免文字符号在 Android 字体渲染异常
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 13,
                    color: active ? theme.colorScheme.onPrimary : theme.hintColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 20,
              child: Text(
                (index + 1).toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? theme.colorScheme.primary : theme.hintColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              track.duration > 0 ? formatTime(track.duration) : '--:--',
              style: TextStyle(
                fontSize: 10,
                color: active ? theme.colorScheme.primary : theme.hintColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
