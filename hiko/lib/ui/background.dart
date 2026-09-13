import 'dart:io';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/settings_store.dart';
import 'theme.dart';

/// 选择并导入背景图（1.84）：file_selector 三端通吃（Android 端插件会把 SAF
/// 内容拷到缓存真路径再返回），原图直拷进应用数据目录——不解码重压，
/// 显示端经 cacheWidth 限制解码分辨率控内存。返回落地路径，取消返回 null。
Future<String?> pickAndStoreBackgroundImage(String oldPath) async {
  const group = XTypeGroup(
    label: '图片',
    extensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp'],
  );
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null) return null;
  final dir = await getApplicationSupportDirectory();
  final ext = file.path.contains('.')
      ? file.path.split('.').last.toLowerCase()
      : 'png';
  final dst = File('${dir.path}${Platform.pathSeparator}background.$ext');
  await file.saveTo(dst.path);
  // 旧背景扩展名可能不同，落地成功后再清理
  if (oldPath.isNotEmpty && oldPath != dst.path) {
    try {
      File(oldPath).deleteSync();
    } catch (_) {}
  }
  return dst.path;
}

/// 根层背景：主题底色 → 背景图（不透明度 + 模糊）→ 跟随主题的可读性薄纱
/// （浅色叠白纱、深色叠黑纱，固定值不暴露给用户；未启用背景时不渲染任何覆盖）。
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final path = settings.backgroundPath;
    final hasImage = path.isNotEmpty;

    Widget? image;
    if (hasImage) {
      final size = MediaQuery.sizeOf(context);
      final pw = (size.width * MediaQuery.devicePixelRatioOf(context))
          .round()
          .clamp(1, 4096);
      final blur = settings.backgroundBlur;
      Widget img = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: pw,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
      if (blur > 0) {
        img = ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: img,
        );
      }
      image = Positioned.fill(
        child: Opacity(opacity: settings.backgroundOpacity, child: img),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: dark ? HikoColors.darkBg : HikoColors.lightBg),
        ),
        if (image != null) image,
        if (image != null)
          Positioned.fill(
            child: ColoredBox(
              color: dark
                  ? Colors.black.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
      ],
    );
  }
}
