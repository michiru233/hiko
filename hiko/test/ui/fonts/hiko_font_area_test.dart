import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:hiko/ui/fonts/hiko_font_area.dart';
import 'package:hiko/ui/m3e/m3e.dart';
import 'package:hiko/ui/theme.dart';

/// 分区字体的核心锁（1.99.58）。
///
/// 这套机制的**唯一目的**是：打开某区域时该区域所有文本都换字体，关掉时
/// 真正回到系统字（而不是继续继承外层）。所以每个用例都同时断言三条取值路径
/// —— `Theme`（Material/TextField）、`M3ETheme`（M3E 组件）、`DefaultTextStyle`
/// （裸 `Text` 与内联 `TextStyle`）。
void main() {
  final template = buildHikoTheme(const AppSettings());
  final baseM3E = debugM3ETheme();

  Widget wrap({required HikoFontFamilies families, required Widget child}) =>
      MaterialApp(
        theme: template,
        home: M3ETheme(
          data: baseM3E,
          child: HikoFontScope(
            families: families,
            template: template,
            baseM3E: baseM3E,
            child: child,
          ),
        ),
      );

  /// 在区域内抓一份三路样式。
  Widget probe(HikoFontAreaId area, void Function(_Probe) onProbe) =>
      HikoFontArea(
        area: area,
        child: Builder(
          builder: (context) {
            onProbe(
              _Probe(
                theme: Theme.of(context),
                m3e: M3ETheme.of(context),
                defaultStyle: DefaultTextStyle.of(context).style,
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      );

  testWidgets('区域内三路都拿到族名', (tester) async {
    _Probe? probeResult;
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(ui: 'HikoUser_aaaa'),
        child: probe(HikoFontAreaId.ui, (p) => probeResult = p),
      ),
    );
    expect(
      probeResult!.theme.textTheme.bodyMedium?.fontFamily,
      'HikoUser_aaaa',
    );
    expect(probeResult!.m3e.type.bodyMedium.fontFamily, 'HikoUser_aaaa');
    expect(probeResult!.defaultStyle.fontFamily, 'HikoUser_aaaa');
    // 缺字回退链必须同时带上（用户字体常只有拉丁）
    expect(
      probeResult!.m3e.type.bodyMedium.fontFamilyFallback,
      contains('Noto Sans JP'),
    );
  });

  testWidgets('未选的区域保持系统字（null）', (tester) async {
    _Probe? probeResult;
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(ui: 'HikoUser_aaaa'),
        child: probe(HikoFontAreaId.lyrics, (p) => probeResult = p),
      ),
    );
    // Theme 侧的"系统字"就是根模板自带的那一族（测试环境是 Roboto，
    // 真机是 .SF / 系统 CJK），只要不是用户字体即可。
    expect(
      probeResult!.theme.textTheme.bodyMedium?.fontFamily,
      template.textTheme.bodyMedium?.fontFamily,
    );
    expect(probeResult!.m3e.type.bodyMedium.fontFamily, isNull);
    expect(
      probeResult!.defaultStyle.fontFamily,
      template.textTheme.bodyMedium?.fontFamily,
    );
  });

  testWidgets('嵌套：内层关闭时真正被重置（不继承外层）', (tester) async {
    _Probe? inner;
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(ui: 'HikoUser_outer'),
        child: HikoFontArea(
          area: HikoFontAreaId.ui,
          child: probe(HikoFontAreaId.lyrics, (p) => inner = p),
        ),
      ),
    );
    expect(
      inner!.theme.textTheme.bodyMedium?.fontFamily,
      template.textTheme.bodyMedium?.fontFamily,
    );
    expect(inner!.m3e.type.bodyMedium.fontFamily, isNull);
    expect(
      inner!.defaultStyle.fontFamily,
      template.textTheme.bodyMedium?.fontFamily,
    );
  });

  testWidgets('嵌套：内层开启时用内层族名', (tester) async {
    _Probe? inner;
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(
          ui: 'HikoUser_outer',
          lyrics: 'HikoUser_lrc',
        ),
        child: HikoFontArea(
          area: HikoFontAreaId.ui,
          child: probe(HikoFontAreaId.lyrics, (p) => inner = p),
        ),
      ),
    );
    expect(inner!.theme.textTheme.bodyMedium?.fontFamily, 'HikoUser_lrc');
    expect(inner!.m3e.type.bodyMedium.fontFamily, 'HikoUser_lrc');
  });

  testWidgets('换字体不改配色：区域内的 ColorScheme 仍来自根主题', (tester) async {
    _Probe? probeResult;
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(ui: 'HikoUser_aaaa'),
        child: probe(HikoFontAreaId.ui, (p) => probeResult = p),
      ),
    );
    expect(
      probeResult!.theme.colorScheme.primary,
      template.colorScheme.primary,
    );
    expect(probeResult!.m3e.colors.primary, baseM3E.colors.primary);
  });

  testWidgets('根作用域缺失时 HikoFontArea 原样返回（单测/嵌入不炸）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: template,
        home: const HikoFontArea(area: HikoFontAreaId.ui, child: Text('hello')),
      ),
    );
    expect(find.text('hello'), findsOneWidget);
  });

  testWidgets('内联 TextStyle 也跟随区域字体（DefaultTextStyle 合并）', (tester) async {
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(ui: 'HikoUser_aaaa'),
        child: const HikoFontArea(
          area: HikoFontAreaId.ui,
          child: Text('歌词', style: TextStyle(fontSize: 18, height: 1.8)),
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('歌词'));
    final effective = DefaultTextStyle.of(tester.element(find.text('歌词'))).style
        .merge(text.style);
    expect(effective.fontFamily, 'HikoUser_aaaa');
  });

  testWidgets('对话框走自己的开关，不受打开它的页面影响', (tester) async {
    // 页面（界面）开、对话框关
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(ui: 'HikoUser_ui'),
        child: HikoFontArea(
          area: HikoFontAreaId.ui,
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const M3EDialog(title: '对话框标题', content: Text('正文')),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('对话框标题')).style?.fontFamily,
      isNull,
      reason: '对话框关着就不该继承页面的字体',
    );
  });

  testWidgets('对话框开关打开时用对话框族名', (tester) async {
    await tester.pumpWidget(
      wrap(
        families: const HikoFontFamilies(
          ui: 'HikoUser_ui',
          dialog: 'HikoUser_dlg',
        ),
        child: HikoFontArea(
          area: HikoFontAreaId.dialog,
          child: const M3EDialog(title: '对话框标题', content: Text('正文')),
        ),
      ),
    );
    expect(
      tester.widget<Text>(find.text('对话框标题')).style?.fontFamily,
      'HikoUser_dlg',
    );
  });

  test('buildHikoTheme 的 promptFontFamily 只影响浮层，不污染根 textTheme', () {
    final theme = buildHikoTheme(
      const AppSettings(),
      promptFontFamily: 'HikoUser_x',
    );
    expect(theme.tooltipTheme.textStyle?.fontFamily, 'HikoUser_x');
    expect(theme.dialogTheme.titleTextStyle?.fontFamily, 'HikoUser_x');
    expect(
      theme.textTheme.bodyMedium?.fontFamily,
      template.textTheme.bodyMedium?.fontFamily,
      reason: '根 textTheme 不该被浮层字体污染',
    );
  });

  test('五个开关解析：没选字体时全 null', () {
    expect(HikoFontFamilies.fromSettings(const AppSettings()).isEmpty, isTrue);
    final settings = const AppSettings(
      userFontId: 'abcdef123456',
      userFontOnLyrics: false,
    );
    final families = HikoFontFamilies.fromSettings(settings);
    expect(families.ui, 'HikoUser_abcdef123456');
    expect(families.lyrics, isNull);
    expect(families.online, 'HikoUser_abcdef123456');
  });
}

class _Probe {
  const _Probe({
    required this.theme,
    required this.m3e,
    required this.defaultStyle,
  });

  final ThemeData theme;
  final M3EThemeData m3e;
  final TextStyle defaultStyle;
}
