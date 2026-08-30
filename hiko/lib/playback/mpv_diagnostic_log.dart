import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// mpv 诊断日志落盘：事后排查「进度在走但没声音」类问题的证据。
/// 纯函数 [formatLine] 可单测；写盘失败静默容忍（日志绝不能影响播放）。
class MpvDiagnosticLog {
  MpvDiagnosticLog._();

  static const maxBytes = 2 * 1024 * 1024;
  static const fileName = 'hiko-mpv.log';

  static File? _file;
  static bool _initialized = false;

  /// 首个播放器创建前调用；失败容忍（无日志只降级可观测性）。
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$fileName');
      if (await file.exists() && await file.length() > maxBytes) {
        await file.writeAsString(''); // 超限清空（简单轮转）
      }
      _file = file;
    } catch (e) {
      debugPrint('[mpv-log] 初始化失败（容忍）: $e');
    }
  }

  /// 日志行格式化（纯函数）：`2026-08-30T12:00:00.000 [warn] cplayer: text`
  static String formatLine(
      DateTime now, String level, String prefix, String text) {
    final p = prefix.isEmpty ? '-' : prefix;
    return '${now.toIso8601String()} [$level] $p: $text\n';
  }

  static Future<void> write(String line) async {
    final file = _file;
    if (file == null) return;
    try {
      await file.writeAsString(line, mode: FileMode.append);
    } catch (_) {
      // 写盘失败容忍
    }
  }

  /// 仅供测试注入临时文件。
  static void debugSetFile(File? file) {
    _file = file;
    _initialized = true;
  }
}
