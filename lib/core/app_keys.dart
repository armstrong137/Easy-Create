import 'package:flutter/material.dart';

/// 根 Navigator key：速记层位于 Navigator 之上（MaterialApp.builder 注入），
/// 弹出输入层 / SnackBar 时须通过这里拿到 Navigator 下的 context
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// 根 ScaffoldMessenger key：供速记层在任意页面弹 SnackBar
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
