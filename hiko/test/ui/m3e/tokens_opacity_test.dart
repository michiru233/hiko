import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// 搜索面不透明度与新阴影参数的锁（1.99.71）。
void main() {
  const color = Color(0xFF123456);

  test('clamp：0–1 之外夹回端点', () {
    expect(M3ESurfaceOpacity.clamp(-1), 0);
    expect(M3ESurfaceOpacity.clamp(2), 1);
    expect(M3ESurfaceOpacity.clamp(0.42), 0.42);
  });

  test('apply：1.0 原样返回，其它值只改 alpha', () {
    expect(M3ESurfaceOpacity.apply(color, 1), color);
    final half = M3ESurfaceOpacity.apply(color, 0.5);
    expect(half.a, closeTo(0.5, 0.001));
    expect(half.r, color.r);
    expect(half.g, color.g);
    expect(half.b, color.b);
  });

  test('composited：两层同 alpha 叠加后的有效覆盖', () {
    expect(M3ESurfaceOpacity.composited(0), 0);
    expect(M3ESurfaceOpacity.composited(1), 1);
    expect(M3ESurfaceOpacity.composited(0.5), closeTo(0.75, 0.0001));
  });

  test('阴影 opacity 同比缩放；0 时返回空表', () {
    final half = M3EElevation.shadow(M3EElevation.level3, color, opacity: 0.5);
    expect(half, hasLength(2));
    expect(half[0].color.a, closeTo(0.15, 0.001));
    expect(half[1].color.a, closeTo(0.06, 0.001));

    expect(
      M3EElevation.shadow(M3EElevation.level3, color, opacity: 0),
      isEmpty,
    );
    expect(M3EElevation.shadow(0, color), isEmpty);
  });

  test('默认 opacity=1 与旧行为一致', () {
    final legacy = M3EElevation.shadow(M3EElevation.level3, color);
    expect(legacy[0].color.a, closeTo(0.30, 0.001));
    expect(legacy[1].color.a, closeTo(0.12, 0.001));
  });
}
