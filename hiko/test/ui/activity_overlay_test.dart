import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/widgets/activity_overlay.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/widgets/settings_dialog.dart';

void main() {
  testWidgets('无任务时根通知层不渲染进度条', (tester) async {
    final controller = ActivityOverlayController();
    await tester.pumpWidget(_app(controller));

    expect(find.byType(M3EProgress), findsNothing);
  });

  testWidgets('任务进度在普通对话框之上显示，完成后清理并显示 Toast', (tester) async {
    final controller = ActivityOverlayController();
    await tester.pumpWidget(_app(controller));

    controller.start(label: '正在扫描音频文件', processed: 2, total: 4, progress: 0.5);
    await tester.pump();
    expect(find.text('正在扫描音频文件 2 / 4'), findsOneWidget);
    expect(find.byType(M3EProgress), findsOneWidget);

    showDialog<void>(
      context: tester.element(find.byType(Scaffold)),
      builder: (_) => const AlertDialog(title: Text('普通对话框')),
    );
    await tester.pumpAndSettle();
    expect(find.text('普通对话框'), findsOneWidget);
    expect(find.text('正在扫描音频文件 2 / 4'), findsOneWidget);

    controller.finish();
    controller.showToast('扫描完成');
    await tester.pump();
    expect(find.text('正在扫描音频文件 2 / 4'), findsNothing);
    expect(find.byType(M3EProgress), findsNothing);
    expect(find.text('扫描完成'), findsOneWidget);
  });

  testWidgets('异常路径清理进度状态', (tester) async {
    final controller = ActivityOverlayController();
    await tester.pumpWidget(_app(controller));

    controller.start(label: '正在导入');
    await tester.pump();
    expect(controller.isActive, isTrue);
    expect(find.text('正在导入'), findsOneWidget);

    try {
      throw StateError('导入失败');
    } catch (error) {
      controller.finish();
      controller.showToast('导入失败：$error');
    }
    await tester.pump();
    expect(controller.isActive, isFalse);
    expect(find.text('正在导入'), findsNothing);
    expect(find.text('导入失败：Bad state: 导入失败'), findsOneWidget);
  });

  testWidgets('Toast 无下划线且宽度不超过 520', (tester) async {
    final controller = ActivityOverlayController();
    await tester.pumpWidget(_app(controller, width: 1000));

    controller.showToast('一段足够长的提示文字，用来验证通知层不会横跨整个窗口');
    await tester.pump();

    final text = tester.widget<Text>(find.textContaining('一段足够长'));
    expect(text.style?.decoration, TextDecoration.none);
    final banner = tester.renderObject<RenderBox>(
      find.byType(ConstrainedBox).last,
    );
    expect(banner.size.width, lessThanOrEqualTo(520));
  });

  testWidgets('设置触发扫描，根通知层在设置页之上显示进度', (tester) async {
    final controller = ActivityOverlayController();
    await tester.pumpWidget(
      ProviderScope(
        child: _app(
          controller,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsPage(
                      // 1.99.11：「立即重新扫描」拆为「增量扫描/全量扫描」，语义不变
                      // 1.99.32：独立页不再由回调 pop（扫描进度浮层在页面之上显示）
                      onFullScanRequested: () {
                        controller.start(label: '准备扫描...', progress: 0.0);
                      },
                    ),
                  ),
                ),
                child: const Text('打开设置'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    // 1.99.58 抽屉化：扫描按钮收进「库与扫描」子页；小窗口下这一格可能在视口外
    final libraryTile = find.text('库与扫描');
    await tester.scrollUntilVisible(
      libraryTile,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(libraryTile);
    await tester.pumpAndSettle();
    // 1.99.11：入口拆为「增量扫描/全量扫描」两按钮，两个都要在
    expect(find.text('增量扫描'), findsOneWidget);
    // 1.99.43：设置页动作按钮换成 M3EButton（不再有 Material OutlinedButton）
    final rescan = find.ancestor(
      of: find.text('全量扫描'),
      matching: find.byType(M3EButton),
    );
    await tester.ensureVisible(rescan);
    await tester.tap(rescan);
    await tester.pumpAndSettle();
    // 设置页保持挂载（旧对话框由入口回调 pop；独立页不关，活动浮层在根层之上）
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('准备扫描...'), findsOneWidget);
    expect(controller.isActive, isTrue);
    controller.finish();
  });
}

Widget _app(
  ActivityOverlayController controller, {
  double width = 800,
  Widget? home,
}) {
  return MaterialApp(
    builder: (context, child) => SizedBox(
      width: width,
      child: ActivityOverlayHost(
        controller: controller,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
    home: home ?? const Scaffold(body: SizedBox.expand()),
  );
}
