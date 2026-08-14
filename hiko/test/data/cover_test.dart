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
  });
}
