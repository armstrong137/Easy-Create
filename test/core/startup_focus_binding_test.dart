import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novel_app/core/startup_focus_binding.dart';

class _TestBinding extends AutomatedTestWidgetsFlutterBinding
    with StartupFocusGuard {}

class _Observer extends WidgetsBindingObserver {
  _Observer(this.isLaidOut);

  final bool Function() isLaidOut;
  final events = <ViewFocusEvent>[];
  final layoutAtNotification = <bool>[];

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    events.add(event);
    layoutAtNotification.add(isLaidOut());
  }
}

void main() {
  final binding = _TestBinding();
  final observer = _Observer(
    () =>
        binding.renderViews.isNotEmpty &&
        binding.renderViews.every((view) => view.child?.hasSize == true),
  );
  binding.addObserver(observer);
  final focused = ViewFocusEvent(
    viewId: binding.platformDispatcher.implicitView!.viewId,
    state: ViewFocusState.focused,
    direction: ViewFocusDirection.forward,
  );
  final unfocused = ViewFocusEvent(
    viewId: binding.platformDispatcher.implicitView!.viewId,
    state: ViewFocusState.unfocused,
    direction: ViewFocusDirection.undefined,
  );
  // testWidgets 自己也会预热帧，因此必须在注册测试前模拟真实启动事件。
  binding.handleViewFocusChanged(unfocused);
  binding.handleViewFocusChanged(focused);
  final beforeLayout = List<ViewFocusEvent>.of(observer.events);
  testWidgets('首帧布局后才转发最新焦点，之后即时转发', (tester) async {
    try {
      expect(beforeLayout, isEmpty);
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(width: 40, height: 40),
        ),
      );
      expect(observer.events, [focused]);
      expect(observer.layoutAtNotification, [true]);
      binding.handleViewFocusChanged(unfocused);
      expect(observer.events, [focused, unfocused]);
      expect(tester.takeException(), isNull);
    } finally {
      binding.removeObserver(observer);
    }
  });
}
