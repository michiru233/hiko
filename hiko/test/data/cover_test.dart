import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/cover.dart';
import 'package:image/image.dart' as img;

void main() {
  group('coverDataUrl 封面压缩', () {
    test('大图缩放到 ≤600px 且编码为 JPEG', () {
      final large = img.Image(width: 1600, height: 1200);
      img.fill(large, color: img.ColorRgb8(120, 90, 200));
      final url = coverDataUrl(img.encodePng(large))!;

      expect(url, startsWith('data:image/jpeg;base64,'));
      final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, lessThanOrEqualTo(coverMaxSize));
      expect(decoded.height, lessThanOrEqualTo(coverMaxSize));
      expect(bytes.length, lessThanOrEqualTo(coverMaxBytes));
      // 长边应为 600（等比缩放）
      expect(decoded.width, 600);
      expect(decoded.height, 450);
    });

    test('小图不放大', () {
      final small = img.Image(width: 200, height: 200);
      img.fill(small, color: img.ColorRgb8(10, 200, 100));
      final url = coverDataUrl(img.encodePng(small))!;
      final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, 200);
      expect(decoded.height, 200);
    });

    test('坏数据返回 null', () {
      expect(coverDataUrl(Uint8List.fromList(List.filled(10, 0))), isNull);
    });

    test('压缩阶梯：超限逐级降档不返 null（1.32）', () {
      // 确定性伪随机噪声图；maxBytes 压小触发降档（默认 500KB 下 image 包编码器
      // 几乎打不穿，故注入小上限测真实阶梯路径；生产行为见默认参数用例）
      final noise = img.Image(width: 2400, height: 2400);
      var seed = 42;
      int next() => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) ~/ 0x800000;
      for (final p in noise) {
        p.r = next();
        p.g = next();
        p.b = next();
      }
      final png = img.encodePng(noise);

      // 600@82 ≈ 数百 KB > 30KB → 降档到低质量/小尺寸命中 ≤30KB
      final url = coverDataUrl(png, maxBytes: 30 * 1024);
      expect(url, isNotNull, reason: '超限必须走阶梯降档而非返 null');
      final bytes = base64Decode(url!.substring(url.indexOf(',') + 1));
      expect(bytes.length, lessThanOrEqualTo(30 * 1024));

      // 全档耗尽（上限压到 100B）：也不许 null——返回最小产物
      final url2 = coverDataUrl(png, maxBytes: 100);
      expect(url2, isNotNull, reason: '阶梯耗尽不静默丢封面');
      expect(url2, startsWith('data:image/jpeg;base64,'));
    });

    test('竖图按长边缩放（1.32：高度为长边也落进方形上限）', () {
      final portrait = img.Image(width: 400, height: 800);
      img.fill(portrait, color: img.ColorRgb8(90, 120, 200));
      final url = coverDataUrl(img.encodePng(portrait))!;
      final bytes = base64Decode(url.substring(url.indexOf(',') + 1));
      final decoded = img.decodeJpg(bytes)!;
      expect(decoded.width, lessThanOrEqualTo(coverMaxSize));
      expect(decoded.height, lessThanOrEqualTo(coverMaxSize));
      expect(decoded.height, 600);
      expect(decoded.width, 300);
    });
  });
}
