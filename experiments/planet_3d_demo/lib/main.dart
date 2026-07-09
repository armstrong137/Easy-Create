import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';

/// P1 技术验证 Demo：Flutter 应用壳 + WebView(three.js) 实时 3D 表现层
///
/// 验证目标（对应 docs/ui_review/2026-07-08-UI改造第一版清单.md §3.1）：
/// 1. 真实 3D 地球场景完全离线打包进 App（loadFlutterAsset，无网络）
/// 2. Flutter UI 稳定叠在 3D 场景之上，且可点击（标题/按钮/数据面板）
/// 3. Flutter ⇄ JS 双向通信：按钮驱动镜头推拉；JS 每 0.5s 回报 FPS 与镜头距离
/// 4. WebView 内手势（拖拽旋转/双指缩放/惯性）与 Flutter 手势系统互不干扰
void main() => runApp(const PlanetDemoApp());

class PlanetDemoApp extends StatelessWidget {
  const PlanetDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PlanetDemoPage(),
    );
  }
}

class PlanetDemoPage extends StatefulWidget {
  const PlanetDemoPage({super.key});

  @override
  State<PlanetDemoPage> createState() => _PlanetDemoPageState();
}

class _PlanetDemoPageState extends State<PlanetDemoPage> {
  late final WebViewController _web;
  HttpServer? _server;

  /// JS 上报的实时渲染数据（证明 JS→Flutter 通道活着）
  int _fps = 0;
  String _dist = '-';

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: (msg) {
          final data = jsonDecode(msg.message) as Map<String, dynamic>;
          setState(() {
            _fps = data['fps'] as int;
            _dist = data['dist'] as String;
          });
        },
      );
    _serveAndLoad();
  }

  /// 内置本地静态服务：WebGL 纹理不能走 file://（同源策略拦截 texImage2D），
  /// 由 127.0.0.1 回环服务从 rootBundle 供资产——离线、无权限、无端口暴露
  Future<void> _serveAndLoad() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((req) async {
      final path = req.uri.path == '/' ? '/index.html' : req.uri.path;
      try {
        final data = await rootBundle.load('assets/web$path');
        req.response.headers.contentType = _mime(path);
        req.response.add(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } catch (_) {
        req.response.statusCode = HttpStatus.notFound;
      }
      await req.response.close();
    });
    await _web.loadRequest(
      Uri.parse('http://127.0.0.1:${_server!.port}/index.html'),
    );
  }

  ContentType _mime(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (path.endsWith('.png')) return ContentType('image', 'png');
    return ContentType('image', 'jpeg');
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 3D 场景层（WebView 内 three.js，手势由场景自行处理）
          WebViewWidget(controller: _web),
          // —— 以下全部是 Flutter 叠层，验证浮层合成与命中 ——
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 18),
                // 与正式首页一致的标题样式：证明品牌层可直接叠在 3D 上
                const Text(
                  'Create Something',
                  style: TextStyle(
                    fontSize: 26,
                    color: Colors.white,
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0x66000000),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x55FFFFFF)),
                  ),
                  child: Text(
                    '3D 验证 Demo · Flutter 叠层 · $_fps fps · 镜头 $_dist',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                const Spacer(),
                // 镜头推拉按钮：Flutter → JS 通道驱动 3D 镜头
                Padding(
                  padding: const EdgeInsets.only(bottom: 36),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _zoomButton('拉远', CupertinoIcons.minus, 1.45),
                      const SizedBox(width: 24),
                      _zoomButton('推进', CupertinoIcons.plus, 0.62),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _zoomButton(String label, IconData icon, double factor) {
    return GestureDetector(
      key: Key('镜头$label'),
      onTap: () => _web.runJavaScript('demoZoom($factor)'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x88101826),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0x66AACCFF)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}
