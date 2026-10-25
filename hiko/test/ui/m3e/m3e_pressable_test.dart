import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

import 'm3e_test_harness.dart';

const Key _target = Key('pressable-target');

Widget _subject({
  VoidCallback? onTap,
  bool enabled = true,
  String? label,
  M3EThemeData? theme,
}) =>
    wrapM3E(
      M3EPressable(
        onTap: onTap,
        enabled: enabled,
        semanticLabel: label,
        child: const SizedBox(key: _target, width: 120, height: 80),
      ),
      theme: theme,
    );

double _currentScale(WidgetTester tester) {
  final transform = tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(M3EPressable),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform;
  // 取 X 轴缩放：getMaxScaleOnAxis() 会连 Z 轴一起取最大值，
  // 而 Transform.scale 的 Z 轴恒为 1，永远得到 1.0（踩过一次）。
  return transform.storage[0];
}

Color? _stateLayerColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(M3EPressable),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return (container.decoration! as BoxDecoration).color;
}

void main() {
  testWidgets('点击触发回调', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_subject(onTap: () => tapped++));
    await tester.tap(find.byKey(_target));
    await tester.pumpAndSettle();
    expect(tapped, 1);
  });

  testWidgets('enabled=false 时不触发，也不进入按压态', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(_subject(onTap: () => tapped++, enabled: false));
    await tester.tap(find.byKey(_target));
    await tester.pumpAndSettle();
    expect(tapped, 0);
    expect(_currentScale(tester), 1.0);
    expect(_stateLayerColor(tester)!.a, 0);
  });

  testWidgets('悬停时状态层为 8% onSurface', (tester) async {
    await tester.pumpWidget(_subject(onTap: () {}));
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: Offset.zero);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byKey(_target)));
    await tester.pumpAndSettle();
    expect(_stateLayerColor(tester)!.a, closeTo(0.08, 0.02));
  });

  testWidgets('按下时缩放到 0.97，松手回到 1.0', (tester) async {
    await tester.pumpWidget(_subject(onTap: () {}));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_target)));
    // 第一帧只负责让 TapGestureRecognizer 过 kPressTimeout 派发 onTapDown；
    // 弹簧要到下一帧才有第一个 tick（控制器把首次 tick 记为起点）。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_currentScale(tester), lessThan(0.99));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_currentScale(tester), closeTo(1.0, 0.001));
  });

  testWidgets('关闭动效时按压立即到位（不创建弹簧）', (tester) async {
    await tester.pumpWidget(
      _subject(
        onTap: () {},
        theme: testTheme(motionLevel: M3EMotionLevel.off),
      ),
    );
    final gesture =
        await tester.startGesture(tester.getCenter(find.byKey(_target)));
    // TapGestureRecognizer 的 onTapDown 要等 kPressTimeout（100ms）才派发，
    // 所以这里必须推进时间；「立即到位」指的是没有任何过渡帧，不是不等派发。
    await tester.pump(const Duration(milliseconds: 150));
    await tester.pump();
    expect(_currentScale(tester), 0.97);
    // 再推 200ms 仍是 0.97：弹簧会有过冲，静止不动才是「关闭」。
    await tester.pump(const Duration(milliseconds: 200));
    expect(_currentScale(tester), 0.97);
    await gesture.up();
    await tester.pump();
    expect(_currentScale(tester), 1.0);
  });

  testWidgets('暴露按钮语义与标签', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_subject(onTap: () {}, label: '打开专辑'));
    expect(find.bySemanticsLabel('打开专辑'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('长按回调可用（移动端菜单入口）', (tester) async {
    var longPressed = 0;
    await tester.pumpWidget(
      wrapM3E(
        M3EPressable(
          onLongPress: () => longPressed++,
          child: const SizedBox(key: _target, width: 120, height: 80),
        ),
      ),
    );
    await tester.longPress(find.byKey(_target), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(longPressed, 1);
  });
}
