import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/playback/audio_heal.dart';

void main() {
  group('AudioHealDecider.logSuggestsDeadOutput', () {
    test('命中 coreaudio / audio device / ao 词干', () {
      expect(AudioHealDecider.logSuggestsDeadOutput('ao/coreaudio: device is gone'), isTrue);
      expect(AudioHealDecider.logSuggestsDeadOutput('[cplayer] audio device no longer present'), isTrue);
      expect(AudioHealDecider.logSuggestsDeadOutput('ao: reinitializing'), isTrue);
    });

    test('无关日志不命中', () {
      expect(AudioHealDecider.logSuggestsDeadOutput('position update 12.3s'), isFalse);
      expect(AudioHealDecider.logSuggestsDeadOutput('decoded 4096 samples'), isFalse);
    });
  });

  group('AudioHealDecider.shouldHeal', () {
    test('命中触发：播放中且日志命中 → 自愈', () {
      final decider = AudioHealDecider(now: () => DateTime(2026, 8, 30, 12));
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isTrue,
      );
    });

    test('不命中不触发：未播放或无事件', () {
      final decider = AudioHealDecider(now: () => DateTime(2026, 8, 30, 12));
      expect(
        decider.shouldHeal(playing: false, logHit: true, deviceListChanged: false),
        isFalse,
      );
      expect(
        decider.shouldHeal(playing: true, logHit: false, deviceListChanged: false),
        isFalse,
      );
    });

    test('防抖：自愈后 2 秒内的同波重复事件被吞掉', () {
      var t = DateTime(2026, 8, 30, 12);
      final decider = AudioHealDecider(now: () => t);
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isTrue,
      );
      t = t.add(const Duration(milliseconds: 500));
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isFalse,
      );
      t = t.add(const Duration(seconds: 1, milliseconds: 500)); // 距上次自愈 2s 整
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isFalse,
      );
    });

    test('限流：10 秒窗口内最多 1 次，窗口过后放行', () {
      var t = DateTime(2026, 8, 30, 12);
      final decider = AudioHealDecider(now: () => t);
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isTrue,
      );
      t = t.add(const Duration(seconds: 5)); // 窗口内
      expect(
        decider.shouldHeal(playing: true, logHit: false, deviceListChanged: true),
        isFalse,
      );
      t = t.add(const Duration(seconds: 6)); // 距上次自愈 11s > 10s 窗口
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isTrue,
      );
    });

    test('设备列表变化也能触发（限流规则相同）', () {
      var t = DateTime(2026, 8, 30, 12);
      final decider = AudioHealDecider(now: () => t);
      expect(
        decider.shouldHeal(playing: true, logHit: false, deviceListChanged: true),
        isTrue,
      );
    });

    test('force() 绕过限流（手动逃生门）', () {
      var t = DateTime(2026, 8, 30, 12);
      final decider = AudioHealDecider(now: () => t);
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isTrue,
      );
      decider.force();
      expect(
        decider.shouldHeal(playing: true, logHit: true, deviceListChanged: false),
        isTrue,
      );
    });
  });
}
