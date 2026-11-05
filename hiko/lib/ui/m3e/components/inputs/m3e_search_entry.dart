import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';
import '../motion/m3e_pressable.dart';
import 'm3e_search_surface.dart';

/// 搜索入口（折叠态）：长得像 [M3ESearchBar]，但**整条都可点**，且不含 `TextField`。
///
/// 为什么需要它（1.99.70）：`M3ESearchBar` 只有内部的 `Expanded(TextField)` 能点，
/// 容器、放大镜、左右 8dp 留白全是死区；在线页在 360dp × 1.3 字号下搜索框只剩
/// 约 67dp 宽，真正可点区域约 23×26dp，用户反馈「很难点到」。
///
/// 这里把整条包进 [M3EPressable]，点开后再由调用方弹出一个放大的输入浮层。
/// 顺带解决了移动端「真身 + Offstage 量高副本共用同一个 FocusNode」的隐患 ——
/// 折叠态没有 `EditableText`，两份 header 都只是纯展示。
class M3ESearchEntry extends StatelessWidget {
  const M3ESearchEntry({
    super.key,
    this.text = '',
    this.hintText = '搜索',
    this.onTap,
    this.height = 48,
    this.semanticLabel,
    this.surfaceOpacity = 1,
  });

  /// 已填内容（有值时用 `onSurface`，空时显示 [hintText]）。
  final String text;

  final String hintText;

  final VoidCallback? onTap;

  final double height;

  /// 窄到只剩放大镜时，这是唯一的可读信息（无障碍必填）。
  final String? semanticLabel;

  /// 用户可调的搜索面不透明度（1.99.71）：只调填充与阴影，不做模糊。
  final double surfaceOpacity;

  /// 可用宽度小于它时只画放大镜：再挤下去提示文字只会剩半个字，更像坏掉。
  static const double minTextWidth = 96;

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final colors = theme.colors;
    final hasText = text.isNotEmpty;
    final enabled = onTap != null;

    return M3EPressable(
      onTap: onTap,
      enabled: enabled,
      borderRadius: BorderRadius.circular(M3EShape.full),
      pressScale: 0.98,
      semanticLabel: semanticLabel ?? (hasText ? '搜索：$text' : hintText),
      child: M3ESearchSurface(
        height: height,
        surfaceOpacity: surfaceOpacity,
        enabled: enabled,
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < minTextWidth) {
              return const SizedBox.shrink();
            }
            return Text(
              hasText ? text : hintText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.type.bodyLarge.copyWith(
                color: !enabled
                    ? colors.onSurface.withValues(alpha: 0.38)
                    : hasText
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
              ),
            );
          },
        ),
      ),
    );
  }
}
