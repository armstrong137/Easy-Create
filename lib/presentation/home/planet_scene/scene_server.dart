import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 3D 场景回环资产服务（阶段八 P2-1）
///
/// WebGL 纹理不能从 file:// 加载（同源策略拦截 texImage2D，P1 验证报告 1.3），
/// 由 127.0.0.1 回环 HTTP 服务从 rootBundle 供资产：完全离线、不占权限、
/// 仅监听本机回环不暴露端口。全 App 单例，多个星球页共用一个服务。
class SceneServer {
  HttpServer? _server;

  /// 白名单前缀 → rootBundle 资产根（防目录穿越，只暴露场景所需资产）
  static const _routes = {
    '/app-textures/': 'assets/textures/', // 五颗星球 albedo（复用主 App 既有纹理）
    '/': 'assets/planet_scene/', // 场景页、three.js、地球多层纹理
  };

  /// 启动（幂等），返回端口号
  Future<int> ensureStarted() async {
    final running = _server;
    if (running != null) return running.port;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path == '/' ? '/index.html' : req.uri.path;
    String? assetKey;
    for (final entry in _routes.entries) {
      if (path.startsWith(entry.key)) {
        assetKey = entry.value + path.substring(entry.key.length);
        break;
      }
    }
    if (assetKey == null || assetKey.contains('..')) {
      req.response.statusCode = HttpStatus.notFound;
    } else {
      try {
        final data = await rootBundle.load(assetKey);
        req.response.headers.contentType = _mime(path);
        req.response.add(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } catch (_) {
        req.response.statusCode = HttpStatus.notFound;
      }
    }
    await req.response.close();
  }

  ContentType _mime(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js')) {
      return ContentType('application', 'javascript', charset: 'utf-8');
    }
    if (path.endsWith('.png')) return ContentType('image', 'png');
    return ContentType('image', 'jpeg');
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
  }
}

/// 全局单例（keepAlive：服务与 App 同生命周期）
final sceneServerProvider = Provider<SceneServer>((ref) {
  final server = SceneServer();
  ref.onDispose(server.dispose);
  return server;
});
