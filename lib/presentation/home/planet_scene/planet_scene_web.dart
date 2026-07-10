import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// 真实 3D 星球——Web 端实现（iframe 内嵌同一 three.js 场景）
///
/// 与移动端 PlanetScene 同名同接口（planet_scene.dart 条件导出分发）：
/// - iframe 指向打包进 web 构建的 assets/planet_scene/index.html（同源，无 CORS）
/// - iframe 不接收触摸事件；点击进大纲、魔毯点击、双指缩放都交给 Flutter 外层
/// - 不传 lod：由场景按指针类型自选放大档（手机浏览器降到 4096，桌面用源图上限）
/// - Web 体验版转速取初始值（能量档位变化不动态跟随，正式端在移动 App）
class PlanetScene extends StatefulWidget {
  const PlanetScene({
    super.key,
    required this.planet,
    required this.spin,
    required this.diameter,
    this.stageScale = 1,
    this.zoom = 1,
    this.yaw = 0,
    this.pitch = 0,
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

  /// 拖动转星球的累计偏航/俯仰角（弧度，地球仪手感）
  final double yaw;
  final double pitch;

  @override
  State<PlanetScene> createState() => _PlanetSceneState();
}

class _PlanetSceneState extends State<PlanetScene> {
  /// viewType 必须**每个实例唯一**：Flutter web 对同名 viewType 的重复注册
  /// 会被忽略——PageView 滑动销毁重建页面后，新 State 注册的工厂不生效，
  /// 旧工厂闭包把 iframe 写进旧 State → 新 State 的 _iframe 恒为 null，
  /// 缩放/旋转 postMessage 全部打空（真实回归：多星球滑页后手势失效）
  static int _instanceSeq = 0;
  late final String _viewType = '星球场景_${widget.planet}_${++_instanceSeq}';
  web.HTMLIFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.HTMLIFrameElement()
        ..src =
            'assets/assets/planet_scene/index.html'
            '?planet=${widget.planet}&spin=${widget.spin}'
            '&stage=${widget.stageScale}'
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
    // iframe 同源，postMessage 直达场景（其 message 监听调 setZoom/setRotation）
    if (old.zoom != widget.zoom) {
      _post({'zoom': widget.zoom});
    }
    if (old.yaw != widget.yaw || old.pitch != widget.pitch) {
      _post({'yaw': widget.yaw, 'pitch': widget.pitch});
    }
  }

  void _post(Map<String, double> msg) =>
      _iframe?.contentWindow?.postMessage(msg.jsify(), '*'.toJS);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.diameter,
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
