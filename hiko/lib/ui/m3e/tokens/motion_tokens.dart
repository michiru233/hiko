import 'package:flutter/widgets.dart';

/// 弹簧类型。
///
/// - [spatial]：会位移 / 缩放 / 改圆角的动效，**阻尼 < 1 时允许回弹**
/// - [effects]：只改颜色与透明度，**阻尼恒 1.0，绝不回弹**（回弹的颜色像故障）
enum M3ESpringType { spatial, effects }

/// 弹簧速度档。
enum M3ESpringSpeed { fast, normal, slow }

/// 动效方案。
///
/// - [expressive]：M3E 默认，spatial 阻尼 0.6~0.8，有明显回弹
/// - [standard]：克制版，spatial 阻尼 0.9，几乎不回弹
///
/// effects 两套方案完全相同（都是 1.0），这是规范刻意为之：表达力全部放在 spatial。
enum M3ESpringScheme { expressive, standard }

/// 动效开关三档（对应设置里的「动效：完整 / 减弱 / 关闭」）。
enum M3EMotionLevel {
  /// 完整：弹簧按 token 原值
  full,

  /// 减弱：位移/时长减半，弹簧降级为缓动曲线
  reduced,

  /// 关闭：直接到终态，不创建动画控制器（性能与晕动症双保险）
  off,
}

/// M3E 动效 token。
///
/// 数值来源：`ExpressiveMotionTokens.kt` / `StandardMotionTokens.kt`（0_14_0）。
/// token 里的 `damping` 就是**阻尼比**，可直接喂给
/// [SpringDescription.withDampingRatio] 的 `ratio`，不需要换算。
///
/// 性能约束（写进 plan-hiko-m3e-redesign.md §7.2，实现时不得绕过）：
/// 弹簧只跟离散交互走（按压、选中、展开、切页），**滚动驱动的一切禁止用弹簧**。
@immutable
class M3EMotion {
  const M3EMotion({
    this.scheme = M3ESpringScheme.expressive,
    this.level = M3EMotionLevel.full,
  });

  final M3ESpringScheme scheme;
  final M3EMotionLevel level;

  /// 是否产生动画。关闭时调用方应直接返回终态。
  bool get enabled => level != M3EMotionLevel.off;

  /// 时长系数：完整 1.0 / 减弱 0.5 / 关闭 0。
  double get durationScale => switch (level) {
        M3EMotionLevel.full => 1,
        M3EMotionLevel.reduced => 0.5,
        M3EMotionLevel.off => 0,
      };

  /// 弹簧降级用的缓动曲线（减弱档使用）。
  Curve get fallbackCurve => Curves.easeOutCubic;

  /// 状态层（hover / focus / press 的叠色）过渡时长。
  ///
  /// M3 用 effects spring 表达，但叠色是最频繁的一类过渡（每次指针移动都会触发），
  /// 逐帧跑弹簧模拟在这里没有收益，反而放大 CPU。用 100ms 线性近似，
  /// 与 200ms effects spring 的观感差异在 8% 以内。
  Duration get stateLayerDuration =>
      Duration(milliseconds: (100 * durationScale).round());

  /// 取一个弹簧描述。
  ///
  /// 减弱档不做「更软的弹簧」，而是把刚度调高、阻尼拉到接近临界 —— 位移更小更快，
  /// 对晕动症用户更安全；关闭档返回的弹簧仅供调用方兜底，不应被使用。
  SpringDescription spring(M3ESpringType type, M3ESpringSpeed speed) {
    final (stiffness, damping) = _spec(type, speed);
    if (level == M3EMotionLevel.reduced) {
      return SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: stiffness * 2,
        ratio: 1,
      );
    }
    return SpringDescription.withDampingRatio(
      mass: 1,
      stiffness: stiffness,
      ratio: damping,
    );
  }

  /// 单次过渡时长（减弱/关闭档下用于替代弹簧）。
  Duration duration(M3ESpringType type, M3ESpringSpeed speed) {
    final double base = switch (type) {
      M3ESpringType.spatial => switch (speed) {
          M3ESpringSpeed.fast => 200,
          M3ESpringSpeed.normal => 300,
          M3ESpringSpeed.slow => 400,
        },
      M3ESpringType.effects => switch (speed) {
          M3ESpringSpeed.fast => 100,
          M3ESpringSpeed.normal => 200,
          M3ESpringSpeed.slow => 300,
        },
    };
    return Duration(milliseconds: (base * durationScale).round());
  }

  (double, double) _spec(M3ESpringType type, M3ESpringSpeed speed) {
    if (type == M3ESpringType.effects) {
      return switch (speed) {
        M3ESpringSpeed.fast => (3800, 1.0),
        M3ESpringSpeed.normal => (1600, 1.0),
        M3ESpringSpeed.slow => (800, 1.0),
      };
    }
    if (scheme == M3ESpringScheme.standard) {
      return switch (speed) {
        M3ESpringSpeed.fast => (1400, 0.9),
        M3ESpringSpeed.normal => (700, 0.9),
        M3ESpringSpeed.slow => (300, 0.9),
      };
    }
    return switch (speed) {
      M3ESpringSpeed.fast => (800, 0.6),
      M3ESpringSpeed.normal => (380, 0.8),
      M3ESpringSpeed.slow => (200, 0.8),
    };
  }
}

typedef M3ESpringSpec = (double stiffness, double dampingRatio);
typedef M3ESpeedMap = Map<M3ESpringSpeed, M3ESpringSpec>;
typedef M3ESchemeMap = Map<M3ESpringScheme, M3ESpeedMap>;

/// 原始弹簧 token（不含 scheme / level 逻辑），供回归锁逐值比对。
///
/// 结构：`[type][scheme][speed] = (stiffness, dampingRatio)`
const Map<M3ESpringType, M3ESchemeMap> m3eSpringTokens =
    <M3ESpringType, M3ESchemeMap>{
  M3ESpringType.spatial: <M3ESpringScheme, M3ESpeedMap>{
    M3ESpringScheme.expressive: <M3ESpringSpeed, M3ESpringSpec>{
      M3ESpringSpeed.fast: (800, 0.6),
      M3ESpringSpeed.normal: (380, 0.8),
      M3ESpringSpeed.slow: (200, 0.8),
    },
    M3ESpringScheme.standard: <M3ESpringSpeed, M3ESpringSpec>{
      M3ESpringSpeed.fast: (1400, 0.9),
      M3ESpringSpeed.normal: (700, 0.9),
      M3ESpringSpeed.slow: (300, 0.9),
    },
  },
  M3ESpringType.effects: <M3ESpringScheme, M3ESpeedMap>{
    M3ESpringScheme.expressive: <M3ESpringSpeed, M3ESpringSpec>{
      M3ESpringSpeed.fast: (3800, 1.0),
      M3ESpringSpeed.normal: (1600, 1.0),
      M3ESpringSpeed.slow: (800, 1.0),
    },
    M3ESpringScheme.standard: <M3ESpringSpeed, M3ESpringSpec>{
      M3ESpringSpeed.fast: (3800, 1.0),
      M3ESpringSpeed.normal: (1600, 1.0),
      M3ESpringSpeed.slow: (800, 1.0),
    },
  },
};
