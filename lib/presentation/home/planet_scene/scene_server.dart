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
  static const routes = {
    '/planet/': 'assets/planet_scene/',
    '/tree/': 'assets/tree_scene/',
    '/tree-model/': 'assets/3d/magic_tree/',
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
    final path = req.uri.path;
    String? assetKey;
    if (path.contains('..') || path.contains(r'\')) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    for (final entry in routes.entries) {
      if (path.startsWith(entry.key)) {
        assetKey = entry.value + path.substring(entry.key.length);
        break;
      }
    }
    if (assetKey == null || assetKey.endsWith('/')) {
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
    if (path.endsWith('.webp')) return ContentType('image', 'webp');
    if (path.endsWith('.ktx2')) return ContentType('image', 'ktx2');
    if (path.endsWith('.wasm')) return ContentType('application', 'wasm');
    if (path.endsWith('.json') || path.endsWith('.gltf')) {
      return ContentType('application', 'json', charset: 'utf-8');
    }
    if (path.endsWith('.glb') || path.endsWith('.bin')) {
      return ContentType('application', 'octet-stream');
    }
    if (path.endsWith('.css')) {
      return ContentType('text', 'css', charset: 'utf-8');
    }
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
