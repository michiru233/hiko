import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/library_provider.dart';
import '../../data/library_reorganizer.dart';
import '../../lyrics/lyrics_controller.dart';
import '../../models/album.dart';
import '../../playback/playback_controller.dart';
import '../../utils/rj.dart';
import '../../utils/person_names.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../lyrics/drawer_lyrics_view.dart';
import '../transitions/fullscreen_player_route.dart';
import '../theme.dart';
import 'category_dialog.dart';
import 'detail_kit.dart';
import 'rating_dialog.dart';
import 'toast.dart';

/// 详情抽屉：沉浸式玻璃拟态界面（背景大图虚化 + 拟态高光药丸按钮 + 晶透曲目项）
class DetailDrawer extends ConsumerStatefulWidget {
  const DetailDrawer({
    super.key,
    required this.album,
    required this.onClose,
    this.personFilterKind,
    this.personFilterName,
    this.onPersonFilter,
  });

  final Album album;
  final VoidCallback onClose;
  /// 1.81 当前生效的社团/声优筛选（用于胶囊选中态；kind: 'circle' | 'voice'）
  final String? personFilterKind;
  final String? personFilterName;
  /// 点胶囊回传筛选；传 (null, null) 表示清除（点已选中胶囊 = toggle 关）
  final void Function(String? kind, String? name)? onPersonFilter;

  @override
  ConsumerState<DetailDrawer> createState() => _DetailDrawerState();
}

class _DetailDrawerState extends ConsumerState<DetailDrawer> {
  int _selectedTabIndex = 0; // 0: 曲目列表, 1: 歌词字幕

  /// 1.81 社团/声优分色胶囊行：点选应用/切换筛选，点已选中胶囊取消（抽屉不关，列表同屏）。
  /// 视觉件本体在 detail_kit（与在线详情共用），此处只负责交互。
  Widget _buildPersonPills(Album album, ThemeData theme) {
    final circle = album.albumArtist.trim();
    final voices = splitVoiceNames(album.artist);
    if (circle.isEmpty && voices.isEmpty) return const SizedBox.shrink();
    Widget pill(String kind, String name, Color color) {
      final selected =
          widget.personFilterKind == kind && widget.personFilterName == name;
      return HikoPersonPill(
        name: name,
        color: color,
        selected: selected,
        onTap: () => widget.onPersonFilter
            ?.call(selected ? null : kind, selected ? null : name),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (circle.isNotEmpty) pill('circle', circle, hikoCircleColor),
          for (final name in voices) pill('voice', name, hikoVoiceColor),
        ],
      ),
    );
  }

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
        // 1.83 视觉统一：面板改主界面同款实底（原半透明玻璃 surface），层级靠边框+投影
        color: isDark ? HikoColors.darkBg : HikoColors.lightBg,
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
                  // 1.83 随实底化压暗：保留沉浸氛围但不与主界面争对比
                  opacity: isDark ? 0.10 : 0.07,
                  // RepaintBoundary（1.88.1）：σ55 里层还套着封面的 σ20。
                  // 它只随专辑变化，不该每次父级重绘都重算。
                  child: RepaintBoundary(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
                      child: AlbumCover(album: album),
                    ),
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
                    HikoEyebrowPill(
                      label:
                          '${album.genre.toUpperCase()} · ALBUM ${album.id.padLeft(2, '0')}',
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
                    ),
                    const SizedBox(height: 10),
                    Text(
                      album.title,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      // 1.87：此处为「多人一行」概览，不拆成多个胶囊，只归一化分隔符
                      '${normalizeVoiceSeparators(album.artist)} · ${album.rjCode ?? '本地导入'}',
                      style: TextStyle(fontSize: 12, color: theme.hintColor),
                    ),
                    // 1.81 社团（紫）/声优（蓝）胶囊：点选筛选主列表，抽屉保持打开
                    _buildPersonPills(album, theme),
                    const SizedBox(height: 20),
                    // 操作胶囊按钮
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: hikoFilledPillStyle(),
                          onPressed: () => ref.read(playbackProvider.notifier).playAlbum(album, index: 0),
                          icon: const Icon(Icons.play_arrow_rounded, size: 18),
                          label: const Text('从头播放', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        OutlinedButton.icon(
                          style: hikoOutlinedPillStyle(isDark: isDark),
                          onPressed: () async {
                            await ref
                                .read(libraryProvider.notifier)
                                .updateAlbum(album.id, (a) => a.copyWith(favorite: !a.favorite));
                          },
                          icon: Icon(
                            album.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            size: 15,
                            color: album.favorite ? hikoFavoriteColor : null,
                          ),
                          label: Text(album.favorite ? '已收藏' : '收藏', style: const TextStyle(fontSize: 11)),
                        ),
                        OutlinedButton.icon(
                          style: hikoOutlinedPillStyle(isDark: isDark),
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
                            color: album.rating > 0 ? hikoRatingColor : null,
                          ),
                          label: Text(
                            album.rating > 0 ? '${album.rating} 星' : '未评分',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: hikoOutlinedPillStyle(isDark: isDark),
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
                    HikoInfoRow(label: '总时长', value: '${album.tracks.length} 首${album.totalDuration > 0 ? ' · ${formatDuration(album.totalDuration)}' : ''}'),
                    HikoInfoRow(label: '完成进度', value: '$progress%'),
                    // DLsite 标签
                    if (album.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in album.tags) HikoTagChip(tag: t),
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
                    HikoSegmentedTabs(
                      left: HikoTabButton(
                        label: '曲目列表 (${album.tracks.length})',
                        icon: Icons.format_list_bulleted_rounded,
                        selected: _selectedTabIndex == 0,
                        onTap: () => setState(() => _selectedTabIndex = 0),
                      ),
                      right: HikoTabButton(
                        label: '歌词字幕',
                        icon: Icons.subtitles_rounded,
                        hasBadge: isCurrentAlbum && hasLyrics,
                        selected: _selectedTabIndex == 1,
                        onTap: () => setState(() => _selectedTabIndex = 1),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Tab 内容切换
                    if (_selectedTabIndex == 0) ...[
                      for (var i = 0; i < album.tracks.length; i++)
                        HikoTrackRow(
                          index: i + 1,
                          name: album.tracks[i].name,
                          durationSeconds: album.tracks[i].duration,
                          active: isCurrentAlbum && currentIndex == i,
                          playing: isCurrentAlbum && currentIndex == i && isPlaying,
                          onTap: () {
                            final controller = ref.read(playbackProvider.notifier);
                            if (isCurrentAlbum && currentIndex == i) {
                              // 1.79 点当前曲目不打断播放：播放中仅跳转；暂停中恢复播放再跳转
                              if (!isPlaying) controller.toggle();
                            } else {
                              controller.playAlbum(album, index: i);
                            }
                            // 1.79 桌面端点曲目后跳转全屏播放页（抽屉保留在底层）
                            Navigator.of(context).push(FullscreenPlayerRoute());
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
