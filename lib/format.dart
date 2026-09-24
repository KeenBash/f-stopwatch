/// 将 [Duration] 格式化为 `MM:SS.cc`。
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final cs = d.inMilliseconds ~/ 10 % 100;
  if (h > 0) {
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}.'
        '${cs.toString().padLeft(2, '0')}';
  }
  return '${m.toString().padLeft(2, '0')}:'
      '${s.toString().padLeft(2, '0')}.'
      '${cs.toString().padLeft(2, '0')}';
}

/// 两个 [Duration] 之差。
Duration durationDiff(Duration a, Duration b) => a - b;