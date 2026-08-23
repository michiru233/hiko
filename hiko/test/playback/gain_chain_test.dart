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
}
