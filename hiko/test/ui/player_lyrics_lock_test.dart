import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 播放页尾部与歌词的源码锁（1.99.46）。
///
/// 歌词这一块有两类容易退化的东西：
/// 1. **承重 metrics**：歌词字号必须继续乘 `lyricsFontScale`，估算行高与
///    居中/自动滚动绑在一起（行为锁在 `lyrics_center_sweep_test` 等 18 条用例里）；
/// 2. **旧材质回流**：发光指示条、`FloatingActionButton`、Material 图标钮、
///    `HikoColors` —— 这一版刚清完，别再长回来。
void main() {
  Iterable<String> codeLines(String path) sync* {
    final lines = File(path).readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) continue;
      yield '${i + 1}:${lines[i]}';
    }
  }

  test('播放页：不再出现 HikoColors / FloatingActionButton', () {
    final offenders = <String>[];
    for (final line in codeLines(
      'lib/ui/screens/fullscreen_player_screen.dart',
    )) {
      for (final needle in <String>['HikoColors.', 'FloatingActionButton']) {
        if (line.contains(needle)) offenders.add('$line → $needle');
      }
    }
    expect(offenders, isEmpty);
  });

  test('播放页：曲目 sheet 走 M3ESheet.bottom，音量滑杆有 M3ESlider 锚点', () {
    final source = File('lib/ui/screens/fullscreen_player_screen.dart')
        .readAsStringSync();
    expect(source.contains('M3ESheetVariant.bottom'), isTrue);
    expect(source.contains("ValueKey('volume-slider')"), isTrue);
    expect(source.contains('M3ESlider('), isTrue);
  });

  test('抽屉歌词：去掉发光与 Material 行/浮钮', () {
    final offenders = <String>[];
    for (final line in codeLines('lib/ui/lyrics/drawer_lyrics_view.dart')) {
      for (final needle in <String>[
        'BoxShadow',
        'FloatingActionButton',
        'IconButton(',
        'Colors.white',
        'Colors.black',
      ]) {
        if (line.contains(needle)) offenders.add('$line → $needle');
      }
    }
    expect(offenders, isEmpty);
  });

  test('两个歌词视图都保留 lyricsFontScale 旋钮', () {
    for (final path in <String>[
      'lib/ui/screens/fullscreen_player_screen.dart',
      'lib/ui/lyrics/drawer_lyrics_view.dart',
    ]) {
      expect(
        File(path).readAsStringSync().contains('lyricsFontScale'),
        isTrue,
        reason: '$path 丢了歌词字号旋钮（承重 metrics）',
      );
    }
  });
}
