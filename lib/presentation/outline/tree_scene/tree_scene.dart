import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'tree_scene_io.dart' if (dart.library.js_interop) 'tree_scene_web.dart';

final realtimeTree3DProvider = Provider<bool>(
  (_) => kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST'),
);
