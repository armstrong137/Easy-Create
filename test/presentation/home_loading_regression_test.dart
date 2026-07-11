import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final homePage = File(
    'lib/presentation/home/home_page.dart',
  ).readAsStringSync();

  test('outline route waits for snapshot and stand-in is not black', () {
    expect(homePage, contains('_openOutline'));
    expect(homePage, contains('_awaitSnapshotBeforeRoute'));
    expect(homePage, contains('_snapshotCompleter'));
    expect(homePage, contains('Duration(milliseconds: 90)'));
    expect(homePage, contains('planet: novel.planet'));
    expect(homePage, isNot(contains('Color(0xFF0E1B33)')));
  });

  test('brand title style is shared by boot cover and create title', () {
    expect(homePage, contains('_brandTitleStyle'));
    expect(homePage, contains('_brandTitleStyle(fontSize: 34'));
    expect(homePage, contains('_brandTitleStyle(fontSize: 26'));
  });

  test('create title visibility follows min zoom instead of page lock', () {
    expect(homePage, contains('planetCreateTitleVisible'));
    expect(homePage, contains('_syncCreateTitleVisibility'));
    expect(homePage, contains('planetCreateTitleVisible.value = _zoom <='));
    expect(homePage, contains('valueListenable: planetCreateTitleVisible'));
  });
}
