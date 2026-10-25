import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path_provider/path_provider.dart';

/// 选图并复制进应用数据目录（1.84 引入；1.99.30 起语义为「自选种子图」，
/// 只参与取色、不再铺底 —— 保留独立文件以免设置对话框继续膨胀）。

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
