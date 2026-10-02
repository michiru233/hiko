import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/playback/sleep_timer.dart';

void main() {
  group('SleepTimerLogic', () {
    test('切歌拦截:off 不拦 / 播完当前曲拦 / 倒计时未到期不拦', () {
      expect(
        SleepTimerLogic.shouldBlockTrackSwitch(
            const SleepTimerState(mode: SleepTimerMode.off)),
        isFalse,
      );
      expect(
        SleepTimerLogic.shouldBlockTrackSwitch(
            const SleepTimerState(mode: SleepTimerMode.endOfTrack)),
        isTrue,
      );
    });

    test('倒计时未到期不拦截切歌', () {
      fakeAsync((async) {
        final s = SleepTimerLogic.startTimed(15);
        async.elapse(const Duration(minutes: 14));
        expect(SleepTimerLogic.expired(s), isFalse);
        expect(SleepTimerLogic.shouldBlockTrackSwitch(s), isFalse);
      });
    });

    test('倒计时已到点拦截切歌(下一首绝不起播)', () {
      fakeAsync((async) {
        final s = SleepTimerLogic.startTimed(15);
        async.elapse(const Duration(minutes: 15, seconds: 1));
        expect(SleepTimerLogic.expired(s), isTrue);
        expect(SleepTimerLogic.shouldBlockTrackSwitch(s), isTrue);
      });
    });
  });

  group('SleepTimerEngine', () {
    test('倒计时:到点淡出至 0 并触发 onExpired 停止', () {
      fakeAsync((async) {
        var expiredCount = 0;
        final ticks = <double>[];
        final engine = SleepTimerEngine(
          onTick: (remaining, factor) => ticks.add(factor),
          onExpired: () => expiredCount++,
        );
        engine.startTimed(15);

        // 启动立即 tick 一次:远离淡出窗口,系数 1.0
        expect(ticks.last, 1.0);

        // 进入淡出窗口中点(剩余 5s):系数 ≈ 0.5
        async.elapse(const Duration(minutes: 14, seconds: 55));
        expect(ticks.last, closeTo(0.5, 0.05));

        // 到点:系数归 0,触发 onExpired,引擎回到 off
        async.elapse(const Duration(seconds: 6));
        expect(ticks.last, 0.0);
        expect(expiredCount, 1);
        expect(engine.state.mode, SleepTimerMode.off);
      });
    });

    test('淡出窗口外保持 1.0,窗口内线性下降', () {
      fakeAsync((async) {
        final factors = <double>[];
        final engine = SleepTimerEngine(onTick: (_, f) => factors.add(f));
        engine.startTimed(30);

        async.elapse(const Duration(minutes: 29, seconds: 45));
        expect(factors.last, 1.0); // 剩 15s,窗口外

        async.elapse(const Duration(seconds: 10)); // 剩 5s = 窗口中点
        expect(factors.last, closeTo(0.5, 0.05));
      });
    });

    test('播完当前曲:无计时回调,但切歌拦截生效;cancel 后恢复', () {
      final engine = SleepTimerEngine();
      engine.startEndOfTrack();
      expect(engine.state.mode, SleepTimerMode.endOfTrack);
      expect(
        SleepTimerLogic.shouldBlockTrackSwitch(engine.state),
        isTrue,
      );

      engine.cancel();
      expect(engine.state.mode, SleepTimerMode.off);
      expect(
        SleepTimerLogic.shouldBlockTrackSwitch(engine.state),
        isFalse,
      );
    });

    test('播完当前专辑:不拦截专辑内顺延,只拦专辑边界', () {
      final engine = SleepTimerEngine();
      engine.startEndOfAlbum();
      expect(engine.state.mode, SleepTimerMode.endOfAlbum);
      // 专辑内顺延不拦切歌
      expect(
        SleepTimerLogic.shouldBlockTrackSwitch(engine.state),
        isFalse,
      );

      bool block(String? targetAlbumId, int? targetIndex,
              {int queueIndex = 0, int trackCount = 5, int dir = 1}) =>
          SleepTimerLogic.shouldBlockAlbumAdvance(
            s: engine.state,
            currentAlbumId: 'RJ123',
            queueIndex: queueIndex,
            trackCount: trackCount,
            dir: dir,
            targetAlbumId: targetAlbumId,
            targetIndex: targetIndex,
          );

      // 专辑内顺延 → 放行
      expect(block('RJ123', 1), isFalse);
      expect(block('RJ123', 3, queueIndex: 2), isFalse);
      // 最后一轨 → 回绕第 0 轨(list 模式) → 拦
      expect(block('RJ123', 0, queueIndex: 4, trackCount: 5), isTrue);
      // 单轨专辑顺延 → 拦
      expect(block('RJ123', 0, queueIndex: 0, trackCount: 1), isTrue);
      // 跨专辑(album 模式) → 拦
      expect(block('RJ456', 0), isTrue);
      // 队列尽头(无目标) → 拦
      expect(block(null, null), isTrue);
      // 反向(dir<0)回绕到最后一轨不算「播完」 → 放行
      expect(block('RJ123', 4,
          queueIndex: 0, trackCount: 5, dir: -1), isFalse);

      engine.cancel();
      expect(engine.state.mode, SleepTimerMode.off);
      expect(
        SleepTimerLogic.shouldBlockAlbumAdvance(
          s: engine.state,
          currentAlbumId: 'RJ123',
          queueIndex: 4,
          trackCount: 5,
          dir: 1,
          targetAlbumId: 'RJ123',
          targetIndex: 0,
        ),
        isFalse,
      );
    });

    test('倒计时模式不触发专辑边界拦截', () {
      fakeAsync((async) {
        final s = SleepTimerLogic.startTimed(30);
        expect(
          SleepTimerLogic.shouldBlockAlbumAdvance(
            s: s,
            currentAlbumId: 'RJ123',
            queueIndex: 4,
            trackCount: 5,
            dir: 1,
            targetAlbumId: 'RJ456',
            targetIndex: 0,
          ),
          isFalse,
        );
      });
    });
  });
}
