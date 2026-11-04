import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 字体库里的一个条目。
///
/// [id] 是字体字节的 sha1 前 12 位，同时充当落盘文件名与引擎族名后缀
/// （`HikoUser_<id>`）。这样同一份字体重复导入天然去重，切换字体也不会
/// 撞上「上一个字体同名族」的缓存。
@immutable
class UserFont {
  const UserFont({
    required this.id,
    required this.family,
    required this.file,
    required this.bytes,
    required this.addedAt,
    required this.japanese,
    required this.format,
  });

  /// 12 位小写 hex（sha1 前缀）。
  final String id;

  /// 展示名：字体 name 表里的族名，读不到时是文件名（去扩展名）。
  final String family;

  /// 绝对路径（`Application Support/fonts/<id>.<ext>`）。
  final String file;

  final int bytes;

  /// 毫秒时间戳，用于列表排序。
  final int addedAt;

  /// 是否覆盖日文字形（导入时的探针结果）。
  final bool japanese;

  /// 'ttf' | 'otf'
  final String format;

  /// 列表副标题用：原始文件名（同名不同族时靠它区分）。
  String get fileName => p.basename(file);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'family': family,
    'file': file,
    'bytes': bytes,
    'addedAt': addedAt,
    'japanese': japanese,
    'format': format,
  };

  /// 任一字段非法 → null（损坏的条目整条丢弃，不让它污染整个库）。
  static UserFont? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final family = raw['family'];
    final file = raw['file'];
    final bytes = raw['bytes'];
    final addedAt = raw['addedAt'];
    final japanese = raw['japanese'];
    final format = raw['format'];
    if (id is! String || !RegExp(r'^[0-9a-f]{12}$').hasMatch(id)) return null;
    if (family is! String || family.trim().isEmpty) return null;
    if (file is! String || file.trim().isEmpty) return null;
    if (bytes is! int || bytes <= 0) return null;
    if (addedAt is! int) return null;
    if (japanese is! bool) return null;
    if (format is! String || (format != 'ttf' && format != 'otf')) return null;
    return UserFont(
      id: id,
      family: family,
      file: file,
      bytes: bytes,
      addedAt: addedAt,
      japanese: japanese,
      format: format,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is UserFont && other.id == id);

  @override
  int get hashCode => id.hashCode;
}
