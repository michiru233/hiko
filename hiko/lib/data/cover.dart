import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 封面压缩策略：缩放到 ≤600px，JPEG 82%，≤500KB。
/// 详情页封面在 Retina 屏上需要 ~650 物理像素才清晰（300px 会被放大 2 倍发糊）。
/// 新版无 WebView 桥载荷限制，600px × 100 张 ≈ 8-15MB library.json，
/// 本地读写无内存峰值问题，可接受。
const int coverMaxSize = 600;
const int coverMaxBytes = 500 * 1024;
const int coverQuality = 82;

/// 压缩阶梯（1.32）：尺寸 600→400→300 × 质量 82→30 逐级降档；
/// 全档耗尽也不静默丢封面，返回最小产物（封面缺失比 library.json 偏大更伤）。
const List<int> _ladderSizes = [coverMaxSize, 400, 300];
const List<int> _ladderQualities = [coverQuality, 70, 60, 50, 40, 30];

/// 图片字节 → 压缩后的 dataURL；失败返回 null；压缩超限走降级阶梯，
/// [maxBytes] 仅供测试注入更小上限（默认 500KB，生产行为不变）。
String? coverDataUrl(Uint8List bytes, {int maxBytes = coverMaxBytes}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    Uint8List? smallest;
    for (final maxSize in _ladderSizes) {
      var out = decoded;
      final longSide = decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longSide > maxSize) {
        // 按长边等比缩放（竖图高度为长边时也必须落进方形上限）
        final scale = maxSize / longSide;
        out = img.copyResize(
          decoded,
          width: (decoded.width * scale).round(),
          height: (decoded.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }
      for (final quality in _ladderQualities) {
        final jpeg = img.encodeJpg(out, quality: quality);
        if (jpeg.isEmpty) continue;
        if (jpeg.length <= maxBytes) {
          return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
        }
        if (smallest == null || jpeg.length < smallest.length) {
          smallest = jpeg;
        }
      }
    }
    // 阶梯全耗尽：返回能压出的最小产物，绝不因超限静默丢封面
    return smallest == null
        ? null
        : 'data:image/jpeg;base64,${base64Encode(smallest)}';
  } catch (_) {
    return null;
  }
}

/// 异步调用封面压缩（通过 compute 调度到后台 Isolate，避免主 UI 线程解码大图掉帧）
Future<String?> coverDataUrlAsync(Uint8List bytes) {
  return compute(coverDataUrl, bytes);
}
