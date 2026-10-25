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
import '../m3e/m3e.dart';
import '../transitions/fullscreen_player_route.dart';
import 'category_dialog.dart';
import 'detail_kit.dart';
import 'rating_dialog.dart';
import 'toast.dart';

/// 专辑详情面板（1.99.29 M3ESheet 化，plan §8.4）：不透明色调面，
/// 无氛围光晕；封面挂 drawer- 前缀 Hero tag（点曲目进播放页时从封面形变）。
class DetailDrawer extends ConsumerStatefulWidget {
  const DetailDrawer({
    super.key,
    required this.album,
    required this.onClose,
    this.sheetVariant = M3ESheetVariant.side,
    this.personFilterKind,
    this.personFilterName,
    this.onPersonFilter,
  });

  final Album album;
  final VoidCallback onClose;

  /// 面板形态：桌面侧滑（默认）/ 移动底部（28dp 顶角）。
  final M3ESheetVariant sheetVariant;
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

    return M3ESheet(
      variant: widget.sheetVariant,
      child: Stack(
        children: [
          Positioned.fill(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 两栏头部（D3）：封面 160 角 28 + 右侧标题列
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Hero(
                          tag: 'drawer-${album.id}',
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(M3EShape.xl),
                            child: SizedBox(
                              width: 160,
                              height: 160,
                              child: AlbumCover(album: album),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              HikoEyebrowPill(
                                label: album.genre,
                                onTap: () async {
                                  final chosen = await showSelectCategoryDialog(
                                    context,
                                    currentGenre: album.genre,
                                    albumCount: 1,
                                  );
                                  if (chosen != null && chosen != album.genre) {
                                    await ref
                                        .read(libraryProvider.notifier)
                                        .updateAlbum(album.id,
                                            (a) => a.copyWith(genre: chosen));
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              Text(
                                album.title,
                                style: M3ETheme.of(context)
                                    .type
                                    .titleLargeEmphasized
                                    .copyWith(height: 1.25),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${normalizeVoiceSeparators(album.artist)} · ${album.rjCode ?? '本地导入'}',
                                style: M3ETheme.of(context).type.labelMedium
                                    .copyWith(color: theme.hintColor),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // 社团（紫）/ 声优（蓝）分色胶囊：点选筛选主列表
                    _buildPersonPills(album, theme),
                    const SizedBox(height: 20),
                    // 操作区（D2）：一个 filled 主键 + 三个 outlined 次键
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        M3EButton(
                          variant: M3EButtonVariant.filled,
                          label: '从头播放',
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: () => ref
                              .read(playbackProvider.notifier)
                              .playAlbum(album, index: 0),
                        ),
                        M3EButton(
                          variant: M3EButtonVariant.outlined,
                          label: album.favorite ? '已收藏' : '收藏',
                          icon: Icon(
                            album.favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                          onPressed: () async {
                            await ref
                                .read(libraryProvider.notifier)
                                .updateAlbum(album.id,
                                    (a) => a.copyWith(favorite: !a.favorite));
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
                          onPressed: () async {
                            final rating = await showRatingDialog(
                              context,
                              initialRating: album.rating,
                            );
                            if (rating == null || !context.mounted) return;
                            await ref
                                .read(libraryProvider.notifier)
                                .updateAlbum(album.id,
                                    (a) => a.copyWith(rating: rating));
                          },
                        ),
                        M3EButton(
                          variant: M3EButtonVariant.outlined,
                          label: '整理',
                          icon: const Icon(Icons.refresh_rounded),
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 信息分组卡（§4.4）
                    M3ECard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          HikoDetailInfoRowM3E(
                            label: '总时长',
                            value:
                                '${album.tracks.length} 首 · ${album.totalDuration > 0 ? formatDuration(album.totalDuration) : '--'}',
                          ),
                          HikoDetailInfoRowM3E(
                            label: '完成进度',
                            value: '$progress%',
                            progress: album.totalDuration > 0
                                ? album.played / album.totalDuration
                                : null,
                          ),
                          HikoDetailInfoRowM3E(
                            label: '评分',
                            value: album.rating > 0 ? '★' * album.rating : '未评分',
                          ),
                          if (rj != null)
                            HikoDetailInfoRowM3E(
                              label: 'DLsite',
                              value: rj,
                            ),
                        ],
                      ),
                    ),
                    // DLsite 标签（点选 = 回列表筛选，现行为）
                    if (album.tags.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in album.tags) HikoTagChip(tag: t),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    // 曲目 / 歌词 分段（M3EButtonGroup 连通式）
                    M3EButtonGroup(
                      labels: [
                        '曲目列表 (${album.tracks.length})',
                        hasLyrics ? '歌词字幕 ●' : '歌词字幕',
                      ],
                      selectedIndex: _selectedTabIndex,
                      onSelected: (index) =>
                          setState(() => _selectedTabIndex = index),
                    ),
                    const SizedBox(height: 14),
                    if (_selectedTabIndex == 0) ...[
                      for (var i = 0; i < album.tracks.length; i++)
                        HikoTrackRowM3E(
                          index: i + 1,
                          name: album.tracks[i].name,
                          durationSeconds: album.tracks[i].duration,
                          active: isCurrentAlbum && currentIndex == i,
                          playing: isCurrentAlbum &&
                              currentIndex == i &&
                              isPlaying,
                          onTap: () {
                            final controller =
                                ref.read(playbackProvider.notifier);
                            if (isCurrentAlbum && currentIndex == i) {
                              // 1.79 点当前曲目不打断播放：播放中仅跳转；暂停中恢复播放再跳转
                              if (!isPlaying) controller.toggle();
                            } else {
                              controller.playAlbum(album, index: i);
                            }
                            // 桌面端点曲目后跳转全屏播放页（面板保留在底层）
                            // 1.99.29：从面板封面形变进入
                            Navigator.of(context).push(
                              FullscreenPlayerRoute(
                                heroTag: 'drawer-${album.id}',
                              ),
                            );
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
          // 关闭按钮（M3E 色调圆钮）
          Positioned(
            right: 14,
            top: 14,
            child: Material(
              color: M3ETheme.of(context).colors.surfaceContainerHighest,
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
