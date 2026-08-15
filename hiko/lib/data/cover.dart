import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// 封面压缩策略：缩放到 ≤600px，JPEG 82%，≤500KB。
/// 详情页封面在 Retina 屏上需要 ~650 物理像素才清晰（300px 会被放大 2 倍发糊）。
/// 新版无 WebView 桥载荷限制，600px × 100 张 ≈ 8-15MB library.json，
/// 本地读写无内存峰值问题，可接受。
const int coverMaxSize = 600;
const int coverMaxBytes = 500 * 1024;
const int coverQuality = 82;

/// 图片字节 → 压缩后的 dataURL；失败/超限返回 null（在调用线程直接执行，适合已在 Isolate 中的场景）
String? coverDataUrl(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    var out = decoded;
    if (decoded.width > coverMaxSize || decoded.height > coverMaxSize) {
      out = img.copyResize(
        decoded,
        width: coverMaxSize,
        interpolation: img.Interpolation.average,
      );
    }
    final jpeg = img.encodeJpg(out, quality: coverQuality);
    if (jpeg.isEmpty || jpeg.length > coverMaxBytes) return null;
    return 'data:image/jpeg;base64,${base64Encode(jpeg)}';
  } catch (_) {
    return null;
  }
}

/// 异步调用封面压缩（通过 compute 调度到后台 Isolate，避免主 UI 线程解码大图掉帧）
Future<String?> coverDataUrlAsync(Uint8List bytes) {
  return compute(coverDataUrl, bytes);
}
