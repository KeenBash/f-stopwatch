/// 计时会话数据：进行中快照与历史记录共用的统一数据格式。
///
/// 统一 JSON 字段（持久化/归档都用这一套）：
/// - `t`：累计运行时长（毫秒）
/// - `l`：每次计次的累计时长（毫秒数组）
/// - `s`：会话开始时间（时间戳，可为空）
class TimerData {
  const TimerData({
    required this.elapsed,
    required this.laps,
    this.startedAt,
  });

  final Duration elapsed;

  /// 各次计次的累计时长（与打点顺序一致）。
  final List<Duration> laps;

  /// 会话开始时间（墙上时间）。
  final DateTime? startedAt;

  int get lapCount => laps.length;

  /// 第 [index] 次计次的单次时长。
  Duration lapAt(int index) =>
      index == 0 ? laps[index] : laps[index] - laps[index - 1];

  Map<String, Object?> toJson() => <String, Object?>{
        't': elapsed.inMilliseconds,
        'l': laps.map((d) => d.inMilliseconds).toList(),
        's': startedAt?.millisecondsSinceEpoch,
      };

  factory TimerData.fromJson(Map<String, dynamic> m) => TimerData(
        elapsed: Duration(milliseconds: (m['t'] as num).toInt()),
        laps: (m['l'] as List<dynamic>? ?? const <dynamic>[])
            .map((v) => Duration(milliseconds: (v as num).toInt()))
            .toList(),
        startedAt: m['s'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((m['s'] as num).toInt()),
      );
}

/// 运行中的计时快照：在 [TimerData] 基础上增加保存时刻与是否运行，
/// 用于进程被系统回收后恢复计时。
class TimerSnapshot {
  const TimerSnapshot({
    required this.data,
    required this.savedAt,
    required this.running,
  });

  final TimerData data;
  final DateTime savedAt;
  final bool running;

  Map<String, Object?> toJson() => <String, Object?>{
        ...data.toJson(),
        'r': running,
        'a': savedAt.millisecondsSinceEpoch,
      };

  factory TimerSnapshot.fromJson(Map<String, dynamic> m) => TimerSnapshot(
        data: TimerData.fromJson(m),
        savedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['a'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
        running: m['r'] == true,
      );

  /// 若保存时为运行中，则补上被回收期间流逝的时间。
  TimerData resumedData(DateTime now) {
    if (!running) return data;
    final gap = now.difference(savedAt);
    if (gap <= Duration.zero) return data;
    return TimerData(
      elapsed: data.elapsed + gap,
      laps: data.laps,
      startedAt: data.startedAt,
    );
  }
}
