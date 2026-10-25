import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/tokens/motion_tokens.dart';

/// 弹簧 token 回归锁。
///
/// 注意：`SpringDescription.withDampingRatio` 内部把阻尼比换算成阻尼系数
/// （`damping = ratio * 2 * sqrt(mass * stiffness)`），所以断言时要反算回比值，
/// 不能直接比 `spring.damping`。
double _ratioOf(SpringDescription spring) =>
    spring.damping / (2 * math.sqrt(spring.mass * spring.stiffness));

void main() {
  const motion = M3EMotion();

  for (final type in M3ESpringType.values) {
    for (final speed in M3ESpringSpeed.values) {
      test('${type.name}/${speed.name}：刚度与阻尼比与 token 一致', () {
        final (stiffness, ratio) =
            m3eSpringTokens[type]![M3ESpringScheme.expressive]![speed]!;
        final spring = motion.spring(type, speed);
        expect(spring.stiffness, stiffness);
        expect(_ratioOf(spring), closeTo(ratio, 1e-9));
      });
    }
  }

  test('expressive 的 spatial 会回弹（阻尼比 < 1）', () {
    for (final speed in M3ESpringSpeed.values) {
      expect(
        _ratioOf(motion.spring(M3ESpringType.spatial, speed)),
        lessThan(1),
        reason: speed.name,
      );
    }
  });

  test('effects 两套方案参数完全相同，且永不回弹（阻尼比 = 1）', () {
    const standard = M3EMotion(scheme: M3ESpringScheme.standard);
    for (final speed in M3ESpringSpeed.values) {
      final expressiveSpring =
          motion.spring(M3ESpringType.effects, speed);
      final standardSpring = standard.spring(M3ESpringType.effects, speed);
      expect(_ratioOf(expressiveSpring), 1.0);
      expect(standardSpring.stiffness, expressiveSpring.stiffness);
      expect(_ratioOf(standardSpring), 1.0);
    }
  });

  test('standard 方案的 spatial 几乎不回弹（阻尼比 0.9）', () {
    const standard = M3EMotion(scheme: M3ESpringScheme.standard);
    for (final speed in M3ESpringSpeed.values) {
      final spring = standard.spring(M3ESpringType.spatial, speed);
      expect(_ratioOf(spring), closeTo(0.9, 1e-9), reason: speed.name);
    }
  });

  test('完整档：时长系数 1.0，状态层 100ms', () {
    expect(motion.enabled, isTrue);
    expect(motion.durationScale, 1.0);
    expect(motion.stateLayerDuration, const Duration(milliseconds: 100));
    expect(
      motion.duration(M3ESpringType.spatial, M3ESpringSpeed.normal),
      const Duration(milliseconds: 300),
    );
  });

  test('减弱档：时长减半、弹簧拉到临界阻尼（不回弹）', () {
    const reduced = M3EMotion(level: M3EMotionLevel.reduced);
    expect(reduced.enabled, isTrue);
    expect(reduced.durationScale, 0.5);
    expect(reduced.stateLayerDuration, const Duration(milliseconds: 50));
    expect(
      reduced.duration(M3ESpringType.spatial, M3ESpringSpeed.normal),
      const Duration(milliseconds: 150),
    );
    for (final speed in M3ESpringSpeed.values) {
      expect(_ratioOf(reduced.spring(M3ESpringType.spatial, speed)), 1.0,
          reason: speed.name);
    }
  });

  test('关闭档：不再产生动画，时长归零', () {
    const off = M3EMotion(level: M3EMotionLevel.off);
    expect(off.enabled, isFalse);
    expect(off.durationScale, 0);
    expect(off.stateLayerDuration, Duration.zero);
    expect(
      off.duration(M3ESpringType.spatial, M3ESpringSpeed.slow),
      Duration.zero,
    );
  });
}
