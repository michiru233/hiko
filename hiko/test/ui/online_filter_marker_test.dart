import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/ui/widgets/online_filter_marker.dart';

/// 在线筛选标记的窄屏回归锁（1.97.1）。
///
/// 1.97.0 实机截图问题：安卓竖屏第二行被挤到极限时，标记内部的文字
/// **不可收缩**，`RenderFlex overflow` 把 ✕ 关闭钮顶出屏幕外 ——
/// 用户得到一个「退不出的筛选」。修复 = 标记内部文字一律 `Flexible`。
///
/// 这些测试锁的就是那条布局不变量：**无论分配到多窄，✕ 都必须可见、
/// 且不允许任何溢出异常**。溢出在 widget test 里会以 FlutterError 抛出，
/// 所以「不抛异常」本身就是断言。
void main() {
  const longTag = '双声道立体声/人头麦'; // 实机截图里溢出的那个标签

  Future<void> pumpMarker(
    WidgetTester tester,
    Widget child, {
    required double width,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: width, child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('OnlineTagFilterMarker（1.97.1 布局不变量）', () {
    testWidgets('正常宽度：完整显示 + ✕ 可见', (tester) async {
      await pumpMarker(
        tester,
        const OnlineTagFilterMarker(tag: longTag, onClear: _noop),
        width: 300,
      );
      expect(find.text('标签：$longTag'), findsOneWidget);
      expect(find.byTooltip('退出标签筛选'), findsOneWidget);
    });

    testWidgets('窄到 70px：不溢出，✕ 仍在屏内', (tester) async {
      await pumpMarker(
        tester,
        const OnlineTagFilterMarker(tag: longTag, onClear: _noop),
        width: 70,
      );
      expect(tester.takeException(), isNull,
          reason: '窄空间下不允许 RenderFlex overflow');
      // tooltip 能命中 = ✕ 存在且可命中（旧实现里它被顶出屏幕外、点不到）
      expect(find.byTooltip('退出标签筛选'), findsOneWidget);
    });

    testWidgets('窄到 40px（极端）：仍然不溢出', (tester) async {
      await pumpMarker(
        tester,
        const OnlineTagFilterMarker(tag: longTag, onClear: _noop),
        width: 40,
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('退出标签筛选'), findsOneWidget);
    });
  });

  group('OnlineCreatorFilterMarker（1.97.1 布局不变量）', () {
    testWidgets('窄到 70px：不溢出，✕ 仍在（声优与社团两个维度）', (tester) async {
      for (final (kind, tooltip) in [
        (OnlineCreatorKind.va, '退出声优筛选'),
        (OnlineCreatorKind.circle, '退出社团筛选'),
      ]) {
        await pumpMarker(
          tester,
          OnlineCreatorFilterMarker(
            filter: OnlineCreatorFilter(kind: kind, name: '涼花みなせ'),
            onClear: _noop,
          ),
          width: 70,
        );
        expect(tester.takeException(), isNull, reason: '$tooltip 场景不允许溢出');
        expect(find.byTooltip(tooltip), findsOneWidget);
      }
    });
  });

  group('OnlineBlockedTagsMarker（1.97.1 布局不变量）', () {
    testWidgets('窄到 60px：不溢出（文字可收缩）', (tester) async {
      await pumpMarker(
        tester,
        const OnlineBlockedTagsMarker(count: 12, onTap: _noop),
        width: 60,
      );
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('管理标签黑名单'), findsOneWidget);
    });
  });

  /// 1.99.5 裁决 Q1=A：只扩 ✕ 热区，不改观感（图标仍是 13px，胶囊只是变厚）。
  ///
  /// 实机问题：旧热区 = 13px 图标 + 3px 内边距 = **19×19**，widget 测试量化过
  /// 「中心能点、偏 14px 落空」。这里把两条都钉住 ——
  /// 尺寸不变量（36×36）与行为不变量（偏 14px 仍命中）。
  group('✕ 热区 ≥36×36（1.99.5 裁决 Q1=A）', () {
    /// 取标记内那个承载 ✕ 的 InkWell 尺寸（四件套共用同一个 `_MarkerCloseButton`）。
    Size closeHitSize(WidgetTester tester) {
      return tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.close),
          matching: find.byType(InkWell),
        ),
      );
    }

    testWidgets('实测热区正好 36×36，图标保持 13px', (tester) async {
      await pumpMarker(
        tester,
        const OnlineTagFilterMarker(tag: '耳舐め', onClear: _noop),
        width: 300,
      );
      expect(closeHitSize(tester), const Size(36, 36));
      expect(tester.widget<Icon>(find.byIcon(Icons.close)).size, 13);
    });

    testWidgets('指尖偏 14px 仍命中（旧 19×19 实现此偏移会落空）', (tester) async {
      var taps = 0;
      await pumpMarker(
        tester,
        OnlineTagFilterMarker(tag: '耳舐め', onClear: () => taps++),
        width: 300,
      );
      final center = tester.getCenter(find.byIcon(Icons.close));
      // 旧热区半宽 9.5，偏 14 已出界；新热区半宽 18，偏 14 仍在内。
      await tester.tapAt(center + const Offset(14, 0));
      await tester.pump();
      expect(taps, 1, reason: '偏 14px 的指尖必须仍落在 ✕ 热区内');
    });

    testWidgets('四件套共用同一热区（标签/声优/新通用标记）', (tester) async {
      final cases = <(String, Widget)>[
        ('标签', const OnlineTagFilterMarker(tag: 'タグ', onClear: _noop)),
        (
          '声优',
          OnlineCreatorFilterMarker(
            filter: const OnlineCreatorFilter(
              kind: OnlineCreatorKind.va,
              name: '涼花みなせ',
            ),
            onClear: _noop,
          ),
        ),
        (
          '通用',
          const OnlineSimpleFilterMarker(
            label: '仅字幕',
            tooltip: '只看有字幕',
            onClear: _noop,
          ),
        ),
      ];
      for (final (name, widget) in cases) {
        await pumpMarker(tester, widget, width: 300);
        expect(closeHitSize(tester), const Size(36, 36), reason: '$name 标记热区应为 36');
      }
    });
  });
}

void _noop() {}
