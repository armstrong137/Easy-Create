import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// 真实 3D 星球——Web 端实现（iframe 内嵌同一 three.js 场景）
///
/// 与移动端 PlanetScene 同名同接口（planet_scene.dart 条件导出分发）：
/// - iframe 指向打包进 web 构建的 assets/planet_scene/index.html（同源，无 CORS）
/// - iframe 不接收触摸事件；点击进大纲、魔毯点击、双指缩放都交给 Flutter 外层
/// - 五颗球 albedo 走 apptex 相对路径参数（移动端为回环服务的 /app-textures/）
/// - Web 体验版转速取初始值（能量档位变化不动态跟随，正式端在移动 App）
class PlanetScene extends StatefulWidget {
  const PlanetScene({
    super.key,
    required this.planet,
    required this.spin,
    required this.diameter,
    this.stageScale = 1,
    this.zoom = 1,
  });

  /// 行星纹理名（earth/mars/jupiter/venus/saturn）
  final String planet;

  /// 自转速度（圈/秒，creative_energy.planetSpin 输出）
  final double spin;

  /// 星球直径（逻辑像素；土星场景自动在此框内缩小球体给环留位）
  final double diameter;

  /// 透明舞台倍率：>1 时初始视觉大小不变，但放大空间更大。
  final double stageScale;

  /// 缩放倍率：postMessage 下发到场景做**镜头推进**（放大后依然清晰且居中）
  final double zoom;

  @override
  State<PlanetScene> createState() => _PlanetSceneState();
}

class _PlanetSceneState extends State<PlanetScene> {
  late final String _viewType = '星球场景_${widget.planet}';
  web.HTMLIFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    // 每颗星球注册一次 iframe 工厂（重复注册同名 viewType 会被忽略/覆盖，无害）
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.HTMLIFrameElement()
        ..src =
            'assets/assets/planet_scene/index.html'
            '?planet=${widget.planet}&spin=${widget.spin}'
            '&stage=${widget.stageScale}&apptex=../textures/'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'none';
      _iframe = iframe;
      return iframe;
    });
  }

  @override
  void didUpdateWidget(PlanetScene old) {
    super.didUpdateWidget(old);
    if (old.zoom != widget.zoom) {
      // iframe 同源，postMessage 直达场景（其 message 监听调 setZoom）
      _iframe?.contentWindow?.postMessage(
        {'zoom': widget.zoom}.jsify(),
        '*'.toJS,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.diameter,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
