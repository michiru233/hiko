import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/album_card.dart';

/// 1.99.64：专辑卡的人名胶囊（声优蓝 / 社团紫）在**亮色主题**下字与底同色系
/// 同明度，实测对比度只有 1.20:1 / 1.34:1 —— 用户贴图报障「亮色模式太不清晰」。
///
/// 这里锁两件事：
/// 1. 两对色本身在明暗两个主题下都达到 WCAG AA（≥ 4.5:1，按实际叠在卡片底上算）；
/// 2. 卡片真的用了这对色（底色 = background、字色 = foreground），而不是退回
///    「同色相 14% 底 + 同色相字」的老写法。
void main() {
  /// WCAG 相对亮度。
  double luminance(Color c) {
    double channel(double v) =>
        v <= 0.03928 ? v / 12.92 : _pow((v + 0.055) / 1.055, 2.4);
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  M3EColors colorsFor(String theme) =>
      buildM3EThemeData(AppSettings(theme: theme)).colors;

  Widget host(Album album, String theme) => MaterialApp(
    theme: buildHikoTheme(AppSettings(theme: theme)),
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 190,
        child: AlbumCard(
          album: album,
          multiMode: false,
          selected: false,
          onTap: () {},
          onContextMenu: null,
        ),
      ),
    ),
  );

  Album album() => Album(
    id: 'local-pill',
    sourcePath: '/tmp/rj123',
    title: '【BSS⚡】僕が先に好きだった優しいコスプレ…',
    artist: '飴屋ぺろり',
    albumArtist: 'バイコーンの森',
    rjCode: 'RJ01319610',
    totalDuration: 8700,
    duration: 5,
    date: DateTime(2026),
  );

  /// 胶囊底色以 alpha 叠在卡片面上才是最终观感（暗色那支是 0x33 半透明）。
  Color pillBackdrop(BuildContext context, Color background) {
    final surface = M3ETheme.of(context).colors.surfaceContainerLow;
    return Color.alphaBlend(background, surface);
  }

  for (final theme in <String>['light', 'dark']) {
    final isDark = theme == 'dark';

    test('$theme：声优 / 社团胶囊的色对达到 AA（≥ 4.5:1）', () {
      final colors = colorsFor(theme);
      for (final entry in <String, M3ETintPair>{
        '声优': M3ESemantic.albumVoicePill(isDark),
        '社团': M3ESemantic.albumCirclePill(isDark),
      }.entries) {
        final bg = Color.alphaBlend(
          entry.value.background,
          colors.surfaceContainerLow,
        );
        final ratio = contrast(entry.value.foreground, bg);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason:
              '$theme 主题下「${entry.key}」胶囊对比度只有 ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    testWidgets('$theme：卡片上的人名胶囊用的是这对色，且对比度达标', (tester) async {
      await tester.pumpWidget(host(album(), theme));
      await tester.pump();

      Future<void> checkPill(String name, M3ETintPair expected) async {
        final text = tester.widget<Text>(find.text(name));
        final fg = text.style?.color;
        expect(fg, expected.foreground, reason: '$theme：$name 字色没用色对');

        final container = tester.widget<Container>(
          find.ancestor(of: find.text(name), matching: find.byType(Container)).first,
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, expected.background, reason: '$theme：$name 底色没用色对');

        final bg = pillBackdrop(tester.element(find.text(name)), decoration.color!);
        expect(contrast(fg!, bg), greaterThanOrEqualTo(4.5));
      }

      await checkPill('飴屋ぺろり', M3ESemantic.albumVoicePill(isDark));
      await checkPill('バイコーンの森', M3ESemantic.albumCirclePill(isDark));
      expect(tester.takeException(), isNull);
    });
  }

  test('源码锁：卡片不再写「同色相 14% 底」的老写法', () {
    final source = File('lib/ui/widgets/album_card.dart').readAsStringSync();
    expect(source.contains('M3ESemantic.albumVoicePill('), isTrue);
    expect(source.contains('M3ESemantic.albumCirclePill('), isTrue);
    expect(
      source.contains('color.withValues(alpha: 0.14'),
      isFalse,
      reason: '同色相半透明底 + 同色相字是 1.99.64 要根治的写法',
    );
  });
}

double _pow(double base, double exponent) => math.pow(base, exponent).toDouble();
