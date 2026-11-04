import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'font_models.dart';
import 'sfnt_parser.dart';

/// 字体库运行时状态。
@immutable
class FontLibraryState {
  const FontLibraryState({this.fonts = const <UserFont>[], this.busy = false});

  /// 按导入时间升序。
  final List<UserFont> fonts;

  /// 导入 / 删除进行中（UI 用来禁用按钮、显示转圈）。
  final bool busy;

  UserFont? byId(String id) {
    for (final font in fonts) {
      if (font.id == id) return font;
    }
    return null;
  }

  FontLibraryState copyWith({List<UserFont>? fonts, bool? busy}) =>
      FontLibraryState(fonts: fonts ?? this.fonts, busy: busy ?? this.busy);
}

/// 导入结果。UI 按 [status] 决定提示文案与是否弹「应用范围」面板。
enum FontImportStatus {
  cancelled,
  ok,
  duplicate,
  tooLarge,
  badFormat,
  libraryFull,
  failed,
}

@immutable
class FontImportResult {
  const FontImportResult(this.status, {this.font, this.info, this.error});

  final FontImportStatus status;

  /// 成功（或重复命中）时的库条目。
  final UserFont? font;

  /// 解析出的字体信息（族名 / 日文覆盖 / 可变字体）。
  final SfntInfo? info;

  final SfntError? error;

  bool get isOk => status == FontImportStatus.ok;
}

/// 字体库：元数据存 SharedPreferences，文件落 `Application Support/fonts/`。
///
/// 为什么元数据不进 [AppSettings]：字体库是一个会增删的集合，塞进
/// 设置模型会让 `copyWith` 多一个 List 字段、备份也多一堆死路径。
/// 这里单独一个 `hiko-user-fonts` 键，与背景图路径一样被备份排除。
class FontLibraryNotifier extends StateNotifier<FontLibraryState> {
  FontLibraryNotifier({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory,
      super(const FontLibraryState());

  static const String prefsKey = 'hiko-user-fonts';

  /// 库内最多保留几个字体（再多也没有意义，且每个都要占内存）。
  static const int maxFonts = 20;

  /// 单文件上限。CJK 字体常见 5–20MB，32MB 已能覆盖绝大多数；
  /// 再大读进内存 + 解析峰值会让 Android 低端机被 LMK 干掉。
  static const int maxBytes = 32 * 1024 * 1024;

  final Future<Directory> Function() _directory;

  /// 只读 prefs + 校验文件存在性，不碰磁盘目录创建。
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    final fonts = <UserFont>[];
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final list = decoded is Map ? decoded['fonts'] : null;
        if (list is List) {
          for (final item in list) {
            final font = UserFont.fromJson(item);
            if (font == null) continue;
            if (!File(font.file).existsSync()) continue;
            fonts.add(font);
          }
        }
      } catch (_) {
        // 坏 JSON 当作空库，不让设置页打不开
      }
    }
    fonts.sort((a, b) => a.addedAt.compareTo(b.addedAt));
    state = FontLibraryState(fonts: fonts);
  }

  UserFont? find(String id) => state.byId(id);

  /// 弹系统文件选择器。`ttf/otf` 用扩展名 + MIME 双保险：
  /// Android 的 `MimeTypeMap` 认不出扩展名时会退成 `*/*`，用户在
  /// 选到别的文件时会由 [importBytes] 的 magic 判定兜住。
  Future<FontImportResult> importFromPicker() async {
    if (state.busy) {
      return const FontImportResult(FontImportStatus.cancelled);
    }
    const group = XTypeGroup(
      label: '字体',
      extensions: <String>['ttf', 'otf'],
      mimeTypes: <String>[
        'font/ttf',
        'font/otf',
        'application/x-font-ttf',
        'application/x-font-otf',
      ],
    );
    final XFile? file;
    try {
      file = await openFile(acceptedTypeGroups: <XTypeGroup>[group]);
    } catch (e) {
      debugPrint('字体选择失败: $e');
      return const FontImportResult(FontImportStatus.failed);
    }
    if (file == null) {
      return const FontImportResult(FontImportStatus.cancelled);
    }
    final name = p.basenameWithoutExtension(file.path);
    try {
      final length = await file.length();
      if (length > maxBytes) {
        return const FontImportResult(FontImportStatus.tooLarge);
      }
      final bytes = await file.readAsBytes();
      return await importBytes(bytes, fallbackName: name);
    } catch (e) {
      debugPrint('读取字体失败: $e');
      return const FontImportResult(FontImportStatus.failed);
    }
  }

  /// 落盘 + 入库。测试直接调这个，不需要真的弹选择器。
  Future<FontImportResult> importBytes(
    Uint8List bytes, {
    String? fallbackName,
  }) async {
    if (state.busy) {
      return const FontImportResult(FontImportStatus.cancelled);
    }
    if (bytes.length > maxBytes) {
      return const FontImportResult(FontImportStatus.tooLarge);
    }
    if (bytes.isEmpty) {
      return const FontImportResult(FontImportStatus.badFormat);
    }

    final id = sha1.convert(bytes).toString().substring(0, 12);
    final existing = state.byId(id);
    if (existing != null) {
      return FontImportResult(FontImportStatus.duplicate, font: existing);
    }
    if (state.fonts.length >= maxFonts) {
      return const FontImportResult(FontImportStatus.libraryFull);
    }

    final parsed = parseSfnt(bytes);
    if (!parsed.isOk) {
      return FontImportResult(FontImportStatus.badFormat, error: parsed.error);
    }
    final info = parsed.info!;

    state = state.copyWith(busy: true);
    try {
      final dir = await _fontDir();
      final target = File(p.join(dir.path, '$id.${info.flavor}'));
      await _writeAtomically(target, bytes);
      final font = UserFont(
        id: id,
        family: (info.family?.trim().isNotEmpty ?? false)
            ? info.family!.trim()
            : (fallbackName?.trim().isNotEmpty ?? false)
            ? fallbackName!.trim()
            : '未命名字体',
        file: target.path,
        bytes: bytes.length,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        japanese: info.hasJapanese,
        format: info.flavor,
      );
      state = state.copyWith(fonts: <UserFont>[...state.fonts, font]);
      await _persist();
      return FontImportResult(FontImportStatus.ok, font: font, info: info);
    } catch (e) {
      debugPrint('保存字体失败: $e');
      return const FontImportResult(FontImportStatus.failed);
    } finally {
      state = state.copyWith(busy: false);
    }
  }

  /// 删除条目与磁盘文件（文件删不掉不阻塞元数据清理）。
  Future<void> remove(UserFont font) async {
    state = state.copyWith(
      fonts: state.fonts.where((f) => f.id != font.id).toList(),
      busy: true,
    );
    try {
      final file = File(font.file);
      if (file.existsSync()) await file.delete();
    } catch (e) {
      debugPrint('删除字体文件失败: $e');
    }
    await _persist();
    if (mounted) state = state.copyWith(busy: false);
  }

  Future<Directory> _fontDir() async {
    final base = await _directory();
    final dir = Directory(p.join(base.path, 'fonts'));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 先写 `.part` 再 rename：中途失败不会留下半截字体被当成可用文件。
  Future<void> _writeAtomically(File target, Uint8List bytes) async {
    final part = File('${target.path}.part');
    await part.writeAsBytes(bytes, flush: true);
    await part.rename(target.path);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      prefsKey,
      jsonEncode(<String, Object?>{
        'version': 1,
        'fonts': <Object?>[for (final font in state.fonts) font.toJson()],
      }),
    );
  }
}

final StateNotifierProvider<FontLibraryNotifier, FontLibraryState>
fontLibraryProvider =
    StateNotifierProvider<FontLibraryNotifier, FontLibraryState>(
      (ref) => FontLibraryNotifier(),
    );
