import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 封面压缩策略（与旧版 Android 统一）：缩放到 ≤300px，JPEG 75%，≤120KB。
/// 整份 library.json 整体读写，封面过大直接拖垮库文件；300px 在手机/桌面卡片视觉无损。
const int coverMaxSize = 300;
const int coverMaxBytes = 120 * 1024;
const int coverQuality = 75;

/// 图片字节 → 压缩后的 dataURL；失败/超限返回 null
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
