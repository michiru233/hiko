import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../settings_store.dart';
import 'kikoeru_client.dart';
import 'online_models.dart';

/// asmr.one 账号状态（1.93.0，裁决 Q1=A / Q7=A）。
///
/// 只存 JWT，**不做 refresh**：实测服务端没有 refresh 端点，JWT 有效期 30 天，
/// 到期只能重新登录。所以这里的状态机很薄 —— 令牌在就带着它发请求，
/// 服务端说无效就清掉并提示重登。
@immutable
class OnlineAccountState {
  const OnlineAccountState({
    this.restoring = true,
    this.token = '',
    this.user = OnlineUser.guest,
    this.busy = false,
    this.error,
  });

  /// 启动后正在用磁盘上的令牌问一次服务端。**首帧要区分「未登录」与「还不知道」**，
  /// 否则每次冷启动都会闪一下「请先登录」。
  final bool restoring;

  /// 原始 JWT（已剥掉 `Bearer ` / 噪声前缀），空串表示未登录
  final String token;
  final OnlineUser user;

  /// 正在登录中（按钮转圈用）
  final bool busy;
  final String? error;

  bool get loggedIn => token.isNotEmpty && user.loggedIn;

  /// 展示名；服务端没给名字时退到「已登录」，不显示空白
  String get displayName {
    final name = user.name.trim();
    if (name.isNotEmpty) return name;
    return loggedIn ? '已登录' : '未登录';
  }

  /// 状态已确定（不再处于恢复中），UI 可以据此决定是否显示登录引导
  bool get settled => !restoring;

  OnlineAccountState copyWith({
    bool? restoring,
    String? token,
    OnlineUser? user,
    bool? busy,
    String? error,
    bool clearError = false,
  }) =>
      OnlineAccountState(
        restoring: restoring ?? this.restoring,
        token: token ?? this.token,
        user: user ?? this.user,
        busy: busy ?? this.busy,
        error: clearError ? null : (error ?? this.error),
      );
}

class OnlineAccountNotifier extends StateNotifier<OnlineAccountState> {
  OnlineAccountNotifier(this._ref) : super(const OnlineAccountState());

  /// 令牌的持久化键。**刻意不进 `AppSettings`**：那是给 UI 直接渲染的设置，
  /// 而令牌是凭证，混进去会让它出现在所有 watch settings 的构建路径上。
  static const _kToken = 'hiko-online-token';

  final Ref _ref;

  KikoeruClient _client({String? token}) {
    final settings = _ref.read(settingsProvider);
    return KikoeruClient(
      baseUrl: settings.onlineServer,
      proxy: settings.scrapeProxy,
      token: token ?? state.token,
    );
  }

  /// 冷启动恢复：读磁盘令牌，拿它问一次 `/api/auth/me`。
  ///
  /// 三种结果分开处理：
  /// - 服务端说 `loggedIn: false`（令牌过期/被换掉）→ 清令牌，落到未登录
  /// - 网络不通 → **保留**令牌。断网不等于令牌失效，不该罚用户重新登录
  /// - 正常 → 落到已登录
  Future<void> restore() async {
    final saved = await _readToken();
    if (saved.isEmpty) {
      state = state.copyWith(restoring: false);
      return;
    }
    try {
      final user = await _client(token: saved).fetchMe();
      if (!user.loggedIn) {
        await _clearToken();
        state = const OnlineAccountState(restoring: false);
        return;
      }
      state = state.copyWith(
        restoring: false,
        token: saved,
        user: user,
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(
        restoring: false,
        token: saved,
        user: const OnlineUser(loggedIn: true),
        clearError: true,
      );
    }
  }

  /// 登录。成功返回 null，失败返回可直接展示的中文文案。
  ///
  /// 走不带令牌的副本发请求（网页端在登录端点上把 Authorization 置空，
  /// 见 `KikoeruClient.login`）。
  Future<String?> login({
    required String name,
    required String password,
  }) async {
    final account = name.trim();
    if (account.isEmpty) return '请填写用户名';
    if (password.isEmpty) return '请填写密码';
    if (state.busy) return null;

    state = state.copyWith(busy: true, clearError: true);
    try {
      final token = await _client(token: '').login(
        name: account,
        password: password,
      );
      // 再用令牌确认一次身份（顺带校验令牌真的能用）。这一步失败不致命：
      // 令牌已经拿到手，只是名字暂时用用户输入的顶上。
      OnlineUser user;
      try {
        final fetched = await _client(token: token).fetchMe();
        user = fetched.loggedIn
            ? fetched
            : OnlineUser(loggedIn: true, name: account);
      } catch (_) {
        user = OnlineUser(loggedIn: true, name: account);
      }
      await _saveToken(token);
      state = state.copyWith(
        busy: false,
        token: token,
        user: user,
        clearError: true,
      );
      return null;
    } on KikoeruException catch (e) {
      state = state.copyWith(busy: false, error: e.message);
      return e.message;
    } catch (e) {
      const message = '登录失败，请检查网络后重试';
      state = state.copyWith(busy: false, error: message);
      return message;
    }
  }

  /// 登出。**没有服务端端点**（实测）—— asmr.one 网页版登出就是删掉本地令牌，
  /// 所以这里也只清本地。令牌在服务端仍然有效直到自然过期。
  Future<void> logout() async {
    await _clearToken();
    state = const OnlineAccountState(restoring: false);
  }

  /// 业务请求里撞上 401 时调用：清令牌 + 记一条过期提示（裁决 Q7=A，不静默重试）。
  Future<void> handleUnauthorized() async {
    if (state.token.isEmpty) return;
    await _clearToken();
    state = const OnlineAccountState(
      restoring: false,
      error: '登录已过期，请重新登录',
    );
  }

  Future<String> _readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return KikoeruClient.sanitizeToken(prefs.getString(_kToken) ?? '');
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
  }
}

final onlineAccountProvider =
    StateNotifierProvider<OnlineAccountNotifier, OnlineAccountState>(
  (ref) => OnlineAccountNotifier(ref),
);

/// 账号状态已确定且已登录
final onlineLoggedInProvider = Provider<bool>(
  (ref) => ref.watch(onlineAccountProvider.select((s) => s.loggedIn)),
);
