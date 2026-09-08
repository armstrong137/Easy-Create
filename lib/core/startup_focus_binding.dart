import 'dart:ui';

import 'package:flutter/widgets.dart';

/// 浏览器初始焦点可能早于控件布局，几何焦点遍历必须等首帧布局完成。
mixin StartupFocusGuard on WidgetsBinding {
  bool _firstLayoutComplete = false;
  ViewFocusEvent? _pendingFocus;

  @override
  void handleViewFocusChanged(ViewFocusEvent event) {
    if (!_firstLayoutComplete) {
      _pendingFocus = event;
      return;
    }
    super.handleViewFocusChanged(event);
  }

  @override
  void drawFrame() {
    super.drawFrame();
    if (_firstLayoutComplete || rootElement == null) return;
    _firstLayoutComplete = true;
    final event = _pendingFocus;
    _pendingFocus = null;
    if (event != null) super.handleViewFocusChanged(event);
  }
}

class StartupWidgetsBinding extends WidgetsFlutterBinding
    with StartupFocusGuard {}
