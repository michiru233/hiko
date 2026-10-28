import 'package:flutter/material.dart';

import '../../theme/m3e_theme.dart';
import '../../tokens/shape_tokens.dart';

/// M3E 线性进度条（plan §8.8）：圆角全档、无阴影、单一指示色。
///
/// 建这个组件的原因是**进度条曾有三套**：在线换页用 Material
/// `LinearProgressIndicator`（2dp、默认蓝、无轨道），详情与播放条另写轨道色，
/// 下载中心干脆自绘 `Stack + FractionallySizedBox`（1.99.57 审计 P0-2）。
/// 三套的共同点是「都长得像进度条」，不同点是圆角、轨道色、指示色各一份。
///
/// 两种形态：
/// - 默认：4dp **带轨道**，用于「已完成多少」的可读进度（详情完成度、下载进度）；
/// - [M3EProgress.thin]：2dp **无轨道**，用于「正在换页 / 正在同步」这类
///   一闪而过的活动条 —— 无轨道是因为它只表达「有事在发生」，画底色反而
///   像一条常驻分隔线。
///
/// 内部仍用 Material 的 `LinearProgressIndicator` 承载不定量动画（与
/// `M3ESlider` 内包 `Slider` 同一条约定）：不定量态的分段滑动曲线是 M3 的
/// 规范动画，自绘一遍只会得到「看起来像但不同步」的第二套。
class M3EProgress extends StatelessWidget {
  const M3EProgress({
    super.key,
    this.value,
    this.height = 4,
    this.color,
    this.trackColor,
    this.semanticLabel,
  }) : _showTrack = true;

  /// 2dp 活动细条：无轨道，`value` 通常留空（不定量）。
  const M3EProgress.thin({
    super.key,
    this.value,
    this.color,
    this.semanticLabel,
  })  : height = 2,
        trackColor = null,
        _showTrack = false;

  /// 0~1；null = 不定量（分段滑动）。
  final double? value;

  /// 条高。默认 4，[M3EProgress.thin] 固定 2。
  final double height;

  /// 指示色，默认 `primary`。
  final Color? color;

  /// 轨道色，默认 `surfaceContainerHighest`；`thin` 形态忽略。
  final Color? trackColor;

  final String? semanticLabel;

  final bool _showTrack;

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    // NaN 会一路穿过 `clamp`（比较全为 false）并在 Canvas 里画出 NaN 宽度 ——
    // 下载进度由 `received / total` 计算，total 未就绪时就是 0/0。视为 0。
    final raw = value;
    final v = raw == null
        ? null
        : (raw.isNaN ? 0.0 : raw.clamp(0.0, 1.0));
    final track = _showTrack
        ? (trackColor ?? colors.surfaceContainerHighest)
        : Colors.transparent;
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: M3EShape.radius(M3EShape.full),
        child: LinearProgressIndicator(
          value: v,
          minHeight: height,
          backgroundColor: track,
          valueColor: AlwaysStoppedAnimation<Color>(color ?? colors.primary),
          semanticsLabel: semanticLabel,
        ),
      ),
    );
  }
}
