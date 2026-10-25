import 'package:flutter/material.dart';

import '../theme/m3e_theme.dart';
import '../tokens/shape_tokens.dart';

/// 导航计数徽标（rail / bar 共用）。
///
/// M3E 的 badge 有两种：小圆点（有无）与数字胶囊。这里只做数字胶囊，
/// 因为导航项上的计数是「有多少张专辑」，不是「有新内容」这种二值状态。
enum NavBadgeTone {
  /// 安静档：库内计数（多少张专辑）。用容器色，不抢注意力。
  muted,

  /// 提示档：真·未读/异常。用 error 色。
  alert,
}

class NavBadge extends StatelessWidget {
  const NavBadge({
    super.key,
    required this.count,
    this.maxCount = 99,
    this.tone = NavBadgeTone.muted,
  });

  final int count;
  final int maxCount;
  final NavBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final colors = M3ETheme.of(context).colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: tone == NavBadgeTone.alert
            ? colors.error
            : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(M3EShape.full),
      ),
      alignment: Alignment.center,
      child: Text(
        count > maxCount ? '$maxCount+' : '$count',
        style: TextStyle(
          fontSize: 10,
          height: 1,
          fontWeight: FontWeight.w600,
          color: tone == NavBadgeTone.alert
              ? colors.onError
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
