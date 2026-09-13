import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/playback/gain_chain.dart';

void main() {
  group('gainAfChain', () {
    test('增益 ≤ 1.0 返回空串（清除 af 链直通）', () {
      expect(gainAfChain(1.0), '');
      expect(gainAfChain(0.5), '');
    });

    test('增益 2.0：lavfi 浮点增益 + alimiter 软限幅（不做响度归一）', () {
      final chain = gainAfChain(2.0);
      expect(chain, contains('volume=volume=2.0'));
      expect(chain, contains('alimiter'));
      expect(chain, contains('level=false'));
    });

    test('增益 2.5：数值直接写入滤镜串', () {
      expect(gainAfChain(2.5), contains('volume=volume=2.5'));
    });
  });

  group('gainToDb（Android LoudnessEnhancer 目标增益）', () {
    test('g ≤ 1.0 返回 0 dB（旁路直通）', () {
      expect(gainToDb(1.0), 0.0);
      expect(gainToDb(0.5), 0.0);
    });

    test('2.0x → 6.02dB、4.0x → 12.04dB（20×log10）', () {
      expect(gainToDb(2.0), closeTo(6.0206, 0.001));
      expect(gainToDb(4.0), closeTo(12.0412, 0.001));
    });

    test('1.0x 与 2.0x 的 dB 差恰为 20×log10(2)≈6.02', () {
      final diff = gainToDb(2.0) - gainToDb(1.0);
      expect(diff, closeTo(6.0206, 0.001));
    });
  });

  group('desktopGainCapFor（1.80 起 macOS/Windows 均为 4.0）', () {
    test('macOS 4.0（volume-max=400 放开钳制）/ Windows 4.0', () {
      expect(desktopGainCapFor(true), 4.0);
      expect(desktopGainCapFor(false), 4.0);
    });
  });

  group('desktopVolumeFor（macOS 增益并入 volume，Windows 只承载 base）', () {
    test('macOS：base×gain，全量程 4.0x 不再压顶', () {
      expect(desktopVolumeFor(true, 1.0, 1.0), closeTo(1.0, 1e-9));
      expect(desktopVolumeFor(true, 1.0, 1.5), closeTo(1.5, 1e-9));
      expect(desktopVolumeFor(true, 0.8, 1.5), closeTo(1.2, 1e-9));
      expect(desktopVolumeFor(true, 0.8, 4.0), closeTo(3.2, 1e-9));
      expect(desktopVolumeFor(true, 1.0, 5.0), closeTo(4.0, 1e-9));
    });

    test('Windows：增益走 af 链，volume 仅承载 base', () {
      expect(desktopVolumeFor(false, 0.8, 2.0), closeTo(0.8, 1e-9));
      expect(desktopVolumeFor(false, 1.0, 3.0), closeTo(1.0, 1e-9));
    });
  });
}
