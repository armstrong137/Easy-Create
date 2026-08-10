import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../home/planet_scene/scene_server.dart';
import 'tree_scene_controller.dart';
import 'tree_scene_protocol.dart';

class TreeScene extends ConsumerStatefulWidget {
  const TreeScene({
    super.key,
    required this.controller,
    this.active = true,
    this.visible = true,
    this.onReady,
  });

  final TreeSceneController controller;
  final bool active;
  final bool visible;
  final VoidCallback? onReady;

  @override
  ConsumerState<TreeScene> createState() => _TreeSceneState();
}

class _TreeSceneState extends ConsumerState<TreeScene>
    with WidgetsBindingObserver {
  WebViewController? _web;

  bool get _shouldRender => widget.active && widget.visible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final port = await ref.read(sceneServerProvider).ensureStarted();
    final model = Uri.encodeQueryComponent('/tree-model/magic_tree.glb');
    late final WebViewController controller;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFDF6EC))
      ..addJavaScriptChannel(
        'TreeSceneBridge',
        onMessageReceived: (message) async {
          final decoded = jsonDecode(message.message);
          if (decoded is! Map) return;
          final event = TreeSceneEvent.fromJson(
            Map<String, Object?>.from(decoded),
          );
          await widget.controller.handleEvent(event);
          if (event.type == 'scene.ready' &&
              event.sessionId == widget.controller.sessionId) {
            widget.onReady?.call();
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            widget.controller.attachSender((command) {
              return controller.runJavaScript(
                'window.EasyCreateTreeScene.receive(${jsonEncode(command)})',
              );
            });
            await widget.controller.initializeTransport();
            if (!_shouldRender) widget.controller.pause();
          },
        ),
      )
      ..loadRequest(
        Uri.parse('http://127.0.0.1:$port/tree/index.html?model=$model'),
      );
    if (!mounted) return;
    setState(() => _web = controller);
  }

  @override
  void didUpdateWidget(TreeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    final was = oldWidget.active && oldWidget.visible;
    if (was == _shouldRender) return;
    _shouldRender ? widget.controller.resume() : widget.controller.pause();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _shouldRender) {
      widget.controller.resume();
    } else if (state != AppLifecycleState.resumed) {
      widget.controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.disposeAssets();
    widget.controller.detachSender();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    if (web == null) return const SizedBox.expand();
    return IgnorePointer(child: WebViewWidget(controller: web));
  }
}
