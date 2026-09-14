import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/settings_store.dart';
import 'theme.dart';

/// 选择并导入背景图（1.84）：file_selector 三端通吃（Android 端插件会把 SAF
/// 内容拷到缓存真路径再返回），原图直拷进应用数据目录——不解码重压，
/// 显示端解码时限制分辨率控内存。返回落地路径，取消返回 null。
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

/// ponytail: 背景固定按 2560px 宽解码——>4K 屏且关模糊时会略软；
/// 升级路径是跟随窗口尺寸动态重解码。模糊/不透明度场景完全够用。
const int _kBackgroundDecodeWidth = 2560;

class LoadedBackgroundImage {
  const LoadedBackgroundImage(this.path, this.image);
  final String path;
  final ui.Image? image; // 解码失败为 null（渲染层直接不画）
}

/// 背景图常驻解码缓存（1.86）。此前走 Image.file+ImageCache：全屏大图与封面
/// 缩略图挤同一份 100MB 缓存，换页被挤出后要从磁盘重解码——Android 详情页
/// "背景过一会才出现"、返回主页卡顿、mac 全屏页进入卡顿皆源于此。
/// 改为模块级 ui.Image 强引用：同路径只解码一次、永不逐出（幂等，可重复调用）。
final ValueNotifier<LoadedBackgroundImage?> backgroundLoadedImage =
    ValueNotifier(null);


Future<void> loadBackgroundImage(String path) async {
  final current = backgroundLoadedImage.value;
  if (path.isEmpty) {
    current?.image?.dispose();
    backgroundLoadedImage.value = null;
    return;
  }
  if (current != null && current.path == path && current.image != null) return;
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: _kBackgroundDecodeWidth,
    );
    final image = (await codec.getNextFrame()).image;
    current?.image?.dispose();
    backgroundLoadedImage.value = LoadedBackgroundImage(path, image);
  } catch (_) {
    // 文件损坏/被删：与解码失败一致，渲染层退回主题底色
    current?.image?.dispose();
    backgroundLoadedImage.value = LoadedBackgroundImage(path, null);
  }
}

/// 根层背景：主题底色 → 背景图（不透明度 + 模糊）→ 跟随主题的可读性薄纱
/// （浅色叠白纱、深色叠黑纱，固定值不暴露给用户；未启用背景时不渲染任何覆盖）。
/// 图层整体包 RepaintBoundary：全屏模糊只在图片变化时重栅格化，
/// 页面滚动/路由动画不再连带（1.86 性能修复的关键）。
class BackgroundLayer extends StatelessWidget {
  const BackgroundLayer({super.key, required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final path = settings.backgroundPath;

    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(color: dark ? HikoColors.darkBg : HikoColors.lightBg),
        ),
        if (path.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<LoadedBackgroundImage?>(
                valueListenable: backgroundLoadedImage,
                builder: (_, loaded, _) {
                  if (loaded == null ||
                      loaded.path != path ||
                      loaded.image == null) {
                    return const SizedBox.shrink();
                  }
                  Widget img = RawImage(
                    image: loaded.image,
                    fit: BoxFit.cover,
                  );
                  final blur = settings.backgroundBlur;
                  if (blur > 0) {
                    img = ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: img,
                    );
                  }
                  return Opacity(
                    opacity: settings.backgroundOpacity,
                    child: img,
                  );
                },
              ),
            ),
          ),
        if (path.isNotEmpty)
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
