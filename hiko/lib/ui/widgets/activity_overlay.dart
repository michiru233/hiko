import 'dart:async';

import 'package:flutter/material.dart';

class ActivityProgress {
  const ActivityProgress({
    required this.label,
    this.progress,
    this.processed = 0,
    this.total = 0,
  });

  final String label;
  final double? progress;
  final int processed;
  final int total;
}

/// Application-level notification state. The host is inserted by MaterialApp
/// after Navigator so it remains above dialogs in the same Flutter window.
class ActivityOverlayController extends ChangeNotifier {
  ActivityProgress? _activity;
  String? _toast;
  Timer? _toastTimer;
  bool _attached = false;

  ActivityProgress? get activity => _activity;
  String? get toast => _toast;
  bool get isActive => _activity != null;
  bool get isAttached => _attached;

  void attach() => _attached = true;

  void detach() {
    _attached = false;
    _toastTimer?.cancel();
    _toastTimer = null;
  }

  void start({
    required String label,
    double? progress,
    int processed = 0,
    int total = 0,
  }) {
    _activity = ActivityProgress(
      label: label,
      progress: progress,
      processed: processed,
      total: total,
    );
    notifyListeners();
  }

  void update({String? label, double? progress, int? processed, int? total}) {
    final current = _activity;
    if (current == null) return;
    _activity = ActivityProgress(
      label: label ?? current.label,
      progress: progress ?? current.progress,
      processed: processed ?? current.processed,
      total: total ?? current.total,
    );
    notifyListeners();
  }

  void finish() {
    if (_activity == null) return;
    _activity = null;
    notifyListeners();
  }

  void showToast(
    String message, {
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    _toastTimer?.cancel();
    _toast = message;
    notifyListeners();
    _toastTimer = Timer(duration, () {
      _toast = null;
      _toastTimer = null;
      notifyListeners();
    });
  }
}

final activityOverlayController = ActivityOverlayController();

class ActivityOverlayHost extends StatefulWidget {
  const ActivityOverlayHost({
    super.key,
    required this.child,
    required this.controller,
  });

  final Widget child;
  final ActivityOverlayController controller;

  @override
  State<ActivityOverlayHost> createState() => _ActivityOverlayHostState();
}

class _ActivityOverlayHostState extends State<ActivityOverlayHost> {
  @override
  void initState() {
    super.initState();
    widget.controller.attach();
  }

  @override
  void dispose() {
    widget.controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (widget.controller.activity case final activity?)
            _ActivityBanner(activity: activity),
          if (widget.controller.toast case final message?)
            _ToastBanner(message: message),
        ],
      ),
    );
  }
}

class _ActivityBanner extends StatelessWidget {
  const _ActivityBanner({required this.activity});

  final ActivityProgress activity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = activity.total > 0
        ? ' ${activity.processed} / ${activity.total}'
        : '';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 96,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF292735),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${activity.label}$count',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: activity.progress,
                      minHeight: 4,
                      backgroundColor: Colors.white.withValues(alpha: 0.15),
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastBanner extends StatelessWidget {
  const _ToastBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 96,
      child: IgnorePointer(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: const Color(0xFF292735),
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
