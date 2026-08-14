import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final image = img.decodePng(File(args[0]).readAsBytesSync())!;
  for (var y = 200; y <= 280; y += 8) {
    var minX = 1 << 30, maxX = 0, count = 0;
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      final r = p.r.toInt(), g = p.g.toInt(), b = p.b.toInt();
      // 浅紫 tonal：r,b 高（>210），g 明显低（180-215）
      if (r > 210 && b > 210 && g >= 185 && g <= 224) {
        minX = min(minX, x); maxX = max(maxX, x); count++;
      }
    }
    stdout.writeln('y=$y: x $minX-$maxX, count=$count');
  }
}
int min(int a, int b) => a < b ? a : b;
int max(int a, int b) => a > b ? a : b;
