import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **业务面样式锁**（1.99.48）。
///
/// 账本锁（`style_ledger_lock_test.dart`）管的是「全仓不许出现什么」；
/// 这一份管的是「每个面**必须**接到哪一支 token 上」——
/// 两者缺一不可：只禁不导，下一次改动会找一个「等价的新写法」绕过去。
///
/// 覆盖审计点名的五个面：设置 / 在线 / 对话框 / 歌词 / 统计，+ 提示层。
void main() {
  List<String> codeLines(String path) =>
      File(path).readAsLinesSync().where((l) {
        final t = l.trimLeft();
        return !(t.startsWith('//') || t.startsWith('*') || t.startsWith('/*'));
      }).toList();

  void expectFree(String path, List<String> needles, {String? reason}) {
    final offenders = <String>[];
    final lines = codeLines(path);
    for (var i = 0; i < lines.length; i++) {
      for (final needle in needles) {
        if (lines[i].contains(needle)) offenders.add('$path → $needle');
      }
    }
    expect(offenders, isEmpty, reason: reason ?? '$path 还在写自己的样式值');
  }

  void expectHas(String path, List<String> needles) {
    final body = codeLines(path).join('\n');
    for (final needle in needles) {
      expect(
        body.contains(needle),
        isTrue,
        reason: '$path 必须从 $needle 取样式，不能另写一份',
      );
    }
  }

  const noOwnColors = <String>['Color(0x', 'hintColor', 'HikoColors'];

  group('设置页', () {
    test('不再自持色值', () {
      expectFree('lib/ui/widgets/settings_dialog.dart', noOwnColors);
    });

    test('状态点用语义色而不是随手一支绿', () {
      expectHas('lib/ui/widgets/settings_dialog.dart', ['M3ESemantic.success']);
    });
  });

  group('在线面', () {
    const files = <String>[
      'lib/ui/screens/online_screen.dart',
      'lib/ui/screens/online_favorites_screen.dart',
      'lib/ui/widgets/online_detail_panel.dart',
      'lib/ui/widgets/online_card_kit.dart',
      'lib/ui/widgets/online_work_grid.dart',
      'lib/ui/widgets/online_filter_marker.dart',
      'lib/ui/widgets/online_cover.dart',
    ];

    test('五个在线文件都不再自持色值', () {
      for (final f in files) {
        expectFree(f, noOwnColors);
      }
    });

    test('元数据胶囊的四对色必须从 M3ESemantic 取', () {
      expectHas('lib/ui/widgets/online_card_kit.dart', [
        'M3ESemantic.artistPill(',
        'M3ESemantic.circlePill(',
        'M3ESemantic.downloadPill(',
        'M3ESemantic.neutralPill(',
      ]);
    });

    test('详情里的社团 / 声优 / 收藏 / 评分都接语义色', () {
      expectHas('lib/ui/widgets/online_detail_panel.dart', [
        'M3ESemantic.circleTint',
        'M3ESemantic.voiceTint',
        'M3ESemantic.favorite',
        'M3ESemantic.rating',
      ]);
    });

    test('在线面不得再出现裸菜单 API（1.99.48 收口）', () {
      for (final f in files) {
        expectFree(f, <String>['showMenu(', 'PopupMenuButton(', 'MenuAnchor(']);
      }
    });
  });

  group('对话框族', () {
    const files = <String>[
      'lib/ui/widgets/confirm_dialog.dart',
      'lib/ui/widgets/rating_dialog.dart',
      'lib/ui/widgets/category_dialog.dart',
      'lib/ui/widgets/online_account_dialogs.dart',
      'lib/ui/widgets/offline_download_dialog.dart',
    ];

    test('对话框不再自持色值', () {
      for (final f in files) {
        expectFree(f, noOwnColors);
      }
    });

    test('评分星走评分金语义色', () {
      expectHas('lib/ui/widgets/rating_dialog.dart', ['M3ESemantic.rating']);
    });
  });

  group('歌词', () {
    const files = <String>[
      'lib/ui/lyrics/drawer_lyrics_view.dart',
      'lib/ui/lyrics/lyrics_auto_scroll.dart',
    ];

    test('歌词行不再自持色值（承重 metrics 不在这一版动）', () {
      for (final f in files) {
        expectFree(f, noOwnColors);
      }
    });

    test('歌词字号仍由 lyricsFontScale 驱动（不是 type 角色）', () {
      expectHas('lib/ui/lyrics/drawer_lyrics_view.dart', ['lyricsFontScale']);
      expectHas('lib/ui/lyrics/lyrics_auto_scroll.dart', [
        'lyricsEstimatedLineHeight',
      ]);
    });
  });

  group('统计', () {
    test('三支统计色必须来自语义表', () {
      expectHas('lib/ui/widgets/stats_view.dart', [
        'M3ESemantic.statFinished',
        'M3ESemantic.statStarted',
        'M3ESemantic.statUnplayed',
        'M3ESemantic.rating',
      ]);
    });

    test('不再自持色值', () {
      expectFree('lib/ui/widgets/stats_view.dart', noOwnColors);
    });

    test('统计卡半径走档位（M3ECard 的 radius 参数也是圆角真源）', () {
      expectHas('lib/ui/widgets/stats_view.dart', ['radius: M3EShape.lg']);
    });
  });

  group('提示层', () {
    test('toast 面与字色来自语义表（恒暗面，不随主题翻白）', () {
      expectHas('lib/ui/widgets/activity_overlay.dart', [
        'M3ESemantic.toastSurface',
        'M3ESemantic.onToastSurface',
      ]);
      expectFree('lib/ui/widgets/activity_overlay.dart', noOwnColors);
    });
  });
}
