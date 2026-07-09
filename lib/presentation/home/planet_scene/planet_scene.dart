import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 平台分发：移动端 WebView 实现 / Web 端 iframe 实现（同名 PlanetScene）
export 'planet_scene_io.dart'
    if (dart.library.js_interop) 'planet_scene_web.dart';

/// 是否启用真实 3D 星球场景（阶段八 P2-1）
///
/// - Web 构建启用（iframe 内嵌同一 three.js 场景，Safari/WKWebView 同引擎）
/// - 测试环境（FLUTTER_TEST）自动关闭：widget 测试无法创建平台视图，
///   走旧 FragmentShader 路径，既有测试零改动
///   （kIsWeb 须在 Platform 之前短路——dart:io Platform 在 web 运行时不可用）
/// - 也是清单 §12.2 低端机/设置页"高级 3D 效果开关"的接入点（后续接设置页）
final advanced3DProvider = Provider<bool>(
  (_) => kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST'),
);
