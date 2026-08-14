import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/category.dart';
import 'library_provider.dart';

class CategoriesNotifier extends StateNotifier<List<CategoryItem>> {
  CategoriesNotifier(this._ref) : super(CategoryItem.defaultCategories);

  final Ref _ref;
  static const _kCategories = 'hiko-custom-categories';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kCategories);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        state = list
            .map((e) => CategoryItem.fromJson(e as Map<String, dynamic>))
            .toList();
        return;
      } catch (_) {
        // 解析失败回退到默认
      }
    }
    state = CategoryItem.defaultCategories;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(state.map((e) => e.toJson()).toList());
    await prefs.setString(_kCategories, jsonStr);
  }

  /// 添加分类（去重）
  Future<bool> addCategory(CategoryItem category) async {
    final trimmedName = category.name.trim();
    if (trimmedName.isEmpty) return false;
    if (state.any((c) => c.name == trimmedName)) return false;

    state = [...state, category.copyWith(name: trimmedName)];
    await _persist();
    return true;
  }

  /// 更新分类（重命名或修改颜色）。若重命名，则同步更新全部已有专辑的 genre
  Future<bool> updateCategory(String oldName, CategoryItem updated) async {
    final newName = updated.name.trim();
    if (newName.isEmpty) return false;
    if (oldName != newName && state.any((c) => c.name == newName)) return false;

    final index = state.indexWhere((c) => c.name == oldName);
    if (index == -1) return false;

    final nextList = [...state];
    nextList[index] = updated.copyWith(name: newName);
    state = nextList;
    await _persist();

    // 若名称变动，同步更新音声库中属于 oldName 的专辑
    if (oldName != newName) {
      final libNotifier = _ref.read(libraryProvider.notifier);
      final albums = _ref.read(libraryProvider);
      final affectedIds = albums
          .where((a) => a.genre == oldName)
          .map((a) => a.id)
          .toSet();
      if (affectedIds.isNotEmpty) {
        await libNotifier.updateAlbums(affectedIds, (a) => a.copyWith(genre: newName));
      }
    }
    return true;
  }

  /// 删除分类。同时将库中该分类下的专辑重置为 '未分类'
  Future<void> removeCategory(String name) async {
    state = state.where((c) => c.name != name).toList();
    await _persist();

    final libNotifier = _ref.read(libraryProvider.notifier);
    final albums = _ref.read(libraryProvider);
    final affectedIds = albums
        .where((a) => a.genre == name)
        .map((a) => a.id)
        .toSet();
    if (affectedIds.isNotEmpty) {
      await libNotifier.updateAlbums(affectedIds, (a) => a.copyWith(genre: '未分类'));
    }
  }

  /// 重新排序分类
  Future<void> reorderCategories(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= state.length) return;
    if (newIndex < 0 || newIndex > state.length) return;

    var actualNewIndex = newIndex;
    if (oldIndex < actualNewIndex) {
      actualNewIndex -= 1;
    }
    final nextList = [...state];
    final item = nextList.removeAt(oldIndex);
    nextList.insert(actualNewIndex, item);
    state = nextList;
    await _persist();
  }
}

final categoriesProvider =
    StateNotifierProvider<CategoriesNotifier, List<CategoryItem>>((ref) {
  final notifier = CategoriesNotifier(ref);
  return notifier;
});
