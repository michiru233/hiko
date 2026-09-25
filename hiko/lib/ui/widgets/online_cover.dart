import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../data/settings_store.dart';
import '../covers/cover_cache.dart';

/// 在线作品封面：内存 LRU → 磁盘 LRU → 网络下载（[CoverCache.loadNetwork]）。
///
/// 与本地 [AlbumCover] 保持同一套防社死隐私模糊行为——在线列表同样是封面墙，
/// 不模糊等于把防社死模式开了个口子。σ20 高斯外面必须有 RepaintBoundary，
/// 否则父级每次重绘都会重算全尺寸模糊（1.88.1 的既有约束）。
class OnlineCover extends StatelessWidget {
  const OnlineCover({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.blurSigma = 20,
  });

  /// 封面地址；null 表示该作品没有可用封面，直接给占位图
  final String? url;
  final BoxFit fit;

  /// 模糊强度：列表卡片 20（不可辨识），详情页大图也沿用 20
  final double blurSigma;

  static final _blurFilter = ImageFilter.blur(
    sigmaX: 20,
    sigmaY: 20,
    tileMode: TileMode.clamp,
  );

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: privacyBlur,
      child: _image(context),
      builder: (_, blurred, child) => blurred
          ? ClipRect(
              child: RepaintBoundary(
                child: ImageFiltered(imageFilter: _blurFilter, child: child),
              ),
            )
          : child!,
    );
  }

  Widget _image(BuildContext context) {
    final source = url;
    if (source == null || source.isEmpty) return _placeholder(context);

    final cached = CoverCache.instance.peek(source);
    if (cached != null) return _bytes(cached);

    return FutureBuilder<Uint8List?>(
      future: CoverCache.instance.loadNetwork(source),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) return _placeholder(context);
        return _bytes(bytes);
      },
    );
  }

  Widget _bytes(Uint8List bytes) => Image.memory(
        bytes,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, _, _) => _placeholder(context),
      );

  Widget _placeholder(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.music_note_outlined,
          size: 22,
          color: theme.hintColor.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
