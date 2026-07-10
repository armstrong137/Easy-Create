// 局域网静态服务：手机浏览器体验 Flutter Web 版 App
//
// 由 scripts/serve_web.ps1 拉起，不要直接跑（端口/防火墙/构建都在 ps1 里处理）。
// 绑 0.0.0.0 而非 127.0.0.1——只听环回地址手机就永远连不上。
import 'dart:io';

/// MIME 表：.wasm 必须精确（drift 的 sqlite3.wasm 走 MIME 校验，
/// 报错的话网页版数据库直接不可用——新建星球会"诞生不了"）
const _mimes = {
  'html': 'text/html; charset=utf-8',
  'js': 'application/javascript',
  'mjs': 'application/javascript',
  'wasm': 'application/wasm',
  'json': 'application/json',
  'css': 'text/css',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'ico': 'image/x-icon',
  'svg': 'image/svg+xml',
  'otf': 'font/otf',
  'ttf': 'font/ttf',
  'woff2': 'font/woff2',
  'frag': 'text/plain',
  'bin': 'application/octet-stream',
};

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.parse(args[0]) : 8788;
  final root = Directory('build/web').absolute;
  if (!root.existsSync()) {
    stderr.writeln('未找到 ${root.path}，请先 flutter build web');
    exit(1);
  }

  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('serving ${root.path} on 0.0.0.0:$port');

  await for (final req in server) {
    final path = req.uri.path == '/' ? '/index.html' : req.uri.path;
    // 防目录穿越：解析后必须仍在 root 之内
    final file = File('${root.path}/$path'.replaceAll('//', '/'));
    final inRoot = file.absolute.path.startsWith(root.path);

    if (!inRoot || !file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
    } else {
      final ext = path.split('.').last.toLowerCase();
      req.response.headers.set(
        'Content-Type',
        _mimes[ext] ?? 'application/octet-stream',
      );
      // 改完代码重开页面就要拿到新构建，别让浏览器缓存旧的
      req.response.headers.set('Cache-Control', 'no-store');
      await req.response.addStream(file.openRead());
    }
    await req.response.close();
  }
}
