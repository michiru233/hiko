import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/playback/mpv_diagnostic_log.dart';

void main() {
  group('MpvDiagnosticLog.formatLine', () {
    test('包含时间戳、级别与前缀', () {
      final line = MpvDiagnosticLog.formatLine(
        DateTime(2026, 8, 30, 12, 34, 56, 789),
        'warn',
        'cplayer',
        'audio device no longer present',
      );
      expect(
        line,
        '2026-08-30T12:34:56.789 [warn] cplayer: audio device no longer present\n',
      );
    });

    test('空前缀回退为 -，文本原样保留', () {
      final line = MpvDiagnosticLog.formatLine(
        DateTime(2026, 1, 2, 3, 4, 5),
        'error',
        '',
        'ao/coreaudio: init failed',
      );
      expect(line, '2026-01-02T03:04:05.000 [error] -: ao/coreaudio: init failed\n');
    });
  });

  group('MpvDiagnosticLog.write', () {
    test('写入临时文件并追加；init 未完成前不写', () async {
      final tmp = await Directory.systemTemp.createTemp('hiko-mpv-log-test');
      addTearDown(() async => await tmp.delete(recursive: true));
      final file = File('${tmp.path}/hiko-mpv.log');

      MpvDiagnosticLog.debugSetFile(null);
      await MpvDiagnosticLog.write('ignored\n'); // 无文件：静默不抛
      expect(await file.exists(), isFalse);

      MpvDiagnosticLog.debugSetFile(file);
      await MpvDiagnosticLog.write('first\n');
      await MpvDiagnosticLog.write('second\n');
      expect(await file.readAsString(), 'first\nsecond\n');
      MpvDiagnosticLog.debugSetFile(null);
    });
  });
}
