import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import 'tree_scene_controller.dart';
import 'tree_scene_protocol.dart';

class TreeScene extends StatefulWidget {
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
  State<TreeScene> createState() => _TreeSceneState();
}

class _TreeSceneState extends State<TreeScene> {
  static int _instances = 0;
  late final int _instance = ++_instances;
  late final String _token = 'tree-$_instance';
  late final String _viewType = '实时魔树场景_$_instance';
  web.HTMLIFrameElement? _iframe;
  Timer? _readyTimer;

  bool get _shouldRender => widget.active && widget.visible;

  late final JSFunction _onMessage = ((web.MessageEvent event) {
    final frame = _iframe;
    if (frame == null || event.source != frame.contentWindow) return;
    final data = event.data;
    if (!data.isA<JSString>()) return;
    final decoded = jsonDecode((data as JSString).toDart);
    if (decoded is! Map ||
        decoded['source'] != 'easy-create-tree-scene' ||
        decoded['token'] != _token ||
        decoded['event'] is! Map) {
      return;
    }
    final sceneEvent = TreeSceneEvent.fromJson(
      Map<String, Object?>.from(decoded['event'] as Map),
    );
    if (sceneEvent.sessionId != widget.controller.sessionId) return;
    widget.controller.handleEvent(sceneEvent);
    if (sceneEvent.type == 'scene.ready') {
      _readyTimer?.cancel();
      widget.onReady?.call();
    }
  }).toJS;

  @override
  void initState() {
    super.initState();
    _readyTimer = Timer(
      const Duration(seconds: 8),
      widget.controller.markStartupTimedOut,
    );
    web.window.addEventListener('message', _onMessage);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.HTMLIFrameElement()
        ..src = _sceneSource()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'transparent'
        ..style.pointerEvents = 'none'
        ..style.display = widget.visible ? '' : 'none';
      _iframe = iframe;
      iframe.addEventListener(
        'load',
        ((web.Event _) {
          widget.controller.attachSender((command) => _post(command));
          widget.controller.initializeTransport();
          if (!_shouldRender) widget.controller.pause();
        }).toJS,
      );
      return iframe;
    });
  }

  String _sceneSource() =>
      'assets/assets/tree_scene/index.html'
      '?token=${Uri.encodeQueryComponent(_token)}'
      '&session=${Uri.encodeQueryComponent(widget.controller.sessionId)}'
      '&model=${Uri.encodeQueryComponent('../3d/magic_tree/magic_tree.glb')}';

  void _post(Map<String, Object?> command) {
    _iframe?.contentWindow?.postMessage(
      {
        'source': 'easy-create-flutter',
        'token': _token,
        'command': command,
      }.jsify(),
      '*'.toJS,
    );
  }

  @override
  void didUpdateWidget(TreeScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _iframe?.style.display = widget.visible ? '' : 'none';
    }
    final was = oldWidget.active && oldWidget.visible;
    if (was == _shouldRender) return;
    _shouldRender ? widget.controller.resume() : widget.controller.pause();
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    widget.controller.disposeAssets();
    widget.controller.detachSender();
    _iframe?.src = 'about:blank';
    _iframe?.remove();
    _iframe = null;
    web.window.removeEventListener('message', _onMessage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(child: HtmlElementView(viewType: _viewType));
  }
}
