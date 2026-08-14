import 'package:flutter/foundation.dart';

/// 分类数据项模型
@immutable
class CategoryItem {
  const CategoryItem({
    required this.name,
    required this.colorValue,
  });

  final String name;
  final int colorValue;

  /// 可选的预设柔和配色盘（8 种日系与自然治愈色）
  static const List<int> palette = [
    0xFF8E83E7, // 柔紫
    0xFFEA8C79, // 橙红
    0xFF70C6AA, // 薄荷绿
    0xFFE2B25F, // 暖黄
    0xFF5B9BD5, // 晴蓝
    0xFFED7D95, // 樱粉
    0xFF4DB6AC, // 青绿
    0xFF9575CD, // 幽紫
  ];

  /// 默认初始分类
  static const List<CategoryItem> defaultCategories = [
    CategoryItem(name: 'ASMR', colorValue: 0xFF8E83E7),
    CategoryItem(name: '剧情向', colorValue: 0xFFEA8C79),
    CategoryItem(name: '治愈系', colorValue: 0xFF70C6AA),
    CategoryItem(name: '环境音', colorValue: 0xFFE2B25F),
  ];

  CategoryItem copyWith({
    String? name,
    int? colorValue,
  }) {
    return CategoryItem(
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'colorValue': colorValue,
      };

  factory CategoryItem.fromJson(Map<String, dynamic> json) {
    return CategoryItem(
      name: json['name'] as String? ?? '未命名分类',
      colorValue: json['colorValue'] as int? ?? 0xFF8E83E7,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CategoryItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          colorValue == other.colorValue;

  @override
  int get hashCode => name.hashCode ^ colorValue.hashCode;

  @override
  String toString() => 'CategoryItem(name: $name, colorValue: 0x${colorValue.toRadixString(16)})';
}
