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
    this.zoom = 1,
    this.yaw = 0,
    this.pitch = 0,
    this.autoPrewarm = true,
    this.active = true,
    this.visible = true,
    this.snapshotRequestId = 0,
    this.onReady,
    this.onSnapshot,
  });

  /// 行星纹理名（earth/mars/jupiter/venus/saturn）
  final String planet;

  /// 自转速度（圈/秒，creative_energy.planetSpin 输出）
  final double spin;

  /// 星球直径（逻辑像素；土星场景自动在此框内缩小球体给环留位）
  final double diameter;

  /// 透明舞台倍率：>1 时初始视觉大小不变，但放大空间更大。
  final double stageScale;

  /// 缩放倍率：下发到场景做**镜头推进**（重新渲染，放大后依然清晰且居中）
  final double zoom;

  /// 拖动转星球的累计偏航/俯仰角（弧度，地球仪手感）
  final double yaw;
  final double pitch;

  /// 是否允许场景在首屏稳定后主动预热高清 LOD。
  ///
  /// 首页会预构建相邻页来减少切星球卡顿；相邻页只暖基础场景，避免多颗星球同时抢高清显存。
  final bool autoPrewarm;

  /// 是否为当前可见页：非当前页暂停场景渲染（多球常驻越用越卡）
  final bool active;

  /// 首页路由是否在最顶（未被大纲页覆盖）。移动端 WebView 全程存活、不销毁；
  /// 覆盖时暂停渲染省电，返回即恢复（接口与 web 端一致）。
  final bool visible;

  /// 快照请求序号（移动端不摘除场景，暂无实际动作，保留同名接口）
  final int snapshotRequestId;

  /// 场景首帧渲染完成（宿主用它淡出加载期的星球替身）
  final VoidCallback? onReady;

  /// Web 端 iframe 返回的场景快照；移动端 WebView 暂不使用，保留同名接口。
  final ValueChanged<String>? onSnapshot;

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
        onMessageReceived: (msg) {
          // 首帧就绪信号（其余为 FPS 遥测，真机验收时读取）
          if (msg.message.contains('"ready":true')) {
            widget.onReady?.call();
          }
        },
      )
      ..loadRequest(
        Uri.parse(
          'http://127.0.0.1:$port/index.html'
          '?planet=${widget.planet}&spin=${widget.spin}'
          // lod=mid：移动端放大档封顶 4096。8192 单张纹理占显存约 134MB，
          // iPhone Safari/WKWebView 会直接卡死
          '&stage=${widget.stageScale}&lod=mid'
          '&autoPrewarm=${widget.autoPrewarm ? 1 : 0}',
        ),
      );
    if (!mounted) return;
    setState(() => _web = controller);
  }

  @override
  void didUpdateWidget(PlanetScene old) {
    super.didUpdateWidget(old);
    // 创作能量变化 → 转速经桥下发（星球纹理不会变，novel.planet 不可变）
    if (old.planet != widget.planet) {
      _web?.runJavaScript("setPlanet('${widget.planet}')");
    }
    if (old.spin != widget.spin) {
      _web?.runJavaScript('setSpin(${widget.spin})');
    }
    // 捏合缩放 → 镜头推进（场景侧自带阻尼平滑）
    if (old.zoom != widget.zoom) {
      _web?.runJavaScript('setZoom(${widget.zoom})');
    }
    // 拖动 → 转星球（场景侧同样带阻尼）
    if (old.yaw != widget.yaw || old.pitch != widget.pitch) {
      _web?.runJavaScript('setRotation(${widget.yaw}, ${widget.pitch})');
    }
    if (old.autoPrewarm != widget.autoPrewarm) {
      _web?.runJavaScript('setAutoPrewarm(${widget.autoPrewarm})');
    }
    // 非当前页 或 被大纲页覆盖 → 暂停渲染（多球常驻越用越卡 / 覆盖时省电）
    final was = old.active && old.visible;
    final now = widget.active && widget.visible;
    if (was != now) {
      _web?.runJavaScript(now ? 'resumeRender()' : 'pauseRender()');
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
