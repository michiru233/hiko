/// 详情页共用件（本地专辑详情抽屉 ↔ 在线作品详情面板）。
///
/// 1.91.0 抽出：两处详情页要求视觉完全一致，复制一份必然漂移，
/// 所以把颜色、间距、圆角、字号这些常量收在这里，两边都从这里取。
/// 数值全部照搬 1.83–1.90 的 `detail_drawer.dart`，未做任何视觉调整。
library;

import 'package:flutter/material.dart';

import '../../utils/time.dart';
import '../theme.dart';

// ------------------------------------------------------------------ 调色板

/// 社团胶囊紫（1.77 起沿用）
const Color hikoCircleColor = Color(0xFFB39DDB);

/// 声优胶囊蓝
const Color hikoVoiceColor = Color(0xFF90CAF9);

/// DLsite 标签底色 / 字色
const Color hikoTagBgColor = Color(0xFFE3F4F2);
const Color hikoTagFgColor = Color(0xFF2E8A8F);

/// 收藏红 / 评分金（详情页操作胶囊用）
const Color hikoFavoriteColor = Color(0xFFD34C44);
const Color hikoRatingColor = Color(0xFFE8B33C);

// ------------------------------------------------------------------ 样式件

/// 详情页里的描边胶囊按钮（收藏 / 评分 / 整理专辑 / 在浏览器打开…）
ButtonStyle hikoOutlinedPillStyle({
  required bool isDark,
  EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
}) =>
    OutlinedButton.styleFrom(
      padding: padding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      side: BorderSide(
        color: isDark ? HikoColors.darkGlassBorder : HikoColors.lightGlassBorderSubtle,
      ),
      backgroundColor: isDark
          ? Colors.white.withValues(alpha: 0.05)
          : Colors.black.withValues(alpha: 0.03),
    );

/// 详情页里的实心胶囊按钮（从头播放 / 播放全部）
ButtonStyle hikoFilledPillStyle() => FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      elevation: 0,
    );

/// 详情页顶部「眼眉」胶囊（本地：分类 · ALBUM 01；在线：来源 · RJ 号）。
/// [onTap] 为空时去掉下拉箭头，表示纯标识不可交互。
class HikoEyebrowPill extends StatelessWidget {
  const HikoEyebrowPill({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = Container(
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
            label,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: theme.colorScheme.primary),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: pill,
    );
  }
}

/// 社团（紫）/ 声优（蓝）分色胶囊。[onTap] 为空即纯展示。
class HikoPersonPill extends StatelessWidget {
  const HikoPersonPill({
    super.key,
    required this.name,
    required this.color,
    this.selected = false,
    this.onTap,
  });

  final String name;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: selected ? 0.32 : 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withValues(alpha: selected ? 0.7 : 0.4),
        ),
      ),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: color,
        ),
      ),
    );
    if (onTap == null) return pill;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: pill,
    );
  }
}

/// DLsite 标签胶囊（青色小方角）
class HikoTagChip extends StatelessWidget {
  const HikoTagChip({super.key, required this.tag, this.onTap});

  final String tag;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: hikoTagBgColor.withValues(alpha: isDark ? 0.2 : 0.8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tag,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          color: hikoTagFgColor,
        ),
      ),
    );
    if (onTap == null) return chip;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: chip,
    );
  }
}

/// 详情页信息行（上方一条分隔线，两端对齐）
class HikoInfoRow extends StatelessWidget {
  const HikoInfoRow({super.key, required this.label, required this.value});

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
          Text(value,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

/// 胶囊分段开关里的单个 Tab
class HikoTabButton extends StatelessWidget {
  const HikoTabButton({
    super.key,
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

/// 双 Tab 分段开关外壳（曲目列表 / 歌词字幕）
class HikoSegmentedTabs extends StatelessWidget {
  const HikoSegmentedTabs({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? HikoColors.darkGlassBorderSubtle
              : HikoColors.lightGlassBorderSubtle,
        ),
      ),
      child: Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 4),
          Expanded(child: right),
        ],
      ),
    );
  }
}

/// 详情页曲目行：圆形播放/暂停键 + 两位序号 + 标题 + 时长。
///
/// 本地与在线共用同一套视觉（1.91.0 抽出）。[indent] 供在线按目录层级缩进，
/// 本地传 0。[name] 由调用方映射（本地 `Track.name`、在线剥掉扩展名的标题）。
class HikoTrackRow extends StatelessWidget {
  const HikoTrackRow({
    super.key,
    required this.index,
    required this.name,
    required this.durationSeconds,
    required this.active,
    required this.playing,
    required this.onTap,
    this.indent = 0.0,
    this.trailing,
  });

  /// 展示用序号（1 起）。在线按「所在目录内」编号，本地按专辑内编号
  final int index;
  final String name;
  final double durationSeconds;
  final bool active;
  final bool playing;
  final VoidCallback onTap;
  final double indent;

  /// 右侧时长左边额外的角标（在线用来放字幕图标）
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = active ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: InkWell(
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
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.05)),
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
                  index.toString().padLeft(2, '0'),
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
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              ?trailing,
              Text(
                durationSeconds > 0 ? formatTime(durationSeconds) : '--:--',
                style: TextStyle(
                  fontSize: 10,
                  color: active ? theme.colorScheme.primary : theme.hintColor,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
