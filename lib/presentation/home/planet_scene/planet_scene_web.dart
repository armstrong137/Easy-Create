import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// 真实 3D 星球——Web 端实现（iframe 内嵌同一 three.js 场景）
///
/// 与移动端 PlanetScene 同名同接口（planet_scene.dart 条件导出分发）：
/// - iframe 指向打包进 web 构建的 assets/planet_scene/index.html（同源，无 CORS）
/// - iframe 不接收触摸事件；点击进大纲、魔毯点击、双指缩放都交给 Flutter 外层
/// - lod 不显式下发，由场景按指针类型自选：手机浏览器 mid(6144)、桌面 hi——
///   曾强制 lod=hi 导致 iPhone 首次换档上传 8192(约134MB) 明显掉帧
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
    this.autoPrewarm = true,
    this.onReady,
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

  /// 是否允许当前场景在加载后主动预热高清 LOD；相邻预构建页会关闭它以节省显存。
  final bool autoPrewarm;

  /// 场景首帧渲染完成（宿主用它淡出加载期的星球替身）
  final VoidCallback? onReady;

  @override
  State<PlanetScene> createState() => _PlanetSceneState();
}

class _PlanetSceneState extends State<PlanetScene> {
  /// viewType 必须**每个实例唯一**：Flutter web 对同名 viewType 的重复注册
  /// 会被忽略——PageView 滑动销毁重建页面后，新 State 注册的工厂不生效，
  /// 旧工厂闭包把 iframe 写进旧 State → 新 State 的 _iframe 恒为 null，
  /// 缩放/旋转 postMessage 全部打空（真实回归：多星球滑页后手势失效）
  static int _instanceSeq = 0;
  late final int _seq = ++_instanceSeq;
  late final String _viewType = '星球场景_${widget.planet}_$_seq';
  web.HTMLIFrameElement? _iframe;

  /// 场景就绪监听（token 匹配本实例，多颗星球互不串扰）
  late final JSFunction _onMessage = ((web.MessageEvent e) {
    final data = e.data;
    if (data.isA<JSString>() &&
        (data as JSString).toDart == 'sceneReady:$_seq') {
      widget.onReady?.call();
    }
  }).toJS;

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _onMessage);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.HTMLIFrameElement()
        ..src =
            'assets/assets/planet_scene/index.html'
            '?planet=${widget.planet}&spin=${widget.spin}'
            '&stage=${widget.stageScale}'
            '&autoPrewarm=${widget.autoPrewarm ? 1 : 0}'
            '&token=$_seq'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.pointerEvents = 'none';
      _iframe = iframe;
      return iframe;
    });
  }

  @override
  void dispose() {
    web.window.removeEventListener('message', _onMessage);
    super.dispose();
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
    if (old.autoPrewarm != widget.autoPrewarm) {
      _post({'autoPrewarm': widget.autoPrewarm ? 1 : 0});
    }
  }

  void _post(Map<String, double> msg) =>
      _iframe?.contentWindow?.postMessage(msg.jsify(), '*'.toJS);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.diameter,
      // IgnorePointer 必不可少：platform view 会在 Flutter 手势竞技场里
      // 赢走所有手势——iframe 的 pointer-events:none 只管 DOM 层，
      // 不包这层则"点星球进大纲"在 web 上永远不触发（真实回归，
      // 已用 CDP 探针实证：书名可点、星球区域不可点）
      child: IgnorePointer(
        child: HtmlElementView(viewType: _viewType),
      ),
    );
  }
}
