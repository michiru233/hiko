import 'dart:ui';

/// 表面不透明度（1.99.71）。
///
/// M3E 的层深靠**不透明色调面**：`surface → Low → Container → High → Highest`。
/// 这个 token 不定义新材质，只给「用户主动放弃那层底」的场景一个统一入口：
/// 只调 alpha，不做模糊、不做玻璃（1.99.30 已删除玻璃层）。
///
/// 约定：所有消费点共用**同一档**值。alpha < 1 时色阶差会被背景稀释，
/// 阴影随之淡出，是最后一点「这里还有一层」的线索。
abstract final class M3ESurfaceOpacity {
  static const double transparent = 0;
  static const double opaque = 1;

  static double clamp(double value) => value.clamp(transparent, opaque);

  /// 1.0 时**原样返回**：保证默认路径与旧实现逐位相同（颜色严格相等断言依赖这点）。
  static Color apply(Color color, double opacity) {
    final value = clamp(opacity);
    return value >= opaque ? color : color.withValues(alpha: value);
  }

  /// 子面盖在父面之上、两者同为 [opacity] 时的有效覆盖：1 − (1−a)²。
  static double composited(double opacity) {
    final value = clamp(opacity);
    return 1 - (1 - value) * (1 - value);
  }
}
