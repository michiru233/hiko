import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/album.dart';
import '../../utils/time.dart';
import '../covers/cover_art.dart';

/// 专辑卡片（对应旧版 .album-card）：封面 + 悬停操作 + 标题/艺人 + 标签
class AlbumCard extends ConsumerWidget {
  const AlbumCard({
    super.key,
    required this.album,
    required this.multiMode,
    required this.selected,
    required this.onTap,
    required this.onContextMenu,
    this.showScrapedTags = false,
  });

  final Album album;
  final bool multiMode;
  final bool selected;
  final VoidCallback onTap;

  /// 右键（桌面）/长按（移动）菜单回调，携带触发位置
  final void Function(Offset position)? onContextMenu;

  /// 1.43：是否显示 DLsite 刮削标签（由 home_screen 从设置传入，默认关；
  /// 卡片不直接读 ProviderScope，保持可独立构造——widget_test 无 ProviderScope）
  final bool showScrapedTags;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // 桌面端悬停显示点击指针；Ink 水波纹按压反馈（圆角对齐封面）。
    // 长按/右键菜单位置用 Listener 原始指针记录（InkWell 无 onLongPressStart），
    // Listener 不参与手势竞技场，不影响水波纹。
    Offset? pointerPosition;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Listener(
        onPointerDown: (e) {
          pointerPosition = e.position;
          if (onContextMenu != null && e.buttons == kSecondaryButton) {
            onContextMenu!(e.position);
          }
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onContextMenu == null
                ? null
                : () => onContextMenu!(pointerPosition ?? Offset.zero),
            borderRadius: BorderRadius.circular(10),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面 + 多选勾选（固定正方形，占卡片上部）
            LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: AlbumCover(album: album),
                      ),
                    ),
                    if (multiMode)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: onTap,
                              customBorder: const CircleBorder(),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: selected
                                      ? theme.colorScheme.primary
                                      : Colors.black.withValues(alpha: 0.4),
                                  border: Border.all(
                                      color: Colors.white.withValues(alpha: 0.85),
                                      width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    selected ? '✓' : '',
                                    style: TextStyle(
                                      color: selected
                                          ? theme.colorScheme.onPrimary
                                          : Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (selected)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: theme.colorScheme.primary, width: 2),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            // 信息区：占封面下方剩余空间（高度由网格宽高比决定，杜绝溢出）。
            // 1.42.0：五项信息（专辑名/艺术家/专辑艺术家/RJ号/总时长）放大提级——
            // 标题 13 w700；艺术家行 11px 前景色；RJ号实底胶囊 + 总时长胶囊。
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    // 1.44：artist/albumArtist 胶囊化（与总时长同款次级色），
                    // 去重逻辑不变：albumArtist 为空或与 artist 相同时只显示 artist
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _Pill(
                          text: album.artist,
                          bg: theme.colorScheme.secondaryContainer,
                          color: theme.colorScheme.onSecondaryContainer,
                          maxWidth: 178,
                        ),
                        if (album.albumArtist.isNotEmpty &&
                            album.albumArtist != album.artist)
                          _Pill(
                            text: album.albumArtist,
                            bg: theme.colorScheme.secondaryContainer,
                            color: theme.colorScheme.onSecondaryContainer,
                            maxWidth: 178,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        _Pill(
                          text: album.rjCode ?? '本地导入',
                          bg: theme.colorScheme.primary,
                          color: theme.colorScheme.onPrimary,
                          bold: true,
                        ),
                        _Pill(
                          text: album.totalDuration > 0
                              ? formatDuration(album.totalDuration)
                              : '${album.duration} 首',
                          bg: theme.colorScheme.secondaryContainer,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                        _Tag(text: album.genre),
                      ],
                    ),
                    if (showScrapedTags && album.tags.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 4,
                        children: [
                          for (final t in album.tags.take(3))
                            _Tag(
                              text: t,
                              color: const Color(0xFF2E8A8F),
                              bg: const Color(0xFFE3F4F2),
                            ),
                          if (album.tags.length > 3)
                            _Tag(
                              text: '+${album.tags.length - 3}',
                              color: const Color(0xFF2E8A8F),
                              bg: const Color(0xFFD7ECEA),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        ),
        ),
      ),
    );
  }
}

/// 高亮胶囊（1.42.0）：RJ号/总时长等关键信息，10px 加粗、实底高对比。
/// 1.44.0：文字 maxLines 1 + ellipsis，可选 [maxWidth] 约束（超长艺术家名
/// 在无界 Wrap 内会横向溢出，必须限宽截断）。
class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.bg,
    required this.color,
    this.bold = false,
    this.maxWidth,
  });

  final String text;
  final Color bg;
  final Color color;
  final bool bold;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    Widget pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
            fontSize: 10,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color),
      ),
    );
    if (maxWidth != null) {
      pill = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: pill,
      );
    }
    return pill;
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, this.color, this.bg});

  final String text;
  final Color? color;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg ?? theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color ?? theme.hintColor),
      ),
    );
  }
}
