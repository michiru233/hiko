import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/categories_provider.dart';
import '../../models/category.dart';
import '../m3e/m3e.dart';

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
  ConsumerState<_CategoryEditDialog> createState() =>
      _CategoryEditDialogState();
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
    const reserved = {'本地音声', '最近添加', '正在播放', '收藏夹', '未分类'};
    if (reserved.contains(name)) {
      setState(() => _errorText = '该名称为系统保留视图，不可使用');
      return;
    }

    final categories = ref.read(categoriesProvider);
    final isDuplicate = categories.any(
      (c) =>
          c.name.toLowerCase() == name.toLowerCase() &&
          c.name != widget.initial?.name,
    );
    if (isDuplicate) {
      setState(() => _errorText = '已存在同名分类');
      return;
    }

    Navigator.of(context)
        .pop(CategoryItem(name: name, colorValue: _selectedColor));
  }

  @override
  Widget build(BuildContext context) {
    final theme = M3ETheme.of(context);
    final isEditing = widget.initial != null;

    return M3EDialog(
      // 表单对话框不比内容面板，420 已经把输入框与色板排得很松
      maxWidth: 420,
      leading: _ColorDot(colorValue: _selectedColor, size: 24),
      title: isEditing ? '编辑分类' : '新建分类',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '分类名称',
              hintText: '如：治愈系、角色扮演、同人音声',
              errorText: _errorText,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: M3EShape.radius(M3EShape.sm),
              ),
            ),
            onChanged: (_) {
              if (_errorText != null) setState(() => _errorText = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 18),
          Text(
            '标识颜色',
            style: theme.type.labelMedium.copyWith(
              color: theme.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final colorVal in CategoryItem.palette)
                M3EPressable(
                  onTap: () => setState(() => _selectedColor = colorVal),
                  borderRadius: M3EShape.radius(M3EShape.full),
                  pressScale: 0.92,
                  semanticLabel: '颜色 ${colorVal.toRadixString(16)}',
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: AnimatedContainer(
                        duration: theme.motion.stateLayerDuration,
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Color(colorVal),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _selectedColor == colorVal
                                ? theme.colors.onSurface
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: _selectedColor == colorVal
                            ? Center(
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: theme.colors.surface,
                                ),
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
      actions: <Widget>[
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        M3EButton(label: isEditing ? '保存' : '创建', onPressed: _submit),
      ],
    );
  }
}

/// 分类色点：外圈 18% 底 + 内芯实色。
class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.colorValue, this.size = 28});

  final int colorValue;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(colorValue).withValues(alpha: 0.18),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: size * 0.36,
          height: size * 0.36,
          decoration: BoxDecoration(
            color: Color(colorValue),
            shape: BoxShape.circle,
          ),
        ),
      ),
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
    final theme = M3ETheme.of(context);
    final categories = ref.watch(categoriesProvider);

    return M3EDialog(
      maxWidth: 420,
      leading: Icon(
        Icons.label_outline_rounded,
        size: 24,
        color: theme.colors.primary,
      ),
      title: albumCount > 1 ? '批量设置分类 ($albumCount 张专辑)' : '设置专辑分类',
      // 正文自带滚动 + 行要贴边（列表行的选中块自己带圆角）
      scrollable: false,
      contentPadding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      content: SingleChildScrollView(
        child: M3EList(
          children: <Widget>[
            for (final item in categories)
              M3EListItem(
                title: item.name,
                leading: _ColorDot(colorValue: item.colorValue, size: 18),
                selected: item.name == currentGenre,
                onTap: () => Navigator.of(context).pop(item.name),
              ),
            const _ThinDivider(),
            M3EListItem(
              title: '未分类 (移出分类)',
              leading: Icon(
                Icons.clear_rounded,
                size: 18,
                color: theme.colors.onSurfaceVariant,
              ),
              selected: currentGenre == '未分类',
              onTap: () => Navigator.of(context).pop('未分类'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        M3EButton(
          label: '新建分类…',
          variant: M3EButtonVariant.tonal,
          icon: const Icon(Icons.add_rounded),
          onPressed: () async {
            final newCat = await showCategoryEditDialog(context);
            if (newCat != null) {
              await ref.read(categoriesProvider.notifier).addCategory(newCat);
              if (context.mounted) {
                Navigator.of(context).pop(newCat.name);
              }
            }
          },
        ),
        M3EButton(
          label: '取消',
          variant: M3EButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// 1dp `outlineVariant` 分隔线（不用 Material `Divider`，它读旧主题桥的色）。
class _ThinDivider extends StatelessWidget {
  const _ThinDivider();

  @override
  Widget build(BuildContext context) {
    final colors = M3ETheme.of(context).colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: SizedBox(
        height: 1,
        child: ColoredBox(color: colors.outlineVariant),
      ),
    );
  }
}
