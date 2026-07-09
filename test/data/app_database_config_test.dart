import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web 数据库显式配置 sqlite3.wasm 与 drift_worker.js', () {
    final source = File(
      'lib/data/database/app_database.dart',
    ).readAsStringSync();

    expect(
      source,
      contains('DriftWebOptions'),
      reason: 'drift_flutter 在 Web 端必须显式传入 web 配置，否则数据库无法打开',
    );
    expect(source, contains("Uri.parse('sqlite3.wasm')"));
    expect(source, contains("Uri.parse('drift_worker.js')"));
    expect(File('web/sqlite3.wasm').existsSync(), isTrue);
    expect(File('web/drift_worker.js').existsSync(), isTrue);
  });
}
