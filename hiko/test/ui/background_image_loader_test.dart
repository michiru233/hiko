import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/background.dart';

/// 1.86 背景图常驻解码缓存：同路径只解码一次（幂等）、空路径清空。
/// 换页被挤出缓存反复重解码，正是 Android 详情页背景"过一会才出现"的根因。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadBackgroundImage 幂等：同路径复用同一实例，空路径清空', () async {
    // 1x1 PNG（解码端 targetWidth 放大到 2560，不影响幂等性判断）
    const pngBase64 =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final dir = await Directory.systemTemp.createTemp('hiko-bg-test');
    final file = File('${dir.path}${Platform.pathSeparator}bg.png')
      ..writeAsBytesSync(base64Decode(pngBase64));
    addTearDown(() => dir.delete(recursive: true));

    await loadBackgroundImage('');
    expect(backgroundLoadedImage.value, isNull);

    await loadBackgroundImage(file.path);
    final first = backgroundLoadedImage.value;
    expect(first, isNotNull);
    expect(first!.path, file.path);
    expect(first.image, isNotNull);

    await loadBackgroundImage(file.path);
    expect(identical(backgroundLoadedImage.value, first), isTrue);
  });
}
