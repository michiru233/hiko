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
import '../widgets/category_dialog.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/toast.dart';
import 'fullscreen_player_screen.dart';

/// 移动端专辑详情全屏页面（1.56）：沉浸式大图背景+顶栏返回+曲目列表+操作按钮
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  int _selectedTabIndex = 0; // 0: 曲目列表, 1: 歌词字幕

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final album = ref.watch(
      libraryProvider.select(
        (list) => list.firstWhere(
          (a) => a.id == widget.albumId,
          orElse: () => throw StateError('Album not found: ${widget.albumId}'),
        ),
      ),
    );

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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.arrow_back,
              color: isDark ? Colors.white : Colors.black87,
              size: 20,
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          // 背景大图高斯模糊
          Positioned.fill(
            child: AlbumCover(
              album: album,
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Container(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.6)
                    : Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ),
          // 内容区
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                // 封面与元数据
                _buildHeader(album, theme, isDark, rj, progress),
                const SizedBox(height: 16),
                // Tab 切换（曲目/歌词）
                _buildTabs(theme, isDark, hasLyrics),
                const SizedBox(height: 8),
                // 内容区域 - 移除底部 padding，让列表居中
                Expanded(
                  child: _selectedTabIndex == 0
                      ? _buildTrackList(
                          album,
                          theme,
                          isDark,
                          currentIndex,
                          isPlaying,
                        )
                      : const DrawerLyricsView(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    Album album,
    ThemeData theme,
    bool isDark,
    String? rj,
    int progress,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          // 封面 - 缩小尺寸
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 160,
              height: 160,
              child: AlbumCover(
                album: album,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // 标题
          Text(
            album.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          // 艺术家
          Text(
            album.albumArtist,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          // RJ 码 + 时长 + 进度
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              if (rj != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rj,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  album.totalDuration > 0
                      ? formatDuration(album.totalDuration)
                      : '${album.duration} 首',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                  ),
                ),
              ),
              if (progress > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '已听 $progress%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // 操作按钮行
          _buildActionButtons(album, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Album album, ThemeData theme, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 全部播放 - 点击后跳转到全屏播放页
        ElevatedButton.icon(
          onPressed: () {
            ref.read(playbackProvider.notifier).playAlbum(album);
            // 自动跳转到全屏播放页
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const FullscreenPlayerScreen(),
              ),
            );
          },
          icon: const Icon(Icons.play_arrow, size: 20),
          label: const Text('全部播放'),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // 评分
        IconButton(
          onPressed: () => _showRatingDialog(album),
          icon: Icon(
            album.rating > 0 ? Icons.star : Icons.star_border,
            color: album.rating > 0
                ? Colors.amber
                : (isDark ? HikoColors.darkMuted : HikoColors.lightMuted),
          ),
          tooltip: '评分',
        ),
        // 分类
        IconButton(
          onPressed: () => _showCategoryDialog(album),
          icon: Icon(
            Icons.label_outline,
            color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
          ),
          tooltip: '分类',
        ),
      ],
    );
  }

  Widget _buildTabs(ThemeData theme, bool isDark, bool hasLyrics) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildTab('曲目', 0, theme, isDark),
          const SizedBox(width: 16),
          if (hasLyrics) _buildTab('歌词', 1, theme, isDark),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index, ThemeData theme, bool isDark) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? theme.colorScheme.primary
                : (isDark ? HikoColors.darkMuted : HikoColors.lightMuted),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackList(
    Album album,
    ThemeData theme,
    bool isDark,
    int currentIndex,
    bool isPlaying,
  ) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: album.tracks.length,
      itemBuilder: (context, index) {
        final track = album.tracks[index];
        final isCurrent = index == currentIndex;
        return _buildTrackItem(
          track,
          index,
          album,
          theme,
          isDark,
          isCurrent,
          isPlaying,
        );
      },
    );
  }

  Widget _buildTrackItem(
    Track track,
    int index,
    Album album,
    ThemeData theme,
    bool isDark,
    bool isCurrent,
    bool isPlaying,
  ) {
    return Material(
      color: isCurrent
          ? theme.colorScheme.primary.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          ref.read(playbackProvider.notifier).playAlbum(album, index: index);
          // 点击曲目后自动跳转到全屏播放页
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const FullscreenPlayerScreen(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 序号或播放中图标
              SizedBox(
                width: 32,
                child: isCurrent
                    ? Icon(
                        isPlaying ? Icons.volume_up : Icons.pause,
                        size: 18,
                        color: theme.colorScheme.primary,
                      )
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark
                              ? HikoColors.darkMuted
                              : HikoColors.lightMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const SizedBox(width: 8),
              // 曲名
              Expanded(
                child: Text(
                  track.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : (isDark ? HikoColors.darkInk : HikoColors.lightInk),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // 时长
              Text(
                formatDuration(track.duration),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRatingDialog(Album album) async {
    final rating = await showRatingDialog(
      context,
      initialRating: album.rating,
    );
    if (rating != null && mounted) {
      await ref.read(libraryProvider.notifier).updateAlbum(
            album.id,
            (a) => a.copyWith(rating: rating),
          );
      if (mounted) showHikoToast(context, rating > 0 ? '已评 $rating 星' : '已清除评分');
    }
  }

  Future<void> _showCategoryDialog(Album album) async {
    final chosen = await showSelectCategoryDialog(
      context,
      currentGenre: album.genre,
    );
    if (chosen != null && mounted) {
      await ref.read(libraryProvider.notifier).updateAlbum(
            album.id,
            (a) => a.copyWith(genre: chosen),
          );
      if (mounted) showHikoToast(context, chosen.isEmpty ? '已移至未分类' : '已移至 $chosen');
    }
  }
}
