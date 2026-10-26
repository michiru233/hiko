import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/m3e/m3e.dart';

/// 产品语义色的回归锁（1.99.48）。
///
/// 这一组颜色**不由种子色派生**：它们承载信息（谁 = 哪支色），
/// 换强调色时不能被一起算掉。所以锁的方式和 37 个角色不同 ——
/// 角色锁「层深关系」，这里锁「色值本身 + 可读性 + 亮暗分叉」。
///
/// 为什么值得逐值钉住：这些色散落在在线卡、详情、统计、提示层五个面上，
/// 一旦有人「顺手调亮一点」，是**不会**有编译错误、也不会有别的测试变红的。
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  group('分色与强调色', () {
    test('社团紫 / 声优蓝 是 1.77 起沿用的那两支（换色等于换语义）', () {
      expect(M3ESemantic.circleTint, const Color(0xFFB39DDB));
      expect(M3ESemantic.voiceTint, const Color(0xFF90CAF9));
    });

    test('社团紫与声优蓝必须可区分（色距 > 60）', () {
      final dr = (M3ESemantic.circleTint.r - M3ESemantic.voiceTint.r) * 255;
      final dg = (M3ESemantic.circleTint.g - M3ESemantic.voiceTint.g) * 255;
      final db = (M3ESemantic.circleTint.b - M3ESemantic.voiceTint.b) * 255;
      expect(math.sqrt(dr * dr + dg * dg + db * db), greaterThan(60));
    });

    test('收藏红 / 评分金 / 统计三色各就各位', () {
      expect(M3ESemantic.favorite, const Color(0xFFD34C44));
      expect(M3ESemantic.rating, const Color(0xFFE8B33C));
      expect(M3ESemantic.success, const Color(0xFF4CAF50));
      expect(M3ESemantic.statFinished, const Color(0xFF4C9E6B));
      expect(M3ESemantic.statStarted, M3ESemantic.rating);
      expect(M3ESemantic.statUnplayed, const Color(0xFF9A8FC2));
    });
  });

  group('DLsite 标签', () {
    test('亮暗两套字色不同，且暗色那支更亮（深底可读）', () {
      expect(
        M3ESemantic.tagForegroundLight,
        isNot(M3ESemantic.tagForegroundDark),
      );
      expect(
        M3ESemantic.tagForegroundDark.computeLuminance(),
        greaterThan(M3ESemantic.tagForegroundLight.computeLuminance()),
        reason: '暗色主题的标签字必须提亮，否则 0xFF2E8A8F 在深底上看不清',
      );
      expect(M3ESemantic.tagForeground(false), M3ESemantic.tagForegroundLight);
      expect(M3ESemantic.tagForeground(true), M3ESemantic.tagForegroundDark);
    });

    test('标签底与字可比（≥ 3:1）', () {
      // 实测 3.58:1 —— 未达小字 AA 的 4.5，但这是 1.77 以来的既有配色，
      // 本版只做「色值收口」不改观感（深一点就会让整屏标签变重）。
      // 真正想提对比度时，改这里的同时把断言抬到 4.5，别只改色值。
      expect(
        contrast(M3ESemantic.tagBackground, M3ESemantic.tagForegroundLight),
        greaterThan(3.0),
      );
    });
  });

  group('在线元数据胶囊', () {
    final pairs = <String, M3ETintPair Function(bool)>{
      'artist': M3ESemantic.artistPill,
      'circle': M3ESemantic.circlePill,
      'download': M3ESemantic.downloadPill,
      'neutral': M3ESemantic.neutralPill,
    };

    test('暗色底一律用 alpha（不换色相，只降不透明度）', () {
      for (final entry in pairs.entries) {
        final dark = entry.value(true);
        expect(
          dark.background.a,
          lessThan(1.0),
          reason: '${entry.key} 的暗色底应当是半透明，和「浅底 + 深字」同一套语法',
        );
      }
    });

    test('亮色：三支染色对不透明，中性对是有意的半透明', () {
      for (final key in <String>['artist', 'circle', 'download']) {
        expect(
          pairs[key]!(false).background.a,
          1.0,
          reason: '$key 的亮色底应当不透明，否则卡面会透出封面',
        );
      }
      expect(
        pairs['neutral']!(false).background.a,
        lessThan(1.0),
        reason: '时长胶囊是「就是个数字」的那一档，用 5% 黑压一层就够',
      );
    });

    test('四对的底色 / 字色互不相同（一排看过去能分清）', () {
      final bgs = pairs.values.map((f) => f(false).background).toList();
      final fgs = pairs.values.map((f) => f(false).foreground).toList();
      expect(bgs.toSet().length, bgs.length, reason: '有两类胶囊底色撞了');
      expect(fgs.toSet().length, fgs.length, reason: '有两类胶囊字色撞了');
    });

    test('亮色四对的字压在底上都要可读（≥ 4.5:1）', () {
      for (final entry in pairs.entries) {
        final light = entry.value(false);
        expect(
          contrast(light.background, light.foreground),
          greaterThan(4.5),
          reason: '${entry.key} 胶囊在亮色主题下对比不足',
        );
      }
    });

    test('rj 不在语义表里：它走主色实底，必须随种子色变', () {
      // 这条不是源码锁，而是把设计意图写下来：往这里加一支「作品号紫」
      // 会让在线卡的作品号不再跟随用户选的强调色。
      expect(M3ESemantic.artistPill(false).foreground, isNot(Colors.purple));
    });
  });

  group('提示层与封面渐变', () {
    test('toast 恒暗：亮暗两套主题都不翻白', () {
      expect(M3ESemantic.toastSurface.computeLuminance(), lessThan(0.2));
      expect(M3ESemantic.onToastSurface, Colors.white);
      expect(
        contrast(M3ESemantic.toastSurface, M3ESemantic.onToastSurface),
        greaterThan(4.5),
      );
    });

    test('封面渐变底端是近黑，不是纯黑（纯黑会把封面颜色抠出硬边）', () {
      expect(M3ESemantic.artworkVignette, const Color(0xFF101010));
      expect(M3ESemantic.artworkVignette, isNot(Colors.black));
    });
  });
}
