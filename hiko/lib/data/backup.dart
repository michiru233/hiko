import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/album.dart';
import 'categories_provider.dart';
import 'settings_store.dart';

/// 备份文件（1.99.14）：库快照 + 分类 + 设置键值，单 JSON 文件换机迁移。
/// 明确不包含：JWT 登录令牌（用户裁决 2026-10-02）、封面缓存、本机路径类设置
/// （音乐目录 / 自定义背景图——跨机无效）。
/// 本地专辑的源文件路径在新机无效属既有限制，导入后由既有「清理失效记录」兜底，
/// 不自动清理。
class HikoBackup {
  HikoBackup({
    this.schemaVersion = currentSchemaVersion,
    required this.createdAt,
    required this.albums,
    required this.categories,
    required this.settings,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final DateTime createdAt;

  /// 库快照：模型往返（fromJson/toJson 与 library.json 落盘同一 schema）
  final List<Album> albums;

  /// 分类表原始 JSON（CategoryItem.toJson），原样带走、原样写回
  final List<Object> categories;

  /// SharedPreferences 中 `hiko-` 前缀键值（排除令牌/路径/分类键）
  final Map<String, Object> settings;

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'createdAt': createdAt.toIso8601String(),
        'library': {
          'version': 1,
          'albums': albums.map((a) => a.toJson()).toList(),
        },
        'categories': categories,
        'settings': settings,
      };

  String encode() => jsonEncode(toJson());

  /// 从运行中的应用状态构建备份（库快照由调用方传入；分类与设置读 prefs）
  static Future<HikoBackup> capture({required List<Album> albums}) async {
    final prefs = await SharedPreferences.getInstance();
    final categoriesRaw = prefs.getString(CategoriesNotifier.categoriesPrefKey);
    final categories = <Object>[];
    if (categoriesRaw != null && categoriesRaw.isNotEmpty) {
      final decoded = jsonDecode(categoriesRaw);
      if (decoded is List) categories.addAll(decoded.cast<Object>());
    }
    final settings = <String, Object>{
      for (final key in prefs.getKeys())
        if (key.startsWith('hiko-') &&
            key != CategoriesNotifier.categoriesPrefKey &&
            !SettingsNotifier.backupExcludedKeys.contains(key) &&
            prefs.get(key) != null)
          key: prefs.get(key)!,
    };
    return HikoBackup(
      createdAt: DateTime.now(),
      albums: albums,
      categories: categories,
      settings: settings,
    );
  }

  /// 解析并校验备份内容；JSON 损坏 / 版本不符 / 结构缺失抛 [BackupFormatException]
  static HikoBackup decode(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException catch (e) {
      throw BackupFormatException('不是合法的 JSON（${e.message}）');
    }
    if (decoded is! Map<String, dynamic>) {
      throw BackupFormatException('备份结构不正确');
    }
    final version = decoded['schemaVersion'];
    if (version is! int || version < 1 || version > currentSchemaVersion) {
      throw BackupFormatException('不支持的备份版本：$version');
    }
    try {
      final library = decoded['library'];
      final albumList = library is Map<String, dynamic>
          ? (library['albums'] as List? ?? const []).toList()
          : const <Object>[];
      final categories = (decoded['categories'] as List? ?? const []).toList();
      final settings = <String, Object>{
        for (final e in
            (decoded['settings'] as Map<String, dynamic>? ?? const {}).entries)
          if (e.value != null) e.key: e.value!,
      };
      return HikoBackup(
        schemaVersion: version,
        createdAt:
            DateTime.tryParse(decoded['createdAt'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
        albums: albumList.map((a) => Album.fromJson(asObjectMap(a))).toList(),
        categories: categories.cast<Object>(),
        settings: settings,
      );
    } on TypeError catch (e) {
      throw BackupFormatException('备份字段类型不正确（$e）');
    }
  }

  /// 把备份的分类与设置写回 SharedPreferences。
  /// 库的写回由调用方走 `libraryProvider.replaceAll`（需要 notifier 生命周期）。
  /// 返回写回的设置键数量。
  Future<int> restoreToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        CategoriesNotifier.categoriesPrefKey, jsonEncode(categories));
    var count = 0;
    for (final entry in settings.entries) {
      final v = entry.value;
      if (v is bool) {
        await prefs.setBool(entry.key, v);
      } else if (v is int) {
        await prefs.setInt(entry.key, v);
      } else if (v is num) {
        await prefs.setDouble(entry.key, v.toDouble());
      } else if (v is String) {
        await prefs.setString(entry.key, v);
      } else if (v is List) {
        await prefs.setStringList(
            entry.key, v.map((e) => e.toString()).toList());
      } else {
        continue;
      }
      count++;
    }
    return count;
  }

  static Map<String, dynamic> asObjectMap(Object value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    throw BackupFormatException('备份条目不是对象');
  }
}

/// 备份文件不可读 / 不受支持
class BackupFormatException implements Exception {
  BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
