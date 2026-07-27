import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/foundation.dart';
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
    this.prewarmPlanets = const [],
    this.active = true,
    this.visible = true,
    this.fullDetail = false,
    this.snapshotRequestId = 0,
    this.onReady,
    this.onSnapshot,
    this.onLost,
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

  /// 相邻星球贴图只预取到 HTTP 缓存层（场景侧不解码、不上传 GPU）：
  /// 可见场景零后台重活，切球事务时再真正解码/分块上传。
  final List<String> prewarmPlanets;

  /// 是否为当前可见页：非当前页暂停场景渲染——滑过的页被 keepAlive 后
  /// iframe 仍在后台 rAF 渲染，多球常驻会越用越卡（用户实测）
  final bool active;

  /// 首页路由是否在最顶（未被大纲页覆盖）。为 false 时把 iframe DOM
  /// `display:none` 并暂停渲染——**不销毁**：返回时直接恢复，scene 与
  /// 底图都还在，无重建、无 1 秒加载、无替身黑帧（对齐移动端不销毁的行为）。
  /// display:none 让平台视图退出合成，规避"驻留非当前路由 → 丢 canvas → 大纲白屏"。
  final bool visible;

  /// 本次换星球是否整包前台一次上传（新建星球用）：为真时场景走 immediate，
  /// 接管即全清、不走"底图先出 → 细节后补"两相（新建无滑页动画，可整包前台）。
  /// 滑页切换恒为 false，保持两相以保护滑动帧。
  final bool fullDetail;

  /// 快照请求序号：+1 即让场景回传一张最新快照（进大纲前调用，
  /// 供返回时替身用；不做周期快照——PNG 编码在主线程是固定 jank 源）
  final int snapshotRequestId;

  /// 场景就绪/换星球接管完成，回传**已接管的星球名**：宿主据此只在场景真正
  /// 换到当前页星球时才淡出替身（快速新建时串行换球会滞后，不能见 ready 就揭幕）。
  final ValueChanged<String>? onReady;

  /// 场景低清透明快照（宿主返回首页/重建 iframe 时用来兜底，避免露出空白）。
  final ValueChanged<String>? onSnapshot;

  /// 场景画面冻结、正在自动重建（宿主据此复位就绪、让替身盖住重建窗口）。
  final VoidCallback? onLost;

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
  late final String _viewType = '共享星球场景_$_seq';
  web.HTMLIFrameElement? _iframe;

  /// 最近一次收到场景心跳/就绪的时刻。心跳只在场景**真正渲染出帧后**才发，
  /// 因此心跳断流即等于画面冻结（丢 WebGL 上下文、渲染循环抛错等）。
  DateTime _lastAlive = DateTime.now();
  Timer? _watchdog;

  /// 自动重建次数上限：连续修不好就别无限重载（避免反复闪烁）
  int _recoverCount = 0;
  static const _maxRecover = 3;

  /// 场景就绪监听（token 匹配本实例，多颗星球互不串扰）
  late final JSFunction _onMessage = ((web.MessageEvent e) {
    final data = e.data;
    if (!data.isA<JSString>()) return;
    final text = (data as JSString).toDart;
    // 心跳：只更新存活时刻，不做别的
    if (text.startsWith('sceneAlive:$_seq:')) {
      _lastAlive = DateTime.now();
      _recoverCount = 0; // 恢复正常出帧，重置重建配额
      return;
    }
    // 场景自报丢了 WebGL 上下文：立即重建（旧实现无人处理，永久停在最后一帧）
    if (text == 'sceneContextLost:$_seq') {
      _recoverScene('WebGL 上下文丢失');
      return;
    }
    // 首帧就绪 / 切星球原地换贴图接管完成——形如 sceneReady:$seq:planet、
    // planetReady:$seq:planet，尾段是已接管的星球名，回传给宿主判断是否揭幕。
    final readyPrefixes = ['sceneReady:$_seq:', 'planetReady:$_seq:'];
    for (final prefix in readyPrefixes) {
      if (text.startsWith(prefix)) {
        widget.onReady?.call(text.substring(prefix.length));
        return;
      }
    }
    final snapshotPrefix = 'sceneSnapshot:$_seq:';
    if (text.startsWith(snapshotPrefix)) {
      widget.onSnapshot?.call(text.substring(snapshotPrefix.length));
    }
  }).toJS;

  /// 按**当前**属性拼场景 URL：重建时要沿用现在这颗星球，不能回到初始那颗
  String _sceneSrc() =>
      'assets/assets/planet_scene/index.html'
      '?planet=${widget.planet}&spin=${widget.spin}'
      '&stage=${widget.stageScale}'
      '&prewarm=${Uri.encodeComponent(widget.prewarmPlanets.join(','))}'
      '&token=$_seq';

  @override
  void initState() {
    super.initState();
    web.window.addEventListener('message', _onMessage);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      final iframe = web.HTMLIFrameElement()
        ..src = _sceneSrc()
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.backgroundColor = 'transparent'
        ..style.pointerEvents = 'none'
        // 若创建时首页已被覆盖（罕见），初始即隐藏
        ..style.display = widget.visible ? '' : 'none';
      _iframe = iframe;
      return iframe;
    });
    // 看门狗：只在"本该出帧"时判活。心跳每秒一次，6 秒无心跳即判定画面冻结
    // （iPhone 实测会卡死不动：丢 WebGL 上下文后旧实现永远停在最后一帧）。
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      // 页面在后台（锁屏/切走 App）时浏览器会停掉 rAF，心跳本就该断——
      // 这不是冻结，绝不能误判重建，否则每次切回来都白闪一次。
      if (!_shouldRender || web.document.hidden) {
        _lastAlive = DateTime.now();
        return;
      }
      if (DateTime.now().difference(_lastAlive) > const Duration(seconds: 6)) {
        _recoverScene('连续 6 秒无渲染心跳');
      }
    });
  }

  /// 画面冻结自愈：重载 iframe 拿一个全新的 WebGL 上下文（沿用当前星球）。
  /// 重建期通知宿主复位就绪，让替身盖住，不给用户看空白。
  void _recoverScene(String reason) {
    final frame = _iframe;
    if (frame == null || !mounted) return;
    if (_recoverCount >= _maxRecover) return; // 修不好就不再无限重载
    _recoverCount++;
    _lastAlive = DateTime.now(); // 给重建留出时间，别立刻二次触发
    debugPrint('星球场景自愈重建（$reason，第 $_recoverCount 次）');
    widget.onLost?.call();
    // 加时间戳绕开缓存，确保拿到全新文档与上下文
    frame.src = '${_sceneSrc()}&r=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 有效渲染 = 当前页 且 首页在顶。任一为假即暂停 rAF（省 GPU、不抢主线程）
  bool get _shouldRender => widget.active && widget.visible;

  @override
  void dispose() {
    _watchdog?.cancel();
    _post({'dispose': 1});
    _iframe?.src = 'about:blank';
    _iframe?.remove();
    _iframe = null;
    web.window.removeEventListener('message', _onMessage);
    super.dispose();
  }

  @override
  void didUpdateWidget(PlanetScene old) {
    super.didUpdateWidget(old);
    // iframe 同源，postMessage 直达场景（其 message 监听调 setPlanet/setZoom/…）
    if (old.planet != widget.planet) {
      // 切星球：**合并**下发 planet + 当前视角，让场景原地换贴图时直接沿用
      // 当前 yaw/pitch/zoom/spin，避免新星球先按默认角度亮一帧再收角度"跳一下"。
      _post({
        'planet': widget.planet,
        'yaw': widget.yaw,
        'pitch': widget.pitch,
        'zoom': widget.zoom,
        'spin': widget.spin,
        // 画布尺寸固定，取景差异随星球一起下发（土星 3、其余 4.2）
        'stage': widget.stageScale,
        // 新建星球：整包前台一次上传，接管即全清（场景侧 setPlanet 读 state.immediate）
        'immediate': widget.fullDetail,
      });
    } else {
      if (old.stageScale != widget.stageScale) {
        _post({'stage': widget.stageScale});
      }
      if (old.zoom != widget.zoom) {
        _post({'zoom': widget.zoom});
      }
      if (old.yaw != widget.yaw || old.pitch != widget.pitch) {
        _post({'yaw': widget.yaw, 'pitch': widget.pitch});
      }
    }
    if (!listEquals(old.prewarmPlanets, widget.prewarmPlanets)) {
      _post({'prewarmPlanets': widget.prewarmPlanets});
    }
    // 进/出大纲：切 iframe 显隐（display:none 让平台视图退出合成，规避大纲白屏）
    if (old.visible != widget.visible) {
      _iframe?.style.display = widget.visible ? '' : 'none';
    }
    // 渲染开关随 active/visible 任一变化更新（暂停时不烧 GPU/不抢主线程）
    final was = old.active && old.visible;
    if (was != _shouldRender) {
      _post({'render': _shouldRender ? 1 : 0});
    }
    if (old.snapshotRequestId != widget.snapshotRequestId) {
      _post({'snapshot': 1});
    }
  }

  void _post(Map<String, Object?> msg) =>
      _iframe?.contentWindow?.postMessage(msg.jsify(), '*'.toJS);

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.diameter,
      // IgnorePointer 必不可少：platform view 会在 Flutter 手势竞技场里
      // 赢走所有手势——iframe 的 pointer-events:none 只管 DOM 层，
      // 不包这层则"点星球进大纲"在 web 上永远不触发（真实回归，
      // 已用 CDP 探针实证：书名可点、星球区域不可点）
      child: IgnorePointer(child: HtmlElementView(viewType: _viewType)),
    );
  }
}
