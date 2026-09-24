import 'dart:async';

import 'package:flutter/foundation.dart';

/// 计时/停表核心模型，双端共享。
///
/// 采用 “累计基准 _base + 本次运行时长” 的模型：暂停时把当前运行段折入
/// _base，续跑时新建一个 [Stopwatch]（内部自然从 0 起算），从而避免
/// 暂停/续跑后重复累计的问题。
class StopwatchModel extends ChangeNotifier {
  /// 已暂停部分与历史运行段累计的基准。
  Duration _base = Duration.zero;

  /// 当前运行段的计时器（未运行时为 null）。
  Stopwatch? _stopwatch;

  /// 驱动 UI 刷新（刷新间隔 10ms，避免每帧重建）。
  Timer? _ticker;

  /// 每次打点（计次）记录的累计时间。
  final List<Duration> _laps = <Duration>[];

  bool get isRunning => _stopwatch?.isRunning ?? false;

  /// 是否处于暂停状态（true=暂停/未开始，false=运行中）。
  bool get isPaused => !isRunning;

  /// 当前总时间（本地累积基准 + 本次进行中的时长）。
  Duration get elapsed {
    final sw = _stopwatch;
    if (sw == null || !sw.isRunning) return _base;
    return _base + sw.elapsed;
  }

  /// 自上次打点以来的本次时间增量（最后一个打点之后累计的部分）。
  Duration get lapDelta => _laps.isEmpty ? elapsed : elapsed - _laps.last;

  /// 打点记录（累计时间，按顺序），只读。
  List<Duration> get laps => List<Duration>.unmodifiable(_laps);

  /// 开始（从暂停处/未开始处启动一个全新的运行段）。
  void start() {
    if (isRunning) return;
    _stopwatch = Stopwatch()..start();
    _startTicker();
    notifyListeners();
  }

  /// 暂停：把进行中的运行段折入累计基准，再停止计时。
  void pause() {
    final sw = _stopwatch;
    if (sw == null || !sw.isRunning) return;
    _base += sw.elapsed;
    sw.stop();
    _stopTicker();
    notifyListeners();
  }

  /// 开始/暂停切换。
  void toggle() {
    if (isRunning) {
      pause();
    } else {
      start();
    }
  }

  /// 重置所有状态（停止计时、清空打点、回到未开始）。
  void reset() {
    _stopwatch?.stop();
    _stopwatch = null;
    _base = Duration.zero;
    _laps.clear();
    _stopTicker();
    notifyListeners();
  }

  /// 打点（计次加一）：记录当前累计时间。仅在真正运行中生效（暂停时不计次）。
  void lap() {
    if (!isRunning) return;
    _laps.add(elapsed);
    notifyListeners();
  }

  // ---------- 计时刷新 ----------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 10), (_) {
      notifyListeners();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopTicker();
    super.dispose();
  }
}