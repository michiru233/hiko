import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../playback/playback_controller.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../utils/rj.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../lyrics/drawer_lyrics_view.dart';
import '../theme.dart';
import '../widgets/category_dialog.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/toast.dart';
import 'fullscreen_player_screen.dart';

/// 移动端专辑详情全屏页面（1.56；1.77 重构为整页 CustomScrollView）：
/// 全宽封面→标题→元信息胶囊→社团/声优分色胶囊→操作按钮→曲目/歌词，一直往下滑。
/// 社团（紫）/声优（蓝）胶囊点选后 pop 回列表页按该人筛选。
class AlbumDetailScreen extends ConsumerStatefulWidget {
  const AlbumDetailScreen({super.key, required this.albumId});

  final String albumId;

  @override
  ConsumerState<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends ConsumerState<AlbumDetailScreen> {
  int _selectedTabIndex = 0; // 0: 曲目列表, 1: 歌词字幕

  static const _circleColor = Color(0xFFB39DDB); // 社团紫
  static const _voiceColor = Color(0xFF90CAF9); // 声优蓝

  /// 声优串拆分：多轨 TPE1 常见分隔符（全半角）
  static final _voiceSplitPattern = RegExp(r'[、，,／/;；]');

  List<String> _voiceNames(Album album) => album.artist
      .split(_voiceSplitPattern)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

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
      body: CustomScrollView(
        slivers: [
          // 全宽封面（1:1），延伸到顶栏背后
          SliverToBoxAdapter(
            child: AspectRatio(
              aspectRatio: 1,
              child: AlbumCover(album: album, fit: BoxFit.cover),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _buildHeader(album, theme, isDark, rj, progress),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            sliver: SliverToBoxAdapter(
              child: _buildTabs(theme, isDark, hasLyrics),
            ),
          ),
          if (_selectedTabIndex == 0)
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 24,
              ),
              sliver: SliverList.builder(
                itemCount: album.tracks.length,
                itemBuilder: (context, index) => _buildTrackItem(
                  album.tracks[index],
                  index,
                  album,
                  theme,
                  isDark,
                  index == currentIndex,
                  isPlaying,
                ),
              ),
            )
          else
            // 歌词视图自带内部滚动，占满剩余视口
            SliverFillRemaining(
              hasScrollBody: true,
              child: DrawerLyricsView(),
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
    final circle = album.albumArtist.trim();
    final voices = _voiceNames(album);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Text(
          album.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.3,
            color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
          ),
        ),
        const SizedBox(height: 10),
        // RJ 码 + 时长 + 进度
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (rj != null)
              _buildMetaPill(
                rj,
                color: theme.colorScheme.primary,
                background: theme.colorScheme.primary.withValues(alpha: 0.2),
                isDark: isDark,
              ),
            _buildMetaPill(
              album.totalDuration > 0
                  ? formatDuration(album.totalDuration)
                  : '${album.duration} 首',
              color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
              background: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              isDark: isDark,
            ),
            if (progress > 0)
              _buildMetaPill(
                '已听 $progress%',
                color: theme.colorScheme.secondary,
                background: theme.colorScheme.secondary.withValues(alpha: 0.2),
                isDark: isDark,
              ),
          ],
        ),
        // 社团｜声优 分节 + 分色胶囊（点选回列表筛选）
        if (circle.isNotEmpty || voices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '社团｜声优',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: isDark ? HikoColors.darkInk : HikoColors.lightInk,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (circle.isNotEmpty)
                _buildPersonPill(context, 'circle', circle, _circleColor),
              for (final name in voices)
                _buildPersonPill(context, 'voice', name, _voiceColor),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // 操作按钮行
        _buildActionButtons(album, theme, isDark),
      ],
    );
  }

  Widget _buildMetaPill(
    String text, {
    required Color color,
    required Color background,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// 社团/声优胶囊：点选后携带 ('circle'|'voice', 名字) 返回列表页应用筛选
  Widget _buildPersonPill(
    BuildContext context,
    String kind,
    String name,
    Color color,
  ) {
    return InkWell(
      onTap: () => Navigator.of(context).pop<(String, String)>((kind, name)),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(Album album, ThemeData theme, bool isDark) {
    return Row(
      children: [
        // 全部播放 - 点击后跳转到全屏播放页
        ElevatedButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact(); // 主操作按钮使用中等强度反馈
            // 从断点继续播放（如果有断点）
            final resumeIndex = album.resumeTrackIndex >= 0 ? album.resumeTrackIndex : 0;
            final resumePos = album.resumeTrackIndex >= 0 ? album.resumePosition : 0.0;
            ref.read(playbackProvider.notifier).playAlbum(
              album,
              index: resumeIndex,
              startPosition: resumePos,
            );
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
        const Spacer(),
        // 评分 - 扩大触摸目标到 48×48px
        IconButton(
          onPressed: () => _showRatingDialog(album),
          icon: Icon(
            album.rating > 0 ? Icons.star : Icons.star_border,
            size: 24,
            color: album.rating > 0
                ? Colors.amber
                : (isDark ? HikoColors.darkMuted : HikoColors.lightMuted),
          ),
          tooltip: '评分',
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
        // 分类 - 扩大触摸目标到 48×48px
        IconButton(
          onPressed: () => _showCategoryDialog(album),
          icon: Icon(
            Icons.label_outline,
            size: 24,
            color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
          ),
          tooltip: '分类',
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ],
    );
  }

  Widget _buildTabs(ThemeData theme, bool isDark, bool hasLyrics) {
    return Row(
      children: [
        _buildTab('曲目', 0, theme, isDark),
        const SizedBox(width: 16),
        if (hasLyrics) _buildTab('歌词', 1, theme, isDark),
      ],
    );
  }

  Widget _buildTab(String label, int index, ThemeData theme, bool isDark) {
    final isSelected = _selectedTabIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedTabIndex = index),
      borderRadius: BorderRadius.circular(20),
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

  Widget _buildTrackItem(
    Track track,
    int index,
    Album album,
    ThemeData theme,
    bool isDark,
    bool isCurrent,
    bool isPlaying,
  ) {
    // 获取播放器真实时长（如果当前曲目正在播放）
    final playbackState = ref.watch(playbackProvider);
    final isCurrentlyPlaying = isCurrent && playbackState.currentTrack?.url == track.url;
    final realDuration = isCurrentlyPlaying && playbackState.duration > 0
        ? playbackState.duration
        : track.duration;

    // 使用 RepaintBoundary 隔离每个列表项的重绘
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: isCurrent
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              HapticFeedback.selectionClick(); // 列表项选择使用轻量反馈

              // 断点续播：如果点击的是上次播放的断点曲目，从断点位置继续
              final isResumeTrack = (album.resumeTrackIndex == index);
              final startPos = isResumeTrack ? album.resumePosition : 0.0;

              ref.read(playbackProvider.notifier).playAlbum(
                album,
                index: index,
                startPosition: startPos,
              );

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
                  // 曲名 - 提升到 16px 可读标准
                  Expanded(
                    child: Text(
                      track.name,
                      style: TextStyle(
                        fontSize: 16,
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
                  // 时长 - 提升到 14px
                  Text(
                    formatTime(realDuration),
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? HikoColors.darkMuted : HikoColors.lightMuted,
                    ),
                  ),
                ],
              ),
            ),
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
