import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/categories_provider.dart';
import '../../models/category.dart';

/// 弹出编辑或新建分类对话框
/// [initial] 为空时表示新建分类，不为空时表示编辑现有分类
Future<CategoryItem?> showCategoryEditDialog(
  BuildContext context, {
  CategoryItem? initial,
}) {
  return showDialog<CategoryItem>(
    context: context,
    builder: (context) => _CategoryEditDialog(initial: initial),
  );
}

class _CategoryEditDialog extends ConsumerStatefulWidget {
  const _CategoryEditDialog({this.initial});

  final CategoryItem? initial;

  @override
  ConsumerState<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends ConsumerState<_CategoryEditDialog> {
  late final TextEditingController _nameController;
  late int _selectedColor;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initial?.name ?? '');
    _selectedColor = widget.initial?.colorValue ?? CategoryItem.palette.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorText = '请输入分类名称');
      return;
    }
    const reserved = {'全部音声', '最近添加', '正在播放', '收藏夹', '未分类'};
    if (reserved.contains(name)) {
      setState(() => _errorText = '该名称为系统保留视图，不可使用');
      return;
    }

    final categories = ref.read(categoriesProvider);
    final isDuplicate = categories.any(
      (c) => c.name.toLowerCase() == name.toLowerCase() && c.name != widget.initial?.name,
    );
    if (isDuplicate) {
      setState(() => _errorText = '已存在同名分类');
      return;
    }

    Navigator.of(context).pop(CategoryItem(name: name, colorValue: _selectedColor));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isEditing = widget.initial != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Color(_selectedColor).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(_selectedColor),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isEditing ? '编辑分类' : '新建分类',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: '分类名称',
                hintText: '如：治愈系、角色扮演、同人音声',
                errorText: _errorText,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 18),
            Text(
              '标识颜色',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.hintColor,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final colorVal in CategoryItem.palette)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedColor = colorVal),
                      customBorder: const CircleBorder(),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(colorVal),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedColor == colorVal
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : Colors.transparent,
                              width: 2.2,
                            ),
                            boxShadow: _selectedColor == colorVal
                                ? [
                                    BoxShadow(
                                      color: Color(colorVal).withValues(alpha: 0.45),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    )
                                  ]
                                : null,
                          ),
                          child: _selectedColor == colorVal
                              ? const Center(
                                  child: Icon(Icons.check, size: 14, color: Colors.white),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(isEditing ? '保存' : '创建'),
        ),
      ],
    );
  }
}

/// 弹出选择分类对话框（归类弹窗）
/// 返回选中的分类名；若选择移出分类则返回 '未分类'；取消返回 null
Future<String?> showSelectCategoryDialog(
  BuildContext context, {
  required String currentGenre,
  int albumCount = 1,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _SelectCategoryDialog(
      currentGenre: currentGenre,
      albumCount: albumCount,
    ),
  );
}

class _SelectCategoryDialog extends ConsumerWidget {
  const _SelectCategoryDialog({
    required this.currentGenre,
    required this.albumCount,
  });

  final String currentGenre;
  final int albumCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Row(
        children: [
          Icon(Icons.label_outline, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            albumCount > 1 ? '批量设置分类 ($albumCount 张专辑)' : '设置专辑分类',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final item in categories)
                      _CategoryOptionTile(
                        item: item,
                        isSelected: item.name == currentGenre,
                        onTap: () => Navigator.of(context).pop(item.name),
                      ),
                    const Divider(height: 12, indent: 8, endIndent: 8),
                    // 移出分类项
                    InkWell(
                      onTap: () => Navigator.of(context).pop('未分类'),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            Icon(Icons.clear_rounded, size: 16, color: theme.hintColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '未分类 (移出分类)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: theme.hintColor,
                                ),
                              ),
                            ),
                            if (currentGenre == '未分类')
                              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 新建分类快捷入口
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final newCat = await showCategoryEditDialog(context);
                  if (newCat != null) {
                    await ref.read(categoriesProvider.notifier).addCategory(newCat);
                    if (context.mounted) {
                      Navigator.of(context).pop(newCat.name);
                    }
                  }
                },
                icon: const Icon(Icons.add, size: 15),
                label: const Text('新建分类...', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class _CategoryOptionTile extends StatelessWidget {
  const _CategoryOptionTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final CategoryItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: Color(item.colorValue),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
