import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_keys.dart';
import 'core/startup_focus_binding.dart';
import 'presentation/home/home_page.dart';
import 'presentation/outline/magic_carpet.dart' show CarpetOverlay;
import 'presentation/shared/quick_capture/capture_button_prefs.dart';
import 'presentation/shared/quick_capture/quick_capture_layer.dart';

Future<void> main() async {
  if (kIsWeb) {
    StartupWidgetsBinding();
  } else {
    WidgetsFlutterBinding.ensureInitialized();
  }
  // 预载偏好存储（按钮位置等），以同步 Provider 形式注入
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const NovelApp(),
    ),
  );
}

/// App 根组件：全局速记层覆盖在所有页面之上
class NovelApp extends ConsumerStatefulWidget {
  const NovelApp({super.key});

  @override
  ConsumerState<NovelApp> createState() => _NovelAppState();
}

class _NovelAppState extends ConsumerState<NovelApp> {
  /// 弹出层感知：对话框/菜单弹出时速记按钮自动让位
  late final ModalAwareObserver _modalObserver = ModalAwareObserver(ref);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Create Something',
      navigatorKey: rootNavigatorKey,
      navigatorObservers: [_modalObserver],
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      theme: ThemeData(
        // 黑白素净基调（铅笔树风格），后续 core/ 主题细化
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black),
        useMaterial3: true,
        // 全局默认字体＝霞鹜文楷：所有未显式指定 fontFamily 的中文文本
        // 都走楷体（Text 的 style 会合并到主题 DefaultTextStyle 上）。
        // 品牌标题等显式写 EasyCreateBrand 的照常覆盖。
        fontFamily: 'LXGWWenKai',
      ),
      // 用 builder 把全局魔毯与速记双按钮叠在 Navigator 之上
      // → 任何界面可速记、随时打开灵感魔毯
      builder: (context, child) =>
          QuickCaptureLayer(child: CarpetOverlay(child: child!)),
      home: const HomePage(),
    );
  }
}
