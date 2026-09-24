import 'package:flutter/services.dart';

/// 与安卓原生悬浮窗通信的两端。
class OverlayBridge {
  OverlayBridge._();

  static const MethodChannel _method = MethodChannel('com.f_stopwatch/overlay');
  static const EventChannel _events =
      EventChannel('com.f_stopwatch/overlay/buttons');

  /// Dart → Native：启动前台悬浮窗服务。
  static Future<bool> startForeground() async =>
      await _method.invokeMethod<bool>('startForeground') ?? false;

  /// Dart → Native：停止前台悬浮窗服务。
  static Future<void> stopForeground() async =>
      await _method.invokeMethod<void>('stopForeground');

  /// Dart → Native：更新悬浮窗内总时间文本。
  static Future<void> updateTotal(String text) async {
    try {
      await _method.invokeMethod<void>('updateTotal', text);
    } catch (_) {/* 悬浮窗未启动时忽略 */}
  }

  /// Dart → Native：更新辅助小字行（本次计时/第N次），空串隐藏。
  static Future<void> updateSecondary(String text) async {
    try {
      await _method.invokeMethod<void>('updateSecondary', text);
    } catch (_) {/* 忽略 */}
  }

  /// Dart → Native：同步暂停/运行状态，用于刷新悬浮窗按钮图标。
  static Future<void> updateRunning({required bool paused}) async {
    try {
      await _method.invokeMethod<void>('updateRunning', paused);
    } catch (_) {/* 忽略 */}
  }

  /// Dart → Native：下发悬浮窗配置（字体颜色 ARGB、大小缩放、背景透明度 0-255）。
  static Future<void> updateConfig({
    required int fontColor,
    required double sizeScale,
    required int bgAlpha,
  }) async {
    try {
      await _method.invokeMethod<void>('updateConfig', <String, Object>{
        'fontColor': fontColor,
        'sizeScale': sizeScale,
        'bgAlpha': bgAlpha,
      });
    } catch (_) {/* 忽略 */}
  }

  /// Dart → Native：查询是否已授予悬浮窗权限。
  static Future<bool> hasOverlayPermission() async =>
      await _method.invokeMethod<bool>('hasOverlayPermission') ?? false;

  /// Dart → Native：跳转到系统悬浮窗授权页。
  static Future<void> requestOverlayPermission() async =>
      await _method.invokeMethod<void>('requestOverlayPermission');

  /// Dart → Native：将悬浮窗恢复到默认位置（状态栏下方）。
  static Future<void> resetPosition() async {
    try {
      await _method.invokeMethod<void>('resetPosition');
    } catch (_) {/* 忽略 */}
  }

  /// Dart → Native：推送悬浮窗计次列表内容（空列表则清空，供原生列表浮窗使用）。
  static Future<void> updateLaps(List<String> lines) async {
    try {
      await _method.invokeMethod<void>('updateLaps', lines);
    } catch (_) {/* 忽略 */}
  }

  /// Dart → Native：查询原生悬浮窗当前是否真实在运行。
  static Future<bool> isOverlayActive() async =>
      await _method.invokeMethod<bool>('isOverlayActive') ?? false;

  /// Native → Dart：悬浮窗按钮点击事件（"toggle" | "lap"）。
  static Stream<String> onButtonPressed() =>
      _events.receiveBroadcastStream().map((e) => e.toString());
}