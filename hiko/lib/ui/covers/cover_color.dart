import 'dart:typed_data';
import 'dart:ui' show Color;

import 'package:image/image.dart' as img;

import 'cover_cache.dart';

/// 封面主色提取（1.99.29，播放页背景渐变用）。
///
/// 复用 [CoverCache] 的字节缓存（data:/网络同源），`package:image` 降采样到
/// 32×32 后做粗直方图取主色。plan §9.2 规定的配色种子管线（降采样 → 主色 →
/// HCT）在 1.99.30 落地时与本文件合并；那里需要 HCT 色调板，这里只要一个
/// 「能代表这张封面」的颜色，RGB 直方图就够。
///
/// 主色规则：饱和度太低的灰段（近黑/近白）不配当主色，除非整张图都灰。
/// 结果按封面源缓存，同一封面整个会话只解码一次。
abstract final class CoverColor {
  static final Map<String, Color> _cache = {};

  static Color? _fromBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final small = img.copyResize(decoded, width: 32, height: 32);
    // RGB 4bit/通道 的粗直方图：1024 个样本，桶足够密又不会糊掉主调。
    final buckets = <int, int>{};
    for (final p in small.data!) {
      final r8 = p.r.toInt(), g8 = p.g.toInt(), b8 = p.b.toInt();
      final key = (r8 >> 4 << 8) | (g8 >> 4 << 4) | (b8 >> 4);
      buckets[key] = (buckets[key] ?? 0) + 1;
    }
    if (buckets.isEmpty) return null;

    int best = -1;
    double bestScore = -1;
    for (final e in buckets.entries) {
      final r = ((e.key >> 8) & 0xF) * 17;
      final g = ((e.key >> 4) & 0xF) * 17;
      final b = (e.key & 0xF) * 17;
      final maxC = [r, g, b].reduce((a, c) => a > c ? a : c);
      final minC = [r, g, b].reduce((a, c) => a < c ? a : c);
      final saturation = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
      final luminance = 0.299 * r + 0.587 * g + 0.114 * b;
      // 过暗/过亮的桶降权，避免选中死黑与死白；荧光高饱和不该压过画面主调，
      // 所以饱和度权重有封顶（1.0 之后不再加分）。
      final lWeight = luminance < 25 || luminance > 225 ? 0.3 : 1.0;
      final score = e.value * (0.3 + saturation.clamp(0.0, 1.0)) * lWeight;
      if (score > bestScore) {
        bestScore = score;
        best = e.key;
      }
    }
    if (best < 0) return null;
    return Color.fromARGB(
      255,
      ((best >> 8) & 0xF) * 17,
      ((best >> 4) & 0xF) * 17,
      (best & 0xF) * 17,
    );
  }

  /// 取封面主色；拿不到（无封面/解码失败）返回 null，调用方回退主题色。
  static Future<Color?> of({required String? coverSource}) async {
    if (coverSource == null) return null;
    final cached = _cache[coverSource];
    if (cached != null) return cached;

    Uint8List? bytes;
    if (coverSource.startsWith('data:')) {
      bytes = CoverCache.instance.peek(coverSource) ??
          await CoverCache.instance.load(coverSource);
    } else if (coverSource.startsWith('http')) {
      bytes = CoverCache.instance.peek(coverSource) ??
          await CoverCache.instance.loadNetwork(coverSource);
    }
    if (bytes == null) return null;
    final color = _fromBytes(bytes);
    if (color != null) _cache[coverSource] = color;
    return color;
  }
}
