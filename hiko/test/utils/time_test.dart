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

  group('formatTimestamp', () {
    test('补零到分钟', () {
      expect(formatTimestamp(DateTime(2026, 1, 2, 3, 4)), '2026-01-02 03:04');
      expect(formatTimestamp(DateTime(2026, 12, 31, 23, 59)), '2026-12-31 23:59');
    });
  });

  group('formatBytes', () {
    test('按量级换单位', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(1015808), '992 KB');
      expect(formatBytes(9955328), '9.5 MB');
      expect(formatBytes(1181116006), '1.1 GB');
    });
  });
}
