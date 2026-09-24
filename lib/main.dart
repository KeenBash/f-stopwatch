import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/android/android_app.dart';
import 'src/web/web_app.dart';
import 'src/windows/windows_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 按平台分发：Web（先判断 kIsWeb）→ 调试端；Android → 悬浮窗；其余(Windows) → 主窗口+热键。
  final Widget app;
  if (kIsWeb) {
    app = const WebStopwatchApp();
  } else if (defaultTargetPlatform == TargetPlatform.android) {
    app = const AndroidStopwatchApp();
  } else {
    app = const WindowsStopwatchApp();
  }

  runApp(app);
}