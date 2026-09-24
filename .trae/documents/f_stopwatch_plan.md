# f-stopwatch 跨端计时/停表应用实施计划

## Context（背景）
用户需要在空目录 `d:\BDG\github\f-stopwatch` 从零开发一个 **安卓 + Windows 双端** 的计时/停表应用：

- **通用能力**：计时（累计总时间）、停表（开始/暂停）、计次（打点/加一，记录每次的时间点和总时间）。
- **Windows 端**：主窗口 + 全局热键。支持自定义按键分别触发 **暂停/开始** 和 **计次加一**；界面显示总时间，并列出自每次计时的时间（本次与累计）。
- **安卓端**：不需要自定义按键，但需要**悬浮窗**。悬浮窗显示总时间，下方有 **暂停/开始** 和 **计次加一** 两个按钮。

### 已确认的决策
1. **框架**：Flutter（Dart 单代码库，编译为原生，性能好，Windows + Android 官方支持）。
2. **构建**：只写代码，用户在装有 Flutter / Android SDK / JDK 11+ / VS(C++) 的机器上自行构建。本机不安装工具链（本机仅有 JDK 1.8、Node、dotnet，无 Flutter、无 Android SDK、无 VS）。
3. **Windows 形态**：主窗口 + 全局热键（非悬浮小窗）。

### 关键技术选型验证
- **全局热键**：`hotkey_manager`（leanflutter，pub: `hotkey_manager`），`hotkeyManager.register(HotKey(key:..., modifiers:..., scope: HotKeyScope.system), keyDownHandler:)`，支持 Windows 系统级热键且自带原生实现——**不需要手写 C++ runner**，标准 `flutter create` 脚手架即可。
- **安卓悬浮窗**：原生实现（Kotlin + `WindowManager` + `TYPE_APPLICATION_OVERLAY` + `SYSTEM_ALERT_WINDOW` 权限），通过双向 MethodChannel 与 Dart 引擎通信；用 **前台服务(ForegroundService)** 保证进程常驻并显示持久通知。
- **计时代码全在 Dart 侧**（纯 `Stopwatch` + `List<Duration>` 打点），双端共享，性能与逻辑一致。

## 架构与文件结构

### 共享核心（lib/，双端复用）
- `lib/stopwatch_model.dart` — `StopwatchModel extends ChangeNotifier`：`isRunning`、`elapsed`、`lapList`（每次打点的 `Duration`），方法 `toggle()`、`lap()`、`reset()`。计时用 `Stopwatch`，进度用 `Timer.periodic` 驱动刷新（刷新间隔 10ms，避免每秒高强度的 UI 重建）。
- `lib/format.dart` — `formatDuration(Duration)`：输出 `MM:SS.cc`；打点记录同时给出**本次增量**和**累计时间**两个字符串。
- `lib/overlay_bridge.dart` — 安卓 MethodChannel 封装：
  - Dart→Native：`updateTotal(String)`、`startForeground()`、`stopForeground()`。
  - Native→Dart：`onButtonPressed`（`"toggle"` | `"lap"`）事件流（`EventChannel`）。
- `lib/hotkeys.dart` — Windows 全局热键封装：注册/注销；提供默认键位 + 可配置键位（用 `shared_preferences` 持久化）。热键回调只转发到 `StopwatchModel`。

### Windows（lib/src/windows/ + pubspec 依赖）
- `lib/src/windows/windows_app.dart` — 主界面 `WindowsStopwatchScreen`：
  - 大号总时间显示；
  - 按钮区：**开始/暂停**、**计次加一**、**重置**；
  - 打点列表：每条显示“本次 vs 累计”；
  - `KeyboardListener` 处理应用内按键（焦点态同样可操作）；
  - `hotkey_manager` 注册**系统级**热键（应用不在前台也可触发）：默认 `F2`=暂停/开始，`F3`=计次加一，可在界面设置页自定义并持久化。
- 依赖：`hotkey_manager`、`shared_preferences`。

### Android（lib/src/android/ + android/ 平台代码）
- `lib/src/android/android_app.dart` — 安卓主界面（简洁）：
  - 请求 `SYSTEM_ALERT_WINDOW` 悬浮窗权限（`Settings.canDrawOverlays` → `ACTION_MANAGE_OVERLAY_PERMISSION`）；
  - 权限授予后“启动悬浮窗”按钮 → 启动 FrontgroundService。
- 悬浮窗内容（原生 View，轻量高性能）：`TextView` 显示总时间 + 两个 `Button`（暂停/开始、计次+1）。
- `android/app/src/main/.../MainActivity.kt` — `FlutterActivity`，`configureFlutterEngine` 里注册并暴露 MethodChannel（静态单例供 Service 使用）。
- `android/app/src/main/.../OverlayService.kt` — 前台服务 + WindowManager 添加 `TYPE_APPLICATION_OVERLAY` 悬浮窗；接收 `updateTotal` 更新文本；按钮点击通过 channel 发回 Dart 触发 toggle/lap。
- `android/app/src/main/AndroidManifest.xml` 追加（权限与 Service 声明）：
  - `SYSTEM_ALERT_WINDOW`、`FOREGROUND_SERVICE`、`POST_NOTIFICATIONS`(Android 13+)；
  - `<service android:name=".OverlayService" android:foregroundServiceType="specialUse"...>` 及通知渠道代码。
- `android/app/build.gradle` 校验 `minSdk >= 23`（悬浮窗要求放宽）。

## 实施步骤
1. 写 `pubspec.yaml`（flutter / flutter_lints / hotkey_manager / shared_preferences；环境、SDK 约束）。
2. 写共享核心：`lib/stopwatch_model.dart`、`lib/format.dart`。
3. 写 Windows 端：`lib/hotkeys.dart` + `lib/src/windows/windows_app.dart` + 主入口。
4. 写 Android 端：`lib/overlay_bridge.dart` + `lib/src/android/android_app.dart` + `MainActivity.kt` + `OverlayService.kt` + AndroidManifest 追加。
5. 写 `README.md`：
   - 构建前置：安装 Flutter + VS(C++ 桌面负载，Windows) + Android Studio/SDK + JDK11+。
   - 生成脚手架：在空目录执行 `flutter create --platforms=windows,android --project-name f_stopwatch .`（生成 `windows/`、`android/` 标准模板），再 `flutter pub get`。
   - 运行：`flutter run -d windows`；安卓 `flutter run -d <device>`。
   - 安卓悬浮窗使用说明（授权悬浮窗权限 → 应用内启动悬浮窗）。
6. 需用户配合的一处：因本机无 Flutter SDK，无法在此运行 `flutter create` 生成 `windows/` 平台脚手架与 build；`lib/` 代码与安卓平台源码由本计划生成，`windows/`/`android/` 标准脚手架需用户用其 Flutter 版本执行一次 `flutter create`（会保留我的 `lib/` 与自定义安卓文件，手动 merge 自定义 `MainActivity.kt`/`OverlayService.kt`/Manifest）。

## 验证
- **静态**：本机无可执行环境，用 `dart analyze`（如有 Dart）或人工 review 保证语法/类型正确；用户侧 `flutter analyze`、`flutter test`。
- **Windows**：`flutter run -d windows` 后可：点按钮/按 F2 开始暂停、F3 计次、看累计与每次时间、应用失焦后热键仍生效、重置。
- **Android**：`flutter run -d <设备>` → 授权悬浮窗 → 启动悬浮窗 → 悬浮窗显示总时间，点暂停/开始、计次+1，主界面打点列表同步；切走应用悬浮窗与定时持续运行。