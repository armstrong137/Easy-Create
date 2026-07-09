import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'scene_server.dart';

/// 真实 3D 星球——移动端实现（WebView + three.js 场景层，P1 验证报告定稿路线）
///
/// 与旧 PlanetView/SaturnView 同位替换：
/// - IgnorePointer 包裹——本层不接管任何手势，点击进大纲/长按删除/翻页全归 Flutter
/// - 透明背景——星空仍由下层 Flutter 四档银河图负责
/// - 转速跟随创作能量（didUpdateWidget 时经桥下发，无需重建场景）
/// - 土星的 3D 环带在场景内渲染（前后遮挡天然成立，不再需要 2D 贴层）
class PlanetScene extends ConsumerStatefulWidget {
  const PlanetScene({
    super.key,
    required this.planet,
    required this.spin,
    required this.diameter,
    this.stageScale = 1,
  });

  /// 行星纹理名（earth/mars/jupiter/venus/saturn）
  final String planet;

  /// 自转速度（圈/秒，creative_energy.planetSpin 输出）
  final double spin;

  /// 星球直径（逻辑像素；土星场景自动在此框内缩小球体给环留位）
  final double diameter;

  /// 透明舞台倍率：>1 时初始视觉大小不变，但放大空间更大。
  final double stageScale;

  @override
  ConsumerState<PlanetScene> createState() => _PlanetSceneState();
}

class _PlanetSceneState extends ConsumerState<PlanetScene> {
  WebViewController? _web;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    debugPrint('星球场景: 开始加载 planet=${widget.planet}');
    final port = await ref.read(sceneServerProvider).ensureStarted();
    debugPrint('星球场景: 回环服务端口 $port');
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (u) => debugPrint('星球场景: 页面开始 $u'),
          onPageFinished: (u) => debugPrint('星球场景: 页面完成 $u'),
          onWebResourceError: (e) =>
              debugPrint('星球场景资源错误: ${e.errorCode} ${e.description}'),
        ),
      )
      ..addJavaScriptChannel(
        'SceneBridge',
        onMessageReceived: (_) {
          // FPS 遥测通道（真机验收时读取；此处不驱动 UI）
        },
      )
      ..loadRequest(
        Uri.parse(
          'http://127.0.0.1:$port/index.html'
          '?planet=${widget.planet}&spin=${widget.spin}&stage=${widget.stageScale}',
        ),
      );
    if (!mounted) return;
    setState(() => _web = controller);
  }

  @override
  void didUpdateWidget(PlanetScene old) {
    super.didUpdateWidget(old);
    // 创作能量变化 → 转速经桥下发（星球纹理不会变，novel.planet 不可变）
    if (old.spin != widget.spin) {
      _web?.runJavaScript('setSpin(${widget.spin})');
    }
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    // 场景页透明底，加载过程本身不可见，无需占位渐变
    // （不能用 Opacity(0) 包平台视图：会延迟其初始化）
    return SizedBox.square(
      dimension: widget.diameter,
      child: web == null
          ? const SizedBox.shrink()
          : IgnorePointer(
              // 手势全部留给 Flutter 层（点击进大纲、长按删除、PageView 翻页）
              child: WebViewWidget(controller: web),
            ),
    );
  }
}
