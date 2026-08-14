import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

/// 生成应用图标源图（1024x1024）：深紫渐变 + 白色月亮 + 星点（Kikoeru 品牌）。
/// 用法：dart run tool/gen_icon.dart
void main() {
  const size = 1024;
  final image = img.Image(width: size, height: size);

  // 对角渐变（#6559d8 → #4b416c）
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final t = (x + y) / (2 * size);
      final r = (0x65 + (0x4B - 0x65) * t).round();
      final g = (0x59 + (0x41 - 0x59) * t).round();
      final b = (0xD8 + (0x6C - 0xD8) * t).round();
      image.setPixelRgb(x, y, r, g, b);
    }
  }

  // 装饰圆（低透明度高光）
  _fillCircle(image, 820, 200, 300, (255, 255, 255, 12));
  _fillCircle(image, 140, 100, 220, (255, 255, 255, 8));

  // 白色月亮（大圆 + 偏移深色圆裁剪出月牙）
  const cx = 512, cy = 470, r = 260;
  _fillCircle(image, cx, cy, r, (255, 255, 255, 255));
  // 用深色同渐变色覆盖右下方形成月牙
  _fillCircle(image, cx + 95, cy - 60, 235, (0x5A, 0x4F, 0xC0, 255));

  // 星点
  _fillCircle(image, 810, 190, 14, (255, 255, 255, 220));
  _fillCircle(image, 720, 300, 9, (255, 255, 255, 180));
  _fillCircle(image, 190, 760, 11, (255, 255, 255, 160));

  // 圆角裁切（iOS/macOS 风格 20% 圆角）
  final rounded = _roundCorners(image, (size * 0.20).round());

  final out = File('assets/icon.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(img.encodePng(rounded));
  stdout.writeln('icon generated: ${out.path}');
}

void _fillCircle(img.Image image, int cx, int cy, int r, (int, int, int, int) c) {
  final (r8, g8, b8, a8) = c;
  for (var y = max(0, cy - r); y <= min(image.height - 1, cy + r); y++) {
    for (var x = max(0, cx - r); x <= min(image.width - 1, cx + r); x++) {
      final d = sqrt(pow(x - cx, 2) + pow(y - cy, 2));
      if (d <= r) {
        final alpha = ((1 - (d / r)) * a8 * 0.35 + a8 * 0.65).clamp(0, 255).round();
        image.setPixelRgba(x, y, r8, g8, b8, alpha);
      }
    }
  }
}

img.Image _roundCorners(img.Image image, int radius) {
  final out = img.Image.from(image);
  final size = image.width;
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final inCorner = (x < radius && y < radius) ||
          (x >= size - radius && y < radius) ||
          (x < radius && y >= size - radius) ||
          (x >= size - radius && y >= size - radius);
      if (!inCorner) continue;
      // 计算到最近圆角的距离
      final cx = x < radius ? radius : size - radius - 1;
      final cy = y < radius ? radius : size - radius - 1;
      final d = sqrt(pow(x - cx, 2) + pow(y - cy, 2));
      if (d > radius) {
        out.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return out;
}
