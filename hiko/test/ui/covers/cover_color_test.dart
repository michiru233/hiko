import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:hiko/ui/covers/cover_color.dart';

/// 封面主色提取（1.99.29 播放页背景渐变的取色管线）。
///
/// 直方图评分的契约：大块饱和色赢过灰段与死黑死白；解码失败返回 null
/// 而不是抛错（背景静默回退主题色）。
Uint8List _png(img.Image image) =>
    Uint8List.fromList(img.encodePng(image));

String _dataUrl(Uint8List bytes) =>
    'data:image/png;base64,${base64Encode(bytes)}';

void main() {
  test('大块饱和红：主色落在红色系（r 显著高于 g/b）', () async {
    final image = img.Image(width: 32, height: 32);
    img.fillRect(image, x1: 0, y1: 0, x2: 31, y2: 31,
        color: img.ColorRgb8(200, 40, 40));
    final color = await CoverColor.of(coverSource: _dataUrl(_png(image)));
    expect(color, isNotNull);
    final r = (color!.r * 255).round(), g = (color.g * 255).round(), b = (color.b * 255).round();
    expect(r, greaterThan(g * 2), reason: 'r 通道占优');
    expect(r, greaterThan(b * 2));
  });

  test('纯灰封面：也能返回颜色（不崩、不为空）', () async {
    final image = img.Image(width: 32, height: 32);
    img.fillRect(image, x1: 0, y1: 0, x2: 31, y2: 31,
        color: img.ColorRgb8(128, 128, 128));
    final color = await CoverColor.of(coverSource: _dataUrl(_png(image)));
    expect(color, isNotNull);
    expect((color!.r * 255).round(), 136, reason: '4bit 直方图把 128 归入桶 8（8×17=136）');
  });

  test('非法 data URL：返回 null 不抛错', () async {
    final color = await CoverColor.of(
      coverSource: 'data:image/png;base64,####',
    );
    expect(color, isNull);
  });

  test('无封面源：返回 null', () async {
    expect(await CoverColor.of(coverSource: null), isNull);
  });
}
