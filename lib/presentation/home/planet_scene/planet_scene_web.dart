import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

/// 真实 3D 星球——Web 端实现（iframe 内嵌同一 three.js 场景）
///
/// 与移动端 PlanetScene 同名同接口（planet_scene.dart 条件导出分发）：
/// - iframe 指向打包进 web 构建的 assets/planet_scene/index.html（同源，无 CORS）
/// - iframe 接收触摸事件，交给场景内 OrbitControls 做拖拽旋转与双指缩放
/// - 五颗球 albedo 走 apptex 相对路径参数（移动端为回环服务的 /app-textures/）
/// - Web 体验版转速取初始值（能量档位变化不动态跟随，正式端在移动 App）
class PlanetScene extends StatelessWidget {
  PlanetScene({
    super.key,
    required this.planet,
    required this.spin,
    required this.diameter,
  }) {
    // 每颗星球注册一次 iframe 工厂（重复注册同名 viewType 会被忽略/覆盖，无害）
    ui_web.platformViewRegistry.registerViewFactory('星球场景_$planet', (_) {
      final iframe = web.HTMLIFrameElement()
        ..src =
            'assets/assets/planet_scene/index.html'
            '?planet=$planet&spin=$spin&apptex=../../textures/'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
  }

  /// 行星纹理名（earth/mars/jupiter/venus/saturn）
  final String planet;

  /// 自转速度（圈/秒，creative_energy.planetSpin 输出）
  final double spin;

  /// 星球直径（逻辑像素；土星场景自动在此框内缩小球体给环留位）
  final double diameter;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: diameter,
      child: HtmlElementView(viewType: '星球场景_$planet'),
    );
  }
}
