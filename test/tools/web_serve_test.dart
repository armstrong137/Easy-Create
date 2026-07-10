import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 手机能连上网页版体验的前提条件（源码/资产级断言，不发网络请求）
///
/// 这些点每一条都曾真实导致"手机打不开/打开是白屏/数据库不可用"。
void main() {
  final serveDart = File('scripts/serve_web.dart');
  final servePs1 = File('scripts/serve_web.ps1');

  test('服务脚本存在，且绑 0.0.0.0（只听环回地址手机永远连不上）', () {
    expect(serveDart.existsSync(), isTrue);
    expect(servePs1.existsSync(), isTrue);
    final src = serveDart.readAsStringSync();
    expect(src, contains('InternetAddress.anyIPv4'));
    expect(
      src,
      isNot(contains('InternetAddress.loopbackIPv4')),
      reason: '绑环回地址则只有本机能访问',
    );
  });

  test('wasm 的 MIME 精确为 application/wasm（错了则网页版数据库不可用）', () {
    final src = serveDart.readAsStringSync();
    expect(src, contains("'wasm': 'application/wasm'"));
    // 改完代码手机刷新要拿到新构建，不能吃浏览器缓存
    expect(src, contains("'Cache-Control', 'no-store'"));
  });

  test('web/index.html 必须让双指手势落到 Flutter，而不是被浏览器吃掉', () {
    final html = File('web/index.html').readAsStringSync();
    // 缺 viewport meta 时手机浏览器把双指当"页面缩放"，星球捏合永远收不到手势
    expect(html, contains('name="viewport"'));
    expect(html, contains('width=device-width'));
    // iOS Safari 无视 user-scalable=no，必须显式拦截它的双指手势事件
    expect(html, contains('gesturestart'));
    expect(html, contains('e.touches.length > 1'));
    expect(html, contains('touch-action: none'));
  });

  test('ps1 会自测局域网地址并打印当前 IP（IP 随所连 WiFi 变化）', () {
    final src = servePs1.readAsStringSync();
    expect(src, contains('http://\${ip}:\$Port'));
    expect(src, contains('Get-NetIPAddress'));
    expect(src, contains('advfirewall'), reason: '防火墙未放行则手机入站被拦');
  });

  group('drift Web 运行时', () {
    final wasm = File('web/sqlite3.wasm');
    final worker = File('web/drift_worker.js');

    test('运行时文件已就位（缺失则网页版建星球必然失败）', () {
      expect(wasm.existsSync(), isTrue, reason: 'web/sqlite3.wasm 缺失');
      expect(worker.existsSync(), isTrue, reason: 'web/drift_worker.js 缺失');
      expect(wasm.lengthSync(), greaterThan(100 * 1024));
      expect(worker.lengthSync(), greaterThan(10 * 1024));
    });

    test('版本须与 pubspec.lock 锁定的 drift / sqlite3 一致', () {
      // 版本错配时 drift 会在运行时静默降级/抛错，只有真机浏览器能发现，
      // 故在此把「锁文件版本」与「下载运行时的版本」绑在一起
      final lock = File('pubspec.lock').readAsStringSync();

      String versionOf(String pkg) {
        final m = RegExp(
          '^  $pkg:\\n(?:.*\\n)*?    version: "([^"]+)"',
          multiLine: true,
        ).firstMatch(lock);
        expect(m, isNotNull, reason: 'pubspec.lock 未找到 $pkg');
        return m!.group(1)!;
      }

      final versions = File('web/RUNTIME_VERSIONS.txt')
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty && !l.startsWith('#') && l.contains('='))
          .toList();
      final pinned = {
        for (final line in versions)
          line.split('=')[0].trim(): line.split('=')[1].trim(),
      };

      expect(
        pinned['sqlite3'],
        versionOf('sqlite3'),
        reason: 'web/sqlite3.wasm 版本与 pubspec.lock 的 sqlite3 不一致，'
            '请按 web/RUNTIME_VERSIONS.txt 里的下载命令更新',
      );
      expect(
        pinned['drift'],
        versionOf('drift'),
        reason: 'web/drift_worker.js 版本与 pubspec.lock 的 drift 不一致',
      );
    });
  });
}
