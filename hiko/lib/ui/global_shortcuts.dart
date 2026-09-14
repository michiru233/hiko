import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_store.dart';
import '../playback/playback_controller.dart';

/// 焦点落在输入框（EditableText 及其后代）内时返回 true。
/// 顶层的可单测守卫：Shortcuts 在焦点链祖先上先于文本输入判定，
/// 不挡住的话搜索框里打空格会误触发播放/暂停（1.41 引入，1.86 移至此处）。
bool isFocusInsideEditable(BuildContext? context) {
  if (context == null) return false;
  return context.findAncestorStateOfType<EditableTextState>() != null;
}

/// 快捷键 Intent：播放/暂停
class TogglePlaybackIntent extends Intent {
  const TogglePlaybackIntent();
}

/// 快捷键 Intent：快退/快进（direction: -1 / 1，步长取设置 seekStepSeconds）
class SeekIntent extends Intent {
  final int direction;
  const SeekIntent(this.direction);
}

/// 快捷键 Intent：上一首/下一首（direction: -1 / 1）
class StepTrackIntent extends Intent {
  final int direction;
  const StepTrackIntent(this.direction);
}

/// 快捷键 Intent：返回上一级（Esc）
class BackIntent extends Intent {
  const BackIntent();
}

/// 全局快捷键（1.86）：挂在 MaterialApp.builder——Navigator 之上，
/// 详情页 / 全屏播放页 / 对话框打开时同样生效。此前这些键只接在
/// HomeScreen 内部，push 出去的页面全部收不到，是"mac 没快捷键"的根因。
/// 空格=播放/暂停；←→=快退/快进（步长=设置里的快进秒数）；↑↓=切曲；
/// Esc=返回上一级（pop 最顶层路由，无路由可退时 no-op）。
class HikoGlobalShortcuts extends ConsumerWidget {
  const HikoGlobalShortcuts({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  bool get _typing =>
      isFocusInsideEditable(FocusManager.instance.primaryFocus?.context);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.space): TogglePlaybackIntent(),
        SingleActivator(LogicalKeyboardKey.arrowLeft): SeekIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowRight): SeekIntent(1),
        SingleActivator(LogicalKeyboardKey.arrowUp): StepTrackIntent(-1),
        SingleActivator(LogicalKeyboardKey.arrowDown): StepTrackIntent(1),
        SingleActivator(LogicalKeyboardKey.escape): BackIntent(),
      },
      child: Actions(
        actions: {
          TogglePlaybackIntent: CallbackAction<TogglePlaybackIntent>(
            onInvoke: (_) {
              if (_typing) return null;
              ref.read(playbackProvider.notifier).toggle();
              return null;
            },
          ),
          SeekIntent: CallbackAction<SeekIntent>(
            onInvoke: (intent) {
              if (_typing) return null;
              final controller = ref.read(playbackProvider.notifier);
              final pos = ref.read(playbackProvider).position;
              final step = ref.read(settingsProvider).seekStepSeconds;
              controller.seek(pos + intent.direction * step);
              return null;
            },
          ),
          StepTrackIntent: CallbackAction<StepTrackIntent>(
            onInvoke: (intent) {
              if (_typing) return null;
              final controller = ref.read(playbackProvider.notifier);
              if (intent.direction < 0) {
                controller.prev();
              } else {
                controller.next();
              }
              return null;
            },
          ),
          BackIntent: CallbackAction<BackIntent>(
            onInvoke: (_) {
              navigatorKey.currentState?.maybePop();
              return null;
            },
          ),
        },
        child: child,
      ),
    );
  }
}
