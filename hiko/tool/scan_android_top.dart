import 'dart:io';
import 'package:image/image.dart' as img;

/// 扫描 Android 截图顶部找按钮色块（tonal 浅紫 / 主色）
void main(List<String> args) {
  final image = img.decodePng(File(args[0]).readAsBytesSync())!;
  for (var y = 60; y < 400; y += 6) {
    var minX = 1 << 30, maxX = 0, count = 0;
    for (var x = 500; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      // 浅紫 tonal（secondaryContainer 系）或主色紫 #6559d8
      final isTonal = b > 200 && r > 180 && g > 170 && (b - r).abs() < 90;
      final isPrimary = (r - 101).abs() < 40 && (g - 89).abs() < 40 && (b - 216).abs() < 50;
      if (isTonal || isPrimary) {
        minX = min(minX, x); maxX = max(maxX, x); count++;
      }
    }
    if (count > 20) {
      stdout.writeln('y=$y: x $minX-$maxX, count=$count');
    }
  }
}
int min(int a, int b) => a < b ? a : b;
int max(int a, int b) => a > b ? a : b;
