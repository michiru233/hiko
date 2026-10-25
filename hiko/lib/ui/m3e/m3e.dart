/// M3E 设计系统层的唯一对外出口。
///
/// 业务代码**只 import 这一个文件**（`import '../m3e/m3e.dart';`），
/// 不直接深入 `tokens/` 或 `components/`。这样将来整体替换实现（例如官方
/// Material 库内置 M3E 之后切过去）只需要改这个 barrel 与内部实现，
/// 调用点一行不动。
///
/// 分层（见 plan-hiko-m3e-redesign.md §4.1）：
/// - `tokens/` 纯数值，无 widget，可单独跑单测
/// - `theme/` 把 token 装配成 InheritedWidget
/// - `components/` 只依赖 tokens + theme，**不依赖任何业务代码**
library;

export 'adaptive/hiko_breakpoints.dart';
export 'adaptive/hiko_shell.dart';
export 'components/actions/m3e_button.dart';
export 'components/actions/m3e_button_group.dart';
export 'components/actions/m3e_fab.dart';
export 'components/actions/m3e_icon_button.dart';
export 'components/inputs/m3e_slider.dart';
export 'components/motion/m3e_pressable.dart';
export 'components/progress/m3e_loading_indicator.dart';
export 'components/surfaces/m3e_card.dart';
export 'components/surfaces/m3e_sheet.dart';
export 'components/surfaces/m3e_toolbar.dart';
export 'components/selection/m3e_chip.dart';
export 'components/surfaces/m3e_list.dart';
export 'navigation/m3e_app_bar.dart';
export 'navigation/m3e_floating_header.dart';
export 'navigation/m3e_nav_badge.dart';
export 'navigation/m3e_nav_bar.dart';
export 'navigation/m3e_nav_rail.dart';
export 'navigation/m3e_navigation_destination.dart';
export 'theme/m3e_theme.dart';
export 'theme/m3e_theme_builder.dart';
export 'tokens/color_tokens.dart';
export 'tokens/elevation_tokens.dart';
export 'tokens/motion_tokens.dart';
export 'tokens/shape_tokens.dart';
export 'tokens/type_tokens.dart';
