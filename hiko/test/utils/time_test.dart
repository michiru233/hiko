import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/utils/time.dart';

void main() {
  group('formatTime', () {
    test('mm:ss', () {
      expect(formatTime(0), '0:00');
      expect(formatTime(65), '1:05');
      expect(formatTime(3723), '62:03');
    });

    test('非法值', () {
      expect(formatTime(-1), '00:00');
      expect(formatTime(double.nan), '00:00');
      expect(formatTime(double.infinity), '00:00');
    });
  });

  group('formatDuration', () {
    test('中文时长', () {
      expect(formatDuration(0), '--');
      expect(formatDuration(75), '1分钟');
      expect(formatDuration(3600), '1小时');
      expect(formatDuration(4980), '1小时23分钟');
    });
  });
}
