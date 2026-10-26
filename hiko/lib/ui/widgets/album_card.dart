import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../utils/person_names.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';
import '../m3e/m3e.dart';

/// 专辑卡片（M3E 内容面，1.99.28）。
///
/// 材质从玻璃换成**色调面**：`surfaceContainerLow` 底、16dp 圆角、零投影。
/// 卡片与页面底（`surface`）的层级差由色阶给出，不再靠描边与模糊 —— 这也是
/// 深色模式下「卡片看不见」那个老问题的根治办法（见 plan §1.1）。
///
/// 圆角遵循嵌套规则：卡片 16 − 内边距 4 = 封面 12。
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.multiMode,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
    this.showScrapedTags = false,
    this.highlighted = false,
  });

  final Album album;
  final bool multiMode;
  final bool selected;
  final VoidCallback onTap;
  final void Function(Offset position)? onContextMenu;
  final bool showScrapedTags;
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    Offset? pointerPosition;

    return Listener(
      onPointerDown: (event) => pointerPosition = event.position,
      child: M3ECard(
        padding: const EdgeInsets.all(4),
        radius: M3EShape.lg,
        // 定位命中用 primaryContainer 底；多选选中用 secondaryContainer。
        color: highlighted
            ? colors.primaryContainer
            : selected
                ? colors.secondaryContainer
                : null,
        onTap: onTap,
        onLongPress: onContextMenu == null
            ? null
            : () => onContextMenu!(pointerPosition ?? Offset.zero),
        onSecondaryTapDown: onContextMenu,
        semanticLabel: album.title,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                // 英雄时刻 A 的起点（1.99.29）：与移动详情页封面同 tag 链式形变。
                // 前缀 card- 与播放条（bar-）/详情抽屉（drawer-）隔离，避免
                // 同路由多 Hero 断言；飞行用默认规则（目标子树从来源位置飞入）。
                Hero(
                  tag: 'card-${album.id}',
                  child: ClipRRect(
                    // 16 − 4 = 12
                    borderRadius: M3EShape.radius(M3EShape.md),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: AlbumCover(album: album),
                    ),
                  ),
                ),
                if (multiMode)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _SelectBadge(selected: selected),
                  ),
                if (highlighted)
                  Positioned.fill(
                    child: IgnorePointer(
                      // 定位高亮专用 key：测试用它判定「这张卡正在发光」，
                      // 与具体材质解耦（玻璃 → 色调面换过一次，锁不该跟着改）。
                      key: const ValueKey<String>('hiko-album-card-highlight'),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: M3EShape.radius(M3EShape.md),
                          border: Border.all(
                            color: colors.primary,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    album.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: (selected
                            ? theme.type.titleSmallEmphasized
                            : theme.type.titleSmall)
                        .copyWith(color: colors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  // 声优/社团分色胶囊（1.44 语义的复刻，1.99.36 用户反馈恢复）：
                  // 逐人拆分、各一颗独立胶囊；长名在胶囊内换行不溢出。
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final voice
                          in splitVoiceNames(
                              normalizeVoiceSeparators(album.artist)))
                        _PersonPillMini(
                            name: voice, color: M3ESemantic.voiceTint),
                      if (_showCirclePill)
                        _PersonPillMini(
                            name: album.albumArtist,
                            color: M3ESemantic.circleTint),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      _MetaPill(
                        text: album.rjCode ?? '本地导入',
                        background: colors.primaryContainer,
                        foreground: colors.onPrimaryContainer,
                        emphasized: true,
                      ),
                      _MetaPill(
                        text: album.totalDuration > 0
                            ? formatDuration(album.totalDuration)
                            : '${album.duration} 首',
                        background: colors.surfaceContainerHigh,
                        foreground: colors.onSurfaceVariant,
                      ),
                      if (album.genre.isNotEmpty)
                        _MetaPill(
                          text: album.genre,
                          background: colors.surfaceContainerHigh,
                          foreground: colors.onSurfaceVariant,
                        ),
                      if (showScrapedTags)
                        for (final tag in album.tags.take(3))
                          _MetaPill(
                            text: tag,
                            background: M3ESemantic.tagBackground
                                .withValues(alpha: colors.isDark ? 0.28 : 0.9),
                            foreground: M3ESemantic.tagForeground(colors.isDark),
                          ),
                      if (showScrapedTags && album.tags.length > 3)
                        _MetaPill(
                          text: '+${album.tags.length - 3}',
                          background: M3ESemantic.tagBackground
                              .withValues(alpha: colors.isDark ? 0.28 : 0.9),
                          foreground: M3ESemantic.tagForeground(colors.isDark),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 社团胶囊是否展示：为空或与声优串相同时不重复占位（沿用 1.44 去重语义）。
  bool get _showCirclePill {
    final circle = album.albumArtist;
    if (circle.isEmpty) return false;
    return circle != album.artist;
  }
}

/// 多选角标：M3E 的选中语义是「圆形勾选」，不是自绘对勾字符。
class _SelectBadge extends StatelessWidget {
  const _SelectBadge({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return AnimatedContainer(
      duration: M3ETheme.of(context).motion.stateLayerDuration,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.primary : colors.scrim.withValues(alpha: 0.45),
        border: Border.all(color: colors.surface, width: 2),
      ),
      child: selected
          ? Icon(Icons.check, size: 14, color: colors.onPrimary)
          : null,
    );
  }
}

/// 元数据小标签：4dp 圆角（芯片语言），labelSmall 字号。
class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.text,
    required this.background,
    required this.foreground,
    this.emphasized = false,
  });

  final String text;
  final Color background;
  final Color foreground;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final type = M3ETheme.of(context).type;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: M3EShape.radius(M3EShape.xs),
      ),
      child: Text(
        text,
        softWrap: true,
        style: (emphasized
                ? type.labelSmall.copyWith(fontWeight: FontWeight.w700)
                : type.labelSmall)
            .copyWith(color: foreground),
      ),
    );
  }
}

/// 卡片级迷你人名胶囊：声优（蓝）/ 社团（紫）分色，文字超长在胶囊内换行。
class _PersonPillMini extends StatelessWidget {
  const _PersonPillMini({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: M3EShape.radius(M3EShape.full),
      ),
      child: Text(
        name,
        softWrap: true,
        style: M3ETheme.of(context).type.labelSmall.copyWith(
          fontWeight: FontWeight.w500,
          height: 1.25,
          color: color,
        ),
      ),
    );
  }
}
