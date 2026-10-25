import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';
import '../../models/album.dart';
import '../../models/track.dart';
import '../../playback/playback_controller.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../utils/person_names.dart';
import '../../utils/rj.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../lyrics/drawer_lyrics_view.dart';
import '../m3e/m3e.dart';
import '../widgets/category_dialog.dart';
import '../widgets/detail_kit.dart';
import '../widgets/rating_dialog.dart';
import '../widgets/toast.dart';
import '../transitions/fullscreen_player_route.dart';

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

  /// 声优串拆分：走共享实现，与桌面详情抽屉同源（1.87 删掉本地重复正则）
  List<String> _voiceNames(Album album) => splitVoiceNames(album.artist);

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
          // 全宽封面（1:1），延伸到顶栏背后；Hero tag 与卡片封面一致
          //（链式形变：卡片 16 → 详情 28 → 播放页 28，1.99.29）
          SliverToBoxAdapter(
            child: AspectRatio(
              aspectRatio: 1,
              child: Hero(
                tag: 'card-${album.id}',
                child: AlbumCover(album: album, fit: BoxFit.cover),
              ),
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
              child: _buildTabs(hasLyrics),
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

  /// 1.99.34 M3E 换装（plan-hiko-detail-m3e.md §4）：眉题 chip（分类切换，
  /// 内部 id 不再展示）+ headlineSmallEmphasized 标题 + 元数据行 +
  /// 分色胶囊（点选回列表筛选）+ 主键/次键操作行 + 完成进度分组卡。
  Widget _buildHeader(
    Album album,
    ThemeData theme,
    bool isDark,
    String? rj,
    int progress,
  ) {
    final circle = album.albumArtist.trim();
    final voices = _voiceNames(album);
    final type = M3ETheme.of(context).type;
    final colors = M3ETheme.of(context).colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HikoEyebrowPill(
          label: album.genre.isEmpty ? '未分类' : album.genre,
          onTap: () => _showCategoryDialog(album),
        ),
        const SizedBox(height: 12),
        Text(
          album.title,
          style: type.headlineSmallEmphasized.copyWith(height: 1.3),
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (album.artist.isNotEmpty) album.artist,
            if (rj != null) rj,
            if (album.totalDuration > 0) formatDuration(album.totalDuration),
          ].join(' · '),
          style: type.labelMedium.copyWith(color: colors.onSurfaceVariant),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        // 社团｜声优 分色胶囊（点选回列表筛选，1.77 链路不变）
        if (circle.isNotEmpty || voices.isNotEmpty) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (circle.isNotEmpty)
                HikoPersonPill(
                  name: circle,
                  color: _circleColor,
                  onTap: () => Navigator.of(context)
                      .pop<(String, String)> (('circle', circle)),
                ),
              for (final name in voices)
                HikoPersonPill(
                  name: name,
                  color: _voiceColor,
                  onTap: () => Navigator.of(context)
                      .pop<(String, String)> (('voice', name)),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        // 操作区（D2）：一个 filled 主键 + outlined 次键
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            M3EButton(
              variant: M3EButtonVariant.filled,
              label: '从头播放',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () {
                HapticFeedback.mediumImpact();
                // 从断点继续播放（如果有断点）
                final resumeIndex =
                    album.resumeTrackIndex >= 0 ? album.resumeTrackIndex : 0;
                final resumePos = album.resumeTrackIndex >= 0
                    ? album.resumePosition
                    : 0.0;
                ref.read(playbackProvider.notifier).playAlbum(
                      album,
                      index: resumeIndex,
                      startPosition: resumePos,
                    );
                // 自动跳转到全屏播放页（从详情封面形变进入，英雄时刻 A 第二跳）
                Navigator.of(context)
                    .push(FullscreenPlayerRoute(heroTag: 'card-${album.id}'));
              },
            ),
            M3EButton(
              variant: M3EButtonVariant.outlined,
              label: album.rating > 0 ? '${album.rating} 星' : '未评分',
              icon: Icon(
                album.rating > 0
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
              ),
              onPressed: () => _showRatingDialog(album),
            ),
            M3EButton(
              variant: M3EButtonVariant.outlined,
              label: album.genre.isEmpty ? '未分类' : album.genre,
              icon: const Icon(Icons.label_outline),
              onPressed: () => _showCategoryDialog(album),
            ),
          ],
        ),
        // 完成进度分组卡（§4.4）
        if (album.totalDuration > 0) ...[
          const SizedBox(height: 16),
          M3ECard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: HikoDetailInfoRowM3E(
              label: '完成进度',
              value: '$progress%',
              progress: album.played / album.totalDuration,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTabs(bool hasLyrics) {
    // M3EButtonGroup：歌词 tab 仅在有歌词时出现（与旧交互一致）
    final labels = hasLyrics ? const ['曲目', '歌词'] : const ['曲目'];
    return M3EButtonGroup(
      labels: labels,
      selectedIndex: _selectedTabIndex.clamp(0, labels.length - 1),
      onSelected: (index) => setState(() => _selectedTabIndex = index),
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
    final isCurrentlyPlaying =
        isCurrent && playbackState.currentTrack?.url == track.url;
    final realDuration = isCurrentlyPlaying && playbackState.duration > 0
        ? playbackState.duration
        : track.duration;

    // RepaintBoundary 隔离每个列表项的重绘；行本体为 M3E 版（1.99.34）
    return RepaintBoundary(
      child: HikoTrackRowM3E(
        index: index + 1,
        name: track.name,
        durationSeconds: realDuration,
        active: isCurrent,
        playing: isCurrent && isPlaying,
        onTap: () {
          HapticFeedback.selectionClick();

          // 断点续播：如果点击的是上次播放的断点曲目，从断点位置继续
          final isResumeTrack = (album.resumeTrackIndex == index);
          final startPos = isResumeTrack ? album.resumePosition : 0.0;

          ref.read(playbackProvider.notifier).playAlbum(
                album,
                index: index,
                startPosition: startPos,
              );

          // 点击曲目后自动跳转到全屏播放页（封面形变，同上）
          Navigator.of(context)
              .push(FullscreenPlayerRoute(heroTag: 'card-${album.id}'));
        },
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
