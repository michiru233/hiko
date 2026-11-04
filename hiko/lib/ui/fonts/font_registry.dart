import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'font_models.dart';

/// 运行时字体注册。
///
/// Flutter 没有「卸载字体」的 API：注册过的族会一直留在引擎里直到进程退出。
/// 因此这里做两件事：
/// 1. 同一个 [UserFont.id] 只 `load()` 一次（重复 load 会真的重复占内存）；
/// 2. 族名自造成 ASCII（`HikoUser_<id>`），绝不把字体 name 表里的族名
///    直接交给引擎 —— 那个字符串可能带引号、零宽字符或超长。
class FontRegistry {
  FontRegistry._();

  static final Set<String> _loaded = <String>{};

  /// 测试注入点：默认走 `FontLoader`。
  @visibleForTesting
  static Future<void> Function(String family, ByteData data)? debugLoader;

  static String familyOf(String id) => 'HikoUser_$id';

  static bool isLoaded(String id) => _loaded.contains(id);

  @visibleForTesting
  static void resetForTest() {
    _loaded.clear();
    debugLoader = null;
  }

  /// 注册失败返回 false 且**不写入已加载集合**，下次可以重试。
  static Future<bool> ensureLoaded(UserFont font) async {
    if (_loaded.contains(font.id)) return true;
    try {
      final bytes = await File(font.file).readAsBytes();
      if (bytes.isEmpty) return false;
      final family = familyOf(font.id);
      final data = ByteData.sublistView(bytes);
      final loader = debugLoader;
      if (loader != null) {
        await loader(family, data);
      } else {
        final fontLoader = FontLoader(family)
          ..addFont(Future<ByteData>.value(data));
        await fontLoader.load();
      }
      _loaded.add(font.id);
      return true;
    } catch (e) {
      debugPrint('字体注册失败: $e');
      return false;
    }
  }
}
