import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/models/album.dart';
import 'package:hiko/ui/theme.dart';
import 'package:hiko/ui/widgets/album_card.dart';

/// 1.32 点击反馈验收：主题按压 overlay ≥0.12 alpha；点击目标是 Ink（水波纹可绘制）
void main() {
  test('主题按压 overlay ≥0.12 alpha（浅/深两套）', () {
    for (final themeName in ['light', 'dark']) {
      final theme = buildHikoTheme(AppSettings(theme: themeName));
      expect(theme.highlightColor.a, greaterThanOrEqualTo(0.12),
          reason: '$themeName highlightColor（按压持续 overlay）');
      expect(theme.splashColor.a, greaterThanOrEqualTo(0.12),
          reason: '$themeName splashColor（水波纹）');
      expect(identical(theme.splashFactory, NoSplash.splashFactory), isFalse,
          reason: '$themeName 不能关掉水波纹');
    }
  });

  testWidgets('专辑卡片用 Ink 反馈且点击回调触发', (tester) async {
    var tapped = 0;
    final album = Album(
      id: 'a',
      sourcePath: '/x',
      title: '按压反馈测试',
      artist: '社团',
      date: DateTime.now(),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildHikoTheme(AppSettings()),
          home: Scaffold(
            body: SizedBox(
              width: 220,
              height: 340,
              child: AlbumCard(
                album: album,
                multiMode: false,
                selected: false,
                onTap: () => tapped++,
                onContextMenu: null,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(InkWell), findsOneWidget,
        reason: '卡片点击目标必须是 Ink（GestureDetector 无水波纹）');
    await tester.tap(find.byType(AlbumCard));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });
}
