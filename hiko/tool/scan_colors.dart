import 'dart:io';
import 'package:image/image.dart' as img;

/// 输出指定区域每行的主色（找按钮）
void main(List<String> args) {
  final image = img.decodePng(File(args[0]).readAsBytesSync())!;
  for (var y = 80; y < 330; y += 10) {
    final counts = <int, int>{};
    for (var x = 600; x < image.width; x += 4) {
      final p = image.getPixel(x, y);
      final key = (p.r.toInt() / 32).toInt() * 1000000 +
          (p.g.toInt() / 32).toInt() * 1000 +
          (p.b.toInt() / 32).toInt();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final top = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final desc = top.take(3).map((e) {
      final r = (e.key ~/ 1000000) * 32, g = ((e.key ~/ 1000) % 1000) * 32, b = (e.key % 1000) * 32;
      return 'rgb($r,$g,$b)x${e.value}';
    }).join(' | ');
    stdout.writeln('y=$y: $desc');
  }
}
